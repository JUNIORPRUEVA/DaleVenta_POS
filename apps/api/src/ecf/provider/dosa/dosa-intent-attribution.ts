export type DosaIntentAttributionAudit = {
  id?: string;
  action: string;
  metadata: unknown;
  before?: unknown;
  after?: unknown;
  actorUserId?: string | null;
};

function provider(value: unknown): string | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const candidate = (value as Record<string, unknown>).provider;
  return candidate === "DOSA" || candidate === "ALANUBE" ? candidate : null;
}

export function historicalIntentProvider(audits: readonly DosaIntentAttributionAudit[]): string {
  const originals = audits.filter((entry) => entry.action === "ONBOARDING_STARTED");
  if (originals.length === 0 || originals.length !== audits.filter((entry) =>
    entry.action !== "INTENT_PROVIDER_RECONCILED").length) return "UNVERIFIED";
  const values = new Set(originals.map((entry) => provider(entry.metadata)));
  return values.size === 1 ? values.values().next().value ?? "UNVERIFIED" : "UNVERIFIED";
}

export function effectiveIntentProvider(audits: readonly DosaIntentAttributionAudit[]): string {
  const historical = historicalIntentProvider(audits);
  const reconciliations = audits.filter((entry) => entry.action === "INTENT_PROVIDER_RECONCILED");
  if (historical === "DOSA" && reconciliations.length === 0) return "DOSA";
  if (historical !== "ALANUBE" || reconciliations.length !== 1) return "UNVERIFIED";
  const original = audits.find((entry) => entry.action === "ONBOARDING_STARTED" &&
    entry.metadata && typeof entry.metadata === "object" && !Array.isArray(entry.metadata) &&
    (entry.metadata as Record<string, unknown>).created === true);
  const reconciliation = reconciliations[0];
  const metadata = reconciliation.metadata;
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) return "UNVERIFIED";
  const details = metadata as Record<string, unknown>;
  return reconciliation.actorUserId &&
    original?.id && details.sourceAuditId === original.id &&
    typeof details.externalReviewReference === "string" && details.externalReviewReference.length > 0 &&
    typeof details.ownerApprovalReference === "string" && details.ownerApprovalReference.length > 0 &&
    provider(reconciliation.before) === "ALANUBE" &&
    provider(reconciliation.after) === "DOSA"
    ? "DOSA" : "UNVERIFIED";
}
