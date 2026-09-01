import { ConfigService } from "@nestjs/config";
import { ConflictException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { ProductsService } from "./products.service";

describe("ProductsService tenant isolation (multiempresa)", () => {
  function buildService(
    findMany: jest.Mock,
    options: {
      config?: Record<string, string>;
      catalogProducts?: { findAll?: jest.Mock };
      prisma?: any;
      resolveSource?: jest.Mock;
    } = {},
  ) {
    const prisma = options.prisma ?? {
      product: { findMany },
    };
    const resolveSource =
      options.resolveSource ??
      jest.fn(async (companyId: string) => ({
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
      }));
    const service = new ProductsService(
      prisma as never,
      (options.catalogProducts ?? {}) as never,
      { resolveForCompany: resolveSource } as never,
      {
        get: jest.fn((key: string) => options.config?.[key] ?? ""),
      } as unknown as ConfigService,
      {
        assertCanCreateProduct: jest.fn().mockResolvedValue(undefined),
      } as never,
    );
    return { service, prisma, resolveSource };
  }

  const companyA = "11111111-1111-1111-1111-111111111111";
  const companyB = "22222222-2222-4222-8222-222222222222";

  it("list all products scoped strictly to the authenticated company", async () => {
    const findMany = jest.fn().mockResolvedValue([
      {
        id: "p-1",
        companyId: companyA,
        nombre: "Producto A",
        codigo: "A-1",
        categoria: "General",
        costo: 10,
        precio: 20,
        stock: 5,
        taxTreatment: "INHERIT",
        taxRate: null,
        taxPriceMode: null,
        imagen: null,
        imageKey: null,
        imageUpdatedAt: null,
      },
    ]);
    const { service } = buildService(findMany);

    const result = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    // La consulta SIEMPRE filtra por la empresa del usuario autenticado.
    expect(findMany).toHaveBeenCalledWith({
      where: { companyId: companyA, archivedAt: null },
      orderBy: { nombre: "asc" },
      select: expect.any(Object),
    });
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("p-1");
  });

  it("does NOT reuse the where filter across companies (A nunca ve B)", async () => {
    const findMany = jest
      .fn()
      .mockImplementation((args: { where: { companyId: string } }) => {
        return Promise.resolve(
          args.where.companyId === companyA
            ? [
                {
                  id: "pA",
                  companyId: companyA,
                  nombre: "Producto de A",
                  codigo: "A",
                  categoria: "General",
                  costo: 1,
                  precio: 2,
                  stock: 3,
                  taxTreatment: "INHERIT",
                  taxRate: null,
                  taxPriceMode: null,
                  imagen: null,
                  imageKey: null,
                  imageUpdatedAt: null,
                },
              ]
            : [
                {
                  id: "pB",
                  companyId: companyB,
                  nombre: "Producto de B",
                  codigo: "B",
                  categoria: "General",
                  costo: 1,
                  precio: 2,
                  stock: 3,
                  taxTreatment: "INHERIT",
                  taxRate: null,
                  taxPriceMode: null,
                  imagen: null,
                  imageKey: null,
                  imageUpdatedAt: null,
                },
              ],
        );
      });
    const { service } = buildService(findMany);

    const forA = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);
    const forB = await service.findAll({
      id: "user-b",
      role: "ADMIN",
      companyId: companyB,
    } as never);

    expect(forA[0].id).toBe("pA");
    expect(forB[0].id).toBe("pB");
    expect(findMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        where: { companyId: companyA, archivedAt: null },
      }),
    );
    expect(findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: { companyId: companyB, archivedAt: null },
      }),
    );
  });

  it("uses an explicit SELECT that excludes unused heavy columns", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const { service } = buildService(findMany);
    await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    const select = (
      findMany.mock.calls[0][0] as { select: Record<string, boolean> }
    ).select;
    // Campos que SÍ deben incluirse (consumidos por los clientes).
    for (const field of [
      "id",
      "companyId",
      "nombre",
      "codigo",
      "categoria",
      "costo",
      "precio",
      "stock",
      "taxTreatment",
      "taxRate",
      "taxPriceMode",
      "imagen",
      "imageKey",
      "imageUpdatedAt",
      "archivedAt",
    ]) {
      expect(select[field]).toBe(true);
    }
    // Columnas pesadas que ningún cliente POS consume: no deben leerse.
    expect(select.imageStorageProvider).toBeUndefined();
    expect(select.imageMimeType).toBeUndefined();
    expect(select.imageOriginalFileName).toBeUndefined();
  });

  it("falls back to the legacy product select when production has not received UoM columns yet", async () => {
    const schemaMismatch = {
      code: "P2022",
      message: "The column `Product.unitOfMeasureId` does not exist",
    };
    const findMany = jest
      .fn()
      .mockRejectedValueOnce(schemaMismatch)
      .mockResolvedValueOnce([
        {
          id: "legacy-product",
          companyId: companyA,
          nombre: "Producto legacy",
          codigo: "LEG-1",
          categoria: "General",
          costo: 10,
          precio: 20,
          stock: 5,
          taxTreatment: "INHERIT",
          taxRate: null,
          taxPriceMode: null,
          imagen: null,
          imageKey: null,
          imageUpdatedAt: null,
        },
      ]);
    const { service } = buildService(findMany);

    const result = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    expect(findMany).toHaveBeenCalledTimes(2);
    expect(findMany.mock.calls[0][0].select.unitOfMeasureId).toBe(true);
    expect(findMany.mock.calls[1][0].select.unitOfMeasureId).toBeUndefined();
    expect(findMany.mock.calls[1][0].select.unitOfMeasure).toBeUndefined();
    expect(result[0]).toMatchObject({
      id: "legacy-product",
      unitOfMeasureId: "UNIT",
      unitOfMeasure: expect.objectContaining({ code: "UNIT", precision: 0 }),
    });
  });

  it("uses the company product source to read FULLPOS instead of the empty local Product table", async () => {
    const findMany = jest.fn();
    const catalogFindAll = jest.fn().mockResolvedValue({
      items: [{ id: "external-1", nombre: "Producto externo" }],
    });
    const resolveSource = jest.fn(async (companyId: string) => ({
      companyId,
      source: "FULLPOS",
      readOnly: true,
      fullposCompanyId: "fullpos-company-a",
      supportsDecimalStock: false,
      supportsNativeUom: false,
      supportsProductCreate: false,
      supportsProductEdit: false,
      supportsStockAdjustment: false,
      resolution: "company",
    }));
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    const result = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    expect(resolveSource).toHaveBeenCalledWith(companyA);
    expect(catalogFindAll).toHaveBeenCalledWith({
      companyId: companyA,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-a",
    });
    expect(findMany).not.toHaveBeenCalled();
    expect(result).toEqual([{ id: "external-1", nombre: "Producto externo" }]);
    await expect(
      service.getSource({
        id: "user-a",
        role: "ADMIN",
        companyId: companyA,
      } as never),
    ).resolves.toBe("FULLPOS");
    await expect(
      service.isReadOnly({
        id: "user-a",
        role: "ADMIN",
        companyId: companyA,
      } as never),
    ).resolves.toBe(true);
  });

  it("keeps LOCAL and FULLPOS companies isolated in the same process", async () => {
    const findMany = jest.fn().mockResolvedValue([
      {
        id: "local-a",
        companyId: companyA,
        nombre: "Local A",
        codigo: "A",
        categoria: "General",
        costo: 1,
        precio: 2,
        stock: 3,
        taxTreatment: "INHERIT",
        taxRate: null,
        taxPriceMode: null,
        imagen: null,
        imageKey: null,
        imageUpdatedAt: null,
      },
    ]);
    const catalogFindAll = jest.fn().mockResolvedValue({
      items: [{ id: "external-b", nombre: "FullPOS B" }],
    });
    const resolveSource = jest.fn(async (companyId: string) =>
      companyId === companyA
        ? {
            companyId,
            source: "LOCAL",
            readOnly: false,
            fullposCompanyId: null,
            supportsDecimalStock: true,
            supportsNativeUom: true,
            supportsProductCreate: true,
            supportsProductEdit: true,
            supportsStockAdjustment: true,
            resolution: "company",
          }
        : {
            companyId,
            source: "FULLPOS",
            readOnly: true,
            fullposCompanyId: "fullpos-company-b",
            supportsDecimalStock: false,
            supportsNativeUom: false,
            supportsProductCreate: false,
            supportsProductEdit: false,
            supportsStockAdjustment: false,
            resolution: "company",
          },
    );
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    const local = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);
    const external = await service.findAll({
      id: "user-b",
      role: "ADMIN",
      companyId: companyB,
    } as never);

    expect(local[0].id).toBe("local-a");
    expect(external[0].id).toBe("external-b");
    expect(findMany).toHaveBeenCalledTimes(1);
    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: companyA, archivedAt: null },
      }),
    );
    expect(catalogFindAll).toHaveBeenCalledWith({
      companyId: companyB,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-b",
    });
  });

  it("does not collapse same external sourceProductId across companies", async () => {
    const findMany = jest.fn();
    const catalogFindAll = jest
      .fn()
      .mockResolvedValueOnce({ items: [{ id: "same-1", nombre: "A" }] })
      .mockResolvedValueOnce({ items: [{ id: "same-1", nombre: "B" }] });
    const resolveSource = jest.fn(async (companyId: string) => ({
      companyId,
      source: "FULLPOS",
      readOnly: true,
      fullposCompanyId:
        companyId === companyA ? "fullpos-company-a" : "fullpos-company-b",
      supportsDecimalStock: false,
      supportsNativeUom: false,
      supportsProductCreate: false,
      supportsProductEdit: false,
      supportsStockAdjustment: false,
      resolution: "company",
    }));
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    await service.findAll({
      id: "a",
      role: "ADMIN",
      companyId: companyA,
    } as never);
    await service.findAll({
      id: "b",
      role: "ADMIN",
      companyId: companyB,
    } as never);

    expect(catalogFindAll).toHaveBeenNthCalledWith(1, {
      companyId: companyA,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-a",
    });
    expect(catalogFindAll).toHaveBeenNthCalledWith(2, {
      companyId: companyB,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-b",
    });
  });

  it("propagates provider failures instead of returning an empty product list", async () => {
    const providerError = new Error("provider unavailable");
    const findMany = jest.fn();
    const catalogFindAll = jest.fn().mockRejectedValue(providerError);
    const resolveSource = jest.fn(async (companyId: string) => ({
      companyId,
      source: "FULLPOS",
      readOnly: true,
      fullposCompanyId: "fullpos-company-a",
      supportsDecimalStock: false,
      supportsNativeUom: false,
      supportsProductCreate: false,
      supportsProductEdit: false,
      supportsStockAdjustment: false,
      resolution: "company",
    }));
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    await expect(
      service.findAll({ id: "a", role: "ADMIN", companyId: companyA } as never),
    ).rejects.toThrow("provider unavailable");
    expect(findMany).not.toHaveBeenCalled();
  });

  it("treats deleting an absent product in the authenticated tenant as idempotent success", async () => {
    const prisma = {
      product: {
        findMany: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null),
        deleteMany: jest.fn(),
      },
      inventoryMovement: { count: jest.fn() },
      warehouseTransferItem: { count: jest.fn() },
      saleItem: { count: jest.fn() },
      cotizacionItem: { count: jest.fn() },
      purchaseOrderItem: { count: jest.fn() },
      purchaseReceiptItem: { count: jest.fn() },
    };
    const { service } = buildService(prisma.product.findMany, { prisma });

    await expect(
      service.remove(
        {
          id: "user-a",
          role: "ADMIN",
          companyId: companyA,
        } as never,
        "01583f95-78c7-4100-887b-7a29480e5d0d",
      ),
    ).resolves.toEqual({ ok: true });

    expect(prisma.product.findFirst).toHaveBeenCalledWith({
      where: {
        id: "01583f95-78c7-4100-887b-7a29480e5d0d",
        companyId: companyA,
      },
      select: { id: true, archivedAt: true },
    });
    expect(prisma.product.deleteMany).not.toHaveBeenCalled();
  });

  it("physically deletes a product only when the authenticated tenant has no protected history", async () => {
    const prisma = {
      product: {
        findMany: jest.fn(),
        findFirst: jest.fn().mockResolvedValue({
          id: "product-a",
          archivedAt: null,
        }),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      inventoryMovement: { count: jest.fn().mockResolvedValue(0) },
      warehouseTransferItem: { count: jest.fn().mockResolvedValue(0) },
      saleItem: { count: jest.fn().mockResolvedValue(0) },
      cotizacionItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseReceiptItem: { count: jest.fn().mockResolvedValue(0) },
    };
    const { service } = buildService(prisma.product.findMany, { prisma });

    await expect(
      service.remove(
        { id: "user-a", role: "ADMIN", companyId: companyA } as never,
        "product-a",
      ),
    ).resolves.toEqual({ ok: true });

    expect(prisma.inventoryMovement.count).toHaveBeenCalledWith({
      where: { companyId: companyA, productId: "product-a" },
    });
    expect(prisma.saleItem.count).toHaveBeenCalledWith({
      where: { productId: "product-a", sale: { companyId: companyA } },
    });
    expect(prisma.product.deleteMany).toHaveBeenCalledWith({
      where: { id: "product-a", companyId: companyA },
    });
  });

  it("returns a controlled conflict when product history prevents physical delete", async () => {
    const prisma = {
      product: {
        findMany: jest.fn(),
        findFirst: jest.fn().mockResolvedValue({
          id: "product-a",
          archivedAt: null,
        }),
        deleteMany: jest.fn(),
      },
      inventoryMovement: { count: jest.fn().mockResolvedValue(2) },
      warehouseTransferItem: { count: jest.fn().mockResolvedValue(0) },
      saleItem: { count: jest.fn().mockResolvedValue(1) },
      cotizacionItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseReceiptItem: { count: jest.fn().mockResolvedValue(0) },
    };
    const { service } = buildService(prisma.product.findMany, { prisma });

    await expect(async () =>
      service.remove(
        { id: "user-a", role: "ADMIN", companyId: companyA } as never,
        "product-a",
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "PRODUCT_HAS_HISTORY",
        canArchive: true,
        details: expect.objectContaining({
          inventoryMovements: 2,
          saleItems: 1,
        }),
      }),
    });
    expect(prisma.product.deleteMany).not.toHaveBeenCalled();
  });

  it.each([
    ["InventoryMovement", "inventoryMovement", "inventoryMovements"],
    ["SaleItem", "saleItem", "saleItems"],
    [
      "WarehouseTransferItem",
      "warehouseTransferItem",
      "warehouseTransferItems",
    ],
    ["PurchaseOrderItem", "purchaseOrderItem", "purchaseOrderItems"],
    ["PurchaseReceiptItem", "purchaseReceiptItem", "purchaseReceiptItems"],
  ])(
    "blocks physical delete when %s history exists",
    async (_label, delegateName, detailKey) => {
      const counts = {
        inventoryMovement: 0,
        warehouseTransferItem: 0,
        saleItem: 0,
        cotizacionItem: 0,
        purchaseOrderItem: 0,
        purchaseReceiptItem: 0,
        [delegateName]: 1,
      } as Record<string, number>;
      const prisma = {
        product: {
          findMany: jest.fn(),
          findFirst: jest.fn().mockResolvedValue({
            id: "product-a",
            archivedAt: null,
          }),
          deleteMany: jest.fn(),
        },
        inventoryMovement: {
          count: jest.fn().mockResolvedValue(counts.inventoryMovement),
        },
        warehouseTransferItem: {
          count: jest.fn().mockResolvedValue(counts.warehouseTransferItem),
        },
        saleItem: { count: jest.fn().mockResolvedValue(counts.saleItem) },
        cotizacionItem: {
          count: jest.fn().mockResolvedValue(counts.cotizacionItem),
        },
        purchaseOrderItem: {
          count: jest.fn().mockResolvedValue(counts.purchaseOrderItem),
        },
        purchaseReceiptItem: {
          count: jest.fn().mockResolvedValue(counts.purchaseReceiptItem),
        },
      };
      const { service } = buildService(prisma.product.findMany, { prisma });

      await expect(async () =>
        service.remove(
          { id: "user-a", role: "ADMIN", companyId: companyA } as never,
          "product-a",
        ),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "PRODUCT_HAS_HISTORY",
          canArchive: true,
          details: expect.objectContaining({ [detailKey]: 1 }),
        }),
      });
      expect(prisma.product.deleteMany).not.toHaveBeenCalled();
    },
  );

  it("archives a product idempotently inside the authenticated tenant", async () => {
    const archivedProduct = {
      id: "product-a",
      companyId: companyA,
      nombre: "Archivado",
      codigo: null,
      categoria: "General",
      costo: 1,
      precio: 2,
      stock: 3,
      taxTreatment: "INHERIT",
      taxRate: null,
      taxPriceMode: null,
      imagen: null,
      imageKey: null,
      imageUpdatedAt: null,
      archivedAt: new Date("2026-09-01T12:00:00Z"),
    };
    const prisma = {
      product: {
        findMany: jest.fn(),
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "product-a", archivedAt: null })
          .mockResolvedValueOnce(archivedProduct),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const { service } = buildService(prisma.product.findMany, { prisma });

    const result = await service.archive(
      { id: "user-a", role: "ADMIN", companyId: companyA } as never,
      "product-a",
    );

    expect(prisma.product.updateMany).toHaveBeenCalledWith({
      where: { id: "product-a", companyId: companyA, archivedAt: null },
      data: { archivedAt: expect.any(Date) },
    });
    expect(result).toMatchObject({
      ok: true,
      archived: true,
      product: expect.objectContaining({
        id: "product-a",
        archived: true,
        activo: false,
      }),
    });
  });

  it("does not archive a product from another tenant", async () => {
    const prisma = {
      product: {
        findMany: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn(),
      },
    };
    const { service } = buildService(prisma.product.findMany, { prisma });

    await expect(
      service.archive(
        { id: "user-a", role: "ADMIN", companyId: companyA } as never,
        "product-b",
      ),
    ).rejects.toThrow("Producto no encontrado");
    expect(prisma.product.findFirst).toHaveBeenCalledWith({
      where: { id: "product-b", companyId: companyA },
      select: { id: true, archivedAt: true },
    });
    expect(prisma.product.updateMany).not.toHaveBeenCalled();
  });
});
