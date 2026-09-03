import { Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

describe("SalesService UoM decimal foundation", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  function taxCalculator() {
    return {
      calculate: jest.fn((input: any) => ({
        total: input.lines.reduce(
          (sum: Prisma.Decimal, line: any) =>
            sum.plus(new Prisma.Decimal(line.quantity).mul(line.unitPrice)),
          new Prisma.Decimal(0),
        ),
        taxableBase: new Prisma.Decimal(0),
        taxAmount: new Prisma.Decimal(0),
        exemptAmount: input.lines.reduce(
          (sum: Prisma.Decimal, line: any) =>
            sum.plus(new Prisma.Decimal(line.quantity).mul(line.unitPrice)),
          new Prisma.Decimal(0),
        ),
        discountAmount: new Prisma.Decimal(0),
        lines: input.lines.map((line: any, index: number) => {
          const lineTotal = new Prisma.Decimal(line.quantity).mul(line.unitPrice);
          return {
            index,
            grossAmount: lineTotal,
            discountAmount: new Prisma.Decimal(0),
            taxableBase: new Prisma.Decimal(0),
            taxRate: new Prisma.Decimal(0),
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

  function serviceWith(
    prisma: Record<string, unknown>,
    inventory: Record<string, unknown> = {},
  ) {
    return new SalesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      { emitCompany: jest.fn() } as never,
      {
        getCompanyFiscalSettings: jest.fn().mockResolvedValue({
          taxEnabled: false,
          defaultTaxRate: new Prisma.Decimal(0),
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

  it("decrements YARD stock exactly and stores unit snapshots", async () => {
    let createdItem: Record<string, unknown> | null = null;
    const saleCreate = jest.fn().mockResolvedValue({
      id: "sale-1",
      cashSessionId: "cash-1",
      saleDate: new Date("2026-08-30T12:00:00.000Z"),
    });
    const saleItemCreate = jest.fn().mockImplementation((args) => {
      createdItem = { id: "item-1", ...args.data };
      return Promise.resolve(createdItem);
    });
    const prisma = {
      product: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: "product-yard",
            nombre: "Tela azul",
            imagen: null,
            costo: new Prisma.Decimal("10"),
            stock: new Prisma.Decimal("20"),
            taxTreatment: "INHERIT",
            taxRate: null,
            taxPriceMode: null,
            unitOfMeasure: {
              code: "YARD",
              name: "Yarda",
              symbol: "yd",
              allowDecimals: true,
              precision: 3,
            },
          },
        ]),
      },
      company: { findFirst: jest.fn().mockResolvedValue({ name: "Empresa" }) },
      appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }),
      },
      $transaction: jest.fn((callback) =>
        callback({
          terminal: {
            findFirst: jest.fn().mockResolvedValue({
              id: "terminal-1",
              companyId: user.companyId,
              name: "Caja Principal",
              code: "MAIN-POS",
              deviceFingerprint: null,
              defaultWarehouseId: "warehouse-1",
              defaultWarehouse: {
                id: "warehouse-1",
                companyId: user.companyId,
                name: "Principal",
                code: "MAIN",
                isActive: true,
              },
            }),
          },
          saleItem: { create: saleItemCreate },
          sale: {
            create: saleCreate,
            findUniqueOrThrow: jest.fn().mockImplementation(() =>
              Promise.resolve({
                id: "sale-1",
                cashSessionId: "cash-1",
                saleDate: new Date("2026-08-30T12:00:00.000Z"),
                items: [createdItem],
              }),
            ),
          },
        }),
      ),
    };
    const inventory = {
      decreaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = serviceWith(prisma, inventory);

    const sale = await service.create(user as never, {
      items: [
        {
          productId: "product-yard",
          qty: 5.5,
          priceSoldUnit: 100,
        },
      ],
    });

    expect(inventory.decreaseStockInTransaction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        warehouseId: "warehouse-1",
        quantity: new Prisma.Decimal("5.5"),
        sourceType: "SALE",
        sourceId: "sale-1",
        sourceItemId: "item-1",
      }),
    );
    expect(sale.items[0].unitCodeSnapshot).toBe("YARD");
    expect(sale.items[0].unitSymbolSnapshot).toBe("yd");
    expect(sale.items[0].unitPrecisionSnapshot).toBe(3);
    expect(sale.items[0].warehouseCodeSnapshot).toBe("MAIN");
  });

  it("keeps external quick sale unit snapshots and validates precision", () => {
    const service = serviceWith({});

    const normalized = (service as any).normalizeItem(
      {
        productName: "Corte de tela",
        qty: 2.375,
        priceSoldUnit: 120,
        costUnitSnapshot: 40,
        unitCodeSnapshot: "YARD",
        unitNameSnapshot: "Yarda",
        unitSymbolSnapshot: "yd",
        unitPrecisionSnapshot: 3,
      },
      0,
      new Map(),
    );

    expect(normalized.unitCodeSnapshot).toBe("YARD");
    expect(normalized.unitNameSnapshot).toBe("Yarda");
    expect(normalized.unitSymbolSnapshot).toBe("yd");
    expect(normalized.unitPrecisionSnapshot).toBe(3);

    expect(() =>
      (service as any).normalizeItem(
        {
          productName: "Corte de tela",
          qty: 2.3751,
          priceSoldUnit: 120,
          costUnitSnapshot: 40,
          unitCodeSnapshot: "YARD",
          unitNameSnapshot: "Yarda",
          unitSymbolSnapshot: "yd",
          unitPrecisionSnapshot: 3,
        },
        0,
        new Map(),
      ),
    ).toThrow("precisión permitida");
  });

  it("restores decimal inventory exactly on partial return using original snapshot", async () => {
    const refundCreate = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: "refund-1",
        cashSessionId: "cash-1",
        saleDate: new Date("2026-08-30T12:05:00.000Z"),
        items: args.data.items.create.map((item: any, index: number) => ({
          id: `refund-item-${index + 1}`,
          ...item,
        })),
      }),
    );
    const originalItem = {
      id: "item-1",
      productId: "product-yard",
      productSource: "LOCAL",
      sourceProductId: "product-yard",
      warehouseId: "warehouse-1",
      warehouseNameSnapshot: "Principal",
      warehouseCodeSnapshot: "MAIN",
      productNameSnapshot: "Tela azul",
      productImageSnapshot: null,
      qty: new Prisma.Decimal("5.5"),
      unitCodeSnapshot: "YARD",
      unitNameSnapshot: "Yarda",
      unitSymbolSnapshot: "yd",
      unitPrecisionSnapshot: 3,
      priceSoldUnit: new Prisma.Decimal("100"),
      grossAmount: new Prisma.Decimal("550"),
      lineDiscountAmount: new Prisma.Decimal("0"),
      taxableBase: new Prisma.Decimal("0"),
      taxRate: new Prisma.Decimal("0"),
      taxAmount: new Prisma.Decimal("0"),
      exemptAmount: new Prisma.Decimal("550"),
      taxIncluded: false,
      taxExempt: true,
      costUnitSnapshot: new Prisma.Decimal("10"),
      subtotalSold: new Prisma.Decimal("550"),
      subtotalCost: new Prisma.Decimal("55"),
      profit: new Prisma.Decimal("495"),
    };
    const prisma = {
      sale: {
        findFirst: jest.fn().mockResolvedValue({
          id: "sale-1",
          companyId: user.companyId,
          isDeleted: false,
          kind: "invoice",
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
          items: [originalItem],
        }),
        create: refundCreate,
      },
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }),
      },
      $transaction: jest.fn((callback) =>
        callback({
          saleItem: {
            groupBy: jest.fn().mockResolvedValue([]),
            findMany: jest.fn().mockResolvedValue([]),
          },
          inventoryMovement: {
            groupBy: jest.fn().mockResolvedValue([]),
          },
          sale: {
            findFirst: jest.fn().mockResolvedValue({
              id: "sale-1",
              companyId: user.companyId,
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
              items: [originalItem],
            }),
            create: refundCreate,
            findUniqueOrThrow: jest.fn().mockImplementation(() =>
              Promise.resolve({
                id: "refund-1",
                cashSessionId: "cash-1",
                saleDate: new Date("2026-08-30T12:05:00.000Z"),
                items: [
                  {
                    id: "refund-item-1",
                    refundedSaleItemId: "item-1",
                    qty: new Prisma.Decimal("1.25"),
                    unitCodeSnapshot: "YARD",
                    warehouseCodeSnapshot: "MAIN",
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

    const refund = await service.returnSale(user as never, "sale-1", {
      items: [{ saleItemId: "item-1", qty: 1.25 }],
    });

    expect(inventory.increaseStockInTransaction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        warehouseId: "warehouse-1",
        quantity: new Prisma.Decimal("1.25"),
        sourceType: "SALE_RETURN",
        sourceId: "refund-1",
        sourceItemId: "refund-item-1",
      }),
    );
    expect(refund.items[0].qty.toString()).toBe("1.25");
    expect(refund.items[0].unitCodeSnapshot).toBe("YARD");
    expect(refund.items[0].warehouseCodeSnapshot).toBe("MAIN");
  });
});
