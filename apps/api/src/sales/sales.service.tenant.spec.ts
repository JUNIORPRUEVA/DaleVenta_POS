import { BadRequestException } from "@nestjs/common";
import { SalesService } from "./sales.service";

describe("SalesService tenant isolation", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  function serviceWith(prisma: Record<string, unknown>) {
    return new SalesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      { emitCompany: jest.fn() } as never,
      {
        getCompanyFiscalSettings: jest.fn().mockResolvedValue({
          taxEnabled: false,
          defaultTaxRate: 0,
          pricesIncludeTax: false,
          ncfEnabled: false,
        }),
        resolvePriceMode: jest.fn().mockReturnValue("NO_TAX"),
        calculatorService: { calculate: jest.fn() },
      } as never,
      {
        normalizeType: jest.fn(),
        reserveNextNcf: jest.fn(),
        markIssued: jest.fn(),
      } as never,
    );
  }

  it("rejects clientId from another company when creating a sale", async () => {
    const prisma = {
      sale: { findFirst: jest.fn() },
      client: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        customerId: "22222222-2222-4222-8222-222222222222",
        items: [
          {
            productName: "Servicio",
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 50,
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.client.findFirst).toHaveBeenCalledWith({
      where: {
        id: "22222222-2222-4222-8222-222222222222",
        companyId: user.companyId,
        isDeleted: false,
      },
      select: {
        nombre: true,
        telefono: true,
        taxId: true,
        businessName: true,
        direccion: true,
      },
    });
  });

  it("rejects productId from another company when creating a sale", async () => {
    const prisma = {
      sale: { findFirst: jest.fn() },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      company: {
        findFirst: jest.fn().mockResolvedValue({ name: "Empresa A" }),
      },
      appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        items: [
          {
            productId: "22222222-2222-4222-8222-222222222222",
            qty: 1,
            priceSoldUnit: 100,
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.product.findMany).toHaveBeenCalledWith({
      where: {
        id: { in: ["22222222-2222-4222-8222-222222222222"] },
        companyId: user.companyId,
        archivedAt: null,
      },
      select: {
        id: true,
        nombre: true,
        imagen: true,
        costo: true,
        stock: true,
        taxTreatment: true,
        taxRate: true,
        taxPriceMode: true,
        unitOfMeasure: {
          select: {
            code: true,
            name: true,
            symbol: true,
            allowDecimals: true,
            precision: true,
          },
        },
      },
    });
  });

  it("stores LOCAL product identity for local sale lines", () => {
    const service = serviceWith({} as any);
    const product = {
      id: "11111111-1111-4111-8111-111111111111",
      nombre: "Tela local",
      imagen: null,
      costo: 10,
      stock: 20,
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
    };

    const normalized = (service as any).normalizeItem(
      {
        productId: product.id,
        qty: 5.5,
        priceSoldUnit: 20,
      },
      0,
      new Map([[product.id, product]]),
    );

    expect(normalized).toMatchObject({
      productId: product.id,
      productSource: "LOCAL",
      sourceProductId: product.id,
      productNameSnapshot: "Tela local",
      unitCodeSnapshot: "YARD",
    });
  });

  it("rejects FULLPOS sale lines until writable stock is proven", async () => {
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(null) },
      company: { findFirst: jest.fn().mockResolvedValue({ name: "Empresa A" }) },
      appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        items: [
          {
            productName: "Tela FULLPOS",
            productSource: "FULLPOS",
            sourceProductId: "same-remote-id",
            qty: 5.5,
            priceSoldUnit: 20,
            costUnitSnapshot: 10,
          },
        ],
      } as never),
    ).rejects.toThrow("FULLPOS");
  });

  it("returns the existing sale for the same company and clientRequestId", async () => {
    const existingSale = {
      id: "33333333-3333-4333-8333-333333333333",
      companyId: user.companyId,
      clientRequestId: "sale-request-1",
      items: [],
    };
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(existingSale) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        clientRequestId: "sale-request-1",
        items: [
          {
            productName: "Servicio",
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 50,
          },
        ],
      }),
    ).resolves.toBe(existingSale);

    expect(prisma.sale.findFirst).toHaveBeenCalledWith({
      where: { companyId: user.companyId, clientRequestId: "sale-request-1" },
      include: expect.any(Object),
    });
  });

  it("falls back to a compatible sale list instead of returning empty on schema mismatch", async () => {
    const fallbackSale = {
      id: "44444444-4444-4444-8444-444444444444",
      userId: user.id,
      customerId: null,
      saleDate: new Date("2026-08-20T12:00:00.000Z"),
      note: null,
      totalSold: 3300,
      totalCost: 0,
      totalProfit: 3300,
      commissionAmount: 330,
      paymentMethod: "cash",
      paymentCashAmount: 3300,
      paymentTransferAmount: 0,
      creditAmount: 0,
      creditPaidAmount: 0,
      creditBalance: 0,
      creditStatus: "none",
      isDeleted: false,
      deletedAt: null,
    };
    const prisma = {
      sale: {
        findMany: jest
          .fn()
          .mockRejectedValueOnce({ code: "P2022" })
          .mockResolvedValueOnce([fallbackSale]),
      },
    };
    const service = serviceWith(prisma);

    await expect(
      service.listInvoices(
        user as never,
        "2026-08-01",
        "2026-08-20",
        undefined,
        true,
      ),
    ).resolves.toEqual([fallbackSale]);

    expect(prisma.sale.findMany).toHaveBeenCalledTimes(2);
    expect(prisma.sale.findMany).toHaveBeenLastCalledWith({
      where: {
        companyId: user.companyId,
        saleDate: {
          gte: new Date("2026-08-01T04:00:00.000Z"),
          lt: new Date("2026-08-21T04:00:00.000Z"),
        },
      },
      orderBy: { saleDate: "desc" },
      select: expect.objectContaining({
        id: true,
        totalSold: true,
        saleDate: true,
      }),
    });
  });

  it("listInvoices scopes by companyId and applies take when limit is provided", async () => {
    const prisma = {
      sale: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    await service.listInvoices(
      user as never,
      "2026-08-01",
      "2026-08-20",
      undefined,
      false,
      20,
    );

    expect(prisma.sale.findMany).toHaveBeenCalledWith({
      where: {
        companyId: user.companyId,
        isDeleted: false,
        saleDate: {
          gte: new Date("2026-08-01T04:00:00.000Z"),
          lt: new Date("2026-08-21T04:00:00.000Z"),
        },
      },
      orderBy: { saleDate: "desc" },
      take: 20,
      include: expect.any(Object),
    });
  });

  it("listMine scopes by companyId and applies take when limit is provided", async () => {
    const prisma = {
      sale: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    await service.listMine(
      user as never,
      "2026-08-01",
      "2026-08-20",
      undefined,
      false,
      20,
    );

    expect(prisma.sale.findMany).toHaveBeenCalledWith({
      where: {
        companyId: user.companyId,
        isDeleted: false,
        saleDate: {
          gte: new Date("2026-08-01T04:00:00.000Z"),
          lt: new Date("2026-08-21T04:00:00.000Z"),
        },
      },
      orderBy: { saleDate: "desc" },
      take: 20,
      include: expect.any(Object),
    });
  });

  it("listInvoices without limit does not add take", async () => {
    const prisma = {
      sale: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    await service.listInvoices(
      user as never,
      "2026-08-01",
      "2026-08-20",
      undefined,
      false,
    );

    expect(prisma.sale.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ take: undefined }),
    );
  });
});
