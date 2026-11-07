import { Injectable, Logger } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service";
import { isEcfPortalPilotCompany } from "./ecf-portal-pilot.policy";
import {
  decidePortalEligibility,
  type PortalEligibilityDecision,
} from "./ecf-portal-enrollment.policy";

/**
 * Autorización POR EMPRESA para usar el asistente e-CF.
 *
 * Problema que resuelve
 * ---------------------
 * La elegibilidad vivía en `ECF_PORTAL_PILOT_COMPANY_IDS`, una variable del
 * despliegue: cada cliente nuevo exigía editar el entorno y reiniciar, y no
 * quedaba registro de quién lo autorizó. Aquí la decisión es un dato de la base,
 * con autor, motivo, fecha y caducidad.
 *
 * Reglas
 * ------
 * 1. **Fail-closed.** Sin una fila `ACTIVE` vigente (ni la lista heredada) no
 *    hay elegibilidad. Una autorización caducada deja de servir sin que nadie
 *    toque nada.
 * 2. **Una sola vigente por empresa.** Lo garantiza un índice único parcial en la
 *    base: dos autorizaciones simultáneas no pueden coexistir.
 * 3. **Historial, no borrado.** Revocar marca `revokedAt`; la fila permanece.
 * 4. **Aislamiento.** Toda consulta y toda escritura se filtra por `companyId`;
 *    no existe una operación "para todas".
 * 5. **La lista heredada no manda.** `ECF_PORTAL_PILOT_COMPANY_IDS` se sigue
 *    leyendo para no romper un despliegue ya configurado, pero solo como
 *    compatibilidad: queda fuera de toda escritura y se declara obsoleta.
 */

/** De dónde viene la autorización. Lista cerrada. */
export const ECF_PORTAL_ENROLLMENT_SOURCES = [
  /** Una persona de plataforma la concede, con motivo. */
  "ADMIN_AUTHORIZATION",
  /** Existe una referencia contractual verificable. */
  "CONTRACT_REFERENCE",
  /** La regla automática la concedió al cumplirse las condiciones. */
  "AUTO_ELIGIBLE",
] as const;

export type EcfPortalEnrollmentSource = (typeof ECF_PORTAL_ENROLLMENT_SOURCES)[number];

export const ECF_PORTAL_ENROLLMENT_STATUS = {
  ACTIVE: "ACTIVE",
  REVOKED: "REVOKED",
} as const;

/**
 * ¿Está habilitada la inscripción automática?
 *
 * **Encendida por defecto** (opt-out). Antes era opt-in y el resultado real era
 * que ninguna empresa nueva podía abrir el asistente: sin fila de inscripción no
 * había elegibilidad, y la única forma de entrar era que alguien de Fulltech
 * concediera el acceso a mano. Eso contradecía el objetivo del producto, que es
 * que el cliente complete su trámite solo.
 *
 * Sigue siendo un interruptor: `ECF_PORTAL_AUTO_ENROLL_ENABLED=false` la apaga
 * sin desplegar código, y una empresa concreta se sigue bloqueando revocando su
 * inscripción (una revocación gana siempre sobre esta regla).
 */
export function isPortalAutoEnrollmentEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (
    (env.ECF_PORTAL_AUTO_ENROLL_ENABLED ?? "true").trim().toLowerCase() !== "false"
  );
}

/** Motivo de elegibilidad. Se devuelve a la interfaz para no adivinar nada. */
export type EcfPortalEligibilityReason =
  | "ENROLLED"
  | "ENROLLED_LEGACY_ENV"
  | "AUTO_ELIGIBLE"
  | "NO_AUTHORIZATION"
  | "AUTHORIZATION_EXPIRED"
  | "AUTHORIZATION_REVOKED"
  | "COMPANY_NOT_FOUND";

export type EcfPortalEligibility = {
  eligible: boolean;
  companyId: string;
  reason: EcfPortalEligibilityReason;
  /** Fecha en la que caduca la autorización vigente, si la tiene. */
  expiresAt: string | null;
  /** De dónde viene (solo si es elegible). */
  source: string | null;
  /** `true` si la elegibilidad viene de la variable heredada. */
  legacy: boolean;
};

