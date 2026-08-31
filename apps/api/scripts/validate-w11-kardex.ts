import {
  InventoryMovementType,
  LicenseStatus,
  Prisma,
  PrismaClient,
  ProductSource,
  Role,
  WarehouseTransferStatus,
} from "@prisma/client";
import * as bcrypt from "bcryptjs";

const prisma = new PrismaClient();
const apiBaseUrl = process.env.W11_API_BASE_URL ?? "http://127.0.0.1:4000";
const email = "w11.kardex@daleventa.local";
const password = process.env.W11_VISUAL_PASSWORD;
const companySlug = "w11-kardex-uat";
const disabledCompanySlug = "w11-kardex-disabled-uat";

const companyId = "51111111-1111-4111-8111-111111111111";
const disabledCompanyId = "52222222-2222-4222-8222-222222222222";
const userId = "53333333-3333-4333-8333-333333333333";
const sourceWarehouseId = "54444444-4444-4444-8444-444444444441";
const destinationWarehouseId = "54444444-4444-4444-8444-444444444442";
const inactiveWarehouseId = "54444444-4444-4444-8444-444444444443";
const yardProductId = "55555555-5555-4555-8555-555555555551";
const unitProductId = "55555555-5555-4555-8555-555555555552";
const poundProductId = "55555555-5555-4555-8555-555555555553";

function assertSafeDbName(db: string) {
  if (db === "daleventa" || db === "daleventa_pos") {
    throw new Error("Refusing W11 validation on protected database.");
  }
  if (!db.includes("validation") && !db.includes("uat")) {
    throw new Error(`Unsafe W11 validation database: ${db}`);
  }
}

async function currentDatabase() {
  const [{ db, host, port }] = await prisma.$queryRawUnsafe<
    Array<{ db: string; host: string | null; port: number }>
  >("select current_database() as db, inet_server_addr()::text as host, inet_server_port() as port");
  assertSafeDbName(db);
  return { db, host: host ?? "local-socket", port };
}

