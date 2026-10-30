import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  EcfAuditAction,
  EcfDgiiHabilitationState,
  EcfOnboardingStepKey,
  EcfOnboardingStepStatus,
  Prisma,
} from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { ECF_DGII_REQUIREMENT_CATALOG } from "./ecf-dgii-habilitation.policy";
import {
  ECF_ACTIVATION_CLASS,
  ECF_ACTIVATION_STATUS,
  activationBlockers,
  activationClassOf,
  activationSummary,
  buildActivationView,
  initialStepStatus,
  nextExecutableStep,
  resolveCatalogEntry,
  stepStatusFromTransport,
  type ActivationStepInput,
} from "./ecf-dgii-activation.policy";

/** Variable que decide el transporte del motor. Por defecto: simulado. */
export const ECF_ACTIVATION_TRANSPORT_ENV = "ECF_ACTIVATION_TRANSPORT";
/** Escenario del simulador: ok | reject | timeout. */
export const ECF_ACTIVATION_SCENARIO_ENV = "ECF_ACTIVATION_SIMULATION_SCENARIO";

/** Estados desde los que el expediente ya fue presentado alguna vez. */
const SUBMITTED_STATES: ReadonlySet<EcfDgiiHabilitationState> = new Set([
  EcfDgiiHabilitationState.APPLICATION_PENDING,
  EcfDgiiHabilitationState.IN_PROGRESS,
  EcfDgiiHabilitationState.TESTS_PENDING,
  EcfDgiiHabilitationState.IN_CERTIFICATION,
  EcfDgiiHabilitationState.REQUIRES_CORRECTION,
]);

/**
 * Motor de activación e-CF (self-service).
 *
 * Lo que este servicio garantiza, y por qué:
 *
 *  1. **Solo ejecuta lo que puede**: los pasos de `CLIENT_ACTION` y
 *     `AUTHORITY_WAIT` nunca se completan desde aquí. Quedan `BLOCKED` con el
 *     motivo exacto en `blockedReason`.
 *  2. **No salta pasos**: si el siguiente paso no es ejecutable, el motor se
 *     detiene. No se puede llegar a `PRODUCTION_ENABLEMENT` sin certificado.
 *  3. **Simulación ≠ aprobación**: el resultado de un paso de proveedor simulado
 *     se guarda con `resultSummary = 'SIMULATED:<key>'` y jamás escribe
 *     `authorizationSource`, ni `authorizedAt`, ni `APPROVED`.
 *  4. **Idempotente**: repetir `start` no duplica trabajo; cada paso se toma con
 *     un compare-and-set sobre su estado previo.
 *  5. **Auditado**: cada transición deja un `STEP_UPDATED` con antes/después.
 */
