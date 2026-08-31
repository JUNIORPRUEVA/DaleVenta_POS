import {
  InventoryMovementType,
  Prisma,
  PrismaClient,
  ProductSource,
  PurchaseOrderStatus,
  Role,
} from "@prisma/client";
import { InventoryMutationService } from "../src/inventory/inventory-mutation.service";
import { PurchasesService } from "../src/purchases/purchases.service";

const prisma = new PrismaClient();
const marker = "w6-purchase-fixture";
const d = (value: Prisma.Decimal.Value) => new Prisma.Decimal(value);

const service = new PurchasesService(
  prisma as any,
  { get: () => "" } as any,
  {} as any,
  new InventoryMutationService(prisma as any),
);

async function createCompany(slug: string, source?: ProductSource) {
  return prisma.company.create({
    data: { name: slug, slug, productSource: source ?? null },
  });
}

async function createUser(companyId: string, email: string) {
  return prisma.user.create({
    data: {
      companyId,
      email,
      passwordHash: "w6-validation",
      nombreCompleto: "W6 Validator",
      telefono: "000",
      edad: 30,
      role: Role.ADMIN,
    },
  });
}

async function createProduct(companyId: string, name: string, stock: string) {
  return prisma.product.create({
    data: {
      companyId,
      nombre: name,
      categoria: "W6",
      costo: d(1),
      precio: d(2),
      stock: d(stock),
      unitOfMeasureId: "YARD",
    },
  });
}

