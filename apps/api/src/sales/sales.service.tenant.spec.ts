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
        getCompanyFiscalSettings: jest.fn(),
        resolvePriceMode: jest.fn(),
        calculatorService: { calculate: jest.fn() },
      } as never,
      { normalizeType: jest.fn(), reserveNextNcf: jest.fn(), markIssued: jest.fn() } as never,
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
        items: [{ productName: "Servicio", qty: 1, priceSoldUnit: 100, costUnitSnapshot: 50 }],
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
});
