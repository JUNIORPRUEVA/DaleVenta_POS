import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfDocumentQueryService } from "./ecf-document-query.service";
import { EcfPreparationService } from "./ecf-preparation.service";
import { EcfSequenceService } from "./ecf-sequence.service";

// Opt-in suite on the ephemeral test database. La preparación de consumo (E32)
// crea un borrador local numerado: no hay red, no hay proveedor y no se declara
// ninguna aceptación, pero SÍ se consume un e-NCF del rango autorizado por la
// DGII para ese tipo, porque un comprobante de consumo sin número no es emitible.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("E32 consumo (venta → borrador local numerado) on PostgreSQL", () => {
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

  /** Empresa habilitada con numeración E31, E32 y E34 declarada y autorizada. */
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
    // La numeración exige autorización DGII declarada (fail-closed).
    for (const documentType of ["E31", "E32", "E34"]) {
      await prisma.ecfDgiiAuthorizedSequence.create({
        data: {
          environment: "SANDBOX",
          companyId,
          documentType,
          authorizationNumber: `SYNTH-${documentType}`,
          rangeFrom: 1,
          rangeTo: 10_000,
          approvedQuantity: 10_000,
          declarationVersion: "v1",
          declaredByUserId: userId,
        },
      });
    }
    const sequences = new EcfSequenceService(prisma);
    await sequences.register(user, { documentType: "E31", startNumber: 1, endNumber: 10 });
    await sequences.register(user, { documentType: "E32", startNumber: 1, endNumber: 10 });
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

  it("prepares a numbered E32 draft from a consumo sale", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const result = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.documentType).toBe("E32");
    expect(result.value.encf).toMatch(/^E32\d{10}$/);
    expect(result.value.numberingState).toBe("ALLOCATED_FROM_AUTHORIZED_RANGE");
    expect(result.value.status).toBe("LOCAL_VALIDATED");
    expect(result.value.saleId).toBe(sale.id);

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: result.value.documentId },
    });
    expect(stored.documentType).toBe("E32");
    expect(stored.sourceType).toBe("SALE");
    expect(stored.sourceId).toBe(sale.id);
    // El e-NCF queda reservado en el resumen de emisión del borrador.
    const summary = (stored.payloadSummary ?? {}) as Record<string, any>;
    expect(summary.emission?.encf).toBe(result.value.encf);
    expect(stored.status).toBe("LOCAL_VALIDATED");
  });

  it("consumes exactly one E32 number and never touches the E31/E34 ranges", async () => {
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
    // Solo avanza el rango de consumo.
    expect(after).toEqual(
      before.map((row) =>
        row.documentType === "E32" ? { ...row, nextNumber: row.nextNumber + 1 } : row,
      ),
    );
    expect(await prisma.ecfSequenceAuditLog.count({ where: { companyId } })).toBe(auditsBefore + 1);
    expect(
      await prisma.ecfSequenceAuditLog.count({
        where: { companyId, action: "ALLOCATED", type: "E32" },
      }),
    ).toBe(1);
  });

  it("refuses consumo when E32 has no DGII authorization declared", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    // El rango sigue registrado, pero sin la autorización de la DGII no se
    // entrega ningún número: la compuerta vive dentro de la transacción.
    await prisma.ecfDgiiAuthorizedSequence.deleteMany({
      where: { companyId, documentType: "E32" },
    });

    await expect(
      preparation.prepareConsumoFromSale(user, consumoInput(sale.id)),
    ).rejects.toThrow(/ECF_SEQUENCE_NOT_AUTHORIZED/);
    expect(
      await prisma.ecfElectronicDocument.count({
        where: { companyId, sourceType: "SALE", sourceId: sale.id },
      }),
    ).toBe(0);
  });

  it("is idempotent per sale: a retry reuses the same document AND the same e-NCF", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const first = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));
    const second = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(second.value.documentId).toBe(first.value.documentId);
    expect(second.value.encf).toBe(first.value.encf);
    // Un reintento no puede quemar un segundo número.
    expect(
      await prisma.ecfSequenceAuditLog.count({
        where: { companyId, action: "ALLOCATED", type: "E32" },
      }),
    ).toBe(1);
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

  it("is not emitting: the e-NCF is reserved but nothing was sent", async () => {
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
    // El resumen de emisión existe porque el número está reservado; lo que no
    // existe es una aceptación ni un envío.
    expect((summary.emission as { encf?: string } | undefined)?.encf).toBe(result.value.encf);
    expect(summary.type).toBe("E32");
  });

  it("the draft shows up in the company tray WITH its e-NCF", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    const prepared = await preparation.prepareConsumoFromSale(user, consumoInput(sale.id));
    expect(prepared.ok).toBe(true);
    if (!prepared.ok) return;

    const list = await query.list(user, { documentType: "E32" });

    expect(list.total).toBe(1);
    expect(list.items[0].documentType).toBe("E32");
    expect(list.items[0].encf).toBe(prepared.value.encf);
    expect(list.items[0].status).toBe("LOCAL_VALIDATED");
    expect(list.items[0].statusGroup).toBe("PENDING");
    expect(list.items[0].total).toBe("59.00");
    expect(list.items[0].currency).toBe("DOP");
  });
});
