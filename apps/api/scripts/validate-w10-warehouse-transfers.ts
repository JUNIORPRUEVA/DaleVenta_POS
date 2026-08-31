import { PrismaClient, ProductSource } from "@prisma/client";
import { WarehousesService } from "../src/warehouses/warehouses.service";

const prisma = new PrismaClient();
const decimal = (value: string | number) => value.toString();

const service = new WarehousesService(prisma as any, {
  resolveForCompany: async (companyId: string) => {
    const company = await prisma.company.findUniqueOrThrow({
      where: { id: companyId },
      select: { productSource: true },
    });
    const source = company.productSource ?? ProductSource.LOCAL;
    return { source, readOnly: source !== ProductSource.LOCAL };
  },
} as any);

async function main() {
  const [{ db }] = await prisma.$queryRawUnsafe<Array<{ db: string }>>(
    "select current_database() as db",
  );
  if (!db.includes("validation") && !db.includes("uat")) {
    throw new Error(`Unsafe database for W10 validation: ${db}`);
  }
  if (db === "daleventa") throw new Error("Refusing production database");

  const baseline = await counts();
  await cleanup();
  await ensureUnits();

  const companyA = await company("w10-transfer-a", ProductSource.LOCAL);
  const companyB = await company("w10-transfer-b", ProductSource.LOCAL);
  const fullposCompany = await company("w10-transfer-fullpos", ProductSource.FULLPOS);
  const userA = await user(companyA.id, "w10-transfer-a@daleventa.local");

  const main = await warehouse(companyA.id, "Main W10", "MAIN", true);
  const branch = await warehouse(companyA.id, "Bavaro W10", "BAV", false);
  const extra = await warehouse(companyA.id, "Extra W10", "EXT", false);
  const otherWarehouse = await warehouse(companyB.id, "Other W10", "OTH", true);
  const inactive = await prisma.warehouse.create({
    data: {
      companyId: companyA.id,
      name: "Inactive W10",
      code: "INA",
      isActive: false,
    },
  });
  await user(companyB.id, "w10-transfer-b@daleventa.local");

  const unit = await product(companyA.id, "Audifonos W10", "UNIT", "100", main.id);
  const pound = await product(companyA.id, "Peso W10", "UNIT", "10", main.id);
  const yard = await product(companyA.id, "Tela W10", "YARD", "50.75", main.id);
  const otherProduct = await product(companyB.id, "Other Product W10", "UNIT", "5", otherWarehouse.id);
  const fullposWarehouse = await warehouse(fullposCompany.id, "FullPOS W10", "FPO", true);
  const fullposDestination = await warehouse(fullposCompany.id, "FullPOS Dest W10", "FPD", false);
  const fullposProduct = await product(fullposCompany.id, "FullPOS Product W10", "UNIT", "5", fullposWarehouse.id);

  const apiUser = { id: userA.id, companyId: companyA.id, role: "ADMIN" };
  const results: Record<string, unknown> = {};

  const beforeSimple = await stock(unit.id, main.id, branch.id);
  const simple = await service.createTransfer(apiUser as any, {
    sourceWarehouseId: main.id,
    destinationWarehouseId: branch.id,
    clientRequestId: "w10-simple",
    items: [{ productId: unit.id, quantity: "30" }],
  });
  const afterSimple = await stock(unit.id, main.id, branch.id);
  results.simpleTransfer =
    beforeSimple.product === "100" &&
    afterSimple.source === "70" &&
    afterSimple.destination === "30" &&
    afterSimple.product === "100" &&
    simple.items[0].quantityDecimal === "30";
  results.movements = await movementPair(simple.id);

  const idempotent = await service.createTransfer(apiUser as any, {
    sourceWarehouseId: main.id,
    destinationWarehouseId: branch.id,
    clientRequestId: "w10-simple",
    items: [{ productId: unit.id, quantity: "30" }],
  });
  const afterRetry = await stock(unit.id, main.id, branch.id);
  results.idempotency =
    idempotent.id === simple.id &&
    afterRetry.source === "70" &&
    afterRetry.destination === "30";
  await prisma.warehouse.update({ where: { id: main.id }, data: { name: "Main W10 Renamed" } });
  await prisma.product.update({ where: { id: unit.id }, data: { nombre: "Audifonos W10 Renamed" } });
  const snapshotted = await service.getTransfer(apiUser as any, simple.id);
  results.snapshots =
    snapshotted.sourceWarehouse.name === "Main W10" &&
    snapshotted.items[0].productName === "Audifonos W10";

  results.sameWarehouseRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: main.id,
      clientRequestId: "w10-same",
      items: [{ productId: unit.id, quantity: "1" }],
    }),
  );

  const beforeInsufficient = await stock(unit.id, main.id, branch.id);
  results.insufficientRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-insufficient",
      items: [{ productId: unit.id, quantity: "1000" }],
    }),
  );
  results.noPartialOnInsufficient =
    JSON.stringify(beforeInsufficient) ===
    JSON.stringify(await stock(unit.id, main.id, branch.id));

  const missingDest = await service.createTransfer(apiUser as any, {
    sourceWarehouseId: main.id,
    destinationWarehouseId: extra.id,
    clientRequestId: "w10-missing-dest",
    items: [{ productId: pound.id, quantity: "3" }],
  });
  results.destinationRowCreated =
    missingDest.items[0].quantityDecimal === "3" &&
    (await stock(pound.id, main.id, extra.id)).destination === "3";

  await service.createTransfer(apiUser as any, {
    sourceWarehouseId: main.id,
    destinationWarehouseId: branch.id,
    clientRequestId: "w10-decimal",
    items: [{ productId: yard.id, quantity: "7.625" }],
  });
  results.decimalPreserved =
    (await stock(yard.id, main.id, branch.id)).source === "43.125";

  const beforeMultiA = await stock(unit.id, main.id, branch.id);
  const beforeMultiB = await stock(pound.id, main.id, branch.id);
  await service.createTransfer(apiUser as any, {
    sourceWarehouseId: main.id,
    destinationWarehouseId: branch.id,
    clientRequestId: "w10-multi",
    items: [
      { productId: unit.id, quantity: "3" },
      { productId: pound.id, quantity: "5" },
    ],
  });
  results.multiItemAtomic =
    (await stock(unit.id, main.id, branch.id)).source === "67" &&
    (await stock(pound.id, main.id, branch.id)).source === "2";

  const beforePartialA = await stock(unit.id, main.id, branch.id);
  const beforePartialB = await stock(pound.id, main.id, branch.id);
  results.multiItemFailureRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-partial-fail",
      items: [
        { productId: unit.id, quantity: "1" },
        { productId: pound.id, quantity: "99" },
      ],
    }),
  );
  results.noPartialOnMultiFailure =
    JSON.stringify(beforePartialA) ===
      JSON.stringify(await stock(unit.id, main.id, branch.id)) &&
    JSON.stringify(beforePartialB) ===
      JSON.stringify(await stock(pound.id, main.id, branch.id));

  results.crossCompanySourceRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: otherWarehouse.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-cross-source",
      items: [{ productId: unit.id, quantity: "1" }],
    }),
  );
  results.crossCompanyDestinationRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: otherWarehouse.id,
      clientRequestId: "w10-cross-destination",
      items: [{ productId: unit.id, quantity: "1" }],
    }),
  );
  results.crossCompanyProductRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-cross-product",
      items: [{ productId: otherProduct.id, quantity: "1" }],
    }),
  );
  results.inactiveSourceRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: inactive.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-inactive-source",
      items: [{ productId: unit.id, quantity: "1" }],
    }),
  );
  results.inactiveDestinationRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: inactive.id,
      clientRequestId: "w10-inactive-destination",
      items: [{ productId: unit.id, quantity: "1" }],
    }),
  );
  results.fullposRejected = await rejects(() =>
    service.createTransfer(
      { id: userA.id, companyId: fullposCompany.id, role: "ADMIN" } as any,
      {
        sourceWarehouseId: fullposWarehouse.id,
        destinationWarehouseId: fullposDestination.id,
        clientRequestId: "w10-fullpos",
        items: [{ productId: fullposProduct.id, quantity: "1" }],
      },
    ),
  );

  await prisma.product.update({ where: { id: unit.id }, data: { stock: "99" } });
  results.driftRejected = await rejects(() =>
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-drift",
      items: [{ productId: unit.id, quantity: "1" }],
    }),
  );
  await prisma.product.update({ where: { id: unit.id }, data: { stock: "100" } });

  const over = await product(companyA.id, "Concurrent Over W10", "UNIT", "5", main.id);
  const overResults = await Promise.allSettled([
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-concurrent-over-1",
      items: [{ productId: over.id, quantity: "4" }],
    }),
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: extra.id,
      clientRequestId: "w10-concurrent-over-2",
      items: [{ productId: over.id, quantity: "4" }],
    }),
  ]);
  const overStock = await stock(over.id, main.id, branch.id, extra.id);
  results.concurrentOverTransferPrevented =
    overResults.filter((item) => item.status === "fulfilled").length === 1 &&
    overStock.source === "1";

  const valid = await product(companyA.id, "Concurrent Valid W10", "UNIT", "10", main.id);
  const validResults = await Promise.allSettled([
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: branch.id,
      clientRequestId: "w10-concurrent-valid-1",
      items: [{ productId: valid.id, quantity: "4" }],
    }),
    service.createTransfer(apiUser as any, {
      sourceWarehouseId: main.id,
      destinationWarehouseId: extra.id,
      clientRequestId: "w10-concurrent-valid-2",
      items: [{ productId: valid.id, quantity: "6" }],
    }),
  ]);
  results.concurrentValidTransfersSafe =
    validResults.every((item) => item.status === "fulfilled") &&
    (await stock(valid.id, main.id, branch.id, extra.id)).source === "0";

  results.deleteBlocked = await rejects(async () => service.deleteTransfer());

  if (Object.values(results).some((value) => value !== true)) {
    console.log(JSON.stringify(results, null, 2));
    throw new Error("W10 validation failed");
  }

  await cleanup();
  const after = await counts();
  console.log(JSON.stringify({ db, results, cleanup: { baseline, after } }, null, 2));
}

