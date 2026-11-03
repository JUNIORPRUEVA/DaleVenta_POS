import { randomUUID } from "node:crypto";
import { isEcfLocalTarget, matchEcfLocalTarget } from "../ecf-local-target";
import { Prisma, type EcfElectronicDocument, type EcfElectronicDocumentStatus } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfDocumentIdempotencyService } from "./ecf-document-idempotency.service";
import { EcfE34CreditService } from "./ecf-e34-credit.service";
import { validE34Partial } from "../fiscal-core/ecf-fixtures";

const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;
uat("E34 real PostgreSQL synthetic integrity (not DGII acceptance)", () => {
  let prisma: PrismaService, service: EcfE34CreditService, prepare: EcfDocumentIdempotencyService;
  const companyIds = [randomUUID(), randomUUID()];
  const actor = randomUUID();
  const user = (companyId = companyIds[0]): TenantUser => ({ id: actor, role: "ADMIN", companyId });
  let sequence = 0;
  const encf = (type: string) => `${type}${String(++sequence).padStart(10, "0")}`;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" || process.env.ECF_EMISSION_ENABLED !== "false") throw Error("E34_UAT_TARGET_REFUSED");
    prisma = new PrismaService();
    await prisma.$connect();
    expect((await prisma.$queryRaw<Array<{ name: string }>>`SELECT current_database() AS name`)[0].name).toBe(matchEcfLocalTarget()?.name);
    await prisma.company.createMany({ data: companyIds.map((id) => ({ id, name: "Synthetic E34 immutable audit fixtures", slug: `ecf-81-90-${id}` })) });
    service = new EcfE34CreditService(prisma); prepare = new EcfDocumentIdempotencyService(prisma);
  });
  // Retain synthetic fixture records: ledger/evidence are intentionally immutable.
  afterAll(async () => { await prisma?.$disconnect(); });

  async function original(options: { companyId?: string; status?: EcfElectronicDocumentStatus; evidence?: boolean; snapshot?: boolean; type?: "E31" | "E32" | "E34" } = {}) {
    const companyId = options.companyId ?? companyIds[0], type = options.type ?? "E31", number = encf(type);
    const evidenceRef = `uat://synthetic-not-dgii/${randomUUID()}`, evidenceHash = "a".repeat(64);
    const document = await prisma.ecfElectronicDocument.create({ data: {
      companyId, documentType: type, status: options.status ?? "DGII_ACCEPTED",
      externalDocumentNumber: number, externalProviderId: `synthetic-${randomUUID()}`,
      idempotencyKey: `synthetic-original-${randomUUID()}`, payloadFingerprint: "b".repeat(64),
      fiscalSnapshot: options.snapshot === false ? Prisma.DbNull : {
        total: "100.00", currency: "DOP", issueDate: "2026-10-14", issuerRnc: "101000001", encf: number, evidenceRef, evidenceHash,
      },
    } });
    if (options.evidence !== false) await prisma.ecfElectronicDocumentStatusLog.create({ data: {
      companyId, documentId: document.id, statusAfter: "DGII_ACCEPTED", reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII",
      metadata: { evidenceRef, evidenceHash },
    } });
    return document;
  }
  async function note(o: EcfElectronicDocument, amount = "40.00", requestId = randomUUID(), companyId = o.companyId, overrides: Record<string, unknown> = {}) {
    return prepare.prepareLocalDocument({ companyId, clientRequestId: requestId, document: {
      ...validE34Partial, reference: { ...validE34Partial.reference!, originalType: o.documentType as "E31",
        originalENcf: o.externalDocumentNumber!, originalIssueDate: "2026-10-14" },
      lines: [{ ...validE34Partial.lines[0], unitPrice: amount, taxCategory: "EXEMPT", taxRate: "0" }],
      totals: { subtotal: amount, taxableBase: "0", exemptAmount: amount, discountAmount: "0", itbisAmount: "0", total: amount },
      ...overrides,
    } });
  }
  async function outcome(n: EcfElectronicDocument, status: "DGII_ACCEPTED" | "DGII_REJECTED", withLog = true) {
    const evidenceRef = `uat://synthetic-not-dgii/${randomUUID()}`, evidenceHash = "c".repeat(64);
    const summary = n.payloadSummary as Record<string, unknown>;
    await prisma.ecfElectronicDocument.updateMany({ where: { id: n.id, companyId: n.companyId }, data: {
      status, externalDocumentNumber: encf("E34"), externalProviderId: `synthetic-${randomUUID()}`,
    } });
    const saved = await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { id: n.id, companyId: n.companyId } });
    await prisma.ecfElectronicDocument.updateMany({ where: { id: n.id, companyId: n.companyId }, data: {
      fiscalSnapshot: { total: summary.total, currency: "DOP", issueDate: "2026-10-14", issuerRnc: "101000001",
        encf: saved.externalDocumentNumber!, evidenceRef, evidenceHash } as Prisma.InputJsonValue,
    } });
    if (withLog) await prisma.ecfElectronicDocumentStatusLog.create({ data: { companyId: n.companyId, documentId: n.id,
      statusAfter: status, reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII", metadata: { evidenceRef, evidenceHash } } });
  }

  it("1 original valid: reserves locally without applying a fiscal credit", async () => {
    const o = await original(), n = await note(o);
    expect((await service.reserve(user(), o.id, n.id)).state).toBe("RESERVED");
    expect(await service.balance(user(), o.id)).toMatchObject({ originalAmount: "100.00", creditedAmount: "0.00", reservedAmount: "40.00", availableAmount: "60.00" });
  });
  it("2 nonexistent original fails closed", async () => {
    const o = await original(), n = await note(o);
    await expect(service.reserve(user(), randomUUID(), n.id)).rejects.toThrow("E34_ORIGINAL_NOT_FOUND");
  });
  it("3 original from another company is not exposed or credited", async () => {
    const o = await original({ companyId: companyIds[1] }), n = await note(o, "40.00", randomUUID(), companyIds[0]);
    await expect(service.reserve(user(), o.id, n.id)).rejects.toThrow("E34_ORIGINAL_NOT_FOUND");
  });
  it("4 missing fiscal snapshot or matching evidence log is blocked", async () => {
    for (const options of [{ snapshot: false }, { evidence: false }]) {
      const o = await original(options), n = await note(o);
      await expect(service.reserve(user(), o.id, n.id)).rejects.toThrow(/E34_(FISCAL|OUTCOME)_EVIDENCE_REQUIRED/);
    }
  });
  it("5 commercial/provider/invalidated originals are not accepted fiscal originals", async () => {
    for (const status of ["LOCAL_VALIDATED", "PROVIDER_ACCEPTED", "CANCELLED", "DGII_REJECTED"] as const) {
      const o = await original({ status }), n = await note(o);
      await expect(service.reserve(user(), o.id, n.id)).rejects.toThrow("E34_ORIGINAL_NOT_FISCALLY_ACCEPTED");
    }
  });
  it("6 partial applied credit requires matching synthetic outcome evidence", async () => {
    const o = await original(), n = await note(o);
    await service.reserve(user(), o.id, n.id);
    await expect(service.transition(user(), n.id, "APPLIED")).rejects.toThrow("E34_OUTCOME_EVIDENCE_REQUIRED");
    await outcome(n, "DGII_ACCEPTED");
    await service.transition(user(), n.id, "APPLIED");
    expect(await service.balance(user(), o.id)).toMatchObject({ creditedAmount: "40.00", reservedAmount: "0.00", availableAmount: "60.00" });
  });
  it("7 full credit holds the entire original amount", async () => {
    const o = await original(), n = await note(o, "100.00");
    await service.reserve(user(), o.id, n.id);
    expect((await service.balance(user(), o.id)).availableAmount).toBe("0.00");
  });
  it("8 accumulated partial credits cannot exceed the original", async () => {
    const o = await original();
    for (const amount of ["40.00", "60.00"]) {
      const n = await note(o, amount); await service.reserve(user(), o.id, n.id);
      await outcome(n, "DGII_ACCEPTED"); await service.transition(user(), n.id, "APPLIED");
    }
    expect((await service.balance(user(), o.id)).creditedAmount).toBe("100.00");
    await expect(service.reserve(user(), o.id, (await note(o, "0.01")).id)).rejects.toThrow("E34_INSUFFICIENT_FISCAL_BALANCE");
  });
  it("9 an excessive requested credit is rejected atomically", async () => {
    const o = await original(), n = await note(o, "100.01");
    await expect(service.reserve(user(), o.id, n.id)).rejects.toThrow("E34_INSUFFICIENT_FISCAL_BALANCE");
    expect((await service.balance(user(), o.id)).availableAmount).toBe("100.00");
  });
  it("10 concurrent incompatible reservations have exactly one winner", async () => {
    const o = await original(), a = await note(o, "70.00"), b = await note(o, "70.00");
    const results = await Promise.allSettled([service.reserve(user(), o.id, a.id), service.reserve(user(), o.id, b.id)]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect((await service.balance(user(), o.id)).availableAmount).toBe("30.00");
  });
  it("11 identical concurrent replays create one reservation and one event", async () => {
    const o = await original(), n = await note(o);
    const rows = await Promise.all(Array.from({ length: 8 }, () => service.reserve(user(), o.id, n.id)));
    expect(new Set(rows.map((r) => r.id)).size).toBe(1);
    expect(await prisma.ecfCreditReservationEvent.count({ where: { companyId: o.companyId, reservationId: rows[0].id } })).toBe(1);
  });
  it("12 divergent retry and mutation of a reserved payload are blocked", async () => {
    const o = await original(), requestId = randomUUID(), n = await note(o, "40.00", requestId);
    await service.reserve(user(), o.id, n.id);
    await expect(note(o, "41.00", requestId)).rejects.toThrow("IDEMPOTENCY_PAYLOAD_MISMATCH");
    await expect(prisma.ecfElectronicDocument.updateMany({ where: { companyId: n.companyId, id: n.id }, data: { payloadFingerprint: "d".repeat(64) } })).rejects.toThrow("E34_RESERVED_PAYLOAD_IMMUTABLE");
  });
  it("13 unknown results retain money and cannot be cancelled automatically", async () => {
    const o = await original(), n = await note(o, "70.00"); await service.reserve(user(), o.id, n.id);
    await service.transition(user(), n.id, "UNKNOWN_RESULT");
    await expect(service.transition(user(), n.id, "CANCELLED")).rejects.toThrow();
    expect(await service.balance(user(), o.id)).toMatchObject({ unknownAmount: "70.00", availableAmount: "30.00", creditedAmount: "0.00" });
  });
  it("14 rejected outcome releases money only with matching evidence", async () => {
    const o = await original(), n = await note(o); await service.reserve(user(), o.id, n.id);
    await service.transition(user(), n.id, "UNKNOWN_RESULT");
    await outcome(n, "DGII_REJECTED", false);
    await expect(service.transition(user(), n.id, "REJECTED")).rejects.toThrow("E34_OUTCOME_EVIDENCE_REQUIRED");
    const saved = await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: n.companyId, id: n.id } });
    const snapshot = saved.fiscalSnapshot as Record<string, string>;
    await prisma.ecfElectronicDocumentStatusLog.create({ data: { companyId: n.companyId, documentId: n.id, statusAfter: "DGII_REJECTED",
      metadata: { evidenceRef: snapshot.evidenceRef, evidenceHash: snapshot.evidenceHash } } });
    await service.transition(user(), n.id, "REJECTED");
    expect(await service.balance(user(), o.id)).toMatchObject({ rejectedAmount: "40.00", unknownAmount: "0.00", availableAmount: "100.00" });
  });
  it("15 recreating backend clients preserves reservations and unknown outcomes", async () => {
    const o = await original(), n = await note(o); await service.reserve(user(), o.id, n.id);
    await service.transition(user(), n.id, "UNKNOWN_RESULT");
    const restarted = new PrismaService();
    try { expect((await new EcfE34CreditService(restarted).reserve(user(), o.id, n.id)).state).toBe("UNKNOWN_RESULT"); }
    finally { await restarted.$disconnect(); }
  });
  it("16 history is atomic, idempotent and append only at PostgreSQL level", async () => {
    const o = await original(), n = await note(o), r = await service.reserve(user(), o.id, n.id);
    await service.transition(user(), n.id, "UNKNOWN_RESULT"); await service.transition(user(), n.id, "UNKNOWN_RESULT");
    const events = await prisma.ecfCreditReservationEvent.findMany({ where: { companyId: o.companyId, reservationId: r.id }, orderBy: { createdAt: "asc" } });
    expect(events.map((e) => e.stateAfter)).toEqual(["RESERVED", "UNKNOWN_RESULT"]);
    await expect(prisma.ecfCreditReservationEvent.deleteMany({ where: { companyId: o.companyId, reservationId: r.id } })).rejects.toThrow("E34_CREDIT_EVENTS_APPEND_ONLY");
  });
  it("17 tenant-aware FKs reject a reference to another company even through direct SQL", async () => {
    const foreign = await original({ companyId: companyIds[1] }); const local = await original(), n = await note(local);
    await expect(prisma.ecfElectronicDocument.updateMany({ where: { companyId: n.companyId, id: n.id }, data: { originalDocumentId: foreign.id } })).rejects.toMatchObject({ code: "P2003" });
    await expect(service.balance(user(), foreign.id)).rejects.toThrow("E34_ORIGINAL_NOT_FOUND");
  });
  it("18 fractional cents are rejected rather than rounded into a reservation", async () => {
    const o = await original(), n = await note(o, "1.005");
    await expect(service.reserve(user(), o.id, n.id)).rejects.toThrow("E34_AMOUNT_PRECISION_INVALID");
    expect((await service.balance(user(), o.id)).availableAmount).toBe("100.00");
  });
  it("19 inconsistent reference/currency/date is rejected", async () => {
    const o = await original();
    for (const overrides of [{ currency: "USD" }, { reference: { originalENcf: "E310000000000", originalIssueDate: "2026-10-14" } }, { issueDate: "2026-10-13" }]) {
      const n = await note(o, "40.00", randomUUID(), o.companyId, overrides);
      await expect(service.reserve(user(), o.id, n.id)).rejects.toThrow();
    }
  });
  it("20 missing required reference fields and draft notes cannot reserve or apply", async () => {
    const o = await original(), n = await note(o, "40.00", randomUUID(), o.companyId, { reference: undefined });
    await expect(service.reserve(user(), o.id, n.id)).rejects.toThrow("E34_REFERENCE_MISMATCH");
    const draft = await note(o); await prisma.ecfElectronicDocument.updateMany({ where: { companyId: draft.companyId, id: draft.id }, data: { status: "LOCAL_DRAFT" } });
    await expect(service.reserve(user(), o.id, draft.id)).rejects.toThrow("E34_NOTE_NOT_LOCALLY_READY");
  });
  it("21 distinct equal-amount notes coexist and local cancellation releases only unsent holds", async () => {
    const o = await original(), a = await note(o, "30.00"), b = await note(o, "30.00");
    const first = await service.reserve(user(), o.id, a.id), second = await service.reserve(user(), o.id, b.id);
    expect(first.id).not.toBe(second.id);
    await service.transition(user(), a.id, "CANCELLED");
    expect(await service.balance(user(), o.id)).toMatchObject({ availableAmount: "70.00", reservedAmount: "30.00", cancelledAmount: "30.00" });
  });
  it("22 database trigger prevents direct over-reservation and evidence-free application", async () => {
    const o = await original(), a = await note(o, "70.00"), b = await note(o, "40.00");
    const reservation = await service.reserve(user(), o.id, a.id);
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId: b.companyId, id: b.id }, data: { originalDocumentId: o.id } });
    await expect(prisma.ecfCreditReservation.create({ data: { companyId: o.companyId, originalDocumentId: o.id, creditDocumentId: b.id, amount: "40.00", requestFingerprint: "f".repeat(64) } })).rejects.toThrow("E34_FISCAL_BALANCE_EXCEEDED");
    await expect(prisma.ecfCreditReservation.update({ where: { companyId_creditDocumentId: { companyId: o.companyId, creditDocumentId: a.id } }, data: { state: "APPLIED" } })).rejects.toThrow("E34_OUTCOME_EVIDENCE_REQUIRED");
    await expect(prisma.ecfCreditReservation.delete({ where: { companyId_creditDocumentId: { companyId: o.companyId, creditDocumentId: a.id } } })).rejects.toThrow("E34_RESERVATION_HISTORY_IMMUTABLE");
    expect(await prisma.ecfCreditReservationEvent.count({ where: { companyId: o.companyId, reservationId: reservation.id } })).toBe(1);
  });
  it("23 accepted-but-untracked legacy credits block further reservations", async () => {
    const o = await original(), legacy = await note(o);
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId: o.companyId, id: legacy.id }, data: { originalDocumentId: o.id, status: "DGII_ACCEPTED" } });
    await expect(service.reserve(user(), o.id, (await note(o)).id)).rejects.toThrow("E34_UNTRACKED_CREDITS_REQUIRE_REVIEW");
  });
  it("24 fiscal snapshots and per-tenant fiscal reference identity are immutable/unique", async () => {
    const o = await original();
    await expect(prisma.ecfElectronicDocument.updateMany({ where: { companyId: o.companyId, id: o.id }, data: { fiscalSnapshot: { total: "1000.00" } } })).rejects.toThrow("E34_FISCAL_SNAPSHOT_IMMUTABLE");
    await expect(prisma.ecfElectronicDocument.create({ data: { companyId: o.companyId, documentType: "E31", externalDocumentNumber: o.externalDocumentNumber,
      idempotencyKey: randomUUID(), payloadFingerprint: "f".repeat(64) } })).rejects.toMatchObject({ code: "P2002" });
  });
  it("25 E32 originals are supported; E34 originals fail the conservative reference policy", async () => {
    const valid = await original({ type: "E32" });
    expect((await service.reserve(user(), valid.id, (await note(valid)).id)).state).toBe("RESERVED");
    const invalid = await original({ type: "E34" });
    await expect(service.reserve(user(), invalid.id, (await note(invalid)).id)).rejects.toThrow("E34_REFERENCE_TYPE_UNSUPPORTED");
  });
  it("26 a submitted reservation cannot be cancelled without a verified final outcome", async () => {
    const o = await original(), n = await note(o); await service.reserve(user(), o.id, n.id);
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId: n.companyId, id: n.id }, data: { status: "SEND_IN_PROGRESS" } });
    await expect(service.transition(user(), n.id, "CANCELLED")).rejects.toThrow("E34_UNKNOWN_OR_SUBMITTED_CANNOT_RELEASE");
    expect((await service.balance(user(), o.id)).availableAmount).toBe("60.00");
  });
  it("27 PostgreSQL itself serializes concurrent direct inserts below the same fiscal budget", async () => {
    const o = await original(), a = await note(o, "60.00"), b = await note(o, "60.00");
    for (const n of [a, b]) await prisma.ecfElectronicDocument.updateMany({ where: { companyId: n.companyId, id: n.id }, data: { originalDocumentId: o.id } });
    const results = await Promise.allSettled([a, b].map((n) => prisma.ecfCreditReservation.create({ data: {
      companyId: o.companyId, originalDocumentId: o.id, creditDocumentId: n.id, amount: "60.00", requestFingerprint: "f".repeat(64),
    } })));
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect((await service.balance(user(), o.id)).availableAmount).toBe("40.00");
  });
  it("28 unauthenticated calls cannot supply a tenant identity through document IDs", async () => {
    await expect(service.reserve({ id: "", role: "ADMIN", companyId: companyIds[0] }, randomUUID(), randomUUID())).rejects.toThrow("Usuario no autenticado");
    await expect(service.balance({ id: actor, role: "ADMIN" }, randomUUID())).rejects.toThrow("Usuario sin empresa asignada");
  });
});
