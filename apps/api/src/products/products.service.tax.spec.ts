import { BadRequestException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ProductsService } from "./products.service";

describe("ProductsService fiscal validation", () => {
  it("rejects taxable product rates that are not active in the tenant company", async () => {
    const transactionClient = {
      product: {
        findFirst: jest.fn().mockResolvedValue(null),
        findMany: jest.fn().mockResolvedValue([]),
      },
      tax: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
    };
    const prisma = {
      $transaction: jest.fn(
        (callback: (tx: typeof transactionClient) => unknown) =>
          callback(transactionClient),
      ),
    };
    const service = new ProductsService(
      prisma as never,
      {} as never,
      { get: jest.fn().mockReturnValue("") } as unknown as ConfigService,
      {
        assertCanCreateProduct: jest.fn().mockResolvedValue(undefined),
      } as never,
    );

    await expect(
      service.create(
        {
          id: "user-1",
          role: "ADMIN",
          companyId: "11111111-1111-1111-1111-111111111111",
        } as never,
        {
          nombre: "Producto ajeno",
          precio: 100,
          costo: 50,
          stock: 1,
          categoria: "General",
          taxTreatment: "TAXABLE",
          taxRate: 0.16,
          taxPriceMode: "TAX_ADDED",
        },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(transactionClient.tax.findFirst).toHaveBeenCalledWith({
      where: {
        companyId: "11111111-1111-1111-1111-111111111111",
        isActive: true,
        rate: expect.anything(),
      },
      select: { id: true },
    });
  });
});
