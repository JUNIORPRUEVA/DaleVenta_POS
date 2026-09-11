import { Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

const companyId = "11111111-1111-4111-8111-111111111111";
const user = {
  id: "22222222-2222-4222-8222-222222222222",
  role: "ADMIN",
  companyId,
};

function taxCalculator() {
  return {
    calculate: jest.fn((input: any) => ({
      total: input.lines.reduce(
        (sum: Prisma.Decimal, line: any) =>
          sum.plus(new Prisma.Decimal(line.quantity).mul(line.unitPrice)),
        new Prisma.Decimal(0),
      ),
      taxableBase: new Prisma.Decimal("100"),
      taxAmount: new Prisma.Decimal("18"),
      exemptAmount: new Prisma.Decimal("0"),
      discountAmount: new Prisma.Decimal("0"),
      lines: input.lines.map((line: any, index: number) => {
        const lineTotal = new Prisma.Decimal(line.quantity).mul(line.unitPrice);
        return {
          index,
          grossAmount: lineTotal,
          discountAmount: new Prisma.Decimal(0),
          taxableBase: lineTotal,
          taxRate: new Prisma.Decimal("0.18"),
          taxAmount: lineTotal.mul("0.18").toDecimalPlaces(2),
          exemptAmount: new Prisma.Decimal(0),
          taxIncluded: false,
          taxExempt: false,
          lineTotal,
        };
      }),
    })),
    validateFiscalCustomer: jest.fn(),
  };
}

function serviceWith(prisma: unknown, inventory: unknown) {
  return new SalesService(
    prisma as never,
    { get: jest.fn().mockReturnValue("") } as never,
    { emitCompany: jest.fn() } as never,
    {
      getCompanyFiscalSettings: jest.fn().mockResolvedValue({
        taxEnabled: true,
        defaultTaxRate: new Prisma.Decimal("0.18"),
        pricesIncludeTax: false,
        ncfEnabled: false,
      }),
      resolvePriceMode: jest.fn().mockReturnValue("TAX_ADDED"),
      calculatorService: taxCalculator(),
    } as never,
    {
      normalizeType: jest.fn(),
      reserveNextNcf: jest.fn(),
      markIssued: jest.fn(),
    } as never,
    inventory as never,
  );
}

function product(overrides: Record<string, unknown> = {}) {
  return {
    id: "product-a",
    nombre: "Producto A",
    imagen: null,
    costo: new Prisma.Decimal("10"),
    stock: new Prisma.Decimal("100"),
    taxTreatment: "TAXABLE",
    taxRate: new Prisma.Decimal("0.18"),
    taxPriceMode: "TAX_ADDED",
    itemType: "PRODUCT",
    trackInventory: true,
    unitOfMeasure: {
      code: "UNIT",
      name: "Unidad",
      symbol: "u",
      precision: 0,
      allowDecimals: false,
    },
    ...overrides,
  };
}

/**
 * Arnes de `SalesService.create` que CUENTA las operaciones de escritura que
 * se ejecutan DENTRO de la transacción, para poder comparar el N+1 real.
 */
function buildCountingHarness(products: ReturnType<typeof product>[]) {
  const txCounters = {
    saleItemCreate: 0,
    saleItemCreateMany: 0,
    saleItemRowsInserted: 0,
  };
  const saleItemCreate = jest.fn(async () => {
    txCounters.saleItemCreate += 1;
    txCounters.saleItemRowsInserted += 1;
    return { id: "never-used" };
  });
  const saleItemCreateMany = jest.fn(async ({ data }: any) => {
    txCounters.saleItemCreateMany += 1;
    txCounters.saleItemRowsInserted += data.length;
    return { count: data.length };
  });

  const tx = {
    terminal: {
      findFirst: jest.fn().mockResolvedValue({
        id: "terminal-1",
        companyId,
        name: "Caja",
        code: "POS",
        deviceFingerprint: null,
        defaultWarehouseId: "warehouse-1",
        defaultWarehouse: {
          id: "warehouse-1",
          companyId,
          name: "Principal",
          code: "MAIN",
          isActive: true,
        },
      }),
    },
    sale: {
      create: jest.fn().mockResolvedValue({
        id: "sale-1",
        cashSessionId: "cash-1",
        saleDate: new Date("2026-09-10T10:00:00.000Z"),
      }),
      findUniqueOrThrow: jest.fn().mockResolvedValue({
        id: "sale-1",
        cashSessionId: "cash-1",
        saleDate: new Date("2026-09-10T10:00:00.000Z"),
        items: [],
      }),
    },
    saleItem: { create: saleItemCreate, createMany: saleItemCreateMany },
  };

  const prisma = {
    cotizacion: { findFirst: jest.fn() },
    sale: { findFirst: jest.fn().mockResolvedValue(null) },
    client: { findFirst: jest.fn() },
    company: {
      findFirst: jest.fn().mockResolvedValue({
        name: "Empresa",
        inventoryEnabled: true,
      }),
    },
    appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
    product: { findMany: jest.fn().mockResolvedValue(products) },
    cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }) },
    $transaction: jest.fn((callback: any) => callback(tx)),
  };

  const inventory = {
    decreaseStockForSaleInTransaction: jest.fn().mockResolvedValue([]),
    decreaseStockInTransaction: jest.fn().mockResolvedValue({}),
  };

  return {
    service: serviceWith(prisma, inventory),
    prisma,
    inventory,
    tx,
    txCounters,
  };
}