async function counts() {
  const [companies, transfers, movements] = await Promise.all([
    prisma.company.count({ where: { slug: { startsWith: "w10-transfer-" } } }),
    prisma.warehouseTransfer.count({
      where: { company: { slug: { startsWith: "w10-transfer-" } } },
    }),
    prisma.inventoryMovement.count({
      where: { company: { slug: { startsWith: "w10-transfer-" } } },
    }),
  ]);
  return { companies, transfers, movements };
}

async function cleanup() {
  await prisma.user.deleteMany({ where: { email: { endsWith: "@daleventa.local" } } });
  await prisma.company.deleteMany({ where: { slug: { startsWith: "w10-transfer-" } } });
  await prisma.unitOfMeasure.deleteMany({ where: { id: { startsWith: "W10_" } } });
}

async function ensureUnits() {
  await prisma.unitOfMeasure.createMany({
    data: [
      {
        id: "W10_UNIT",
        code: "W10_UNIT",
        name: "Unidad W10",
        symbol: "u",
        category: "COUNT",
        allowDecimals: false,
        precision: 0,
      },
      {
        id: "W10_YARD",
        code: "W10_YARD",
        name: "Yarda W10",
        symbol: "yd",
        category: "LENGTH",
        allowDecimals: true,
        precision: 3,
      },
    ],
    skipDuplicates: true,
  });
}