@Injectable()
export class EcfDgiiActivationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /** Estado del motor: etapas, clase de cada una y qué falta. */
  async getActivation(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    const view = await this.readView(companyId);
    return this.toResponse(companyId, view);
  }

  /** Arranca (o continúa) la activación. Idempotente. */
  async start(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    this.assertTransportAvailable();

    const [record, appConfig] = await Promise.all([
      this.prisma.ecfDgiiHabilitation.findUnique({ where: { companyId } }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: { rnc: true },
      }),
    ]);

    const applicationSubmitted =
      (record?.currentSnapshotVersion ?? 0) > 0 ||
      (record !== null && SUBMITTED_STATES.has(record.state));

    const blockers = activationBlockers({
      fiscalDataReady: Boolean(appConfig?.rnc?.trim()),
      applicationSubmitted,
    });
    if (blockers.length > 0) {
      throw new BadRequestException({
        message: "ECF_ACTIVATION_BLOCKED",
        blockers,
      });
    }

    await this.runPendingSteps(companyId, user.id);
    const view = await this.readView(companyId);
    return this.toResponse(companyId, view);
  }

  /** Reintenta un paso que falló. No salta el orden. */
  async retryStep(user: TenantUser, key: string) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    this.assertTransportAvailable();

    // El cliente puede devolver `key` (requisito) o `stepKey` (etapa). Para
    // FISCAL_DATA/FISCAL_CONFIG no son iguales, así que se resuelve al canónico
    // antes de tocar la base: escribir el requisito como etapa no existe en el
    // enum y el reintento se perdía en silencio.
    const entry = resolveCatalogEntry(key);
    if (!entry) {
      throw new NotFoundException("ECF_ACTIVATION_STEP_UNKNOWN");
    }
    const className = activationClassOf(entry.key);
    if (className === ECF_ACTIVATION_CLASS.CLIENT_ACTION) {
      // Un paso del cliente no se "reintenta" desde el motor: lo resuelve él.
      throw new BadRequestException("ECF_ACTIVATION_AWAITING_CLIENT");
    }
    if (className === ECF_ACTIVATION_CLASS.AUTHORITY_WAIT) {
      throw new BadRequestException("ECF_ACTIVATION_AWAITING_AUTHORITY");
    }

    const stepKey = entry.stepKey as EcfOnboardingStepKey;
    const current = await this.prisma.ecfOnboardingStep.findUnique({
      where: { companyId_stepKey: { companyId, stepKey } },
      select: { status: true, blockedReason: true },
    });

    // Una etapa BLOQUEADA **con motivo** es una decisión registrada: la tomó una
    // persona o el expediente, no el motor. Reintentarla borraría la razón y
    // dejaría que el transporte simulado la diera por buena. Quien la bloqueó es
    // quien debe levantarla; aquí solo se informa.
    if (
      current?.status === EcfOnboardingStepStatus.BLOCKED &&
      current.blockedReason
    ) {
      throw new ConflictException({
        message: "ECF_ACTIVATION_STEP_BLOCKED_BY_DECISION",
        blockedReason: current.blockedReason,
      });
    }

    if (
      current &&
      (current.status === EcfOnboardingStepStatus.FAILED ||
        current.status === EcfOnboardingStepStatus.BLOCKED)
    ) {
      await this.prisma.$transaction(async (tx) => {
        await tx.ecfOnboardingStep.updateMany({
          where: {
            companyId,
            stepKey,
            status: {
              in: [
                EcfOnboardingStepStatus.FAILED,
                EcfOnboardingStepStatus.BLOCKED,
              ],
            },
            // Compare-and-set: si alguien registró un motivo entre la lectura y
            // esta escritura, la condición deja de cumplirse y no se toca nada.
            blockedReason: null,
          },
          data: {
            status: EcfOnboardingStepStatus.PENDING,
            lastErrorCode: null,
            lastError: null,
            blockedReason: null,
          },
        });
        await tx.ecfAuditLog.create({
          data: {
            companyId,
            actorUserId: user.id,
            action: EcfAuditAction.STEP_UPDATED,
            targetType: "EcfOnboardingStep",
            after: {
              stepKey,
              from: current.status,
              to: ECF_ACTIVATION_STATUS.PENDING,
              retried: true,
            } as Prisma.InputJsonValue,
          },
        });
      });
    } else if (!current) {
      // Sin etapa creada todavía no hay nada que reintentar: se prepara el
      // catálogo y se continúa. No es un error del cliente.
      await this.ensureSteps(companyId);
    }

    await this.runPendingSteps(companyId, user.id);
    const view = await this.readView(companyId);
    return this.toResponse(companyId, view);
  }

  /** Vista de solo lectura para el panel de plataforma. */
  async getActivationForCompany(companyId: string) {
    await this.assertCompanyExists(companyId);
    const view = await this.readView(companyId);
    return this.toResponse(companyId, view);
  }

  // ---------------------------------------------------------------- interno

  /**
   * Ejecuta pasos mientras el siguiente sea del motor.
   *
   * Se detiene en cuanto un paso no se completa: así no puede adelantar trabajo
   * sobre un certificado o una autorización que todavía no existen.
   */
  private async runPendingSteps(companyId: string, actorUserId: string) {
    await this.ensureSteps(companyId);

    for (let iteration = 0; iteration < ECF_DGII_REQUIREMENT_CATALOG.length + 1; iteration++) {
      const steps = await this.readView(companyId);
      const next = nextExecutableStep(buildActivationView(steps));
      if (!next) return;

      // Compare-and-set: solo una ejecución puede tomar el paso.
      const taken = await this.prisma.ecfOnboardingStep.updateMany({
        where: {
          companyId,
          stepKey: next.stepKey as EcfOnboardingStepKey,
          status: { in: [EcfOnboardingStepStatus.PENDING, EcfOnboardingStepStatus.FAILED] },
        },
        data: {
          status: EcfOnboardingStepStatus.IN_PROGRESS,
          startedAt: new Date(),
          updatedByUserId: actorUserId,
        },
      });
      if (taken.count !== 1) {
        // Otra ejecución lo tomó o ya estaba resuelto: se reevalúa.
        continue;
      }

      const outcome = await this.executeStep(next.key, next.className);
      const target = stepStatusFromTransport({
        className: next.className,
        transportOk: outcome.ok,
        simulated: outcome.simulated,
      });
      const dbStatus = this.toDbStatus(target);
      const now = new Date();

      await this.prisma.$transaction(async (tx) => {
        await tx.ecfOnboardingStep.updateMany({
          where: { companyId, stepKey: next.stepKey as EcfOnboardingStepKey },
          data: {
            status: dbStatus,
            ...(dbStatus === EcfOnboardingStepStatus.COMPLETED
              ? { completedAt: now, blockedReason: null, lastErrorCode: null }
              : {}),
            ...(dbStatus === EcfOnboardingStepStatus.BLOCKED
              ? { blockedReason: outcome.blockedReason }
              : {}),
            ...(dbStatus === EcfOnboardingStepStatus.FAILED
              ? {
                  lastErrorCode: outcome.errorCode ?? "ECF_ACTIVATION_STEP_FAILED",
                  lastError: outcome.detail ?? null,
                }
              : {}),
            resultSummary: outcome.summary,
            updatedByUserId: actorUserId,
          },
        });
        await tx.ecfAuditLog.create({
          data: {
            companyId,
            actorUserId,
            action: EcfAuditAction.STEP_UPDATED,
            targetType: "EcfOnboardingStep",
            after: {
              stepKey: next.stepKey,
              from: ECF_ACTIVATION_STATUS.PENDING,
              to: target,
              simulated: outcome.simulated,
              summary: outcome.summary,
            } as Prisma.InputJsonValue,
          },
        });
      });

      if (dbStatus !== EcfOnboardingStepStatus.COMPLETED) return;
    }
  }

  /**
   * Ejecuta un paso del motor.
   *
   * `AUTOMATIC_LOCAL` se resuelve localmente. `PROVIDER_WAIT` pasa por el
   * transporte, hoy simulado. El transporte real está prohibido mientras no
   * exista contrato: `assertTransportAvailable` lo bloquea antes de llegar aquí.
   */
  private async executeStep(
    key: string,
    className: string,
  ): Promise<{
    ok: boolean;
    simulated: boolean;
    summary: string;
    errorCode?: string;
    detail?: string;
    blockedReason?: string;
  }> {
    if (className === ECF_ACTIVATION_CLASS.AUTOMATIC_LOCAL) {
      return {
        ok: true,
        simulated: false,
        summary: `LOCAL:${key}`,
      };
    }

    const scenario = (
      this.config.get<string>(ECF_ACTIVATION_SCENARIO_ENV) ?? "ok"
    ).toLowerCase();

    // Simulación: no contacta a nadie y se marca como tal de forma explícita.
    if (scenario === "reject") {
      return {
        ok: false,
        simulated: true,
        summary: `SIMULATED_REJECTED:${key}`,
        errorCode: "ECF_ACTIVATION_SIMULATED_REJECTION",
        detail: "El escenario simulado devolvió un rechazo.",
      };
    }
    if (scenario === "timeout") {
      return {
        ok: false,
        simulated: true,
        summary: `SIMULATED_TIMEOUT:${key}`,
        errorCode: "ECF_ACTIVATION_SIMULATED_TIMEOUT",
        detail: "El escenario simulado no respondió a tiempo.",
      };
    }
    return { ok: true, simulated: true, summary: `SIMULATED_OK:${key}` };
  }

  private toDbStatus(status: string): EcfOnboardingStepStatus {
    switch (status) {
      case ECF_ACTIVATION_STATUS.COMPLETED:
        return EcfOnboardingStepStatus.COMPLETED;
      case ECF_ACTIVATION_STATUS.FAILED:
        return EcfOnboardingStepStatus.FAILED;
      case ECF_ACTIVATION_STATUS.PENDING:
        // Crítico: el compare-and-set de `runPendingSteps` solo toma pasos
        // PENDING o FAILED. Convertir PENDING en BLOCKED dejaba los pasos
        // recién creados en un estado que el motor nunca recoge, así que una
        // empresa nueva no ejecutaba nada y no dejaba auditoría.
        return EcfOnboardingStepStatus.PENDING;
      default:
        return EcfOnboardingStepStatus.BLOCKED;
    }
  }

  /** Crea las etapas que falten con su estado inicial honesto. */
  private async ensureSteps(companyId: string) {
    const existing = await this.prisma.ecfOnboardingStep.findMany({
      where: { companyId },
      select: { stepKey: true },
    });
    const present = new Set(existing.map((row) => row.stepKey));
    const missing = ECF_DGII_REQUIREMENT_CATALOG.filter(
      (item) => !present.has(item.stepKey as EcfOnboardingStepKey),
    );
    if (missing.length === 0) return;

    await this.prisma.ecfOnboardingStep.createMany({
      data: missing.map((item) => ({
        companyId,
        stepKey: item.stepKey as EcfOnboardingStepKey,
        status: this.toDbStatus(initialStepStatus(item.key)),
        ...(activationClassOf(item.key) === ECF_ACTIVATION_CLASS.CLIENT_ACTION
          ? { blockedReason: "AWAITING_CLIENT" }
          : {}),
        ...(activationClassOf(item.key) === ECF_ACTIVATION_CLASS.AUTHORITY_WAIT
          ? { blockedReason: "AWAITING_AUTHORITY" }
          : {}),
      })),
      skipDuplicates: true,
    });
  }

  /** Cruza catálogo + estado persistido y delega toda decisión en la política. */
  private async readView(companyId: string): Promise<ActivationStepInput[]> {
    const rows = await this.prisma.ecfOnboardingStep.findMany({
      where: { companyId },
      select: { stepKey: true, status: true, blockedReason: true },
    });
    const byStep = new Map(rows.map((row) => [row.stepKey, row]));

    return ECF_DGII_REQUIREMENT_CATALOG.map((item) => {
      const row = byStep.get(item.stepKey as EcfOnboardingStepKey);
      return {
        key: item.key,
        stepKey: item.stepKey,
        label: item.label,
        mandatory: item.mandatory,
        status: this.toActivationStatus(row?.status, item.key),
      };
    });
  }

  private toActivationStatus(
    status: EcfOnboardingStepStatus | undefined,
    key: string,
  ): string {
    switch (status) {
      case EcfOnboardingStepStatus.COMPLETED:
      case EcfOnboardingStepStatus.CONFIRMED:
        return ECF_ACTIVATION_STATUS.COMPLETED;
      case EcfOnboardingStepStatus.FAILED:
        return ECF_ACTIVATION_STATUS.FAILED;
      case EcfOnboardingStepStatus.BLOCKED: {
        const className = activationClassOf(key);
        if (className === ECF_ACTIVATION_CLASS.AUTHORITY_WAIT) {
          return ECF_ACTIVATION_STATUS.AWAITING_AUTHORITY;
        }
        return ECF_ACTIVATION_STATUS.AWAITING_CLIENT;
      }
      default:
        return ECF_ACTIVATION_STATUS.PENDING;
    }
  }

  private toResponse(companyId: string, view: ActivationStepInput[]) {
    const built = buildActivationView(view);
    return {
      companyId,
      transport: "SIMULATED",
      realTransportEnabled: false,
      summary: activationSummary(built),
      steps: built.map((step) => ({
        key: step.key,
        stepKey: step.stepKey,
        label: step.label,
        mandatory: step.mandatory,
        className: step.className,
        status: step.status,
        resolved: step.resolved,
        executable: step.executable,
        awaiting: step.awaiting,
      })),
    };
  }

  /**
   * El transporte real está desactivado hasta que exista contrato verificado.
   * Se comprueba en cada arranque, no solo al inicio del proceso.
   */
  private assertTransportAvailable() {
    const mode = (
      this.config.get<string>(ECF_ACTIVATION_TRANSPORT_ENV) ?? "simulated"
    ).toLowerCase();
    if (mode !== "simulated") {
      throw new ServiceUnavailableException(
        "ECF_ACTIVATION_REAL_TRANSPORT_NOT_CONFIGURED",
      );
    }
  }

  private async assertCompanyExists(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true },
    });
    if (!company) throw new NotFoundException("Empresa no encontrada");
  }
}
