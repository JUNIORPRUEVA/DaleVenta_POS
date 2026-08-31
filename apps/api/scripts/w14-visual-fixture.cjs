const { PrismaClient, Prisma } = require("@prisma/client");
const bcrypt = require("bcryptjs");

const prisma = new PrismaClient();
const password = process.env.W14_VISUAL_PASSWORD;
const pin = process.env.W14_VISUAL_PIN;

if (!password || !pin) {
  throw new Error("W14_VISUAL_PASSWORD and W14_VISUAL_PIN are required");
}

async function cleanup() {
  const slugs = [
    "w14-visual-multi",
    "w14-visual-single",
    "w14-visual-zero",
  ];
  const emails = [
    "w14.multi@daleventas.test",
    "w14.single@daleventas.test",
    "w14.zero@daleventas.test",
  ];
  await prisma.company.deleteMany({ where: { slug: { in: slugs } } });
  await prisma.user.deleteMany({ where: { email: { in: emails } } });
}

async function createCompany({ name, slug, email, warehouses }) {
  const passwordHash = await bcrypt.hash(password, 10);
  const pinHash = await bcrypt.hash(pin, 10);
  const company = await prisma.company.create({
    data: {
      name,
      slug,
      status: "ACTIVE",
      plan: "ENTERPRISE",
      licenseStatus: "ACTIVE",
      maxUsers: 25,
      maxProducts: 1000,
      measurementUnitsEnabled: true,
    },
  });
  const user = await prisma.user.create({
    data: {
      companyId: company.id,
      email,
      passwordHash,
      nombreCompleto: `${name} Admin`,
      telefono: "8095550101",
      edad: 30,
      role: "ADMIN",
      userPermissions: {},
    },
  });
  await prisma.companyMember.create({
    data: {
      companyId: company.id,
      userId: user.id,
      role: "OWNER",
      status: "ACTIVE",
    },
  });
  await prisma.appConfig.create({
    data: {
      id: `w14-${slug}`,
      companyId: company.id,
      companyName: name,
      phone: "809-555-0101",
      address: "Validacion W14",
      adminAuthorizationPinHash: pinHash,
    },
  });

  const createdWarehouses = [];
  for (const warehouse of warehouses) {
    createdWarehouses.push(
      await prisma.warehouse.create({
        data: {
          companyId: company.id,
          name: warehouse.name,
          code: warehouse.code,
          isDefault: warehouse.isDefault,
          isActive: true,
        },
      }),
    );
  }

  const defaultWarehouse = createdWarehouses.find((w) => w.isDefault);
  const defaultTerminal = await prisma.terminal.create({
    data: {
      companyId: company.id,
      name: "Caja Principal W14",
      code: "W14-TERM-01",
      defaultWarehouseId: defaultWarehouse.id,
      isDefault: true,
      isActive: true,
      deviceFingerprint: `${slug}-desktop`,
    },
  });

  return { company, user, warehouses: createdWarehouses, defaultTerminal };
}

function movement(ctx, product, warehouse, type, delta, previous, resulting, reason) {
  return {
    companyId: ctx.company.id,
    productId: product.id,
    warehouseId: warehouse.id,
    type,
    quantityDelta: new Prisma.Decimal(delta),
    previousQuantity: new Prisma.Decimal(previous),
    resultingQuantity: new Prisma.Decimal(resulting),
    unitCodeSnapshot: "UNIT",
    unitNameSnapshot: "Unidad",
    unitSymbolSnapshot: "u",
    unitPrecisionSnapshot: 0,
    reason,
    createdByUserId: ctx.user.id,
  };
}

