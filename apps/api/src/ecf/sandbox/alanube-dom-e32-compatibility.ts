import Ajv from "ajv";
import addFormats from "ajv-formats";
import { createHash } from "node:crypto";
import { ALANUBE_E32_QUERY } from "../alanube/contracts/alanube-e32-query.generated";

export const E32_COMPATIBILITY_PROFILE = "ALANUBE_DOM_E32_SANDBOX_OBSERVED_V1";
export type E32CompatibilityContext = {
  provider: "ALANUBE_DOM"; environment: "SANDBOX"; endpoint: "GET_E32_TOKEN_PRIMARY";
  companyId: string; verifiedCompanyId: string; operationId: string; remoteId: string; encf: string; rnc: string;
  issueDate: string; totalAmount: number; expectedLegalStatus: "ACCEPTED"; expectedSequenceConsumed: true;
};
const ajv = new Ajv({ allErrors: true, strictSchema: false, strictTypes: false,
  coerceTypes: false, useDefaults: false, removeAdditional: false });
addFormats(ajv); ajv.addFormat("ulid", /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/);
const contract = ALANUBE_E32_QUERY.checkinvoices;
const validate = ajv.compile(contract.responses["200"]);
function schema(body: unknown) {
  const ok = validate(body) as boolean;
  return { ok, errors: (validate.errors ?? []).map(e => ({ path: e.instancePath, keyword: e.keyword })) };
}
function calendar(day: string) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
  if (!m) return false;
  const y = +m[1], month = +m[2], d = +m[3];
  const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
  return y > 0 && month >= 1 && month <= 12 && d >= 1 && d <= [31,leap?29:28,31,30,31,30,31,31,30,31,30,31][month-1];
}
function clock(h: string, m: string, s: string) { return +h < 24 && +m < 60 && +s < 60; }

// Observed compatibility, not an amendment to the published contract. No writer,
// network client, fiscal authority or timezone inference is exposed here.
export function assessAlanubeDomE32Compatibility(httpStatus: number, body: unknown, context: E32CompatibilityContext) {
  const r = body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};
  const published = schema(body), view = { ...r }, reasons: string[] = [];
  const rules: Array<{ code: string; field: string; original: string | null; representation: string | null }> = [];
  const scope = context.provider === "ALANUBE_DOM" && context.environment === "SANDBOX" && context.endpoint === "GET_E32_TOKEN_PRIMARY" &&
    Boolean(context.companyId) && context.companyId === context.verifiedCompanyId &&
    Number.isFinite(context.totalAmount) && context.totalAmount > 0 && context.totalAmount < 250000;
  if (!scope) reasons.push("COMPATIBILITY_SCOPE_REFUSED");
  if (httpStatus !== 200) reasons.push("HTTP_200_REQUIRED");
  if (!/^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(context.remoteId) || r.id !== context.remoteId) reasons.push("REMOTE_ID_MISMATCH");
  if (!/^E32\d{10}$/.test(context.encf) || r.documentNumber !== context.encf) reasons.push("ENCF_MISMATCH");
  if (!/^\d{9,11}$/.test(context.rnc) || r.companyIdentification !== context.rnc) reasons.push("EMITTER_MISMATCH");
  if (context.expectedLegalStatus !== "ACCEPTED" || r.legalStatus !== context.expectedLegalStatus || r.status !== "FINISHED") reasons.push("STATUS_CONTRADICTION_OR_INCOMPLETE");
  if (context.expectedSequenceConsumed !== true || r.sequenceConsumed !== true) reasons.push("SEQUENCE_CONTRADICTION_OR_INCOMPLETE");
  if ((Array.isArray(r.response) && r.response.length) || (r.response !== undefined && !Array.isArray(r.response))) reasons.push("CONTRADICTORY_RESPONSE");
  let fiscalIssueDate: string | null = null;
  if (typeof r.stampDate === "string" && calendar(r.stampDate)) fiscalIssueDate = r.stampDate;
  else if (typeof r.stampDate === "string" && /^\d{4}-\d{2}-\d{2}T00:00:00\.000Z$/.test(r.stampDate) && calendar(r.stampDate.slice(0,10))) {
    fiscalIssueDate = r.stampDate.slice(0,10); view.stampDate = fiscalIssueDate;
    rules.push({ code: "OBSERVED_MIDNIGHT_Z_AS_LEXICAL_DATE", field: "stampDate", original: r.stampDate, representation: fiscalIssueDate });
  } else reasons.push("STAMP_DATE_INVALID_OR_UNSUPPORTED");
  if (!calendar(context.issueDate) || fiscalIssueDate !== context.issueDate) reasons.push("FISCAL_DATE_MISMATCH");
  let signature: { kind: string; value: string; timeZone: null; instant: null } | null = null;
  if (typeof r.signatureDate === "string") {
    const local = /^(\d{2})-(\d{2})-(\d{4}) (\d{2}):(\d{2}):(\d{2})$/.exec(r.signatureDate);
    const iso = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.exec(r.signatureDate);
    if (local && calendar(`${local[3]}-${local[2]}-${local[1]}`) && clock(local[4],local[5],local[6])) {
      const wall = `${local[3]}-${local[2]}-${local[1]}T${local[4]}:${local[5]}:${local[6]}`;
      signature = { kind: "LOCAL_WALL_CLOCK_UNZONED", value: wall, timeZone: null, instant: null };
      // Optional wire field cannot truthfully be converted to RFC3339. Keep it
      // separately, with its original, outside the schema-validation view.
      delete view.signatureDate;
      rules.push({ code: "OBSERVED_DMY_SECONDS_UNZONED", field: "signatureDate", original: r.signatureDate, representation: wall });
    } else if (iso && calendar(iso[1]) && clock(iso[2],iso[3],iso[4])) {
      signature = { kind: "RFC3339_ORIGINAL", value: r.signatureDate, timeZone: null, instant: null };
    } else reasons.push("SIGNATURE_DATE_INVALID_OR_AMBIGUOUS");
  } else if (r.signatureDate !== undefined) reasons.push("SIGNATURE_DATE_INVALID_OR_AMBIGUOUS");
  if (r.trackId === null) {
    if (scope && r.status === "FINISHED" && r.legalStatus === "ACCEPTED" && r.sequenceConsumed === true) {
      delete view.trackId;
      rules.push({ code: "OBSERVED_NULL_TRACK_ID_UNAVAILABLE", field: "trackId", original: null, representation: null });
    } else reasons.push("NULL_TRACK_ID_SCOPE_REFUSED");
  }
  const compatibleView = schema(view);
  if (!compatibleView.ok) reasons.push("UNHANDLED_SCHEMA_VIOLATION");
  return { profile: E32_COMPATIBILITY_PROFILE,
    correlation: { companyId: context.companyId, operationId: context.operationId, remoteId: context.remoteId, encf: context.encf, rnc: context.rnc },
    publishedContract: { ...published, schemaSha256: contract.schemaSha256 },
    compatibility: { ok: reasons.length === 0, reasons, validationViewSchemaValid: compatibleView.ok, remainingSchemaErrors: compatibleView.errors, rules },
    representation: { fiscalIssueDate, signature, trackIdAvailable: typeof r.trackId === "string" && compatibleView.ok },
    observedProviderOutcome: reasons.length ? "UNKNOWN" : "ACCEPTED",
    proposedLocalStatus: reasons.length ? null : "HUMAN_REVIEW_REQUIRED",
    canUpdateFiscalStatus: false, canRetryPost: false, canApplyReconciliation: false };
}

