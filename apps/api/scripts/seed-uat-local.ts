import {
  CompanyMemberRole,
  CompanyMemberStatus,
  LicenseStatus,
  Prisma,
  PrismaClient,
  ProductSource,
  PurchaseOrderStatus,
  Role,
} from "@prisma/client";
import * as bcrypt from "bcryptjs";

const prisma = new PrismaClient();
function requiredDbName() {
  return (process.env.UAT_SERVER_MODE ?? "").trim().toLowerCase() === "true"
    ? "daleventa_uat"
    : "daleventa_uat_local";
}

const units = [
  {
    id: "UNIT",
    code: "UNIT",
    name: "Unidad",
    symbol: "u",
    category: "COUNT",
    allowDecimals: false,
    precision: 0,
  },
  {
    id: "YARD",
    code: "YARD",
    name: "Yarda",
    symbol: "yd",
    category: "LENGTH",
    allowDecimals: true,
    precision: 3,
  },
  {
    id: "POUND",
    code: "POUND",
    name: "Libra",
    symbol: "lb",
    category: "WEIGHT",
    allowDecimals: true,
    precision: 3,
  },
] as const;

const companies = {
  enabled: {
    id: "11111111-1111-4111-8111-111111111111",
    slug: "uat-uom-enabled",
    name: "UAT Local - UoM Enabled",
    measurementUnitsEnabled: true,
  },
  disabled: {
    id: "22222222-2222-4222-8222-222222222222",
    slug: "uat-uom-disabled",
    name: "UAT Local - UoM Disabled",
    measurementUnitsEnabled: false,
  },
};

const uatUserId = "33333333-3333-4333-8333-333333333333";
const uatDisabledUserId = "44444444-4444-4444-8444-444444444444";

const products = [
  {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
    companyId: companies.enabled.id,
    nombre: "Audifonos UAT",
    codigo: "UAT-UNIT-001",
    categoria: "UAT",
    costo: "50",
    precio: "100",
    stock: "10",
    unitOfMeasureId: "UNIT",
  },
  {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
    companyId: companies.enabled.id,
    nombre: "Tela Azul UAT",
    codigo: "UAT-YARD-001",
    categoria: "UAT",
    costo: "70",
    precio: "120",
    stock: "20.5",
    unitOfMeasureId: "YARD",
  },
  {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
    companyId: companies.enabled.id,
    nombre: "Producto Peso UAT",
    codigo: "UAT-POUND-001",
    categoria: "UAT",
    costo: "80",
    precio: "150",
    stock: "10",
    unitOfMeasureId: "POUND",
  },
  {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4",
    companyId: companies.enabled.id,
    nombre: "Tela Azul Visual UAT",
    codigo: "UAT-YARD-VISUAL-001",
    categoria: "UAT",
    costo: "70",
    precio: "120",
    stock: "20.5",
    unitOfMeasureId: "YARD",
  },
  {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5",
    companyId: companies.enabled.id,
    nombre: "Carne Visual UAT",
    codigo: "UAT-POUND-VISUAL-001",
    categoria: "UAT",
    costo: "80",
    precio: "150",
    stock: "10",
    unitOfMeasureId: "POUND",
  },
  {
    id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
    companyId: companies.disabled.id,
    nombre: "Audifonos Legacy UAT",
    codigo: "UAT-OFF-UNIT-001",
    categoria: "UAT",
    costo: "50",
    precio: "100",
    stock: "10",
    unitOfMeasureId: "UNIT",
  },
] as const;

function assertUatOnly() {
  const appEnv = (process.env.APP_ENV ?? "").trim().toLowerCase();
  const localOnly = (process.env.UAT_LOCAL_ONLY ?? "").trim().toLowerCase();
  const serverUat = (process.env.UAT_SERVER_MODE ?? "").trim().toLowerCase();
  const url = (process.env.DATABASE_URL ?? "").trim();
  const expectedDb = requiredDbName();

  if (appEnv !== "uat" || (localOnly !== "true" && serverUat !== "true")) {
    throw new Error(
      "Refusing UAT seed: APP_ENV=uat and UAT_LOCAL_ONLY=true or UAT_SERVER_MODE=true are required.",
    );
  }
  if (!url.includes(`/${expectedDb}`)) {
    throw new Error(
      `Refusing UAT seed: DATABASE_URL must target ${expectedDb}.`,
    );
  }
  if (/\/daleventa($|\?)|\/daleventa_pos($|\?)/i.test(url)) {
    throw new Error(
      "Refusing UAT seed: DATABASE_URL looks remote or protected.",
    );
  }
}