async function createWarehouse(companyId: string, code: string, isDefault = false) {
  return prisma.warehouse.create({
    data: { companyId, name: code, code, isDefault, isActive: true },
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

async function createOrder(input: {
  companyId: string;
  userId: string;
  productId?: string | null;
  productSource?: ProductSource | null;
  sourceProductId?: string | null;
  name: string;
  quantity: string;
  createInventoryProductOnReceipt?: boolean;
}) {
  const quantity = d(input.quantity);
  return prisma.purchaseOrder.create({
    data: {
      companyId: input.companyId,
      orderNumber: `${marker}-${Date.now()}-${Math.random()}`,
      status: PurchaseOrderStatus.APPROVED,
      subtotal: quantity.mul(2).toDecimalPlaces(2),
      total: quantity.mul(2).toDecimalPlaces(2),
      createdById: input.userId,
      items: {
        create: {
          productId: input.productId ?? null,
          productSource:
            input.productSource ?? (input.productId ? ProductSource.LOCAL : null),
          sourceProductId: input.sourceProductId ?? input.productId ?? null,
          productNameSnapshot: input.name,
          quantity,
          receivedQuantity: d(0),
          pendingQuantity: quantity,
          unitCodeSnapshot: "YARD",
          unitNameSnapshot: "Yarda",
          unitSymbolSnapshot: "yd",
          unitPrecisionSnapshot: 3,
          unitCost: d(2),
          subtotal: quantity.mul(2).toDecimalPlaces(2),
          createInventoryProductOnReceipt: Boolean(
            input.createInventoryProductOnReceipt,
          ),
        },
      },
    },
    include: { items: true },
  });
}

async function productState(companyId: string, productId: string, warehouseId: string) {
  const product = await prisma.product.findFirstOrThrow({
    where: { id: productId, companyId },
    select: { stock: true },
  });
  const stock = await prisma.warehouseStock.findFirstOrThrow({
    where: { companyId, productId, warehouseId },
    select: { quantity: true },
  });
  const movements = await prisma.inventoryMovement.findMany({
    where: { companyId, productId, warehouseId },
    orderBy: { createdAt: "asc" },
    select: {
      type: true,
      quantityDelta: true,
      sourceType: true,
      sourceId: true,
      sourceItemId: true,
      reason: true,
    },
  });
  return {
    product: product.stock.toFixed(6),
    warehouse: stock.quantity.toFixed(6),
    movements: movements.map((movement) => ({
      ...movement,
      quantityDelta: movement.quantityDelta.toFixed(6),
    })),
  };
}

async function cleanup(slugs: string[]) {
  const companies = await prisma.company.findMany({
    where: { slug: { in: slugs } },
    select: { id: true },
  });
  const companyIds = companies.map((company) => company.id);
  if (companyIds.length) {
    const orders = await prisma.purchaseOrder.findMany({
      where: { companyId: { in: companyIds } },
      select: { id: true },
    });
    const orderIds = orders.map((order) => order.id);
    const orderItems = orderIds.length
      ? await prisma.purchaseOrderItem.findMany({
          where: { purchaseOrderId: { in: orderIds } },
          select: { id: true },
        })
      : [];
    const orderItemIds = orderItems.map((item) => item.id);
    const receipts = orderIds.length
      ? await prisma.purchaseReceipt.findMany({
          where: { purchaseOrderId: { in: orderIds } },
          select: { id: true },
        })
      : [];
    const receiptIds = receipts.map((receipt) => receipt.id);

    const receiptItemWhere = [
      receiptIds.length ? { purchaseReceiptId: { in: receiptIds } } : null,
      orderItemIds.length ? { purchaseOrderItemId: { in: orderItemIds } } : null,
    ].filter(
      (
        where,
      ): where is
        | { purchaseReceiptId: { in: string[] } }
        | { purchaseOrderItemId: { in: string[] } } => Boolean(where),
    );
    if (receiptItemWhere.length) {
      await prisma.purchaseReceiptItem.deleteMany({
        where: { OR: receiptItemWhere },
      });
    }
    await prisma.purchaseReceipt.deleteMany({
      where: { purchaseOrderId: { in: orderIds } },
    });
    await prisma.purchaseOrderItem.deleteMany({
      where: { purchaseOrderId: { in: orderIds } },
    });
    await prisma.purchaseOrder.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.inventoryMovement.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.warehouseStock.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.terminal.deleteMany({ where: { companyId: { in: companyIds } } });
    await prisma.warehouse.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.product.deleteMany({ where: { companyId: { in: companyIds } } });
  }
  await prisma.company.deleteMany({ where: { slug: { in: slugs } } });
  await prisma.user.deleteMany({
    where: { email: { in: slugs.map((slug) => `${slug}@example.com`) } },
  });
}

async function main() {
  const slugs = [
    `${marker}-main`,
    `${marker}-explicit`,
    `${marker}-tenant`,
    `${marker}-concurrent`,
    `${marker}-new`,
    `${marker}-fullpos`,
    `${marker}-rollback`,
  ];
  await cleanup(slugs);

  try {
    const company = await createCompany(slugs[0]);
    const user = await createUser(company.id, `${slugs[0]}@example.com`);
    const mainWarehouse = await createWarehouse(company.id, "MAIN", true);
    const product = await createProduct(company.id, "W6 Main Product", "10");
    await createStock(company.id, mainWarehouse.id, product.id, "10");
    const order = await createOrder({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      name: "W6 Main Product",
      quantity: "14.5",
    });
    const beforeOrderStock = await productState(
      company.id,
      product.id,
      mainWarehouse.id,
    );
    const receipt = await service.receiveOrder(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      order.id,
      {
        clientRequestId: "normal-receipt",
        updateInventory: true,
        items: [
          {
            purchaseOrderItemId: order.items[0].id,
            quantityReceived: 7.625,
            unitCost: 2,
          },
        ],
      },
    );
    const duplicate = await service.receiveOrder(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      order.id,
      {
        clientRequestId: "normal-receipt",
        updateInventory: true,
        items: [
          {
            purchaseOrderItemId: order.items[0].id,
            quantityReceived: 7.625,
            unitCost: 2,
          },
        ],
      },
    );
    await service.receiveOrder(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      order.id,
      {
        clientRequestId: "second-partial",
        updateInventory: true,
        items: [
          {
            purchaseOrderItemId: order.items[0].id,
            quantityReceived: 6.875,
            unitCost: 2,
          },
        ],
      },
    );
    const mainState = await productState(company.id, product.id, mainWarehouse.id);

    const noInventoryOrder = await createOrder({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      name: "W6 No Inventory",
      quantity: "0.125",
    });
    await service.receiveOrder(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      noInventoryOrder.id,
      {
        clientRequestId: "no-inventory",
        updateInventory: false,
        items: [
          {
            purchaseOrderItemId: noInventoryOrder.items[0].id,
            quantityReceived: 0.125,
            unitCost: 2,
          },
        ],
      },
    );
    const noInventoryState = await productState(
      company.id,
      product.id,
      mainWarehouse.id,
    );

    const explicitCompany = await createCompany(slugs[1]);
    const explicitUser = await createUser(
      explicitCompany.id,
      `${slugs[1]}@example.com`,
    );
    const explicitMain = await createWarehouse(explicitCompany.id, "MAIN", true);
    const explicitBranch = await createWarehouse(explicitCompany.id, "BRANCH");
    const explicitProduct = await createProduct(
      explicitCompany.id,
      "W6 Explicit Product",
      "50.75",
    );
    await createStock(explicitCompany.id, explicitMain.id, explicitProduct.id, "50.75");
    await createStock(explicitCompany.id, explicitBranch.id, explicitProduct.id, "0");
    const explicitOrder = await createOrder({
      companyId: explicitCompany.id,
      userId: explicitUser.id,
      productId: explicitProduct.id,
      name: "W6 Explicit Product",
      quantity: "50.75",
    });
    const explicitReceipt = await service.receiveOrder(
      { id: explicitUser.id, companyId: explicitCompany.id, role: Role.ADMIN },
      explicitOrder.id,
      {
        warehouseId: explicitBranch.id,
        clientRequestId: "explicit",
        updateInventory: true,
        items: [
          {
            purchaseOrderItemId: explicitOrder.items[0].id,
            quantityReceived: 50.75,
            unitCost: 2,
          },
        ],
      },
    );
    const explicitState = await productState(
      explicitCompany.id,
      explicitProduct.id,
      explicitBranch.id,
    );

    const tenantCompany = await createCompany(slugs[2]);
    const tenantWarehouse = await createWarehouse(tenantCompany.id, "MAIN", true);
    const crossWarehouseRejected = await service
      .receiveOrder(
        { id: user.id, companyId: company.id, role: Role.ADMIN },
        noInventoryOrder.id,
        {
          warehouseId: tenantWarehouse.id,
          clientRequestId: "cross-warehouse",
          updateInventory: true,
          items: [
            {
              purchaseOrderItemId: noInventoryOrder.items[0].id,
              quantityReceived: 0.001,
              unitCost: 2,
            },
          ],
        },
      )
      .then(
        () => false,
        () => true,
      );

    const concurrentCompany = await createCompany(slugs[3]);
    const concurrentUser = await createUser(
      concurrentCompany.id,
      `${slugs[3]}@example.com`,
    );
    const concurrentWarehouse = await createWarehouse(
      concurrentCompany.id,
      "MAIN",
      true,
    );
    const concurrentProduct = await createProduct(
      concurrentCompany.id,
      "W6 Concurrent Product",
      "0",
    );
    await createStock(
      concurrentCompany.id,
      concurrentWarehouse.id,
      concurrentProduct.id,
      "0",
    );
    const concurrentOrder = await createOrder({
      companyId: concurrentCompany.id,
      userId: concurrentUser.id,
      productId: concurrentProduct.id,
      name: "W6 Concurrent Product",
      quantity: "5",
    });
    const concurrent = await Promise.allSettled([
      service.receiveOrder(
        {
          id: concurrentUser.id,
          companyId: concurrentCompany.id,
          role: Role.ADMIN,
        },
        concurrentOrder.id,
        {
          clientRequestId: "concurrent-a",
          updateInventory: true,
          items: [
            {
              purchaseOrderItemId: concurrentOrder.items[0].id,
              quantityReceived: 5,
              unitCost: 2,
            },
          ],
        },
      ),
      service.receiveOrder(
        {
          id: concurrentUser.id,
          companyId: concurrentCompany.id,
          role: Role.ADMIN,
        },
        concurrentOrder.id,
        {
          clientRequestId: "concurrent-b",
          updateInventory: true,
          items: [
            {
              purchaseOrderItemId: concurrentOrder.items[0].id,
              quantityReceived: 5,
              unitCost: 2,
            },
          ],
        },
      ),
    ]);
    const concurrentState = await productState(
      concurrentCompany.id,
      concurrentProduct.id,
      concurrentWarehouse.id,
    );

    const newProductCompany = await createCompany(slugs[4]);
    const newProductUser = await createUser(
      newProductCompany.id,
      `${slugs[4]}@example.com`,
    );
    const newProductWarehouse = await createWarehouse(
      newProductCompany.id,
      "MAIN",
      true,
    );
    const newProductOrder = await createOrder({
      companyId: newProductCompany.id,
      userId: newProductUser.id,
      productId: null,
      productSource: null,
      name: "W6 Created Product",
      quantity: "0.125",
      createInventoryProductOnReceipt: true,
    });
    await service.receiveOrder(
      { id: newProductUser.id, companyId: newProductCompany.id, role: Role.ADMIN },
      newProductOrder.id,
      {
        updateInventory: true,
        clientRequestId: "new-product",
        items: [
          {
            purchaseOrderItemId: newProductOrder.items[0].id,
            quantityReceived: 0.125,
            unitCost: 2,
          },
        ],
      },
    );
    const newOrderItem = await prisma.purchaseOrderItem.findUniqueOrThrow({
      where: { id: newProductOrder.items[0].id },
      select: { productId: true },
    });
    const newProductState = await productState(
      newProductCompany.id,
      newOrderItem.productId!,
      newProductWarehouse.id,
    );

    const fullposCompany = await createCompany(slugs[5], ProductSource.FULLPOS);
    const fullposUser = await createUser(
      fullposCompany.id,
      `${slugs[5]}@example.com`,
    );
    await createWarehouse(fullposCompany.id, "MAIN", true);
    const fullposOrder = await createOrder({
      companyId: fullposCompany.id,
      userId: fullposUser.id,
      productId: null,
      productSource: ProductSource.FULLPOS,
      sourceProductId: "remote-product",
      name: "W6 Fullpos Product",
      quantity: "1",
    });
    const fullposRejected = await service
      .receiveOrder(
        { id: fullposUser.id, companyId: fullposCompany.id, role: Role.ADMIN },
        fullposOrder.id,
        {
          updateInventory: true,
          items: [
            {
              purchaseOrderItemId: fullposOrder.items[0].id,
              quantityReceived: 1,
              unitCost: 2,
            },
          ],
        },
      )
      .then(
        () => false,
        () => true,
      );

    const rollbackCompany = await createCompany(slugs[6]);
    const rollbackUser = await createUser(
      rollbackCompany.id,
      `${slugs[6]}@example.com`,
    );
    const rollbackWarehouse = await createWarehouse(rollbackCompany.id, "MAIN", true);
    const rollbackProduct = await createProduct(
      rollbackCompany.id,
      "W6 Rollback Product",
      "10",
    );
    await createStock(rollbackCompany.id, rollbackWarehouse.id, rollbackProduct.id, "9");
    const rollbackOrder = await createOrder({
      companyId: rollbackCompany.id,
      userId: rollbackUser.id,
      productId: rollbackProduct.id,
      name: "W6 Rollback Product",
      quantity: "1",
    });
    const driftRejected = await service
      .receiveOrder(
        { id: rollbackUser.id, companyId: rollbackCompany.id, role: Role.ADMIN },
        rollbackOrder.id,
        {
          updateInventory: true,
          items: [
            {
              purchaseOrderItemId: rollbackOrder.items[0].id,
              quantityReceived: 1,
              unitCost: 2,
            },
          ],
        },
      )
      .then(
        () => false,
        () => true,
      );
    const rollbackReceiptCount = await prisma.purchaseReceipt.count({
      where: { purchaseOrderId: rollbackOrder.id },
    });
    const rollbackMovementCount = await prisma.inventoryMovement.count({
      where: { companyId: rollbackCompany.id },
    });

    console.log(
      JSON.stringify(
        {
          orderDoesNotMutateStock: beforeOrderStock,
          normalReceipt: {
            receiptId: receipt.receipt.id,
            duplicateSameReceipt: duplicate.receipt.id === receipt.receipt.id,
            receiptItemWarehouseCode:
              receipt.receipt.items[0]?.warehouseCodeSnapshot,
            state: mainState,
            movementSourceItemMatches:
              mainState.movements[0]?.sourceItemId ===
              receipt.receipt.items[0]?.id,
            noInventoryDidNotMutate:
              JSON.stringify(noInventoryState) === JSON.stringify(mainState),
          },
          explicitWarehouse: {
            receiptItemWarehouseCode:
              explicitReceipt.receipt.items[0]?.warehouseCodeSnapshot,
            state: explicitState,
          },
          tenantSecurity: { crossWarehouseRejected },
          concurrency: {
            fulfilled: concurrent.filter((result) => result.status === "fulfilled")
              .length,
            rejected: concurrent.filter((result) => result.status === "rejected")
              .length,
            state: concurrentState,
          },
          newProductDuringReceipt: {
            productId: newOrderItem.productId,
            state: newProductState,
          },
          fullposHandling: { fullposRejected },
          rollback: {
            driftRejected,
            rollbackReceiptCount,
            rollbackMovementCount,
          },
        },
        null,
        2,
      ),
    );
  } finally {
    await cleanup(slugs);
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
