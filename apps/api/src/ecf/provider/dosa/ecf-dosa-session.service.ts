import { Inject, Injectable } from "@nestjs/common";

/** Estado de la sesión, alineado con `EcfDosaSessionStatus` de Prisma. */
export type DosaSessionStatus =
  | "NOT_STARTED"
  | "RUNNING"
  | "ATTENTION"
  | "COMPLETED"
  | "FAILED"
  | "CANCELLED"
  | "EXPIRED";

/** Estados TERMINALES: liberan la clave activa para permitir otro intento. */
export type DosaSessionClosedStatus =
  | "COMPLETED"
  | "FAILED"
  | "CANCELLED"
  | "EXPIRED";

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
  /**
   * Opcional: solo la implementación real (Prisma) la tiene.
   *
   * Es necesaria para la vinculación por `postulacion_id`, porque la
   * exclusividad concurrente NO se puede garantizar con una sola sentencia: el
   * bloqueo y la comprobación tienen que ir en la misma transacción.
   */
  $transaction?<T>(fn: (tx: DosaSessionStore) => Promise<T>): Promise<T>;
}

export const ECF_DOSA_SESSION_STORE = Symbol("ECF_DOSA_SESSION_STORE");

export type DosaSessionClaim =
  | {
      ok: true;
      id: string;
      status: DosaSessionStatus;
      created: boolean;
      sessionUrl: string | null;
      attemptNo: number;
    }
  | { ok: false; reason: "MISSING_COMPANY" | "MISSING_RNC" };

