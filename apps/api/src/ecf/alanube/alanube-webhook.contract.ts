export type AlanubeWebhookContractStatus =
  | "BLOCKED_PENDING_OFFICIAL_SIGNATURE_CONTRACT"
  | "READY_FOR_MOCKS_ONLY";

export type AlanubeWebhookEnvelope = {
  provider: "ALANUBE";
  eventId: string;
  companyExternalId?: string;
  documentExternalId?: string;
  eventType: string;
  occurredAt?: string;
  payload: unknown;
};

export function validateAlanubeWebhookEnvelope(
  value: unknown,
): { ok: true; envelope: AlanubeWebhookEnvelope } | { ok: false; reason: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, reason: "INVALID_OBJECT" };
  }
  const record = value as Record<string, unknown>;
  if (record.provider !== "ALANUBE") return { ok: false, reason: "INVALID_PROVIDER" };
  if (typeof record.eventId !== "string" || !/^[A-Za-z0-9_.:-]{3,128}$/.test(record.eventId)) {
    return { ok: false, reason: "INVALID_EVENT_ID" };
  }
  if (typeof record.eventType !== "string" || !/^[A-Za-z0-9_.:-]{3,128}$/.test(record.eventType)) {
    return { ok: false, reason: "INVALID_EVENT_TYPE" };
  }
  // This is a bounded LOCAL test/intake envelope, not the provider wire schema.
  const allowed = ["provider", "eventId", "companyExternalId", "documentExternalId", "eventType", "occurredAt", "payload"];
  if (Object.keys(record).some((key) => !allowed.includes(key)) || !record.payload ||
      typeof record.payload !== "object" || Array.isArray(record.payload)) return { ok: false, reason: "INVALID_PAYLOAD" };
  for (const key of ["companyExternalId", "documentExternalId"]) {
    if (record[key] !== undefined && (typeof record[key] !== "string" || !/^[A-Za-z0-9_.:-]{1,128}$/.test(record[key] as string))) return { ok: false, reason: "INVALID_REFERENCE" };
  }
  if (record.occurredAt !== undefined && (typeof record.occurredAt !== "string" ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(record.occurredAt) ||
      !Number.isFinite(Date.parse(record.occurredAt)) || new Date(record.occurredAt).toISOString() !== record.occurredAt)) return { ok: false, reason: "INVALID_DATE" };
  return { ok: true, envelope: record as AlanubeWebhookEnvelope };
}

export const ALANUBE_WEBHOOK_CONTRACT_STATUS: AlanubeWebhookContractStatus =
  "BLOCKED_PENDING_OFFICIAL_SIGNATURE_CONTRACT";
