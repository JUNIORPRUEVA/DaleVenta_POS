import { BadRequestException } from "@nestjs/common";
import { InventoryMovementType, Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

const companyId = "11111111-1111-1111-1111-111111111111";
const user = { id: "user-a", role: "ADMIN", companyId };

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
  };
}

function serviceWith(prisma: Record<string, unknown>, inventory: any) {
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

function product(input: {
  id: string;
  itemType?: "PRODUCT" | "SERVICE";
  trackInventory?: boolean;
  stock?: string;
}) {
  return {
    id: input.id,
    nombre: input.id,
    imagen: null,
    costo: new Prisma.Decimal("10"),
    stock: new Prisma.Decimal(input.stock ?? "10"),
    itemType: input.itemType ?? "PRODUCT",
    trackInventory: input.trackInventory ?? true,
    taxTreatment: "TAXABLE",
    taxRate: new Prisma.Decimal("0.18"),
    taxPriceMode: "TAX_ADDED",
    unitOfMeasure: {
      code: input.id.includes("yard") ? "YARD" : "UNIT",
      name: input.id.includes("yard") ? "Yarda" : "Unidad",
      symbol: input.id.includes("yard") ? "yd" : "u",
      allowDecimals: input.id.includes("yard"),
      precision: input.id.includes("yard") ? 3 : 0,
    },
  };
}

function buildCreateHarness(options: {
  inventoryEnabled?: boolean;
  products: ReturnType<typeof product>[];
}) {
  const createdItems: any[] = [];
  const saleCreate = jest.fn().mockResolvedValue({
    id: "sale-1",
    cashSessionId: "cash-1",
    saleDate: new Date("2026-09-04T10:00:00.000Z"),
  });
  const saleItemCreate = jest.fn().mockImplementation((args) => {
    const row = { id: `item-${createdItems.length + 1}`, ...args.data };
    createdItems.push(row);
    return Promise.resolve(row);
  });
  const existingSaleFind = jest.fn().mockResolvedValue(null);
  const txSaleFind = jest.fn().mockImplementation(() =>
    Promise.resolve({
      id: "sale-1",
      cashSessionId: "cash-1",
      saleDate: new Date("2026-09-04T10:00:00.000Z"),
      items: createdItems,
      totalSold: new Prisma.Decimal("100"),
      taxableBase: new Prisma.Decimal("100"),
      taxAmount: new Prisma.Decimal("18"),
      paymentCashAmount: new Prisma.Decimal("118"),
      cashReceived: new Prisma.Decimal("120"),
      changeAmount: new Prisma.Decimal("2"),
    }),
  );
  const prisma = {
    cotizacion: { findFirst: jest.fn() },
    sale: { findFirst: existingSaleFind },
    client: { findFirst: jest.fn() },
    company: {
      findFirst: jest.fn().mockResolvedValue({
        name: "Empresa",
        inventoryEnabled: options.inventoryEnabled ?? true,
      }),
    },
    appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
    product: { findMany: jest.fn().mockResolvedValue(options.products) },
    cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }) },
    $transaction: jest.fn((callback) =>
      callback({
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
          create: saleCreate,
          findUniqueOrThrow: txSaleFind,
        },
        saleItem: { create: saleItemCreate },
      }),
    ),
  };
  const inventory = {
    decreaseStockInTransaction: jest.fn().mockResolvedValue({}),
    increaseStockInTransaction: jest.fn().mockResolvedValue({}),
  };
  return {
    service: serviceWith(prisma, inventory),
    prisma,
    inventory,
    createdItems,
  };
}

