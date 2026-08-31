import {
  InventoryMovementType,
  Prisma,
  PrismaClient,
  Role,
} from "@prisma/client";
import { InventoryMutationService } from "../src/inventory/inventory-mutation.service";
import { SalesService } from "../src/sales/sales.service";

const prisma = new PrismaClient();
const marker = "w5-sales-fixture";
const d = (value: Prisma.Decimal.Value) => new Prisma.Decimal(value);

const taxService = {
  getCompanyFiscalSettings: async () => ({
    taxEnabled: false,
    defaultTaxRate: d(0),
    ncfEnabled: false,
  }),
  resolvePriceMode: () => "NO_TAX",
  calculatorService: {
    calculate: ({ lines }: { lines: Array<{ quantity: Prisma.Decimal; unitPrice: Prisma.Decimal }> }) => ({
      total: d(0),
      taxableBase: d(0),
      taxAmount: d(0),
      exemptAmount: lines.reduce(
        (sum, line) => sum.plus(line.quantity.mul(line.unitPrice)),
        d(0),
      ),
      discountAmount: d(0),
      lines: lines.map((line, index) => ({
        index,
        grossAmount: line.quantity.mul(line.unitPrice),
        discountAmount: d(0),
        taxableBase: d(0),
        taxRate: d(0),
        taxAmount: d(0),
        exemptAmount: line.quantity.mul(line.unitPrice),
        taxIncluded: false,
        taxExempt: true,
        lineTotal: line.quantity.mul(line.unitPrice),
      })),
    }),
    validateFiscalCustomer: () => undefined,
  },
};

const ncfService = {
  normalizeType: (value: string) => value,
  reserveNextNcf: async () => null,
  markIssued: async () => undefined,
};

const service = new SalesService(
  prisma as any,
  {} as any,
  { emitCompany: () => undefined } as any,
  taxService as any,
  ncfService as any,
  new InventoryMutationService(prisma as any),
);

async function createCompany(slug: string) {
  return prisma.company.create({
    data: { name: slug, slug, productSource: null },
  });
}

