import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";
import { validE34Partial } from "../fiscal-core/ecf-fixtures";
import { EcfEmissionService, type EcfEmissionWire, type EcfEmissionWireRequest } from "./ecf-emission.service";
import { EcfE34CreditService } from "./ecf-e34-credit.service";

// Opt-in suite on an authorized local target (ephemeral test database), simulated
// transport, synthetic data only. No real Alanube call, no fiscal emission.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("E34 credit-note emission orchestrator (simulated transport)", () => {
  let prisma: PrismaService, credit: EcfE34CreditService, emission: EcfEmissionService;
  const actor = randomUUID();
  let sequence = 0;
  const next = (t: string) => `${t}${String(++sequence).padStart(10, "0")}`;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" || process.env.ECF_EMISSION_ENABLED === "true") {
      throw new Error("E34_EMISSION_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    credit = new EcfE34CreditService(prisma);
    emission = new EcfEmissionService(prisma);
  });
  afterAll(async () => { await prisma?.$disconnect(); });

  async function tenant() {
    const companyId = randomUUID();
    await prisma.company.create({ data: { id: companyId, name: "Synthetic E34 emission", slug: `ecf-e34e-${companyId}` } });
    return { companyId, user: { id: actor, role: "ADMIN", companyId } as TenantUser };
  }
  async function eligibleOriginal(companyId: string, total = "100.00", status: "DGII_ACCEPTED" | "PROVIDER_ACCEPTED" = "DGII_ACCEPTED") {
    const encf = next("E31");
    const evidenceRef = `uat://synthetic-not-dgii/${randomUUID()}`, evidenceHash = "a".repeat(64);
    const document = await prisma.ecfElectronicDocument.create({ data: { companyId, documentType: "E31", status,
      externalDocumentNumber: encf, externalProviderId: `synthetic-${randomUUID()}`,
      idempotencyKey: `synthetic-original-${randomUUID()}`, payloadFingerprint: "b".repeat(64),
      fiscalSnapshot: { total, currency: "DOP", issueDate: "2026-10-14", issuerRnc: "101000001", encf, evidenceRef, evidenceHash } } });
    if (status === "DGII_ACCEPTED") await prisma.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId: document.id,
      statusAfter: "DGII_ACCEPTED", reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII", metadata: { evidenceRef, evidenceHash } } });
    return document;
  }
  function noteDocument(originalEncf: string, amount: string, issueDate = "2026-10-14"): EcfFiscalDocument {
    return { ...validE34Partial, issueDate,
      reference: { ...validE34Partial.reference!, originalType: "E31", originalENcf: originalEncf, originalIssueDate: "2026-10-14" },
      lines: [{ ...validE34Partial.lines[0], unitPrice: amount, taxCategory: "EXEMPT", taxRate: "0" }],
      totals: { subtotal: amount, taxableBase: "0", exemptAmount: amount, discountAmount: "0", itbisAmount: "0", total: amount } };
  }
  const e34Metadata = (encf: string) => ({ encf, paymentType: 1, creditNoteIndicator: 0, modificationCode: 3 } as const);
  function prepareNote(user: TenantUser, originalId: string, originalEncf: string, amount: string, requestId = randomUUID()) {
    return credit.prepareNote(user, { originalId, document: noteDocument(originalEncf, amount),
      metadata: e34Metadata(next("E34")), clientRequestId: requestId });
  }
  function simulated(encf: string, options: { status?: number; body?: Record<string, unknown>; errorCode?: "TIMEOUT" | "NETWORK_ERROR" } = {}) {
    const calls: EcfEmissionWireRequest[] = [];
    const remoteId = "0" + randomUUID().replace(/-/g, "").slice(0, 25).toUpperCase();
    const port: EcfEmissionWire = { async execute(input) { calls.push(input);
      if (options.errorCode) return { ok: false, errorCode: options.errorCode, safeMessage: "synthetic" };
      return { ok: true, statusCode: options.status ?? 201, body: options.body ?? { id: remoteId, documentNumber: encf,
        companyIdentification: "101000001", status: "FINISHED", legalStatus: "ACCEPTED", sequenceConsumed: true } };
    } };
    return { port, calls, remoteId };
  }
  const reservationOf = (companyId: string, documentId: string) =>
    prisma.ecfCreditReservation.findUnique({ where: { companyId_creditDocumentId: { companyId, creditDocumentId: documentId } } });
  const encfOf = (document: { payloadSummary: unknown }) =>
    (document.payloadSummary as { emission: { encf: string } }).emission.encf;

  it("refuses to dispatch an E34 that has no credit reservation", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId);
    // Prepared WITHOUT going through prepareNote: no reservation exists yet.
    const note = await emission.prepare(user, { document: noteDocument(original.externalDocumentNumber!, "40.00"),
      metadata: e34Metadata(next("E34")), clientRequestId: randomUUID() });
    const { port, calls } = simulated("E340000000001");
    await expect(emission.dispatchOnce(user, note.id, port)).rejects.toThrow("E34_DISPATCH_REQUIRES_RESERVATION");
    expect(calls).toHaveLength(0);
    expect((await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: note.id } })).status).toBe("LOCAL_VALIDATED");
  });

  it("prepares, reserves and dispatches an accepted partial note into human review", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const { document, reservation } = await prepareNote(user, original.id, original.externalDocumentNumber!, "40.00");
    expect(reservation).toMatchObject({ state: "RESERVED", originalDocumentId: original.id });
    const encf = encfOf(document);
    const { port, calls, remoteId } = simulated(encf);
    const outcome = await emission.dispatchOnce(user, document.id, port);
    expect(outcome).toMatchObject({ correlated: true, canRetryPost: false });
    expect(calls).toHaveLength(1);
    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } });
    expect(stored).toMatchObject({ status: "HUMAN_REVIEW_REQUIRED", externalProviderId: remoteId, externalDocumentNumber: encf, fiscalSnapshot: null });
    // The reservation is HELD: uncertainty about the fiscal outcome never releases it.
    expect(await reservationOf(companyId, document.id)).toMatchObject({ state: "RESERVED" });
    expect(await prisma.ecfEvidenceReceipt.count({ where: { companyId, documentId: document.id } })).toBe(1);
    // Only the original is fiscally accepted; the note was never auto-promoted.
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId, id: { not: original.id },
      status: { in: ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] } } })).toBe(0);
  });

  it("supports a total note up to the original balance", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const { document, reservation } = await prepareNote(user, original.id, original.externalDocumentNumber!, "100.00");
    expect(reservation.amount.toString()).toBe("100");
    const port = simulated(encfOf(document)).port;
    expect((await emission.dispatchOnce(user, document.id, port)).correlated).toBe(true);
  });

  it("allows several partial notes while the remaining balance is sufficient", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const first = await prepareNote(user, original.id, original.externalDocumentNumber!, "30.00");
    const second = await prepareNote(user, original.id, original.externalDocumentNumber!, "70.00");
    expect(second.reservation.amount.toString()).toBe("70");
    expect(await prisma.ecfCreditReservation.count({ where: { companyId, originalDocumentId: original.id, state: "RESERVED" } })).toBe(2);
    expect(first.document.id).not.toBe(second.document.id);
  });

  it("refuses a credit that exceeds the available balance", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    await prepareNote(user, original.id, original.externalDocumentNumber!, "80.00");
    await expect(prepareNote(user, original.id, original.externalDocumentNumber!, "40.00"))
      .rejects.toThrow("E34_INSUFFICIENT_FISCAL_BALANCE");
  });

  it("refuses a note whose original is not fiscally accepted", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00", "PROVIDER_ACCEPTED");
    await expect(prepareNote(user, original.id, original.externalDocumentNumber!, "10.00"))
      .rejects.toThrow("E34_ORIGINAL_NOT_FISCALLY_ACCEPTED");
  });

  it("refuses an original that belongs to another company", async () => {
    const a = await tenant();
    const b = await tenant();
    const original = await eligibleOriginal(a.companyId, "100.00");
    await expect(prepareNote(b.user, original.id, original.externalDocumentNumber!, "10.00"))
      .rejects.toThrow("E34_ORIGINAL_NOT_FOUND");
  });

  it("is idempotent per operation and refuses a divergent retry", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const requestId = randomUUID();
    const encf = next("E34");
    const first = await credit.prepareNote(user, { originalId: original.id, document: noteDocument(original.externalDocumentNumber!, "25.00"),
      metadata: { encf, paymentType: 1, creditNoteIndicator: 0, modificationCode: 3 }, clientRequestId: requestId });
    const again = await credit.prepareNote(user, { originalId: original.id, document: noteDocument(original.externalDocumentNumber!, "25.00"),
      metadata: { encf, paymentType: 1, creditNoteIndicator: 0, modificationCode: 3 }, clientRequestId: requestId });
    expect(again.document.id).toBe(first.document.id);
    expect(await prisma.ecfCreditReservation.count({ where: { companyId, creditDocumentId: first.document.id } })).toBe(1);
    await expect(credit.prepareNote(user, { originalId: original.id, document: noteDocument(original.externalDocumentNumber!, "30.00"),
      metadata: { encf, paymentType: 1, creditNoteIndicator: 0, modificationCode: 3 }, clientRequestId: requestId })).rejects.toThrow();
  });

  it("keeps a rejection for human review without releasing the reservation", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const { document } = await prepareNote(user, original.id, original.externalDocumentNumber!, "40.00");
    const encf = encfOf(document);
    const { port } = simulated(encf, { body: { id: "0" + randomUUID().replace(/-/g, "").slice(0, 25).toUpperCase(),
      documentNumber: encf, companyIdentification: "101000001", status: "FINISHED", legalStatus: "REJECTED", sequenceConsumed: true } });
    await emission.dispatchOnce(user, document.id, port);
    expect(await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } }))
      .toMatchObject({ status: "HUMAN_REVIEW_REQUIRED", safeErrorCode: "ECF_OBSERVED_REJECTED" });
    expect(await reservationOf(companyId, document.id)).toMatchObject({ state: "RESERVED" });
  });

  it("keeps a timeout unknown without releasing the reservation and without retry", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const { document } = await prepareNote(user, original.id, original.externalDocumentNumber!, "40.00");
    const { port, calls } = simulated("E340000000010", { errorCode: "TIMEOUT" });
    await emission.dispatchOnce(user, document.id, port);
    expect(await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } }))
      .toMatchObject({ status: "UNKNOWN_RESULT", externalProviderId: null });
    expect(await reservationOf(companyId, document.id)).toMatchObject({ state: "RESERVED" });
    await expect(emission.dispatchOnce(user, document.id, port)).rejects.toThrow();
    expect(calls).toHaveLength(1);
  });

  it("does not bind a contradictory response", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const { document } = await prepareNote(user, original.id, original.externalDocumentNumber!, "40.00");
    const { port } = simulated("E340000000011", { body: { id: "0" + randomUUID().replace(/-/g, "").slice(0, 25).toUpperCase(),
      documentNumber: "E349999999999", companyIdentification: "101000001", status: "FINISHED", legalStatus: "ACCEPTED", sequenceConsumed: true } });
    const outcome = await emission.dispatchOnce(user, document.id, port);
    expect(outcome.correlated).toBe(false);
    expect(await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } }))
      .toMatchObject({ status: "UNKNOWN_RESULT", externalProviderId: null });
  });

  it("allows only one effective dispatch under concurrency", async () => {
    const { companyId, user } = await tenant();
    const original = await eligibleOriginal(companyId, "100.00");
    const { document } = await prepareNote(user, original.id, original.externalDocumentNumber!, "40.00");
    const encf = encfOf(document);
    const a = simulated(encf), b = simulated(encf);
    const results = await Promise.allSettled([
      emission.dispatchOnce(user, document.id, a.port),
      emission.dispatchOnce(user, document.id, b.port),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(a.calls.length + b.calls.length).toBe(1);
    expect((await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } })).status).toBe("HUMAN_REVIEW_REQUIRED");
  });

  it("refuses cross-tenant dispatch of a reserved note", async () => {
    const a = await tenant();
    const b = await tenant();
    const original = await eligibleOriginal(a.companyId, "100.00");
    const { document } = await prepareNote(a.user, original.id, original.externalDocumentNumber!, "40.00");
    const { port, calls } = simulated("E340000000014");
    await expect(emission.dispatchOnce(b.user, document.id, port)).rejects.toThrow();
    expect(calls).toHaveLength(0);
  });
});