async function prepareFixture() {
  if (!password) throw new Error("W11_VISUAL_PASSWORD is required.");

  await prisma.user.deleteMany({ where: { email } });
  await prisma.company.deleteMany({
    where: { slug: { in: [companySlug, disabledCompanySlug] } },
  });
  await prisma.unitOfMeasure.deleteMany({
    where: { id: { in: ["W11_UNIT", "W11_YARD", "W11_POUND"] } },
  });

  await prisma.unitOfMeasure.createMany({
    data: [
      {
        id: "W11_UNIT",
        code: "W11_UNIT",
        name: "Unidad W11",
        symbol: "u",
        category: "COUNT",
        allowDecimals: false,
        precision: 0,
      },
      {
        id: "W11_YARD",
        code: "W11_YARD",
        name: "Yarda W11",
        symbol: "yd",
        category: "LENGTH",
        allowDecimals: true,
        precision: 3,
      },
      {
        id: "W11_POUND",
        code: "W11_POUND",
        name: "Libra W11",
        symbol: "lb",
        category: "WEIGHT",
        allowDecimals: true,
        precision: 3,
      },
    ],
  });

  await prisma.company.createMany({
    data: [
      {
        id: companyId,
        name: "W11 Kardex UAT",
        slug: companySlug,
        status: "ACTIVE",
        plan: "ENTERPRISE",
        licenseStatus: LicenseStatus.ACTIVE,
        productSource: ProductSource.LOCAL,
        measurementUnitsEnabled: true,
        maxUsers: 20,
        maxProducts: 1000,
      },
      {
        id: disabledCompanyId,
        name: "W11 Kardex Disabled UAT",
        slug: disabledCompanySlug,
        status: "ACTIVE",
        plan: "ENTERPRISE",
        licenseStatus: LicenseStatus.ACTIVE,
        productSource: ProductSource.LOCAL,
        measurementUnitsEnabled: false,
        maxUsers: 20,
        maxProducts: 1000,
      },
    ],
  });

  await prisma.warehouse.createMany({
    data: [
      {
        id: sourceWarehouseId,
        companyId,
        name: "Principal W11",
        code: "PRI-W11",
        isDefault: true,
        isActive: true,
      },
      {
        id: destinationWarehouseId,
        companyId,
        name: "Bavaro W11",
        code: "BAV-W11",
        isDefault: false,
        isActive: true,
      },
      {
        id: inactiveWarehouseId,
        companyId,
        name: "Almacen Inactivo W11",
        code: "INA-W11",
        isDefault: false,
        isActive: false,
      },
    ],
  });

  await prisma.product.createMany({
    data: [
      {
        id: yardProductId,
        companyId,
        nombre: "Tela Azul W11 Kardex",
        codigo: "W11-YD",
        categoria: "W11",
        costo: "70",
        precio: "120",
        stock: "20.875",
        unitOfMeasureId: "W11_YARD",
      },
      {
        id: unitProductId,
        companyId,
        nombre: "Audifonos W11 Kardex",
        codigo: "W11-U",
        categoria: "W11",
        costo: "50",
        precio: "100",
        stock: "10",
        unitOfMeasureId: "W11_UNIT",
      },
      {
        id: poundProductId,
        companyId,
        nombre: "Producto Peso W11 Kardex",
        codigo: "W11-LB",
        categoria: "W11",
        costo: "80",
        precio: "150",
        stock: "2.375",
        unitOfMeasureId: "W11_POUND",
      },
    ],
  });

  await prisma.warehouseStock.createMany({
    data: [
      { companyId, warehouseId: sourceWarehouseId, productId: yardProductId, quantity: "15.375" },
      { companyId, warehouseId: destinationWarehouseId, productId: yardProductId, quantity: "5.5" },
      { companyId, warehouseId: inactiveWarehouseId, productId: yardProductId, quantity: "0" },
      { companyId, warehouseId: sourceWarehouseId, productId: unitProductId, quantity: "10" },
      { companyId, warehouseId: sourceWarehouseId, productId: poundProductId, quantity: "2.375" },
    ],
  });

  await prisma.user.create({
    data: {
      id: userId,
      companyId,
      email,
      passwordHash: await bcrypt.hash(password, 10),
      nombreCompleto: "Admin W11 Kardex",
      telefono: "000",
      edad: 30,
      role: Role.ADMIN,
    },
  });

  const transfer = await prisma.warehouseTransfer.create({
    data: {
      companyId,
      sourceWarehouseId,
      destinationWarehouseId,
      sourceWarehouseNameSnapshot: "Principal W11",
      sourceWarehouseCodeSnapshot: "PRI-W11",
      destinationWarehouseNameSnapshot: "Bavaro W11",
      destinationWarehouseCodeSnapshot: "BAV-W11",
      status: WarehouseTransferStatus.COMPLETED,
      clientRequestId: "w11-kardex-transfer",
      createdByUserId: userId,
      completedAt: new Date("2026-08-31T12:04:00.000Z"),
      notes: "Synthetic W11 transfer",
      items: {
        create: {
          productId: yardProductId,
          productNameSnapshot: "Tela Azul W11 Kardex",
          productCodeSnapshot: "W11-YD",
          quantity: "5.5",
          unitCodeSnapshot: "W11_YARD",
          unitNameSnapshot: "Yarda W11",
          unitSymbolSnapshot: "yd",
          unitPrecisionSnapshot: 3,
        },
      },
    },
    include: { items: true },
  });

  const common = {
    companyId,
    productId: yardProductId,
    unitCodeSnapshot: "W11_YARD",
    unitNameSnapshot: "Yarda W11",
    unitSymbolSnapshot: "yd",
    unitPrecisionSnapshot: 3,
    createdByUserId: userId,
  };

  await prisma.inventoryMovement.createMany({
    data: [
      {
        ...common,
        warehouseId: sourceWarehouseId,
        type: InventoryMovementType.INITIAL_STOCK,
        quantityDelta: "20.5",
        previousQuantity: "0",
        resultingQuantity: "20.5",
        sourceType: "PRODUCT",
        sourceId: yardProductId,
        reason: "Stock inicial sintetico W11",
        createdAt: new Date("2026-08-31T12:00:00.000Z"),
      },
      {
        ...common,
        warehouseId: sourceWarehouseId,
        type: InventoryMovementType.ADJUSTMENT_IN,
        quantityDelta: "0.5",
        previousQuantity: "20.5",
        resultingQuantity: "21",
        sourceType: "MANUAL_ADJUSTMENT",
        sourceId: yardProductId,
        reason: "Ajuste W11 +0.5 yd",
        createdAt: new Date("2026-08-31T12:01:00.000Z"),
      },
      {
        ...common,
        warehouseId: sourceWarehouseId,
        type: InventoryMovementType.ADJUSTMENT_OUT,
        quantityDelta: "-0.125",
        previousQuantity: "21",
        resultingQuantity: "20.875",
        sourceType: "MANUAL_ADJUSTMENT",
        sourceId: yardProductId,
        reason: "Ajuste W11 -0.125 yd",
        createdAt: new Date("2026-08-31T12:02:00.000Z"),
      },
      {
        ...common,
        warehouseId: sourceWarehouseId,
        type: InventoryMovementType.TRANSFER_OUT,
        quantityDelta: "-5.5",
        previousQuantity: "20.875",
        resultingQuantity: "15.375",
        sourceWarehouseId,
        destinationWarehouseId,
        sourceType: "WAREHOUSE_TRANSFER",
        sourceId: transfer.id,
        sourceItemId: transfer.items[0].id,
        reason: "Transferencia W11 a Bavaro",
        createdAt: new Date("2026-08-31T12:04:00.000Z"),
      },
      {
        ...common,
        warehouseId: destinationWarehouseId,
        type: InventoryMovementType.TRANSFER_IN,
        quantityDelta: "5.5",
        previousQuantity: "0",
        resultingQuantity: "5.5",
        sourceWarehouseId,
        destinationWarehouseId,
        sourceType: "WAREHOUSE_TRANSFER",
        sourceId: transfer.id,
        sourceItemId: transfer.items[0].id,
        reason: "Transferencia W11 desde Principal",
        createdAt: new Date("2026-08-31T12:04:01.000Z"),
      },
      {
        companyId,
        productId: unitProductId,
        warehouseId: sourceWarehouseId,
        type: InventoryMovementType.SALE,
        quantityDelta: "-10",
        previousQuantity: "20",
        resultingQuantity: "10",
        unitCodeSnapshot: "W11_UNIT",
        unitNameSnapshot: "Unidad W11",
        unitSymbolSnapshot: "u",
        unitPrecisionSnapshot: 0,
        sourceType: "SALE",
        reason: "Venta sintetica W11",
        createdByUserId: userId,
        createdAt: new Date("2026-08-31T12:05:00.000Z"),
      },
      {
        companyId,
        productId: poundProductId,
        warehouseId: sourceWarehouseId,
        type: InventoryMovementType.SALE,
        quantityDelta: "-2.375",
        previousQuantity: "4.75",
        resultingQuantity: "2.375",
        unitCodeSnapshot: "W11_POUND",
        unitNameSnapshot: "Libra W11",
        unitSymbolSnapshot: "lb",
        unitPrecisionSnapshot: 3,
        sourceType: "SALE",
        reason: "Venta sintetica W11",
        createdByUserId: userId,
        createdAt: new Date("2026-08-31T12:06:00.000Z"),
      },
    ],
  });
}