async function seedMultiWarehouse() {
  const ctx = await createCompany({
    name: "W14 Multi Almacen",
    slug: "w14-visual-multi",
    email: "w14.multi@daleventas.test",
    warehouses: [
      { name: "Principal W14", code: "MAIN", isDefault: true },
      { name: "Sucursal W14", code: "BRANCH", isDefault: false },
    ],
  });
  const [main, branch] = ctx.warehouses;
  const product = await prisma.product.create({
    data: {
      companyId: ctx.company.id,
      nombre: "Router Mesh W14",
      codigo: "W14-ROUTER",
      categoria: "Equipos",
      costo: new Prisma.Decimal("1200.00"),
      precio: new Prisma.Decimal("2500.00"),
      stock: new Prisma.Decimal("42.000000"),
    },
  });
  const cable = await prisma.product.create({
    data: {
      companyId: ctx.company.id,
      nombre: "Cable UTP W14",
      codigo: "W14-CABLE",
      categoria: "Materiales",
      costo: new Prisma.Decimal("35.00"),
      precio: new Prisma.Decimal("80.00"),
      stock: new Prisma.Decimal("18.500000"),
    },
  });
  await prisma.warehouseStock.createMany({
    data: [
      { companyId: ctx.company.id, warehouseId: main.id, productId: product.id, quantity: new Prisma.Decimal("30.000000") },
      { companyId: ctx.company.id, warehouseId: branch.id, productId: product.id, quantity: new Prisma.Decimal("12.000000") },
      { companyId: ctx.company.id, warehouseId: main.id, productId: cable.id, quantity: new Prisma.Decimal("10.000000") },
      { companyId: ctx.company.id, warehouseId: branch.id, productId: cable.id, quantity: new Prisma.Decimal("8.500000") },
    ],
  });
  await prisma.inventoryMovement.createMany({
    data: [
      movement(ctx, product, main, "INITIAL_STOCK", "30", "0", "30", "Fixture inicial MAIN"),
      movement(ctx, product, branch, "INITIAL_STOCK", "12", "0", "12", "Fixture inicial BRANCH"),
      movement(ctx, cable, main, "ADJUSTMENT_IN", "10", "0", "10", "Ajuste visual"),
      movement(ctx, cable, branch, "TRANSFER_IN", "8.5", "0", "8.5", "Transferencia visual"),
    ],
  });
  const transfer = await prisma.warehouseTransfer.create({
    data: {
      companyId: ctx.company.id,
      sourceWarehouseId: main.id,
      destinationWarehouseId: branch.id,
      sourceWarehouseNameSnapshot: main.name,
      sourceWarehouseCodeSnapshot: main.code,
      destinationWarehouseNameSnapshot: branch.name,
      destinationWarehouseCodeSnapshot: branch.code,
      status: "COMPLETED",
      operationId: `w14-transfer-${Date.now()}`,
      clientRequestId: `w14-client-${Date.now()}`,
      createdByUserId: ctx.user.id,
      completedAt: new Date(),
      notes: "Transferencia fixture W14",
    },
  });
  return { ...ctx, product, cable, transfer };
}

async function seedSingleWarehouse() {
  const ctx = await createCompany({
    name: "W14 Almacen Unico",
    slug: "w14-visual-single",
    email: "w14.single@daleventas.test",
    warehouses: [{ name: "Unico W14", code: "MAIN", isDefault: true }],
  });
  const product = await prisma.product.create({
    data: {
      companyId: ctx.company.id,
      nombre: "Producto Simple W14",
      codigo: "W14-SINGLE",
      categoria: "General",
      costo: new Prisma.Decimal("50.00"),
      precio: new Prisma.Decimal("100.00"),
      stock: new Prisma.Decimal("9.000000"),
    },
  });
  await prisma.warehouseStock.create({
    data: {
      companyId: ctx.company.id,
      warehouseId: ctx.warehouses[0].id,
      productId: product.id,
      quantity: new Prisma.Decimal("9.000000"),
    },
  });
  await prisma.inventoryZeroConfigState.create({
    data: {
      companyId: ctx.company.id,
      status: "COMPLETED",
      warehouseId: ctx.warehouses[0].id,
      terminalId: ctx.defaultTerminal.id,
      localProductCount: 1,
      warehouseStockCount: 1,
      stockHash: "w14-single",
      completedAt: new Date(),
    },
  });
  return ctx;
}

async function seedZeroConfigCompany() {
  const ctx = await createCompany({
    name: "W14 Cero Config",
    slug: "w14-visual-zero",
    email: "w14.zero@daleventas.test",
    warehouses: [{ name: "Principal", code: "MAIN", isDefault: true }],
  });
  await prisma.inventoryZeroConfigState.create({
    data: {
      companyId: ctx.company.id,
      status: "COMPLETED",
      warehouseId: ctx.warehouses[0].id,
      terminalId: ctx.defaultTerminal.id,
      localProductCount: 0,
      warehouseStockCount: 0,
      stockHash: "w14-zero",
      completedAt: new Date(),
    },
  });
  return ctx;
}

async function main() {
  await cleanup();
  const multi = await seedMultiWarehouse();
  const single = await seedSingleWarehouse();
  const zero = await seedZeroConfigCompany();
  console.log(JSON.stringify({
    ok: true,
    users: {
      multi: "w14.multi@daleventas.test",
      single: "w14.single@daleventas.test",
      zero: "w14.zero@daleventas.test",
    },
    ids: {
      multiCompanyId: multi.company.id,
      productId: multi.product.id,
      transferId: multi.transfer.id,
      singleCompanyId: single.company.id,
      zeroCompanyId: zero.company.id,
    },
  }, null, 2));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
