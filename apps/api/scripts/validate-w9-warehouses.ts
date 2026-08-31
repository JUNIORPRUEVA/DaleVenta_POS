import { Prisma, PrismaClient, ProductSource, Role } from "@prisma/client";
import { createHash } from "node:crypto";
import { WarehousesService } from "../src/warehouses/warehouses.service";

const prisma = new PrismaClient();
const marker = "w9-warehouse-fixture";
const d = (value: Prisma.Decimal.Value) => new Prisma.Decimal(value);

function sourceResolver() {
  return {
    resolveForCompany: async (companyId: string) => {
      const company = await prisma.company.findFirstOrThrow({
        where: { id: companyId },
        select: { productSource: true },
      });
      const source = company.productSource ?? ProductSource.LOCAL;
      return {
        source,
        readOnly: source !== ProductSource.LOCAL,
      };
    },
  };
}

function service() {
  return new WarehousesService(prisma as any, sourceResolver() as any);
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
    await prisma.terminal.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.warehouse.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.product.deleteMany({
      where: { companyId: { in: companyIds } },
    });
  }
  await prisma.company.deleteMany({ where: { slug: { in: slugs } } });
  await prisma.user.deleteMany({
    where: { email: { in: slugs.map((slug) => `${slug}@example.com`) } },
  });
}

async function baseline(slugs: string[]) {
  const [
    company,
    product,
    warehouse,
    warehouseStock,
    inventoryMovement,
    terminal,
  ] = await Promise.all([
    prisma.company.count({ where: { slug: { notIn: slugs } } }),
    prisma.product.count(),
    prisma.warehouse.count(),
    prisma.warehouseStock.count(),
    prisma.inventoryMovement.count(),
    prisma.terminal.count(),
  ]);
  const stocks = await prisma.warehouseStock.findMany({
    orderBy: [
      { companyId: "asc" },
      { warehouseId: "asc" },
      { productId: "asc" },
    ],
    select: {
      companyId: true,
      warehouseId: true,
      productId: true,
      quantity: true,
    },
  });
  const stockHash = createHash("sha256")
    .update(
      stocks
        .map(
          (row) =>
            `${row.companyId}:${row.warehouseId}:${row.productId}:${row.quantity.toFixed(6)}`,
        )
        .join("|"),
    )
    .digest("hex");
  return {
    counts: {
      company,
      product,
      warehouse,
      warehouseStock,
      inventoryMovement,
      terminal,
    },
    stockHash,
  };
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
      passwordHash: "w9-validation",
      nombreCompleto: "W9 Validator",
      telefono: "000",
      edad: 30,
      role: Role.ADMIN,
    },
  });
}

async function createWarehouse(input: {
  companyId: string;
  name: string;
  code: string;
  isDefault?: boolean;
}) {
  return prisma.warehouse.create({
    data: {
      companyId: input.companyId,
      name: input.name,
      code: input.code,
      isDefault: input.isDefault ?? false,
      isActive: true,
    },
  });
}

async function createProduct(companyId: string, stock: Prisma.Decimal.Value) {
  return prisma.product.create({
    data: {
      companyId,
      nombre: `${marker}-product`,
      categoria: "W9",
      costo: d(10),
      precio: d(100),
      stock: d(stock),
      unitOfMeasureId: "UNIT",
    },
  });
}

async function createTerminal(input: {
  companyId: string;
  warehouseId: string;
  code: string;
}) {
  return prisma.terminal.create({
    data: {
      companyId: input.companyId,
      name: input.code,
      code: input.code,
      defaultWarehouseId: input.warehouseId,
      isDefault: true,
      isActive: true,
    },
  });
}

async function stockState(companyId: string, productId: string) {
  const product = await prisma.product.findFirstOrThrow({
    where: { id: productId, companyId },
    select: { stock: true },
  });
  const stocks = await prisma.warehouseStock.findMany({
    where: { companyId, productId },
    orderBy: { warehouseId: "asc" },
    select: { warehouseId: true, quantity: true },
  });
  const movements = await prisma.inventoryMovement.count({
    where: { companyId, productId },
  });
  return {
    product: product.stock.toFixed(6),
    stocks: stocks.map((stock) => ({
      warehouseId: stock.warehouseId,
      quantity: stock.quantity.toFixed(6),
    })),
    movements,
  };
}

