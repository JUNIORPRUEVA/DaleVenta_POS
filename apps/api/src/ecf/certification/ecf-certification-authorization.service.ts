import { Injectable, Logger } from "@nestjs/common";
import { EcfAuditAction, EcfCertificationStatus, Prisma } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import {
  decideCertificationGrant,
  decideCertificationRevoke,
  isCertificationGrantTarget,
  type EcfCertificationDecision,
  type EcfCertificationGrantTarget,
} from "./ecf-certification-authorization.policy";

/**
 * Autorización de EMISIÓN por empresa.
 *
 * Es la ruta administrativa que faltaba: el estado de certificación que el
 * orquestador exige para despachar (`AUTHORIZED_SANDBOX`, `PRODUCTION_READY`)
 * solo se podía escribir a mano en la base. Aquí queda como una operación con
 * actor, motivo obligatorio, transiciones cerradas y auditoría.
 *
 * Reglas
 * ------
 * 1. **Solo avanza.** Las transiciones permitidas viven en la política; no hay
 *    forma de saltarse sandbox antes de producción ni de rebajar con un grant.
 * 2. **El bloqueo manda.** Una empresa con `BLOCKED` no se autoriza: ese estado
 *    describe evidencia vigente en contra.
 * 3. **Todo se audita.** Cada cambio escribe una fila en `ecf_audit_logs` con
 *    estado anterior, estado nuevo, actor, motivo y referencia de evidencia.
 *    Una repetición idempotente no escribe nada (no duplica historia).
 * 4. **No emite.** Esta autorización no envía nada a DOSA, no activa
 *    credenciales, no toca `enabled`, `environment`, `productionEnabled` ni
 *    banderas de entorno. Solo cambia `certificationStatus`.
 * 5. **Aislamiento.** Toda consulta y toda escritura se filtra por `companyId`.
 */

/** `targetType` de las filas de auditoría de este módulo. */
const AUDIT_TARGET_TYPE = "ECF_CERTIFICATION_AUTHORIZATION";

/** `metadata.operation`: distingue autorización de revocación sin migrar el enum. */
const AUDIT_OPERATION = {
  AUTHORIZE: "CERTIFICATION_STATUS_AUTHORIZED",
  REVOKE: "CERTIFICATION_STATUS_REVOKED",
} as const;

export type CertificationAuthorizationResult =
  | {
      ok: true;
      companyId: string;
      changed: boolean;
      from: EcfCertificationStatus;
      to: EcfCertificationStatus;
    }
  | { ok: false; blockedReason: string };

export type CertificationAuthorizationSnapshot = {
  companyId: string;
  certificationStatus: EcfCertificationStatus;
  enabled: boolean;
  provider: string;
  environment: string;
  productionEnabled: boolean;
  /** Estados que se pueden pedir ahora mismo. Vacío si no hay avance posible. */
  availableTargets: EcfCertificationGrantTarget[];
  history: Array<{
    id: string;
    operation: string | null;
    from: string | null;
    to: string | null;
    reason: string | null;
    evidenceReference: string | null;
    actorUserId: string | null;
    createdAt: Date;
  }>;
};

