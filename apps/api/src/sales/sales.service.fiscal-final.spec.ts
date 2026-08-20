import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

describe("SalesService fiscal closure", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
    authorizedPermissions: ["refundSales"],
  };

  it("converts a fiscal quote using stored snapshots and reserves one B01 NCF", async () => {
    const createdSale = {
      id: "sale-a",
      cashSessionId: "cash-a",
      saleDate: new Date(),
    };
    const tx = {
      product: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      sale: { create: jest.fn().mockResolvedValue(createdSale) },
    };
    const prisma = {
      cotizacion: {
        findFirst: jest.fn().mockResolvedValue({
          id: "22222222-2222-4222-8222-222222222222",
          companyId: user.companyId,
          customerId: null,
          fiscalTaxEnabled: true,
          fiscalPriceMode: "TAX_INCLUDED",
          taxableBase: new Prisma.Decimal("21779.66"),
          taxAmount: new Prisma.Decimal("3920.34"),
          exemptAmount: new Prisma.Decimal("0"),
          discountAmount: new Prisma.Decimal("0"),
          total: new Prisma.Decimal("25700"),
          items: [
            {
              id: "item-q",
              productId: "44444444-4444-4444-8444-444444444444",
              productNameSnapshot: "Fulltech CANATECH",
              productImageSnapshot: null,
              qty: new Prisma.Decimal("1"),
              unitPrice: new Prisma.Decimal("25700"),
              costUnitSnapshot: new Prisma.Decimal("18000"),
              subtotalCost: new Prisma.Decimal("18000"),
              taxTreatment: "TAXABLE",
              taxPriceMode: "TAX_INCLUDED",
              grossAmount: new Prisma.Decimal("25700"),
              lineDiscountAmount: new Prisma.Decimal("0"),
              taxableBase: new Prisma.Decimal("21779.66"),
              taxRate: new Prisma.Decimal("0.18"),
              taxAmount: new Prisma.Decimal("3920.34"),
              exemptAmount: new Prisma.Decimal("0"),
              taxIncluded: true,
              taxExempt: false,
              lineTotal: new Prisma.Decimal("25700"),
            },
          ],
        }),
      },
      company: {
        findFirst: jest.fn().mockResolvedValue({ name: "Fallback SRL" }),
      },
      appConfig: {
        findFirst: jest.fn().mockResolvedValue({
          companyName: "FULLTECH, SRL",
          rnc: "133080206",
          address: "Higuey",
          phone: "809-000-0000",
        }),
      },
      sale: { findFirst: jest.fn() },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-a" }) },
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const ncf = {
      normalizeType: jest.fn((type: string) => type.trim().toUpperCase()),
      reserveNextNcf: jest.fn().mockResolvedValue({
        sequenceId: "33333333-3333-4333-8333-333333333333",
        ncf: "B0100000001",
        type: "B01",
      }),
      markIssued: jest.fn(),
    };
    const calculatorService = {
      calculate: jest.fn(),
      validateFiscalCustomer: jest.fn(),
    };
    const service = new SalesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      { emitCompany: jest.fn() } as never,
      {
        getCompanyFiscalSettings: jest.fn().mockResolvedValue({
          taxEnabled: true,
          defaultTaxRate: new Prisma.Decimal("0.18"),
          pricesIncludeTax: true,
          ncfEnabled: true,
        }),
        resolvePriceMode: jest.fn().mockReturnValue("TAX_INCLUDED"),
        calculatorService,
      } as never,
      ncf as never,
    );

    await service.create(user as never, {
      sourceQuotationId: "22222222-2222-4222-8222-222222222222",
      fiscalVoucherType: "B01",
      fiscalCustomerTaxId: "101010101",
      fiscalCustomerName: "FULLTECH SRL",
      expectedTotalSold: 25700,
      items: [
        { productName: "Stale", qty: 1, priceSoldUnit: 1, costUnitSnapshot: 0 },
      ],
    });

    expect(calculatorService.calculate).not.toHaveBeenCalled();
    expect(ncf.reserveNextNcf).toHaveBeenCalledTimes(1);
    expect(ncf.markIssued).toHaveBeenCalledTimes(1);
    expect(tx.sale.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          sourceQuotationId: "22222222-2222-4222-8222-222222222222",
          totalSold: new Prisma.Decimal("25700"),
          taxableBase: new Prisma.Decimal("21779.66"),
          taxAmount: new Prisma.Decimal("3920.34"),
          totalCost: new Prisma.Decimal("18000"),
          totalProfit: new Prisma.Decimal("3779.66"),
          commercialProfit: new Prisma.Decimal("3779.66"),
          netTaxProfit: new Prisma.Decimal("3779.66"),
          ncf: "B0100000001",
          issuerNameSnapshot: "FULLTECH, SRL",
          issuerTaxIdSnapshot: "133080206",
          issuerAddressSnapshot: "Higuey",
          issuerPhoneSnapshot: "809-000-0000",
          items: expect.objectContaining({
            create: [
              expect.objectContaining({
                taxableBase: new Prisma.Decimal("21779.66"),
                taxAmount: new Prisma.Decimal("3920.34"),
                subtotalCost: new Prisma.Decimal("18000"),
                profit: new Prisma.Decimal("3779.66"),
                commercialProfit: new Prisma.Decimal("3779.66"),
                netTaxProfit: new Prisma.Decimal("3779.66"),
              }),
            ],
          }),
        }),
      }),
    );
  });

  it("does not convert the same quotation twice", async () => {
    const existingSale = { id: "sale-existing" };
    const prisma = {
      cotizacion: {
        findFirst: jest.fn().mockResolvedValue({
          id: "22222222-2222-4222-8222-222222222222",
          companyId: user.companyId,
          customerId: null,
          fiscalTaxEnabled: true,
          fiscalPriceMode: "TAX_INCLUDED",
          taxableBase: new Prisma.Decimal("1000"),
          taxAmount: new Prisma.Decimal("180"),
          exemptAmount: new Prisma.Decimal("0"),
          discountAmount: new Prisma.Decimal("0"),
          total: new Prisma.Decimal("1180"),
          items: [],
        }),
      },
      sale: { findFirst: jest.fn().mockResolvedValue(existingSale) },
    };
    const ncf = {
      normalizeType: jest.fn(),
      reserveNextNcf: jest.fn(),
      markIssued: jest.fn(),
    };
    const service = new SalesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      { emitCompany: jest.fn() } as never,
      {} as never,
      ncf as never,
    );

    const result = await service.create(user as never, {
      sourceQuotationId: "22222222-2222-4222-8222-222222222222",
      items: [
        {
          productName: "Ignored",
          qty: 1,
          priceSoldUnit: 1180,
          costUnitSnapshot: 0,
        },
      ],
    });

    expect(result).toBe(existingSale);
    expect(ncf.reserveNextNcf).not.toHaveBeenCalled();
  });

  it("rejects a partial return above the remaining original quantity", async () => {
    const saleItem = {
      id: "item-a",
      productId: "product-a",
      productNameSnapshot: "Producto",
      productImageSnapshot: null,
      qty: new Prisma.Decimal("2"),
      priceSoldUnit: new Prisma.Decimal("1180"),
      grossAmount: new Prisma.Decimal("2360"),
      lineDiscountAmount: new Prisma.Decimal("0"),
      taxableBase: new Prisma.Decimal("2000"),
      taxRate: new Prisma.Decimal("0.18"),
      taxAmount: new Prisma.Decimal("360"),
      exemptAmount: new Prisma.Decimal("0"),
      taxIncluded: true,
      taxExempt: false,
      costUnitSnapshot: new Prisma.Decimal("600"),
      subtotalSold: new Prisma.Decimal("2360"),
      subtotalCost: new Prisma.Decimal("1200"),
      profit: new Prisma.Decimal("1160"),
    };
    const tx = {
      saleItem: {
        groupBy: jest
          .fn()
          .mockResolvedValue([
            {
              refundedSaleItemId: "item-a",
              _sum: { qty: new Prisma.Decimal("1") },
            },
          ]),
      },
    };
    const prisma = {
      sale: {
        findFirst: jest.fn().mockResolvedValue({
          id: "sale-a",
          companyId: user.companyId,
          userId: user.id,
          customerId: null,
          cashSessionId: "cash-a",
          saleDate: new Date(),
          note: null,
          kind: "invoice",
          isDeleted: false,
          fiscalTaxEnabled: true,
          fiscalPriceMode: "TAX_INCLUDED",
          fiscalVoucherType: "B01",
          fiscalCustomerTaxId: "101010101",
          fiscalCustomerName: "FULLTECH SRL",
          items: [saleItem],
        }),
      },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-a" }) },
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const ncf = {
      normalizeType: jest.fn(),
      reserveNextNcf: jest.fn(),
      markIssued: jest.fn(),
    };
    const service = new SalesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      { emitCompany: jest.fn() } as never,
      {} as never,
      ncf as never,
    );

    await expect(
      service.returnSale(user as never, "sale-a", {
        items: [{ saleItemId: "item-a", qty: 2 }],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
