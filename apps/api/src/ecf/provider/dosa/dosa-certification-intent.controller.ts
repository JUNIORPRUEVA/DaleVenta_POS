import {
  Body,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Controller,
  Get,
  HttpCode,
  Inject,
  Post,
  Req,
  ServiceUnavailableException,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { IsOptional, IsString, MaxLength, MinLength, IsUUID, Equals, IsIn } from "class-validator";
import { Prisma } from "@prisma/client";
import type { Request } from "express";
import { Permissions } from "../../../auth/roles.decorator";
import { RolesGuard } from "../../../auth/roles.guard";
import { requireTenant, type TenantUser } from "../../../auth/tenant-context";
import { PrismaService } from "../../../prisma/prisma.service";
import { isEcfPortalPilotCompany } from "../../portal/ecf-portal-pilot.policy";
import {
  DosaCertificationIntentService,
  type DosaIntentRejection,
} from "./dosa-certification-intent.service";
import { DosaCredentialService } from "./dosa-credential.service";
import type { DosaCredentialEnvironment } from "./dosa-credential-vault.service";
import { ECF_DOSA_FISCAL_CONFIG } from "./dosa-emission.service";
import type { DosaCompanyFiscalConfigReader } from "./dosa-emission.service";
import { effectiveIntentProvider, historicalIntentProvider, intentReconciliationKind, type DosaIntentAttributionAudit } from "./dosa-intent-attribution";
import {
  INTERNAL_EVIDENCE_SCHEMA,
  internalEvidenceDigest,
  verifyInternalEvidence,
  type DosaInternalEvidenceSnapshot,
  type DosaReconciliationReviewKind,
} from "./dosa-internal-review-evidence";

/** Cuerpo del registro de intención. */
export class RegisterDosaIntentDto {
  /**
   * RNC que el cliente cree conocer. **Solo se compara** con el del expediente:
   * nunca se acepta como identidad. Se admite para detectar clientes
   * desincronizados y responder con un motivo claro.
   */
  @IsOptional()
  @IsString()
  @MaxLength(32)
  rnc?: string;
}

/**
 * Cuerpo de la reconciliación administrativa del proveedor.
 *
 * Dos clases de revisión, mutuamente excluyentes:
 *
 * * `EXTERNAL` (por defecto, retrocompatible): exige una referencia de un acto
 *   del proveedor y la aprobación del propietario.
 * * `INTERNAL`: excepción basada en evidencia interna reproducible. Exige una
 *   referencia interna, la aprobación del propietario y una segunda bandera
 *   (`ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED`). No admite ninguna
 *   referencia externa: no se puede disfrazar una revisión interna de externa.
 */
export class ReconcileDosaIntentDto {
  @IsUUID() intentId!: string;
  @IsUUID() sourceAuditId!: string;
  /** Ausente = `EXTERNAL`, para no romper a los llamadores existentes. */
  @IsOptional() @IsIn(["EXTERNAL", "INTERNAL"]) reviewKind?: DosaReconciliationReviewKind;
  @IsOptional() @IsString() @MinLength(8) @MaxLength(128) externalReviewReference?: string;
  @IsOptional() @IsString() @MinLength(8) @MaxLength(128) internalReviewReference?: string;
  @IsString() @MinLength(8) @MaxLength(128) ownerApprovalReference!: string;
  @IsString() @MinLength(20) @MaxLength(500) reason!: string;
  @Equals("RECONCILE_EXISTING_DOSA_INTENT") confirmation!: string;
}

export type DosaIntentHttpResponse = {
  ok: true;
  companyId: string;
  rnc: string;
  sessionId: string;
  attemptNo: number;
  created: boolean;
  status: string;
  provider: string;
  ecfEnabled: boolean;
  /** Siempre `false`: preparar no autoriza emisión. */
  fiscalAuthorizationGranted: false;
};

export type DosaIntentStateResponse = {
  ok: true;
  companyId: string;
  canonicalRnc: string | null;
  canonicalSource: string | null;
  ecfEnabled: boolean;
  provider: string;
  canRegister: boolean;
  blockingReasons: readonly string[];
  session: {
    id: string;
    status: string;
    attemptNo: number;
    sessionUrl: string | null;
  } | null;
  credentials: {
    environment: DosaCredentialEnvironment;
    status: string;
    /** Solo presencia: nunca el valor, ni siquiera con nombre de clave. */
    present: {
      hasProductionKey: boolean;
      hasTestKey: boolean;
      hasSecret: boolean;
    };
  } | null;
  fiscalAuthorizationGranted: false;
};

type IntentAuditEntry = DosaIntentAttributionAudit & {
  id: string;
  action: string;
  createdAt: Date;
  metadata: unknown;
};

function recordedProvider(entries: readonly IntentAuditEntry[]): string {
  const providers = new Set(
    entries.map((entry) => {
      const metadata = entry.metadata;
      if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) return null;
      const provider = (metadata as Record<string, unknown>).provider;
      return provider === "DOSA" || provider === "ALANUBE" ? provider : null;
    }).filter((value): value is "DOSA" | "ALANUBE" => value !== null),
  );
  return providers.size === 1 ? [...providers][0] : "UNVERIFIED";
}

