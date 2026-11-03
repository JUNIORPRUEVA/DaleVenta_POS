import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";
import { EcfSequenceService } from "./ecf-sequence.service";
import { EcfEmissionService } from "./ecf-emission.service";

// Opt-in suite on an authorized local target (ephemeral test database).
// Synthetic data only: no real Alanube call, no fiscal emission.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("e-CF numbering ranges (E31/E34) on PostgreSQL", () => {
  let prisma: PrismaService, sequences: EcfSequenceService, emission: EcfEmissionService;
  const actor = randomUUID();

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" || process.env.ECF_EMISSION_ENABLED === "true") {
      throw new Error("ECF_NUMBERING_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    sequences = new EcfSequenceService(prisma);
    emission = new EcfEmissionService(prisma);
  });
  afterAll(async () => { await prisma?.$disconnect(); });

  async function tenant() {
    const companyId = randomUUID();
    await prisma.company.create({ data: { id: companyId, name: "Synthetic numbering", slug: `ecf-seq-${companyId}` } });
    return { companyId, user: { id: actor, role: "ADMIN", companyId } as TenantUser };
  }
  const range = (user: TenantUser, documentType: string, startNumber: number, endNumber: number, validUntil?: Date) =>
    sequences.register(user, { documentType, startNumber, endNumber, validUntil });
  const allocated = (user: TenantUser) => sequences.allocate(user, "E31");

  it("allocates sequential e-NCFs in the official 13-character format", async () => {
    const { user } = await tenant();
    await range(user, "E31", 1, 5);
    expect((await allocated(user)).encf).toBe("E310000000001");
    expect((await allocated(user)).encf).toBe("E310000000002");
  });

  it("never hands out the same number twice under concurrency", async () => {
    const { companyId, user } = await tenant();
    const sequence = await range(user, "E31", 1, 50);
    const results = await Promise.all(Array.from({ length: 20 }, () => allocated(user)));
    const encfs = results.map((r) => r.encf);
    expect(new Set(encfs).size).toBe(20);
    expect([...encfs].sort()).toEqual(Array.from({ length: 20 }, (_, i) => `E3100000000${String(i + 1).padStart(2, "0")}`).sort());
    expect((await prisma.ecfSequence.findUniqueOrThrow({ where: { id: sequence.id } })).nextNumber).toBe(21);
    expect(await prisma.ecfSequenceAuditLog.count({ where: { companyId, action: "ALLOCATED" } })).toBe(20);
  });

  it("refuses to allocate beyond the range", async () => {
    const { user } = await tenant();
    await range(user, "E31", 1, 2);
    await allocated(user);
    await allocated(user);
    await expect(allocated(user)).rejects.toThrow("ECF_SEQUENCE_EXHAUSTED");
  });

  it("refuses an expired range without consuming anything", async () => {
    const { companyId, user } = await tenant();
    await range(user, "E31", 1, 10, new Date(Date.now() - 86_400_000));
    await expect(allocated(user)).rejects.toThrow("ECF_SEQUENCE_EXHAUSTED");
    expect(await prisma.ecfSequenceAuditLog.count({ where: { companyId } })).toBe(0);
  });

  it("keeps every company on its own range", async () => {
    const a = await tenant();
    const b = await tenant();
    await range(a.user, "E31", 1, 10);
    await allocated(a.user);
    await expect(allocated(b.user)).rejects.toThrow("ECF_SEQUENCE_EXHAUSTED");
    await range(b.user, "E31", 1, 10);
    expect((await allocated(b.user)).encf).toBe("E310000000001");
    expect((await allocated(a.user)).encf).toBe("E310000000002");
  });

  it("does not free a number when the document is cancelled", async () => {
    const { companyId, user } = await tenant();
    const sequence = await range(user, "E31", 1, 10);
    const first = await allocated(user);
    const document = await prisma.ecfElectronicDocument.create({ data: { companyId, documentType: "E31",
      status: "LOCAL_VALIDATED", externalDocumentNumber: first.encf, payloadFingerprint: "b".repeat(64),
      idempotencyKey: `synthetic-${randomUUID()}` } });
    await prisma.ecfElectronicDocument.updateMany({ where: { companyId, id: document.id }, data: { status: "CANCELLED" } });
    const second = await allocated(user);
    expect(second.encf).not.toBe(first.encf);
    expect((await prisma.ecfSequence.findUniqueOrThrow({ where: { id: sequence.id } })).nextNumber).toBe(3);
  });

  it("reuses the number already consumed for the same operation", async () => {
    const { companyId, user } = await tenant();
    const sequence = await range(user, "E31", 1, 10);
    const operationKey = randomUUID();
    const first = await sequences.allocate(user, "E31", { operationKey });
    const again = await sequences.allocate(user, "E31", { operationKey });
    expect(again.encf).toBe(first.encf);
    expect((await prisma.ecfSequence.findUniqueOrThrow({ where: { id: sequence.id } })).nextNumber).toBe(2);
    expect(await prisma.ecfSequenceAuditLog.count({ where: { companyId, action: "ALLOCATED" } })).toBe(1);
  });

  it("refuses to allocate for E32, which keeps its own single-use slot", async () => {
    const { user } = await tenant();
    await expect(sequences.allocate(user, "E32")).rejects.toThrow("ECF_SEQUENCE_TYPE_UNSUPPORTED");
  });

  it("refuses a renewal below the consumed frontier", async () => {
    const { user } = await tenant();
    await range(user, "E31", 1, 10);
    await allocated(user);
    await allocated(user);
    await allocated(user);
    await expect(sequences.renew(user, { documentType: "E31", startNumber: 2, endNumber: 20 }))
      .rejects.toThrow("ECF_SEQUENCE_REUSE_BLOCKED");
    const renewed = await sequences.renew(user, { documentType: "E31", startNumber: 4, endNumber: 20 });
    expect(renewed.startNumber).toBe(4);
    expect((await allocated(user)).encf).toBe("E310000000004");
  });

  it("refuses a second active range for the same document type", async () => {
    const { user } = await tenant();
    await range(user, "E31", 1, 10);
    await expect(range(user, "E31", 11, 20)).rejects.toThrow("ECF_SEQUENCE_ALREADY_EXISTS");
    await expect(range(user, "E31", 10, 1)).rejects.toThrow("ECF_SEQUENCE_RANGE_INVALID");
  });

  it("makes consumption irreversible at the database level", async () => {
    const { user } = await tenant();
    const sequence = await range(user, "E31", 1, 10);
    await allocated(user);
    await allocated(user);
    // A defective caller cannot roll the front backwards: the guard trigger rejects it.
    await expect(prisma.$executeRawUnsafe(
      `UPDATE ecf_sequences SET next_number = 0 WHERE id = '${sequence.id}'`)).rejects.toThrow();
    await expect(prisma.$executeRawUnsafe(
      `UPDATE ecf_sequences SET prefix = 'E99' WHERE id = '${sequence.id}'`)).rejects.toThrow();
    expect((await prisma.ecfSequence.findUniqueOrThrow({ where: { id: sequence.id } })).nextNumber).toBe(3);
  });

  it("keeps the allocation ledger append-only", async () => {
    const { companyId, user } = await tenant();
    await range(user, "E31", 1, 10);
    const first = await allocated(user);
    await expect(prisma.$executeRawUnsafe(
      `UPDATE ecf_sequence_audit_logs SET encf = 'E319999999999' WHERE company_id = '${companyId}'`)).rejects.toThrow();
    const ledger = await prisma.ecfSequenceAuditLog.findFirstOrThrow({ where: { companyId, action: "ALLOCATED" } });
    expect(ledger.encf).toBe(first.encf);
  });

  it("allocates the number from the range when the emitter does not provide one", async () => {
    const { companyId, user } = await tenant();
    const sequence = await range(user, "E31", 1, 10);
    const metadata = { sequenceDueDate: "2026-12-31", incomeType: 1, paymentType: 1 } as unknown as EcfIssuanceMetadata;
    const document = await emission.prepare(user, { document: validE31WithItbis, metadata, clientRequestId: randomUUID() });
    expect((document.payloadSummary as { emission: { encf: string } }).emission.encf).toBe("E310000000001");
    expect((await prisma.ecfSequence.findUniqueOrThrow({ where: { id: sequence.id } })).nextNumber).toBe(2);
    expect(await prisma.ecfSequenceAuditLog.count({ where: { companyId, action: "ALLOCATED", encf: "E310000000001" } })).toBe(1);
  });
});
