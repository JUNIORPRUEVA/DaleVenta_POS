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
 * * **Confirmación del proveedor** — un evento en `ecf_dosa_webhook_events` con
 *   `estado_certificacion = 'finalizado'` y una firma que no sea `BLOCKED`.
 * * **Aprobación DGII** — `ecf_dgii_habilitation` con estado `APPROVED` y
 *   `authorization_source = 'DGII_OFFICIAL_RECORD'`. Una declaración manual del
 *   operador (`MANUAL_OPERATOR_DECLARATION`) **no** cuenta.
 * * **Autorización administrativa** — una acción de auditoría
 *   `DGII_AUTHORIZATION_RECORDED` con actor real, que no haya sido revocada
 *   después por `DGII_AUTHORIZATION_REVOKED`.
 * * **Vínculo empresa↔RNC** — una sesión en `ecf_dosa_certification_sessions`.
 *   Sin vínculo no hay activación, porque el RNC del evento es solo una pista.
 */

export type DosaActivationEvidence = {
  /** El RNC está vinculado a esta empresa por una sesión de servidor. */
  identityLinked: boolean;
  providerConfirmed: boolean;
  dgiiApproved: boolean;
  administrativeAuthorized: boolean;
  /** Trazabilidad legible. Sin secretos. */
  details: {
    linkedSessions: number;
    authenticatedProviderEvents: number;
    dgiiState: string | null;
    dgiiSource: string | null;
    authorizationsRecorded: number;
    authorizationsRevoked: number;
  };
};

export interface DosaAuthorizationReader {
  read(input: { companyId: string; rnc: string }): Promise<DosaActivationEvidence>;
}

export const ECF_DOSA_AUTHORIZATION = Symbol("ECF_DOSA_AUTHORIZATION");

type EvidenceRow = {
  linked_sessions: string | number;
  provider_events: string | number;
  dgii_state: string | null;
  dgii_source: string | null;
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

export class PrismaDosaAuthorizationReader implements DosaAuthorizationReader {
  constructor(private readonly prisma: DosaRawClient) {}

  async read(input: {
    companyId: string;
    rnc: string;
  }): Promise<DosaActivationEvidence> {
    const rows = await this.prisma.$queryRaw<EvidenceRow[]>`
      SELECT
        (SELECT count(*)
           FROM "ecf_dosa_certification_sessions" s
          WHERE s."company_id" = ${input.companyId}::uuid
            AND s."rnc" = ${normalizeRnc(input.rnc)}) AS linked_sessions,
        (SELECT count(*)
           FROM "ecf_dosa_webhook_events" e
          WHERE e."company_id" = ${input.companyId}::uuid
            AND e."estado_certificacion" = 'finalizado'
            AND e."signature_status" <> 'BLOCKED') AS provider_events,
        (SELECT h."state"::text
           FROM "ecf_dgii_habilitations" h
          WHERE h."company_id" = ${input.companyId}::uuid
          LIMIT 1) AS dgii_state,
        (SELECT h."authorization_source"::text
           FROM "ecf_dgii_habilitations" h
          WHERE h."company_id" = ${input.companyId}::uuid
          LIMIT 1) AS dgii_source,
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
    const linkedSessions = toCount(row?.linked_sessions);
    const providerEvents = toCount(row?.provider_events);
    const recorded = toCount(row?.authorizations_recorded);
    const revoked = toCount(row?.authorizations_revoked);

    return {
      identityLinked: linkedSessions > 0,
      providerConfirmed: linkedSessions > 0 && providerEvents > 0,
      // La aprobacion DGII debe venir de registro oficial, no de una
      // declaracion manual del operador.
      dgiiApproved:
        row?.dgii_state === "APPROVED" && row?.dgii_source === "DGII_OFFICIAL_RECORD",
      // Una autorizacion revocada despues invalida las anteriores.
      administrativeAuthorized: recorded > revoked,
      details: {
        linkedSessions,
        authenticatedProviderEvents: providerEvents,
        dgiiState: row?.dgii_state ?? null,
        dgiiSource: row?.dgii_source ?? null,
        authorizationsRecorded: recorded,
        authorizationsRevoked: revoked,
      },
    };
  }
}

/** Motivos por los que la evidencia no basta para activar. */
export function activationBlockers(evidence: DosaActivationEvidence): string[] {
  const blockers: string[] = [];
  if (!evidence.identityLinked) blockers.push("ECF_DOSA_ACTIVATION_RNC_NOT_LINKED");
  if (!evidence.providerConfirmed) blockers.push("ECF_DOSA_ACTIVATION_PROVIDER_NOT_CONFIRMED");
  if (!evidence.dgiiApproved) blockers.push("ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED");
  if (!evidence.administrativeAuthorized) {
    blockers.push("ECF_DOSA_ACTIVATION_ADMIN_NOT_AUTHORIZED");
  }
  return blockers;
}
