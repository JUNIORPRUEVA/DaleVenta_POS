import { Injectable } from "@nestjs/common";
import type { EcfCanonicalIdentityService } from "../../dgii/certificate/ecf-canonical-identity.service";
import type { EcfDosaSessionService } from "./ecf-dosa-session.service";

/**
 * Intención de certificación de una empresa FullPOS.
 *
 * Este es el eslabón que faltaba: registrar **antes** de abrir el asistente que
 * esta empresa quiere certificarse, con el RNC que el backend ya tiene
 * verificado. Sin este registro, un evento del proveedor no tiene a qué empresa
 * pertenecer y se rechaza (404). Con él, la correlación es por dato de servidor.
 *
 * Reglas que no se negocian:
 *
 * 1. **El RNC sale del servidor**, de la identidad canónica del expediente
 *    fiscal. Si el navegador manda un RNC, solo sirve para compararlo: si no
 *    coincide, se rechaza. Nunca se acepta como identidad.
 * 2. **Un RNC compartido no se asocia.** Si otra empresa ya declaró el mismo
 *    RNC, se bloquea la asociación automática en lugar de elegir una.
 * 3. **Solo se reutiliza la tabla de sesiones existente.** No hay un segundo
 *    modelo, ni una segunda sesión, ni un asistente paralelo.
 * 4. **Esto no vincula ni activa nada.** Crea una sesión candidata; la
 *    vinculación real sigue esperando la autenticidad verificable del webhook.
 */
export type DosaIntentRejection =
  | "COMPANY_RNC_NOT_VERIFIED"
  | "RNC_DOES_NOT_MATCH_COMPANY_IDENTITY"
  | "AMBIGUOUS_RNC"
  | "SESSION_CLAIM_FAILED";

export type DosaIntentResult =
  | {
      ok: true;
      companyId: string;
      rnc: string;
      sessionId: string;
      attemptNo: number;
      created: boolean;
      /** Siempre `false`: registrar una intención no habilita emisión. */
      fiscalAuthorizationGranted: false;
    }
  | { ok: false; reason: DosaIntentRejection; detail?: string };

/** ¿Cuántas otras empresas comparten este RNC? */
export interface DosaRncOwnersReader {
  countOtherCompaniesWithRnc(input: {
    rnc: string;
    excludingCompanyId: string;
  }): Promise<number>;
}

export const ECF_DOSA_RNC_OWNERS = Symbol("ECF_DOSA_RNC_OWNERS");

export interface DosaRawRncClient {
  $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T>;
}

/**
 * Cuenta empresas distintas con ese RNC, combinando las dos fuentes donde el
 * backend guarda el RNC de una empresa:
 *
 * * `app_config.rnc` — dato fiscal con el que se emite.
 * * `ecf_dosa_certification_sessions.rnc` — intentos de certificación ya
 *   registrados.
 *
 * Se normaliza (solo alfanumérico, mayúsculas) para que `1-33-306-001` y
 * `133306001` cuenten como el mismo RNC.
 */
export class PrismaDosaRncOwnersReader implements DosaRncOwnersReader {
  constructor(private readonly prisma: DosaRawRncClient) {}

  async countOtherCompaniesWithRnc(input: {
    rnc: string;
    excludingCompanyId: string;
  }): Promise<number> {
    const normalized = normalizeRnc(input.rnc);
    if (normalized.length === 0) return 0;
    const rows = await this.prisma.$queryRaw<Array<{ n: number | string }>>`
      SELECT count(*)::int AS "n"
        FROM (
          SELECT c."company_id" AS company_id
            FROM "app_config" c
           WHERE upper(regexp_replace(coalesce(c."rnc", ''), '[^0-9A-Za-z]', '', 'g')) = ${normalized}
          UNION
          SELECT s."company_id" AS company_id
            FROM "ecf_dosa_certification_sessions" s
           WHERE upper(regexp_replace(coalesce(s."rnc", ''), '[^0-9A-Za-z]', '', 'g')) = ${normalized}
        ) AS owners
       WHERE owners.company_id <> ${input.excludingCompanyId}::uuid
    `;
    const value = rows[0]?.n ?? 0;
    return typeof value === "number" ? value : Number.parseInt(`${value}`, 10) || 0;
  }
}

