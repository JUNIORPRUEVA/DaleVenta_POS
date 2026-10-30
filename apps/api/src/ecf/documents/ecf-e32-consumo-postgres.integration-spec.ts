import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfDocumentQueryService } from "./ecf-document-query.service";
import { EcfPreparationService } from "./ecf-preparation.service";
import { EcfSequenceService } from "./ecf-sequence.service";

// Opt-in suite on the ephemeral test database. La preparación de consumo (E32)
// crea un borrador local: no hay red, no hay proveedor, no se declara ninguna
// aceptación y NO se consume numeración.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("E32 consumo (venta → borrador local sin numeración) on PostgreSQL", () => {
  let prisma: PrismaService;
  let preparation: EcfPreparationService;
  let query: EcfDocumentQueryService;
  let userId: string;
  let unitId: string;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_E32_CONSUMO_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    preparation = new EcfPreparationService(prisma);
    query = new EcfDocumentQueryService(prisma);
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-consumo-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic Consumo User",
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

  /** Empresa habilitada con rango E31/E34 para comprobar que NO se toca. */
  async function tenant(options: { enabled?: boolean; allowedTypes?: string[] } = {}) {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name: "Synthetic consumo", slug: `ecf-consumo-${companyId}` },
    });
    await prisma.ecfCompanyConfiguration.create({
      data: {
        companyId,
        enabled: options.enabled ?? true,
        environment: "SANDBOX",
        allowedTypes: options.allowedTypes ?? ["E31", "E32"],
      },
    });
    const user = { id: userId, role: "ADMIN", companyId } as TenantUser;
    const sequences = new EcfSequenceService(prisma);
    await sequences.register(user, { documentType: "E31", startNumber: 1, endNumber: 10 });
    await sequences.register(user, { documentType: "E34", startNumber: 1, endNumber: 10 });
    return { companyId, user };
  }

  /**
   * Venta de consumo final: sin receptor, que es lo que E32 representa. E31
   * exigiría RNC y razón social.
   */
  async function createSale(companyId: string, withBuyer = false) {
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
        ...(withBuyer
          ? { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" }
          : {}),
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

  const consumoInput = (saleId: string) => ({
    saleId,
    documentType: "E32" as const,
    paymentType: 1 as const,
    incomeType: 1 as const,
  });

  it("prepares a local E32 draft from a consumo sale without allocating a number", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.documentType).toBe("E32");
    expect(result.value.encf).toBeNull();
    expect(result.value.numberingState).toBe("PENDING_SANDBOX_SLOT");
    expect(result.value.status).toBe("LOCAL_VALIDATED");
    expect(result.value.saleId).toBe(sale.id);

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: result.value.documentId },
    });
    expect(stored.documentType).toBe("E32");
    expect(stored.sourceType).toBe("SALE");
    expect(stored.sourceId).toBe(sale.id);
    // Sin número asignado no puede haber e-NCF persistido.
    expect(stored.externalDocumentNumber).toBeNull();
    expect(stored.status).toBe("LOCAL_VALIDATED");
  });

  it("never consumes the company numbering range and never opens an E32 range", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    const before = await prisma.ecfSequence.findMany({
      where: { companyId },
      select: { documentType: true, nextNumber: true },
      orderBy: { documentType: "asc" },
    });
    const auditsBefore = await prisma.ecfSequenceAuditLog.count({ where: { companyId } });

    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));
    expect(result.ok).toBe(true);

    const after = await prisma.ecfSequence.findMany({
      where: { companyId },
      select: { documentType: true, nextNumber: true },
      orderBy: { documentType: "asc" },
    });
    expect(after).toEqual(before);
    expect(after.some((row) => row.documentType === "E32")).toBe(false);
    expect(await prisma.ecfSequenceAuditLog.count({ where: { companyId } })).toBe(auditsBefore);
  });

  it("is idempotent per sale: a retry returns the same document", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const first = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));
    const second = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(second.value.documentId).toBe(first.value.documentId);
    expect(
      await prisma.ecfElectronicDocument.count({
        where: { companyId, sourceType: "SALE", sourceId: sale.id },
      }),
    ).toBe(1);
  });

  it("the one-document-per-sale rule holds in BOTH directions", async () => {
    const consumo = await tenant();
    // Con receptor: así el rechazo del segundo intento viene de la guarda de
    // "un comprobante por venta" y no de la falta de datos del cliente.
    const consumoSale = await createSale(consumo.companyId, true);
    const first = await preparation.prepareConsumoFromSale(
      consumo.user,
      consumoInput(consumoSale.id),
    );
    expect(first.ok).toBe(true);
    // E31 sobre una venta que ya es E32 también se rechaza.
    const reverse = await preparation.prepareFromSale(consumo.user, {
      saleId: consumoSale.id,
      documentType: "E31",
      paymentType: 1,
      incomeType: 1,
      sequenceDueDate: "2026-12-31",
    });
    expect(reverse.ok).toBe(false);
    if (reverse.ok) return;
    expect(reverse.code).toBe("ECF_SALE_ALREADY_PREPARED_AS_OTHER_TYPE");
    expect(
      await prisma.ecfElectronicDocument.count({
        where: { companyId: consumo.companyId, sourceType: "SALE", sourceId: consumoSale.id },
      }),
    ).toBe(1);
  });

  it("refuses E32 over a sale that already has another fiscal document", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId, true);
    const e31 = await preparation.prepareFromSale(user, {
      saleId: sale.id,
      documentType: "E31",
      paymentType: 1,
      incomeType: 1,
      sequenceDueDate: "2026-12-31",
    });
    expect(e31.ok).toBe(true);

    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_SALE_ALREADY_PREPARED_AS_OTHER_TYPE");
  });

  it("refuses when the company has e-CF disabled", async () => {
    const { companyId, user } = await tenant({ enabled: false });
    const sale = await createSale(companyId);

    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_COMPANY_DISABLED");
    expect(
      await prisma.ecfElectronicDocument.count({ where: { companyId } }),
    ).toBe(0);
  });

  it("refuses when E32 is not enabled for the company", async () => {
    const { companyId, user } = await tenant({ allowedTypes: ["E31"] });
    const sale = await createSale(companyId);

    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DOCUMENT_TYPE_NOT_ALLOWED");
  });

  it("refuses a non-E32 type through the consumo path", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const result = await preparation.prepareConsumoFromSale(user, {
      ...consumoInput(sale.id),
      documentType: "E31" as never,
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_CONSUMO_TYPE_REQUIRED");
  });

  it("never reads another company's sale", async () => {
    const a = await tenant();
    const b = await tenant();
    const sale = await createSale(a.companyId);

    const result = await preparation.prepareConsumoFromSale(b.user, consumoInput(sale.id));

    expect(result.ok).toBe(false);
    expect(
      await prisma.ecfElectronicDocument.count({ where: { companyId: b.companyId } }),
    ).toBe(0);
  });

  it("preparing consumo does not touch inventory, cash or the sale", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    const saleBefore = await prisma.sale.findFirstOrThrow({ where: { companyId, id: sale.id } });

    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));
    expect(result.ok).toBe(true);

    const saleAfter = await prisma.sale.findFirstOrThrow({ where: { companyId, id: sale.id } });
    expect(saleAfter).toEqual(saleBefore);
    expect(await prisma.inventoryMovement.count({ where: { companyId } })).toBe(0);
    expect(await prisma.saleItem.count({ where: { saleId: sale.id } })).toBe(1);
  });

  it("is not emitting: no provider id, no attempt, no emission summary", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: result.value.documentId },
    });
    expect(stored.externalProviderId).toBeNull();
    expect(stored.status).not.toBe("DGII_ACCEPTED");
    expect(stored.status).not.toBe("PROVIDER_ACCEPTED");
    const summary = (stored.payloadSummary ?? {}) as Record<string, unknown>;
    expect(summary.emission).toBeUndefined();
    expect(summary.type).toBe("E32");
  });

  it("the draft shows up in the company tray without an e-NCF", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    const list = await query.list(user, { documentType: "E32" });

    expect(list.total).toBe(1);
    expect(list.items[0].documentType).toBe("E32");
    expect(list.items[0].encf).toBeNull();
    expect(list.items[0].status).toBe("LOCAL_VALIDATED");
    expect(list.items[0].statusGroup).toBe("PENDING");
    expect(list.items[0].total).toBe("59.00");
    expect(list.items[0].currency).toBe("DOP");
  });
});