describe("SalesService optional inventory tracking", () => {
  it("decrements tracked products and persists snapshot=true", async () => {
    const { service, inventory, createdItems } = buildCreateHarness({
      products: [product({ id: "tracked-product" })],
    });

    const sale = await service.create(user as never, {
      paymentMethod: "cash",
      paymentCashAmount: 100,
      cashReceived: 120,
      changeAmount: 20,
      items: [{ productId: "tracked-product", qty: 2, priceSoldUnit: 50 }],
    });

    expect(createdItems[0].inventoryTrackedSnapshot).toBe(true);
    expect(createdItems[0].warehouseCodeSnapshot).toBe("MAIN");
    expect(inventory.decreaseStockInTransaction).toHaveBeenCalledTimes(1);
    expect(sale.paymentCashAmount.toString()).toBe("118");
    expect(sale.cashReceived.toString()).toBe("120");
    expect(sale.changeAmount.toString()).toBe("2");
  });

  it("allows non-tracked products without stock mutation or warehouse resolution", async () => {
    const { service, inventory, createdItems, prisma } = buildCreateHarness({
      products: [
        product({
          id: "non-tracked-product",
          trackInventory: false,
          stock: "0",
        }),
      ],
    });

    await service.create(user as never, {
      items: [
        {
          productId: "non-tracked-product",
          qty: 9,
          priceSoldUnit: 10,
          inventoryTrackedSnapshot: false,
        },
      ],
    });

    expect(createdItems[0].inventoryTrackedSnapshot).toBe(false);
    expect(createdItems[0].warehouseId).toBeNull();
    expect(inventory.decreaseStockInTransaction).not.toHaveBeenCalled();
    const tx = (prisma.$transaction as jest.Mock).mock.calls[0][0];
    expect(tx).toBeDefined();
  });

  it("allows services and company inventory-off sales without stock mutation", async () => {
    const serviceHarness = buildCreateHarness({
      products: [product({ id: "install-service", itemType: "SERVICE" })],
    });
    await serviceHarness.service.create(user as never, {
      items: [{ productId: "install-service", qty: 1, priceSoldUnit: 100 }],
    });
    expect(serviceHarness.createdItems[0].inventoryTrackedSnapshot).toBe(false);
    expect(
      serviceHarness.inventory.decreaseStockInTransaction,
    ).not.toHaveBeenCalled();

    const offHarness = buildCreateHarness({
      inventoryEnabled: false,
      products: [product({ id: "tracked-while-off", stock: "0" })],
    });
    await offHarness.service.create(user as never, {
      items: [{ productId: "tracked-while-off", qty: 99, priceSoldUnit: 1 }],
    });
    expect(offHarness.createdItems[0].inventoryTrackedSnapshot).toBe(false);
    expect(
      offHarness.inventory.decreaseStockInTransaction,
    ).not.toHaveBeenCalled();
  });

  it("handles mixed sales, UoM decimals, and offline captured config drift", async () => {
    const { service, inventory, createdItems } = buildCreateHarness({
      inventoryEnabled: false,
      products: [
        product({ id: "tracked-yard" }),
        product({ id: "service-unit", itemType: "SERVICE" }),
        product({ id: "product-off", trackInventory: false }),
      ],
    });

    await service.create(user as never, {
      clientRequestId: "offline-mixed-1",
      items: [
        {
          productId: "tracked-yard",
          qty: 2.375,
          priceSoldUnit: 20,
          inventoryTrackedSnapshot: true,
        },
        { productId: "service-unit", qty: 1, priceSoldUnit: 30 },
        {
          productId: "product-off",
          qty: 3,
          priceSoldUnit: 10,
          inventoryTrackedSnapshot: false,
        },
      ],
    });

    expect(createdItems.map((item) => item.inventoryTrackedSnapshot)).toEqual([
      true,
      false,
      false,
    ]);
    expect(inventory.decreaseStockInTransaction).toHaveBeenCalledTimes(1);
    expect(inventory.decreaseStockInTransaction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        productId: "tracked-yard",
        quantity: new Prisma.Decimal("2.375"),
      }),
    );
  });

  it("keeps legacy payload derivation, rejects tracked insufficient stock, and allows untracked", async () => {
    const service = serviceWith({}, {});
    const tracked = (service as any).normalizeItem(
      { productId: "p1", qty: 1, priceSoldUnit: 1 },
      0,
      new Map([["p1", product({ id: "p1", stock: "0" })]]),
      true,
    );
    const untracked = (service as any).normalizeItem(
      {
        productId: "p2",
        qty: 99,
        priceSoldUnit: 1,
        inventoryTrackedSnapshot: false,
      },
      1,
      new Map([["p2", product({ id: "p2", stock: "0" })]]),
      true,
    );

    expect(tracked.inventoryTrackedSnapshot).toBe(true);
    expect(untracked.inventoryTrackedSnapshot).toBe(false);
  });

  it("preserves source semantics for external sale lines", async () => {
    const service = serviceWith({}, {});
    const normalized = (service as any).normalizeItem(
      {
        productName: "FullPOS externo",
        productSource: "FULLPOS",
        sourceProductId: "external-1",
        qty: 1,
        priceSoldUnit: 10,
        costUnitSnapshot: 5,
      },
      0,
      new Map(),
      true,
    );
    expect(normalized.inventoryTrackedSnapshot).toBe(false);
    expect(() =>
      (service as any).assertNoUnsupportedExternalStockMutation([normalized]),
    ).toThrow(BadRequestException);
  });

  it("uses snapshot authority for cancellation and keeps restoration idempotent", async () => {
    const sale = {
      id: "sale-cancel",
      companyId,
      isDeleted: false,
      kind: "invoice",
      items: [
        {
          id: "item-tracked",
          productId: "tracked",
          productSource: "LOCAL",
          warehouseId: "warehouse-1",
          qty: new Prisma.Decimal(2),
          inventoryTrackedSnapshot: true,
        },
        {
          id: "item-untracked",
          productId: "untracked",
          productSource: "LOCAL",
          warehouseId: null,
          qty: new Prisma.Decimal(5),
          inventoryTrackedSnapshot: false,
        },
      ],
    };
    const updateMany = jest
      .fn()
      .mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 0 });
    const prisma = {
      sale: {
        findFirst: jest.fn().mockResolvedValue({
          id: sale.id,
          userId: user.id,
          isDeleted: false,
          kind: "invoice",
          inventoryRestoredAt: null,
        }),
      },
      $transaction: jest.fn((callback) =>
        callback({
          sale: {
            findFirst: jest.fn().mockResolvedValue(sale),
            count: jest.fn().mockResolvedValue(0),
            updateMany,
          },
        }),
      ),
    };
    const inventory = {
      increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = serviceWith(prisma, inventory);

    await (service as any).cancelSaleInventory(user, sale.id);
    await (service as any).cancelSaleInventory(user, sale.id);

    expect(inventory.increaseStockInTransaction).toHaveBeenCalledTimes(1);
    expect(inventory.increaseStockInTransaction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        productId: "tracked",
        warehouseId: "warehouse-1",
        quantity: new Prisma.Decimal(2),
        type: InventoryMovementType.SALE_CANCELLATION,
      }),
    );
  });

  it("uses snapshot authority for refund restoration and financial-only refunds", async () => {
    const trackedOriginal = {
      id: "item-tracked",
      productId: "tracked",
      productSource: "LOCAL",
      sourceProductId: "tracked",
      warehouseId: "warehouse-1",
      warehouseNameSnapshot: "Principal",
      warehouseCodeSnapshot: "MAIN",
      productNameSnapshot: "Tracked",
      productImageSnapshot: null,
      qty: new Prisma.Decimal(4),
      unitCodeSnapshot: "UNIT",
      unitNameSnapshot: "Unidad",
      unitSymbolSnapshot: "u",
      unitPrecisionSnapshot: 0,
      priceSoldUnit: new Prisma.Decimal(10),
      grossAmount: new Prisma.Decimal(40),
      lineDiscountAmount: new Prisma.Decimal(0),
      taxableBase: new Prisma.Decimal(40),
      taxRate: new Prisma.Decimal("0.18"),
      taxAmount: new Prisma.Decimal("7.2"),
      exemptAmount: new Prisma.Decimal(0),
      taxIncluded: false,
      taxExempt: false,
      costUnitSnapshot: new Prisma.Decimal(1),
      subtotalSold: new Prisma.Decimal(40),
      subtotalCost: new Prisma.Decimal(4),
      profit: new Prisma.Decimal(36),
      inventoryTrackedSnapshot: true,
    };
    const untrackedOriginal = {
      ...trackedOriginal,
      id: "item-untracked",
      productId: "untracked",
      productNameSnapshot: "Untracked",
      inventoryTrackedSnapshot: false,
    };
    const refundCreate = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: "refund-1",
        cashSessionId: "cash-1",
        saleDate: new Date("2026-09-04T11:00:00.000Z"),
        items: args.data.items.create.map((item: any, index: number) => ({
          id: `refund-item-${index + 1}`,
          ...item,
        })),
      }),
    );
    const saleFind = {
      id: "sale-refund",
      companyId,
      isDeleted: false,
      kind: "invoice",
      cancelledAt: null,
      inventoryRestoredAt: null,
      customerId: null,
      fiscalTaxEnabled: true,
      fiscalPriceMode: "TAX_ADDED",
      fiscalVoucherType: null,
      issuerNameSnapshot: null,
      issuerTaxIdSnapshot: null,
      issuerAddressSnapshot: null,
      issuerPhoneSnapshot: null,
      issuerEmailSnapshot: null,
      fiscalCustomerTaxId: null,
      fiscalCustomerName: null,
      customerAddressSnapshot: null,
      customerPhoneSnapshot: null,
      items: [trackedOriginal, untrackedOriginal],
    };
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(saleFind) },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }) },
      $transaction: jest.fn((callback) =>
        callback({
          saleItem: {
            groupBy: jest.fn().mockResolvedValue([]),
            findMany: jest.fn().mockResolvedValue([]),
          },
          inventoryMovement: { groupBy: jest.fn().mockResolvedValue([]) },
          sale: {
            findFirst: jest.fn().mockResolvedValue(saleFind),
            create: refundCreate,
            findUniqueOrThrow: jest.fn().mockImplementation(() =>
              Promise.resolve({
                id: "refund-1",
                cashSessionId: "cash-1",
                saleDate: new Date("2026-09-04T11:00:00.000Z"),
                items: [
                  {
                    id: "refund-item-1",
                    refundedSaleItemId: "item-tracked",
                    qty: new Prisma.Decimal(2),
                  },
                  {
                    id: "refund-item-2",
                    refundedSaleItemId: "item-untracked",
                    qty: new Prisma.Decimal(2),
                  },
                ],
              }),
            ),
          },
        }),
      ),
    };
    const inventory = {
      increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = serviceWith(prisma, inventory);

    await service.returnSale(user as never, "sale-refund", {
      items: [
        { saleItemId: "item-tracked", qty: 2 },
        { saleItemId: "item-untracked", qty: 2 },
      ],
      restoreInventory: true,
    });

    expect(inventory.increaseStockInTransaction).toHaveBeenCalledTimes(1);
    expect(inventory.increaseStockInTransaction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        productId: "tracked",
        quantity: new Prisma.Decimal(2),
        sourceType: "SALE_RETURN",
      }),
    );
    expect(refundCreate.mock.calls[0][0].data.items.create).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          refundedSaleItemId: "item-tracked",
          inventoryTrackedSnapshot: true,
        }),
        expect.objectContaining({
          refundedSaleItemId: "item-untracked",
          inventoryTrackedSnapshot: false,
        }),
      ]),
    );
  });

  it("returns existing sale on clientRequestId retry without duplicate movement", async () => {
    const existing = { id: "sale-existing", items: [] };
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(existing) },
    };
    const inventory = { decreaseStockInTransaction: jest.fn() };
    const service = serviceWith(prisma, inventory);

    const result = await service.create(user as never, {
      clientRequestId: "sale-retry-1",
      items: [{ productId: "tracked", qty: 1, priceSoldUnit: 10 }],
    });

    expect(result).toBe(existing);
    expect(inventory.decreaseStockInTransaction).not.toHaveBeenCalled();
  });
});
