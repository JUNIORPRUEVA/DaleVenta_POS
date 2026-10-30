import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfPreparationService } from "./ecf-preparation.service";
import { EcfSequenceService } from "./ecf-sequence.service";

// Opt-in suite on the ephemeral test database. Preparar crea un borrador local:
// no hay red, no hay proveedor y ninguna aceptación se declara.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("EcfPreparationService (venta → borrador e-CF) on PostgreSQL", () => {
  let prisma: PrismaService;
  let preparation: EcfPreparationService;
  let userId: string;
  let unitId: string;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_PREPARATION_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    preparation = new EcfPreparationService(prisma);
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-prep-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic Preparation User",
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

  /** Empresa habilitada (o no) con un rango E31 disponible. */
  async function tenant(options: { enabled?: boolean; allowedTypes?: string[]; withRange?: boolean } = {}) {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name: "Synthetic prep", slug: `ecf-prep-${companyId}` },
    });
    await prisma.ecfCompanyConfiguration.create({
      data: {
        companyId,
        enabled: options.enabled ?? true,
        environment: "SANDBOX",
        allowedTypes: options.allowedTypes ?? undefined,
      },
    });
    const user = { id: userId, role: "ADMIN", companyId } as TenantUser;
    if (options.withRange !== false) {
      await new EcfSequenceService(prisma).register(user, {
        documentType: "E31",
        startNumber: 1,
        endNumber: 10,
      });
    }
    return { companyId, user };
  }

  async function createSale(companyId: string, withBuyer = true) {
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
        // Congelado como lo haría el flujo de ventas real.
        itemTypeSnapshot: "PRODUCT",
      },
    });
    return sale;
  }

  const baseInput = (saleId: string) => ({
    saleId,
    documentType: "E31" as const,
    paymentType: 1 as const,
    incomeType: 1 as const,
    // Exigido por el contrato E31 (`idDoc.sequenceDueDate`); no se inventa.
    sequenceDueDate: "2026-12-31",
  });

  it("prepares an E31 draft from a real sale and allocates the e-NCF", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const result = await preparation.prepareFromSale(user, baseInput(sale.id));

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.encf).toBe("E310000000001");
    expect(result.value.status).toBe("LOCAL_VALIDATED");
    expect(result.value.saleId).toBe(sale.id);
    expect(result.value.evidence.snapshotFingerprint).toHaveLength(64);

    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: result.value.documentId },
    });
    expect(stored.sourceType).toBe("SALE");
    expect(stored.sourceId).toBe(sale.id);
  });

  it("preparing is NOT emitting: no provider id, no attempt, no evidence receipt", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const result = await preparation.prepareFromSale(user, baseInput(sale.id));

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const stored = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: result.value.documentId },
    });
    expect(stored.externalProviderId).toBeNull();
    expect(stored.status).not.toBe("DGII_ACCEPTED");
    expect(
      await prisma.ecfElectronicDocumentAttempt.count({
        where: {
          companyId,
          documentId: result.value.documentId,
          operation: "SEND_TO_PROVIDER",
        },
      }),
    ).toBe(0);
    expect(
      await prisma.ecfEvidenceReceipt.count({
        where: { companyId, documentId: result.value.documentId },
      }),
    ).toBe(0);
  });

  it("refuses to prepare while the company has e-CF switched off", async () => {
    const { companyId, user } = await tenant({ enabled: false });
    const sale = await createSale(companyId);

    const result = await preparation.prepareFromSale(user, baseInput(sale.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_COMPANY_DISABLED");
  });

  it("refuses a document type the company does not allow", async () => {
    const { companyId, user } = await tenant({ allowedTypes: ["E32"] });
    const sale = await createSale(companyId);

    const result = await preparation.prepareFromSale(user, baseInput(sale.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DOCUMENT_TYPE_NOT_ALLOWED");
  });

  it("refuses E32: it belongs to the sandbox single-use flow, not to the sale flow", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId, false);

    const result = await preparation.prepareFromSale(user, {
      ...baseInput(sale.id),
      documentType: "E32" as unknown as "E31",
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_TYPE_REQUIRES_SANDBOX_FLOW");
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId } })).toBe(0);
  });

  it("is idempotent per sale and consumes a single number", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    const input = baseInput(sale.id);

    const first = await preparation.prepareFromSale(user, input);
    const second = await preparation.prepareFromSale(user, input);

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(second.value.documentId).toBe(first.value.documentId);
    expect(second.value.encf).toBe(first.value.encf);
    // Una venta no puede producir dos comprobantes: solo se consumió un número.
    const sequence = await prisma.ecfSequence.findFirstOrThrow({ where: { companyId } });
    expect(sequence.nextNumber).toBe(2);
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId } })).toBe(1);
  });

  it("refuses to re-prepare the same sale with divergent data", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const first = await preparation.prepareFromSale(user, baseInput(sale.id));
    expect(first.ok).toBe(true);

    // Misma venta, otro dato fiscal: el documento es el mismo pero el payload
    // cambiaría, así que se bloquea en vez de divergir en silencio. (Se cambia
    // `incomeType` y no `paymentType` porque ese último falla antes por
    // contrato, no por divergencia.)
    await expect(
      preparation.prepareFromSale(user, { ...baseInput(sale.id), incomeType: 2 }),
    ).rejects.toThrow("ECF_EMISSION_PAYLOAD_DIVERGENCE");
  });

  it("refuses to prepare a sale from another company", async () => {
    const a = await tenant();
    const b = await tenant();
    const sale = await createSale(a.companyId);

    const result = await preparation.prepareFromSale(b.user, baseInput(sale.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_SALE_NOT_FOUND");
  });

  it("surfaces the adapter failure instead of producing a document", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId, false);

    const result = await preparation.prepareFromSale(user, baseInput(sale.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_BUYER_DATA_REQUIRED");
    expect(
      await prisma.ecfElectronicDocument.count({ where: { companyId } }),
    ).toBe(0);
  });

  it("refuses to prepare when the company has no numbering range", async () => {
    const { companyId, user } = await tenant({ withRange: false });
    const sale = await createSale(companyId);

    // El orquestador protege la numeración lanzando un error de dominio: no
    // existe borrador ni se consume nada cuando no hay rango disponible.
    await expect(
      preparation.prepareFromSale(user, baseInput(sale.id)),
    ).rejects.toThrow("ECF_SEQUENCE_EXHAUSTED");
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId } })).toBe(0);
  });
});
