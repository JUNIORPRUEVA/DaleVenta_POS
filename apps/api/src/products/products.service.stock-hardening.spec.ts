import { BadRequestException, NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { ProductsService } from "./products.service";

const companyA = "11111111-1111-1111-1111-111111111111";
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
) {
  const service = new ProductsService(
    prisma as never,
    {} as never,
    { resolveForCompany: jest.fn(async () => sourceContext()) } as never,
    { get: jest.fn(() => "") } as unknown as ConfigService,
    { assertCanCreateProduct: jest.fn().mockResolvedValue(undefined) } as never,
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
});