const REJECTION_HTTP: Record<DosaIntentRejection, "CONFLICT" | "UNAVAILABLE"> = {
  COMPANY_RNC_NOT_VERIFIED: "CONFLICT",
  RNC_DOES_NOT_MATCH_COMPANY_IDENTITY: "CONFLICT",
  AMBIGUOUS_RNC: "CONFLICT",
  SESSION_CLAIM_FAILED: "UNAVAILABLE",
};

/**
 * Preasociación empresa ↔ RNC de la Postulación Inteligente.
 *
 * Controlador **delgado a propósito**: no decide identidad, no elige empresa y no
 * toca credenciales. Traduce la petición autenticada al servicio, comprueba el
 * opt-in de e-CF y deja auditoría.
 *
 * Garantías:
 *
 * * La empresa sale **del contexto del servidor** (`requireTenant`). Un
 *   `companyId` en el cuerpo se ignora por completo: no existe en el DTO.
 * * El RNC sale del expediente fiscal del backend; el del cliente solo se compara.
 * * Registrar la intención **no activa** facturación electrónica: no se escribe
 *   en `ecf_company_configurations`, ni en credenciales, ni en secuencias.
 * * La respuesta no contiene claves fiscales ni secretos.
 * * Es idempotente: repetir devuelve la misma sesión con `created: false`; dos
 *   envíos simultáneos no crean dos intentos.
 *
 * Preparación y activación son estados **distintos** y no se confunden:
 *
 * * *Preparación* = esta fila de sesión, creada por la acción voluntaria de un
 *   administrador con `manageEcfOnboarding` sobre su propia empresa.
 * * *Activación* = `ecf_company_configurations.enabled` (módulo visible) y
 *   `production_enabled` (emisión real), que este controlador **nunca** toca.
 *
 * Por eso el opt-in de e-CF **no** se exige aquí: exigirlo obligaría a activar
 * el módulo antes de poder prepararlo, que es justo el orden inverso. La
 * autorización administrativa (autenticación + permiso + empresa del token) es
 * el opt-in de la preparación; la activación sigue teniendo sus propias
 * compuertas fiscales, intactas.
 */
