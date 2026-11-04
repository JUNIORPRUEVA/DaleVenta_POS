import { Inject, Injectable } from "@nestjs/common";

import type { EcfCanonicalIdentity } from "../../dgii/certificate/ecf-canonical-identity.service";
import {
  isDosaEmailValid,
  type DosaCertificationSessionClient,
  type DosaSessionResult,
} from "./dosa-certification-session.client";
import type {
  DosaActiveSession,
  DosaSessionClaim,
  DosaSessionClosedStatus,
} from "./ecf-dosa-session.service";

/**
 * Apertura de la sesión de certificación DOSA para una empresa.
 *
 * Resuelve el problema completo en un solo lugar:
 *
 * 1. **Una sola captura de datos.** El RNC sale del expediente fiscal del
 *    backend y el correo de `app_config.ecf_contact_email`. Nada se acepta del
 *    navegador, así que el cliente no vuelve a escribir esos datos.
 * 2. **Reutilización segura.** Si la empresa ya tiene una sesión vigente sin
 *    caducar, se devuelve esa misma; no se crea otra.
 * 3. **Candado por empresa.** Un `UPDATE` condicional (lease) garantiza que
 *    solo una petición llama al proveedor; un doble clic o dos instancias no
 *    duplican la postulación.
 * 4. **Incertidumbre explícita.** Un timeout o un 5xx marcan el intento como
 *    `ATTENTION` y **no** se reintentan solos: la próxima petición tampoco
 *    repetirá la llamada hasta que un operador lo revise.
 * 5. **Secretos fuera.** La clave de servidor, el token y la URL de sesión no
 *    se registran. La URL solo se devuelve a un usuario autorizado de ESA
 *    empresa.
 */

export type DosaSessionOpenFailureCode =
  | "ECF_DOSA_SESSION_RNC_REQUIRED"
  | "ECF_DOSA_SESSION_EMAIL_REQUIRED"
  | "ECF_DOSA_SESSION_EMAIL_INVALID"
  | "ECF_DOSA_SESSION_DISABLED"
  | "ECF_DOSA_SESSION_IN_PROGRESS"
  | "ECF_DOSA_SESSION_UNCERTAIN"
  | "ECF_DOSA_SESSION_PROVIDER_ERROR"
  | "ECF_DOSA_SESSION_NOT_PERSISTED"
  | "ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED"
  | "ECF_DOSA_SESSION_EXPIRY_UNKNOWN";

export type DosaSessionOpenResult =
  | {
      ok: true;
      sessionUrl: string;
      expiresAt: string;
      attemptNo: number;
      providerPostulationId: string;
      reused: boolean;
    }
  | {
      ok: false;
      code: DosaSessionOpenFailureCode;
      message: string;
      /** `true` cuando el proveedor pudo crear la sesión aunque no la tengamos. */
      uncertain?: boolean;
      providerCode?: string;
    };

/** Lo mínimo que necesita el lanzador de la identidad fiscal canónica. */
export interface DosaIdentityReader {
  resolve(companyId: string): Promise<Pick<EcfCanonicalIdentity, "taxId">>;
}

/** Lectura del correo de facturación configurado para la empresa. */
export interface DosaContactEmailReader {
  read(companyId: string): Promise<string>;
}

/** Contrato estrecho de persistencia: permite probar sin base de datos. */
export interface DosaSessionCoordinator {
  /**
   * Historial ya reconciliado para esta empresa/RNC. La apertura automática no
   * puede mutar esos expedientes: requieren una operación explícita y auditada.
   */
  hasReconciledIntent?(
    companyId: string,
    rnc: string,
  ): Promise<boolean>;
  findActiveSessionFor(
    companyId: string,
    rnc: string,
  ): Promise<DosaActiveSession | null>;
  claim(input: {
    companyId: string;
    rnc: string;
    createdByUserId?: string | null;
  }): Promise<DosaSessionClaim>;
  acquireRequestLease(input: {
    companyId: string;
    rnc: string;
    leaseMs: number;
  }): Promise<{
    acquired: boolean;
    sessionUrl: string | null;
    sessionExpiresAt: string | null;
  }>;
  releaseRequestLease(input: { companyId: string; rnc: string }): Promise<void>;
  recordIssuedSession(input: {
    companyId: string;
    rnc: string;
    sessionUrl: string;
    sessionExpiresAt: string;
    providerPostulationId: string;
  }): Promise<{ recorded: boolean }>;
  markSessionUncertain(input: {
    companyId: string;
    rnc: string;
    reasonCode: string;
  }): Promise<{ updated: boolean }>;
  close(input: {
    companyId: string;
    rnc: string;
    status: DosaSessionClosedStatus;
  }): Promise<{ closed: boolean }>;
}

