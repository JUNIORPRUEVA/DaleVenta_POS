import {
  InventoryMovementType,
  Prisma,
  PrismaClient,
  ProductSource,
  Role,
} from "@prisma/client";
import { InventoryMutationService } from "../src/inventory/inventory-mutation.service";
import { SalesService } from "../src/sales/sales.service";

const prisma = new PrismaClient();
const marker = "w7-return-fixture";
const d = (value: Prisma.Decimal.Value) => new Prisma.Decimal(value);

function service() {
  return new SalesService(
    prisma as any,
    { get: () => "" } as any,
    { emitCompany: () => undefined } as any,
    {} as any,
    {} as any,
    new InventoryMutationService(prisma as any),
  );
}

async function cleanup(slugs: string[]) {
  const companies = await prisma.company.findMany({
    where: { slug: { in: slugs } },
    select: { id: true },
  });
  const companyIds = companies.map((company) => company.id);
  if (companyIds.length) {
    await prisma.inventoryMovement.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.sale.deleteMany({ where: { companyId: { in: companyIds } } });
    await prisma.cashSession.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.inventoryZeroConfigState.deleteMany({
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
      passwordHash: "w7-validation",
      nombreCompleto: "W7 Validator",
      telefono: "000",
      edad: 30,
      role: Role.ADMIN,
    },
  });
}

async function createCashSession(companyId: string, userId: string) {
  return prisma.cashSession.create({
    data: {
      companyId,
      openedByUserId: userId,
      userName: "W7 Validator",
      status: "OPEN",
      initialAmount: d(0),
    },
  });
}

async function createWarehouse(companyId: string, code: string, isDefault = false) {
  return prisma.warehouse.create({
    data: { companyId, name: code, code, isDefault, isActive: true },
  });
}

async function createProduct(
  companyId: string,
  unitOfMeasureId: string,
  stock: Prisma.Decimal.Value,
) {
  const product = await prisma.product.create({
    data: {
      companyId,
      nombre: `${marker}-${unitOfMeasureId}`,
      categoria: "W7",
      costo: d(10),
      precio: d(100),
      stock: d(stock),
      unitOfMeasureId,
    },
  });
  return product;
}

async function setWarehouseStock(
  companyId: string,
  warehouseId: string,
  productId: string,
  quantity: Prisma.Decimal.Value,
) {
  return prisma.warehouseStock.create({
    data: { companyId, warehouseId, productId, quantity: d(quantity) },
  });
}

async function createOriginalSale(input: {
  companyId: string;
  userId: string;
  cashSessionId: string;
  productId: string;
  warehouseId: string | null;
  warehouseName?: string | null;
  warehouseCode?: string | null;
  qty: Prisma.Decimal.Value;
  unitCode: string;
  unitName: string;
  unitSymbol: string;
  unitPrecision: number;
  productSource?: ProductSource | null;
  cancelled?: boolean;
}) {
  const qty = d(input.qty);
  const subtotalSold = qty.mul(100).toDecimalPlaces(2);
  const subtotalCost = qty.mul(10).toDecimalPlaces(2);
  return prisma.sale.create({
    data: {
      companyId: input.companyId,
      userId: input.userId,
      cashSessionId: input.cashSessionId,
      saleDate: new Date(),
      paymentMethod: "cash",
      totalSold: subtotalSold,
      totalCost: subtotalCost,
      totalProfit: subtotalSold.minus(subtotalCost),
      commissionAmount: d(0),
      kind: "invoice",
      status: "PAID",
      cancelledAt: input.cancelled ? new Date() : null,
      inventoryRestoredAt: input.cancelled ? new Date() : null,
      items: {
        create: {
          productId: input.productId,
          productSource: input.productSource ?? ProductSource.LOCAL,
          sourceProductId: input.productId,
          warehouseId: input.warehouseId,
          warehouseNameSnapshot: input.warehouseName ?? null,
          warehouseCodeSnapshot: input.warehouseCode ?? null,
          productNameSnapshot: `${marker}-item`,
          qty,
          unitCodeSnapshot: input.unitCode,
          unitNameSnapshot: input.unitName,
          unitSymbolSnapshot: input.unitSymbol,
          unitPrecisionSnapshot: input.unitPrecision,
          priceSoldUnit: d(100),
          grossAmount: subtotalSold,
          lineDiscountAmount: d(0),
          taxableBase: d(0),
          taxRate: d(0),
          taxAmount: d(0),
          exemptAmount: subtotalSold,
          taxIncluded: false,
          taxExempt: true,
          costUnitSnapshot: d(10),
          subtotalSold,
          subtotalCost,
          profit: subtotalSold.minus(subtotalCost),
          commercialProfit: subtotalSold.minus(subtotalCost),
          netTaxProfit: subtotalSold.minus(subtotalCost),
        },
      },
    },
    include: { items: true },
  });
}