describe("SalesService.create — huella de escrituras por venta (N+1)", () => {
  const trackedItems = [
    { productId: "product-a", qty: 1, priceSoldUnit: 100 },
    { productId: "product-b", qty: 2, priceSoldUnit: 50 },
    { productId: "product-c", qty: 3, priceSoldUnit: 10 },
  ];

  it("inserta todas las líneas en UNA sola sentencia (antes: 1 por línea)", async () => {
    const { service, txCounters, tx } = buildCountingHarness([
      product({ id: "product-a" }),
      product({ id: "product-b" }),
      product({ id: "product-c" }),
    ]);

    await service.create(user as never, {
      paymentMethod: "cash",
      paymentCashAmount: 230,
      items: trackedItems,
    });

    expect(txCounters.saleItemCreate).toBe(0);
    expect(txCounters.saleItemCreateMany).toBe(1);
    expect(txCounters.saleItemRowsInserted).toBe(3);
    expect(tx.saleItem.create).not.toHaveBeenCalled();
    expect(tx.saleItem.createMany).toHaveBeenCalledTimes(1);
    expect(tx.saleItem.createMany.mock.calls[0][0].data).toHaveLength(3);
  });

  it("descarga el stock en UNA sola llamada por lote (antes: 1 por línea)", async () => {
    const { service, inventory } = buildCountingHarness([
      product({ id: "product-a" }),
      product({ id: "product-b" }),
      product({ id: "product-c" }),
    ]);

    await service.create(user as never, {
      paymentMethod: "cash",
      paymentCashAmount: 230,
      items: trackedItems,
    });

    expect(inventory.decreaseStockForSaleInTransaction).toHaveBeenCalledTimes(
      1,
    );
    const [, batchInput] =
      inventory.decreaseStockForSaleInTransaction.mock.calls[0];
    expect(batchInput.companyId).toBe(companyId);
    expect(batchInput.warehouseId).toBe("warehouse-1");
    expect(batchInput.saleId).toBe("sale-1");
    expect(
      batchInput.items.map((item: any) => ({
        productId: item.productId,
        quantity: item.quantity.toString(),
        hasSourceItemId: Boolean(item.sourceItemId),
      })),
    ).toEqual([
      { productId: "product-a", quantity: "1", hasSourceItemId: true },
      { productId: "product-b", quantity: "2", hasSourceItemId: true },
      { productId: "product-c", quantity: "3", hasSourceItemId: true },
    ]);
  });

  it("los ids de las líneas insertadas son los que usa el movimiento de inventario", async () => {
    const { service, inventory, tx } = buildCountingHarness([
      product({ id: "product-a" }),
      product({ id: "product-b" }),
    ]);

    await service.create(user as never, {
      paymentMethod: "cash",
      paymentCashAmount: 200,
      items: [
        { productId: "product-a", qty: 1, priceSoldUnit: 100 },
        { productId: "product-b", qty: 2, priceSoldUnit: 50 },
      ],
    });

    const insertedRows = tx.saleItem.createMany.mock.calls[0][0].data;
    const [, batchInput] =
      inventory.decreaseStockForSaleInTransaction.mock.calls[0];

    expect(insertedRows.map((row: any) => row.id).filter(Boolean)).toHaveLength(
      2,
    );
    expect(batchInput.items.map((item: any) => item.sourceItemId)).toEqual(
      insertedRows.map((row: any) => row.id),
    );
  });

  it("no toca inventario cuando ninguna línea es de stock (venta rápida)", async () => {
    const { service, inventory, txCounters } = buildCountingHarness([]);

    await service.create(user as never, {
      paymentMethod: "cash",
      paymentCashAmount: 200,
      items: [
        { productName: "Corte", qty: 1, priceSoldUnit: 200, costUnitSnapshot: 0 },
      ],
    });

    expect(
      inventory.decreaseStockForSaleInTransaction,
    ).not.toHaveBeenCalled();
    expect(txCounters.saleItemCreateMany).toBe(1);
    expect(txCounters.saleItemRowsInserted).toBe(1);
  });
});
