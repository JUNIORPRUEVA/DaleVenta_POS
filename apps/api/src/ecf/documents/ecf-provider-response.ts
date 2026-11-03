import { validateAlanubeOfficialResponse } from "../alanube/alanube-schema-validator";
import type { EcfDocumentType } from "../fiscal-core/ecf-fiscal-document";

// Provider observations and fiscal authority are separate. This generic
// assessment works for any e-CF type (E31/E32/E34) and never grants DGII status
// or permission to send/retry a document.
export type EcfProviderObservationContext = {
  documentType: EcfDocumentType;
  expectedEncf: string;
  expectedTaxId: string;
  remoteConflict: boolean;
  expectedRemoteId?: string;
  expectedHttpStatus?: number;
};

export type EcfProviderObservation = {
  checks: Record<string, boolean | null>;
  reasons: string[];
  schemaSha256: string;
  schemaErrors: Array<{ path: string; keyword: string }>;
  correlated: boolean;
  observedOutcome: "ACCEPTED" | "REJECTED" | "PENDING" | "UNKNOWN";
  providerOutcome: "ACCEPTED" | "REJECTED" | "PENDING" | "UNKNOWN";
  safeCode: string;
  remoteId: string | null;
  documentNumber: string | null;
  providerStatus: string | null;
  observedLegalStatus: string | null;
  sequenceConsumed: boolean | null;
  canUpdateFiscalStatus: false;
  canRetryPost: false;
};

export function assessEcfProviderResponse(
  httpStatus: number,
  body: unknown,
  context?: EcfProviderObservationContext,
): EcfProviderObservation {
  const value = body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};
  const documentType = context?.documentType ?? "E32";
  const expectedHttpStatus = context?.expectedHttpStatus ?? 201;
  const schema = validateAlanubeOfficialResponse(documentType, httpStatus, body);
  const idValid = typeof value.id === "string" && /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(value.id);
  const numberValid = typeof value.documentNumber === "string" && new RegExp(`^${documentType}\\d{10}$`).test(value.documentNumber);
  const accepted = value.legalStatus === "ACCEPTED" || value.legalStatus === "ACCEPTED_WITH_OBSERVATIONS";
  const rejected = value.legalStatus === "REJECTED";
  const pending = value.legalStatus === undefined && ["TO_SEND", "WAITING_RESPONSE"].includes(String(value.status));
  const complete = idValid && numberValid && typeof value.status === "string" && typeof value.sequenceConsumed === "boolean" &&
    (accepted || rejected || pending);
  const checks = {
    HTTP_201: httpStatus === expectedHttpStatus, OFFICIAL_SCHEMA: schema.ok, REMOTE_ID: idValid,
    DOCUMENT_NUMBER: numberValid, COMPLETE: complete,
    NUMBER_MATCH: context ? value.documentNumber === context.expectedEncf : null,
    COMPANY_MATCH: context ? value.companyIdentification === undefined || value.companyIdentification === context.expectedTaxId : null,
    REMOTE_NOT_CONFLICTING: context ? !context.remoteConflict && (!context.expectedRemoteId || value.id === context.expectedRemoteId) : null,
    SEQUENCE_CONSISTENT: !accepted || value.sequenceConsumed === true,
    RESPONSE_CONSISTENT: !accepted || !Array.isArray(value.response) || value.response.length === 0,
  };
  const reasons = Object.entries(checks).filter(([, pass]) => pass === false).map(([key]) => key);
  // A schema-valid partial object is not sufficient evidence. Correlation must
  // come from the authenticated operation, never from values supplied by a file.
  const correlated = Boolean(context) && reasons.length === 0;
  const observedOutcome = reasons.length ? "UNKNOWN" : accepted ? "ACCEPTED" : rejected ? "REJECTED" : pending ? "PENDING" : "UNKNOWN";
  return {
    checks, reasons, schemaSha256: schema.schemaSha256,
    schemaErrors: schema.errors.slice(0, 40).map(error => ({ path: error.path.slice(0, 256), keyword: error.keyword })),
    correlated, observedOutcome,
    providerOutcome: correlated ? observedOutcome : "UNKNOWN",
    safeCode: reasons.length ? `ECF_${reasons[0]}_FAILED` : correlated ? `ECF_OBSERVED_${observedOutcome}` : "ECF_CORRELATION_NOT_CHECKED",
    remoteId: idValid ? value.id as string : null,
    documentNumber: numberValid ? value.documentNumber as string : null,
    providerStatus: schema.ok && typeof value.status === "string" ? value.status : null,
    observedLegalStatus: schema.ok && typeof value.legalStatus === "string" ? value.legalStatus : null,
    sequenceConsumed: typeof value.sequenceConsumed === "boolean" ? value.sequenceConsumed : null,
    canUpdateFiscalStatus: false as const, canRetryPost: false as const,
  };
}
