import { EcfElectronicDocumentStatus } from "@prisma/client";

const TRANSITIONS: Record<EcfElectronicDocumentStatus, EcfElectronicDocumentStatus[]> = {
  LOCAL_DRAFT: [
    "LOCAL_VALIDATION_PENDING",
    "LOCAL_VALIDATED",
    "CANCELLED",
    "HUMAN_REVIEW_REQUIRED",
  ],
  LOCAL_VALIDATION_PENDING: [
    "LOCAL_VALIDATED",
    "HUMAN_REVIEW_REQUIRED",
    "CANCELLED",
  ],
  LOCAL_VALIDATED: ["READY_TO_SEND", "HUMAN_REVIEW_REQUIRED", "CANCELLED"],
  READY_TO_SEND: ["SEND_PENDING", "HUMAN_REVIEW_REQUIRED", "CANCELLED"],
  SEND_PENDING: ["SEND_IN_PROGRESS", "HUMAN_REVIEW_REQUIRED", "CANCELLED"],
  SEND_IN_PROGRESS: [
    "UNKNOWN_RESULT",
    "PROVIDER_ACCEPTED",
    "PROVIDER_REJECTED",
    "HUMAN_REVIEW_REQUIRED",
  ],
  UNKNOWN_RESULT: [
    "PROVIDER_ACCEPTED",
    "PROVIDER_REJECTED",
    "DGII_STATUS_PENDING",
    "HUMAN_REVIEW_REQUIRED",
  ],
  PROVIDER_ACCEPTED: ["DGII_STATUS_PENDING", "HUMAN_REVIEW_REQUIRED"],
  PROVIDER_REJECTED: ["HUMAN_REVIEW_REQUIRED"],
  DGII_STATUS_PENDING: ["DGII_ACCEPTED", "DGII_REJECTED", "UNKNOWN_RESULT", "HUMAN_REVIEW_REQUIRED"],
  DGII_ACCEPTED: ["HUMAN_REVIEW_REQUIRED"],
  DGII_REJECTED: ["HUMAN_REVIEW_REQUIRED"],
  HUMAN_REVIEW_REQUIRED: ["LOCAL_DRAFT", "CANCELLED"],
  CANCELLED: [],
};

const EVIDENCE_REQUIRED = new Set<EcfElectronicDocumentStatus>([
  "PROVIDER_ACCEPTED",
  "PROVIDER_REJECTED",
  "DGII_ACCEPTED",
  "DGII_REJECTED",
]);

export type EcfTransitionDecision =
  | { ok: true }
  | { ok: false; code: string; safeMessage: string };

export function canTransitionEcfDocument(
  from: EcfElectronicDocumentStatus,
  to: EcfElectronicDocumentStatus,
  options: { hasEvidence?: boolean } = {},
): EcfTransitionDecision {
  if (from === to) return { ok: true };
  if (!TRANSITIONS[from]?.includes(to)) {
    return {
      ok: false,
      code: "ECF_INVALID_STATUS_TRANSITION",
      safeMessage: "Transición e-CF no permitida.",
    };
  }
  if (EVIDENCE_REQUIRED.has(to) && !options.hasEvidence) {
    return {
      ok: false,
      code: "ECF_STATUS_EVIDENCE_REQUIRED",
      safeMessage: "El cambio de estado requiere evidencia verificable.",
    };
  }
  return { ok: true };
}

export function terminalUnknownRequiresHumanReview(
  status: EcfElectronicDocumentStatus,
) {
  return status === "UNKNOWN_RESULT";
}

export const ECF_DOCUMENT_TRANSITIONS = TRANSITIONS;
