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

  function serviceWith(prisma: Record<string, unknown>) {
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
    );
  }

  it("decrements YARD stock exactly and stores unit snapshots", async () => {
    const updateMany = jest.fn().mockResolvedValue({ count: 1 });
    const saleCreate = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: "sale-1",
        cashSessionId: "cash-1",
        saleDate: new Date("2026-08-30T12:00:00.000Z"),
        items: args.data.items.create,
      }),
    );
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
        updateMany,
      },
      company: { findFirst: jest.fn().mockResolvedValue({ name: "Empresa" }) },
      appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({ id: "cash-1" }),
      },
      $transaction: jest.fn((callback) =>
        callback({
          product: { updateMany },
          sale: { create: saleCreate },
        }),
      ),
    };
    const service = serviceWith(prisma);

    const sale = await service.create(user as never, {
      items: [
        {
          productId: "product-yard",
          qty: 5.5,
          priceSoldUnit: 100,
        },
      ],
    });

    const decrementedBy = updateMany.mock.calls[0][0].data.stock.decrement;
    expect(decrementedBy.toString()).toBe("5.5");
    expect(sale.items[0].unitCodeSnapshot).toBe("YARD");
    expect(sale.items[0].unitSymbolSnapshot).toBe("yd");
    expect(sale.items[0].unitPrecisionSnapshot).toBe(3);
  });

  it("restores decimal inventory exactly on partial return using original snapshot", async () => {
    const increment = jest.fn().mockResolvedValue({ count: 1 });
    const refundCreate = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: "refund-1",
        cashSessionId: "cash-1",
        saleDate: new Date("2026-08-30T12:05:00.000Z"),
        items: args.data.items.create,
      }),
    );
    const originalItem = {
      id: "item-1",
      productId: "product-yard",
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
          },
          product: {
            updateMany: increment,
          },
          sale: {
            create: refundCreate,
          },
        }),
      ),
    };
    const service = serviceWith(prisma);

    const refund = await service.returnSale(user as never, "sale-1", {
      items: [{ saleItemId: "item-1", qty: 1.25 }],
    });

    const incrementedBy = increment.mock.calls[0][0].data.stock.increment;
    expect(incrementedBy.toString()).toBe("1.25");
    expect(refund.items[0].qty.toString()).toBe("1.25");
    expect(refund.items[0].unitCodeSnapshot).toBe("YARD");
  });
});
