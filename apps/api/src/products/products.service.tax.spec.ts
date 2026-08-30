import { BadRequestException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ProductsService } from "./products.service";

describe("ProductsService fiscal validation", () => {
  function buildService(transactionClient: any) {
    const prisma = {
      $transaction: jest.fn(
        (callback: (tx: typeof transactionClient) => unknown) =>
          callback(transactionClient),
      ),
    };
    const service = new ProductsService(
      prisma as never,
      {} as never,
      {
        resolveForCompany: jest.fn(async (companyId: string) => ({
          companyId,
          source: "LOCAL",
          readOnly: false,
          fullposCompanyId: null,
          supportsDecimalStock: true,
          supportsNativeUom: true,
          supportsProductCreate: true,
          supportsProductEdit: true,
          supportsStockAdjustment: true,
          resolution: "safe-default",
        })),
      } as never,
      { get: jest.fn().mockReturnValue("") } as unknown as ConfigService,
      {
        assertCanCreateProduct: jest.fn().mockResolvedValue(undefined),
      } as never,
    );
    return { service, prisma };
  }

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
    const { service } = buildService(transactionClient);

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

  it("ignores null taxRate on partial product payloads", async () => {
    const createdProduct = {
      id: "product-1",
      nombre: "Producto parcial",
      codigo: null,
      precio: 100,
      costo: 50,
      stock: 1,
      categoria: "General",
      imagen: null,
      taxTreatment: "INHERIT",
      taxRate: null,
      taxPriceMode: null,
    };
    const transactionClient = {
      product: {
        findFirst: jest.fn().mockResolvedValue(createdProduct),
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn().mockResolvedValue(createdProduct),
      },
      tax: {
        findFirst: jest.fn(),
      },
      saleItem: { count: jest.fn().mockResolvedValue(0) },
      cotizacionItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      websiteProductOverride: { count: jest.fn().mockResolvedValue(0) },
    };
    const { service } = buildService(transactionClient);

    await service.create(
      {
        id: "user-1",
        role: "ADMIN",
        companyId: "11111111-1111-1111-1111-111111111111",
      } as never,
      {
        nombre: "Producto parcial",
        precio: 100,
        costo: 50,
        stock: 1,
        categoria: "General",
        taxRate: null,
        taxPriceMode: null,
      } as never,
    );

    expect(transactionClient.product.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        taxRate: undefined,
        taxPriceMode: undefined,
      }),
    });
  });

  it("normalizes EXEMPT products with null tax fields", async () => {
    const createdProduct = {
      id: "product-1",
      nombre: "Producto exento",
      codigo: null,
      precio: 100,
      costo: 50,
      stock: 1,
      categoria: "General",
      imagen: null,
      taxTreatment: "EXEMPT",
      taxRate: null,
      taxPriceMode: null,
    };
    const transactionClient = {
      product: {
        findFirst: jest.fn().mockResolvedValue(createdProduct),
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn().mockResolvedValue(createdProduct),
      },
      tax: {
        findFirst: jest.fn(),
      },
      saleItem: { count: jest.fn().mockResolvedValue(0) },
      cotizacionItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      websiteProductOverride: { count: jest.fn().mockResolvedValue(0) },
    };
    const { service } = buildService(transactionClient);

    await service.create(
      {
        id: "user-1",
        role: "ADMIN",
        companyId: "11111111-1111-1111-1111-111111111111",
      } as never,
      {
        nombre: "Producto exento",
        precio: 100,
        costo: 50,
        stock: 1,
        categoria: "General",
        taxTreatment: "EXEMPT",
        taxRate: null,
        taxPriceMode: null,
      } as never,
    );

    expect(transactionClient.product.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        taxTreatment: "EXEMPT",
        taxRate: null,
        taxPriceMode: null,
      }),
    });
  });
});