type ClaimRow = {
  id: string;
  status: string;
  session_url: string | null;
  attempt_no: number;
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

  /**
   * Crea o recupera el intento EN CURSO de la empresa+RNC. Nunca crea dos a la
   * vez: la clave activa es única en la base de datos.
   *
   * Si el intento anterior terminó (COMPLETED/FAILED/CANCELLED/EXPIRED), su
   * `active_key` es NULL y este método crea un intento NUEVO con
   * `attempt_no + 1`, conservando el anterior como historial.
   */
  async claim(input: {
    companyId: string;
    rnc: string;
    createdByUserId?: string | null;
  }): Promise<DosaSessionClaim> {
    const companyId = (input.companyId ?? "").trim();
    if (!companyId) return { ok: false, reason: "MISSING_COMPANY" };

    const rnc = normalizeRnc(input.rnc);
    if (!rnc) return { ok: false, reason: "MISSING_RNC" };

    const activeKey = `${companyId}:${rnc}`;

    // Competición posible: dos peticiones sin intento activo calculan el mismo
    // `attempt_no`. Una inserta; la otra choca contra el índice
    // (company_id, rnc, attempt_no). Entonces:
    //   1. si la ganadora ya confirmó, se devuelve SU fila (misma sesión);
    //   2. si aún no es visible, se espera un poco y se reintenta.
    // Es un claim idempotente, no un reintento fiscal: no reenvía nada.
    let lastError: unknown;
    for (let attempt = 0; attempt < 4; attempt += 1) {
      try {
        const rows = await this.store.$queryRaw<ClaimRow[]>`
          INSERT INTO "ecf_dosa_certification_sessions"
            ("id", "company_id", "rnc", "attempt_no", "active_key",
             "created_by_user_id", "created_at", "updated_at")
          VALUES
            (gen_random_uuid(), ${companyId}::uuid, ${rnc},
             (SELECT COALESCE(MAX("attempt_no"), 0) + 1
                FROM "ecf_dosa_certification_sessions"
               WHERE "company_id" = ${companyId}::uuid AND "rnc" = ${rnc}),
             ${activeKey},
             NULLIF(${input.createdByUserId ?? ""}, '')::uuid, NOW(), NOW())
          ON CONFLICT ("active_key") DO UPDATE SET "updated_at" = NOW()
          RETURNING "id", "status", "session_url", "attempt_no", ("xmax" = 0) AS "created"
        `;
        return toClaim(rows[0]);
      } catch (error) {
        if (!isUniqueViolation(error)) throw error;
        lastError = error;
        const winner = await this.findActive(companyId, rnc);
        if (winner) return winner;
        await delay(15 + attempt * 15);
      }
    }
    throw lastError;
  }

  /**
   * Indica si la empresa/RNC tiene un expediente reconciliado en su historial.
   *
   * Es una lectura pura: no crea, no cierra y no actualiza nada. La apertura
   * automática la usa para bloquear transiciones sobre expedientes históricos.
   */
  async hasReconciledIntent(
    companyId: string,
    rnc: string,
  ): Promise<boolean> {
    const company = `${companyId ?? ""}`.trim();
    const normalized = normalizeRnc(rnc);
    if (!company || !normalized) return false;
    const rows = await this.store.$queryRaw<Array<{ found: number }>>`
      SELECT 1 AS "found"
        FROM "ecf_dosa_certification_sessions" s
        JOIN "ecf_audit_logs" a
          ON a."company_id" = s."company_id"
         AND a."target_type" = 'DOSA_CERTIFICATION_INTENT'
         AND a."target_id" = s."id"
         AND a."action" = 'INTENT_PROVIDER_RECONCILED'
       WHERE s."company_id" = ${company}::uuid
         AND s."rnc" = ${normalized}
       LIMIT 1
    `;
    return rows.length === 1;
  }

  /**
   * Lectura del intento EN CURSO para diagnóstico (endpoint de estado).
   * No crea nada y no cambia nada: si no hay intento, devuelve `null`.
   */
  async findActiveFor(
    companyId: string,
    rnc: string,
  ): Promise<DosaSessionClaim | null> {
    const company = `${companyId ?? ""}`.trim();
    const normalized = normalizeRnc(rnc);
    if (!company || !normalized) return null;
    return this.findActive(company, normalized);
  }

  /** Sesión EN CURSO de la empresa+RNC, si ya existe. */
  private async findActive(
    companyId: string,
    rnc: string,
  ): Promise<DosaSessionClaim | null> {
    const rows = await this.store.$queryRaw<ClaimRow[]>`
      SELECT "id", "status", "session_url", "attempt_no", FALSE AS "created"
        FROM "ecf_dosa_certification_sessions"
       WHERE "active_key" = ${`${companyId}:${rnc}`}
       LIMIT 1
    `;
    return rows.length === 1 ? toClaim(rows[0]) : null;
  }

  /**
   * Cierra el intento EN CURSO con un estado terminal y libera la clave activa.
   *
   * Solo se pueden cerrar estados terminales: no existe un camino para marcar
   * `COMPLETED` desde un evento del navegador.
   */
  async close(input: {
    companyId: string;
    rnc: string;
    status: DosaSessionClosedStatus;
  }): Promise<{ closed: boolean }> {
    // Validación en EJECUCIÓN, no solo de tipos: cerrar con un estado en curso
    // dejaría una sesión "activa" sin clave activa y rompería el invariante.
    if (!TERMINAL_STATUSES.has(input.status)) {
      throw new Error("ECF_DOSA_SESSION_INVALID_CLOSE_STATUS");
    }
    const companyId = (input.companyId ?? "").trim();
    const rnc = normalizeRnc(input.rnc);
    if (!companyId || !rnc) return { closed: false };

    const activeKey = `${companyId}:${rnc}`;
    const rows = await this.store.$queryRaw<{ id: string }[]>`
      UPDATE "ecf_dosa_certification_sessions"
         SET "status" = ${input.status}::"EcfDosaSessionStatus",
             "active_key" = NULL,
             "closed_at" = NOW(),
             "updated_at" = NOW()
       WHERE "company_id" = ${companyId}::uuid
         AND "rnc" = ${rnc}
         AND "active_key" = ${activeKey}
      RETURNING "id"
    `;
    return { closed: rows.length === 1 };
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
         AND "active_key" = ${`${companyId}:${rnc}`}
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
         AND "active_key" = ${`${companyId}:${rnc}`}
      RETURNING "id"
    `;
    return { updated: rows.length === 1 };
  }

  /**
   * Vincula el `postulacion_id` que reporta el PROVEEDOR con el intento activo.
   *
   * **Por qué no basta un `NOT EXISTS`**
   *
   * Una sola sentencia con `NOT EXISTS` NO garantiza exclusividad concurrente:
   * bajo `READ COMMITTED` la foto se toma al empezar la sentencia, así que dos
   * transacciones simultáneas pueden comprobar «no existe» antes de que la otra
   * confirme su escritura, y ambas escribir. Las filas son distintas (dos
   * sesiones de dos empresas), así que tampoco hay conflicto de escritura que
   * PostgreSQL resuelva solo: es *write skew* clásico.
   *
   * **Estrategia**
   *
   * 1. Se abre una transacción y se toma un bloqueo de asesoría exclusivo sobre
   *    el `postulacion_id`. Dos vinculaciones del MISMO identificador se
   *    serializan; las de identificadores distintos no se estorban.
   * 2. Ya con el bloqueo, la comprobación se ejecuta en una sentencia NUEVA, con
   *    foto nueva, así que ve lo que la otra transacción confirmó.
   * 3. El bloqueo es `xact`: se libera solo al cerrar la transacción, incluso si
   *    hay error. No queda nada tomado si el proceso muere.
   *
   * **Por qué no un UNIQUE**
   *
   * El alcance de unicidad de `postulacion_id` no está documentado por el
   * proveedor. Para una misma empresa podría ser legítimo reutilizar el mismo
   * identificador en un reintento o en la recuperación de un intento anterior.
   * Imponer un UNIQUE global sin ese dato sería inventar una regla de negocio;
   * aquí se serializa y se decide con la regla conservadora (un identificador,
   * una empresa), dejando la restricción declarativa para cuando el proveedor
   * confirme el alcance.
   *
   * Condiciones, todas dentro de la misma sentencia:
   *
   * * Solo el intento ACTIVO (`active_key`) de esa empresa y ese RNC.
   * * Solo si aún no tiene identificador, o si es el MISMO: un evento fuera de
   *   orden no reescribe el vínculo ni alterna entre identificadores.
   * * Nunca si otra empresa ya lo tiene.
   *
   * Si no hay intento activo no se crea nada: el evento queda registrado con su
   * `postulacion_id` y la vinculación queda pendiente de reconciliación.
   */
  async bindProviderPostulation(input: {
    companyId: string;
    rnc: string;
    providerPostulationId: string;
  }): Promise<{ bound: boolean }> {
    const companyId = (input.companyId ?? "").trim();
    const rnc = normalizeRnc(input.rnc);
    const postulationId = (input.providerPostulationId ?? "").trim();
    if (!companyId || !rnc || !postulationId) return { bound: false };

    const id = postulationId.slice(0, 128);
    const runTransaction = this.store.$transaction?.bind(this.store);

    if (typeof runTransaction === "function") {
      return runTransaction(async (tx: DosaSessionStore) => {
        // Serializa por identificador, con espacio de nombres propio. El
        // envoltorio devuelve un entero porque `pg_advisory_xact_lock` devuelve
        // `void` y el driver no sabe deserializarlo.
        await tx.$queryRaw`
          SELECT 1 AS "ok"
            FROM (SELECT pg_advisory_xact_lock(
                    hashtext('fullpos:dosa:postulacion'),
                    hashtext(${id})
                  )) AS "bloqueo"
        `;
        return this.bindWithin(tx, { companyId, rnc, id });
      });
    }

    // Sin transacción (dobles de prueba) se mantiene la comprobación, pero NO se
    // puede afirmar exclusividad concurrente. La implementación real siempre la
    // tiene, así que este camino no se usa en producción.
    return this.bindWithin(this.store, { companyId, rnc, id });
  }

  private async bindWithin(
    store: DosaSessionStore,
    input: { companyId: string; rnc: string; id: string },
  ): Promise<{ bound: boolean }> {
    const rows = await store.$queryRaw<{ id: string }[]>`
      UPDATE "ecf_dosa_certification_sessions"
         SET "provider_postulation_id" = ${input.id},
             "provider_confirmed_at" = NOW(),
             "updated_at" = NOW()
       WHERE "company_id" = ${input.companyId}::uuid
         AND "rnc" = ${input.rnc}
         AND "active_key" = ${`${input.companyId}:${input.rnc}`}
         AND ("provider_postulation_id" IS NULL OR "provider_postulation_id" = ${input.id})
         AND NOT EXISTS (
           SELECT 1 FROM "ecf_dosa_certification_sessions" otro
            WHERE otro."provider_postulation_id" = ${input.id}
              AND otro."company_id" <> ${input.companyId}::uuid
         )
      RETURNING "id"
    `;
    return { bound: rows.length === 1 };
  }

  /**
   * Lectura del intento activo con los metadatos de la sesión emitida.
   *
   * Se usa para REUTILIZAR una sesión vigente sin volver a llamar al proveedor
   * y para detectar una caducada. No crea ni cambia nada.
   */
  async findActiveSessionFor(
    companyId: string,
    rnc: string,
  ): Promise<DosaActiveSession | null> {
    const company = `${companyId ?? ""}`.trim();
    const normalized = normalizeRnc(rnc);
    if (!company || !normalized) return null;
    const rows = await this.store.$queryRaw<
      Array<{
        id: string;
        status: string;
        attempt_no: number;
        session_url: string | null;
        session_expires_at: Date | string | null;
        provider_postulation_id: string | null;
      }>
    >`
      SELECT "id", "status", "attempt_no", "session_url",
             "session_expires_at", "provider_postulation_id"
        FROM "ecf_dosa_certification_sessions"
       WHERE "active_key" = ${`${company}:${normalized}`}
       LIMIT 1
    `;
    const row = rows[0];
    if (!row) return null;
    return {
      id: row.id,
      status: row.status as DosaSessionStatus,
      attemptNo: row.attempt_no,
      sessionUrl: row.session_url,
      sessionExpiresAt: toIsoOrNull(row.session_expires_at),
      providerPostulationId: row.provider_postulation_id,
    };
  }

  /**
   * Reserva temporal de la petición en vuelo.
   *
   * Un único `UPDATE` condicional actúa como candado por empresa+RNC: solo la
   * petición que encuentra la reserva libre (o vencida) la obtiene. Las demás
   * no llaman al proveedor, así que un doble clic o dos instancias del backend
   * no pueden crear dos sesiones. La reserva vence sola: si el proceso muere,
   * la siguiente petición puede recuperarla.
   */
  async acquireRequestLease(input: {
    companyId: string;
    rnc: string;
    leaseMs: number;
  }): Promise<{ acquired: boolean; sessionUrl: string | null; sessionExpiresAt: string | null }> {
    const company = `${input.companyId ?? ""}`.trim();
    const rnc = normalizeRnc(input.rnc);
    if (!company || !rnc) {
      return { acquired: false, sessionUrl: null, sessionExpiresAt: null };
    }
    const leaseSeconds = Math.max(5, Math.ceil(input.leaseMs / 1000));
    const rows = await this.store.$queryRaw<
      Array<{ session_url: string | null; session_expires_at: Date | string | null }>
    >`
      UPDATE "ecf_dosa_certification_sessions"
         SET "session_lease_until" = NOW() + (${`${leaseSeconds}`} || ' seconds')::interval,
             "updated_at" = NOW()
       WHERE "company_id" = ${company}::uuid
         AND "rnc" = ${rnc}
         AND "active_key" = ${`${company}:${rnc}`}
         AND ("session_lease_until" IS NULL OR "session_lease_until" < NOW())
      RETURNING "session_url", "session_expires_at"
    `;
    const row = rows[0];
    return {
      acquired: rows.length === 1,
      sessionUrl: row?.session_url ?? null,
      sessionExpiresAt: toIsoOrNull(row?.session_expires_at ?? null),
    };
  }

  /** Libera la reserva sin cambiar el estado. La deja disponible para reintento. */
  async releaseRequestLease(input: {
    companyId: string;
    rnc: string;
  }): Promise<void> {
    const company = `${input.companyId ?? ""}`.trim();
    const rnc = normalizeRnc(input.rnc);
    if (!company || !rnc) return;
    await this.store.$queryRaw`
      UPDATE "ecf_dosa_certification_sessions"
         SET "session_lease_until" = NULL,
             "updated_at" = NOW()
       WHERE "company_id" = ${company}::uuid
         AND "rnc" = ${rnc}
         AND "active_key" = ${`${company}:${rnc}`}
    `;
  }

  /**
   * Guarda la sesión emitida por el proveedor en el intento activo.
   *
   * Solo escribe el intento ACTIVO de ESA empresa y ese RNC. La URL es una
   * capacidad del proveedor: se persiste para poder reanudar y **nunca** se
   * registra en logs.
   */
  async recordIssuedSession(input: {
    companyId: string;
    rnc: string;
    sessionUrl: string;
    sessionExpiresAt: string;
    providerPostulationId: string;
  }): Promise<{ recorded: boolean }> {
    const company = `${input.companyId ?? ""}`.trim();
    const rnc = normalizeRnc(input.rnc);
    const url = `${input.sessionUrl ?? ""}`.trim();
    const postulation = `${input.providerPostulationId ?? ""}`.trim();
    if (!company || !rnc || !url || !postulation) return { recorded: false };
    const rows = await this.store.$queryRaw<{ id: string }[]>`
      UPDATE "ecf_dosa_certification_sessions"
         SET "session_url" = ${url},
             "session_expires_at" = ${input.sessionExpiresAt}::timestamptz,
             "provider_postulation_id" = ${postulation.slice(0, 128)},
             "session_issued_at" = NOW(),
             "session_lease_until" = NULL,
             "status" = 'RUNNING',
             "updated_at" = NOW()
       WHERE "company_id" = ${company}::uuid
         AND "rnc" = ${rnc}
         AND "active_key" = ${`${company}:${rnc}`}
      RETURNING "id"
    `;
    return { recorded: rows.length === 1 };
  }

  /**
   * Marca el intento como INCIERTO cuando el proveedor no respondió de forma
   * concluyente (timeout o 5xx).
   *
   * No se reintenta automáticamente: DOSA pudo haber creado la sesión. Pasa a
   * `ATTENTION`, conserva la clave activa y exige intervención explícita.
   */
  async markSessionUncertain(input: {
    companyId: string;
    rnc: string;
    reasonCode: string;
  }): Promise<{ updated: boolean }> {
    const company = `${input.companyId ?? ""}`.trim();
    const rnc = normalizeRnc(input.rnc);
    const code = `${input.reasonCode ?? ""}`.trim().slice(0, 64);
    if (!company || !rnc) return { updated: false };
    const rows = await this.store.$queryRaw<{ id: string }[]>`
      UPDATE "ecf_dosa_certification_sessions"
         SET "status" = 'ATTENTION',
             "session_lease_until" = NULL,
             "last_event_type" = ${code || "PROVIDER_UNCERTAIN"},
             "last_event_at" = NOW(),
             "updated_at" = NOW()
       WHERE "company_id" = ${company}::uuid
         AND "rnc" = ${rnc}
         AND "active_key" = ${`${company}:${rnc}`}
      RETURNING "id"
    `;
    return { updated: rows.length === 1 };
  }
}

export type DosaActiveSession = {
  id: string;
  status: DosaSessionStatus;
  attemptNo: number;
  sessionUrl: string | null;
  sessionExpiresAt: string | null;
  providerPostulationId: string | null;
};

function toIsoOrNull(value: Date | string | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

/** Traduce la fila del RETURNING al contrato público del servicio. */
function toClaim(row: ClaimRow): DosaSessionClaim {
  return {
    ok: true,
    id: row.id,
    status: row.status as DosaSessionStatus,
    created: row.created === true,
    sessionUrl: row.session_url,
    attemptNo: row.attempt_no,
  };
}

/** Violación de índice único. Prisma la reporta como P2010 con `meta.code` 23505. */
function isUniqueViolation(error: unknown): boolean {
  const candidate = error as
    | { code?: unknown; meta?: { code?: unknown } }
    | null
    | undefined;
  const direct = candidate?.code;
  if (direct === "P2002" || direct === "23505") return true;
  const nested = candidate?.meta?.code;
  return nested === "P2002" || nested === "23505";
}

/** Estados que liberan la clave activa. Debe coincidir con el enum de Prisma. */
const TERMINAL_STATUSES = new Set<string>([
  "COMPLETED",
  "FAILED",
  "CANCELLED",
  "EXPIRED",
]);

/** Espera acotada antes de reintentar un claim que chocó con otra petición. */
function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Igual que en el resto del módulo: quita separadores, no completa dígitos. */
function normalizeRnc(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
  return cleaned.length > 0 && cleaned.length <= 32 ? cleaned : null;
}
