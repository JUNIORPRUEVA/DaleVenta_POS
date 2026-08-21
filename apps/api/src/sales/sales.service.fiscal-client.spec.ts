import { Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

describe("SalesService fiscal client persistence (B01)", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  const taxCalculation = {
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
  };

  function buildHarness(options: {
    findClient?: (query: unknown) => Promise<unknown | null>;
    fiscalVoucherType?: string;
    fiscalCustomerTaxId?: string | null;
    fiscalCustomerName?: string | null;
  }) {
    const tx = {
      product: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      sale: {
        create: jest.fn().mockResolvedValue({
          id: "sale-a",
          cashSessionId: "cash-a",
          saleDate: new Date(),
        }),
      },
      client: {
        findFirst: jest.fn((query) =>
          options.findClient ? options.findClient(query) : Promise.resolve(null),
        ),
        update: jest.fn(),
        create: jest.fn(),
      },
    };
    const prisma = {
      cotizacion: { findFirst: jest.fn().mockResolvedValue(null) },
      client: { findFirst: jest.fn().mockResolvedValue(null) },
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
      product: { findMany: jest.fn().mockResolvedValue([]) },
      sale: { findFirst: jest.fn() },
      cashSession: { findFirst: jest.fn().mockResolvedValue({ id: "cash-a" }) },
      $transaction: jest.fn((callback: (t: typeof tx) => unknown) =>
        callback(tx),
      ),
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
      calculate: jest.fn().mockReturnValue(taxCalculation),
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

    return { service, tx, ncf };
  }

  const saleItems = [
    { productName: "Servicio", qty: 1, priceSoldUnit: 1000, costUnitSnapshot: 0 },
  ];

  it("creates a reusable fiscal client (normalized RNC) when a B01 sale is emitted", async () => {
    const { service, tx, ncf } = buildHarness({});

    await service.create(user as never, {
      fiscalVoucherType: "B01",
      fiscalCustomerTaxId: "1-33-02025-3",
      fiscalCustomerName: "potatoes.dres, srl",
      expectedTotalSold: 1180,
      items: saleItems,
    });

    // The client is persisted with the NORMALIZED document and the name.
    expect(tx.client.create).toHaveBeenCalledTimes(1);
    expect(tx.client.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          nombre: "potatoes.dres, srl",
          businessName: "potatoes.dres, srl",
          taxId: "133020253",
          taxIdType: "RNC",
          companyId: user.companyId,
        }),
      }),
    );
    // Emitting the sale consumes exactly ONE NCF.
    expect(ncf.reserveNextNcf).toHaveBeenCalledTimes(1);
    expect(ncf.markIssued).toHaveBeenCalledTimes(1);
  });

  it("reuses an existing client by RNC without creating a duplicate", async () => {
    const { service, tx, ncf } = buildHarness({
      findClient: () =>
        Promise.resolve({
          id: "client-a",
          nombre: "Potatoe",
          businessName: null,
          taxId: "133020253",
        }),
    });

    await service.create(user as never, {
      fiscalVoucherType: "B01",
      fiscalCustomerTaxId: "133020253",
      fiscalCustomerName: "potatoes.dres, srl",
      expectedTotalSold: 1180,
      items: saleItems,
    });

    expect(tx.client.create).not.toHaveBeenCalled();
    // Fills the missing businessName on the existing client.
    expect(tx.client.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "client-a" },
        data: expect.objectContaining({ businessName: "potatoes.dres, srl" }),
      }),
    );
    expect(ncf.reserveNextNcf).toHaveBeenCalledTimes(1);
  });

  it("does not create a client nor consume NCF for a non-fiscal sale", async () => {
    const { service, tx, ncf } = buildHarness({});

    await service.create(user as never, {
      expectedTotalSold: 1180,
      items: saleItems,
    });

    expect(tx.client.create).not.toHaveBeenCalled();
    expect(ncf.reserveNextNcf).not.toHaveBeenCalled();
    expect(ncf.markIssued).not.toHaveBeenCalled();
  });

  it("does not create a client when the fiscal name is missing (snapshot only)", async () => {
    const { service, tx } = buildHarness({});

    await service.create(user as never, {
      fiscalVoucherType: "B01",
      fiscalCustomerTaxId: "133020253",
      fiscalCustomerName: "",
      expectedTotalSold: 1180,
      items: saleItems,
    });

    expect(tx.client.create).not.toHaveBeenCalled();
  });
});