export function normalizeRnc(value: string): string {
  return `${value ?? ""}`.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}

@Injectable()
export class DosaCertificationIntentService {
  constructor(
    private readonly identity: EcfCanonicalIdentityService,
    private readonly sessions: EcfDosaSessionService,
    private readonly rncOwners: DosaRncOwnersReader,
  ) {}

  async register(input: {
    companyId: string;
    userId?: string | null;
    /** RNC que el navegador cree conocer. Solo se usa para comparar. */
    rncFromClient?: string | null;
  }): Promise<DosaIntentResult> {
    const target = await this.resolveTarget(input);
    if (!target.ok) return target;

    const claim = await this.sessions.claim({
      companyId: input.companyId,
      rnc: target.rnc,
      createdByUserId: input.userId ?? null,
    });
    if (!claim.ok) {
      return {
        ok: false,
        reason: "SESSION_CLAIM_FAILED",
        detail: (claim as { reason?: string }).reason,
      };
    }

    return {
      ok: true,
      companyId: input.companyId,
      rnc: target.rnc,
      sessionId: claim.id,
      attemptNo: claim.attemptNo,
      created: claim.created,
      fiscalAuthorizationGranted: false,
    };
  }

  /**
   * Comprueba si la intención podría registrarse, **sin crear nada**.
   * Sirve para el endpoint de estado y para explicar al administrador qué falta.
   */
  async preview(input: {
    companyId: string;
    rncFromClient?: string | null;
  }): Promise<
    | { ok: true; rnc: string }
    | { ok: false; reason: DosaIntentRejection; detail?: string }
  > {
    return this.resolveTarget(input);
  }

  /** Estado interno de la preparación. Nunca devuelve secretos. */
  async describe(input: { companyId: string }): Promise<{
    canonicalRnc: string | null;
    canonicalSource: string | null;
    session: {
      id: string;
      status: string;
      attemptNo: number;
      sessionUrl: string | null;
    } | null;
  }> {
    const canonical = await this.identity.resolve(input.companyId);
    const rnc = normalizeRnc(canonical.taxId ?? "");
    if (rnc.length === 0) {
      return { canonicalRnc: null, canonicalSource: canonical.source ?? null, session: null };
    }
    const active = await this.sessions.findActiveFor(input.companyId, rnc);
    return {
      canonicalRnc: rnc,
      canonicalSource: canonical.source ?? null,
      session:
        active && active.ok
          ? {
              id: active.id,
              status: active.status,
              attemptNo: active.attemptNo,
              sessionUrl: active.sessionUrl,
            }
          : null,
    };
  }

  /**
   * Comprobaciones comunes a `register` y `preview`. El RNC siempre sale del
   * servidor; el del navegador solo se compara.
   */
  private async resolveTarget(input: {
    companyId: string;
    rncFromClient?: string | null;
  }): Promise<
    | { ok: true; rnc: string }
    | { ok: false; reason: DosaIntentRejection; detail?: string }
  > {
    const canonical = await this.identity.resolve(input.companyId);
    const serverRnc = normalizeRnc(canonical.taxId ?? "");
    if (serverRnc.length === 0) {
      return { ok: false, reason: "COMPANY_RNC_NOT_VERIFIED" };
    }

    const clientRnc = normalizeRnc(input.rncFromClient ?? "");
    if (clientRnc.length > 0 && clientRnc !== serverRnc) {
      // El navegador no manda: si dice otro RNC, se rechaza el intento entero.
      return { ok: false, reason: "RNC_DOES_NOT_MATCH_COMPANY_IDENTITY" };
    }

    const others = await this.rncOwners.countOtherCompaniesWithRnc({
      rnc: serverRnc,
      excludingCompanyId: input.companyId,
    });
    if (others > 0) {
      // Varias empresas comparten RNC: no se elige una, se bloquea.
      return { ok: false, reason: "AMBIGUOUS_RNC", detail: `${others}` };
    }

    return { ok: true, rnc: serverRnc };
  }
}