/** Contrato estrecho del cliente DOSA. */
export interface DosaSessionClientPort {
  describeReadiness(): {
    ready: boolean;
    blockingReasons: readonly string[];
  };
  createSession(request: {
    rncEmisor: string;
    correo: string;
  }): Promise<DosaSessionResult>;
}

export const ECF_DOSA_IDENTITY_READER = Symbol("ECF_DOSA_IDENTITY_READER");
export const ECF_DOSA_CONTACT_EMAIL_READER = Symbol(
  "ECF_DOSA_CONTACT_EMAIL_READER",
);
export const ECF_DOSA_SESSION_COORDINATOR = Symbol(
  "ECF_DOSA_SESSION_COORDINATOR",
);
export const ECF_DOSA_SESSION_CLIENT = Symbol("ECF_DOSA_SESSION_CLIENT");

/** Margen para no reutilizar una sesión que caduca en segundos. */
const EXPIRY_SKEW_MS = 30_000;
/**
 * Debe superar el timeout máximo del cliente (120 s) para que el lease no
 * expire mientras la petición ganadora sigue esperando al proveedor. Si el
 * proceso muere, la reserva se libera sola al vencer.
 */
export const DOSA_SESSION_DEFAULT_LEASE_MS = 180_000;

@Injectable()
export class DosaCertificationSessionService {
  constructor(
    @Inject(ECF_DOSA_IDENTITY_READER)
    private readonly identity: DosaIdentityReader,
    @Inject(ECF_DOSA_CONTACT_EMAIL_READER)
    private readonly emails: DosaContactEmailReader,
    @Inject(ECF_DOSA_SESSION_COORDINATOR)
    private readonly sessions: DosaSessionCoordinator,
    @Inject(ECF_DOSA_SESSION_CLIENT)
    private readonly client: DosaSessionClientPort,
    private readonly options: {
      leaseMs?: number;
      pollAttempts?: number;
      pollDelayMs?: number;
    } = {},
  ) {}

