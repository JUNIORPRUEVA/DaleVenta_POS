import { BadRequestException, NotFoundException } from "@nestjs/common";
import { CotizacionesService } from "./cotizaciones.service";

describe("CotizacionesService tenant isolation", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  function serviceWith(prisma: Record<string, unknown>) {
    return new CotizacionesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      { get: jest.fn(), set: jest.fn(), delByPattern: jest.fn(), isEnabled: jest.fn().mockReturnValue(false) } as never,
      { normalizeWhatsAppNumber: jest.fn() } as never,
      {
        getCompanyFiscalSettings: jest.fn(),
        resolvePriceMode: jest.fn(),
        calculatorService: { calculate: jest.fn() },
      } as never,
    );
  }

  it("does not read quoteId from another company", async () => {
    const prisma = {
      cotizacion: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.findOne(user as never, "22222222-2222-4222-8222-222222222222"),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.cotizacion.findFirst).toHaveBeenCalledWith({
      where: {
        id: "22222222-2222-4222-8222-222222222222",
        companyId: user.companyId,
      },
      include: expect.any(Object),
    });
  });

  it("lists quotes with tenant scope, stable pagination and max 200 rows", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const count = jest.fn().mockResolvedValue(601);
    const prisma = {
      cotizacion: { findMany, count },
      $transaction: jest.fn((queries: unknown[]) => Promise.all(queries)),
    };
    const redis = {
      get: jest.fn().mockResolvedValue(null),
      set: jest.fn(),
      delByPattern: jest.fn(),
      isEnabled: jest.fn().mockReturnValue(false),
    };
    const service = new CotizacionesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      redis as never,
      { normalizeWhatsAppNumber: jest.fn() } as never,
      {
        getCompanyFiscalSettings: jest.fn(),
        resolvePriceMode: jest.fn(),
        calculatorService: { calculate: jest.fn() },
      } as never,
    );

    const result = await service.list(user as never, {
      page: 3,
      limit: 999,
    });

    expect(result).toMatchObject({
      items: [],
      page: 3,
      limit: 200,
      total: 601,
      hasMore: true,
      nextPage: 4,
    });
    expect(findMany).toHaveBeenCalledWith({
      where: { companyId: user.companyId },
      skip: 400,
      take: 201,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      include: expect.any(Object),
    });
    expect(count).toHaveBeenCalledWith({
      where: { companyId: user.companyId },
    });
  });

  it("applies quote history filters before pagination", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const count = jest.fn().mockResolvedValue(0);
    const prisma = {
      cotizacion: { findMany, count },
      $transaction: jest.fn((queries: unknown[]) => Promise.all(queries)),
    };
    const service = serviceWith(prisma);

    await service.list(user as never, {
      page: 1,
      limit: 50,
      search: "camara 809",
      userId: user.id,
      customerId: "22222222-2222-4222-8222-222222222222",
      from: "2026-10-01",
      to: "2026-10-10",
    });

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          companyId: user.companyId,
          createdByUserId: user.id,
          customerId: "22222222-2222-4222-8222-222222222222",
          createdAt: {
            gte: new Date("2026-10-01T00:00:00.000Z"),
            lte: new Date("2026-10-10T23:59:59.999Z"),
          },
          AND: [
            {
              OR: expect.arrayContaining([
                { customerName: { contains: "camara 809", mode: "insensitive" } },
                {
                  items: {
                    some: {
                      productNameSnapshot: {
                        contains: "camara 809",
                        mode: "insensitive",
                      },
                    },
                  },
                },
                {
                  customerPhoneNormalized: {
                    contains: "809",
                    mode: "insensitive",
                  },
                },
              ]),
            },
          ],
        }),
        skip: 0,
        take: 51,
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      }),
    );
  });

  it("rejects clientId from another company when creating a quote", async () => {
    const transactionClient = {
      client: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const prisma = {
      product: { findMany: jest.fn().mockResolvedValue([]) },
      $transaction: jest.fn((callback: (tx: typeof transactionClient) => unknown) =>
        callback(transactionClient),
      ),
    };
    const service = serviceWith(prisma);
    (service as any).taxes.getCompanyFiscalSettings.mockResolvedValue({
      taxEnabled: false,
      defaultTaxRate: 0.18,
      pricesIncludeTax: false,
    });
    (service as any).taxes.resolvePriceMode.mockReturnValue("NO_TAX");
    (service as any).taxes.calculatorService.calculate.mockReturnValue({
      subtotal: { toString: () => "100" },
      discountAmount: 0,
      taxableBase: 0,
      taxAmount: 0,
      exemptAmount: 100,
      total: { minus: () => ({}) },
      lines: [{ lineTotal: { minus: () => ({}) }, grossAmount: 100, discountAmount: 0, taxableBase: 0, taxRate: 0, taxAmount: 0, exemptAmount: 100, taxIncluded: false, taxExempt: true }],
    });

    await expect(
      service.create(user as never, {
        customerId: "22222222-2222-4222-8222-222222222222",
        customerName: "Cliente B",
        customerPhone: "8090000000",
        items: [{ productName: "Servicio", qty: 1, unitPrice: 100, costUnitSnapshot: 50 }],
      } as never),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(transactionClient.client.findFirst).toHaveBeenCalledWith({
      where: {
        id: "22222222-2222-4222-8222-222222222222",
        companyId: user.companyId,
        isDeleted: false,
      },
      select: { id: true },
    });
  });

  it("rejects productId from another company when creating a quote", async () => {
    const prisma = {
      product: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        customerName: "Cliente",
        customerPhone: "8090000000",
        items: [
          {
            productId: "22222222-2222-4222-8222-222222222222",
            qty: 1,
            unitPrice: 100,
          },
        ],
      } as never),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.product.findMany).toHaveBeenCalledWith({
      where: {
        id: { in: ["22222222-2222-4222-8222-222222222222"] },
        companyId: user.companyId,
      },
      select: {
        id: true,
        nombre: true,
        imagen: true,
        costo: true,
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

  it("preserves FULLPOS product identity on quote lines without live catalog dependency", async () => {
    const prisma = {
      product: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    const [item] = await (service as any).normalizeItems(user.companyId, [
      {
        productName: "Producto externo",
        productSource: "FULLPOS",
        sourceProductId: "same-remote-id",
        qty: 2.375,
        unitPrice: 100,
        costUnitSnapshot: 50,
      },
    ]);

    expect(item).toMatchObject({
      productId: null,
      productSource: "FULLPOS",
      sourceProductId: "same-remote-id",
      productNameSnapshot: "Producto externo",
      unitCodeSnapshot: "UNIT",
    });
    expect(prisma.product.findMany).not.toHaveBeenCalled();
  });
});
