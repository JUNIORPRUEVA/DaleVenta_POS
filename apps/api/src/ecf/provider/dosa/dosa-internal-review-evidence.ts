import { createHash } from "node:crypto";

/**
 * Evidencia INTERNA para la reconciliación EXCEPCIONAL de un intento DOSA.
 *
 * Qué demuestra y qué no:
 *
 * * Demuestra **integridad y reproducibilidad**: el `evidenceSnapshot` que se
 *   guarda en la auditoría produce exactamente el mismo dígito SHA-256 si se
 *   recalcula, y cualquier alteración del snapshot o del digest se detecta.
 * * **No** demuestra ausencia absoluta de actividad externa en el proveedor.
 *   Describe el estado local verificable en el instante de la decisión.
 *
 * Reglas de diseño que no se negocian:
 *
 * 1. El digest **siempre** se calcula en el servidor. Nunca se acepta uno
 *    enviado por el cliente.
 * 2. Un hash con formato correcto **no** basta: la atribución vuelve a verificar
 *    la consistencia interna del snapshot antes de aceptar la decisión.
 * 3. La serialización es determinista (claves ordenadas, sin `undefined`), para
 *    que el mismo snapshot dé siempre el mismo digest.
 */

export type DosaReconciliationReviewKind = "EXTERNAL" | "INTERNAL";

export const INTERNAL_EVIDENCE_SCHEMA = "fullpos.dosa.internal-review.v1" as const;

/** Campos del intento que forman parte del snapshot (nunca secretos). */
export type DosaInternalEvidenceIntent = {
  id: string;
  companyId: string;
  rnc: string;
  attemptNo: number;
  status: string;
  createdAt: string;
  createdByUserId: string | null;
  providerPostulationId: string | null;
  sessionUrl: string | null;
  lastEventType: string | null;
  providerConfirmedAt: string | null;
  closedAt: string | null;
};

export type DosaInternalEvidenceAudit = {
  total: number;
  originalAuditId: string;
  originalActorUserId: string | null;
  originalProvider: string;
  originalCreated: boolean;
  originalRnc: string;
  originalAttemptNo: number;
};

export type DosaInternalEvidenceActivity = {
  legacyProviderAttempts: number;
  webhookEvents: number;
  portalTickets: number;
  portalSessions: number;
};

export type DosaInternalEvidenceSnapshot = {
  schema: typeof INTERNAL_EVIDENCE_SCHEMA;
  intent: DosaInternalEvidenceIntent;
  audit: DosaInternalEvidenceAudit;
  activity: DosaInternalEvidenceActivity;
};

/**
 * Serialización determinista: claves ordenadas alfabéticamente y recursiva.
 * Los `undefined` se omiten para que un campo ausente y un `undefined` no
 * produzcan digests distintos.
 */
export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value) ?? "null";
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record)
    .filter((key) => record[key] !== undefined)
    .sort();
  const body = keys
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
    .join(",");
  return `{${body}}`;
}

export function internalEvidenceDigest(snapshot: DosaInternalEvidenceSnapshot): string {
  return createHash("sha256").update(stableStringify(snapshot), "utf8").digest("hex");
}

export type DosaInternalEvidenceVerdict =
  | { ok: true }
  | { ok: false; reason: string };

const TEXT_MAX = 256;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonEmptyText(value: unknown, min = 1, max = TEXT_MAX): boolean {
  return typeof value === "string" && value.trim().length >= min && value.length <= max;
}

/**
 * Verifica una decisión INTERNAL guardada en la auditoría.
 *
 * No se fía del formato del hash: reconstruye el digest desde el snapshot y
 * comprueba las invariantes que hacen que el caso sea exactamente el
 * excepcional (intento 1, NOT_STARTED, sin referencias de proveedor, sin
 * actividad externa y con una única auditoría original coherente).
 */