async function assertCurrentDatabase() {
  const rows = await prisma.$queryRaw<Array<{ current_database: string }>>`
    SELECT current_database()
  `;
  const database = rows[0]?.current_database;
  const expectedDb = requiredDbName();
  if (database !== expectedDb) {
    throw new Error(
      `Refusing UAT seed: connected to ${database}, expected ${expectedDb}.`,
    );
  }
}

async function upsertUnits() {
  for (const unit of units) {
    await prisma.unitOfMeasure.upsert({
      where: { id: unit.id },
      create: unit,
      update: {
        code: unit.code,
        name: unit.name,
        symbol: unit.symbol,
        category: unit.category,
        allowDecimals: unit.allowDecimals,
        precision: unit.precision,
        active: true,
      },
    });
  }
}

async function upsertCompany(
  company: (typeof companies)[keyof typeof companies],
) {
  await prisma.company.upsert({
    where: { id: company.id },
    create: {
      id: company.id,
      name: company.name,
      slug: company.slug,
      status: "ACTIVE",
      plan: "ENTERPRISE",
      licenseStatus: LicenseStatus.ACTIVE,
      maxUsers: 20,
      maxProducts: 1000,
      measurementUnitsEnabled: company.measurementUnitsEnabled,
      productSource: "LOCAL",
    },
    update: {
      name: company.name,
      status: "ACTIVE",
      plan: "ENTERPRISE",
      licenseStatus: LicenseStatus.ACTIVE,
      maxUsers: 20,
      maxProducts: 1000,
      measurementUnitsEnabled: company.measurementUnitsEnabled,
      productSource: "LOCAL",
    },
  });

  await prisma.appConfig.upsert({
    where: { companyId: company.id },
    create: {
      id: `uat_${company.slug}`,
      companyId: company.id,
      companyName: company.name,
      rnc: "000000000",
      phone: "000-000-0000",
      address: "Synthetic UAT local",
      description: "Synthetic UAT company",
    },
    update: {
      companyName: company.name,
      rnc: "000000000",
      phone: "000-000-0000",
      address: "Synthetic UAT local",
      description: "Synthetic UAT company",
    },
  });
}

async function upsertUatUser(params: {
  id: string;
  email: string;
  passwordHash: string;
  companyId: string;
  name: string;
}) {
  await prisma.user.upsert({
    where: { id: params.id },
    create: {
      id: params.id,
      companyId: params.companyId,
      email: params.email,
      passwordHash: params.passwordHash,
      nombreCompleto: params.name,
      telefono: "0000000000",
      edad: 0,
      role: Role.ADMIN,
      blocked: false,
      tieneHijos: false,
      estaCasado: false,
      casaPropia: false,
      vehiculo: false,
      licenciaConducir: false,
    },
    update: {
      companyId: params.companyId,
      email: params.email,
      passwordHash: params.passwordHash,
      role: Role.ADMIN,
      blocked: false,
    },
  });

  await prisma.companyMember.upsert({
    where: {
      userId_companyId: { userId: params.id, companyId: params.companyId },
    },
    create: {
      userId: params.id,
      companyId: params.companyId,
      role: CompanyMemberRole.OWNER,
      status: CompanyMemberStatus.ACTIVE,
      joinedAt: new Date(),
    },
    update: {
      role: CompanyMemberRole.OWNER,
      status: CompanyMemberStatus.ACTIVE,
    },
  });
}

