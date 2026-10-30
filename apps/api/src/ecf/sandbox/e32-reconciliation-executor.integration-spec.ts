import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { Prisma } from "@prisma/client";
import type { EcfElectronicDocumentStatus } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import { fingerprint } from "../documents/ecf-document-idempotency.service";
import { assessAlanubeDomE32Compatibility, type E32CompatibilityAssessment } from "./alanube-dom-e32-compatibility";
import { E32ReconciliationExecutor, type E32ReconciliationRequest } from "./e32-reconciliation-executor";
import type { E32TrialManifest } from "./e32-sandbox.policy";

// Opt-in PostgreSQL UAT suite. Synthetic fixtures only; the real historical
// document/trial are read, never written. Normal runs never touch a database.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;
const ROLLBACK = Symbol("rollback");
const TENANT = "e7df7640-04ea-4000-9135-0c4451822205";
const HIST_DOCUMENT = "56cb2743-c4a0-4be4-a167-3cd5d0314f40";
const HIST_TRIAL = "2d552e31-4d6b-4ee2-a2b7-7caaf75484dd";
const RNC = "132109122";
const ISSUE_DATE = "2026-10-14";
const GET_SHA = "a".repeat(64);
const POST_SHA = "b".repeat(64);
type Tx = Prisma.TransactionClient;