async function createUser(companyId: string, email: string) {
  return prisma.user.create({
    data: {
      companyId,
      email,
      passwordHash: "w5-validation",
      nombreCompleto: "W5 Validator",
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
      categoria: "W5",
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

async function createTerminal(
  companyId: string,
  code: string,
  defaultWarehouseId: string,
  options: { deviceFingerprint?: string; isDefault?: boolean } = {},
) {
  return prisma.terminal.create({
    data: {
      companyId,
      name: code,
      code,
      defaultWarehouseId,
      deviceFingerprint: options.deviceFingerprint,
      isDefault: options.isDefault ?? true,
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

async function openCashSession(companyId: string, userId: string) {
  return prisma.cashSession.create({
    data: {
      companyId,
      openedByUserId: userId,
      userName: "W5 Validator",
      status: "OPEN",
      initialAmount: d(0),
    },
  });
}

async function state(companyId: string, productId: string, warehouseId: string) {
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

async function main() {
  const slugs = [
    `${marker}-sale`,
    `${marker}-cancel`,
    `${marker}-refund`,
    `${marker}-tenant`,
    `${marker}-insufficient`,
  ];
  await prisma.user.deleteMany({
    where: { email: { in: slugs.map((slug) => `${slug}@example.com`) } },
  });
  await prisma.company.deleteMany({ where: { slug: { in: slugs } } });

  try {
    const company = await createCompany(slugs[0]);
    const user = await createUser(company.id, `${slugs[0]}@example.com`);
    await openCashSession(company.id, user.id);
    const main = await createWarehouse(company.id, "MAIN", true);
    const branch = await createWarehouse(company.id, "BRANCH");
    const terminal = await createTerminal(company.id, "T1", main.id, {
      deviceFingerprint: "w5-sale-device",
    });
    const product = await createProduct(company.id, "W5 Sale Product", "10");
    await createStock(company.id, main.id, product.id, "10");

    const sale = await service.create(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      {
        clientRequestId: "w5-terminal-first-sale",
        deviceFingerprint: "w5-sale-device",
        items: [{ productId: product.id, qty: 3, priceSoldUnit: 2 }],
      },
    );
    const saleItem = sale.items[0];
    const saleState = await state(company.id, product.id, main.id);

    const historyProduct = await createProduct(
      company.id,
      "W5 Terminal History Product",
      "8",
    );
    await createStock(company.id, main.id, historyProduct.id, "4");
    await createStock(company.id, branch.id, historyProduct.id, "4");
    const historicalSale = await service.create(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      {
        clientRequestId: "w5-terminal-history-main",
        terminalId: terminal.id,
        items: [{ productId: historyProduct.id, qty: 1, priceSoldUnit: 2 }],
      },
    );
    await prisma.terminal.update({
      where: { id: terminal.id },
      data: { defaultWarehouseId: branch.id },
    });
    const futureSale = await service.create(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      {
        clientRequestId: "w5-terminal-history-branch",
        terminalId: terminal.id,
        items: [{ productId: historyProduct.id, qty: 1, priceSoldUnit: 2 }],
      },
    );

    const cancelCompany = await createCompany(slugs[1]);
    const cancelUser = await createUser(cancelCompany.id, `${slugs[1]}@example.com`);
    await openCashSession(cancelCompany.id, cancelUser.id);
    const cancelWarehouse = await createWarehouse(cancelCompany.id, "MAIN", true);
    const cancelTerminal = await createTerminal(
      cancelCompany.id,
      "MAIN-POS",
      cancelWarehouse.id,
      { deviceFingerprint: "w5-cancel-device" },
    );
    const cancelProduct = await createProduct(
      cancelCompany.id,
      "W5 Cancel Product",
      "10",
    );
    await createStock(cancelCompany.id, cancelWarehouse.id, cancelProduct.id, "10");
    const saleToCancel = await service.create(
      { id: cancelUser.id, companyId: cancelCompany.id, role: Role.ADMIN },
      {
        clientRequestId: "w5-cancel-sale",
        terminalId: cancelTerminal.id,
        items: [{ productId: cancelProduct.id, qty: 3, priceSoldUnit: 2 }],
      },
    );
    const firstCancel = await service.remove(
      { id: cancelUser.id, companyId: cancelCompany.id, role: Role.ADMIN },
      saleToCancel.id,
    );
    let secondCancelRejected = false;
    try {
      await service.remove(
        { id: cancelUser.id, companyId: cancelCompany.id, role: Role.ADMIN },
        saleToCancel.id,
      );
    } catch {
      secondCancelRejected = true;
    }
    const cancelState = await state(
      cancelCompany.id,
      cancelProduct.id,
      cancelWarehouse.id,
    );

    const refundCompany = await createCompany(slugs[2]);
    const refundUser = await createUser(refundCompany.id, `${slugs[2]}@example.com`);
    await openCashSession(refundCompany.id, refundUser.id);
    const refundWarehouse = await createWarehouse(refundCompany.id, "MAIN", true);
    const refundTerminal = await createTerminal(
      refundCompany.id,
      "MAIN-POS",
      refundWarehouse.id,
    );
    const refundProduct = await createProduct(
      refundCompany.id,
      "W5 Refund Product",
      "5",
    );
    await createStock(refundCompany.id, refundWarehouse.id, refundProduct.id, "5");
    const saleToRefund = await service.create(
      { id: refundUser.id, companyId: refundCompany.id, role: Role.ADMIN },
      {
        clientRequestId: "w5-refund-sale",
        terminalId: refundTerminal.id,
        items: [{ productId: refundProduct.id, qty: 2, priceSoldUnit: 2 }],
      },
    );
    const refund = await service.returnSale(
      {
        id: refundUser.id,
        companyId: refundCompany.id,
        role: Role.ADMIN,
        authorizedPermissions: ["refundSales"],
      },
      saleToRefund.id,
      { items: [{ saleItemId: saleToRefund.items[0].id, qty: 1 }] },
    );
    let cancelAfterRefundBlocked = false;
    try {
      await service.remove(
        { id: refundUser.id, companyId: refundCompany.id, role: Role.ADMIN },
        saleToRefund.id,
      );
    } catch {
      cancelAfterRefundBlocked = true;
    }
    const refundState = await state(
      refundCompany.id,
      refundProduct.id,
      refundWarehouse.id,
    );

    const tenantCompany = await createCompany(slugs[3]);
    const tenantWarehouse = await createWarehouse(tenantCompany.id, "MAIN", true);
    const tenantTerminal = await createTerminal(
      tenantCompany.id,
      "MAIN-POS",
      tenantWarehouse.id,
    );
    const crossWarehouseRejected = await service
      .create(
        { id: user.id, companyId: company.id, role: Role.ADMIN },
        {
          terminalId: tenantTerminal.id,
          items: [{ productId: product.id, qty: 1, priceSoldUnit: 2 }],
        },
      )
      .then(
        () => false,
        () => true,
      );

    const insufficientCompany = await createCompany(slugs[4]);
    const insufficientUser = await createUser(
      insufficientCompany.id,
      `${slugs[4]}@example.com`,
    );
    await openCashSession(insufficientCompany.id, insufficientUser.id);
    const insufficientWarehouse = await createWarehouse(
      insufficientCompany.id,
      "MAIN",
      true,
    );
    const insufficientTerminal = await createTerminal(
      insufficientCompany.id,
      "MAIN-POS",
      insufficientWarehouse.id,
    );
    const insufficientProduct = await createProduct(
      insufficientCompany.id,
      "W5 Insufficient Product",
      "1",
    );
    await createStock(
      insufficientCompany.id,
      insufficientWarehouse.id,
      insufficientProduct.id,
      "1",
    );
    const beforeInsufficientSaleCount = await prisma.sale.count({
      where: { companyId: insufficientCompany.id },
    });
    const beforeInsufficientMovementCount = await prisma.inventoryMovement.count({
      where: { companyId: insufficientCompany.id },
    });
    const insufficientRejected = await service
      .create(
        {
          id: insufficientUser.id,
          companyId: insufficientCompany.id,
          role: Role.ADMIN,
        },
        {
          clientRequestId: "w5-insufficient-sale",
          terminalId: insufficientTerminal.id,
          items: [{ productId: insufficientProduct.id, qty: 2, priceSoldUnit: 2 }],
        },
      )
      .then(
        () => false,
        () => true,
      );
    const afterInsufficientSaleCount = await prisma.sale.count({
      where: { companyId: insufficientCompany.id },
    });
    const afterInsufficientMovementCount = await prisma.inventoryMovement.count({
      where: { companyId: insufficientCompany.id },
    });
    const insufficientState = await state(
      insufficientCompany.id,
      insufficientProduct.id,
      insufficientWarehouse.id,
    );

    const concurrencyCompany = await createCompany(`${marker}-concurrency`);
    slugs.push(`${marker}-concurrency`);
    const concurrencyUser = await createUser(
      concurrencyCompany.id,
      `${marker}-concurrency@example.com`,
    );
    await openCashSession(concurrencyCompany.id, concurrencyUser.id);
    const concurrencyWarehouse = await createWarehouse(
      concurrencyCompany.id,
      "MAIN",
      true,
    );
    const concurrencyTerminal = await createTerminal(
      concurrencyCompany.id,
      "MAIN-POS",
      concurrencyWarehouse.id,
    );
    const concurrencyProduct = await createProduct(
      concurrencyCompany.id,
      "W5 Last Unit Product",
      "1",
    );
    await createStock(
      concurrencyCompany.id,
      concurrencyWarehouse.id,
      concurrencyProduct.id,
      "1",
    );
    const concurrentResults = await Promise.allSettled([
      service.create(
        { id: concurrencyUser.id, companyId: concurrencyCompany.id, role: Role.ADMIN },
        {
          clientRequestId: "w5-last-unit-a",
          terminalId: concurrencyTerminal.id,
          items: [{ productId: concurrencyProduct.id, qty: 1, priceSoldUnit: 2 }],
        },
      ),
      service.create(
        { id: concurrencyUser.id, companyId: concurrencyCompany.id, role: Role.ADMIN },
        {
          clientRequestId: "w5-last-unit-b",
          terminalId: concurrencyTerminal.id,
          items: [{ productId: concurrencyProduct.id, qty: 1, priceSoldUnit: 2 }],
        },
      ),
    ]);
    const concurrencyState = await state(
      concurrencyCompany.id,
      concurrencyProduct.id,
      concurrencyWarehouse.id,
    );
    const fixtureCompanyIds = [
      company.id,
      cancelCompany.id,
      refundCompany.id,
      insufficientCompany.id,
      concurrencyCompany.id,
    ];
    const fixtureProducts = await prisma.product.findMany({
      where: { companyId: { in: fixtureCompanyIds } },
      select: { id: true, companyId: true, stock: true },
    });
    const fixtureStocks = await prisma.warehouseStock.findMany({
      where: { companyId: { in: fixtureCompanyIds } },
      select: { productId: true, companyId: true, quantity: true },
    });
    const stockTotals = new Map<string, Prisma.Decimal>();
    for (const row of fixtureStocks) {
      const key = `${row.companyId}:${row.productId}`;
      stockTotals.set(key, (stockTotals.get(key) ?? d(0)).plus(row.quantity));
    }
    const driftCount = fixtureProducts.filter((product) => {
      const key = `${product.companyId}:${product.id}`;
      return !product.stock.equals(stockTotals.get(key) ?? d(0));
    }).length;
    const negativeWarehouseStockCount = await prisma.warehouseStock.count({
      where: {
        companyId: { in: fixtureCompanyIds },
        quantity: { lt: d(0) },
      },
    });

    const report = {
      terminalSale: {
        saleId: sale.id,
        terminalId: sale.terminalId,
        resolvedFromDeviceFingerprint: sale.terminalId === terminal.id,
        saleItemWarehouseId: saleItem.warehouseId,
        saleItemWarehouseCodeSnapshot: saleItem.warehouseCodeSnapshot,
        mainState: saleState,
        deductedFromMain:
          saleState.product === "7.000000" &&
          saleState.warehouse === "7.000000" &&
          saleItem.warehouseId === main.id &&
          saleState.movements.some(
            (movement) =>
              movement.type === InventoryMovementType.SALE &&
              movement.quantityDelta === "-3.000000" &&
              movement.sourceItemId === saleItem.id,
          ),
      },
      terminalReassignmentHistory: {
        historicalWarehouseId: historicalSale.items[0]?.warehouseId,
        futureWarehouseId: futureSale.items[0]?.warehouseId,
        historicalSaleStayedMain: historicalSale.items[0]?.warehouseId === main.id,
        futureSaleUsedBranch: futureSale.items[0]?.warehouseId === branch.id,
      },
      cancellation: {
        firstCancel,
        secondCancelRejected,
        state: cancelState,
        restoredOnce:
          cancelState.product === "10.000000" &&
          cancelState.warehouse === "10.000000" &&
          cancelState.movements.filter(
            (movement) =>
              movement.type === InventoryMovementType.SALE_CANCELLATION,
          ).length === 1,
      },
      refundInteraction: {
        refundId: refund.id,
        cancelAfterRefundBlocked,
        state: refundState,
      },
      tenantSecurity: { crossWarehouseRejected },
      insufficientStock: {
        insufficientRejected,
        noSalePartial: beforeInsufficientSaleCount === afterInsufficientSaleCount,
        noMovementPartial:
          beforeInsufficientMovementCount === afterInsufficientMovementCount,
        state: insufficientState,
      },
      concurrency: {
        fulfilled: concurrentResults.filter(
          (result) => result.status === "fulfilled",
        ).length,
        rejected: concurrentResults.filter(
          (result) => result.status === "rejected",
        ).length,
        noNegativeStock: concurrencyState.warehouse === "0.000000",
        state: concurrencyState,
      },
      reconciliation: {
        driftCount,
        negativeWarehouseStockCount,
      },
    };

    const assertions = [
      report.terminalSale.resolvedFromDeviceFingerprint,
      report.terminalSale.deductedFromMain,
      report.terminalReassignmentHistory.historicalSaleStayedMain,
      report.terminalReassignmentHistory.futureSaleUsedBranch,
      report.cancellation.secondCancelRejected,
      report.cancellation.restoredOnce,
      report.refundInteraction.cancelAfterRefundBlocked,
      report.tenantSecurity.crossWarehouseRejected,
      report.insufficientStock.insufficientRejected,
      report.insufficientStock.noSalePartial,
      report.insufficientStock.noMovementPartial,
      report.concurrency.fulfilled === 1,
      report.concurrency.rejected === 1,
      report.concurrency.noNegativeStock,
      report.reconciliation.driftCount === 0,
      report.reconciliation.negativeWarehouseStockCount === 0,
    ];

    if (assertions.some((ok) => !ok)) {
      throw new Error("W5 terminal-first validation failed");
    }

    console.log(
      JSON.stringify(report, null, 2),
    );
  } finally {
    await prisma.user.deleteMany({
      where: { email: { in: slugs.map((slug) => `${slug}@example.com`) } },
    });
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