async function upsertAdmin() {
  const email = process.env.UAT_ADMIN_EMAIL || "uat.admin@daleventa.local";
  const disabledEmail =
    process.env.UAT_DISABLED_EMAIL || "uat.legacy@daleventa.local";
  const password = process.env.UAT_ADMIN_PASSWORD;
  if (!password) {
    throw new Error("UAT_ADMIN_PASSWORD is required.");
  }
  const passwordHash = await bcrypt.hash(password, 10);

  await upsertUatUser({
    id: uatUserId,
    email,
    passwordHash,
    companyId: companies.enabled.id,
    name: "Administrador UAT Local",
  });

  await upsertUatUser({
    id: uatDisabledUserId,
    email: disabledEmail,
    passwordHash,
    companyId: companies.disabled.id,
    name: "Administrador Legacy UAT",
  });
}

async function ensureDefaultInventory(companyId: string) {
  const warehouse = await prisma.warehouse.upsert({
    where: { companyId_code: { companyId, code: "UAT-DEFAULT" } },
    create: {
      companyId,
      name: "UAT Default Warehouse",
      code: "UAT-DEFAULT",
      isDefault: true,
      isActive: true,
    },
    update: {
      name: "UAT Default Warehouse",
      isDefault: true,
      isActive: true,
    },
  });

  const terminal = await prisma.terminal.upsert({
    where: { companyId_code: { companyId, code: "UAT-POS" } },
    create: {
      companyId,
      name: "UAT POS",
      code: "UAT-POS",
      defaultWarehouseId: warehouse.id,
      isDefault: true,
      isActive: true,
    },
    update: {
      defaultWarehouseId: warehouse.id,
      isDefault: true,
      isActive: true,
    },
  });

  await prisma.inventoryZeroConfigState.upsert({
    where: { companyId },
    create: {
      companyId,
      status: "COMPLETED",
      warehouseId: warehouse.id,
      terminalId: terminal.id,
      completedAt: new Date(),
    },
    update: {
      status: "COMPLETED",
      warehouseId: warehouse.id,
      terminalId: terminal.id,
      completedAt: new Date(),
    },
  });

  return { warehouse, terminal };
}

async function upsertProducts() {
  for (const product of products) {
    await prisma.product.upsert({
      where: { id: product.id },
      create: {
        id: product.id,
        companyId: product.companyId,
        nombre: product.nombre,
        codigo: product.codigo,
        categoria: product.categoria,
        costo: new Prisma.Decimal(product.costo),
        precio: new Prisma.Decimal(product.precio),
        stock: new Prisma.Decimal(product.stock),
        unitOfMeasureId: product.unitOfMeasureId,
      },
      update: {
        nombre: product.nombre,
        codigo: product.codigo,
        categoria: product.categoria,
        costo: new Prisma.Decimal(product.costo),
        precio: new Prisma.Decimal(product.precio),
        stock: new Prisma.Decimal(product.stock),
        unitOfMeasureId: product.unitOfMeasureId,
      },
    });
  }
}

async function syncWarehouseStock() {
  for (const company of Object.values(companies)) {
    const { warehouse } = await ensureDefaultInventory(company.id);
    for (const product of products.filter(
      (item) => item.companyId === company.id,
    )) {
      await prisma.warehouseStock.upsert({
        where: {
          companyId_warehouseId_productId: {
            companyId: product.companyId,
            warehouseId: warehouse.id,
            productId: product.id,
          },
        },
        create: {
          companyId: product.companyId,
          warehouseId: warehouse.id,
          productId: product.id,
          quantity: new Prisma.Decimal(product.stock),
        },
        update: {
          quantity: new Prisma.Decimal(product.stock),
        },
      });
    }
  }
}

function productByCode(code: string) {
  const product = products.find((item) => item.codigo === code);
  if (!product) throw new Error(`Missing UAT product fixture: ${code}`);
  return product;
}

function unitSnapshot(unitOfMeasureId: string) {
  const unit = units.find((item) => item.id === unitOfMeasureId);
  if (!unit) throw new Error(`Missing UAT unit fixture: ${unitOfMeasureId}`);
  return {
    unitCodeSnapshot: unit.code,
    unitNameSnapshot: unit.name,
    unitSymbolSnapshot: unit.symbol,
    unitPrecisionSnapshot: unit.precision,
  };
}