  async open(input: {
    companyId: string;
    userId?: string | null;
  }): Promise<DosaSessionOpenResult> {
    const companyId = `${input.companyId ?? ""}`.trim();
    const canonical = await this.identity.resolve(companyId);
    const rnc = normalizeRnc(canonical.taxId ?? "");
    if (!rnc) {
      return failure(
        "ECF_DOSA_SESSION_RNC_REQUIRED",
        "La empresa no tiene un RNC verificado en su expediente fiscal.",
      );
    }

    const email = `${(await this.emails.read(companyId)) ?? ""}`.trim();
    if (!email) {
      return failure(
        "ECF_DOSA_SESSION_EMAIL_REQUIRED",
        "Falta el correo de facturación electrónica de la empresa.",
      );
    }
    if (!isDosaEmailValid(email)) {
      return failure(
        "ECF_DOSA_SESSION_EMAIL_INVALID",
        "El correo de facturación electrónica no es válido.",
      );
    }

    // Un expediente reconciliado es histórico: la apertura automática no puede
    // cambiar sus estados, fechas, referencias ni identificadores. La única
    // vía es una operación explícita, autorizada y auditada.
    if (
      (await this.sessions.hasReconciledIntent?.(companyId, rnc)) === true
    ) {
      return failure(
        "ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED",
        "Este expediente tiene una revisión histórica registrada. La apertura automática está bloqueada: requiere una operación explícita y auditada.",
      );
    }

    const readiness = this.client.describeReadiness();
    if (!readiness.ready) {
      // Fail-closed: sin bandera o sin clave, no se llama al proveedor. El
      // cliente puede seguir usando el asistente manual.
      return failure(
        "ECF_DOSA_SESSION_DISABLED",
        "La apertura automática de sesiones DOSA no está habilitada.",
        { providerCode: readiness.blockingReasons.join(",") },
      );
    }

    // 1) Reutilización directa de una sesión vigente.
    const existing = await this.sessions.findActiveSessionFor(companyId, rnc);
    const reusable = reusableUrl(existing);
    if (reusable) return reusable;

    // Una URL histórica sin fecha de vencimiento no se puede validar. Se trata
    // como revisión manual: ni se reutiliza ni se sobrescribe con una nueva
    // sesión automática.
    if (existing && existing.sessionUrl && !existing.sessionExpiresAt) {
      return failure(
        "ECF_DOSA_SESSION_EXPIRY_UNKNOWN",
        "Hay una sesión anterior sin fecha de vencimiento verificable. Requiere revisión antes de abrir otra.",
      );
    }

    // 2) Una sesión incierta NO se reintenta sola.
    if (existing && existing.status === "ATTENTION") {
      return failure(
        "ECF_DOSA_SESSION_UNCERTAIN",
        "El proveedor no confirmó la sesión anterior. No se reintenta automáticamente.",
        { uncertain: true },
      );
    }

    // 3) Sesión caducada: se cierra para liberar el hueco del intento.
    if (existing && existing.sessionExpiresAt && isExpired(existing.sessionExpiresAt)) {
      await this.sessions.close({ companyId, rnc, status: "EXPIRED" });
    }

    // 4) Claim idempotente por empresa+RNC (índice único en la base).
    const claim = await this.sessions.claim({
      companyId,
      rnc,
      createdByUserId: input.userId ?? null,
    });
    if (!claim.ok) {
      return failure(
        "ECF_DOSA_SESSION_RNC_REQUIRED",
        "La empresa no tiene un RNC verificado en su expediente fiscal.",
      );
    }

    // El claim puede devolver un intento ya existente: hay que reevaluarlo,
    // porque otra petición pudo emitirlo mientras tanto.
    const afterClaim = await this.sessions.findActiveSessionFor(companyId, rnc);
    const reusableAfterClaim = reusableUrl(afterClaim);
    if (reusableAfterClaim) return reusableAfterClaim;
    if (afterClaim && afterClaim.status === "ATTENTION") {
      return failure(
        "ECF_DOSA_SESSION_UNCERTAIN",
        "El proveedor no confirmó la sesión anterior. No se reintenta automáticamente.",
        { uncertain: true },
      );
    }

    // 5) Candado: solo una petición puede llamar al proveedor.
    const lease = await this.sessions.acquireRequestLease({
      companyId,
      rnc,
      leaseMs: this.options.leaseMs ?? DOSA_SESSION_DEFAULT_LEASE_MS,
    });
    if (!lease.acquired) {
      const winner = await this.waitForWinner(companyId, rnc);
      if (winner) return winner;
      return failure(
        "ECF_DOSA_SESSION_IN_PROGRESS",
        "Ya hay una apertura de sesión en curso para esta empresa.",
      );
    }
    if (lease.sessionUrl && !isExpired(lease.sessionExpiresAt)) {
      // Otra petición emitió la sesión justo antes de ceder el candado.
      return {
        ok: true,
        sessionUrl: lease.sessionUrl,
        expiresAt: lease.sessionExpiresAt ?? "",
        attemptNo: claim.attemptNo,
        providerPostulationId: afterClaim?.providerPostulationId ?? "",
        reused: true,
      };
    }

    let result: DosaSessionResult;
    try {
      result = await this.client.createSession({ rncEmisor: rnc, correo: email });
    } catch {
      // Excepción no controlada del transporte: el proveedor pudo crear la
      // sesión. Se marca incierta y NO se reintenta.
      await this.sessions.markSessionUncertain({
        companyId,
        rnc,
        reasonCode: "TRANSPORT_EXCEPTION",
      });
      return failure(
        "ECF_DOSA_SESSION_UNCERTAIN",
        "No hubo respuesta concluyente del proveedor. No se reintenta automáticamente.",
        { uncertain: true },
      );
    }

    if (!result.ok) {
      if (result.uncertain) {
        await this.sessions.markSessionUncertain({
          companyId,
          rnc,
          reasonCode: result.code,
        });
        return failure(
          "ECF_DOSA_SESSION_UNCERTAIN",
          "No hubo respuesta concluyente del proveedor. No se reintenta automáticamente.",
          { uncertain: true, providerCode: result.code },
        );
      }
      // Fallo definitivo (4xx): se libera el candado para un reintento MANUAL
      // del administrador, nunca automático.
      await this.sessions.releaseRequestLease({ companyId, rnc });
      return failure(
        "ECF_DOSA_SESSION_PROVIDER_ERROR",
        "El proveedor rechazó la apertura de la sesión.",
        { providerCode: result.code },
      );
    }

    const recorded = await this.sessions.recordIssuedSession({
      companyId,
      rnc,
      sessionUrl: result.session.url,
      sessionExpiresAt: result.session.expiresAt,
      providerPostulationId: result.session.postulacionId,
    });
    if (!recorded.recorded) {
      // La sesión existe en el proveedor pero no se pudo guardar: tratarla como
      // incierta impide que se pida otra y se duplique la postulación.
      await this.sessions.markSessionUncertain({
        companyId,
        rnc,
        reasonCode: "SESSION_NOT_PERSISTED",
      });
      return failure(
        "ECF_DOSA_SESSION_NOT_PERSISTED",
        "La sesión se creó pero no se pudo guardar. Requiere revisión.",
        { uncertain: true },
      );
    }

    return {
      ok: true,
      sessionUrl: result.session.url,
      expiresAt: result.session.expiresAt,
      attemptNo: claim.attemptNo,
      providerPostulationId: result.session.postulacionId,
      reused: false,
    };
  }

