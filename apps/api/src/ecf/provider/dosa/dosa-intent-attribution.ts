import { verifyInternalEvidence } from "./dosa-internal-review-evidence";

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

const NON_ORIGIN_ACTIONS = new Set([
  "INTENT_PROVIDER_RECONCILED",
  // Una autorización posterior no es un origen de proveedor: solo habilita la
  // transición del expediente histórico ya reconciliado.
  "INTENT_HISTORICAL_TRANSITION_AUTHORIZED",
]);

export function historicalIntentProvider(audits: readonly DosaIntentAttributionAudit[]): string {
  const originals = audits.filter((entry) => entry.action === "ONBOARDING_STARTED");
  // Cualquier acción desconocida sigue invalidando la atribución. No se
  // convierte en origen ni se ignora: un historial malformado debe bloquear.
  const unknown = audits.some(
    (entry) => entry.action !== "ONBOARDING_STARTED" && !NON_ORIGIN_ACTIONS.has(entry.action),
  );
  if (originals.length === 0 || unknown) return "UNVERIFIED";
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

  // Comunes a las dos variantes: actor identificable, decisión sobre la
  // auditoría original exacta y atribución ALANUBE -> DOSA.
  if (!reconciliation.actorUserId) return "UNVERIFIED";
  if (!original?.id || details.sourceAuditId !== original.id) return "UNVERIFIED";
  if (provider(reconciliation.before) !== "ALANUBE") return "UNVERIFIED";
  if (provider(reconciliation.after) !== "DOSA") return "UNVERIFIED";

  // Variante EXCEPCIONAL por revisión interna: no se acepta por el formato del
  // hash, se rehace la verificación completa del snapshot.
  if (details.reviewKind === "INTERNAL") {
    return verifyInternalEvidence(details).ok ? "DOSA" : "UNVERIFIED";
  }

  // Variante EXTERNAL. `reviewKind` ausente = registro anterior a la excepción:
  // se sigue exigiendo la referencia externa y la aprobación del propietario.
  return typeof details.externalReviewReference === "string" &&
    details.externalReviewReference.trim().length > 0 &&
    typeof details.ownerApprovalReference === "string" &&
    details.ownerApprovalReference.trim().length > 0
    ? "DOSA"
    : "UNVERIFIED";
}

/**
 * Qué clase de revisión sustentó la reconciliación, para el diagnóstico.
 *
 * `null` si no hay reconciliación; `UNVERIFIED` si la hay pero no es válida.
 * La interfaz usa esto para no insinuar una confirmación del proveedor cuando
 * la decisión fue interna.
 */
export function intentReconciliationKind(
  audits: readonly DosaIntentAttributionAudit[],
): "EXTERNAL" | "INTERNAL" | null | "UNVERIFIED" {
  const reconciliations = audits.filter((entry) => entry.action === "INTENT_PROVIDER_RECONCILED");
  if (reconciliations.length === 0) return null;
  if (effectiveIntentProvider(audits) !== "DOSA") return "UNVERIFIED";
  const metadata = reconciliations[0].metadata;
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) return "UNVERIFIED";
  return (metadata as Record<string, unknown>).reviewKind === "INTERNAL" ? "INTERNAL" : "EXTERNAL";
}