uat("E32 authorized reconciliation executor (synthetic UAT)", () => {
  let prisma: PrismaService;
  let executor: E32ReconciliationExecutor;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" || process.env.ECF_EMISSION_ENABLED === "true") {
      throw new Error("E32_RECONCILIATION_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    executor = new E32ReconciliationExecutor(prisma);
  });
  afterAll(async () => { await prisma?.$disconnect(); });

  // Runs `fn` inside a transaction that always rolls back, so no synthetic row
  // ever persists. A savepoint lets `fn` assert on failures without poisoning.
  async function rolledBack(fn: (tx: Tx) => Promise<void>) {
    let failure: unknown;
    try {
      await prisma.$transaction(async (tx) => { await fn(tx); throw ROLLBACK; },
        { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
    } catch (error) { if (error !== ROLLBACK) failure = error; }
    if (failure) throw failure;
  }

  type Fixture = {
    companyId: string; actorUserId: string; operationId: string; documentId: string; trialId: string;
    remoteId: string; encf: string; manifest: E32TrialManifest;
  };

  async function createFixture(client: Tx, opts: {
    documentStatus?: EcfElectronicDocumentStatus; trialState?: string; postAttempts?: number; queryAttempts?: number;
  } = {}): Promise<Fixture> {
    const companyId = randomUUID();
    await client.company.create({ data: { id: companyId, name: "Synthetic E32 reconciliation", slug: `ecf-reconcile-${companyId}` } });
    const actorUserId = randomUUID();
    const operationId = randomUUID();
    const remoteId = "0" + randomUUID().replace(/-/g, "").slice(0, 25).toUpperCase();
    const encf = "E32" + String(Math.floor(Math.random() * 1e10)).padStart(10, "0");
    const manifest: E32TrialManifest = {
      version: 1, mode: "MOCK_ONLY", clientRequestId: operationId,
      sender: { legalName: "SYNTHETIC RECONCILE", taxId: RNC, address: "Synthetic test address" },
      issueDate: ISSUE_DATE, metadata: { encf, paymentType: 1, incomeType: 1 },
      companyAuthorizationRef: "mock://not-real-provider-authorization",
      numbering: { from: encf, to: encf, validUntil: "2028-12-31", authorizationRef: "mock://not-a-real-range" },
    };
    const idempotencyKey = `ecf:v2:${companyId}:E32:REQUEST:${operationId}`;
    const document = await client.ecfElectronicDocument.create({ data: {
      companyId, documentType: "E32", status: opts.documentStatus ?? "UNKNOWN_RESULT", idempotencyKey,
      payloadFingerprint: fingerprint(manifest), createdByUserId: actorUserId, updatedByUserId: actorUserId } });
    const payload = { totals: { totalAmount: "168.00" } };
    const trial = await client.ecfSandboxE32Trial.create({ data: {
      companyId, documentId: document.id, slot: `MOCK_ONLY:${companyId}`, mode: "MOCK_ONLY",
      manifest: manifest as unknown as Prisma.InputJsonValue, manifestFingerprint: fingerprint(manifest),
      payload: payload as Prisma.InputJsonValue, payloadFingerprint: fingerprint(payload) } });
    const target = opts.trialState ?? "UNKNOWN_RESULT";
    if (target !== "PREPARED") {
      await client.ecfSandboxE32Trial.updateMany({ where: { companyId, id: trial.id, state: "PREPARED" }, data: { state: "CLAIMED" } });
      if (target !== "CLAIMED") {
        await client.ecfSandboxE32Trial.updateMany({ where: { companyId, id: trial.id, state: "CLAIMED" }, data: { state: target } });
      }
    }
    await client.ecfSandboxE32TrialEvent.create({ data: { companyId, trialId: trial.id, kind: "POST_OBSERVATION",
      safeCode: "E32_OBSERVED_ACCEPTED", bodySha256: POST_SHA, httpStatus: 201 } });
    const posts = opts.postAttempts ?? 1;
    for (let index = 0; index < posts; index += 1) {
      await client.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId: document.id,
        operation: "SEND_TO_PROVIDER", idempotencyKey: index === 0 ? idempotencyKey : `${idempotencyKey}:dup${index}`,
        requestFingerprint: POST_SHA, createdByUserId: actorUserId } });
    }
    for (let index = 0; index < (opts.queryAttempts ?? 0); index += 1) {
      await client.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId: document.id,
        operation: "QUERY_PROVIDER", idempotencyKey: `${idempotencyKey}:q${index}`, requestFingerprint: GET_SHA, createdByUserId: actorUserId } });
    }
    return { companyId, actorUserId, operationId, documentId: document.id, trialId: trial.id, remoteId, encf, manifest };
  }

  function body(fixture: Fixture, override: Record<string, unknown> = {}) {
    return { id: fixture.remoteId, documentNumber: fixture.encf, companyIdentification: RNC, status: "FINISHED",
      legalStatus: "ACCEPTED", sequenceConsumed: true, stampDate: `${ISSUE_DATE}T00:00:00.000Z`, trackId: null,
      signatureDate: "14-10-2026 16:59:42", ...override };
  }
  function assess(fixture: Fixture, override: Record<string, unknown> = {}, companyId = fixture.companyId) {
    return assessAlanubeDomE32Compatibility(200, body(fixture, override), {
      provider: "ALANUBE_DOM", environment: "SANDBOX", endpoint: "GET_E32_TOKEN_PRIMARY",
      companyId, verifiedCompanyId: companyId, operationId: fixture.operationId, remoteId: fixture.remoteId,
      encf: fixture.encf, rnc: RNC, issueDate: ISSUE_DATE, totalAmount: 168,
      expectedLegalStatus: "ACCEPTED", expectedSequenceConsumed: true });
  }
  function request(fixture: Fixture, override: Partial<E32ReconciliationRequest> = {}): E32ReconciliationRequest {
    return { companyId: fixture.companyId, actorUserId: fixture.actorUserId, operationId: fixture.operationId,
      documentId: fixture.documentId, trialId: fixture.trialId, remoteId: fixture.remoteId, encf: fixture.encf, rnc: RNC,
      rawSha256: GET_SHA, evidenceChainVerified: true, encryptedArchiveVerified: true, assessment: assess(fixture), ...override };
  }
  async function addBareDocument(client: Tx, companyId: string) {
    return client.ecfElectronicDocument.create({ data: { companyId, documentType: "E32", status: "LOCAL_DRAFT",
      idempotencyKey: `ecf:v2:${companyId}:E32:REQUEST:${randomUUID()}`, payloadFingerprint: "c".repeat(64) } });
  }
  async function addGhostReceipt(client: Tx, companyId: string, operationId: string, actorUserId: string) {
    const document = await addBareDocument(client, companyId);
    const attempt = await client.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId: document.id,
      operation: "QUERY_PROVIDER", idempotencyKey: `ghost:${randomUUID()}`, requestFingerprint: "d".repeat(64) } });
    await client.ecfEvidenceReceipt.create({ data: { companyId, documentId: document.id, attemptId: attempt.id,
      source: "PROVIDER_RESPONSE", eventKey: `reconcile:${operationId}`, rawSha256: "e".repeat(64), correlationHash: "f".repeat(64),
      operationKeyHash: "1".repeat(64), documentFingerprint: "2".repeat(64), requestFingerprint: "3".repeat(64),
      trustLevel: "PROVIDER_DECLARED", authenticity: "BLOCKED_PENDING_PROVIDER_CONTRACT",
      validationCode: "OFFICIAL_SCHEMA_INVALID", observationCode: "E32_OBSERVED_ACCEPTED", httpStatus: 200, actorUserId } });
  }

  it("1: reconciles a synthetic Sandbox E32 into HUMAN_REVIEW_REQUIRED without fiscal acceptance", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      const req = request(fixture);
      const dry = await executor.reconcile(req, { client: tx });
      expect(dry.mode).toBe("DRY_RUN");
      expect(dry.plan).toMatchObject({ result: "READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION", canApply: false, canGrantDgiiAcceptance: false });
      const applied = await executor.reconcile(req, { execute: true, client: tx });
      expect(applied).toMatchObject({ mode: "APPLY", result: "APPLIED", documentStatus: "HUMAN_REVIEW_REQUIRED", remoteId: fixture.remoteId, encf: fixture.encf });
      expect(await tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: fixture.companyId, id: fixture.documentId } }))
        .toMatchObject({ status: "HUMAN_REVIEW_REQUIRED", externalProviderId: fixture.remoteId, externalDocumentNumber: fixture.encf, fiscalSnapshot: null });
      // The consumed trial is terminal and never reset.
      expect((await tx.ecfSandboxE32Trial.findFirstOrThrow({ where: { companyId: fixture.companyId, id: fixture.trialId } })).state).toBe("UNKNOWN_RESULT");
      // No fiscal authority was granted anywhere.
      expect(await tx.ecfElectronicDocument.count({ where: { companyId: fixture.companyId, status: "DGII_ACCEPTED" } })).toBe(0);
    });
  });

  it("2: identical replay is a no-op", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      const req = request(fixture);
      await executor.reconcile(req, { execute: true, client: tx });
      const receipts = await tx.ecfEvidenceReceipt.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId } });
      const logs = await tx.ecfElectronicDocumentStatusLog.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId } });
      expect(await executor.reconcile(req, { execute: true, client: tx })).toMatchObject({ mode: "APPLY", result: "ALREADY_RECONCILED" });
      expect(await tx.ecfEvidenceReceipt.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId } })).toBe(receipts);
      expect(await tx.ecfElectronicDocumentStatusLog.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId } })).toBe(logs);
    });
  });

  it("3: rejects a divergent reconciliation under the same key", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      const req = request(fixture);
      const key = (await executor.reconcile(req, { client: tx })).plan.idempotencyKey;
      await tx.ecfElectronicDocumentAttempt.create({ data: { companyId: fixture.companyId, documentId: fixture.documentId,
        operation: "QUERY_PROVIDER", idempotencyKey: key, requestFingerprint: "f".repeat(64), createdByUserId: fixture.actorUserId } });
      await expect(executor.reconcile(req, { execute: true, client: tx })).rejects.toThrow("E32_RECONCILIATION_REPLAY_CONFLICT");
    });
  });

  it("4: refuses a wrong previous state and writes nothing", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx, { documentStatus: "LOCAL_VALIDATED" });
      const req = request(fixture);
      expect((await executor.reconcile(req, { client: tx })).plan.result).toBe("BLOCKED");
      await expect(executor.reconcile(req, { execute: true, client: tx })).rejects.toThrow("E32_RECONCILIATION_PRECONDITIONS_NOT_MET");
      expect((await tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: fixture.companyId, id: fixture.documentId } })).status).toBe("LOCAL_VALIDATED");
      expect(await tx.ecfEvidenceReceipt.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId } })).toBe(0);
    });
  });

  it("5: rejects a different remote identifier", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      await expect(executor.reconcile(request(fixture, { remoteId: "0" + "1".repeat(25) }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_CORRELATION_MISMATCH");
      const forged = assess(fixture, { id: "0" + "2".repeat(25) });
      await expect(executor.reconcile(request(fixture, { assessment: forged }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_OUTCOME_NOT_REVIEWABLE");
    });
  });

  it("6: rejects a mismatched e-NCF", async () => {
    await rollbackRequest((fixture) => request(fixture, { encf: "E329999999999" }), "E32_RECONCILIATION_ENCF_MISMATCH");
  });

  it("7: rejects another company and a mismatched correlation company", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      await expect(executor.reconcile(request(fixture, { companyId: randomUUID() }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_DOCUMENT_NOT_FOUND");
      const elsewhere = randomUUID();
      await expect(executor.reconcile(request(fixture, { assessment: assess(fixture, {}, elsewhere) }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_CORRELATION_MISMATCH");
    });
  });

  it("8: rejects tampered evidence or forged fiscal authority", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      await expect(executor.reconcile(request(fixture, { rawSha256: "nope" }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_EVIDENCE_HASH_INVALID");
      await expect(executor.reconcile(request(fixture, { evidenceChainVerified: false }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_EVIDENCE_UNVERIFIED");
      const forged = JSON.parse(JSON.stringify(assess(fixture))) as Record<string, unknown>;
      forged.canUpdateFiscalStatus = true;
      await expect(executor.reconcile(request(fixture, { assessment: forged as unknown as E32CompatibilityAssessment }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_AUTHORITY_VIOLATION");
    });
  });

  it("9: rolls back atomically when the transaction fails mid-way", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      await addGhostReceipt(tx, fixture.companyId, fixture.operationId, fixture.actorUserId);
      await tx.$executeRawUnsafe("SAVEPOINT reconciliation");
      await expect(executor.reconcile(request(fixture), { execute: true, client: tx })).rejects.toThrow();
      await tx.$executeRawUnsafe("ROLLBACK TO SAVEPOINT reconciliation");
      // Every write performed before the failing statement was undone.
      expect(await tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: fixture.companyId, id: fixture.documentId } }))
        .toMatchObject({ status: "UNKNOWN_RESULT", externalProviderId: null, externalDocumentNumber: null });
      expect(await tx.ecfElectronicDocumentStatusLog.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId, reasonCode: "E32_PROVIDER_ACCEPTED_OBSERVED" } })).toBe(0);
      expect(await tx.ecfEvidenceReceipt.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId } })).toBe(0);
    });
  });

  it("10: serializes two concurrent executions to a single reconciliation", async () => {
    const fixture = await createFixture(prisma as unknown as Tx);
    const req = request(fixture);
    const outcomes = await Promise.allSettled([
      prisma.$transaction((tx) => executor.reconcile(req, { execute: true, client: tx }), { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead }),
      prisma.$transaction((tx) => executor.reconcile(req, { execute: true, client: tx }), { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead }),
    ]);
    const applied = outcomes.filter((o) => o.status === "fulfilled" && o.value.mode === "APPLY" && o.value.result === "APPLIED");
    expect(applied).toHaveLength(1);
    expect(await prisma.ecfEvidenceReceipt.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId } })).toBe(1);
    expect(await prisma.ecfElectronicDocumentStatusLog.count({ where: { companyId: fixture.companyId, documentId: fixture.documentId, reasonCode: "E32_PROVIDER_ACCEPTED_OBSERVED" } })).toBe(1);
    expect((await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: fixture.companyId, id: fixture.documentId } })).status).toBe("HUMAN_REVIEW_REQUIRED");
  });

  it("11: refuses to reconcile a different document/trial pair", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      const other = await addBareDocument(tx, fixture.companyId);
      await expect(executor.reconcile(request(fixture, { documentId: other.id }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_DOCUMENT_TRIAL_MISMATCH");
      const unrelated = await createFixture(tx);
      await expect(executor.reconcile(request(fixture, { trialId: unrelated.trialId }), { client: tx }))
        .rejects.toThrow("E32_RECONCILIATION_TRIAL_NOT_FOUND");
    });
  });

  it("12: refuses to run outside the isolated UAT target", async () => {
    const previous = process.env.UAT_LOCAL_ONLY;
    process.env.UAT_LOCAL_ONLY = "false";
    try {
      const fixture = { companyId: randomUUID(), actorUserId: randomUUID(), operationId: randomUUID(),
        documentId: randomUUID(), trialId: randomUUID(), remoteId: "0" + "3".repeat(25), encf: "E320000000001", rnc: RNC } as unknown as Fixture;
      await expect(executor.reconcile(request(fixture))).rejects.toThrow("E32_RECONCILIATION_UAT_REQUIRED");
    } finally {
      process.env.UAT_LOCAL_ONLY = previous;
    }
  });

  it("13: records append-only, review-only audit evidence", async () => {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      await executor.reconcile(request(fixture), { execute: true, client: tx });
      const log = await tx.ecfElectronicDocumentStatusLog.findFirstOrThrow({ where: { companyId: fixture.companyId, documentId: fixture.documentId, reasonCode: "E32_PROVIDER_ACCEPTED_OBSERVED" } });
      expect(log.statusBefore).toBe("UNKNOWN_RESULT");
      expect(log.statusAfter).toBe("HUMAN_REVIEW_REQUIRED");
      expect(log.metadata).toMatchObject({ observedProvider: { legalStatus: "ACCEPTED", providerStatus: "FINISHED", sequenceConsumed: true }, dgiiAcceptance: false, receiptTrust: "PROVIDER_DECLARED", publishedValidation: "OFFICIAL_SCHEMA_INVALID" });
      const receipt = await tx.ecfEvidenceReceipt.findFirstOrThrow({ where: { companyId: fixture.companyId, documentId: fixture.documentId } });
      expect(receipt).toMatchObject({ source: "PROVIDER_RESPONSE", trustLevel: "PROVIDER_DECLARED", authenticity: "BLOCKED_PENDING_PROVIDER_CONTRACT", validationCode: "OFFICIAL_SCHEMA_INVALID", observationCode: "E32_PROVIDER_ACCEPTED_OBSERVED", httpStatus: 200 });
      expect(await tx.ecfSandboxE32TrialEvent.count({ where: { companyId: fixture.companyId, trialId: fixture.trialId, kind: "RECONCILIATION" } })).toBe(1);
      // Append-only: records can never be altered or deleted.
      await tx.$executeRawUnsafe("SAVEPOINT audit");
      await expect(tx.ecfEvidenceReceipt.deleteMany({ where: { companyId: fixture.companyId, documentId: fixture.documentId } })).rejects.toThrow();
      await tx.$executeRawUnsafe("ROLLBACK TO SAVEPOINT audit");
    });
  });

  it("14: preserves the reconciled historical E32 document and its terminal trial without fiscal authority", async () => {
    const document = await prisma.ecfElectronicDocument.findFirst({ where: { companyId: TENANT, id: HIST_DOCUMENT } });
    if (!document) { console.warn("historical E32 document absent; preservation check skipped"); return; }
    const receipts = await prisma.ecfEvidenceReceipt.count({ where: { companyId: TENANT, documentId: HIST_DOCUMENT } });
    const queries = await prisma.ecfElectronicDocumentAttempt.count({ where: { companyId: TENANT, documentId: HIST_DOCUMENT, operation: "QUERY_PROVIDER" } });
    if (document.status === "UNKNOWN_RESULT") {
      // Pre-reconciliation: identity unbound, no quarantined receipt, no documented query.
      expect(document).toMatchObject({ externalProviderId: null, externalDocumentNumber: null });
      expect(receipts).toBe(0); expect(queries).toBe(0);
    } else if (document.status === "HUMAN_REVIEW_REQUIRED") {
      // Post-reconciliation: bound to the observed provider identity only, awaiting human review.
      expect(document).toMatchObject({ externalProviderId: "01M4Y3DEPXXG27G8BNQGMNQ04B", externalDocumentNumber: "E320009805001" });
      expect(receipts).toBe(1); expect(queries).toBe(1);
    } else {
      throw new Error(`unexpected historical document status: ${document.status}`);
    }
    // Invariants that must hold in every state.
    expect(document.fiscalSnapshot).toBeNull();
    expect((await prisma.ecfSandboxE32Trial.findFirst({ where: { companyId: TENANT, id: HIST_TRIAL } }))?.state).toBe("UNKNOWN_RESULT");
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId: TENANT, status: { in: ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] } } })).toBe(0);
  });

  async function rollbackRequest(build: (fixture: Fixture) => E32ReconciliationRequest, code: string) {
    await rolledBack(async (tx) => {
      const fixture = await createFixture(tx);
      await expect(executor.reconcile(build(fixture), { client: tx })).rejects.toThrow(code);
    });
  }
});