async function apiGet<T>(path: string, token: string): Promise<T> {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    throw new Error(`${path} failed: ${response.status} ${await response.text()}`);
  }
  return response.json() as Promise<T>;
}

async function login() {
  const response = await fetch(`${apiBaseUrl}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!response.ok) throw new Error(`login failed: ${response.status} ${await response.text()}`);
  return response.json() as Promise<{ accessToken: string; activeCompany?: { slug?: string } }>;
}

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

async function validateApi() {
  const session = await login();
  assert(session.activeCompany?.slug === companySlug, "login did not resolve W11 tenant");

  const movements = await apiGet<{
    total: number;
    items: Array<{
      id?: string;
      type: string;
      quantityDeltaDecimal: string;
      resultingQuantityDecimal: string;
      unit: { symbol: string };
      product: { name: string };
      warehouse: { name: string };
      sourceType?: string | null;
      sourceId?: string | null;
      reference?: { label?: string | null; sourceType?: string | null; rawId?: string | null };
    }>;
  }>("/inventory/movements?take=50", session.accessToken);

  const transferRows = movements.items.filter(
    (item) => item.reference?.sourceType === "WAREHOUSE_TRANSFER",
  );
  assert(transferRows.length === 2, "expected paired transfer movements");
  assert(
    new Set(transferRows.map((item) => item.reference?.rawId)).size === 1,
    "transfer rows do not share source",
  );
  assert(
    transferRows.every((item) => item.reference?.label?.includes("Principal W11") && item.reference?.label?.includes("Bavaro W11")),
    "transfer reference labels were not resolved",
  );
  assert(
    movements.items.some((item) => item.quantityDeltaDecimal === "0.5" && item.resultingQuantityDecimal === "21"),
    "missing +0.5 yd adjustment",
  );
  assert(
    movements.items.some((item) => item.quantityDeltaDecimal === "-0.125" && item.resultingQuantityDecimal === "20.875"),
    "missing -0.125 yd adjustment",
  );
  assert(
    movements.items.some((item) => item.quantityDeltaDecimal === "-2.375" && item.unit.symbol === "lb"),
    "missing 2.375 lb sale bucket movement",
  );

  const pageA = await apiGet<{ items: Array<{ id?: string }> }>(
    "/inventory/movements?take=2&skip=0",
    session.accessToken,
  );
  const pageB = await apiGet<{ items: Array<{ id?: string }> }>(
    "/inventory/movements?take=2&skip=2",
    session.accessToken,
  );
  assert(
    pageA.items.length === 2 && pageB.items.length === 2 && pageA.items[0]?.id !== pageB.items[0]?.id,
    "pagination did not return deterministic windows",
  );

  const stock = await apiGet<{
    warehouses: Array<{ name: string; isActive: boolean }>;
    quantityBuckets: Array<{ unitSymbol: string; productCount: number }>;
    incompatibleUnitsSummed: boolean;
    rows: Array<{ productName: string; companyTotalDecimal: string; reconciled: boolean }>;
  }>("/inventory/stock-report", session.accessToken);
  assert(stock.warehouses.some((warehouse) => !warehouse.isActive && warehouse.name.includes("Inactivo")), "inactive warehouse missing");
  assert(stock.incompatibleUnitsSummed === false, "stock report exposes incompatible total");
  assert(stock.quantityBuckets.some((bucket) => bucket.unitSymbol === "yd"), "yard bucket missing");
  assert(stock.quantityBuckets.some((bucket) => bucket.unitSymbol === "lb"), "pound bucket missing");
  assert(stock.rows.every((product) => product.reconciled), "stock report should reconcile");

  const reconciliation = await apiGet<{ driftCount: number; readOnly: boolean }>(
    "/inventory/reconciliation",
    session.accessToken,
  );
  assert(reconciliation.driftCount === 0, "expected zero reconciliation drift");
  assert(reconciliation.readOnly === true, "reconciliation endpoint must remain read-only");

  return {
    authenticatedTenant: companySlug,
    movementTotal: movements.total,
    transferRows: transferRows.length,
    inactiveWarehouses: stock.warehouses.filter((warehouse) => !warehouse.isActive).length,
    buckets: stock.quantityBuckets,
    reconciliationDrift: reconciliation.driftCount,
  };
}

async function main() {
  const db = await currentDatabase();
  await prepareFixture();
  const api = await validateApi();
  console.log(
    JSON.stringify(
      {
        environment: "W11 UAT/VALIDATION",
        database: db,
        apiBaseUrl,
        productionConnected: false,
        fixture: {
          companySlug,
          disabledCompanySlug,
          email,
          products: ["Tela Azul W11 Kardex", "Audifonos W11 Kardex", "Producto Peso W11 Kardex"],
        },
        api,
      },
      null,
      2,
    ),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => prisma.$disconnect());