async function main() {
  const slugs = [`${marker}-main`, `${marker}-other`, `${marker}-fullpos`];
  await cleanup(slugs);
  const before = await baseline(slugs);

  try {
    const warehouses = service();
    const company = await createCompany(slugs[0]);
    const user = await createUser(company.id, `${slugs[0]}@example.com`);
    const actor = { id: user.id, companyId: company.id, role: Role.ADMIN };
    const main = await createWarehouse({
      companyId: company.id,
      name: "Main Warehouse",
      code: "MAIN",
      isDefault: true,
    });
    const product = await createProduct(company.id, 100);
    await prisma.warehouseStock.create({
      data: {
        companyId: company.id,
        warehouseId: main.id,
        productId: product.id,
        quantity: d(100),
      },
    });
    const terminal = await createTerminal({
      companyId: company.id,
      warehouseId: main.id,
      code: "MAIN-POS",
    });

    const initialState = await stockState(company.id, product.id);
    const list = await warehouses.list(actor as any);
    const branch = await warehouses.create(actor as any, {
      name: "Bávaro",
      code: "bavaro",
    });
    const afterCreate = await stockState(company.id, product.id);
    await warehouses.update(actor as any, branch.id, {
      name: "Sucursal Bávaro",
      code: "BAV-2",
    });
    const afterEdit = await stockState(company.id, product.id);
    await warehouses.setDefault(actor as any, branch.id);
    const defaults = await prisma.warehouse.count({
      where: { companyId: company.id, isDefault: true },
    });
    const afterDefault = await stockState(company.id, product.id);
    const nonZeroDeactivationBlocked = await warehouses
      .deactivate(actor as any, main.id)
      .then(
        () => false,
        () => true,
      );
    await prisma.warehouseStock.updateMany({
      where: {
        companyId: company.id,
        warehouseId: main.id,
        productId: product.id,
      },
      data: { quantity: d(0) },
    });
    await prisma.warehouseStock.create({
      data: {
        companyId: company.id,
        warehouseId: branch.id,
        productId: product.id,
        quantity: d(0),
      },
    });
    const terminalLinkedDeactivationBlocked = await warehouses
      .deactivate(actor as any, main.id)
      .then(
        () => false,
        () => true,
      );
    await warehouses.updateTerminalWarehouse(actor as any, terminal.id, {
      warehouseId: branch.id,
    });
    await prisma.product.update({
      where: { id: product.id },
      data: { stock: d(0) },
    });
    const zeroDeactivated = await warehouses.deactivate(actor as any, main.id);
    const breakdown = await warehouses.productStockBreakdown(
      actor as any,
      product.id,
    );

    const otherCompany = await createCompany(slugs[1]);
    const otherUser = await createUser(
      otherCompany.id,
      `${slugs[1]}@example.com`,
    );
    const otherActor = {
      id: otherUser.id,
      companyId: otherCompany.id,
      role: Role.ADMIN,
    };
    const crossCompanyBlocked = await warehouses
      .setDefault(otherActor as any, branch.id)
      .then(
        () => false,
        () => true,
      );

    const fullposCompany = await createCompany(slugs[2], ProductSource.FULLPOS);
    const fullposUser = await createUser(
      fullposCompany.id,
      `${slugs[2]}@example.com`,
    );
    const fullposProduct = await createProduct(fullposCompany.id, 0);
    const fullposBreakdown = await warehouses.productStockBreakdown(
      {
        id: fullposUser.id,
        companyId: fullposCompany.id,
        role: Role.ADMIN,
      } as any,
      fullposProduct.id,
    );

    console.log(
      JSON.stringify(
        {
          listSameCompany: {
            ok: list.length === 1 && list[0].id === main.id,
          },
          createWarehouse: {
            startsEmpty: !afterCreate.stocks.some(
              (stock) => stock.warehouseId === branch.id,
            ),
            productStockUnchanged:
              initialState.product === afterCreate.product &&
              afterCreate.product === "100.000000",
            noMovement: afterCreate.movements === initialState.movements,
          },
          metadataCrud: {
            editPreservedStock:
              afterCreate.product === afterEdit.product &&
              JSON.stringify(afterCreate.stocks) ===
                JSON.stringify(afterEdit.stocks),
            defaultPreservedStock:
              afterEdit.product === afterDefault.product &&
              JSON.stringify(afterEdit.stocks) ===
                JSON.stringify(afterDefault.stocks),
            defaults,
          },
          deactivation: {
            nonZeroDeactivationBlocked,
            terminalLinkedDeactivationBlocked,
            zeroDeactivated: zeroDeactivated.isActive === false,
          },
          terminalAssignment: {
            terminalId: terminal.id,
            warehouseId: branch.id,
          },
          tenantSecurity: {
            crossCompanyBlocked,
          },
          stockBreakdown: {
            reconciled: breakdown.reconciled,
            totalDecimal: breakdown.totalDecimal,
            warehouseTotalDecimal: breakdown.warehouseTotalDecimal,
          },
          fullpos: {
            readOnly: fullposBreakdown.readOnly,
            source: fullposBreakdown.source,
            warehouses: fullposBreakdown.warehouses.length,
          },
        },
        null,
        2,
      ),
    );
  } finally {
    await cleanup(slugs);
    const after = await baseline(slugs);
    const remaining = await prisma.company.count({
      where: { slug: { startsWith: marker } },
    });
    console.log(
      JSON.stringify(
        {
          cleanup: {
            remainingFixtureCompanies: remaining,
            baselineCountsUnchanged:
              JSON.stringify(before.counts) === JSON.stringify(after.counts),
            warehouseStockHashUnchanged: before.stockHash === after.stockHash,
          },
        },
        null,
        2,
      ),
    );
    await prisma.$disconnect();
  }
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exit(1);
});
