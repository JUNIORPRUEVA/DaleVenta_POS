import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfDocumentQueryService } from "./ecf-document-query.service";

// Opt-in suite on the ephemeral test database. Read-only projections of
// synthetic data: no provider call, no emission, no fiscal acceptance.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("e-CF document query API (tenant isolation) on PostgreSQL", () => {
  let prisma: PrismaService, query: EcfDocumentQueryService;
  const actor = randomUUID();

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_QUERY_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    query = new EcfDocumentQueryService(prisma);
  });
  afterAll(async () => { await prisma?.$disconnect(); });

  async function tenant(name = "Query synthetic") {
    const companyId = randomUUID();
    await prisma.company.create({ data: { id: companyId, name, slug: `ecf-q-${companyId}` } });
    return { companyId, user: { id: actor, role: "ADMIN", companyId } as TenantUser };
  }
  async function acceptedOriginal(companyId: string, total = "100.00") {
    const encf = `E31000000${String(Math.floor(1000 + Math.random() * 9000))}`;
    const evidenceRef = `uat://synthetic-not-dgii/${randomUUID()}`, evidenceHash = "a".repeat(64);
    return prisma.ecfElectronicDocument.create({ data: { companyId, documentType: "E31", status: "DGII_ACCEPTED",
      externalDocumentNumber: encf, externalProviderId: `synthetic-${randomUUID()}`,
      idempotencyKey: `synthetic-original-${randomUUID()}`, payloadFingerprint: "b".repeat(64),
      fiscalSnapshot: { total, currency: "DOP", issueDate: "2026-10-14", issuerRnc: "101000001", encf, evidenceRef, evidenceHash } } })
      .then((doc) => prisma.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId: doc.id,
        statusAfter: "DGII_ACCEPTED", reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII", metadata: { evidenceRef, evidenceHash } } })
        .then(() => prisma.ecfElectronicDocument.findUniqueOrThrow({ where: { companyId_id: { companyId, id: doc.id } } })));
  }
  async function localDoc(companyId: string, documentType: "E31" | "E34" = "E31", status = "HUMAN_REVIEW_REQUIRED") {
    const encf = `${documentType}${String(Math.floor(Math.random() * 1e10)).padStart(10, "0")}`;
    return prisma.ecfElectronicDocument.create({ data: { companyId, documentType, status,
      externalDocumentNumber: encf, idempotencyKey: `synthetic-doc-${randomUUID()}`,
      payloadFingerprint: "c".repeat(64) } });
  }

  it("reports e-CF disabled by default with no emission path exposed", async () => {
    const { user } = await tenant();
    const caps = await query.capabilities(user);
    expect(caps.enabled).toBe(false);
    expect(caps.productionEnabled).toBe(false);
    expect(caps.emissionPathAvailable).toBe(false);
    expect(caps.documentTypes.map((t) => t.documentType)).toEqual(["E31", "E32", "E34"]);
    expect(caps.documentTypes.find((t) => t.documentType === "E32")?.allocatable).toBe(false);
  });

  it("never lists another company's documents", async () => {
    const a = await tenant("A");
    const b = await tenant("B");
    await localDoc(a.companyId);
    const list = await query.list(b.user, {});
    expect(list.total).toBe(0);
    expect(list.items).toHaveLength(0);
  });

  it("returns 404 for another company's document id (no IDOR signal)", async () => {
    const a = await tenant("A");
    const b = await tenant("B");
    const doc = await localDoc(a.companyId);
    await expect(query.detail(b.user, doc.id)).rejects.toThrow("Comprobante e-CF no encontrado");
  });

  it("shows e-NCF, history and attempts on the owner's document", async () => {
    const { companyId, user } = await tenant();
    const doc = await localDoc(companyId, "E31", "HUMAN_REVIEW_REQUIRED");
    await prisma.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId: doc.id,
      statusBefore: "SEND_IN_PROGRESS", statusAfter: "HUMAN_REVIEW_REQUIRED", reasonCode: "ECF_OBSERVED_ACCEPTED" } });
    const detail = await query.detail(user, doc.id);
    expect(detail.encf).toBe(doc.externalDocumentNumber);
    expect(detail.statusGroup).toBe("REQUIRES_REVIEW");
    expect(detail.statusLogs.some((log) => log.reasonCode === "ECF_OBSERVED_ACCEPTED")).toBe(true);
  });

  it("buckets summary counts by functional group", async () => {
    const { companyId, user } = await tenant();
    await localDoc(companyId, "E31", "LOCAL_VALIDATED");
    await localDoc(companyId, "E31", "HUMAN_REVIEW_REQUIRED");
    const summary = await query.summary(user);
    expect(summary.byGroup.PENDING).toBe(1);
    expect(summary.byGroup.REQUIRES_REVIEW).toBe(1);
    expect(summary.total).toBe(2);
  });

  it("offers only fiscally accepted originals with remaining balance for E34", async () => {
    const { companyId, user } = await tenant();
    const original = await acceptedOriginal(companyId, "100.00");
    const eligible = await query.eligibleOriginals(user);
    expect(eligible.items.some((item) => item.id === original.id && item.availableAmount === "100.00")).toBe(true);
  });

  it("lists and registers the company numbering range", async () => {
    const { user } = await tenant();
    await query.registerSequence(user, { documentType: "E31", startNumber: 1, endNumber: 10 });
    const sequences = await query.listSequences(user);
    expect(sequences.items).toHaveLength(1);
    expect(sequences.items[0]).toMatchObject({ documentType: "E31", startNumber: 1, nextNumber: 1,
      endNumber: 10, remaining: 10, consumed: 0 });
  });

  it("projects the frozen receiver and the amount, never the provider payload", async () => {
    const { companyId, user } = await tenant();
    await localDoc(companyId, "E34", "LOCAL_VALIDATED").then((doc) =>
      prisma.ecfElectronicDocument.update({
        where: { companyId_id: { companyId, id: doc.id } },
        data: {
          payloadSummary: {
            type: "E34", issueDate: "2026-10-15", currency: "DOP", total: "59.00",
            lineCount: 1, hasReference: true,
            receiver: { legalName: "Ferretería del Sur", taxId: "101000001" },
            reference: {
              originalENcf: "E310000000001", originalIssueDate: "2026-10-14", originalType: "E31",
            },
          },
        },
      }),
    );

    const list = await query.list(user, {});
    expect(list.items).toHaveLength(1);
    const item = list.items[0];
    expect(item.receiverName).toBe("Ferretería del Sur");
    expect(item.receiverTaxId).toBe("101000001");
    expect(item.total).toBe("59.00");
    expect(item.currency).toBe("DOP");
    expect(item.originalEncf).toBe("E310000000001");
    // El resumen contratado con el proveedor nunca se expone a la aplicación.
    expect(item).not.toHaveProperty("payloadSummary");
    expect(item).not.toHaveProperty("fiscalSnapshot");
  });

  it("does not invent a receiver for a document that never froze one", async () => {
    const { companyId, user } = await tenant();
    await localDoc(companyId, "E31", "LOCAL_VALIDATED");
    const list = await query.list(user, {});
    expect(list.items[0].receiverName).toBeNull();
    expect(list.items[0].receiverTaxId).toBeNull();
  });

  it("paginates with take/skip and reports the filtered total", async () => {
    const { companyId, user } = await tenant();
    for (let index = 0; index < 3; index += 1) {
      await localDoc(companyId, "E31", "LOCAL_VALIDATED");
    }
    const first = await query.list(user, { take: 2, skip: 0 });
    expect(first.total).toBe(3);
    expect(first.items).toHaveLength(2);
    const second = await query.list(user, { take: 2, skip: 2 });
    expect(second.total).toBe(3);
    expect(second.items).toHaveLength(1);
    expect(second.items[0].id).not.toBe(first.items[0].id);
  });
});
