import { Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

describe("SalesService fiscal print data (cashier + NCF expiration)", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };
  const validUntil = new Date("2026-12-31T00:00:00.000Z");

  function build() {
    const createdSale = {
      id: "sale-a",
      cashSessionId: "cash-a",
      saleDate: new Date(),
      userId: user.id,
    };
    let createdItem: Record<string, unknown> | null = null;
    const saleItemCreate = jest.fn().mockImplementation((args) => {
      createdItem = { id: "sale-item-a", ...args.data };
      return Promise.resolve(createdItem);
    });
    const tx = {
      client: { update: jest.fn() },
      saleItem: { create: saleItemCreate },
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
      appConfig: {
        findFirst: jest.fn().mockResolvedValue({
          companyName: "FULLTECH, SRL",
          rnc: "133080206",
          address: "Higuey",
          phone: "809-000-0000",
        }),
      },
      company: { findFirst: jest.fn().mockResolvedValue({ name: "FALLBACK" }) },
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
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({ id: "cash-a" }),
      },
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const ncf = {
      normalizeType: jest.fn((type: string) => type.trim().toUpperCase()),
      reserveNextNcf: jest.fn().mockResolvedValue({
        sequenceId: "33333333-3333-4333-8333-333333333333",
        ncf: "B0100000003",
        type: "B01",
        validUntil,
      }),
      markIssued: jest.fn(),
    };
    const calculatorService = {
      calculate: jest.fn().mockReturnValue({
        total: new Prisma.Decimal("100"),
        taxableBase: new Prisma.Decimal("0"),
        taxAmount: new Prisma.Decimal("0"),
        exemptAmount: new Prisma.Decimal("100"),
        discountAmount: new Prisma.Decimal("0"),
        lines: [
          {
            lineTotal: new Prisma.Decimal("100"),
            grossAmount: new Prisma.Decimal("100"),
            discountAmount: new Prisma.Decimal("0"),
            taxableBase: new Prisma.Decimal("0"),
            taxRate: new Prisma.Decimal("0"),
            taxAmount: new Prisma.Decimal("0"),
            exemptAmount: new Prisma.Decimal("100"),
            taxIncluded: false,
            taxExempt: true,
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
          taxEnabled: false,
          defaultTaxRate: new Prisma.Decimal("0"),
          pricesIncludeTax: false,
          ncfEnabled: true,
        }),
        resolvePriceMode: jest.fn().mockReturnValue("NO_TAX"),
        calculatorService,
      } as never,
      ncf as never,
    );
    return { prisma, tx, ncf, service };
  }

  it("persists the NCF expiration snapshot and includes the user in the response", async () => {
    const { tx, ncf, service } = build();

    const result = await service.create(user as never, {
      customerId: "55555555-5555-4555-8555-555555555555",
      fiscalVoucherType: "B01",
      items: [
        {
          productName: "Servicio",
          qty: 1,
          priceSoldUnit: 100,
          costUnitSnapshot: 50,
        },
      ],
    });

    expect(ncf.reserveNextNcf).toHaveBeenCalledTimes(1);
    expect(ncf.markIssued).toHaveBeenCalledTimes(1);

    // Snapshot del vencimiento NCF en la venta (fuente única para
    // impresión inmediata / reimpresión / PDF / historial).
    expect(tx.sale.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          ncf: "B0100000003",
          ncfExpirationDate: validUntil,
        }),
      }),
    );
    expect(tx.sale.findUniqueOrThrow).toHaveBeenCalledWith(
      expect.objectContaining({
        include: expect.objectContaining({
          user: expect.objectContaining({
            select: expect.objectContaining({
              nombreCompleto: true,
            }),
          }),
        }),
      }),
    );

    expect(result.id).toBe("sale-a");
  });

  it("does not set ncfExpirationDate when no NCF is reserved", async () => {
    const { tx, ncf, service } = build();
    ncf.reserveNextNcf.mockResolvedValue(null);

    await service.create(user as never, {
      items: [
        {
          productName: "Servicio",
          qty: 1,
          priceSoldUnit: 100,
          costUnitSnapshot: 50,
        },
      ],
    });

    expect(tx.sale.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          ncf: null,
          ncfExpirationDate: null,
        }),
      }),
    );
  });
});