@Injectable()
export class EcfCertificationAuthorizationService {
  private readonly logger = new Logger(EcfCertificationAuthorizationService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Situación de autorización de UNA empresa.
   *
   * Devuelve también qué objetivos son alcanzables ahora, para que la interfaz
   * no ofrezca un botón que el servidor va a rechazar.
   */
  async snapshot(
    companyId: string,
    options: { historyTake?: number } = {},
  ): Promise<CertificationAuthorizationSnapshot | null> {
    const id = (companyId ?? "").trim();
    if (!id) return null;

    const [config, audit] = await Promise.all([
      this.prisma.ecfCompanyConfiguration.findUnique({
        where: { companyId: id },
        select: {
          certificationStatus: true,
          enabled: true,
          provider: true,
          environment: true,
          productionEnabled: true,
        },
      }),
      this.prisma.ecfAuditLog.findMany({
        where: { companyId: id, targetType: AUDIT_TARGET_TYPE },
        orderBy: { createdAt: "desc" },
        take: Math.min(Math.max(options.historyTake ?? 20, 1), 100),
        select: {
          id: true,
          metadata: true,
          before: true,
          after: true,
          actorUserId: true,
          createdAt: true,
        },
      }),
    ]);

    if (!config) return null;

    return {
      companyId: id,
      certificationStatus: config.certificationStatus,
      enabled: config.enabled,
      provider: config.provider,
      environment: config.environment,
      productionEnabled: config.productionEnabled,
      availableTargets: availableTargetsFor(config.certificationStatus),
      history: audit.map((row) => {
        const metadata = (row.metadata ?? {}) as Record<string, unknown>;
        const before = (row.before ?? {}) as Record<string, unknown>;
        const after = (row.after ?? {}) as Record<string, unknown>;
        return {
          id: row.id,
          operation: typeof metadata.operation === "string" ? metadata.operation : null,
          from: typeof before.certificationStatus === "string" ? before.certificationStatus : null,
          to: typeof after.certificationStatus === "string" ? after.certificationStatus : null,
          reason: typeof metadata.reason === "string" ? metadata.reason : null,
          evidenceReference:
            typeof metadata.evidenceReference === "string"
              ? metadata.evidenceReference
              : null,
          actorUserId: row.actorUserId,
          createdAt: row.createdAt,
        };
      }),
    };
  }

  /**
   * Autoriza la emisión de una empresa.
   *
   * `reason` es obligatorio: una autorización que habilita comprobantes
   * fiscales sin motivo no es auditable y no se acepta.
   */
  async authorize(input: {
    companyId: string;
    target: string;
    reason: string;
    evidenceReference?: string | null;
    actorUserId: string | null;
  }): Promise<CertificationAuthorizationResult> {
    const companyId = (input.companyId ?? "").trim();
    const reason = (input.reason ?? "").trim();
    if (!companyId) return { ok: false, blockedReason: "COMPANY_REQUIRED" };
    if (!reason) return { ok: false, blockedReason: "REASON_REQUIRED" };
    if (!isCertificationGrantTarget(input.target)) {
      return { ok: false, blockedReason: "ECF_CERTIFICATION_TARGET_NOT_ALLOWED" };
    }

    return this.apply({
      companyId,
      reason,
      evidenceReference: input.evidenceReference ?? null,
      actorUserId: input.actorUserId,
      operation: AUDIT_OPERATION.AUTHORIZE,
      decide: (current) => decideCertificationGrant({ current, target: input.target }),
      target: input.target,
    });
  }

  /** Revoca la autorización vigente. Deja `SUSPENDED`, nunca `NOT_STARTED`. */
  async revoke(input: {
    companyId: string;
    reason: string;
    actorUserId: string | null;
  }): Promise<CertificationAuthorizationResult> {
    const companyId = (input.companyId ?? "").trim();
    const reason = (input.reason ?? "").trim();
    if (!companyId) return { ok: false, blockedReason: "COMPANY_REQUIRED" };
    if (!reason) return { ok: false, blockedReason: "REASON_REQUIRED" };

    return this.apply({
      companyId,
      reason,
      evidenceReference: null,
      actorUserId: input.actorUserId,
      operation: AUDIT_OPERATION.REVOKE,
      decide: (current) => decideCertificationRevoke({ current }),
      target: null,
    });
  }

  /**
   * Núcleo común: leer, decidir, escribir y auditar en la MISMA transacción.
   *
   * La lectura y la escritura comparten transacción para que la auditoría
   * registre el estado que realmente había, no uno leído antes de una escritura
   * concurrente.
   */
  private async apply(input: {
    companyId: string;
    reason: string;
    evidenceReference: string | null;
    actorUserId: string | null;
    operation: string;
    target: string | null;
    decide: (current: EcfCertificationStatus) => EcfCertificationDecision;
  }): Promise<CertificationAuthorizationResult> {
    return this.prisma.$transaction(async (tx) => {
      const config = await tx.ecfCompanyConfiguration.findUnique({
        where: { companyId: input.companyId },
        select: { companyId: true, certificationStatus: true },
      });
      if (!config) {
        return {
          ok: false as const,
          blockedReason: "ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND",
        };
      }

      const decision = input.decide(config.certificationStatus);
      if (!decision.ok) {
        return { ok: false as const, blockedReason: decision.blockedReason };
      }

      // Idempotente: el estado ya era el pedido. Ni escritura ni auditoría.
      if (!decision.changed) {
        return {
          ok: true as const,
          companyId: input.companyId,
          changed: false,
          from: decision.from,
          to: decision.to,
        };
      }

      await tx.ecfCompanyConfiguration.update({
        where: { companyId: input.companyId },
        data: {
          certificationStatus: decision.to,
          updatedByUserId: input.actorUserId,
        },
      });

      await tx.ecfAuditLog.create({
        data: {
          companyId: input.companyId,
          actorUserId: input.actorUserId,
          // Se reutiliza `CONFIG_UPDATED`: el cambio ES una actualización de la
          // configuración e-CF. Se distingue por `targetType` y `metadata`, así
          // que no hace falta migrar el enum en producción para auditar esto.
          action: EcfAuditAction.CONFIG_UPDATED,
          targetType: AUDIT_TARGET_TYPE,
          targetId: null,
          before: { certificationStatus: decision.from } as Prisma.InputJsonValue,
          after: { certificationStatus: decision.to } as Prisma.InputJsonValue,
          metadata: {
            operation: input.operation,
            reason: input.reason,
            evidenceReference: input.evidenceReference,
            target: input.target,
          } as Prisma.InputJsonValue,
        },
      });

      this.logger.log(
        `Certificación e-CF de ${input.companyId}: ${decision.from} -> ${decision.to} (${input.operation})`,
      );

      return {
        ok: true as const,
        companyId: input.companyId,
        changed: true,
        from: decision.from,
        to: decision.to,
      };
    });
  }
}

/**
 * Objetivos alcanzables desde un estado.
 *
 * Se deriva de la política, no se declara aparte: si mañana cambia una
 * transición, la interfaz cambia con ella.
 */
function availableTargetsFor(
  current: EcfCertificationStatus,
): EcfCertificationGrantTarget[] {
  return (["AUTHORIZED_SANDBOX", "PRODUCTION_READY"] as const).filter(
    (target) => decideCertificationGrant({ current, target }).ok,
  ) as EcfCertificationGrantTarget[];
}
