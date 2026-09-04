import { createHash, randomUUID } from "node:crypto";
import { Prisma, PrismaClient, ProductItemType } from "@prisma/client";

export const ZERO_CONFIG_VERSION = "W3_ZERO_CONFIG";
export const DEFAULT_WAREHOUSE_CODE = "MAIN";
export const DEFAULT_WAREHOUSE_NAME = "Main Warehouse";
export const DEFAULT_TERMINAL_CODE = "DEFAULT";
export const DEFAULT_TERMINAL_NAME = "Default Terminal";

type TransactionClient = Prisma.TransactionClient;
type PrismaLike = Pick<PrismaClient, "$transaction" | "company">;

type LocalProductSnapshot = {
  id: string;
  stock: Prisma.Decimal;
  itemType?: ProductItemType | null;
  trackInventory?: boolean | null;
};

export type ZeroConfigCompanyResult = {
  companyId: string;
  status: "created" | "completed" | "skipped";
  warehouseId: string;
  terminalId: string;
  localProductCount: number;
  createdWarehouseStocks: number;
  warehouseStockCount: number;
  stockHash: string;
};

export type ZeroConfigBackfillSummary = {
  companyCount: number;
  completed: number;
  skipped: number;
  createdWarehouseStocks: number;
  results: ZeroConfigCompanyResult[];
};

function decimalKey(value: Prisma.Decimal.Value) {
  return new Prisma.Decimal(value).toFixed(6);
}

function stockHash(products: LocalProductSnapshot[]) {
  const input = [...products]
    .sort((a, b) => a.id.localeCompare(b.id))
    .map((product) => `${product.id}:${decimalKey(product.stock)}`)
    .join(",");
  return createHash("sha256").update(input).digest("hex");
}

export async function ensureDefaultWarehouseAndTerminal(
  tx: TransactionClient,
  companyId: string,
) {
  let warehouse = await tx.warehouse.findUnique({
    where: {
      companyId_code: { companyId, code: DEFAULT_WAREHOUSE_CODE },
    },
  });

  if (!warehouse) {
    warehouse = await tx.warehouse.findFirst({
      where: { companyId, isDefault: true, isActive: true },
      orderBy: { createdAt: "asc" },
    });
  }

  if (!warehouse) {
    warehouse = await tx.warehouse.create({
      data: {
        companyId,
        name: DEFAULT_WAREHOUSE_NAME,
        code: DEFAULT_WAREHOUSE_CODE,
        isDefault: true,
        isActive: true,
      },
    });
  } else if (
    warehouse.code === DEFAULT_WAREHOUSE_CODE &&
    (!warehouse.isDefault || !warehouse.isActive)
  ) {
    warehouse = await tx.warehouse.update({
      where: { id: warehouse.id },
      data: { isDefault: true, isActive: true },
    });
  }

  let terminal = await tx.terminal.findUnique({
    where: {
      companyId_code: { companyId, code: DEFAULT_TERMINAL_CODE },
    },
  });

  if (!terminal) {
    terminal = await tx.terminal.findFirst({
      where: { companyId, isDefault: true, isActive: true },
      orderBy: { createdAt: "asc" },
    });
  }

  if (!terminal) {
    terminal = await tx.terminal.create({
      data: {
        companyId,
        name: DEFAULT_TERMINAL_NAME,
        code: DEFAULT_TERMINAL_CODE,
        defaultWarehouseId: warehouse.id,
        isDefault: true,
        isActive: true,
      },
    });
  } else if (
    terminal.defaultWarehouseId !== warehouse.id ||
    !terminal.isDefault ||
    !terminal.isActive
  ) {
    terminal = await tx.terminal.update({
      where: { id: terminal.id },
      data: {
        defaultWarehouseId: warehouse.id,
        isDefault: true,
        isActive: true,
      },
    });
  }

  return { warehouse, terminal };
}

export async function provisionZeroConfigForNewCompany(
  tx: TransactionClient,
  companyId: string,
) {
  const { warehouse, terminal } = await ensureDefaultWarehouseAndTerminal(
    tx,
    companyId,
  );
  const now = new Date();
  await tx.inventoryZeroConfigState.upsert({
    where: { companyId },
    create: {
      companyId,
      version: ZERO_CONFIG_VERSION,
      status: "COMPLETED",
      warehouseId: warehouse.id,
      terminalId: terminal.id,
      localProductCount: 0,
      warehouseStockCount: 0,
      stockHash: stockHash([]),
      startedAt: now,
      completedAt: now,
    },
    update: {
      status: "COMPLETED",
      warehouseId: warehouse.id,
      terminalId: terminal.id,
      localProductCount: 0,
      warehouseStockCount: 0,
      stockHash: stockHash([]),
      completedAt: now,
    },
  });
  return { warehouse, terminal };
}

