import { randomUUID } from "node:crypto";
import { isEcfLocalTarget, matchEcfLocalTarget } from "../ecf-local-target";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfEvidenceIngestionService, type EvidenceIntake } from "./ecf-evidence-ingestion.service";
import { EcfBlockedAuthenticityVerifier } from "./ecf-evidence-authenticity.service";
import { EcfEvidenceAuthenticityVerifier, digestEvidence } from "./ecf-evidence.policy";

const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;
uat("Evidence quarantine real PostgreSQL, synthetic data only", () => {
  let prisma: PrismaService, service: EcfEvidenceIngestionService;
  const companyIds = [randomUUID(), randomUUID()], actor = randomUUID();
  const user = (companyId = companyIds[0]): TenantUser => ({ id: actor, role: "ADMIN", companyId });
  const idOf = (input: EvidenceIntake): string => JSON.parse(input.raw.toString("utf8")).id;
  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" || process.env.ECF_EMISSION_ENABLED !== "false") throw Error("ECF_EVIDENCE_UAT_REFUSED");
    prisma = new PrismaService(); await prisma.$connect();
    expect((await prisma.$queryRaw<Array<{ name: string }>>`SELECT current_database() AS name`)[0].name).toBe(matchEcfLocalTarget()?.name);
    await prisma.company.createMany({ data: companyIds.map((id) => ({ id, slug: `ecf-91-100-${id}`, name: "Synthetic evidence quarantine fixtures" })) });
    service = new EcfEvidenceIngestionService(prisma, new EcfBlockedAuthenticityVerifier());
  });
  // Receipts are append-only. Retain fixtures and do not bypass DB protection.
  afterAll(async () => { await prisma?.$disconnect(); });
  async function fixture(companyId = companyIds[0]) {
    const remoteId = "0" + randomUUID().replace(/-/g, "").slice(0, 25).toUpperCase();
    const d = await prisma.ecfElectronicDocument.create({ data: { companyId, documentType: "E31", status: "UNKNOWN_RESULT",
      payloadFingerprint: "a".repeat(64), idempotencyKey: `v2:test:${randomUUID()}`, externalProviderId: remoteId } });
    const a = await prisma.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId: d.id, operation: "PREPARE",
      idempotencyKey: d.idempotencyKey, requestFingerprint: d.payloadFingerprint } });
    const input: EvidenceIntake = { documentId: d.id, attemptId: a.id, operationKey: d.idempotencyKey,
      documentFingerprint: d.payloadFingerprint, requestFingerprint: a.requestFingerprint!, source: "SYNTHETIC",
      eventKey: `test:${randomUUID()}`, raw: Buffer.from(JSON.stringify({ id: remoteId, status: "FINISHED" })), httpStatus: 201 };
    return { d, a, input };
  }
  it("synthetic evidence is permanently synthetic and cannot accept a document", async () => {
    const { d, input } = await fixture(); const receipt = await service.ingest(user(), input);
    expect(receipt).toMatchObject({ trustLevel: "SYNTHETIC", authenticity: "BLOCKED_PENDING_PROVIDER_CONTRACT", validationCode: "OFFICIAL_SCHEMA_VALID" });
    expect(await prisma.ecfElectronicDocument.findFirst({ where: { companyId: d.companyId, id: d.id } })).toMatchObject({ status: "UNKNOWN_RESULT", fiscalSnapshot: null });
    expect(await prisma.ecfElectronicDocumentStatusLog.count({ where: { companyId: d.companyId, documentId: d.id } })).toBe(0);
  });
  it("provider-declared response is unauthenticated despite a schema and id", async () => {
    const { input } = await fixture(); const row = await service.ingest(user(), { ...input, source: "PROVIDER_RESPONSE" });
    expect(row.trustLevel).toBe("PROVIDER_DECLARED"); expect(row.authenticity).toBe("BLOCKED_PENDING_PROVIDER_CONTRACT");
  });
  it("test-authenticated evidence cannot become real evidence in storage", async () => {
    class TestVerifier extends EcfEvidenceAuthenticityVerifier {
      async verify() { return { authenticated: true, contractScope: "TEST_ONLY" as const }; }
    }
    const testService = new EcfEvidenceIngestionService(prisma, new TestVerifier()), { input } = await fixture();
    expect(await testService.ingest(user(), input)).toMatchObject({ trustLevel: "SYNTHETIC", authenticity: "TEST_ONLY_AUTHENTICATED" });
    await expect(testService.ingest(user(), { ...input, source: "PROVIDER_RESPONSE" })).rejects.toThrow("ECF_EVIDENCE_AUTH_CONTRACT_UNAVAILABLE");
  });
  it("rejects unknown document/attempt correlation", async () => {
    const { input } = await fixture();
    await expect(service.ingest(user(), { ...input, documentId: randomUUID() })).rejects.toThrow("ECF_EVIDENCE_CORRELATION_NOT_FOUND");
    await expect(service.ingest(user(), { ...input, attemptId: randomUUID() })).rejects.toThrow("ECF_EVIDENCE_CORRELATION_NOT_FOUND");
  });
  it("rejects unknown/contradictory remote identifiers", async () => {
    const { input } = await fixture();
    await expect(service.ingest(user(), { ...input, raw: Buffer.from('{"id":"unknown","status":"FINISHED"}') })).rejects.toThrow("ECF_EVIDENCE_REMOTE_ID_MISMATCH");
  });
  it("rejects another tenant without changing either document", async () => {
    const { input } = await fixture();
    await expect(service.ingest(user(companyIds[1]), input)).rejects.toThrow("ECF_EVIDENCE_CORRELATION_NOT_FOUND");
    await expect(service.reconciliation(user(companyIds[1]), input.documentId)).rejects.toThrow("ECF_EVIDENCE_CORRELATION_NOT_FOUND");
  });
  it("same key has exact idempotent replay, including concurrent requests", async () => {
    const { input } = await fixture();
    const rows = await Promise.all(Array.from({ length: 6 }, () => service.ingest(user(), input)));
    expect(new Set(rows.map((row) => row.id)).size).toBe(1);
  });
  it("rejects incompatible duplicates and replay on a different document", async () => {
    const { input } = await fixture(), other = await fixture(); await service.ingest(user(), input);
    await expect(service.ingest(user(), { ...input, raw: Buffer.from(JSON.stringify({ id: idOf(input), status: "REGISTERED" })) })).rejects.toThrow("ECF_EVIDENCE_REPLAY_CONFLICT");
    await expect(service.ingest(user(), { ...other.input, eventKey: input.eventKey })).rejects.toThrow("ECF_EVIDENCE_REPLAY_CONFLICT");
  });
  it("retains out-of-order and contradictory observations without fiscal transitions", async () => {
    const { input } = await fixture(); await service.ingest(user(), input);
    await service.ingest(user(), { ...input, eventKey: `late:${randomUUID()}`, raw: Buffer.from(JSON.stringify({ id: idOf(input), status: "REGISTERED" })) });
    expect(await service.reconciliation(user(), input.documentId)).toMatchObject({ status: "UNKNOWN_RESULT", receiptCount: 2,
      hasMultiplePayloads: true, requiresManualReview: true, nextAction: "MANUAL_REVIEW", canUpdateFiscalStatus: false });
  });
  it("concurrent event replay across documents has one winner", async () => {
    const a = await fixture(), b = await fixture();
    const results = await Promise.allSettled([service.ingest(user(), a.input), service.ingest(user(), { ...b.input, eventKey: a.input.eventKey })]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(results.filter((result) => result.status === "rejected")).toHaveLength(1);
    expect(await prisma.ecfEvidenceReceipt.count({ where: { companyId: companyIds[0], source: "SYNTHETIC", eventKey: a.input.eventKey } })).toBe(1);
  });
  it("does not bind a remote identifier to a previously unassociated document", async () => {
    const { input } = await fixture();
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId: companyIds[0], id: input.documentId }, data: { externalProviderId: null } });
    await expect(service.ingest(user(), input)).rejects.toThrow("ECF_EVIDENCE_REMOTE_ID_MISMATCH");
    expect(await service.reconciliation(user(), input.documentId)).toMatchObject({ nextAction: "MANUAL_REVIEW", canQueryProvider: false });
  });
  it.each(["TIMEOUT", "NETWORK_ERROR", "PROCESS_RESTART"])("%s does not infer rejection or retry POST", async (reason) => {
    const { input } = await fixture();
    await service.ingest(user(), { ...input, source: "INTERNAL", httpStatus: undefined, raw: Buffer.from(JSON.stringify({ reason })) });
    expect(await service.reconciliation(user(), input.documentId)).toMatchObject({ status: "UNKNOWN_RESULT", canRetryFiscalPost: false, canReleaseReservation: false });
  });
  it("survives recreation of Prisma client and service", async () => {
    const { input } = await fixture(), first = await service.ingest(user(), input);
    const next = new PrismaService(); await next.$connect();
    try { expect((await new EcfEvidenceIngestionService(next, new EcfBlockedAuthenticityVerifier()).ingest(user(), input)).id).toBe(first.id); }
    finally { await next.$disconnect(); }
  });
  it("detects corruption/hash mismatch before database writes", async () => {
    const { input } = await fixture();
    await expect(service.ingest(user(), { ...input, expectedHash: digestEvidence("different") })).rejects.toThrow("ECF_EVIDENCE_HASH_MISMATCH");
    expect(await prisma.ecfEvidenceReceipt.count({ where: { companyId: companyIds[0], documentId: input.documentId } })).toBe(0);
  });
  it("quarantines invalid schemas and unexpected HTTP without storing payload", async () => {
    const { input } = await fixture(); const secretMarker = "synthetic-sensitive-content-not-a-secret";
    const row = await service.ingest(user(), { ...input, raw: Buffer.from(JSON.stringify({ status: 12, sensitive: secretMarker })), httpStatus: 200 });
    expect(row.validationCode).toBe("OFFICIAL_SCHEMA_INVALID"); expect(JSON.stringify(row)).not.toContain(secretMarker);
    expect(row).not.toHaveProperty("raw"); expect(row).not.toHaveProperty("payload");
  });
  it("rejects divergent operation and fingerprints", async () => {
    const { input } = await fixture();
    for (const mismatch of [{ operationKey: "other" }, { documentFingerprint: "b".repeat(64) }, { requestFingerprint: "c".repeat(64) }]) {
      await expect(service.ingest(user(), { ...input, ...mismatch })).rejects.toThrow("ECF_EVIDENCE_OPERATION_MISMATCH");
    }
  });
  it("webhook without verifiable authentication remains quarantined with replay protection", async () => {
    const { input } = await fixture();
    const raw = Buffer.from(JSON.stringify({ provider: "ALANUBE", eventId: input.eventKey, eventType: "document.updated", documentExternalId: idOf(input), payload: { status: "ACCEPTED" } }));
    const row = await service.ingest(user(), { ...input, raw, source: "WEBHOOK", httpStatus: undefined });
    expect(row).toMatchObject({ observationCode: "WEBHOOK_UNVERIFIED", authenticity: "BLOCKED_PENDING_PROVIDER_CONTRACT" });
    expect((await service.ingest(user(), { ...input, raw, source: "WEBHOOK", httpStatus: undefined })).id).toBe(row.id);
  });
  it("rejects malformed webhook or an event without remote correlation", async () => {
    const { input } = await fixture();
    for (const body of [{}, { provider: "ALANUBE", eventId: input.eventKey, eventType: "document.updated", payload: {} }]) {
      await expect(service.ingest(user(), { ...input, source: "WEBHOOK", raw: Buffer.from(JSON.stringify(body)) })).rejects.toThrow();
    }
  });
  it("rejects fiscal reference contradictions and external tenant claims", async () => {
    const { input } = await fixture();
    await expect(service.ingest(user(), { ...input, raw: Buffer.from(JSON.stringify({ id: idOf(input), status: "FINISHED", encf: "E340000000001" })) })).rejects.toThrow("ECF_EVIDENCE_FISCAL_REFERENCE_MISMATCH");
    await expect(service.ingest(user(), { ...input, raw: Buffer.from(JSON.stringify({ companyId: companyIds[1] })) })).rejects.toThrow("ECF_EVIDENCE_TENANT_CLAIM_FORBIDDEN");
  });
  it("database prevents trust promotion, overwrites and deletions", async () => {
    const { input } = await fixture(), row = await service.ingest(user(), input);
    await expect(prisma.ecfEvidenceReceipt.updateMany({ where: { companyId: row.companyId, id: row.id }, data: { trustLevel: "VERIFIED" } })).rejects.toThrow();
    await expect(prisma.ecfEvidenceReceipt.deleteMany({ where: { companyId: row.companyId, id: row.id } })).rejects.toThrow();
  });
  it("database prevents cross-tenant association and false fiscal trust on insert", async () => {
    const { input } = await fixture(), row = await service.ingest(user(), input);
    const { id: _id, ...data } = row;
    await expect(prisma.ecfEvidenceReceipt.create({ data: { ...data, companyId: companyIds[1] } })).rejects.toThrow();
    await expect(prisma.ecfEvidenceReceipt.create({ data: { ...data, eventKey: `bad:${randomUUID()}`, trustLevel: "FISCALLY_CONFIRMED" } })).rejects.toThrow();
  });
  it("database protects correlation after a receipt exists", async () => {
    const { input } = await fixture(); await service.ingest(user(), input);
    await expect(prisma.ecfElectronicDocument.updateMany({ where: { companyId: companyIds[0], id: input.documentId }, data: { payloadFingerprint: "c".repeat(64) } })).rejects.toThrow();
    await expect(prisma.ecfElectronicDocumentAttempt.updateMany({ where: { companyId: companyIds[0], id: input.attemptId }, data: { requestFingerprint: "c".repeat(64) } })).rejects.toThrow();
  });
  it("same external event key can coexist for two tenants", async () => {
    const one = await fixture(), two = await fixture(companyIds[1]);
    const a = await service.ingest(user(), one.input), b = await service.ingest(user(companyIds[1]), { ...two.input, eventKey: one.input.eventKey });
    expect(a.companyId).not.toBe(b.companyId);
  });
  it("no identity means no DB operation", async () => {
    const { input } = await fixture();
    await expect(service.ingest({ id: "", role: "ADMIN" }, input)).rejects.toThrow();
    await expect(service.ingest({ id: actor, role: "ADMIN" }, input)).rejects.toThrow();
  });
  it("rejects an ambiguous remote association instead of choosing a document", async () => {
    const one = await fixture(), two = await fixture();
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId: companyIds[0], id: two.d.id }, data: { externalProviderId: idOf(one.input) } });
    await expect(service.ingest(user(), one.input)).rejects.toThrow("ECF_EVIDENCE_REMOTE_ASSOCIATION_AMBIGUOUS");
  });
  it("E34 unknown reservation remains held during evidence intake/reconciliation", async () => {
    const { input, d } = await fixture();
    // Existing immutable E34 fixtures are tested by the E34 suite; create an isolated
    // synthetic pair here to verify that this service does not touch its ledger.
    const number = "E310000000001";
    const evidenceRef = `uat://synthetic-not-dgii/${randomUUID()}`, evidenceHash = "e".repeat(64);
    const o = await prisma.ecfElectronicDocument.create({ data: { companyId: d.companyId, documentType: "E31", status: "DGII_ACCEPTED",
      payloadFingerprint: "d".repeat(64), idempotencyKey: `test:${randomUUID()}`, externalProviderId: `synthetic-${randomUUID()}`, externalDocumentNumber: number,
      fiscalSnapshot: { total: "100.00", currency: "DOP", issueDate: "2026-10-14", issuerRnc: "101000001", encf: number,
        evidenceRef, evidenceHash } } });
    await prisma.ecfElectronicDocumentStatusLog.create({ data: { companyId: d.companyId, documentId: o.id,
      statusAfter: "DGII_ACCEPTED", reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII", metadata: { evidenceRef, evidenceHash } } });
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId: d.companyId, id: d.id }, data: { documentType: "E34", status: "LOCAL_VALIDATED", originalDocumentId: o.id,
      payloadSummary: { total: "40.00", currency: "DOP", reference: { originalType: "E31", originalENcf: number, originalIssueDate: "2026-10-14" } } } });
    const r = await prisma.ecfCreditReservation.create({ data: { companyId: d.companyId, originalDocumentId: o.id, creditDocumentId: d.id, amount: new Prisma.Decimal("40.00"), requestFingerprint: "f".repeat(64), state: "RESERVED" } });
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId: d.companyId, id: d.id }, data: { status: "UNKNOWN_RESULT" } });
    await prisma.ecfCreditReservation.update({ where: { companyId_creditDocumentId: { companyId: d.companyId, creditDocumentId: d.id } }, data: { state: "UNKNOWN_RESULT" } });
    await service.ingest(user(), input);
    expect(await service.reconciliation(user(), d.id)).toMatchObject({ reservationState: "UNKNOWN_RESULT", canReleaseReservation: false });
    expect(await prisma.ecfCreditReservation.findUnique({ where: { companyId_creditDocumentId: { companyId: d.companyId, creditDocumentId: d.id } } })).toMatchObject({ id: r.id, state: "UNKNOWN_RESULT" });
  });
});
