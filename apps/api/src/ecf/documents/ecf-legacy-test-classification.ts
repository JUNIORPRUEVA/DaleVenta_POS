import { EcfElectronicDocumentStatus, Prisma, PrismaClient } from "@prisma/client";
import { fingerprint } from "./ecf-document-idempotency.service";
import { dosaPrintStamp } from "../provider/dosa/dosa-print-stamp";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hash = /^[0-9a-f]{64}$/;
type Scope = { companyId: string; issuerRnc: string; documentIds: string[] };
type ReviewDocument = {
  id: string; type: string; status: EcfElectronicDocumentStatus; fingerprint: string; encf: string;
  evidencePlan: string; evidenceSha256: string; allocationId: string;
  outcome: string; externalDocumentNumber: string | null;
  originalDocumentId: string | null; sourceType: string | null; sourceId: string | null;
  printStamp: ReturnType<typeof dosaPrintStamp>;
};
export type LegacyTestReview = {
  version: "fullpos.legacy-test-classification.v1";
  scope: Scope;
  documents: ReviewDocument[];
  configuration: { environment: string; productionEnabled: boolean };
  // Original allocation records and range counters are never rewritten.
  ranges: Array<{ id: string; documentType: string; startNumber: number; nextNumber: number; endNumber: number; active: boolean }>;
  minimumTestNext: Record<string, number>;
  manifestHash: string;
};
function fail(code: string): never { throw new Error(`ECF_LEGACY_REVIEW_${code}`); }
function validateScope(scope: Scope) {
  if (!uuid.test(scope.companyId) || !/^\d{9,11}$/.test(scope.issuerRnc) ||
      !Array.isArray(scope.documentIds) || scope.documentIds.length < 1 || scope.documentIds.length > 100 ||
      new Set(scope.documentIds).size !== scope.documentIds.length || scope.documentIds.some(id => !uuid.test(id))) fail("INVALID_SCOPE");
}

async function snapshot(tx: Prisma.TransactionClient, scope: Scope): Promise<Omit<LegacyTestReview, "manifestHash">> {
  validateScope(scope);
  const config = await tx.ecfCompanyConfiguration.findUnique({ where: { companyId: scope.companyId }, select: { environment: true, productionEnabled: true } });
  if (!config || config.environment !== "SANDBOX" || config.productionEnabled) fail("TEST_CONFIGURATION_REQUIRED");
  const rows = await tx.ecfElectronicDocument.findMany({
    where: { companyId: scope.companyId, id: { in: scope.documentIds } }, orderBy: { id: "asc" },
    select: { id: true, documentType: true, status: true, payloadFingerprint: true, fiscalDocument: true, payloadSummary: true,
      externalDocumentNumber: true, originalDocumentId: true, sourceType: true, sourceId: true },
  });
  if (rows.length !== scope.documentIds.length) fail("DOCUMENT_NOT_FOUND");
  const relatedIds = [...new Set([...scope.documentIds, ...rows.map(row => row.originalDocumentId).filter((id): id is string => id !== null)])];
  // to_jsonb also works before the environment column has been deployed.
  const identities = await tx.$queryRaw<Array<{ id: string; environment: string | null }>>`
    SELECT d.id, to_jsonb(d)->>'environment' AS environment FROM ecf_electronic_documents d
    WHERE d.company_id = ${scope.companyId}::uuid AND d.id IN (${Prisma.join(relatedIds.map(id => Prisma.sql`${id}::uuid`))})
  `;
  if (identities.some(row => scope.documentIds.includes(row.id) && row.environment !== null && row.environment !== "SANDBOX")) fail("ENVIRONMENT_ALREADY_BOUND");
  for (const row of rows) {
    if (row.originalDocumentId) {
      const original = identities.find(item => item.id === row.originalDocumentId);
      if (!original || (!scope.documentIds.includes(original.id) && original.environment !== "SANDBOX")) fail("ORIGINAL_REQUIRES_SAME_TEST_REVIEW");
    }
  }
  const allocations = await tx.ecfSequenceAuditLog.findMany({
    where: { companyId: scope.companyId, documentId: { in: scope.documentIds }, action: "ALLOCATED" },
    select: { id: true, documentId: true, encf: true, type: true },
  });
  const ranges = await tx.ecfSequence.findMany({ where: { companyId: scope.companyId }, orderBy: { id: "asc" },
    select: { id: true, documentType: true, startNumber: true, nextNumber: true, endNumber: true, active: true } });
  const minimumTestNext: Record<string, number> = {};
  const documents = rows.map(row => {
    const fiscal = row.fiscalDocument as Record<string, any> | null;
    const summary = row.payloadSummary as Record<string, any> | null;
    const proof = summary?.controlledTest;
    const encf = summary?.emission?.encf;
    if (!fiscal || fiscal.sender?.taxId !== scope.issuerRnc || fiscal.type !== row.documentType ||
        fingerprint(fiscal) !== row.payloadFingerprint) fail("FISCAL_IDENTITY_OR_FINGERPRINT_MISMATCH");
    if (proof?.environment !== "TEST" || proof.correlated !== true || !hash.test(proof.responseSha256 ?? "") ||
        typeof proof.plan !== "string" || !/^[A-Z0-9_:-]{1,128}$/.test(proof.plan) ||
        !["ACCEPTED", "CONDITIONALLY_ACCEPTED", "REJECTED", "IN_PROCESS"].includes(proof.outcome)) fail("TEST_EVIDENCE_REQUIRED");
    if (typeof encf !== "string" || !new RegExp(`^${row.documentType}\\d{10}$`).test(encf)) fail("ENCF_REQUIRED");
    if (row.externalDocumentNumber !== null && row.externalDocumentNumber !== encf) fail("ENCF_MISMATCH");
    const ledger = allocations.filter(a => a.documentId === row.id && a.encf === encf && a.type === row.documentType);
    if (ledger.length !== 1 || allocations.filter(a => a.documentId === row.id).length !== 1) fail("ALLOCATION_MISMATCH");
    const number = Number(encf.slice(3));
    let storedResponse: unknown = proof.safeResponse;
    if (typeof storedResponse === "string") {
      try { storedResponse = storedResponse.length <= 65536 ? JSON.parse(storedResponse) : null; }
      catch { storedResponse = null; }
    }
    const printStamp = dosaPrintStamp(storedResponse, { encf, rnc: scope.issuerRnc, environment: "SANDBOX",
      total: String(fiscal.totals?.total), buyerRnc: fiscal.buyer?.taxId, issueDate: fiscal.issueDate });
    if (summary?.printStamp && fingerprint(summary.printStamp) !== fingerprint(printStamp)) fail("PRINT_STAMP_CONFLICT");
    minimumTestNext[row.documentType] = Math.max(minimumTestNext[row.documentType] ?? 1, number + 1,
      ...ranges.filter(r => r.documentType === row.documentType).map(r => r.nextNumber));
    return { id: row.id, type: row.documentType, status: row.status, fingerprint: row.payloadFingerprint,
      encf, evidencePlan: proof.plan, evidenceSha256: proof.responseSha256, allocationId: ledger[0].id,
      outcome: proof.outcome, externalDocumentNumber: row.externalDocumentNumber,
      originalDocumentId: row.originalDocumentId, sourceType: row.sourceType, sourceId: row.sourceId, printStamp };
  });
  return { version: "fullpos.legacy-test-classification.v1", scope: { ...scope, documentIds: [...scope.documentIds].sort() },
    configuration: config, documents, ranges, minimumTestNext };
}

