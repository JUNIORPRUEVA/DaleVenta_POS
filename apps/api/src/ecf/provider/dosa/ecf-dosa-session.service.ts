import { Inject, Injectable } from "@nestjs/common";

/** Estado de la sesión, alineado con `EcfDosaSessionStatus` de Prisma. */
export type DosaSessionStatus =
  | "NOT_STARTED"
  | "RUNNING"
  | "ATTENTION"
  | "COMPLETED"
  | "FAILED";

/**
 * Forma MÍNIMA del cliente que este servicio necesita.
 *
 * Es estrecha a propósito: permite probar la lógica con un doble sin base de
 * datos, y deja claro que el servicio no hace nada más que SQL parametrizado.
 */
export interface DosaSessionStore {
  $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T>;
}

export const ECF_DOSA_SESSION_STORE = Symbol("ECF_DOSA_SESSION_STORE");

export type DosaSessionClaim =
  | {
      ok: true;
      id: string;
      status: DosaSessionStatus;
      created: boolean;
      sessionUrl: string | null;
    }
  | { ok: false; reason: "MISSING_COMPANY" | "MISSING_RNC" };

type ClaimRow = {
  id: string;
  status: string;
  session_url: string | null;
  created: boolean;
};

/**
 * Persistencia de la sesión de certificación DOSA.
 *
 * El control de duplicados es **transaccional en la base de datos**: un
 * `INSERT ... ON CONFLICT (company_id, rnc)` sobre un índice único. No depende
 * de ninguna clave generada en Flutter, así que dos pestañas, dos dispositivos
 * o un reintento del navegador no pueden crear dos sesiones.
 *
 * Lo que este servicio NO hace, por diseño:
 * * No pide sesiones a DOSA. Ese contrato (`POST /api/certificacion/sesiones`)
 *   no está documentado y no se inventa.
 * * Un evento del navegador solo escribe `last_event_type`/`last_event_at`.
 *   No cambia `status` ni `provider_confirmed_at`.
 * * Solo `applyProviderConfirmation` marca confirmación, y está pensado para
 *   llamarse desde el backend tras reconciliar con el proveedor.
 */
@Injectable()
export class EcfDosaSessionService {
  constructor(
    @Inject(ECF_DOSA_SESSION_STORE) private readonly store: DosaSessionStore,
  ) {}

  /** Crea o recupera la fila de la empresa+RNC. Nunca crea una segunda. */
  async claim(input: {
    companyId: string;
    rnc: string;
    createdByUserId?: string | null;
  }): Promise<DosaSessionClaim> {
    const companyId = (input.companyId ?? "").trim();
    if (!companyId) return { ok: false, reason: "MISSING_COMPANY" };

    const rnc = normalizeRnc(input.rnc);
    if (!rnc) return { ok: false, reason: "MISSING_RNC" };

    const rows = await this.store.$queryRaw<ClaimRow[]>`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id", "company_id", "rnc", "created_by_user_id", "created_at", "updated_at")
      VALUES
        (gen_random_uuid(), ${companyId}::uuid, ${rnc},
         NULLIF(${input.createdByUserId ?? ""}, '')::uuid, NOW(), NOW())
      ON CONFLICT ("company_id", "rnc") DO UPDATE SET "updated_at" = NOW()
      RETURNING "id", "status", "session_url", ("xmax" = 0) AS "created"
    `;

    const row = rows[0];
    return {
      ok: true,
      id: row.id,
      status: row.status as DosaSessionStatus,
      created: row.created === true,
      sessionUrl: row.session_url,
    };
  }

  /**
   * Registra un evento del COMPONENTE como pista.
   *
   * No modifica `status` ni `provider_confirmed_at`: el navegador no es fuente de
   * verdad fiscal. Si la fila no existe, no se crea nada.
   */
  async recordEventHint(input: {
    companyId: string;
    rnc: string;
    eventType: string;
  }): Promise<{ updated: boolean }> {
    const companyId = (input.companyId ?? "").trim();
    const rnc = normalizeRnc(input.rnc);
    const eventType = (input.eventType ?? "").trim();
    if (!companyId || !rnc || !eventType) return { updated: false };

    const rows = await this.store.$queryRaw<{ id: string }[]>`
      UPDATE "ecf_dosa_certification_sessions"
         SET "last_event_type" = ${eventType.slice(0, 64)},
             "last_event_at" = NOW(),
             "updated_at" = NOW()
       WHERE "company_id" = ${companyId}::uuid
         AND "rnc" = ${rnc}
      RETURNING "id"
    `;
    return { updated: rows.length === 1 };
  }

  /**
   * Confirma con el proveedor la postulación. Uso EXCLUSIVO del backend.
   *
   * Aun así no acredita aprobación de la DGII: solo deja constancia de que el
   * proveedor reportó esa postulación, con su marca de tiempo.
   */
  async applyProviderConfirmation(input: {
    companyId: string;
    rnc: string;
    providerPostulationId: string;
  }): Promise<{ updated: boolean }> {
    const companyId = (input.companyId ?? "").trim();
    const rnc = normalizeRnc(input.rnc);
    const postulationId = (input.providerPostulationId ?? "").trim();
    if (!companyId || !rnc || !postulationId) return { updated: false };

    const rows = await this.store.$queryRaw<{ id: string }[]>`
      UPDATE "ecf_dosa_certification_sessions"
         SET "provider_postulation_id" = ${postulationId.slice(0, 128)},
             "provider_confirmed_at" = NOW(),
             "updated_at" = NOW()
       WHERE "company_id" = ${companyId}::uuid
         AND "rnc" = ${rnc}
      RETURNING "id"
    `;
    return { updated: rows.length === 1 };
  }
}

/** Igual que en el resto del módulo: quita separadores, no completa dígitos. */
function normalizeRnc(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
  return cleaned.length > 0 && cleaned.length <= 32 ? cleaned : null;
}