@Controller("ecf/dosa")
@UseGuards(AuthGuard("jwt"), RolesGuard)
export class DosaCertificationIntentController {
  /** Peticiones en vuelo por empresa: corta ráfagas duplicadas. */
  private readonly inFlight = new Set<string>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly intents: DosaCertificationIntentService,
    private readonly credentials: DosaCredentialService,
    // `DosaCompanyFiscalConfigReader` es una interfaz: en runtime no existe como
    // valor, asi que Nest no puede resolverla por tipo. Se inyecta por token.
    @Inject(ECF_DOSA_FISCAL_CONFIG)
    private readonly fiscalConfig: DosaCompanyFiscalConfigReader,
  ) {}

  @Post("certification-intent")
  @HttpCode(200)
  @Permissions("manageEcfOnboarding")
  async register(
    @Req() req: Request,
    @Body() body: RegisterDosaIntentDto,
  ): Promise<DosaIntentHttpResponse> {
    const user = req.user as TenantUser;
    // La empresa SIEMPRE viene del token, jamás del cuerpo.
    const companyId = requireTenant(user);

    if (this.inFlight.has(companyId)) {
      throw new ConflictException("ECF_DOSA_INTENT_IN_PROGRESS");
    }
    this.inFlight.add(companyId);
    try {
      // Informativo: el estado del módulo de emisión NO condiciona la
      // preparación. Puede no existir configuración todavía (`null`) y el
      // administrador sigue teniendo derecho a preparar su habilitación.
      const fiscal = await this.fiscalConfig.read(companyId);

      const result = await this.intents.register({
        companyId,
        userId: user.id,
        rncFromClient: body?.rnc ?? null,
      });

      if (!result.ok) {
        if (REJECTION_HTTP[result.reason] === "UNAVAILABLE") {
          throw new ServiceUnavailableException(result.reason);
        }
        throw new ConflictException(result.reason);
      }

      // La configuración fiscal gobierna EMISIÓN, no la procedencia de una
      // intención. Una intención nueva de esta ruta es DOSA; una existente
      // conserva el proveedor registrado cuando se creó.
      const provider = result.created
        ? "DOSA"
        : await this.intentProvider(companyId, result.sessionId);

      if (result.created) {
        await this.audit(user, companyId, result.sessionId, {
          rnc: result.rnc,
          attemptNo: result.attemptNo,
          created: true,
          provider,
          configuredProvider: fiscal?.provider ?? null,
        });
      }

      return {
        ok: true,
        companyId,
        rnc: result.rnc,
        sessionId: result.sessionId,
        attemptNo: result.attemptNo,
        created: result.created,
        status: result.created ? "NOT_STARTED" : "EXISTING",
        provider,
        ecfEnabled: fiscal?.ecfEnabled === true,
        fiscalAuthorizationGranted: false,
      };
    } finally {
      this.inFlight.delete(companyId);
    }
  }

  @Get("certification-intent")
  @Permissions("viewEcfOnboarding")
  async state(@Req() req: Request): Promise<DosaIntentStateResponse> {
    const companyId = requireTenant(req.user as TenantUser);
    const fiscal = await this.fiscalConfig.read(companyId);
    const described = await this.intents.describe({ companyId });
    const preview = await this.intents.preview({ companyId });

    const environment: DosaCredentialEnvironment = "test";
    const credential = described.canonicalRnc
      ? await this.credentials.inspect({
          companyId,
          rnc: described.canonicalRnc,
          environment,
        })
      : null;

    // `ecfEnabled` es solo informativo: describe el módulo de emisión, no la
    // preparación. `canRegister` depende únicamente de que exista identidad
    // fiscal verificable y no ambigua.
    const ecfEnabled = fiscal?.ecfEnabled === true;
    const blockingReasons = preview.ok ? [] : [preview.reason];

    return {
      ok: true,
      companyId,
      canonicalRnc: described.canonicalRnc,
      canonicalSource: described.canonicalSource,
      ecfEnabled,
      provider: described.session
        ? await this.intentProvider(companyId, described.session.id)
        : "DOSA",
      canRegister: preview.ok,
      blockingReasons,
      session: described.session,
      credentials: credential
        ? {
            environment: credential.environment,
            status: credential.status,
            present: {
              hasProductionKey: credential.present.apiKeyProduccion,
              hasTestKey: credential.present.apiKeyTest,
              hasSecret: credential.present.apiSecret,
            },
          }
        : null,
      fiscalAuthorizationGranted: false,
    };
  }

  @Get("certification-diagnostic")
  @Permissions("manageEcfOnboarding")
  async diagnostic(@Req() req: Request) {
    const companyId = requireTenant(req.user as TenantUser);
    const [fiscal, session] = await Promise.all([
      this.fiscalConfig.read(companyId),
      this.prisma.ecfDosaCertificationSession.findFirst({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        select: {
          id: true,
          status: true,
          attemptNo: true,
          sessionUrl: true,
          providerPostulationId: true,
          createdAt: true,
        },
      }),
    ]);
    const audits = session ? await this.intentAudits(companyId, session.id) : [];
    const reconciliationKind = session ? intentReconciliationKind(audits) : null;
    return {
      companyId,
      configuredEmissionProvider: fiscal?.provider ?? null,
      ecfEnabled: fiscal?.ecfEnabled === true,
      intention: session ? {
        id: session.id,
        attemptNo: session.attemptNo,
        status: session.status,
        recordedProvider: recordedProvider(audits),
        effectiveProvider: effectiveIntentProvider(audits),
        /**
         * Clase de la revisión que sustentó la corrección de atribución.
         * `INTERNAL` avisa de que NO hubo confirmación del proveedor.
         */
        reconciliationKind,
        /**
         * Señal para revisión humana: hay una reconciliación y, además, datos
         * del proveedor en el intento. Ninguna coincidencia se resuelve sola.
         */
        attributionConflict:
          reconciliationKind !== null &&
          (Boolean(session.sessionUrl) || Boolean(session.providerPostulationId)),
        hasProviderSessionUrl: Boolean(session.sessionUrl),
        hasProviderPostulationId: Boolean(session.providerPostulationId),
        createdAt: session.createdAt,
      } : null,
      audit: audits.map((entry) => ({
        id: entry.id,
        action: entry.action,
        createdAt: entry.createdAt,
        recordedProvider: recordedProvider([entry]),
      })),
    };
  }

  /** Records an owner-approved administrative decision; references must be
   * verified independently before the switch is enabled. Never contacts DOSA. */
  @Post("certification-intent/reconcile-provider")
  @HttpCode(200)
  @Permissions("manageEcfOnboarding")
  async reconcileProvider(@Req() req: Request, @Body() body: ReconcileDosaIntentDto) {
    const user = req.user as TenantUser;
    const companyId = requireTenant(user);
    if (user.role !== "ADMIN" && user.role !== "ADMINISTRADOR") {
      throw new ForbiddenException("DOSA_INTENT_ADMIN_REQUIRED");
    }
    // Separate owner-controlled switch. No production write is possible by default.
    if (process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED !== "true") {
      throw new ConflictException("DOSA_INTENT_RECONCILIATION_DISABLED");
    }
    const reviewKind: DosaReconciliationReviewKind =
      body?.reviewKind === "INTERNAL" ? "INTERNAL" : "EXTERNAL";
    // La excepción interna tiene su PROPIA bandera: encender la reconciliación
    // general no la habilita.
    if (
      reviewKind === "INTERNAL" &&
      process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED !== "true"
    ) {
      throw new ConflictException("DOSA_INTENT_RECONCILIATION_INTERNAL_DISABLED");
    }
    if (!isEcfPortalPilotCompany(companyId)) {
      throw new ForbiddenException("PORTAL_PILOT_NOT_INCLUDED");
    }
    if (!body || body.confirmation !== "RECONCILE_EXISTING_DOSA_INTENT" ||
      !body.ownerApprovalReference?.trim() || !body.reason?.trim()) {
      throw new BadRequestException("DOSA_INTENT_RECONCILIATION_EVIDENCE_REQUIRED");
    }
    // Referencias: la del tipo declarado, y NUNCA la del otro tipo.
    const externalReference = (body.externalReviewReference ?? "").trim();
    const internalReference = (body.internalReviewReference ?? "").trim();
    if (externalReference.length > 0 && internalReference.length > 0) {
      // Ni se suman ni se elige una: la decisión es de una sola clase.
      throw new BadRequestException("DOSA_INTENT_REVIEW_REFERENCES_CONFLICT");
    }
    if (reviewKind === "EXTERNAL") {
      if (externalReference.length < 8) {
        throw new BadRequestException("DOSA_INTENT_EXTERNAL_REVIEW_REFERENCE_REQUIRED");
      }
    } else {
      if (internalReference.length < 8) {
        throw new BadRequestException("DOSA_INTENT_INTERNAL_REVIEW_REFERENCE_REQUIRED");
      }
    }
    return this.prisma.$transaction(async (tx) => {
      const intent = await tx.ecfDosaCertificationSession.findFirst({
        where: { id: body.intentId, companyId },
        select: { id: true, rnc: true, attemptNo: true, status: true,
          sessionUrl: true, providerPostulationId: true, lastEventType: true,
          providerConfirmedAt: true, closedAt: true, createdAt: true,
          createdByUserId: true },
      });
      if (!intent) throw new ConflictException("DOSA_INTENT_NOT_FOUND");
      // Valores OBSERVADOS en la lectura, capturados antes de cualquier
      // comprobación: la evidencia que se firma describe lo que se leyó.
      const observedProviderReferences = {
        providerPostulationId: intent.providerPostulationId,
        sessionUrl: intent.sessionUrl,
        lastEventType: intent.lastEventType,
        providerConfirmedAt: intent.providerConfirmedAt,
        closedAt: intent.closedAt,
      };
      const latest = await tx.ecfDosaCertificationSession.findFirst({
        where: { companyId }, orderBy: { createdAt: "desc" }, select: { id: true },
      });
      if (latest?.id !== intent.id || intent.attemptNo !== 1 || intent.status !== "NOT_STARTED" ||
        intent.sessionUrl || intent.providerPostulationId || intent.lastEventType ||
        intent.providerConfirmedAt || intent.closedAt) {
        throw new ConflictException("DOSA_INTENT_RECONCILIATION_STATE_UNSAFE");
      }
      const audits = await tx.ecfAuditLog.findMany({
        where: { companyId, targetType: "DOSA_CERTIFICATION_INTENT", targetId: intent.id },
        select: { id: true, action: true, actorUserId: true, metadata: true, before: true, after: true },
      });
      const originals = audits.filter((entry) => entry.action === "ONBOARDING_STARTED");
      const original = originals.find((entry) => entry.metadata &&
        typeof entry.metadata === "object" && !Array.isArray(entry.metadata) &&
        (entry.metadata as Record<string, unknown>).created === true);
      const source = original?.metadata && typeof original.metadata === "object" &&
        !Array.isArray(original.metadata) ? original.metadata as Record<string, unknown> : null;
      if (originals.length === 0 || audits.length !== originals.length ||
        originals.filter((entry) => entry.metadata && typeof entry.metadata === "object" &&
          !Array.isArray(entry.metadata) &&
          (entry.metadata as Record<string, unknown>).created === true).length !== 1 ||
        original?.id !== body.sourceAuditId ||
        historicalIntentProvider(audits) !== "ALANUBE" ||
        source?.created !== true || source?.rnc !== intent.rnc ||
        source?.attemptNo !== intent.attemptNo ||
        originals.some((entry) => {
          const meta = entry.metadata as Record<string, unknown>;
          return meta.rnc !== intent.rnc || meta.attemptNo !== intent.attemptNo;
        }) ||
        !intent.createdByUserId || original.actorUserId !== intent.createdByUserId) {
        throw new ConflictException("DOSA_INTENT_LOCAL_ORIGIN_UNVERIFIED");
      }
      // La excepción interna solo vale sobre el caso exacto: una única auditoría
      // original. El snapshot que se firma debe describir ese caso, no uno más
      // laxo que luego la atribución rechazaría.
      if (reviewKind === "INTERNAL" && audits.length !== 1) {
        throw new ConflictException("DOSA_INTENT_LOCAL_ORIGIN_UNVERIFIED");
      }
      // Other local records can reveal external activity despite null session refs.
      const [legacyOperations, webhookEvents, portalTickets, portalSessions] = await Promise.all([
        tx.ecfCertificationAttempt.count({ where: { companyId, provider: "ALANUBE",
          createdAt: { gte: intent.createdAt } } }),
        tx.ecfDosaWebhookEvent.count({ where: { companyId, receivedAt: { gte: intent.createdAt } } }),
        tx.ecfCertificationPortalTicket.count({ where: { companyId,
          createdAt: { gte: intent.createdAt } } }),
        tx.ecfCertificationPortalSession.count({ where: { companyId,
          createdAt: { gte: intent.createdAt } } }),
      ]);
      if (legacyOperations || webhookEvents || portalTickets || portalSessions) {
        throw new ConflictException("DOSA_INTENT_EXTERNAL_ACTIVITY_REVIEW_REQUIRED");
      }
      const ownerApprovalReference = body.ownerApprovalReference.trim();
      const reason = body.reason.trim();

      let metadata: Prisma.InputJsonObject;
      if (reviewKind === "INTERNAL") {
        // Evidencia reproducible: se construye y se firma AQUÍ, dentro de la
        // transacción. El cliente no aporta ni el snapshot ni el digest.
        const originalMeta = (original.metadata ?? {}) as Record<string, unknown>;
        const originalProvider =
          originalMeta.provider === "ALANUBE" || originalMeta.provider === "DOSA"
            ? originalMeta.provider
            : "UNVERIFIED";
        const snapshot: DosaInternalEvidenceSnapshot = {
          schema: INTERNAL_EVIDENCE_SCHEMA,
          intent: {
            id: intent.id,
            companyId,
            rnc: intent.rnc,
            attemptNo: intent.attemptNo,
            status: intent.status,
            createdAt: intent.createdAt.toISOString(),
            createdByUserId: intent.createdByUserId,
            // Se copian los valores OBSERVADOS, no constantes: si alguna vez
            // existiera un dato del proveedor, el snapshot lo reflejaría y la
            // verificación lo rechazaría en lugar de ocultarlo.
            providerPostulationId: observedProviderReferences.providerPostulationId,
            sessionUrl: observedProviderReferences.sessionUrl,
            lastEventType: observedProviderReferences.lastEventType,
            providerConfirmedAt:
              observedProviderReferences.providerConfirmedAt?.toISOString() ?? null,
            closedAt: observedProviderReferences.closedAt?.toISOString() ?? null,
          },
          audit: {
            total: audits.length,
            originalAuditId: original.id,
            originalActorUserId: original.actorUserId ?? null,
            originalProvider,
            originalCreated: originalMeta.created === true,
            originalRnc: typeof originalMeta.rnc === "string" ? originalMeta.rnc : "",
            originalAttemptNo:
              typeof originalMeta.attemptNo === "number" ? originalMeta.attemptNo : -1,
          },
          activity: {
            legacyProviderAttempts: legacyOperations,
            webhookEvents,
            portalTickets,
            portalSessions,
          },
        };
        const candidate = {
          sourceAuditId: original.id,
          reviewKind: "INTERNAL" as const,
          internalReviewReference: internalReference,
          internalEvidenceDigest: internalEvidenceDigest(snapshot),
          evidenceSnapshot: snapshot,
          ownerApprovalReference,
          reason,
        };
        // Defensa en profundidad: no se escribe una decisión que la atribución
        // vaya a rechazar después. Falla cerrado antes de tocar la auditoría.
        const verdict = verifyInternalEvidence(candidate);
        if (!verdict.ok) {
          throw new ConflictException("DOSA_INTENT_INTERNAL_EVIDENCE_INCONSISTENT");
        }
        metadata = candidate as unknown as Prisma.InputJsonObject;
      } else {
        metadata = {
          sourceAuditId: original.id,
          reviewKind: "EXTERNAL",
          externalReviewReference: externalReference,
          ownerApprovalReference,
          reason,
        };
      }

      await tx.ecfAuditLog.create({ data: {
        companyId, actorUserId: user.id,
        action: "INTENT_PROVIDER_RECONCILED",
        targetType: "DOSA_CERTIFICATION_INTENT", targetId: intent.id,
        before: { provider: "ALANUBE" }, after: { provider: "DOSA" },
        metadata,
      } });
      return { ok: true, intentId: intent.id, attemptNo: intent.attemptNo,
        historicalProvider: "ALANUBE", effectiveProvider: "DOSA",
        reviewKind, fiscalAuthorizationGranted: false };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  private async intentProvider(companyId: string, sessionId: string): Promise<string> {
    return effectiveIntentProvider(await this.intentAudits(companyId, sessionId));
  }

  private async intentAudits(companyId: string, sessionId: string): Promise<IntentAuditEntry[]> {
    return this.prisma.ecfAuditLog.findMany({
      where: { companyId, targetType: "DOSA_CERTIFICATION_INTENT", targetId: sessionId },
      orderBy: { createdAt: "asc" },
      select: { id: true, action: true, actorUserId: true, createdAt: true,
        metadata: true, before: true, after: true },
    });
  }

  /**
   * Auditoría del intento. Nunca escribe credenciales: solo identificadores y el
   * resultado. Un fallo de auditoría no invalida la sesión ya creada, pero
   * tampoco se inventa un registro.
   */
  private async audit(
    user: TenantUser,
    companyId: string,
    sessionId: string,
    payload: Record<string, unknown>,
  ): Promise<void> {
    try {
      await this.prisma.ecfAuditLog.create({
        data: {
          companyId,
          actorUserId: user.id ?? null,
          action: "ONBOARDING_STARTED",
          targetType: "DOSA_CERTIFICATION_INTENT",
          targetId: sessionId,
          metadata: payload as never,
        },
      });
    } catch {
      // Deliberado: la preparación no se cae por un fallo de auditoría.
    }
  }
}

export { ECF_DOSA_FISCAL_CONFIG };