/** Default operation is read-only and works both before and after the new column. */
export async function planLegacyTestClassification(db: PrismaClient, scope: Scope): Promise<LegacyTestReview> {
  return db.$transaction(async tx => {
    await tx.$executeRaw`SET TRANSACTION READ ONLY`;
    const plan = await snapshot(tx, scope);
    return { ...plan, manifestHash: fingerprint(plan) };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
}

/** Operational entry point only, never an HTTP endpoint. Caller must approve the exact manifest. */
export async function applyLegacyTestClassification(db: PrismaClient, review: LegacyTestReview, approvedHash: string, reviewer: string) {
  if (!review || !hash.test(approvedHash) || approvedHash !== review.manifestHash || !reviewer?.trim() || reviewer.length > 120) fail("EXPLICIT_REVIEW_REQUIRED");
  const { manifestHash, ...body } = review;
  if (fingerprint(body) !== manifestHash) fail("MANIFEST_TAMPERED");
  validateScope(review.scope);
  return db.$transaction(async tx => {
    await tx.$queryRaw`SELECT company_id FROM ecf_company_configurations WHERE company_id = ${review.scope.companyId}::uuid FOR SHARE`;
    await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${review.scope.companyId}::uuid AND id IN (${Prisma.join(review.scope.documentIds.map(id => Prisma.sql`${id}::uuid`))}) ORDER BY id FOR UPDATE`;
    const current = await snapshot(tx, review.scope);
    if (fingerprint(current) !== manifestHash) fail("STALE_MANIFEST");
    const transaction = await tx.$queryRaw<Array<{ id: string }>>`SELECT txid_current()::text AS id`;
    let classified = 0;
    for (const document of review.documents) {
      const row = await tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: review.scope.companyId, id: document.id }, select: { environment: true, payloadSummary: true } });
      if (row.environment === "SANDBOX") {
        const prior = await tx.ecfElectronicDocumentStatusLog.findFirst({ where: { companyId: review.scope.companyId, documentId: document.id,
          reasonCode: "LEGACY_TEST_ENVIRONMENT_CLASSIFIED", metadata: { path: ["manifestHash"], equals: manifestHash } } });
        if (!prior) fail("ALREADY_CLASSIFIED_DIFFERENT_REVIEW");
        continue;
      }
      if (row.environment !== null) fail("ENVIRONMENT_ALREADY_BOUND");
      await tx.ecfElectronicDocumentStatusLog.create({ data: {
        companyId: review.scope.companyId, documentId: document.id,
        statusBefore: document.status, statusAfter: document.status,
        reasonCode: "LEGACY_TEST_ENVIRONMENT_CLASSIFIED",
        safeMessage: "Documento histórico clasificado TEST por revisión explícita; sin emisión ni cambio de resultado fiscal.",
        metadata: { transactionId: transaction[0].id, documentFingerprint: document.fingerprint,
          environment: "SANDBOX", manifestHash, reviewer: reviewer.trim(), evidencePlan: document.evidencePlan,
          evidenceSha256: document.evidenceSha256, originalAllocationId: document.allocationId,
          originalAllocationPreserved: true, printStampRestored: document.printStamp !== null },
      } });
      await tx.ecfElectronicDocument.updateMany({ where: { companyId: review.scope.companyId, id: document.id, environment: null }, data: {
        environment: "SANDBOX", ...(document.printStamp ? { printStamp: document.printStamp } : {}),
      } });
      classified++;
    }
    return { companyId: review.scope.companyId, manifestHash, classified, unchanged: review.documents.length - classified };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable, timeout: 30000 });
}
