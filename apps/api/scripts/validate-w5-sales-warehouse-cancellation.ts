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
) {
  return prisma.terminal.create({
    data: {
      companyId,
      name: code,
      code,
      defaultWarehouseId,
      isDefault: true,
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
    const terminal = await createTerminal(company.id, "T1", branch.id);
    const product = await createProduct(company.id, "W5 Sale Product", "20");
    await createStock(company.id, main.id, product.id, "10");
    await createStock(company.id, branch.id, product.id, "10");

    const sale = await service.create(
      { id: user.id, companyId: company.id, role: Role.ADMIN },
      {
        terminalId: terminal.id,
        items: [{ productId: product.id, qty: 2.25, priceSoldUnit: 2 }],
      },
    );
    const saleItem = sale.items[0];
    const saleState = await state(company.id, product.id, branch.id);

    const cancelCompany = await createCompany(slugs[1]);
    const cancelUser = await createUser(cancelCompany.id, `${slugs[1]}@example.com`);
    await openCashSession(cancelCompany.id, cancelUser.id);
    const cancelWarehouse = await createWarehouse(cancelCompany.id, "MAIN", true);
    const cancelProduct = await createProduct(
      cancelCompany.id,
      "W5 Cancel Product",
      "5",
    );
    await createStock(cancelCompany.id, cancelWarehouse.id, cancelProduct.id, "5");
    const saleToCancel = await service.create(
      { id: cancelUser.id, companyId: cancelCompany.id, role: Role.ADMIN },
      {
        warehouseId: cancelWarehouse.id,
        items: [{ productId: cancelProduct.id, qty: 1, priceSoldUnit: 2 }],
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
    const refundProduct = await createProduct(
      refundCompany.id,
      "W5 Refund Product",
      "5",
    );
    await createStock(refundCompany.id, refundWarehouse.id, refundProduct.id, "5");
    const saleToRefund = await service.create(
      { id: refundUser.id, companyId: refundCompany.id, role: Role.ADMIN },
      {
        warehouseId: refundWarehouse.id,
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
    const crossWarehouseRejected = await service
      .create(
        { id: user.id, companyId: company.id, role: Role.ADMIN },
        {
          warehouseId: tenantWarehouse.id,
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
          warehouseId: insufficientWarehouse.id,
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

    console.log(
      JSON.stringify(
        {
          terminalSale: {
            saleId: sale.id,
            saleItemWarehouseId: saleItem.warehouseId,
            saleItemWarehouseCodeSnapshot: saleItem.warehouseCodeSnapshot,
            branchState: saleState,
            movementSourceItemMatches:
              saleState.movements[0]?.sourceItemId === saleItem.id,
          },
          cancellation: {
            firstCancel,
            secondCancelRejected,
            state: cancelState,
            restoredOnce:
              cancelState.product === "5.000000" &&
              cancelState.warehouse === "5.000000" &&
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
        },
        null,
        2,
      ),
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
