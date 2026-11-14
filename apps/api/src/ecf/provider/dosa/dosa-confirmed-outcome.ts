import { createHash } from "node:crypto";
import { Prisma } from "@prisma/client";
import { requireTenant, TenantUser } from "../../../auth/tenant-context";
import { PrismaService } from "../../../prisma/prisma.service";
import { EcfE34CreditService } from "../../documents/ecf-e34-credit.service";
import { fingerprint } from "../../documents/ecf-document-idempotency.service";
import { EcfFiscalDocument } from "../../fiscal-core/ecf-fiscal-document";
import { moneyString } from "../../fiscal-core/ecf-money";
import { assessDosaProviderResponse } from "./dosa-provider-response";
import { dosaPrintStamp } from "./dosa-print-stamp";
import { DOSA_PERSISTED_REQUEST } from "./dosa-persisted-recovery";

export const DOSA_CONFIRMED_OUTCOME_CONTRACT = "DOSA_EMISSION_2026_11";

/** Internal server-response decision, not a client evidence-import endpoint.
 * Records DOSA's documented DGII result. It does not assert independent DGII
 * signature verification or change the generic evidence quarantine's trust.
 * Authorized SANDBOX dispatches use the reviewed contract without enabling
 * production. Production still requires both explicit server permissions.
 */
