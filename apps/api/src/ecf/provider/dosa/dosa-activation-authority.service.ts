import type { DosaRawClient } from "./dosa-credential.service";

/**
 * Evidencia de activación fiscal, **leída de datos persistidos**.
 *
 * Este módulo existe porque un booleano que envía el llamador no es una
 * autorización: es una afirmación. La activación de facturación electrónica
 * exige que la evidencia esté en la base de datos, con su origen y su actor.
 *
 * De dónde sale cada cosa (tablas que ya existían antes de DOSA):
 *
 * * **Intento vigente** — la fila de `ecf_dosa_certification_sessions` con el
 *   `attempt_no` más alto para esa empresa y ese RNC. Es el único intento que
 *   cuenta: los anteriores son historial, no evidencia.
 * * **Vínculo RNC ↔ postulación** — el `provider_postulation_id` de ese intento.
 * * **Confirmación del proveedor** — un evento en `ecf_dosa_webhook_events`
 *   **con el mismo `postulacion_id`**, `estado_certificacion = 'finalizado'`,
 *   firma que no sea `BLOCKED`, ya procesado (`processing_state = 'COMPLETE'`) y
 *   recibido **después** de que empezara el intento.
 * * **Aprobación DGII** — `ecf_dgii_habilitations` con estado `APPROVED`,
 *   `authorization_source = 'DGII_OFFICIAL_RECORD'` y `authorized_at` posterior
 *   al inicio del intento vigente. Una declaración manual del operador
 *   (`MANUAL_OPERATOR_DECLARATION`) **no** cuenta.
 * * **Autorización administrativa** — la **última** decisión administrativa
 *   (`DGII_AUTHORIZATION_RECORDED` / `DGII_AUTHORIZATION_REVOKED`) registrada
 *   con actor real. No se comparan cantidades: si la última decisión es una
 *   revocación, no hay autorización aunque haya cien registros anteriores. El
 *   último registro autorizante debe ser posterior al inicio del intento.
 *
 * Por qué se encadena todo esto: contar sesiones y eventos por separado permite
 * que un evento de **otra** postulación (o de un intento abandonado) dé por
 * confirmada la empresa. La cadena empresa → RNC → intento → `postulacion_id` →
 * evidencia → aprobación DGII → autorización administrativa no admite saltos.
 */

export type DosaActivationEvidence = {
  /** El RNC está vinculado a esta empresa por una sesión de servidor. */
  identityLinked: boolean;
  /** El intento vigente tiene postulación asignada por el proveedor. */
  postulationBound: boolean;
  providerConfirmed: boolean;
  dgiiApproved: boolean;
  administrativeAuthorized: boolean;
  /** Trazabilidad legible. Sin secretos. */
  details: {
    /** Número del intento vigente (el más alto), `null` si no hay ninguno. */
    attemptNo: number | null;
    /** Inicio del intento vigente, en ISO. */
    attemptStartedAt: string | null;
    /** `postulacion_id` del intento vigente. */
    postulacionId: string | null;
    linkedSessions: number;
    authenticatedProviderEvents: number;
    /** Eventos autenticados de esta empresa que pertenecen a OTRA postulación. */
    providerEventsForOtherPostulations: number;
    dgiiState: string | null;
    dgiiSource: string | null;
    dgiiAuthorizedAt: string | null;
    /** Última decisión administrativa válida (con actor real). */
    lastDecision: "RECORDED" | "REVOKED" | null;
    lastDecisionAt: string | null;
    /** Fecha del último registro autorizante con actor real. */
    lastRecordedAt: string | null;
    authorizationsRecorded: number;
    authorizationsRevoked: number;
  };
};

export interface DosaAuthorizationReader {
  read(input: { companyId: string; rnc: string }): Promise<DosaActivationEvidence>;
}

export const ECF_DOSA_AUTHORIZATION = Symbol("ECF_DOSA_AUTHORIZATION");

type EvidenceRow = {
  attempt_no: number | null;
  attempt_created_at: Date | null;
  postulacion_id: string | null;
  linked_sessions: string | number;
  provider_events: string | number;
  foreign_events: string | number;
  dgii_state: string | null;
  dgii_source: string | null;
  dgii_authorized_at: Date | null;
  last_decision: string | null;
  last_decision_at: Date | null;
  last_recorded_at: Date | null;
  authorizations_recorded: string | number;
  authorizations_revoked: string | number;
};

/** RNC normalizado igual que en el resto del módulo. */
function normalizeRnc(value: string): string {
  return (value ?? "").replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}