async function seedVisualDocuments() {
  const companyId = companies.enabled.id;
  const { warehouse, terminal } = await ensureDefaultInventory(companyId);
  const unitProduct = productByCode("UAT-UNIT-001");
  const yardProduct = productByCode("UAT-YARD-VISUAL-001");
  const poundProduct = productByCode("UAT-POUND-VISUAL-001");

  await prisma.sale.deleteMany({
    where: {
      companyId,
      clientRequestId: {
        in: ["uat-visual-sale-decimals", "uat-report-unit-balance"],
      },
    },
  });

  await prisma.sale.create({
    data: {
      companyId,
      userId: uatUserId,
      terminalId: terminal.id,
      terminalNameSnapshot: terminal.name,
      terminalCodeSnapshot: terminal.code,
      clientRequestId: "uat-report-unit-balance",
      saleDate: new Date("2026-08-30T12:00:00.000Z"),
      paymentMethod: "cash",
      paymentCashAmount: new Prisma.Decimal("800"),
      totalSold: new Prisma.Decimal("800"),
      totalCost: new Prisma.Decimal("400"),
      totalProfit: new Prisma.Decimal("400"),
      commissionAmount: new Prisma.Decimal("80"),
      items: {
        create: [
          {
            productId: unitProduct.id,
            productSource: ProductSource.LOCAL,
            sourceProductId: unitProduct.id,
            warehouseId: warehouse.id,
            warehouseNameSnapshot: warehouse.name,
            warehouseCodeSnapshot: warehouse.code,
            productNameSnapshot: unitProduct.nombre,
            qty: new Prisma.Decimal("8"),
            ...unitSnapshot(unitProduct.unitOfMeasureId),
            priceSoldUnit: new Prisma.Decimal(unitProduct.precio),
            grossAmount: new Prisma.Decimal("800"),
            exemptAmount: new Prisma.Decimal("800"),
            costUnitSnapshot: new Prisma.Decimal(unitProduct.costo),
            subtotalSold: new Prisma.Decimal("800"),
            subtotalCost: new Prisma.Decimal("400"),
            profit: new Prisma.Decimal("400"),
          },
        ],
      },
    },
  });

  await prisma.sale.create({
    data: {
      companyId,
      userId: uatUserId,
      terminalId: terminal.id,
      terminalNameSnapshot: terminal.name,
      terminalCodeSnapshot: terminal.code,
      clientRequestId: "uat-visual-sale-decimals",
      paymentMethod: "cash",
      paymentCashAmount: new Prisma.Decimal("1216.25"),
      totalSold: new Prisma.Decimal("1216.25"),
      totalCost: new Prisma.Decimal("675"),
      totalProfit: new Prisma.Decimal("541.25"),
      commissionAmount: new Prisma.Decimal("121.63"),
      items: {
        create: [
          {
            productId: unitProduct.id,
            productSource: ProductSource.LOCAL,
            sourceProductId: unitProduct.id,
            warehouseId: warehouse.id,
            warehouseNameSnapshot: warehouse.name,
            warehouseCodeSnapshot: warehouse.code,
            productNameSnapshot: unitProduct.nombre,
            qty: new Prisma.Decimal("2"),
            ...unitSnapshot(unitProduct.unitOfMeasureId),
            priceSoldUnit: new Prisma.Decimal(unitProduct.precio),
            grossAmount: new Prisma.Decimal("200"),
            exemptAmount: new Prisma.Decimal("200"),
            costUnitSnapshot: new Prisma.Decimal(unitProduct.costo),
            subtotalSold: new Prisma.Decimal("200"),
            subtotalCost: new Prisma.Decimal("100"),
            profit: new Prisma.Decimal("100"),
          },
          {
            productId: yardProduct.id,
            productSource: ProductSource.LOCAL,
            sourceProductId: yardProduct.id,
            warehouseId: warehouse.id,
            warehouseNameSnapshot: warehouse.name,
            warehouseCodeSnapshot: warehouse.code,
            productNameSnapshot: yardProduct.nombre,
            qty: new Prisma.Decimal("5.5"),
            ...unitSnapshot(yardProduct.unitOfMeasureId),
            priceSoldUnit: new Prisma.Decimal(yardProduct.precio),
            grossAmount: new Prisma.Decimal("660"),
            exemptAmount: new Prisma.Decimal("660"),
            costUnitSnapshot: new Prisma.Decimal(yardProduct.costo),
            subtotalSold: new Prisma.Decimal("660"),
            subtotalCost: new Prisma.Decimal("385"),
            profit: new Prisma.Decimal("275"),
          },
          {
            productId: poundProduct.id,
            productSource: ProductSource.LOCAL,
            sourceProductId: poundProduct.id,
            warehouseId: warehouse.id,
            warehouseNameSnapshot: warehouse.name,
            warehouseCodeSnapshot: warehouse.code,
            productNameSnapshot: poundProduct.nombre,
            qty: new Prisma.Decimal("2.375"),
            ...unitSnapshot(poundProduct.unitOfMeasureId),
            priceSoldUnit: new Prisma.Decimal(poundProduct.precio),
            grossAmount: new Prisma.Decimal("356.25"),
            exemptAmount: new Prisma.Decimal("356.25"),
            costUnitSnapshot: new Prisma.Decimal(poundProduct.costo),
            subtotalSold: new Prisma.Decimal("356.25"),
            subtotalCost: new Prisma.Decimal("190"),
            profit: new Prisma.Decimal("166.25"),
          },
        ],
      },
    },
  });

  await prisma.cotizacion.deleteMany({
    where: { companyId, customerName: "Cliente Visual UAT" },
  });
  await prisma.cotizacion.create({
    data: {
      companyId,
      createdByUserId: uatUserId,
      customerName: "Cliente Visual UAT",
      customerPhone: "0000000000",
      customerPhoneNormalized: "0000000000",
      note: "Synthetic UAT quotation with decimal UoM quantities",
      subtotal: new Prisma.Decimal("1016.25"),
      itbisAmount: new Prisma.Decimal("0"),
      total: new Prisma.Decimal("1016.25"),
      subtotalCost: new Prisma.Decimal("575"),
      totalCost: new Prisma.Decimal("575"),
      totalProfit: new Prisma.Decimal("441.25"),
      items: {
        create: [
          {
            productId: yardProduct.id,
            productSource: ProductSource.LOCAL,
            sourceProductId: yardProduct.id,
            productNameSnapshot: yardProduct.nombre,
            qty: new Prisma.Decimal("5.5"),
            ...unitSnapshot(yardProduct.unitOfMeasureId),
            originalUnitPriceSnapshot: new Prisma.Decimal(yardProduct.precio),
            unitPrice: new Prisma.Decimal(yardProduct.precio),
            costUnitSnapshot: new Prisma.Decimal(yardProduct.costo),
            subtotalCost: new Prisma.Decimal("385"),
            grossAmount: new Prisma.Decimal("660"),
            exemptAmount: new Prisma.Decimal("660"),
            lineTotal: new Prisma.Decimal("660"),
            profit: new Prisma.Decimal("275"),
          },
          {
            productId: poundProduct.id,
            productSource: ProductSource.LOCAL,
            sourceProductId: poundProduct.id,
            productNameSnapshot: poundProduct.nombre,
            qty: new Prisma.Decimal("2.375"),
            ...unitSnapshot(poundProduct.unitOfMeasureId),
            originalUnitPriceSnapshot: new Prisma.Decimal(poundProduct.precio),
            unitPrice: new Prisma.Decimal(poundProduct.precio),
            costUnitSnapshot: new Prisma.Decimal(poundProduct.costo),
            subtotalCost: new Prisma.Decimal("190"),
            grossAmount: new Prisma.Decimal("356.25"),
            exemptAmount: new Prisma.Decimal("356.25"),
            lineTotal: new Prisma.Decimal("356.25"),
            profit: new Prisma.Decimal("166.25"),
          },
        ],
      },
    },
  });

  const existingPurchaseOrders = await prisma.purchaseOrder.findMany({
    where: { companyId, orderNumber: "OC-000001" },
    select: { id: true },
  });
  const existingPurchaseOrderIds = existingPurchaseOrders.map(
    (item) => item.id,
  );
  if (existingPurchaseOrderIds.length > 0) {
    const existingPurchaseOrderItems = await prisma.purchaseOrderItem.findMany({
      where: { purchaseOrderId: { in: existingPurchaseOrderIds } },
      select: { id: true },
    });
    const existingPurchaseOrderItemIds = existingPurchaseOrderItems.map(
      (item) => item.id,
    );
    if (existingPurchaseOrderItemIds.length > 0) {
      await prisma.purchaseReceiptItem.deleteMany({
        where: {
          purchaseOrderItemId: { in: existingPurchaseOrderItemIds },
        },
      });
    }
    await prisma.purchaseReceipt.deleteMany({
      where: { purchaseOrderId: { in: existingPurchaseOrderIds } },
    });
    await prisma.purchaseOrderItem.deleteMany({
      where: { purchaseOrderId: { in: existingPurchaseOrderIds } },
    });
    await prisma.purchaseOrder.deleteMany({
      where: { id: { in: existingPurchaseOrderIds } },
    });
  }
  const purchaseOrder = await prisma.purchaseOrder.create({
    data: {
      companyId,
      orderNumber: "OC-000001",
      status: PurchaseOrderStatus.PARTIALLY_RECEIVED,
      createdById: uatUserId,
      subtotal: new Prisma.Decimal("6060"),
      total: new Prisma.Decimal("6060"),
      notes: "Synthetic UAT purchase with partial decimal receiving",
      items: {
        create: [
          {
            productId: yardProduct.id,
            productSource: ProductSource.LOCAL,
            sourceProductId: yardProduct.id,
            productNameSnapshot: yardProduct.nombre,
            productCodeSnapshot: yardProduct.codigo,
            quantity: new Prisma.Decimal("50.5"),
            receivedQuantity: new Prisma.Decimal("20.25"),
            pendingQuantity: new Prisma.Decimal("30.25"),
            ...unitSnapshot(yardProduct.unitOfMeasureId),
            unitCost: new Prisma.Decimal(yardProduct.precio),
            subtotal: new Prisma.Decimal("6060"),
          },
        ],
      },
    },
    include: { items: true },
  });

  await prisma.purchaseReceipt.create({
    data: {
      purchaseOrderId: purchaseOrder.id,
      supplierInvoiceNumber: "UAT-REC-000001",
      notes: "Synthetic UAT partial receipt",
      clientRequestId: "uat-visual-purchase-receipt",
      receivedById: uatUserId,
      inventoryUpdated: true,
      inventoryUpdatedAt: new Date(),
      items: {
        create: [
          {
            purchaseOrderItemId: purchaseOrder.items[0].id,
            productSource: ProductSource.LOCAL,
            sourceProductId: yardProduct.id,
            destinationWarehouseId: warehouse.id,
            warehouseNameSnapshot: warehouse.name,
            warehouseCodeSnapshot: warehouse.code,
            quantityReceived: new Prisma.Decimal("20.25"),
            ...unitSnapshot(yardProduct.unitOfMeasureId),
            unitCost: new Prisma.Decimal(yardProduct.precio),
          },
        ],
      },
    },
  });
}

async function main() {
  assertUatOnly();
  await assertCurrentDatabase();
  await upsertUnits();
  await upsertCompany(companies.enabled);
  await upsertCompany(companies.disabled);
  await upsertAdmin();
  await upsertProducts();
  await syncWarehouseStock();
  await seedVisualDocuments();

  const productCount = await prisma.product.count();
  const companyCount = await prisma.company.count();
  console.log("UAT local seed completed:", {
    database: requiredDbName(),
    companies: companyCount,
    products: productCount,
    adminEmail: process.env.UAT_ADMIN_EMAIL || "uat.admin@daleventa.local",
    disabledEmail:
      process.env.UAT_DISABLED_EMAIL || "uat.legacy@daleventa.local",
  });
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (error) => {
    console.error(error);
    await prisma.$disconnect();
    process.exit(1);
  });