export async function recordDosaConfirmedOutcome(db: PrismaService, user: TenantUser, documentId: string,
  input: { receiptId: string; attemptId: string; httpStatus: number; body: unknown }): Promise<boolean> {
  if (input.httpStatus !== 200 || process.env.DOSA_EMISSION_ENABLED !== "true") return false;
  const companyId = requireTenant(user);
  const rawHash = createHash("sha256").update(JSON.stringify(input.body)).digest("hex");
  return db.$transaction(async tx => {
    const known = await tx.ecfElectronicDocument.findFirst({ where: { companyId, id: documentId }, select: { originalDocumentId: true } });
    if (!known) return false;
    const ids = [documentId, ...(known.originalDocumentId ? [known.originalDocumentId] : [])];
    await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id IN (${Prisma.join(ids.map(id => Prisma.sql`${id}::uuid`))}) ORDER BY id FOR UPDATE`;
    await tx.$queryRaw`SELECT company_id FROM ecf_company_configurations WHERE company_id = ${companyId}::uuid FOR SHARE`;
    const config = await tx.ecfCompanyConfiguration.findUnique({ where: { companyId } });
    const document = await tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: documentId } });
    const authorizedStatuses = document.environment === "PRODUCTION" ? ["PRODUCTION_READY"] : ["AUTHORIZED_SANDBOX", "PRODUCTION_READY"];
    if (!config?.enabled || config.provider !== "DOSA" || config.environment !== document.environment ||
        !authorizedStatuses.includes(config.certificationStatus) ||
        (document.environment === "PRODUCTION" && !config.productionEnabled)) return false;
    if (document.environment === "PRODUCTION") {
      if (process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED !== "true" ||
          process.env.DOSA_PRODUCTION_EMISSION_ENABLED !== "true") return false;
    } else if (document.environment !== "SANDBOX" || config.productionEnabled) return false;
    const receipt = await tx.ecfEvidenceReceipt.findFirst({ where: { companyId, documentId, id: input.receiptId,
      attemptId: input.attemptId, source: "PROVIDER_RESPONSE", eventKey: `emission:${input.attemptId}`, rawSha256: rawHash, httpStatus: 200 } });
    const attempt = await tx.ecfElectronicDocumentAttempt.findFirst({ where: { companyId, documentId, id: input.attemptId, operation: { in: ["SEND_TO_PROVIDER", "QUERY_PROVIDER"] } } });
    if (!receipt || !attempt || (attempt.operation === "SEND_TO_PROVIDER" && attempt.idempotencyKey !== document.idempotencyKey) ||
        receipt.operationKeyHash !== createHash("sha256").update(document.idempotencyKey).digest("hex") ||
        receipt.documentFingerprint !== document.payloadFingerprint ||
        receipt.requestFingerprint !== attempt.requestFingerprint) return false;
    if (attempt.operation === "QUERY_PROVIDER" && !await tx.ecfElectronicDocumentStatusLog.findFirst({
      where: { companyId, documentId, reasonCode: DOSA_PERSISTED_REQUEST, metadata: { path: ["attemptId"], equals: attempt.id } }, select: { id: true } })) return false;
    const fiscal = document.fiscalDocument as EcfFiscalDocument | null;
    if (!fiscal || fiscal.currency !== "DOP" || fingerprint(fiscal) !== document.payloadFingerprint ||
        fiscal.type !== document.documentType || !document.externalDocumentNumber || !document.externalProviderId || !document.environment) return false;
    const observation = assessDosaProviderResponse(200, input.body, { documentType: fiscal.type,
      expectedEncf: document.externalDocumentNumber, expectedTaxId: fiscal.sender.taxId });
    if (!observation.correlated || observation.observedOutcome !== "ACCEPTED" || observation.sequenceConsumed !== true ||
        (observation.remoteId !== document.externalProviderId &&
          document.externalProviderId !== `DOSA_PENDING:${document.environment}:${fiscal.sender.taxId}:${document.externalDocumentNumber}`)) return false;
    if (await tx.ecfElectronicDocument.findFirst({ where: { companyId, environment: document.environment,
      externalProviderId: document.externalProviderId, id: { not: documentId } }, select: { id: true } })) return false;
    const stamp = dosaPrintStamp(input.body, { encf: document.externalDocumentNumber, rnc: fiscal.sender.taxId,
      environment: document.environment, total: String(fiscal.totals.total), issueDate: fiscal.issueDate, buyerRnc: fiscal.buyer?.taxId });
    const persistedStamp = (document.printStamp ?? (document.payloadSummary as Prisma.JsonObject | null)?.printStamp) as typeof stamp;
    if (!stamp || !persistedStamp || ["qrUrl", "securityCode", "signedAt"].some(key =>
      stamp[key as keyof typeof stamp] !== persistedStamp[key as keyof typeof persistedStamp])) return false;
    const evidenceRef = `dosa:receipt:${receipt.id}`;
    const oldSnapshot = document.fiscalSnapshot as Prisma.JsonObject | null;
    if (document.status === "DGII_ACCEPTED") return oldSnapshot?.evidenceRef === evidenceRef && oldSnapshot?.evidenceHash === rawHash;
    if (document.status !== "HUMAN_REVIEW_REQUIRED" || oldSnapshot !== null) return false;
    const conditional = observation.safeCode === "ECF_DOSA_OBSERVED_CONDITIONALLY_ACCEPTED";
    await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: documentId, status: "HUMAN_REVIEW_REQUIRED" }, data: {
      status: "DGII_ACCEPTED", fiscalSnapshot: { encf: document.externalDocumentNumber, currency: fiscal.currency,
        issueDate: fiscal.issueDate, issuerRnc: fiscal.sender.taxId, total: moneyString(fiscal.totals.total), evidenceRef, evidenceHash: rawHash,
        providerContract: DOSA_CONFIRMED_OUTCOME_CONTRACT },
      safeErrorCode: conditional ? "DOSA_CONFIRMED_DGII_CONDITIONAL" : "DOSA_CONFIRMED_DGII_ACCEPTED",
      safeErrorMessage: conditional ? "Aceptación condicional comunicada por DOSA y registrada con evidencia. Revisa las observaciones del comprobante."
        : "Resultado DGII comunicado por DOSA, correlacionado y registrado con evidencia del envío.",
    } });
    await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId, statusBefore: "HUMAN_REVIEW_REQUIRED", statusAfter: "DGII_ACCEPTED",
      changedByUserId: user.id, reasonCode: "DOSA_CONFIRMED_DGII_ACCEPTED", metadata: {
        evidenceRef, evidenceHash: rawHash, receiptId: receipt.id, attemptId: attempt.id,
        providerContract: DOSA_CONFIRMED_OUTCOME_CONTRACT, authority: "DOSA_REPORTED_DGII_RESULT",
        providerOutcomeCode: observation.safeCode,
        trustLevel: "PROVIDER_DECLARED", environment: document.environment,
      } } });
    if (document.documentType === "E34") await new EcfE34CreditService(db).transitionInTransaction(tx, user, documentId, "APPLIED");
    return true;
  }, { timeout: 30000 });
}