export async function backfillZeroConfigInventoryForCompany(
  tx: TransactionClient,
  companyId: string,
): Promise<ZeroConfigCompanyResult> {
  const existingState = await tx.inventoryZeroConfigState.findUnique({
    where: { companyId },
  });
  if (existingState?.status === "COMPLETED") {
    return {
      companyId,
      status: "skipped",
      warehouseId: existingState.warehouseId ?? "",
      terminalId: existingState.terminalId ?? "",
      localProductCount: existingState.localProductCount,
      createdWarehouseStocks: 0,
      warehouseStockCount: existingState.warehouseStockCount,
      stockHash: existingState.stockHash ?? "",
    };
  }

  const now = new Date();
  await tx.inventoryZeroConfigState.upsert({
    where: { companyId },
    create: { companyId, version: ZERO_CONFIG_VERSION, status: "IN_PROGRESS", startedAt: now },
    update: { status: "IN_PROGRESS" },
  });

  const { warehouse, terminal } = await ensureDefaultWarehouseAndTerminal(
    tx,
    companyId,
  );

  const company = await tx.company.findUnique({
    where: { id: companyId },
    select: { productSource: true },
  });
  const isLocalCompany =
    !company?.productSource || company.productSource === "LOCAL";

  const products = isLocalCompany
    ? await tx.product.findMany({
        where: {
          companyId,
          itemType: ProductItemType.PRODUCT,
          trackInventory: true,
        },
        select: { id: true, stock: true, itemType: true, trackInventory: true },
        orderBy: { id: "asc" },
      })
    : [];
  const productIds = products.map((product) => product.id);
  const existingStocks = productIds.length
    ? await tx.warehouseStock.findMany({
        where: {
          companyId,
          warehouseId: warehouse.id,
          productId: { in: productIds },
        },
        select: { productId: true, quantity: true },
      })
    : [];
  const stockByProductId = new Map(
    existingStocks.map((stock) => [stock.productId, stock.quantity]),
  );

  const mismatches = products.filter((product) => {
    const quantity = stockByProductId.get(product.id);
    return quantity && decimalKey(quantity) !== decimalKey(product.stock);
  });
  if (mismatches.length > 0) {
    throw new Error(
      `W3 backfill refused to overwrite ${mismatches.length} existing WarehouseStock rows for company ${companyId}`,
    );
  }

  const missingStocks = products.filter(
    (product) => !stockByProductId.has(product.id),
  );
  if (missingStocks.length > 0) {
    await tx.warehouseStock.createMany({
      data: missingStocks.map((product) => ({
        id: randomUUID(),
        companyId,
        warehouseId: warehouse.id,
        productId: product.id,
        quantity: product.stock,
      })),
    });
  }
  const createdWarehouseStocks = missingStocks.length;

  const warehouseStockCount = await tx.warehouseStock.count({
    where: { companyId, warehouseId: warehouse.id },
  });
  if (warehouseStockCount !== products.length) {
    throw new Error(
      `W3 backfill expected ${products.length} WarehouseStock rows for company ${companyId}, found ${warehouseStockCount}`,
    );
  }

  const hash = stockHash(products);
  await tx.inventoryZeroConfigState.update({
    where: { companyId },
    data: {
      status: "COMPLETED",
      warehouseId: warehouse.id,
      terminalId: terminal.id,
      localProductCount: products.length,
      warehouseStockCount,
      stockHash: hash,
      completedAt: new Date(),
    },
  });

  return {
    companyId,
    status: "completed",
    warehouseId: warehouse.id,
    terminalId: terminal.id,
    localProductCount: products.length,
    createdWarehouseStocks,
    warehouseStockCount,
    stockHash: hash,
  };
}

export async function backfillZeroConfigInventoryForAllCompanies(
  prisma: PrismaLike,
): Promise<ZeroConfigBackfillSummary> {
  const companies = await prisma.company.findMany({
    select: { id: true },
    orderBy: { id: "asc" },
  });
  const results: ZeroConfigCompanyResult[] = [];

  for (const company of companies) {
    const result = await prisma.$transaction((tx) =>
      backfillZeroConfigInventoryForCompany(tx, company.id),
      { timeout: 30_000 },
    );
    results.push(result);
  }

  return {
    companyCount: companies.length,
    completed: results.filter((result) => result.status === "completed").length,
    skipped: results.filter((result) => result.status === "skipped").length,
    createdWarehouseStocks: results.reduce(
      (total, result) => total + result.createdWarehouseStocks,
      0,
    ),
    results,
  };
}
