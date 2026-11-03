import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfDocumentQueryService } from "./ecf-document-query.service";
import { fingerprint } from "./ecf-document-idempotency.service";
import { EcfPreparationService } from "./ecf-preparation.service";
import { EcfSequenceService } from "./ecf-sequence.service";

// Opt-in suite on the ephemeral test database. Verifica que el comprobante
// preparado quede guardado ÍNTEGRO, sea reconstruible y no pueda alterarse
// después. No hay red, no hay proveedor y no se declara ninguna aceptación.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("persistencia íntegra del comprobante preparado on PostgreSQL", () => {
  let prisma: PrismaService;
  let preparation: EcfPreparationService;
  let query: EcfDocumentQueryService;
  let userId: string;
  let unitId: string;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_FISCAL_DOCUMENT_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    preparation = new EcfPreparationService(prisma);
    query = new EcfDocumentQueryService(prisma);
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-doc-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic Document User",
        telefono: "0000000000",
        edad: 30,
        role: "ADMIN",
      },
    });
    unitId = `UNIT_${randomUUID().slice(0, 8)}`;
    await prisma.unitOfMeasure.create({
      data: { id: unitId, code: unitId, name: "Unidad", symbol: "u", category: "COUNT" },
    });
  });
  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: userId } });
    await prisma?.$disconnect();
  });

  async function tenant() {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name: "Synthetic document", slug: `ecf-doc-${companyId}` },
    });
    await prisma.ecfCompanyConfiguration.create({
      data: { companyId, enabled: true, environment: "SANDBOX" },
    });
    const user = { id: userId, role: "ADMIN", companyId } as TenantUser;
    await new EcfSequenceService(prisma).register(user, {
      documentType: "E31",
      startNumber: 1,
      endNumber: 10,
    });
    return { companyId, user };
  }

  async function createSale(companyId: string) {
    const sale = await prisma.sale.create({
      data: {
        companyId,
        userId,
        totalSold: "59.00",
        totalCost: "1.00",
        totalProfit: "0.00",
        commissionAmount: "0.00",
        taxableBase: "50.00",
        exemptAmount: "0.00",
        discountAmount: "0.00",
        taxAmount: "9.00",
        fiscalTaxEnabled: true,
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1, Santo Domingo",
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
      },
    });
    const product = await prisma.product.create({
      data: {
        companyId,
        nombre: "Producto gravado",
        codigo: `SKU-${randomUUID().slice(0, 8)}`,
        categoria: "General",
        costo: "1.00",
        precio: "59.00",
        unitOfMeasureId: unitId,
        itemType: "PRODUCT",
      },
    });
    await prisma.saleItem.create({
      data: {
        saleId: sale.id,
        productId: product.id,
        productNameSnapshot: "Producto gravado",
        qty: "1",
        priceSoldUnit: "59.00",
        grossAmount: "59.00",
        lineDiscountAmount: "0.00",
        taxableBase: "50.00",
        taxRate: "0.1800",
        taxAmount: "9.00",
        exemptAmount: "0.00",
        costUnitSnapshot: "1.00",
        subtotalSold: "50.00",
        subtotalCost: "1.00",
        profit: "0.00",
        itemTypeSnapshot: "PRODUCT",
      },
    });
    return sale;
  }

  async function preparedDocument() {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    const result = await preparation.prepareFromSale(user, {
      saleId: sale.id,
      documentType: "E31",
      paymentType: 1,
      incomeType: 1,
      sequenceDueDate: "2026-12-31",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("PREPARATION_FAILED");
    return { companyId, user, documentId: result.value.documentId };
  }

  it("stores the WHOLE prepared document, not just a summary", async () => {
    const { companyId, documentId } = await preparedDocument();

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: documentId },
    });

    expect(stored.fiscalDocument).not.toBeNull();
    const document = stored.fiscalDocument as Record<string, unknown>;
    // Partidas, emisor y receptor: lo que un resumen no conservaba.
    expect(Array.isArray(document.lines)).toBe(true);
    expect((document.lines as unknown[]).length).toBe(1);
    expect((document.sender as Record<string, unknown>).taxId).toBe("101000001");
    expect((document.buyer as Record<string, unknown>).taxId).toBe("130000000");
    expect((document.totals as Record<string, unknown>).total).toBe("59.00");
  });

  it("the stored document reproduces the persisted fingerprint", async () => {
    const { companyId, documentId } = await preparedDocument();

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: documentId },
    });

    // Reconstrucción verificable: la huella se recobra desde lo guardado.
    expect(fingerprint(stored.fiscalDocument)).toBe(stored.payloadFingerprint);
  });

  it("the summary stays a summary: it does not smuggle the whole document", async () => {
    const { companyId, documentId } = await preparedDocument();

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: documentId },
    });

    const summary = stored.payloadSummary as Record<string, unknown>;
    expect(summary.lines).toBeUndefined();
    expect(summary.sender).toBeUndefined();
    expect(summary.lineCount).toBe(1);
  });

  it("a prepared document cannot be altered afterwards", async () => {
    const { companyId, documentId } = await preparedDocument();

    await expect(
      prisma.ecfElectronicDocument.update({
        where: { companyId_id: { companyId, id: documentId } },
        data: { fiscalDocument: { tampered: true } },
      }),
    ).rejects.toThrow("ECF_FISCAL_DOCUMENT_IMMUTABLE");

    // Y sigue intacto después del intento.
    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: documentId },
    });
    expect((stored.fiscalDocument as Record<string, unknown>).tampered).toBeUndefined();
    expect(fingerprint(stored.fiscalDocument)).toBe(stored.payloadFingerprint);
  });

  it("the rest of the row may still evolve without touching the document", async () => {
    const { companyId, documentId } = await preparedDocument();

    // El estado y el resumen de emisión sí evolucionan: la inmutabilidad es del
    // contenido fiscal preparado, no de toda la fila.
    await prisma.ecfElectronicDocument.update({
      where: { companyId_id: { companyId, id: documentId } },
      data: { status: "HUMAN_REVIEW_REQUIRED", safeErrorCode: "SYNTHETIC_ONLY" },
    });

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: documentId },
    });
    expect(stored.status).toBe("HUMAN_REVIEW_REQUIRED");
    expect(fingerprint(stored.fiscalDocument)).toBe(stored.payloadFingerprint);
  });

  it("the read API never returns the stored fiscal document", async () => {
    const { user, documentId } = await preparedDocument();

    const detail = await query.detail(user, documentId);
    expect(detail).not.toHaveProperty("fiscalDocument");

    const list = await query.list(user, {});
    expect(list.items).toHaveLength(1);
    expect(list.items[0]).not.toHaveProperty("fiscalDocument");
    expect(list.items[0]).not.toHaveProperty("payloadSummary");
  });

  it("documents prepared before this column keep working with a null document", async () => {
    const { companyId, user } = await tenant();
    // Fila equivalente a un comprobante preparado con una versión anterior.
    const legacy = await prisma.ecfElectronicDocument.create({
      data: {
        companyId,
        documentType: "E31",
        status: "LOCAL_VALIDATED",
        externalDocumentNumber: "E310000000009",
        idempotencyKey: `legacy-${randomUUID()}`,
        payloadFingerprint: "e".repeat(64),
        payloadSummary: { type: "E31", total: "59.00", currency: "DOP" },
      },
    });

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: legacy.id },
    });
    expect(stored.fiscalDocument).toBeNull();

    // La bandeja y el detalle siguen funcionando sin ese dato.
    const detail = await query.detail(user, legacy.id);
    expect(detail.encf).toBe("E310000000009");
    const list = await query.list(user, {});
    expect(list.total).toBe(1);
  });
});
