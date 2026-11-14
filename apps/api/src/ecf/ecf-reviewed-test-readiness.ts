type ReviewedTestDocument = {
  status: string;
  sourceType: string | null;
  sourceId: string | null;
  payloadFingerprint: string;
  payloadSummary: unknown;
  statusLogs: Array<{ metadata: unknown }>;
};

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}

/** A closed engineering trial is not an unresolved commercial invoice.
 * This never changes or grants fiscal acceptance. The legacy classification
 * operation already verifies the frozen identity and original allocation.
 */
export function hasReviewedLegacyTestProof(document: ReviewedTestDocument): boolean {
  if (document.sourceType !== "MANUAL" || document.sourceId !== null) return false;
  const proof = record(record(document.payloadSummary)?.controlledTest);
  if (proof?.environment !== "TEST" || proof.correlated !== true ||
      !/^[a-f0-9]{64}$/.test(String(proof.responseSha256)) || typeof proof.plan !== "string") return false;
  return document.statusLogs.some(log => {
    const review = record(log.metadata);
    return review?.environment === "SANDBOX" &&
      review.documentFingerprint === document.payloadFingerprint &&
      review.evidenceSha256 === proof.responseSha256 && review.evidencePlan === proof.plan &&
      /^[a-f0-9]{64}$/.test(String(review.manifestHash)) &&
      typeof review.reviewer === "string" && review.reviewer.trim().length > 0;
  });
}

export function isClosedReviewedLegacyTest(document: ReviewedTestDocument): boolean {
  const proof = record(record(document.payloadSummary)?.controlledTest);
  return document.status === "HUMAN_REVIEW_REQUIRED" &&
    ["ACCEPTED", "CONDITIONALLY_ACCEPTED", "REJECTED"].includes(String(proof?.outcome)) &&
    hasReviewedLegacyTestProof(document);
}