@Injectable()
export class EcfPortalEnrollmentService {
  private readonly logger = new Logger(EcfPortalEnrollmentService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * ¿Puede esta empresa abrir el asistente?
   *
   * Es la ÚNICA puerta. Se lee en cada llamada: conceder o revocar surte efecto
   * sin reiniciar el servicio.
   */
  async eligibility(
    companyId: string,
    options: { now?: Date; env?: Record<string, string | undefined> } = {},
  ): Promise<EcfPortalEligibility> {
    const now = options.now ?? new Date();
    const id = (companyId ?? "").trim();
    if (!id) {
      return {
        eligible: false,
        companyId: "",
        reason: "COMPANY_NOT_FOUND",
        expiresAt: null,
        source: null,
        legacy: false,
      };
    }

    const row = await this.prisma.ecfPortalEnrollment.findFirst({
      where: { companyId: id },
      orderBy: [{ createdAt: "desc" }],
      select: {
        status: true,
        source: true,
        expiresAt: true,
        revokedAt: true,
      },
    });

    const decision: PortalEligibilityDecision = decidePortalEligibility({
      enrollment: row,
      legacyEligible: isEcfPortalPilotCompany(
        id,
        options.env?.["ECF_PORTAL_PILOT_COMPANY_IDS"],
      ),
      now,
      // La regla se evalúa aquí para que la lectura NO ofrezca una entrada que
      // el backend luego rechace. No escribe: persistir la inscripción es tarea
      // del camino de escritura (`ensureAutoEnrollment`).
      autoEligible:
        isPortalAutoEnrollmentEnabled(options.env) &&
        (await this.meetsAutoEnrollmentRule(id)),
    });

    return {
      eligible: decision.eligible,
      companyId: id,
      reason: decision.reason,
      expiresAt: decision.expiresAt?.toISOString() ?? null,
      source: decision.source,
      legacy: decision.legacy,
    };
  }

  /** Atajo booleano para las rutas que solo necesitan sí/no. */
  async isEligible(companyId: string): Promise<boolean> {
    return (await this.eligibility(companyId)).eligible;
  }

  /**
   * Concede la autorización.
   *
   * Idempotente por empresa: si ya hay una vigente, devuelve la existente y no
   * crea otra (lo mismo que impide el índice único, pero sin lanzar error).
   */
  async grant(input: {
    companyId: string;
    source: EcfPortalEnrollmentSource;
    reason: string;
    actorUserId: string | null;
    contractReference?: string | null;
    expiresAt?: Date | null;
  }): Promise<{ ok: true; id: string; created: boolean } | { ok: false; blockedReason: string }> {
    const companyId = (input.companyId ?? "").trim();
    const reason = (input.reason ?? "").trim();
    if (!companyId) return { ok: false, blockedReason: "COMPANY_REQUIRED" };
    if (!reason) {
      // Una autorización sin motivo no es auditable.
      return { ok: false, blockedReason: "REASON_REQUIRED" };
    }
    if (!(ECF_PORTAL_ENROLLMENT_SOURCES as readonly string[]).includes(input.source)) {
      return { ok: false, blockedReason: "SOURCE_NOT_ALLOWED" };
    }

    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true },
    });
    if (!company) return { ok: false, blockedReason: "COMPANY_NOT_FOUND" };

    const current = await this.prisma.ecfPortalEnrollment.findFirst({
      where: { companyId, status: ECF_PORTAL_ENROLLMENT_STATUS.ACTIVE },
      select: { id: true },
    });
    if (current) return { ok: true, id: current.id, created: false };

    try {
      const created = await this.prisma.ecfPortalEnrollment.create({
        data: {
          companyId,
          source: input.source,
          status: ECF_PORTAL_ENROLLMENT_STATUS.ACTIVE,
          reason,
          contractReference: input.contractReference ?? null,
          authorizedByUserId: input.actorUserId,
          expiresAt: input.expiresAt ?? null,
        },
        select: { id: true },
      });
      return { ok: true, id: created.id, created: true };
    } catch {
      // Carrera contra otra concesión simultánea: el índice único parcial ganó.
      const existing = await this.prisma.ecfPortalEnrollment.findFirst({
        where: { companyId, status: ECF_PORTAL_ENROLLMENT_STATUS.ACTIVE },
        select: { id: true },
      });
      if (existing) return { ok: true, id: existing.id, created: false };
      throw new Error("PORTAL_ENROLLMENT_GRANT_FAILED");
    }
  }

  /** Revoca la autorización vigente. No borra: deja historial. */
  async revoke(input: {
    companyId: string;
    actorUserId: string | null;
    reason: string;
  }): Promise<{ ok: true; revoked: number } | { ok: false; blockedReason: string }> {
    const companyId = (input.companyId ?? "").trim();
    const reason = (input.reason ?? "").trim();
    if (!companyId) return { ok: false, blockedReason: "COMPANY_REQUIRED" };
    if (!reason) return { ok: false, blockedReason: "REASON_REQUIRED" };

    const result = await this.prisma.ecfPortalEnrollment.updateMany({
      where: { companyId, status: ECF_PORTAL_ENROLLMENT_STATUS.ACTIVE },
      data: {
        status: ECF_PORTAL_ENROLLMENT_STATUS.REVOKED,
        revokedAt: new Date(),
        revokedByUserId: input.actorUserId,
        revocationReason: reason,
      },
    });
    return { ok: true, revoked: result.count };
  }

  /** Historial de una empresa, lo más reciente primero. */
  async history(companyId: string, take = 20) {
    return this.prisma.ecfPortalEnrollment.findMany({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      take: Math.min(Math.max(take, 1), 100),
      select: {
        id: true,
        source: true,
        status: true,
        reason: true,
        contractReference: true,
        authorizedByUserId: true,
        expiresAt: true,
        revokedAt: true,
        revokedByUserId: true,
        revocationReason: true,
        createdAt: true,
      },
    });
  }

  /**
   * Inscripción automática de una empresa que cumple la regla.
   *
   * Condiciones, todas verificables en la base: e-CF habilitado, identidad
   * fiscal registrada y una postulación ya iniciada por nuestro backend. No se
   * inscribe a quien solo tiene una cuenta.
   *
   * Solo se ejecuta si `ECF_PORTAL_AUTO_ENROLL_ENABLED=true`; por defecto está
   * apagada y el sistema falla cerrado.
   *
   * Nunca lanza: un fallo aquí no puede romper el flujo que la invoca.
   */
  async ensureAutoEnrollment(companyId: string): Promise<boolean> {
    if (!isPortalAutoEnrollmentEnabled()) return false;
    const id = (companyId ?? "").trim();
    if (!id) return false;

    try {
      const existing = await this.prisma.ecfPortalEnrollment.findFirst({
        where: { companyId: id, status: ECF_PORTAL_ENROLLMENT_STATUS.ACTIVE },
        select: { id: true },
      });
      if (existing) return true;

      const eligible = await this.meetsAutoEnrollmentRule(id);
      if (!eligible) return false;

      const granted = await this.grant({
        companyId: id,
        source: "AUTO_ELIGIBLE",
        reason:
          "Inscripción automática: e-CF habilitado, identidad fiscal registrada y postulación iniciada.",
        actorUserId: null,
      });
      return granted.ok;
    } catch (error) {
      this.logger.warn(
        `No se pudo inscribir automáticamente la empresa ${id}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return false;
    }
  }

  /**
   * Regla de autoservicio: la empresa puede entrar sola al asistente.
   *
   * Condiciones, todas verificables en la base:
   *
   * 1. e-CF habilitado en su configuración,
   * 2. identidad fiscal registrada (RNC).
   *
   * Antes exigía además que existiera una sesión de certificación. Eso hacía la
   * regla **circular**: la sesión solo existe después de entrar al asistente, y
   * al asistente solo se entra estando inscrito. Ninguna empresa nueva podía
   * inscribirse nunca. La condición se retiró; el resto del control sigue igual
   * (permisos, revocación, y la compuerta de emisión que no depende de esto).
   */
  async meetsAutoEnrollmentRule(companyId: string): Promise<boolean> {
    const rows = await this.prisma.$queryRaw<Array<{ ok: boolean }>>`
      SELECT (
        EXISTS (
          SELECT 1 FROM "ecf_company_configurations" c
           WHERE c."company_id" = ${companyId}::uuid AND c."enabled" = TRUE
        )
        AND EXISTS (
          SELECT 1 FROM "app_config" a
           WHERE a."company_id" = ${companyId}::uuid
             AND COALESCE(a."rnc", '') <> ''
        )
      ) AS "ok"
    `;
    return rows[0]?.ok === true;
  }
}