export function verifyInternalEvidence(
  metadata: unknown,
): DosaInternalEvidenceVerdict {
  if (!isRecord(metadata)) return { ok: false, reason: "INVALID_METADATA" };
  if (metadata.reviewKind !== "INTERNAL") {
    return { ok: false, reason: "REVIEW_KIND_NOT_INTERNAL" };
  }
  // Exclusividad: la variante interna no puede arrastrar una referencia externa.
  if (metadata.externalReviewReference !== undefined) {
    return { ok: false, reason: "EXTERNAL_REFERENCE_PRESENT" };
  }
  if (!nonEmptyText(metadata.internalReviewReference, 8, 128)) {
    return { ok: false, reason: "INTERNAL_REFERENCE_MISSING" };
  }
  if (!nonEmptyText(metadata.ownerApprovalReference, 8, 128)) {
    return { ok: false, reason: "OWNER_APPROVAL_MISSING" };
  }
  if (!nonEmptyText(metadata.reason, 20, 500)) {
    return { ok: false, reason: "REASON_MISSING" };
  }

  const snapshot = metadata.evidenceSnapshot;
  if (!isRecord(snapshot) || snapshot.schema !== INTERNAL_EVIDENCE_SCHEMA) {
    return { ok: false, reason: "SNAPSHOT_MISSING" };
  }
  if (!isRecord(snapshot.intent) || !isRecord(snapshot.audit) || !isRecord(snapshot.activity)) {
    return { ok: false, reason: "SNAPSHOT_INCOMPLETE" };
  }

  // 1) Integridad: el digest debe reproducirse exactamente desde el snapshot.
  const digest = metadata.internalEvidenceDigest;
  if (typeof digest !== "string" || !/^[0-9a-f]{64}$/.test(digest)) {
    return { ok: false, reason: "DIGEST_INVALID" };
  }
  if (internalEvidenceDigest(snapshot as DosaInternalEvidenceSnapshot) !== digest) {
    return { ok: false, reason: "DIGEST_MISMATCH" };
  }

  // 2) Consistencia del intento: exactamente el caso excepcional.
  const intent = snapshot.intent as Record<string, unknown>;
  if (intent.attemptNo !== 1) return { ok: false, reason: "INTENT_NOT_FIRST" };
  if (intent.status !== "NOT_STARTED") return { ok: false, reason: "INTENT_NOT_STARTED" };
  if (intent.providerPostulationId !== null) return { ok: false, reason: "PROVIDER_POSTULATION_PRESENT" };
  if (intent.sessionUrl !== null) return { ok: false, reason: "SESSION_URL_PRESENT" };
  if (intent.lastEventType !== null) return { ok: false, reason: "LAST_EVENT_PRESENT" };
  if (intent.providerConfirmedAt !== null) return { ok: false, reason: "PROVIDER_CONFIRMATION_PRESENT" };
  if (intent.closedAt !== null) return { ok: false, reason: "INTENT_CLOSED" };
  if (!nonEmptyText(intent.id, 1, 64) || !nonEmptyText(intent.companyId, 1, 64) || !nonEmptyText(intent.rnc, 1, 32)) {
    return { ok: false, reason: "INTENT_INCOMPLETE" };
  }
  if (!nonEmptyText(intent.createdByUserId, 1, 64)) {
    return { ok: false, reason: "INTENT_WITHOUT_CREATOR" };
  }

  // 3) Auditoría original única, coherente y con la atribución histórica.
  const audit = snapshot.audit as Record<string, unknown>;
  if (audit.total !== 1) return { ok: false, reason: "AUDIT_NOT_UNIQUE" };
  if (audit.originalCreated !== true) return { ok: false, reason: "ORIGINAL_NOT_CREATED" };
  if (audit.originalProvider !== "ALANUBE") return { ok: false, reason: "HISTORICAL_NOT_ALANUBE" };
  if (audit.originalRnc !== intent.rnc) return { ok: false, reason: "ORIGINAL_RNC_MISMATCH" };
  if (audit.originalAttemptNo !== intent.attemptNo) return { ok: false, reason: "ORIGINAL_ATTEMPT_MISMATCH" };
  if (audit.originalActorUserId !== intent.createdByUserId) {
    return { ok: false, reason: "ORIGINAL_ACTOR_MISMATCH" };
  }
  if (!nonEmptyText(audit.originalAuditId, 1, 64)) {
    return { ok: false, reason: "ORIGINAL_AUDIT_MISSING" };
  }
  if (metadata.sourceAuditId !== audit.originalAuditId) {
    return { ok: false, reason: "SOURCE_AUDIT_MISMATCH" };
  }

  // 4) Sin actividad externa registrada.
  const activity = snapshot.activity as Record<string, unknown>;
  const activityChecks: Array<[unknown, string]> = [
    [activity.legacyProviderAttempts, "ACTIVITY_LEGACY_ATTEMPTS"],
    [activity.webhookEvents, "ACTIVITY_WEBHOOK_EVENTS"],
    [activity.portalTickets, "ACTIVITY_PORTAL_TICKETS"],
    [activity.portalSessions, "ACTIVITY_PORTAL_SESSIONS"],
  ];
  for (const [value, reason] of activityChecks) {
    if (typeof value !== "number" || !Number.isFinite(value)) {
      return { ok: false, reason: "ACTIVITY_INVALID" };
    }
    if (value !== 0) return { ok: false, reason };
  }

  return { ok: true };
}
