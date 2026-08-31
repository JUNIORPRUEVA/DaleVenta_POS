import { BadRequestException, ConflictException } from "@nestjs/common";
import { InventoryMovementType, Prisma, ProductSource } from "@prisma/client";
import { InventoryMutationService } from "./inventory-mutation.service";

function decimal(value: Prisma.Decimal.Value) {
  return new Prisma.Decimal(value);
}

function buildService(options: {
  companyProductSource?: ProductSource | null;
  warehouseActive?: boolean;
  stockRows?: Array<{ previous_quantity: string; resulting_quantity: string }>;
  initialProductStock?: Prisma.Decimal.Value;
  warehouseTotal?: Prisma.Decimal.Value;
  movementCreateError?: Error;
  currentWarehouseQuantity?: Prisma.Decimal.Value;
} = {}) {
  const productStock = decimal(options.initialProductStock ?? "10");
  const warehouseTotal = decimal(options.warehouseTotal ?? productStock);
  const tx: any = {
    product: {
      findFirst: jest.fn(async () => ({
        id: "product-a",
        stock: productStock,
        company: { productSource: options.companyProductSource ?? null },
        unitOfMeasure: {
          code: "YARD",
          name: "Yarda",
          symbol: "yd",
          precision: 3,
          allowDecimals: true,
        },
      })),
      updateMany: jest.fn(async () => ({ count: 1 })),
      findFirstOrThrow: jest.fn(async () => ({ stock: decimal("12.5") })),
    },
    warehouse: {
      findFirst: jest.fn(async () =>
        options.warehouseActive === false
          ? null
          : { id: "warehouse-a", name: "Main Warehouse", code: "MAIN" },
      ),
    },
    warehouseStock: {
      findFirst: jest.fn(async () => ({
        quantity: decimal(options.currentWarehouseQuantity ?? "10"),
      })),
    },
    inventoryMovement: {
      create: jest.fn(async ({ data }) => {
        if (options.movementCreateError) throw options.movementCreateError;
        return { id: "movement-a", ...data };
      }),
    },
    $queryRaw: jest.fn(async () => [
      {
        product_stock: productStock.toString(),
        warehouse_total: warehouseTotal.toString(),
      },
    ]),
  };
  const prisma = {
    $transaction: jest.fn(async (fn) => fn(tx)),
  };
  const service = new InventoryMutationService(prisma as any);
  jest
    .spyOn(service as any, "updateWarehouseStockByDelta")
    .mockResolvedValue(
      options.stockRows ?? [
        { previous_quantity: "10.000000", resulting_quantity: "12.500000" },
      ],
    );
  jest
    .spyOn(service as any, "updateWarehouseStockWithExpectedQuantity")
    .mockResolvedValue(
      options.stockRows ?? [
        { previous_quantity: "10.000000", resulting_quantity: "7.000000" },
      ],
    );
  return { service, tx, prisma };
}

describe("InventoryMutationService", () => {
  const base = {
    companyId: "11111111-1111-4111-8111-111111111111",
    productId: "22222222-2222-4222-8222-222222222222",
    warehouseId: "33333333-3333-4333-8333-333333333333",
    type: InventoryMovementType.ADJUSTMENT_IN,
  };

  it("increases stock and creates an immutable movement payload", async () => {
    const { service, tx } = buildService();

    const result = await service.increaseStock({
      ...base,
      quantity: "2.5",
      reason: "count correction",
    });

    expect(result.previousQuantity.toFixed(6)).toBe("10.000000");
    expect(result.resultingQuantity.toFixed(6)).toBe("12.500000");
    expect(tx.product.updateMany).toHaveBeenCalledWith({
      where: { id: base.productId, companyId: base.companyId },
      data: { stock: { increment: decimal("2.5") } },
    });
    expect(tx.inventoryMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        companyId: base.companyId,
        productId: base.productId,
        warehouseId: base.warehouseId,
        type: InventoryMovementType.ADJUSTMENT_IN,
        quantityDelta: decimal("2.5"),
        previousQuantity: decimal("10.000000"),
        resultingQuantity: decimal("12.500000"),
        unitCodeSnapshot: "YARD",
        unitPrecisionSnapshot: 3,
        reason: "count correction",
      }),
    });
  });

  it("decreases stock with a negative movement delta", async () => {
    const { service, tx } = buildService({
      stockRows: [
        { previous_quantity: "10.000000", resulting_quantity: "7.000000" },
      ],
    });

    await service.decreaseStock({
      ...base,
      type: InventoryMovementType.ADJUSTMENT_OUT,
      quantity: "3",
    });

    expect(tx.product.updateMany).toHaveBeenCalledWith({
      where: { id: base.productId, companyId: base.companyId },
      data: { stock: { increment: decimal("-3") } },
    });
    expect(tx.inventoryMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        quantityDelta: decimal("-3"),
        previousQuantity: decimal("10.000000"),
        resultingQuantity: decimal("7.000000"),
      }),
    });
  });

  it("rejects insufficient stock without product compatibility update", async () => {
    const { service, tx } = buildService({ stockRows: [] });

    await expect(
      service.decreaseStock({
        ...base,
        type: InventoryMovementType.ADJUSTMENT_OUT,
        quantity: "11",
      }),
    ).rejects.toBeInstanceOf(ConflictException);
    await expect(
      service.decreaseStock({
        ...base,
        type: InventoryMovementType.ADJUSTMENT_OUT,
        quantity: "11",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        errorCode: "INSUFFICIENT_WAREHOUSE_STOCK",
        details: expect.objectContaining({
          requestedQuantity: "11.000000",
          availableQuantity: "10.000000",
        }),
      }),
    });
    expect(tx.product.updateMany).not.toHaveBeenCalled();
    expect(tx.inventoryMovement.create).not.toHaveBeenCalled();
  });

  it("rejects pre-existing Product.stock drift", async () => {
    const { service } = buildService({
      initialProductStock: "10",
      warehouseTotal: "9",
    });

    await expect(
      service.increaseStock({ ...base, quantity: "1" }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("rejects cross-company or inactive warehouse targets", async () => {
    const { service } = buildService({ warehouseActive: false });

    await expect(
      service.increaseStock({ ...base, quantity: "1" }),
    ).rejects.toThrow("Almacen activo no encontrado");
  });

  it("rejects FULLPOS companies", async () => {
    const { service } = buildService({
      companyProductSource: ProductSource.FULLPOS,
    });

    await expect(
      service.increaseStock({ ...base, quantity: "1" }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("sets counted stock using expected current quantity", async () => {
    const { service } = buildService({
      stockRows: [
        { previous_quantity: "10.000000", resulting_quantity: "7.000000" },
      ],
    });

    const result = await service.setCountedStock({
      companyId: base.companyId,
      productId: base.productId,
      warehouseId: base.warehouseId,
      countedQuantity: "7",
      expectedCurrentQuantity: "10",
    });

    expect(result.quantityDelta.toFixed(6)).toBe("-3.000000");
  });

  it("does not update Product.stock when movement creation fails", async () => {
    const { service, tx } = buildService({
      movementCreateError: new Error("movement insert failed"),
    });

    await expect(
      service.increaseStock({ ...base, quantity: "1" }),
    ).rejects.toThrow("movement insert failed");
    expect(tx.product.updateMany).toHaveBeenCalledTimes(1);
  });
});
