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

  function buildB01CreateHarness(
    customer:
      | {
          id: string;
          nombre: string;
          telefono: string;
          taxId: string | null;
          businessName: string | null;
          direccion: string | null;
        }
      | null,
  ) {
    const prisma = {
      cotizacion: { findFirst: jest.fn() },
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
      client: { findFirst: jest.fn().mockResolvedValue(customer) },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-a" }) },
      $transaction: jest.fn(),
    };
    const ncf = {
      normalizeType: jest.fn((type: string) => type.trim().toUpperCase()),
      reserveNextNcf: jest.fn(),
      markIssued: jest.fn(),
    };
    const calculatorService = {
      calculate: jest.fn().mockReturnValue({
        total: new Prisma.Decimal("1180"),
        taxableBase: new Prisma.Decimal("1000"),
        taxAmount: new Prisma.Decimal("180"),
        exemptAmount: new Prisma.Decimal("0"),
        discountAmount: new Prisma.Decimal("0"),
        lines: [
          {
            index: 0,
            grossAmount: new Prisma.Decimal("1180"),
            discountAmount: new Prisma.Decimal("0"),
            taxableBase: new Prisma.Decimal("1000"),
            taxRate: new Prisma.Decimal("0.18"),
            taxAmount: new Prisma.Decimal("180"),
            exemptAmount: new Prisma.Decimal("0"),
            taxIncluded: true,
            taxExempt: false,
            lineTotal: new Prisma.Decimal("1180"),
          },
        ],
      }),
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
    return { prisma, ncf, service };
  }

  const b01Dto = {
    customerId: "55555555-5555-4555-8555-555555555555",
    fiscalVoucherType: "B01",
    expectedTotalSold: 1180,
    items: [
      {
        productName: "Servicio",
        qty: 1,
        priceSoldUnit: 1180,
        costUnitSnapshot: 0,
      },
    ],
  };

  it("converts a fiscal quote using stored snapshots and reserves one B01 NCF", async () => {
    const createdSale = {
      id: "sale-a",
      cashSessionId: "cash-a",
      saleDate: new Date(),
    };
    let createdItem: Record<string, unknown> | null = null;
    const saleItemCreate = jest.fn().mockImplementation((args) => {
      createdItem = { id: "sale-item-a", ...args.data };
      return Promise.resolve(createdItem);
    });
    const tx = {
      terminal: {
        findFirst: jest.fn().mockResolvedValue({
          id: "terminal-a",
          companyId: user.companyId,
          name: "Caja Principal",
          code: "MAIN-POS",
          deviceFingerprint: null,
          defaultWarehouseId: "warehouse-a",
          defaultWarehouse: {
            id: "warehouse-a",
            companyId: user.companyId,
            name: "Principal",
            code: "MAIN",
            isActive: true,
          },
        }),
      },
      saleItem: { create: saleItemCreate },
      client: { update: jest.fn() },
      sale: {
        create: jest.fn().mockResolvedValue(createdSale),
        findUniqueOrThrow: jest.fn().mockImplementation(() =>
          Promise.resolve({
            ...createdSale,
            items: [createdItem],
          }),
        ),
      },
    };
    const prisma = {
      cotizacion: {
        findFirst: jest.fn().mockResolvedValue({
          id: "22222222-2222-4222-8222-222222222222",
          companyId: user.companyId,
          customerId: "55555555-5555-4555-8555-555555555555",
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
      client: {
        findFirst: jest.fn().mockResolvedValue({
          id: "55555555-5555-4555-8555-555555555555",
          nombre: "Fulltech",
          telefono: "809-555-0000",
          taxId: "101010101",
          businessName: "FULLTECH SRL",
          direccion: "Higuey",
        }),
      },
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
      {
        decreaseStockInTransaction: jest.fn().mockResolvedValue({}),
      } as never,
    );

    await service.create(user as never, {
      sourceQuotationId: "22222222-2222-4222-8222-222222222222",
      fiscalVoucherType: "B01",
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
          customerId: "55555555-5555-4555-8555-555555555555",
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
          fiscalCustomerTaxId: "101010101",
          fiscalCustomerName: "Fulltech",
        }),
      }),
    );
    expect(tx.saleItem.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          saleId: "sale-a",
          warehouseId: "warehouse-a",
          warehouseCodeSnapshot: "MAIN",
          taxableBase: new Prisma.Decimal("21779.66"),
          taxAmount: new Prisma.Decimal("3920.34"),
          subtotalCost: new Prisma.Decimal("18000"),
          profit: new Prisma.Decimal("3779.66"),
          commercialProfit: new Prisma.Decimal("3779.66"),
          netTaxProfit: new Prisma.Decimal("3779.66"),
        }),
      }),
    );
  });

  it("rejects B01 without a selected customer before reserving an NCF", async () => {
    const prisma = {
      cotizacion: { findFirst: jest.fn() },
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
      client: { findFirst: jest.fn() },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-a" }) },
      $transaction: jest.fn(),
    };
    const ncf = {
      normalizeType: jest.fn((type: string) => type.trim().toUpperCase()),
      reserveNextNcf: jest.fn(),
      markIssued: jest.fn(),
    };
    const calculatorService = {
      calculate: jest.fn().mockReturnValue({
        total: new Prisma.Decimal("1180"),
        taxableBase: new Prisma.Decimal("1000"),
        taxAmount: new Prisma.Decimal("180"),
        exemptAmount: new Prisma.Decimal("0"),
        discountAmount: new Prisma.Decimal("0"),
        lines: [
          {
            index: 0,
            grossAmount: new Prisma.Decimal("1180"),
            discountAmount: new Prisma.Decimal("0"),
            taxableBase: new Prisma.Decimal("1000"),
            taxRate: new Prisma.Decimal("0.18"),
            taxAmount: new Prisma.Decimal("180"),
            exemptAmount: new Prisma.Decimal("0"),
            taxIncluded: true,
            taxExempt: false,
            lineTotal: new Prisma.Decimal("1180"),
          },
        ],
      }),
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

    await expect(
      service.create(user as never, {
        fiscalVoucherType: "B01",
        fiscalCustomerTaxId: "101010101",
        fiscalCustomerName: "DTO ONLY SRL",
        expectedTotalSold: 1180,
        items: [
          {
            productName: "Servicio",
            qty: 1,
            priceSoldUnit: 1180,
            costUnitSnapshot: 0,
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(ncf.reserveNextNcf).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("rejects B01 when the selected customer belongs to another company before reserving an NCF", async () => {
    const { prisma, ncf, service } = buildB01CreateHarness(null);

    await expect(service.create(user as never, b01Dto)).rejects.toBeInstanceOf(
      BadRequestException,
    );

    expect(prisma.client.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: b01Dto.customerId,
          companyId: user.companyId,
          isDeleted: false,
        }),
      }),
    );
    expect(ncf.reserveNextNcf).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("rejects B01 when the selected customer has no tax id before reserving an NCF", async () => {
    const { prisma, ncf, service } = buildB01CreateHarness({
      id: b01Dto.customerId,
      nombre: "FULLTECH SRL",
      telefono: "809-555-0000",
      taxId: null,
      businessName: "FULLTECH SRL",
      direccion: "Higuey",
    });

    await expect(service.create(user as never, b01Dto)).rejects.toBeInstanceOf(
      BadRequestException,
    );

    expect(ncf.reserveNextNcf).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("rejects B01 when the selected customer has no fiscal name before reserving an NCF", async () => {
    const { prisma, ncf, service } = buildB01CreateHarness({
      id: b01Dto.customerId,
      nombre: "",
      telefono: "809-555-0000",
      taxId: "101010101",
      businessName: null,
      direccion: "Higuey",
    });

    await expect(service.create(user as never, b01Dto)).rejects.toBeInstanceOf(
      BadRequestException,
    );

    expect(ncf.reserveNextNcf).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
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
        findMany: jest.fn().mockResolvedValue([]),
      },
      inventoryMovement: {
        groupBy: jest.fn().mockResolvedValue([]),
      },
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
          cancelledAt: null,
          inventoryRestoredAt: null,
          fiscalTaxEnabled: true,
          fiscalPriceMode: "TAX_INCLUDED",
          fiscalVoucherType: "B01",
          fiscalCustomerTaxId: "101010101",
          fiscalCustomerName: "FULLTECH SRL",
          items: [saleItem],
        }),
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