async function inventoryState(companyId: string, productId: string) {
  const product = await prisma.product.findFirstOrThrow({
    where: { id: productId, companyId },
    select: { stock: true },
  });
  const stocks = await prisma.warehouseStock.findMany({
    where: { companyId, productId },
    orderBy: { warehouseId: "asc" },
    select: { warehouseId: true, quantity: true },
  });
  const movements = await prisma.inventoryMovement.findMany({
    where: { companyId, productId },
    orderBy: { createdAt: "asc" },
    select: {
      type: true,
      quantityDelta: true,
      warehouseId: true,
      sourceType: true,
      sourceId: true,
      sourceItemId: true,
      reason: true,
    },
  });
  return {
    product: product.stock.toFixed(6),
    stocks: stocks.map((stock) => ({
      warehouseId: stock.warehouseId,
      quantity: stock.quantity.toFixed(6),
    })),
    movements: movements.map((movement) => ({
      ...movement,
      quantityDelta: movement.quantityDelta.toFixed(6),
    })),
  };
}

async function main() {
  await prisma.unitOfMeasure.findUniqueOrThrow({ where: { id: "YARD" } });
  await prisma.unitOfMeasure.findUniqueOrThrow({ where: { id: "POUND" } });
  await prisma.unitOfMeasure.findUniqueOrThrow({ where: { id: "UNIT" } });

  const slugs = [
    `${marker}-main`,
    `${marker}-concurrent-over`,
    `${marker}-concurrent-valid`,
    `${marker}-legacy`,
    `${marker}-fullpos`,
    `${marker}-tenant`,
    `${marker}-cancelled`,
  ];
  await cleanup(slugs);

  try {
    const sales = service();
    const company = await createCompany(slugs[0]);
    const user = await createUser(company.id, `${slugs[0]}@example.com`);
    const cash = await createCashSession(company.id, user.id);
    const mainWarehouse = await createWarehouse(company.id, "MAIN", true);
    const branchWarehouse = await createWarehouse(company.id, "BRANCH");
    const actor = {
      id: user.id,
      companyId: company.id,
      role: Role.ADMIN,
      authorizedPermissions: ["refundSales"],
    };
    const product = await createProduct(company.id, "YARD", "12.375");
    await setWarehouseStock(company.id, mainWarehouse.id, product.id, "0");
    await setWarehouseStock(company.id, branchWarehouse.id, product.id, "12.375");
    const original = await createOriginalSale({
      companyId: company.id,
      userId: user.id,
      cashSessionId: cash.id,
      productId: product.id,
      warehouseId: branchWarehouse.id,
      warehouseName: branchWarehouse.name,
      warehouseCode: branchWarehouse.code,
      qty: "7.625",
      unitCode: "YARD",
      unitName: "Yarda",
      unitSymbol: "yd",
      unitPrecision: 3,
    });

    const firstReturn = await sales.returnSale(actor as any, original.id, {
      clientRequestId: "w7-return-retry",
      items: [{ saleItemId: original.items[0].id, qty: 2.5 }],
      reason: "W7 partial return",
    });
    const retryReturn = await sales.returnSale(actor as any, original.id, {
      clientRequestId: "w7-return-retry",
      items: [{ saleItemId: original.items[0].id, qty: 2.5 }],
      reason: "W7 partial return",
    });
    const secondReturn = await sales.returnSale(actor as any, original.id, {
      clientRequestId: "w7-return-second",
      items: [{ saleItemId: original.items[0].id, qty: 5.125 }],
    });
    const overReturnRejected = await sales
      .returnSale(actor as any, original.id, {
        clientRequestId: "w7-return-over",
        items: [{ saleItemId: original.items[0].id, qty: 0.125 }],
      })
      .then(
        () => false,
        () => true,
      );
    const mainState = await inventoryState(company.id, product.id);

    const financialProduct = await createProduct(company.id, "POUND", "10");
    await setWarehouseStock(company.id, mainWarehouse.id, financialProduct.id, "10");
    const financialOriginal = await createOriginalSale({
      companyId: company.id,
      userId: user.id,
      cashSessionId: cash.id,
      productId: financialProduct.id,
      warehouseId: mainWarehouse.id,
      warehouseName: mainWarehouse.name,
      warehouseCode: mainWarehouse.code,
      qty: "2.375",
      unitCode: "POUND",
      unitName: "Libra",
      unitSymbol: "lb",
      unitPrecision: 3,
    });
    await sales.returnSale(actor as any, financialOriginal.id, {
      clientRequestId: "w7-financial-only",
      restoreInventory: false,
      items: [{ saleItemId: financialOriginal.items[0].id, qty: 2.375 }],
    });
    const financialState = await inventoryState(company.id, financialProduct.id);

    const cancelBlocked = await sales
      .remove(actor as any, original.id)
      .then(
        () => false,
        () => true,
      );

    const cancelledCompany = await createCompany(slugs[6]);
    const cancelledUser = await createUser(
      cancelledCompany.id,
      `${slugs[6]}@example.com`,
    );
    const cancelledCash = await createCashSession(cancelledCompany.id, cancelledUser.id);
    const cancelledWarehouse = await createWarehouse(cancelledCompany.id, "MAIN", true);
    const cancelledProduct = await createProduct(cancelledCompany.id, "UNIT", "10");
    await setWarehouseStock(
      cancelledCompany.id,
      cancelledWarehouse.id,
      cancelledProduct.id,
      "10",
    );
    const cancelledSale = await createOriginalSale({
      companyId: cancelledCompany.id,
      userId: cancelledUser.id,
      cashSessionId: cancelledCash.id,
      productId: cancelledProduct.id,
      warehouseId: cancelledWarehouse.id,
      warehouseName: cancelledWarehouse.name,
      warehouseCode: cancelledWarehouse.code,
      qty: "2",
      unitCode: "UNIT",
      unitName: "Unidad",
      unitSymbol: "u",
      unitPrecision: 0,
      cancelled: true,
    });
    const cancelledReturnRejected = await sales
      .returnSale(
        {
          id: cancelledUser.id,
          companyId: cancelledCompany.id,
          role: Role.ADMIN,
          authorizedPermissions: ["refundSales"],
        } as any,
        cancelledSale.id,
        { items: [{ saleItemId: cancelledSale.items[0].id, qty: 1 }] },
      )
      .then(
        () => false,
        () => true,
      );

    const legacyCompany = await createCompany(slugs[3]);
    const legacyUser = await createUser(legacyCompany.id, `${slugs[3]}@example.com`);
    const legacyCash = await createCashSession(legacyCompany.id, legacyUser.id);
    const legacyWarehouse = await createWarehouse(legacyCompany.id, "MAIN", true);
    const legacyProduct = await createProduct(legacyCompany.id, "YARD", "5");
    await setWarehouseStock(legacyCompany.id, legacyWarehouse.id, legacyProduct.id, "5");
    await prisma.inventoryZeroConfigState.create({
      data: {
        companyId: legacyCompany.id,
        status: "completed",
        warehouseId: legacyWarehouse.id,
        terminalId: null,
        localProductCount: 1,
        warehouseStockCount: 1,
        stockHash: "w7-fixture",
      },
    });
    const legacySale = await createOriginalSale({
      companyId: legacyCompany.id,
      userId: legacyUser.id,
      cashSessionId: legacyCash.id,
      productId: legacyProduct.id,
      warehouseId: null,
      qty: "0.125",
      unitCode: "YARD",
      unitName: "Yarda",
      unitSymbol: "yd",
      unitPrecision: 3,
    });
    await sales.returnSale(
      {
        id: legacyUser.id,
        companyId: legacyCompany.id,
        role: Role.ADMIN,
        authorizedPermissions: ["refundSales"],
      } as any,
      legacySale.id,
      { items: [{ saleItemId: legacySale.items[0].id, qty: 0.125 }] },
    );
    const legacyState = await inventoryState(legacyCompany.id, legacyProduct.id);

    const fullposCompany = await createCompany(slugs[4], ProductSource.FULLPOS);
    const fullposUser = await createUser(fullposCompany.id, `${slugs[4]}@example.com`);
    const fullposCash = await createCashSession(fullposCompany.id, fullposUser.id);
    const fullposWarehouse = await createWarehouse(fullposCompany.id, "MAIN", true);
    const fullposProduct = await createProduct(fullposCompany.id, "UNIT", "0");
    await setWarehouseStock(fullposCompany.id, fullposWarehouse.id, fullposProduct.id, "0");
    const fullposSale = await createOriginalSale({
      companyId: fullposCompany.id,
      userId: fullposUser.id,
      cashSessionId: fullposCash.id,
      productId: fullposProduct.id,
      warehouseId: fullposWarehouse.id,
      warehouseName: fullposWarehouse.name,
      warehouseCode: fullposWarehouse.code,
      qty: "1",
      unitCode: "UNIT",
      unitName: "Unidad",
      unitSymbol: "u",
      unitPrecision: 0,
      productSource: ProductSource.FULLPOS,
    });
    const fullposRejected = await sales
      .returnSale(
        {
          id: fullposUser.id,
          companyId: fullposCompany.id,
          role: Role.ADMIN,
          authorizedPermissions: ["refundSales"],
        } as any,
        fullposSale.id,
        { items: [{ saleItemId: fullposSale.items[0].id, qty: 1 }] },
      )
      .then(
        () => false,
        () => true,
      );

    const tenantCompany = await createCompany(slugs[5]);
    const tenantUser = await createUser(tenantCompany.id, `${slugs[5]}@example.com`);
    await createCashSession(tenantCompany.id, tenantUser.id);
    const crossCompanyRejected = await sales
      .returnSale(
        {
          id: tenantUser.id,
          companyId: tenantCompany.id,
          role: Role.ADMIN,
          authorizedPermissions: ["refundSales"],
        } as any,
        original.id,
        { items: [{ saleItemId: original.items[0].id, qty: 1 }] },
      )
      .then(
        () => false,
        () => true,
      );

    async function concurrentCase(slug: string, qty: string) {
      const c = await createCompany(slug);
      const u = await createUser(c.id, `${slug}@example.com`);
      const cs = await createCashSession(c.id, u.id);
      const w = await createWarehouse(c.id, "MAIN", true);
      const p = await createProduct(c.id, "YARD", "0");
      await setWarehouseStock(c.id, w.id, p.id, "0");
      const s = await createOriginalSale({
        companyId: c.id,
        userId: u.id,
        cashSessionId: cs.id,
        productId: p.id,
        warehouseId: w.id,
        warehouseName: w.name,
        warehouseCode: w.code,
        qty: "5",
        unitCode: "YARD",
        unitName: "Yarda",
        unitSymbol: "yd",
        unitPrecision: 3,
      });
      const a = {
        id: u.id,
        companyId: c.id,
        role: Role.ADMIN,
        authorizedPermissions: ["refundSales"],
      };
      const results = await Promise.allSettled([
        service().returnSale(a as any, s.id, {
          clientRequestId: `${slug}-a`,
          items: [{ saleItemId: s.items[0].id, qty: Number(qty) }],
        }),
        service().returnSale(a as any, s.id, {
          clientRequestId: `${slug}-b`,
          items: [{ saleItemId: s.items[0].id, qty: Number(qty) }],
        }),
      ]);
      const state = await inventoryState(c.id, p.id);
      return {
        fulfilled: results.filter((result) => result.status === "fulfilled").length,
        rejected: results.filter((result) => result.status === "rejected").length,
        state,
      };
    }

    const concurrentOver = await concurrentCase(slugs[1], "4");
    const concurrentValid = await concurrentCase(slugs[2], "2.5");

    const summary = {
      originalWarehouse: {
        firstReturnId: firstReturn.id,
        retrySameReturn: firstReturn.id === retryReturn.id,
        secondReturnId: secondReturn.id,
        overReturnRejected,
        branchWarehouseId: branchWarehouse.id,
        state: mainState,
      },
      financialOnly: {
        noReturnMovement:
          financialState.movements.filter(
            (movement) => movement.type === InventoryMovementType.RETURN,
          ).length === 0,
        state: financialState,
      },
      cancellation: { cancelBlocked, cancelledReturnRejected },
      legacyFallback: {
        restoredToMain:
          legacyState.movements.at(-1)?.reason === "LEGACY_MAIN_WAREHOUSE_FALLBACK" &&
          legacyState.movements.at(-1)?.warehouseId === legacyWarehouse.id,
        state: legacyState,
      },
      fullpos: { fullposRejected },
      tenant: { crossCompanyRejected },
      concurrency: { concurrentOver, concurrentValid },
    };

    console.log(JSON.stringify(summary, null, 2));
  } finally {
    await cleanup(slugs);
    await prisma.$disconnect();
  }
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exit(1);
});
