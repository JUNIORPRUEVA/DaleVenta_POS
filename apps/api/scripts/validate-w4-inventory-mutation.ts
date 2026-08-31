import {
  InventoryMovementType,
  Prisma,
  PrismaClient,
  ProductSource,
} from "@prisma/client";
import { InventoryMutationService } from "../src/inventory/inventory-mutation.service";

const prisma = new PrismaClient();
const service = new InventoryMutationService(prisma as any);
const marker = "w4-ledger-fixture";

const d = (value: Prisma.Decimal.Value) => new Prisma.Decimal(value);

async function createCompany(slug: string, productSource?: ProductSource) {
  return prisma.company.create({
    data: { name: slug, slug, productSource: productSource ?? null },
  });
}

async function createProduct(companyId: string, name: string, stock: string) {
  return prisma.product.create({
    data: {
      companyId,
      nombre: name,
      categoria: "W4",
      costo: d(1),
      precio: d(2),
      stock: d(stock),
      unitOfMeasureId: "YARD",
    },
  });
}

async function createWarehouse(companyId: string, code = "MAIN") {
  return prisma.warehouse.create({
    data: {
      companyId,
      name: code,
      code,
      isDefault: code === "MAIN",
      isActive: true,
    },
  });
}

async function createStock(
  companyId: string,
  warehouseId: string,
  productId: string,
  quantity: string,
) {
  return prisma.warehouseStock.create({
    data: { companyId, warehouseId, productId, quantity: d(quantity) },
  });
}

async function stockState(
  companyId: string,
  productId: string,
  warehouseId: string,
) {
  const product = await prisma.product.findFirstOrThrow({
    where: { id: productId, companyId },
    select: { stock: true },
  });
  const stock = await prisma.warehouseStock.findFirstOrThrow({
    where: { companyId, productId, warehouseId },
    select: { quantity: true },
  });
  const movements = await prisma.inventoryMovement.count({
    where: { companyId, productId, warehouseId },
  });
  return {
    product: product.stock.toFixed(6),
    warehouse: stock.quantity.toFixed(6),
    movements,
  };
}

