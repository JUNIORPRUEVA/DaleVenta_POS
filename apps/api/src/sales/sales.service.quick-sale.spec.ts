import { BadRequestException, NotFoundException } from "@nestjs/common";
import { InventoryMovementType, Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

const companyId = "11111111-1111-1111-1111-111111111111";
const otherCompanyId = "22222222-2222-2222-2222-222222222222";
const user = { id: "user-a", role: "ADMIN", companyId };
const foreignUser = { id: "user-b", role: "ADMIN", companyId: otherCompanyId };

function taxCalculator() {
  return {
    calculate: jest.fn((input: any) => ({
      total: input.lines.reduce(
        (sum: Prisma.Decimal, line: any) =>
          sum.plus(new Prisma.Decimal(line.quantity).mul(line.unitPrice)),
        new Prisma.Decimal(0),
      ),
      taxableBase: new Prisma.Decimal("0"),
      taxAmount: new Prisma.Decimal("0"),
      exemptAmount: new Prisma.Decimal("0"),
      discountAmount: new Prisma.Decimal("0"),
      lines: input.lines.map((line: any, index: number) => {
        const lineTotal = new Prisma.Decimal(line.quantity).mul(line.unitPrice);
        return {
          index,
          grossAmount: lineTotal,
          discountAmount: new Prisma.Decimal(0),
          taxableBase: lineTotal,
          taxRate: new Prisma.Decimal("0"),
          taxAmount: new Prisma.Decimal(0),
          exemptAmount: lineTotal,
          taxIncluded: false,
          taxExempt: true,
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
        taxEnabled: false,
        defaultTaxRate: new Prisma.Decimal("0"),
        pricesIncludeTax: false,
        ncfEnabled: false,
      }),
      resolvePriceMode: jest.fn().mockReturnValue("NO_TAX"),
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

/** Item fuera de inventario (venta rapida): sin productId persistente. */
function quickSaleItem(overrides: Record<string, unknown> = {}) {
  return {
    id: "item-quick",
    productId: null,
    productSource: null,
    sourceProductId: null,
    warehouseId: null,
    warehouseNameSnapshot: null,
    warehouseCodeSnapshot: null,
    productNameSnapshot: "prueva",
    productImageSnapshot: null,
    qty: new Prisma.Decimal(1),
    unitCodeSnapshot: "UNIT",
    unitNameSnapshot: "Unidad",
    unitSymbolSnapshot: "u",
    unitPrecisionSnapshot: 0,
    priceSoldUnit: new Prisma.Decimal(200),
    grossAmount: new Prisma.Decimal(200),
    lineDiscountAmount: new Prisma.Decimal(0),
    taxableBase: new Prisma.Decimal(0),
    taxRate: new Prisma.Decimal(0),
    taxAmount: new Prisma.Decimal(0),
    exemptAmount: new Prisma.Decimal(200),
    taxIncluded: false,
    taxExempt: true,
    costUnitSnapshot: new Prisma.Decimal(0),
    subtotalSold: new Prisma.Decimal(200),
    subtotalCost: new Prisma.Decimal(0),
    profit: new Prisma.Decimal(200),
    inventoryTrackedSnapshot: false,
    ...overrides,
  };
}

/** Item de producto real persistente con trackInventory=false. */
function untrackedProductItem(overrides: Record<string, unknown> = {}) {
  return quickSaleItem({
    id: "item-untracked",
    productId: "untracked-product",
    productSource: "LOCAL",
    sourceProductId: "untracked-product",
    productNameSnapshot: "Producto sin inventario",
    ...overrides,
  });
}

function quickSale(overrides: Record<string, unknown> = {}) {
  return {
    id: "sale-quick",
    companyId,
    userId: user.id,
    isDeleted: false,
    kind: "invoice",
    cancelledAt: null,
    inventoryRestoredAt: null,
    customerId: null,
    fiscalTaxEnabled: false,
    fiscalPriceMode: "NO_TAX",
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
    paymentMethod: "cash",
    totalSold: new Prisma.Decimal(200),
    paymentCashAmount: new Prisma.Decimal(200),
    paymentTransferAmount: new Prisma.Decimal(0),
    creditAmount: new Prisma.Decimal(0),
    creditPaidAmount: new Prisma.Decimal(0),
    creditBalance: new Prisma.Decimal(0),
    creditPayments: [],
    items: [quickSaleItem()],
    ...overrides,
  };
}

function emptyReturnMaps() {
  return {
    saleItem: {
      groupBy: jest.fn().mockResolvedValue([]),
      findMany: jest.fn().mockResolvedValue([]),
    },
    inventoryMovement: { groupBy: jest.fn().mockResolvedValue([]) },
  };
}

function buildCancelHarness(sale: ReturnType<typeof quickSale>) {
  const updateMany = jest
    .fn()
    .mockResolvedValueOnce({ count: 1 })
    .mockResolvedValueOnce({ count: 0 });
  const prisma = {
    sale: {
      findFirst: jest.fn().mockResolvedValue({
        id: sale.id,
        userId: sale.userId,
        isDeleted: false,
        kind: sale.kind,
        inventoryRestoredAt: null,
      }),
    },
    $transaction: jest.fn((callback: any) =>
      callback({
        sale: { findFirst: jest.fn().mockResolvedValue(sale), updateMany },
        ...emptyReturnMaps(),
      }),
    ),
  };
  const inventory = {
    increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    decreaseStockForSaleInTransaction: jest.fn().mockResolvedValue([]),
    decreaseStockInTransaction: jest.fn().mockResolvedValue({}),
  };
  return { service: serviceWith(prisma, inventory), prisma, inventory, updateMany };
}

function buildReturnHarness(
  sale: ReturnType<typeof quickSale>,
  options: { existingRefund?: unknown } = {},
) {
  const refundCreate = jest.fn().mockImplementation((args: any) =>
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
  const saleUpdate = jest.fn().mockResolvedValue({});
  const prisma = {
    sale: {
      findFirst: jest
        .fn()
        .mockResolvedValueOnce(options.existingRefund ?? null)
        .mockResolvedValue(null),
    },
    cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }) },
    client: { findFirst: jest.fn() },
    company: {
      findFirst: jest
        .fn()
        .mockResolvedValue({ name: "Empresa", inventoryEnabled: true }),
    },
    appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
    product: { findMany: jest.fn().mockResolvedValue([]) },
    cotizacion: { findFirst: jest.fn() },
    $transaction: jest.fn((callback: any) =>
      callback({
        $executeRawUnsafe: jest.fn().mockResolvedValue(undefined),
        sale: {
          findFirst: jest.fn().mockResolvedValue(sale),
          create: refundCreate,
          update: saleUpdate,
          findUniqueOrThrow: jest.fn().mockImplementation(async () => ({
            _refund: await refundCreate.mock.results[0].value,
          })),
        },
        ...emptyReturnMaps(),
      }),
    ),
  };
  const inventory = {
    increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    decreaseStockForSaleInTransaction: jest.fn().mockResolvedValue([]),
    decreaseStockInTransaction: jest.fn().mockResolvedValue({}),
  };
  return {
    service: serviceWith(prisma, inventory),
    prisma,
    inventory,
    refundCreate,
    saleUpdate,
  };
}

describe("SalesService quick sale (sin inventario) cancel/return", () => {
  it("creates an out-of-inventory sale without stock mutation or warehouse", async () => {
    const createdItems: any[] = [];
    const saleItemCreateMany = jest.fn().mockImplementation((args: any) => {
      const rows = (args.data as any[]).map((row) => ({ ...row }));
      createdItems.push(...rows);
      return Promise.resolve({ count: rows.length });
    });
    const prisma = {
      cotizacion: { findFirst: jest.fn() },
      sale: { findFirst: jest.fn().mockResolvedValue(null) },
      client: { findFirst: jest.fn() },
      company: {
        findFirst: jest
          .fn()
          .mockResolvedValue({ name: "Empresa", inventoryEnabled: true }),
      },
      appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }) },
      $transaction: jest.fn((callback: any) =>
        callback({
          sale: {
            create: jest.fn().mockResolvedValue({
              id: "sale-1",
              cashSessionId: "cash-1",
              saleDate: new Date("2026-09-04T10:00:00.000Z"),
            }),
            findUniqueOrThrow: jest.fn().mockImplementation(() =>
              Promise.resolve({
                id: "sale-1",
                cashSessionId: "cash-1",
                saleDate: new Date("2026-09-04T10:00:00.000Z"),
                items: createdItems,
                totalSold: new Prisma.Decimal(200),
                paymentCashAmount: new Prisma.Decimal(200),
                cashReceived: new Prisma.Decimal(200),
                changeAmount: new Prisma.Decimal(0),
              }),
            ),
          },
          saleItem: { createMany: saleItemCreateMany },
        }),
      ),
    };
    const inventory = {
      decreaseStockForSaleInTransaction: jest.fn().mockResolvedValue([]),
      increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = serviceWith(prisma, inventory);

    await service.create(user as never, {
      warehouseId: undefined,
      items: [
        {
          productName: "prueva",
          qty: 1,
          priceSoldUnit: 200,
          costUnitSnapshot: 0,
        },
      ],
    } as never);

    expect(
      inventory.decreaseStockForSaleInTransaction,
    ).not.toHaveBeenCalled();
    expect(saleItemCreateMany).toHaveBeenCalledTimes(1);
    expect(saleItemCreateMany.mock.calls[0][0].data[0]).toEqual(
      expect.objectContaining({
        productId: null,
        warehouseId: null,
        inventoryTrackedSnapshot: false,
      }),
    );
  });

  it("cancels a quick sale with no stock movement", async () => {
    const { service, inventory, updateMany } = buildCancelHarness(quickSale());

    await service.remove(user as never, "sale-quick");

    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
    expect(updateMany.mock.calls[0][0].data).toEqual(
      expect.objectContaining({
        inventoryRestoredAt: expect.any(Date),
        cancelledAt: expect.any(Date),
      }),
    );
  });

  it("cancels a trackInventory=false product sale with no stock movement", async () => {
    const sale = quickSale({
      id: "sale-untracked",
      items: [untrackedProductItem()],
    });
    const { service, inventory } = buildCancelHarness(sale);

    await service.remove(user as never, "sale-untracked");

    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
  });

  it("keeps cancellation idempotent and never restores twice", async () => {
    const { service, inventory } = buildCancelHarness(quickSale());

    await service.remove(user as never, "sale-quick");
    await service.remove(user as never, "sale-quick");

    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
  });

  it("returns a full quick sale without stock movement and reverses cash once", async () => {
    const { service, inventory, refundCreate } = buildReturnHarness(quickSale());

    await service.returnSale(user as never, "sale-quick", {} as never);

    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
    expect(refundCreate).toHaveBeenCalledTimes(1);
    const data = refundCreate.mock.calls[0][0].data;
    expect(data).toEqual(
      expect.objectContaining({
        kind: "refund",
        refundedSaleId: "sale-quick",
        paymentCashAmount: new Prisma.Decimal(-200),
      }),
    );
    expect(
      new Prisma.Decimal(data.paymentTransferAmount).isZero(),
    ).toBe(true);
    expect(data.items.create[0]).toEqual(
      expect.objectContaining({
        productId: null,
        refundedSaleItemId: "item-quick",
        inventoryTrackedSnapshot: false,
      }),
    );
  });

  it("returns part of a quick sale and keeps commercial quantities", async () => {
    const sale = quickSale({
      id: "sale-quick-3",
      totalSold: new Prisma.Decimal(600),
      paymentCashAmount: new Prisma.Decimal(600),
      items: [
        quickSaleItem({
          qty: new Prisma.Decimal(3),
          subtotalSold: new Prisma.Decimal(600),
          grossAmount: new Prisma.Decimal(600),
          exemptAmount: new Prisma.Decimal(600),
        }),
      ],
    });
    const { service, inventory, refundCreate } = buildReturnHarness(sale);

    await service.returnSale(user as never, "sale-quick-3", {
      items: [{ saleItemId: "item-quick", qty: 1 }],
    } as never);

    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
    const data = refundCreate.mock.calls[0][0].data;
    expect(new Prisma.Decimal(data.totalSold).toString()).toBe("-200");
    expect(new Prisma.Decimal(data.paymentCashAmount).toString()).toBe("-200");
    expect(new Prisma.Decimal(data.items.create[0].qty).toString()).toBe("1");
  });

  it("summarizes a partially returned quick sale", () => {
    const sale = {
      id: "sale-quick-3",
      isDeleted: false,
      cancelledAt: null,
      status: "PAID",
      kind: "invoice",
      totalSold: new Prisma.Decimal(600),
      items: [
        {
          id: "item-quick",
          qty: new Prisma.Decimal(3),
          subtotalSold: new Prisma.Decimal(600),
        },
      ],
      refunds: [
        {
          totalSold: new Prisma.Decimal(-200),
          items: [{ refundedSaleItemId: "item-quick", qty: new Prisma.Decimal(1) }],
        },
      ],
    };
    const service = serviceWith({}, {});

    const summary = (service as any).withReturnSummary(sale);

    expect(summary).toEqual(
      expect.objectContaining({
        returnStatus: "PARTIALLY_RETURNED",
        canReturn: true,
      }),
    );
    expect(new Prisma.Decimal(summary.returnedAmount).toString()).toBe("200");
    expect(new Prisma.Decimal(summary.returnableAmount).toString()).toBe("400");
  });

  it("cancels only the remaining amount after a partial quick return", async () => {
    const sale = quickSale({
      id: "sale-quick-partial",
      totalSold: new Prisma.Decimal(600),
      paymentCashAmount: new Prisma.Decimal(600),
      items: [
        quickSaleItem({
          qty: new Prisma.Decimal(3),
          subtotalSold: new Prisma.Decimal(600),
          grossAmount: new Prisma.Decimal(600),
          exemptAmount: new Prisma.Decimal(600),
        }),
      ],
    });
    const updateMany = jest.fn().mockResolvedValueOnce({ count: 1 });
    const prisma = {
      sale: {
        findFirst: jest.fn().mockResolvedValue({
          id: sale.id,
          userId: sale.userId,
          isDeleted: false,
          kind: "invoice",
          inventoryRestoredAt: null,
        }),
      },
      $transaction: jest.fn((callback: any) =>
        callback({
          sale: { findFirst: jest.fn().mockResolvedValue(sale), updateMany },
          saleItem: {
            groupBy: jest.fn().mockResolvedValue([
              {
                refundedSaleItemId: "item-quick",
                _sum: { qty: new Prisma.Decimal(1) },
              },
            ]),
            findMany: jest
              .fn()
              .mockResolvedValue([
                { id: "refund-item-1", refundedSaleItemId: "item-quick" },
              ]),
          },
          inventoryMovement: { groupBy: jest.fn().mockResolvedValue([]) },
        }),
      ),
    };
    const inventory = {
      increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = serviceWith(prisma, inventory);

    await service.remove(user as never, "sale-quick-partial");

    // No double reversal: cancellation of an out-of-inventory sale never touches stock.
    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
    expect(updateMany).toHaveBeenCalledTimes(1);
  });

  it("rejects cancelling a fully returned quick sale", async () => {
    const sale = quickSale({
      id: "sale-quick-returned",
      totalSold: new Prisma.Decimal(200),
      paymentCashAmount: new Prisma.Decimal(200),
    });
    const prisma = {
      sale: {
        findFirst: jest.fn().mockResolvedValue({
          id: sale.id,
          userId: sale.userId,
          isDeleted: false,
          kind: "invoice",
          inventoryRestoredAt: null,
        }),
      },
      $transaction: jest.fn((callback: any) =>
        callback({
          sale: { findFirst: jest.fn().mockResolvedValue(sale) },
          saleItem: {
            groupBy: jest.fn().mockResolvedValue([
              {
                refundedSaleItemId: "item-quick",
                _sum: { qty: new Prisma.Decimal(1) },
              },
            ]),
            findMany: jest
              .fn()
              .mockResolvedValue([
                { id: "refund-item-1", refundedSaleItemId: "item-quick" },
              ]),
          },
          inventoryMovement: { groupBy: jest.fn().mockResolvedValue([]) },
        }),
      ),
    };
    const service = serviceWith(prisma, {});

    await expect(service.remove(user as never, "sale-quick-returned")).rejects.toThrow(
      BadRequestException,
    );
    await expect(
      service.remove(user as never, "sale-quick-returned"),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "SALE_ALREADY_FULLY_RETURNED" }),
    });
  });

  it("reuses the same refund on a repeated clientRequestId", async () => {
    const existingRefund = { id: "refund-existing", kind: "refund", items: [] };
    const { service, prisma, refundCreate } = buildReturnHarness(quickSale(), {
      existingRefund,
    });
    prisma.sale.findFirst = jest.fn().mockResolvedValue(existingRefund);

    const result = await service.returnSale(user as never, "sale-quick", {
      clientRequestId: "return-retry-1",
    } as never);

    expect(result).toBe(existingRefund);
    expect(refundCreate).not.toHaveBeenCalled();
  });

  it("reverses transfer-only quick sales through transfer, not cash", async () => {
    const sale = quickSale({
      id: "sale-quick-transfer",
      paymentMethod: "transfer",
      paymentCashAmount: new Prisma.Decimal(0),
      paymentTransferAmount: new Prisma.Decimal(200),
    });
    const { service, refundCreate } = buildReturnHarness(sale);

    await service.returnSale(user as never, "sale-quick-transfer", {} as never);

    const data = refundCreate.mock.calls[0][0].data;
    expect(new Prisma.Decimal(data.paymentCashAmount).toString()).toBe("0");
    expect(new Prisma.Decimal(data.paymentTransferAmount).toString()).toBe(
      "-200",
    );
  });

  it("reverses mixed quick sales proportionally", async () => {
    const sale = quickSale({
      id: "sale-quick-mixed",
      paymentMethod: "mixed",
      paymentCashAmount: new Prisma.Decimal(120),
      paymentTransferAmount: new Prisma.Decimal(80),
    });
    const { service, refundCreate } = buildReturnHarness(sale);

    await service.returnSale(user as never, "sale-quick-mixed", {
      items: [{ saleItemId: "item-quick", qty: 1 }],
    } as never);

    const data = refundCreate.mock.calls[0][0].data;
    expect(new Prisma.Decimal(data.paymentCashAmount).toString()).toBe("-120");
    expect(new Prisma.Decimal(data.paymentTransferAmount).toString()).toBe(
      "-80",
    );
  });

  it("reduces a quick credit sale receivable without fictitious cash-out", async () => {
    const sale = quickSale({
      id: "sale-quick-credit",
      paymentMethod: "credit",
      status: "CREDIT",
      paymentCashAmount: new Prisma.Decimal(0),
      paymentTransferAmount: new Prisma.Decimal(0),
      creditAmount: new Prisma.Decimal(200),
      creditPaidAmount: new Prisma.Decimal(0),
      creditBalance: new Prisma.Decimal(200),
      creditPayments: [],
    });
    const { service, refundCreate, saleUpdate } = buildReturnHarness(sale);

    await service.returnSale(user as never, "sale-quick-credit", {} as never);

    const data = refundCreate.mock.calls[0][0].data;
    // No fictitious cash-out: the receivable is reduced instead of going negative.
    expect(new Prisma.Decimal(data.paymentCashAmount).isZero()).toBe(true);
    expect(new Prisma.Decimal(data.paymentTransferAmount).isZero()).toBe(true);
    expect(new Prisma.Decimal(data.creditAmount).isZero()).toBe(true);
    expect(new Prisma.Decimal(data.creditBalance).isZero()).toBe(true);

    // The original sale receivable is cleared, never made negative.
    expect(saleUpdate).toHaveBeenCalledTimes(1);
    const originalUpdate = saleUpdate.mock.calls[0][0].data;
    expect(new Prisma.Decimal(originalUpdate.creditAmount).isZero()).toBe(true);
    expect(new Prisma.Decimal(originalUpdate.creditBalance).isZero()).toBe(true);
    expect(originalUpdate.status).toBe("PAID");
  });

  it("keeps tenant isolation when cancelling another company sale", async () => {
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(null) },
      $transaction: jest.fn(),
    };
    const service = serviceWith(prisma, {});

    await expect(
      service.remove(foreignUser as never, "sale-quick"),
    ).rejects.toThrow(NotFoundException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("keeps tenant isolation when returning another company sale", async () => {
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(null) },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }) },
      $transaction: jest.fn((callback: any) =>
        callback({
          $executeRawUnsafe: jest.fn().mockResolvedValue(undefined),
          sale: { findFirst: jest.fn().mockResolvedValue(null) },
          ...emptyReturnMaps(),
        }),
      ),
    };
    const inventory = {
      increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = serviceWith(prisma, inventory);

    await expect(
      service.returnSale(foreignUser as never, "sale-quick", {} as never),
    ).rejects.toThrow(NotFoundException);
    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
  });

  it("does not create artificial stock movements for untracked products", async () => {
    const sale = quickSale({
      id: "sale-untracked-return",
      items: [untrackedProductItem()],
    });
    const { service, inventory } = buildReturnHarness(sale);

    await service.returnSale(user as never, "sale-untracked-return", {} as never);

    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
    expect(
      inventory.decreaseStockForSaleInTransaction,
    ).not.toHaveBeenCalled();
  });

  it("restores stock exactly once for a tracked quick-sale line", async () => {
    const trackedItem = quickSaleItem({
      id: "item-tracked-quick",
      productId: "tracked-product",
      productSource: "LOCAL",
      sourceProductId: "tracked-product",
      warehouseId: "warehouse-1",
      inventoryTrackedSnapshot: true,
      qty: new Prisma.Decimal(2),
      subtotalSold: new Prisma.Decimal(400),
      grossAmount: new Prisma.Decimal(400),
      exemptAmount: new Prisma.Decimal(400),
    });
    const sale = quickSale({
      id: "sale-tracked-quick",
      totalSold: new Prisma.Decimal(400),
      paymentCashAmount: new Prisma.Decimal(400),
      items: [trackedItem],
    });
    const { service, inventory } = buildReturnHarness(sale);

    await service.returnSale(user as never, "sale-tracked-quick", {
      items: [{ saleItemId: "item-tracked-quick", qty: 1 }],
    } as never);

    expect(inventory.increaseStockInTransaction).toHaveBeenCalledTimes(1);
    expect(inventory.increaseStockInTransaction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        productId: "tracked-product",
        warehouseId: "warehouse-1",
        quantity: new Prisma.Decimal(1),
        type: InventoryMovementType.RETURN,
      }),
    );
  });
});