export type E32CompatibilityAssessment = ReturnType<typeof assessAlanubeDomE32Compatibility>;

export function prepareE32CompatibilityReconciliationPlan(input: {
  companyId: string; operationId: string; documentId: string; trialId: string; remoteId: string; encf: string;
  responseSha256: string; postResponseSha256: string; manifestFingerprint: string; payloadFingerprint: string;
  documentStatus: string; trialState: string; externalProviderId: string | null; externalDocumentNumber: string | null;
  postAttempts: number; dbQueryAttempts: number; evidenceChainVerified: boolean; encryptedArchiveVerified: boolean; noConflictingReference: boolean;
  assessment: ReturnType<typeof assessAlanubeDomE32Compatibility>;
}) {
  const a = input.assessment;
  const hashesValid = [input.responseSha256,input.postResponseSha256,input.manifestFingerprint,input.payloadFingerprint].every(x=>/^[a-f0-9]{64}$/.test(x));
  const ready = a.compatibility.ok && a.correlation.companyId === input.companyId && a.correlation.operationId === input.operationId &&
    a.correlation.remoteId === input.remoteId && a.correlation.encf === input.encf && hashesValid &&
    input.documentStatus === "UNKNOWN_RESULT" && input.trialState === "UNKNOWN_RESULT" &&
    input.externalProviderId === null && input.externalDocumentNumber === null && input.postAttempts === 1 && input.dbQueryAttempts === 0 &&
    input.evidenceChainVerified && input.encryptedArchiveVerified && input.noConflictingReference;
  const key = createHash("sha256").update(JSON.stringify([input.companyId,input.operationId,input.documentId,input.trialId,
    input.remoteId,input.encf,input.responseSha256,input.postResponseSha256,input.manifestFingerprint,input.payloadFingerprint,a.profile])).digest("hex");
  return { result: ready ? "READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION" : "BLOCKED", canApply: false,
    idempotencyKey: `e32-reconcile:${key}`, companyId: input.companyId, operationId: input.operationId,
    documentId: input.documentId, trialId: input.trialId,
    before: { documentStatus: input.documentStatus, externalProviderId: input.externalProviderId, externalDocumentNumber: input.externalDocumentNumber },
    proposed: ready ? { documentStatus: "HUMAN_REVIEW_REQUIRED", externalProviderId: input.remoteId, externalDocumentNumber: input.encf,
      observedLegalStatus: "ACCEPTED", sequenceConsumed: true, trialState: "UNCHANGED_CONSUMED", fiscalSnapshot: "UNCHANGED",
      receiptTrust: "PROVIDER_DECLARED", publishedValidation: a.publishedContract.ok ? "OFFICIAL_SCHEMA_VALID" : "OFFICIAL_SCHEMA_INVALID",
      compatibilityProfile: a.profile, appliedRules: a.compatibility.rules } : null,
    evidence: { responseSha256: input.responseSha256, postResponseSha256: input.postResponseSha256,
      manifestFingerprint: input.manifestFingerprint, payloadFingerprint: input.payloadFingerprint, schemaSha256: a.publishedContract.schemaSha256 },
    requirements: ["SEPARATE_EXPLICIT_AUTHORIZATION", "VALID_ADMIN_SESSION", "VERIFIED_UAT_BACKUP", "LOCK_AND_RECHECK_EXPECTED_ROWS",
      "ATOMIC_REFERENCE_RECEIPT_STATUS_AUDIT", "SAME_KEY_SAME_CONTENT_NO_OP", "DIVERGENT_CONTENT_CONFLICT", "NO_NETWORK_OR_REISSUANCE"],
    canGrantDgiiAcceptance: false, canReleaseSequence: false };
}