async function company(slug: string, productSource: ProductSource) {
  return prisma.company.create({
    data: {
      name: slug,
      slug,
      productSource,
      measurementUnitsEnabled: true,
    },
  });
}

async function user(companyId: string, email: string) {
  return prisma.user.create({
    data: {
      companyId,
      email,
      passwordHash: "synthetic",
      nombreCompleto: email,
      telefono: "000",
      edad: 30,
      role: "ADMIN",
    },
  });
}

async function warehouse(companyId: string, name: string, code: string, isDefault: boolean) {
  return prisma.warehouse.create({
    data: { companyId, name, code, isDefault, isActive: true },
  });
}

async function product(
  companyId: string,
  nombre: string,
  unitCode: "UNIT" | "YARD",
  quantity: string,
  warehouseId: string,
) {
  const created = await prisma.product.create({
    data: {
      companyId,
      nombre,
      categoria: "W10",
      costo: "1",
      precio: "2",
      stock: quantity,
      unitOfMeasureId: unitCode === "UNIT" ? "W10_UNIT" : "W10_YARD",
    },
  });
  await prisma.warehouseStock.create({
    data: { companyId, warehouseId, productId: created.id, quantity },
  });
  return created;
}

async function stock(productId: string, sourceId: string, destinationId: string, extraId?: string) {
  const product = await prisma.product.findUniqueOrThrow({ where: { id: productId } });
  const rows = await prisma.warehouseStock.findMany({ where: { productId } });
  const find = (warehouseId: string) =>
    rows.find((row) => row.warehouseId === warehouseId)?.quantity.toString() ?? "0";
  return {
    product: product.stock.toString(),
    source: find(sourceId),
    destination: find(destinationId),
    extra: extraId ? find(extraId) : undefined,
  };
}

async function movementPair(transferId: string) {
  const rows = await prisma.inventoryMovement.findMany({
    where: { sourceId: transferId },
    orderBy: { type: "asc" },
  });
  return (
    rows.length === 2 &&
    rows.some((row) => row.type === "TRANSFER_OUT") &&
    rows.some((row) => row.type === "TRANSFER_IN")
  );
}

async function rejects(action: () => Promise<unknown>) {
  try {
    await action();
    return false;
  } catch {
    return true;
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await cleanup().catch(() => undefined);
    await prisma.$disconnect();
  });