async function main() {
  const slugs = [
    `${marker}-a`,
    `${marker}-b`,
    `${marker}-fullpos`,
    `${marker}-concurrent`,
    `${marker}-counted`,
  ];
  await prisma.company.deleteMany({ where: { slug: { in: slugs } } });

  try {
    const companyA = await createCompany(slugs[0]);
    const companyB = await createCompany(slugs[1]);
    const fullposCompany = await createCompany(slugs[2], ProductSource.FULLPOS);
    const warehouseA = await createWarehouse(companyA.id);
    const warehouseB = await createWarehouse(companyB.id);
    const fullposWarehouse = await createWarehouse(fullposCompany.id);
    const productA = await createProduct(companyA.id, "W4 Decimal Product", "10");
    const productB = await createProduct(companyB.id, "W4 Other Product", "5");
    const fullposProduct = await createProduct(
      fullposCompany.id,
      "W4 Fullpos Product",
      "10",
    );

    await createStock(companyA.id, warehouseA.id, productA.id, "10");
    await createStock(companyB.id, warehouseB.id, productB.id, "5");
    await createStock(
      fullposCompany.id,
      fullposWarehouse.id,
      fullposProduct.id,
      "10",
    );

    const increase = await service.increaseStock({
      companyId: companyA.id,
      warehouseId: warehouseA.id,
      productId: productA.id,
      quantity: "2.5",
      type: InventoryMovementType.ADJUSTMENT_IN,
      reason: "W4 increase",
    });
    const decrease = await service.decreaseStock({
      companyId: companyA.id,
      warehouseId: warehouseA.id,
      productId: productA.id,
      quantity: "3",
      type: InventoryMovementType.ADJUSTMENT_OUT,
      reason: "W4 decrease",
    });

    let insufficientStock = false;
    try {
      await service.decreaseStock({
        companyId: companyA.id,
        warehouseId: warehouseA.id,
        productId: productA.id,
        quantity: "999",
        type: InventoryMovementType.ADJUSTMENT_OUT,
      });
    } catch {
      insufficientStock = true;
    }

    const beforeRollback = await stockState(
      companyA.id,
      productA.id,
      warehouseA.id,
    );
    let movementFailureRolledBack = false;
    try {
      await service.increaseStock({
        companyId: companyA.id,
        warehouseId: warehouseA.id,
        productId: productA.id,
        quantity: "1",
        type: InventoryMovementType.ADJUSTMENT_IN,
        createdByUserId: "99999999-9999-4999-8999-999999999999",
      });
    } catch {
      const afterRollback = await stockState(
        companyA.id,
        productA.id,
        warehouseA.id,
      );
      movementFailureRolledBack =
        JSON.stringify(beforeRollback) === JSON.stringify(afterRollback);
    }

    const counted = await service.setCountedStock({
      companyId: companyA.id,
      warehouseId: warehouseA.id,
      productId: productA.id,
      expectedCurrentQuantity: "9.5",
      countedQuantity: "7",
      reason: "W4 counted",
    });

    let crossCompanyProductRejected = false;
    try {
      await service.increaseStock({
        companyId: companyA.id,
        warehouseId: warehouseA.id,
        productId: productB.id,
        quantity: "1",
        type: InventoryMovementType.ADJUSTMENT_IN,
      });
    } catch {
      crossCompanyProductRejected = true;
    }

    let crossCompanyWarehouseRejected = false;
    try {
      await service.increaseStock({
        companyId: companyA.id,
        warehouseId: warehouseB.id,
        productId: productA.id,
        quantity: "1",
        type: InventoryMovementType.ADJUSTMENT_IN,
      });
    } catch {
      crossCompanyWarehouseRejected = true;
    }

    let fullposRejected = false;
    try {
      await service.increaseStock({
        companyId: fullposCompany.id,
        warehouseId: fullposWarehouse.id,
        productId: fullposProduct.id,
        quantity: "1",
        type: InventoryMovementType.ADJUSTMENT_IN,
      });
    } catch {
      fullposRejected = true;
    }

    const concurrentCompany = await createCompany(slugs[3]);
    const concurrentWarehouse = await createWarehouse(concurrentCompany.id);
    const concurrentProduct = await createProduct(
      concurrentCompany.id,
      "W4 Last Unit",
      "1",
    );
    await createStock(
      concurrentCompany.id,
      concurrentWarehouse.id,
      concurrentProduct.id,
      "1",
    );
    const lastUnit = await Promise.allSettled([
      service.decreaseStock({
        companyId: concurrentCompany.id,
        warehouseId: concurrentWarehouse.id,
        productId: concurrentProduct.id,
        quantity: "1",
        type: InventoryMovementType.ADJUSTMENT_OUT,
      }),
      service.decreaseStock({
        companyId: concurrentCompany.id,
        warehouseId: concurrentWarehouse.id,
        productId: concurrentProduct.id,
        quantity: "1",
        type: InventoryMovementType.ADJUSTMENT_OUT,
      }),
    ]);
    const lastUnitState = await stockState(
      concurrentCompany.id,
      concurrentProduct.id,
      concurrentWarehouse.id,
    );

    const countedCompany = await createCompany(slugs[4]);
    const countedWarehouse = await createWarehouse(countedCompany.id);
    const countedProduct = await createProduct(
      countedCompany.id,
      "W4 Count Conflict",
      "5",
    );
    await createStock(
      countedCompany.id,
      countedWarehouse.id,
      countedProduct.id,
      "5",
    );
    const countedConflict = await Promise.allSettled([
      service.setCountedStock({
        companyId: countedCompany.id,
        warehouseId: countedWarehouse.id,
        productId: countedProduct.id,
        expectedCurrentQuantity: "5",
        countedQuantity: "4",
      }),
      service.setCountedStock({
        companyId: countedCompany.id,
        warehouseId: countedWarehouse.id,
        productId: countedProduct.id,
        expectedCurrentQuantity: "5",
        countedQuantity: "3",
      }),
    ]);
    const countedConflictState = await stockState(
      countedCompany.id,
      countedProduct.id,
      countedWarehouse.id,
    );

    const decimalProduct = await createProduct(companyA.id, "W4 Decimal 0.125", "0");
    await createStock(companyA.id, warehouseA.id, decimalProduct.id, "0");
    await service.increaseStock({
      companyId: companyA.id,
      warehouseId: warehouseA.id,
      productId: decimalProduct.id,
      quantity: "0.125",
      type: InventoryMovementType.ADJUSTMENT_IN,
    });
    const decimalState = await stockState(
      companyA.id,
      decimalProduct.id,
      warehouseA.id,
    );

    console.log(
      JSON.stringify(
        {
          increase: {
            previous: increase.previousQuantity.toFixed(6),
            result: increase.resultingQuantity.toFixed(6),
          },
          decrease: {
            previous: decrease.previousQuantity.toFixed(6),
            result: decrease.resultingQuantity.toFixed(6),
          },
          counted: {
            delta: counted.quantityDelta.toFixed(6),
            result: counted.resultingQuantity.toFixed(6),
          },
          insufficientStock,
          movementFailureRolledBack,
          crossCompanyProductRejected,
          crossCompanyWarehouseRejected,
          fullposRejected,
          concurrentLastUnit: {
            fulfilled: lastUnit.filter((result) => result.status === "fulfilled")
              .length,
            rejected: lastUnit.filter((result) => result.status === "rejected")
              .length,
            ...lastUnitState,
          },
          concurrentCountedStock: {
            fulfilled: countedConflict.filter(
              (result) => result.status === "fulfilled",
            ).length,
            rejected: countedConflict.filter(
              (result) => result.status === "rejected",
            ).length,
            ...countedConflictState,
          },
          decimal0125: decimalState,
        },
        null,
        2,
      ),
    );
  } finally {
    await prisma.company.deleteMany({ where: { slug: { in: slugs } } });
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
