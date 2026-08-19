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
      },
    });
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
});
