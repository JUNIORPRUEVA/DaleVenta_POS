import { BadRequestException, NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { ProductsService } from "./products.service";

const companyA = "11111111-1111-1111-1111-111111111111";
const companyB = "22222222-2222-4222-8222-222222222222";
const userA = { id: "user-a", role: "ADMIN", companyId: companyA };

function sourceContext() {
  return {
    companyId: companyA,
    source: "LOCAL",
    readOnly: false,
    fullposCompanyId: null,
    supportsDecimalStock: true,
    supportsNativeUom: true,
    supportsProductCreate: true,
    supportsProductEdit: true,
    supportsStockAdjustment: true,
    resolution: "safe-default",
  };
}

function buildService(
  prisma: Record<string, unknown>,
  inventory: Record<string, unknown> = {},
  licenses: Record<string, unknown> = {
    assertCanCreateProduct: jest.fn().mockResolvedValue(undefined),
    assertCanCreateProductInTransaction: jest.fn().mockResolvedValue(undefined),
  },
) {
  const service = new ProductsService(
    prisma as never,
    {} as never,
    { resolveForCompany: jest.fn(async () => sourceContext()) } as never,
    { get: jest.fn(() => "") } as unknown as ConfigService,
    licenses as never,
    inventory as never,
  );
  jest.spyOn(service as never, "productResponse").mockResolvedValue({
    id: "product-1",
    stock: 15,
  } as never);
  jest.spyOn(service as never, "pruneSafeDuplicateProducts").mockResolvedValue({
    deleted: 0,
    skipped: 0,
  } as never);
  return service;
}

describe("ProductsService stock hardening", () => {
  it("rejects direct stock mutation through normal product update", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          unitOfMeasureId: "YARD",
          unitOfMeasure: {
            id: "YARD",
            code: "YARD",
            name: "Yarda",
            symbol: "yd",
            category: "LENGTH",
            allowDecimals: true,
            precision: 3,
            active: true,
          },
        }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await expect(
      service.update(userA as never, "product-1", {
        nombre: "Tela",
        stock: 20,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("updates metadata without sending stock to Prisma", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          unitOfMeasureId: "YARD",
          unitOfMeasure: {
            id: "YARD",
            code: "YARD",
            name: "Yarda",
            symbol: "yd",
            category: "LENGTH",
            allowDecimals: true,
            precision: 3,
            active: true,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    const result = await service.update(userA as never, "product-1", {
      nombre: "Tela premium",
      precio: 120,
    });

    expect(result.stock).toBe(15);
    expect(tx.product.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "product-1", companyId: companyA, archivedAt: null },
        data: expect.not.objectContaining({ stock: expect.anything() }),
      }),
    );
  });

  it("does not treat transformed DTO stock=undefined as a stock update", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          unitOfMeasureId: "YARD",
          unitOfMeasure: {
            id: "YARD",
            code: "YARD",
            name: "Yarda",
            symbol: "yd",
            category: "LENGTH",
            allowDecimals: true,
            precision: 3,
            active: true,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });
    const dto = {
      nombre: "Tela premium",
      precio: 120,
      stock: undefined,
    };

    await service.update(userA as never, "product-1", dto);

    expect(tx.product.updateMany.mock.calls[0][0].data.stock).toBeUndefined();
  });

  it("keeps stale editor save from restoring old stock", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          unitOfMeasureId: "YARD",
          unitOfMeasure: {
            id: "YARD",
            code: "YARD",
            name: "Yarda",
            symbol: "yd",
            category: "LENGTH",
            allowDecimals: true,
            precision: 3,
            active: true,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await service.update(userA as never, "product-1", {
      nombre: "Nombre editado",
      precio: 120,
      costo: 70,
    });

    expect(tx.product.updateMany.mock.calls[0][0].data.stock).toBeUndefined();
  });

  it("allows stock adjustment through the dedicated inventory flow and audits it", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("14.5"),
          unitOfMeasureId: "YARD",
          unitOfMeasure: {
            id: "YARD",
            code: "YARD",
            name: "Yarda",
            symbol: "yd",
            category: "LENGTH",
            allowDecimals: true,
            precision: 3,
            active: true,
          },
        }),
      },
      warehouse: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: "warehouse-1",
            name: "Principal",
            code: "MAIN",
            isDefault: true,
          },
        ]),
        findFirst: jest.fn().mockResolvedValue({
          id: "warehouse-1",
          name: "Principal",
          code: "MAIN",
        }),
      },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const inventory = {
      setCountedStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = buildService(prisma, inventory);

    await service.adjustStock(userA as never, "product-1", {
      stock: 15,
      reason: "Conteo fisico",
    });

    expect(inventory.setCountedStockInTransaction).toHaveBeenCalledWith(
      tx,
      expect.objectContaining({
        companyId: companyA,
        productId: "product-1",
        warehouseId: "warehouse-1",
        countedQuantity: new Prisma.Decimal("15"),
        expectedCurrentQuantity: new Prisma.Decimal("14.5"),
        reason: "Conteo fisico",
        createdByUserId: "user-a",
      }),
    );
  });

  it("uses the default warehouse for billing stock adjustment when multi-warehouse is disabled", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          multiWarehouseEnabled: false,
        }),
      },
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("0"),
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            category: "COUNT",
            allowDecimals: false,
            precision: 0,
            active: true,
          },
        }),
      },
      warehouse: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: "warehouse-main",
            name: "Principal",
            code: "MAIN",
            isDefault: true,
          },
          {
            id: "warehouse-secondary",
            name: "Secundario",
            code: "SEC",
            isDefault: false,
          },
        ]),
        findFirst: jest.fn().mockResolvedValue({
          id: "warehouse-main",
          name: "Principal",
          code: "MAIN",
        }),
      },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const inventory = {
      setCountedStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = buildService(prisma, inventory);

    await service.adjustStock(userA as never, "product-1", {
      stock: 1,
      reason: "Ajuste desde facturacion",
    });

    expect(tx.company.findUnique).toHaveBeenCalledWith({
      where: { id: companyA },
      select: { multiWarehouseEnabled: true },
    });
    expect(inventory.setCountedStockInTransaction).toHaveBeenCalledWith(
      tx,
      expect.objectContaining({
        companyId: companyA,
        productId: "product-1",
        warehouseId: "warehouse-main",
        countedQuantity: new Prisma.Decimal("1"),
        expectedCurrentQuantity: new Prisma.Decimal("0"),
        sourceType: "PRODUCT_STOCK_COUNT",
        reason: "Ajuste desde facturacion",
        createdByUserId: "user-a",
      }),
    );
  });

  it("keeps tenant isolation on stock adjustment", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn(),
      },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const service = buildService(prisma);

    await expect(
      service.adjustStock(userA as never, "other-company-product", {
        stock: 3,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(tx.product.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          id: "other-company-product",
          companyId: companyA,
          archivedAt: null,
        },
      }),
    );
    expect(tx.product.updateMany).not.toHaveBeenCalled();
  });

  it("normalizes services to non-inventory products and skips initial stock rows", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({ id: "product-1" }),
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn().mockResolvedValue({ id: "product-1" }),
      },
      tax: { findFirst: jest.fn() },
      warehouse: {
        findMany: jest.fn(),
        findFirst: jest.fn(),
      },
      warehouseStock: { upsert: jest.fn() },
      saleItem: { count: jest.fn().mockResolvedValue(0) },
      cotizacionItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      websiteProductOverride: { count: jest.fn().mockResolvedValue(0) },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const inventory = {
      increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = buildService(prisma, inventory);

    await service.create(userA as never, {
      nombre: "Instalacion",
      precio: 800,
      costo: 0,
      stock: 0,
      categoria: "Servicios",
      itemType: "SERVICE",
      trackInventory: true,
    });

    expect(tx.product.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        itemType: "SERVICE",
        trackInventory: false,
        stock: new Prisma.Decimal(0),
      }),
    });
    expect(tx.warehouse.findMany).not.toHaveBeenCalled();
    expect(tx.warehouseStock.upsert).not.toHaveBeenCalled();
    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
  });

  it("rejects initial stock for non-inventory products", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue(null),
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn(),
      },
      tax: { findFirst: jest.fn() },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const service = buildService(prisma);

    await expect(
      service.create(userA as never, {
        nombre: "Garantia",
        precio: 250,
        costo: 0,
        stock: 3,
        categoria: "Servicios",
        itemType: "PRODUCT",
        trackInventory: false,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.product.create).not.toHaveBeenCalled();
  });

  it("forces non-inventory create and skips initial stock when company inventory is disabled", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({ inventoryEnabled: false }),
      },
      product: {
        findFirst: jest.fn().mockResolvedValue(null),
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn().mockResolvedValue({ id: "product-1" }),
      },
      tax: { findFirst: jest.fn() },
      warehouse: { findMany: jest.fn(), findFirst: jest.fn() },
      warehouseStock: { upsert: jest.fn() },
      saleItem: { count: jest.fn().mockResolvedValue(0) },
      cotizacionItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      websiteProductOverride: { count: jest.fn().mockResolvedValue(0) },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const inventory = {
      increaseStockInTransaction: jest.fn().mockResolvedValue({}),
    };
    const service = buildService(prisma, inventory);

    await service.create(userA as never, {
      nombre: "Producto sin modulo inventario",
      precio: 250,
      costo: 100,
      stock: 7,
      categoria: "General",
      itemType: "PRODUCT",
      trackInventory: true,
    });

    expect(tx.company.findUnique).toHaveBeenCalledWith({
      where: { id: companyA },
      select: { inventoryEnabled: true },
    });
    expect(tx.product.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        companyId: companyA,
        itemType: "PRODUCT",
        trackInventory: false,
        stock: new Prisma.Decimal(0),
      }),
    });
    expect(tx.warehouse.findMany).not.toHaveBeenCalled();
    expect(tx.warehouseStock.upsert).not.toHaveBeenCalled();
    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
  });

  it("allows classification changes only while product has no stock or history", async () => {
    const tx = {
      product: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: "product-1",
            stock: new Prisma.Decimal("0"),
            itemType: "PRODUCT",
            trackInventory: true,
            unitOfMeasureId: "UNIT",
            unitOfMeasure: null,
          })
          .mockResolvedValueOnce({ stock: new Prisma.Decimal("0") })
          .mockResolvedValueOnce({ id: "product-1" }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      warehouseStock: { count: jest.fn().mockResolvedValue(0) },
      inventoryMovement: { count: jest.fn().mockResolvedValue(0) },
      saleItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      warehouseTransferItem: { count: jest.fn().mockResolvedValue(0) },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);

    await service.update(userA as never, "product-1", {
      nombre: "Instalacion",
      itemType: "SERVICE",
      trackInventory: true,
    });

    expect(tx.product.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          itemType: "SERVICE",
          trackInventory: false,
        }),
      }),
    );
  });

  it("forces stale inventory-tracked product off on update when company inventory is disabled without touching stock", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({ inventoryEnabled: false }),
      },
      product: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: "product-1",
            stock: new Prisma.Decimal("15"),
            itemType: "PRODUCT",
            trackInventory: true,
            unitOfMeasureId: "UNIT",
            unitOfMeasure: null,
          })
          .mockResolvedValueOnce({ id: "product-1" }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      warehouseStock: { count: jest.fn() },
      inventoryMovement: { count: jest.fn() },
      saleItem: { count: jest.fn() },
      purchaseOrderItem: { count: jest.fn() },
      warehouseTransferItem: { count: jest.fn() },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);

    await service.update(userA as never, "product-1", {
      nombre: "Metadata segura",
      stock: 999,
      trackInventory: true,
    });

    expect(tx.product.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "product-1", companyId: companyA, archivedAt: null },
        data: expect.objectContaining({
          nombre: "Metadata segura",
          trackInventory: false,
        }),
      }),
    );
    expect(tx.product.updateMany.mock.calls[0][0].data.stock).toBeUndefined();
    expect(tx.warehouseStock.count).not.toHaveBeenCalled();
    expect(tx.inventoryMovement.count).not.toHaveBeenCalled();
  });

  it("preserves canonical R2 image identity when editing only price", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            allowDecimals: false,
            precision: 0,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await service.update(userA as never, "product-1", { precio: 125 });

    expect(tx.product.updateMany.mock.calls[0][0].data).toEqual(
      expect.not.objectContaining({
        imagen: expect.anything(),
        imageKey: expect.anything(),
        imageStorageProvider: expect.anything(),
      }),
    );
  });

  it("preserves canonical R2 image identity when toggling EXEMPT", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            allowDecimals: false,
            precision: 0,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      company: {
        findUnique: jest.fn().mockResolvedValue({ taxEnabled: true }),
      },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await service.update(userA as never, "product-1", {
      taxTreatment: "EXEMPT",
      taxRate: null,
      taxPriceMode: null,
    } as never);

    expect(tx.product.updateMany.mock.calls[0][0].data).toEqual(
      expect.objectContaining({
        taxTreatment: "EXEMPT",
        taxRate: null,
        taxPriceMode: null,
      }),
    );
    expect(
      tx.product.updateMany.mock.calls[0][0].data.imageKey,
    ).toBeUndefined();
  });

  it("preserves canonical R2 image identity when editing category", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            allowDecimals: false,
            precision: 0,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await service.update(userA as never, "product-1", {
      categoria: "Nueva categoria",
    });

    expect(tx.product.updateMany.mock.calls[0][0].data.categoria).toBe(
      "Nueva categoria",
    );
    expect(
      tx.product.updateMany.mock.calls[0][0].data.imageKey,
    ).toBeUndefined();
  });

  it("does not persist /media/products URLs as image identity", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            allowDecimals: false,
            precision: 0,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await service.update(userA as never, "product-1", {
      fotoUrl: "/media/products/product-1",
    });

    expect(tx.product.updateMany).not.toHaveBeenCalled();
  });

  it("replaces image identity only when a new R2 key is provided", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            allowDecimals: false,
            precision: 0,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });
    const imageKey = `uploads/companies/${companyA}/products/images/user-a/2026/09/new.png`;

    await service.update(userA as never, "product-1", { imageKey });

    expect(tx.product.updateMany.mock.calls[0][0].data).toEqual(
      expect.objectContaining({
        imageKey,
        imageStorageProvider: "r2",
        imagen: `/media/object?key=${encodeURIComponent(imageKey)}`,
      }),
    );
  });

  it("blocks replacing a product image with another tenant object key", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            allowDecimals: false,
            precision: 0,
          },
        }),
        updateMany: jest.fn(),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await expect(
      service.update(userA as never, "product-1", {
        imageKey: `uploads/companies/${companyB}/products/images/user-b/file.png`,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.product.updateMany).not.toHaveBeenCalled();
  });

  it("removes image identity only on explicit null", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("15"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: {
            id: "UNIT",
            code: "UNIT",
            name: "Unidad",
            symbol: "u",
            allowDecimals: false,
            precision: 0,
          },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);
    jest.spyOn(service, "findOne").mockResolvedValue({ id: "product-1" });

    await service.update(userA as never, "product-1", {
      fotoUrl: null,
      imageKey: null,
    } as never);

    expect(tx.product.updateMany.mock.calls[0][0].data).toEqual(
      expect.objectContaining({
        imagen: null,
        imageKey: null,
        imageStorageProvider: null,
        imageMimeType: null,
        imageOriginalFileName: null,
        imageUpdatedAt: null,
      }),
    );
  });

  it("blocks classification changes when stock or history exists", async () => {
    const tx = {
      product: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: "product-1",
            stock: new Prisma.Decimal("0"),
            itemType: "PRODUCT",
            trackInventory: true,
            unitOfMeasureId: "UNIT",
            unitOfMeasure: null,
          })
          .mockResolvedValueOnce({ stock: new Prisma.Decimal("0") }),
        updateMany: jest.fn(),
      },
      warehouseStock: { count: jest.fn().mockResolvedValue(0) },
      inventoryMovement: { count: jest.fn().mockResolvedValue(1) },
      saleItem: { count: jest.fn().mockResolvedValue(0) },
      purchaseOrderItem: { count: jest.fn().mockResolvedValue(0) },
      warehouseTransferItem: { count: jest.fn().mockResolvedValue(0) },
    };
    const prisma = {
      product: { findFirst: jest.fn().mockResolvedValue({ id: "product-1" }) },
      $transaction: jest.fn((fn) => fn(tx)),
    };
    const service = buildService(prisma);

    await expect(
      service.update(userA as never, "product-1", {
        itemType: "SERVICE",
        trackInventory: false,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.product.updateMany).not.toHaveBeenCalled();
  });

  it("rejects stock adjustment for services and non-inventory products", async () => {
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "service-1",
          stock: new Prisma.Decimal("0"),
          itemType: "SERVICE",
          trackInventory: false,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: null,
        }),
      },
      warehouse: { findMany: jest.fn(), findFirst: jest.fn() },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const service = buildService(prisma);

    await expect(
      service.adjustStock(userA as never, "service-1", { stock: 1 }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.warehouse.findMany).not.toHaveBeenCalled();
  });

  it("rejects stock adjustment when inventory control is disabled", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({ inventoryEnabled: false }),
      },
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          stock: new Prisma.Decimal("5"),
          itemType: "PRODUCT",
          trackInventory: true,
          unitOfMeasureId: "UNIT",
          unitOfMeasure: null,
        }),
      },
      warehouse: { findMany: jest.fn(), findFirst: jest.fn() },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const service = buildService(prisma);

    await expect(
      service.adjustStock(userA as never, "product-1", { delta: 1 }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.warehouse.findMany).not.toHaveBeenCalled();
  });

  it("checks product quota before reactivating an archived product", async () => {
    const licenses = {
      assertCanCreateProduct: jest.fn().mockResolvedValue(undefined),
      assertCanCreateProductInTransaction: jest.fn().mockResolvedValue(undefined),
    };
    const tx = {
      product: {
        findFirst: jest.fn().mockResolvedValue({
          id: "product-1",
          archivedAt: new Date("2026-08-01T00:00:00Z"),
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = { $transaction: jest.fn((fn) => fn(tx)) };
    const service = buildService(prisma, {}, licenses);

    await expect(
      service.reactivate(userA as never, "product-1"),
    ).resolves.toMatchObject({ ok: true, archived: false });
    expect(licenses.assertCanCreateProductInTransaction).toHaveBeenCalledWith(
      tx,
      companyA,
    );
    expect(tx.product.updateMany).toHaveBeenCalledWith({
      where: { id: "product-1", companyId: companyA, archivedAt: { not: null } },
      data: { archivedAt: null },
    });
  });
});