function toCount(value: string | number | null | undefined): number {
  const parsed = typeof value === "number" ? value : Number.parseInt(`${value ?? 0}`, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function toDate(value: Date | string | null | undefined): Date | null {
  if (value === null || value === undefined) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function iso(value: Date | null): string | null {
  return value === null ? null : value.toISOString();
}

/**
 * `true` solo si `candidate` existe y no es anterior a `reference`.
 * Sin intento vigente no hay nada que sea posterior: devuelve `false`.
 */
function notBefore(candidate: Date | null, reference: Date | null): boolean {
  if (candidate === null || reference === null) return false;
  return candidate.getTime() >= reference.getTime();
}

export class PrismaDosaAuthorizationReader implements DosaAuthorizationReader {
  constructor(private readonly prisma: DosaRawClient) {}

  async read(input: {
    companyId: string;
    rnc: string;
  }): Promise<DosaActivationEvidence> {
    const rnc = normalizeRnc(input.rnc);
    const rows = await this.prisma.$queryRaw<EvidenceRow[]>`
      WITH attempt AS (
        SELECT s."attempt_no", s."provider_postulation_id", s."created_at"
          FROM "ecf_dosa_certification_sessions" s
         WHERE s."company_id" = ${input.companyId}::uuid
           AND s."rnc" = ${rnc}
         ORDER BY s."attempt_no" DESC, s."created_at" DESC
         LIMIT 1
      )
      SELECT
        (SELECT attempt."attempt_no" FROM attempt) AS attempt_no,
        (SELECT attempt."created_at" FROM attempt) AS attempt_created_at,
        (SELECT attempt."provider_postulation_id" FROM attempt) AS postulacion_id,
        (SELECT count(*)
           FROM "ecf_dosa_certification_sessions" s
          WHERE s."company_id" = ${input.companyId}::uuid
            AND s."rnc" = ${rnc}) AS linked_sessions,
        (SELECT count(*)
           FROM "ecf_dosa_webhook_events" e
           JOIN attempt a ON true
          WHERE e."company_id" = ${input.companyId}::uuid
            AND a."provider_postulation_id" IS NOT NULL
            AND e."postulacion_id" = a."provider_postulation_id"
            AND e."estado_certificacion" = 'finalizado'
            AND e."signature_status" <> 'BLOCKED'
            AND e."processing_state" = 'COMPLETE'
            AND e."received_at" >= a."created_at") AS provider_events,
        (SELECT count(*)
           FROM "ecf_dosa_webhook_events" e
          WHERE e."company_id" = ${input.companyId}::uuid
            AND e."estado_certificacion" = 'finalizado'
            AND e."signature_status" <> 'BLOCKED'
            AND NOT EXISTS (
              SELECT 1 FROM attempt a
               WHERE a."provider_postulation_id" IS NOT NULL
                 AND e."postulacion_id" = a."provider_postulation_id"
            )) AS foreign_events,
        (SELECT h."state"::text
           FROM "ecf_dgii_habilitations" h
          WHERE h."company_id" = ${input.companyId}::uuid
          LIMIT 1) AS dgii_state,
        (SELECT h."authorization_source"::text
           FROM "ecf_dgii_habilitations" h
          WHERE h."company_id" = ${input.companyId}::uuid
          LIMIT 1) AS dgii_source,
        (SELECT h."authorized_at"
           FROM "ecf_dgii_habilitations" h
          WHERE h."company_id" = ${input.companyId}::uuid
          LIMIT 1) AS dgii_authorized_at,
        (SELECT l."action"::text
           FROM "ecf_audit_logs" l
          WHERE l."company_id" = ${input.companyId}::uuid
            AND l."action"::text IN ('DGII_AUTHORIZATION_RECORDED', 'DGII_AUTHORIZATION_REVOKED')
            AND l."actor_user_id" IS NOT NULL
          ORDER BY l."created_at" DESC, l."id" DESC
          LIMIT 1) AS last_decision,
        (SELECT l."created_at"
           FROM "ecf_audit_logs" l
          WHERE l."company_id" = ${input.companyId}::uuid
            AND l."action"::text IN ('DGII_AUTHORIZATION_RECORDED', 'DGII_AUTHORIZATION_REVOKED')
            AND l."actor_user_id" IS NOT NULL
          ORDER BY l."created_at" DESC, l."id" DESC
          LIMIT 1) AS last_decision_at,
        (SELECT l."created_at"
           FROM "ecf_audit_logs" l
          WHERE l."company_id" = ${input.companyId}::uuid
            AND l."action"::text = 'DGII_AUTHORIZATION_RECORDED'
            AND l."actor_user_id" IS NOT NULL
          ORDER BY l."created_at" DESC, l."id" DESC
          LIMIT 1) AS last_recorded_at,
        (SELECT count(*)
           FROM "ecf_audit_logs" l
          WHERE l."company_id" = ${input.companyId}::uuid
            AND l."action"::text = 'DGII_AUTHORIZATION_RECORDED'
            AND l."actor_user_id" IS NOT NULL) AS authorizations_recorded,
        (SELECT count(*)
           FROM "ecf_audit_logs" l
          WHERE l."company_id" = ${input.companyId}::uuid
            AND l."action"::text = 'DGII_AUTHORIZATION_REVOKED') AS authorizations_revoked
    `;

    const row = rows[0];
    const attemptNo =
      row?.attempt_no === null || row?.attempt_no === undefined
        ? null
        : Number(row.attempt_no);
    const attemptStartedAt = toDate(row?.attempt_created_at);
    const postulacionId = row?.postulacion_id ?? null;

    const linkedSessions = toCount(row?.linked_sessions);
    const providerEvents = toCount(row?.provider_events);
    const foreignEvents = toCount(row?.foreign_events);
    const recorded = toCount(row?.authorizations_recorded);
    const revoked = toCount(row?.authorizations_revoked);

    const dgiiAuthorizedAt = toDate(row?.dgii_authorized_at);
    const lastDecisionAt = toDate(row?.last_decision_at);
    const lastRecordedAt = toDate(row?.last_recorded_at);
    const lastDecision =
      row?.last_decision === "DGII_AUTHORIZATION_RECORDED"
        ? "RECORDED"
        : row?.last_decision === "DGII_AUTHORIZATION_REVOKED"
          ? "REVOKED"
          : null;

    const identityLinked = attemptNo !== null;
    const postulationBound = identityLinked && postulacionId !== null;
    const providerConfirmed = postulationBound && providerEvents > 0;

    // La aprobación DGII debe venir de registro oficial y ser de ESTE intento.
    //
    // Además del registro oficial (documento + resolución), cuenta el cierre
    // firmado del proveedor para el intento vigente: DOSA no marca
    // `estado_certificacion = finalizado` si la DGII no aprobó la postulación, y
    // ese evento llega con firma HMAC, con el `postulacion_id` del intento y
    // después de que este empezara. Exigir además un documento que el proceso
    // no entrega dejaba al cliente bloqueado sin nada que subir.
    const officialRecord =
      row?.dgii_state === "APPROVED" &&
      row?.dgii_source === "DGII_OFFICIAL_RECORD" &&
      notBefore(dgiiAuthorizedAt, attemptStartedAt);
    const dgiiApproved = officialRecord || providerConfirmed;

    // La última decisión administrativa válida prevalece: se mira la última
    // decisión (no la cantidad) y debe ser un registro posterior al inicio del
    // intento vigente.
    const administrativeAuthorized =
      lastDecision === "RECORDED" &&
      lastDecisionAt !== null &&
      notBefore(lastRecordedAt, attemptStartedAt);

    return {
      identityLinked,
      postulationBound,
      providerConfirmed,
      dgiiApproved,
      administrativeAuthorized,
      details: {
        attemptNo,
        attemptStartedAt: iso(attemptStartedAt),
        postulacionId,
        linkedSessions,
        authenticatedProviderEvents: providerEvents,
        providerEventsForOtherPostulations: foreignEvents,
        dgiiState: row?.dgii_state ?? null,
        dgiiSource: row?.dgii_source ?? null,
        dgiiAuthorizedAt: iso(dgiiAuthorizedAt),
        lastDecision,
        lastDecisionAt: iso(lastDecisionAt),
        lastRecordedAt: iso(lastRecordedAt),
        authorizationsRecorded: recorded,
        authorizationsRevoked: revoked,
      },
    };
  }
}

/** Motivos por los que la evidencia no basta para activar. */
export function activationBlockers(evidence: DosaActivationEvidence): string[] {
  const blockers: string[] = [];
  if (!evidence.identityLinked) {
    blockers.push("ECF_DOSA_ACTIVATION_RNC_NOT_LINKED");
  } else if (!evidence.postulationBound) {
    // Hay intento, pero el proveedor todavía no le asignó postulación: sin
    // `postulacion_id` no se puede comprobar a qué postulación pertenece un
    // evento, así que contarlo sería adivinar.
    blockers.push("ECF_DOSA_ACTIVATION_POSTULATION_NOT_BOUND");
  }

  if (!evidence.providerConfirmed) {
    blockers.push("ECF_DOSA_ACTIVATION_PROVIDER_NOT_CONFIRMED");
  }

  if (!evidence.dgiiApproved) {
    if (
      evidence.details.dgiiState === "APPROVED" &&
      evidence.details.dgiiSource === "DGII_OFFICIAL_RECORD"
    ) {
      // Aprobada, pero antes de que existiera este intento: es una aprobación
      // antigua de una postulación previa.
      blockers.push("ECF_DOSA_ACTIVATION_DGII_APPROVAL_STALE");
    } else {
      blockers.push("ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED");
    }
  }

  if (!evidence.administrativeAuthorized) {
    if (evidence.details.lastDecision === "REVOKED") {
      blockers.push("ECF_DOSA_ACTIVATION_ADMIN_DECISION_REVOKED");
    } else if (evidence.details.lastDecision === "RECORDED") {
      blockers.push("ECF_DOSA_ACTIVATION_ADMIN_AUTHORIZATION_STALE");
    } else {
      blockers.push("ECF_DOSA_ACTIVATION_ADMIN_NOT_AUTHORIZED");
    }
  }

  return blockers;
}
