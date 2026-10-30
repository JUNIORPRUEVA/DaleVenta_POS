import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfSaleFiscalAdapter } from "./ecf-sale-fiscal.adapter";

// Opt-in suite on the ephemeral test database. Synthetic sales only: the adapter
// READS persisted data and never writes, emits or contacts a provider.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

type LineSpec = {
  name: string;
  qty: string;
  unitPrice: string;
  taxableBase: string;
  taxAmount: string;
  taxRate: string;
  discount?: string;
  exemptAmount?: string;
  taxExempt?: boolean;
  itemType?: "PRODUCT" | "SERVICE" | null;
};

uat("EcfSaleFiscalAdapter (venta → snapshot fiscal) on PostgreSQL", () => {
  let prisma: PrismaService;
  let adapter: EcfSaleFiscalAdapter;
  let userId: string;
  let unitId: string;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_ADAPTER_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    adapter = new EcfSaleFiscalAdapter(prisma);
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-adapter-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic Adapter User",
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
      data: { id: companyId, name: "Synthetic adapter", slug: `ecf-adp-${companyId}` },
    });
    return { companyId, user: { id: userId, role: "ADMIN", companyId } as TenantUser };
  }

  const money = (spec: LineSpec[]) => {
    const taxableBase = spec.reduce((a, l) => a + Number(l.taxableBase), 0);
    const exemptAmount = spec.reduce((a, l) => a + Number(l.exemptAmount ?? 0), 0);
    const discountAmount = spec.reduce((a, l) => a + Number(l.discount ?? 0), 0);
    const taxAmount = spec.reduce((a, l) => a + Number(l.taxAmount), 0);
    return {
      taxableBase: taxableBase.toFixed(2),
      exemptAmount: exemptAmount.toFixed(2),
      discountAmount: discountAmount.toFixed(2),
      taxAmount: taxAmount.toFixed(2),
      total: (taxableBase + exemptAmount + taxAmount).toFixed(2),
    };
  };

  async function createSale(input: {
    companyId: string;
    lines: LineSpec[];
    totals?: Partial<ReturnType<typeof money>>;
    sale?: Record<string, unknown>;
  }) {
    const totals = { ...money(input.lines), ...(input.totals ?? {}) };
    const sale = await prisma.sale.create({
      data: {
        companyId: input.companyId,
        userId,
        totalSold: totals.total,
        totalCost: "0.00",
        totalProfit: "0.00",
        commissionAmount: "0.00",
        taxableBase: totals.taxableBase,
        exemptAmount: totals.exemptAmount,
        discountAmount: totals.discountAmount,
        taxAmount: totals.taxAmount,
        fiscalTaxEnabled: true,
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1, Santo Domingo",
        issuerPhoneSnapshot: "8090000000",
        ...input.sale,
      },
    });
    for (const line of input.lines) {
      let productId: string | null = null;
      if (line.itemType !== null) {
        const product = await prisma.product.create({
          data: {
            companyId: input.companyId,
            nombre: line.name,
            codigo: `SKU-${randomUUID().slice(0, 8)}`,
            categoria: "General",
            costo: "1.00",
            precio: line.unitPrice,
            unitOfMeasureId: unitId,
            itemType: line.itemType ?? "PRODUCT",
            trackInventory: line.itemType !== "SERVICE",
          },
        });
        productId = product.id;
      }
      await prisma.saleItem.create({
        data: {
          saleId: sale.id,
          productId,
          productNameSnapshot: line.name,
          qty: line.qty,
          priceSoldUnit: line.unitPrice,
          grossAmount: (Number(line.qty) * Number(line.unitPrice)).toFixed(2),
          lineDiscountAmount: line.discount ?? "0.00",
          taxableBase: line.taxableBase,
          taxRate: line.taxRate,
          taxAmount: line.taxAmount,
          exemptAmount: line.exemptAmount ?? "0.00",
          taxExempt: line.taxExempt ?? false,
          costUnitSnapshot: "1.00",
          subtotalSold: line.taxableBase,
          subtotalCost: "1.00",
          profit: "0.00",
          // Congelado como lo haría el flujo de ventas real.
          itemTypeSnapshot: line.itemType === null ? null : (line.itemType ?? "PRODUCT"),
        },
      });
    }
    return { sale, totals };
  }

  const itbisLine: LineSpec = {
    name: "Producto gravado",
    qty: "1",
    unitPrice: "59.00",
    taxableBase: "50.00",
    taxAmount: "9.00",
    taxRate: "0.1800",
  };
  const exemptLine: LineSpec = {
    name: "Producto exento",
    qty: "1",
    unitPrice: "30.00",
    taxableBase: "0.00",
    taxAmount: "0.00",
    taxRate: "0.0000",
    exemptAmount: "30.00",
    taxExempt: true,
  };

  it("builds an E31 snapshot for an ITBIS sale from persisted data", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [itbisLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.type).toBe("E31");
    expect(result.value.snapshot.seller.taxId).toBe("101000001");
    expect(result.value.snapshot.buyer?.taxId).toBe("130000000");
    expect(result.value.snapshot.lines[0]).toMatchObject({
      name: "Producto gravado",
      taxCategory: "ITBIS_18",
      goodServiceIndicator: "GOOD",
      quantity: "1",
      // El contrato fiscal exige el precio unitario SIN impuesto: 50.00 base
      // (no el precio de venta 59.00, que ya incluye el ITBIS).
      unitPrice: "50.0000000000",
    });
    expect(result.value.snapshot.totals).toEqual({
      subtotal: "50.00",
      taxableBase: "50.00",
      exemptAmount: "0.00",
      discountAmount: "0.00",
      itbisAmount: "9.00",
      total: "59.00",
    });
    expect(result.value.evidence.snapshotFingerprint).toHaveLength(64);
  });

  it("marks exempt lines as EXEMPT and keeps them out of the taxable base", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [exemptLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.lines[0].taxCategory).toBe("EXEMPT");
    expect(result.value.snapshot.totals.taxableBase).toBe("0.00");
    expect(result.value.snapshot.totals.exemptAmount).toBe("30.00");
  });

  it("handles a mixed sale (ITBIS + exempt) with both categories", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [itbisLine, exemptLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.lines.map((line) => line.taxCategory)).toEqual([
      "ITBIS_18",
      "EXEMPT",
    ]);
    expect(result.value.snapshot.totals).toMatchObject({
      taxableBase: "50.00",
      exemptAmount: "30.00",
      itbisAmount: "9.00",
      total: "89.00",
    });
  });

  it("preserves line discounts", async () => {
    const { companyId, user } = await tenant();
    const discounted: LineSpec = {
      name: "Con descuento",
      qty: "2",
      unitPrice: "29.50",
      taxableBase: "50.00",
      taxAmount: "9.00",
      taxRate: "0.1800",
      discount: "9.00",
    };
    const { sale } = await createSale({
      companyId,
      lines: [discounted],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.lines[0].discountAmount).toBe("9");
    expect(result.value.snapshot.totals.discountAmount).toBe("9.00");
  });

  it("classifies a service line from Product.itemType", async () => {
    const { companyId, user } = await tenant();
    const service: LineSpec = {
      name: "Servicio técnico",
      qty: "1",
      unitPrice: "59.00",
      taxableBase: "50.00",
      taxAmount: "9.00",
      taxRate: "0.1800",
      itemType: "SERVICE",
    };
    const { sale } = await createSale({
      companyId,
      lines: [service],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.lines[0].goodServiceIndicator).toBe("SERVICE");
  });

  it("keeps the fiscal classification frozen when the product type changes later", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [itbisLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });
    const item = await prisma.saleItem.findFirstOrThrow({ where: { saleId: sale.id } });

    // El producto pasa a ser un SERVICIO DESPUÉS de la venta.
    await prisma.product.update({
      where: { id: item.productId! },
      data: { itemType: "SERVICE" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // La venta sigue siendo un BIEN: la clasificación se congeló al venderla.
    expect(result.value.snapshot.lines[0].goodServiceIndicator).toBe("GOOD");
    const reloaded = await prisma.saleItem.findFirstOrThrow({
      where: { saleId: sale.id },
    });
    expect(reloaded.itemTypeSnapshot).toBe("PRODUCT");
  });

  it("keeps the frozen classification when the product is archived afterwards", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [{ ...itbisLine, itemType: "SERVICE" }],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });
    const item = await prisma.saleItem.findFirstOrThrow({ where: { saleId: sale.id } });
    await prisma.product.update({
      where: { id: item.productId! },
      data: { archivedAt: new Date() },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.lines[0].goodServiceIndicator).toBe("SERVICE");
  });

  it("prepares an E32 for final consumer without identifying the buyer", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({ companyId, lines: [itbisLine] });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E32" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.type).toBe("E32");
    expect(result.value.snapshot.buyer?.taxId).toBeUndefined();
  });

  it("refuses E31 without an identified buyer", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({ companyId, lines: [itbisLine] });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_BUYER_DATA_REQUIRED");
  });

  it.each([
    ["ECF_SALE_CANCELLED", { cancelledAt: new Date(), cancellationReason: "synthetic" }],
    ["ECF_SALE_DELETED", { isDeleted: true, deletedAt: new Date() }],
  ])("refuses a sale that is not eligible with %s", async (code, overrides) => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [itbisLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA", ...overrides },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(code);
  });

  it("refuses a refund sale: it belongs to E34, not to a new comprobante", async () => {
    const { companyId, user } = await tenant();
    const original = await createSale({
      companyId,
      lines: [itbisLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });
    const refund = await createSale({
      companyId,
      lines: [itbisLine],
      sale: {
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
        refundedSaleId: original.sale.id,
        kind: "refund",
      },
    });

    const result = await adapter.build(user, { saleId: refund.sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_SALE_IS_REFUND");
  });

  it("never reads a sale from another company", async () => {
    const a = await tenant();
    const b = await tenant();
    const { sale } = await createSale({
      companyId: a.companyId,
      lines: [itbisLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(b.user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_SALE_NOT_FOUND");
  });

  it("blocks when the issuer fiscal data is incomplete", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [itbisLine],
      sale: {
        issuerTaxIdSnapshot: null,
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
      },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_ISSUER_DATA_INCOMPLETE");
    expect(result.safeMessage).toContain("RNC");
  });

  it("refuses a tax rate it cannot map instead of approximating it", async () => {
    const { companyId, user } = await tenant();
    const odd: LineSpec = {
      name: "Tasa rara",
      qty: "1",
      unitPrice: "19.00",
      taxableBase: "16.10",
      taxAmount: "2.90",
      taxRate: "0.1900",
    };
    const { sale } = await createSale({
      companyId,
      lines: [odd],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_UNSUPPORTED_TAX_RATE");
  });

  it("blocks a line whose fiscal classification was never captured", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [{ ...itbisLine, itemType: null }],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_LINE_CLASSIFICATION_UNCONFIRMED");
  });

  it("blocks when the lines and the sale totals contradict each other", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [itbisLine],
      totals: { total: "999.99" },
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_SALE_TOTALS_MISMATCH");
    expect(result.safeMessage).toContain("total");
  });

  it("blocks a sale without items", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [],
      totals: { taxableBase: "0.00", exemptAmount: "0.00", discountAmount: "0.00", taxAmount: "0.00", total: "0.00" },
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_SALE_HAS_NO_ITEMS");
  });

  it("reconciles amounts at the rounding limit", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [
        { name: "Céntimo", qty: "1", unitPrice: "0.01", taxableBase: "0.01", taxAmount: "0.00", taxRate: "0.0000" },
        { name: "Fracción", qty: "0.333", unitPrice: "3.00", taxableBase: "1.00", taxAmount: "0.18", taxRate: "0.1800" },
      ],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const result = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.snapshot.totals.total).toBe("1.19");
  });

  it("produces the same evidence fingerprint for the same persisted sale", async () => {
    const { companyId, user } = await tenant();
    const { sale } = await createSale({
      companyId,
      lines: [itbisLine],
      sale: { fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Cliente SA" },
    });

    const first = await adapter.build(user, { saleId: sale.id, documentType: "E31" });
    const second = await adapter.build(user, { saleId: sale.id, documentType: "E31" });

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(second.value.evidence.snapshotFingerprint).toBe(
      first.value.evidence.snapshotFingerprint,
    );
  });
});