  /** Espera acotada a que la petición ganadora publique la URL. */
  private async waitForWinner(
    companyId: string,
    rnc: string,
  ): Promise<DosaSessionOpenResult | null> {
    const attempts = Math.max(0, this.options.pollAttempts ?? 6);
    const delayMs = Math.max(0, this.options.pollDelayMs ?? 120);
    for (let i = 0; i < attempts; i += 1) {
      if (delayMs > 0) await delay(delayMs);
      const active = await this.sessions.findActiveSessionFor(companyId, rnc);
      const reusable = reusableUrl(active);
      if (reusable) return reusable;
      if (active && active.status === "ATTENTION") {
        return failure(
          "ECF_DOSA_SESSION_UNCERTAIN",
          "El proveedor no confirmó la sesión. No se reintenta automáticamente.",
          { uncertain: true },
        );
      }
    }
    return null;
  }
}

function reusableUrl(
  active: DosaActiveSession | null,
): DosaSessionOpenResult | null {
  if (!active || !active.sessionUrl || !active.sessionExpiresAt) return null;
  if (isExpired(active.sessionExpiresAt)) return null;
  return {
    ok: true,
    sessionUrl: active.sessionUrl,
    expiresAt: active.sessionExpiresAt,
    attemptNo: active.attemptNo,
    providerPostulationId: active.providerPostulationId ?? "",
    reused: true,
  };
}

function isExpired(expiresAt: string | null | undefined): boolean {
  if (!expiresAt) return true;
  const parsed = Date.parse(expiresAt);
  if (!Number.isFinite(parsed)) return true;
  return parsed - EXPIRY_SKEW_MS <= Date.now();
}

function failure(
  code: DosaSessionOpenFailureCode,
  message: string,
  extra: { uncertain?: boolean; providerCode?: string } = {},
): DosaSessionOpenResult {
  return { ok: false, code, message, ...extra };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeRnc(value: string): string {
  return `${value ?? ""}`.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}
