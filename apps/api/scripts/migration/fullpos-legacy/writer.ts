/**
 * UAT/execute writer for the legacy migration.
 *
 * Design rules:
 *  - never uses operational services (no SalesService.create, no inventory mutation
 *    service): plain, tenant-scoped Prisma inserts in the documented order
 *  - one single transaction: a failure anywhere rolls the whole import back
 *    (nothing is left half-written)
 *  - every row is written with its deterministic UUID and the locked company id
 *  - rollback deletes ONLY the deterministic id set of this migration profile
 *    (never `deleteMany({ companyId })`)
 *  - idempotency: a second run detects the already-imported deterministic set and
 *    performs a clean no-op
 */

import { PrismaClient } from '@prisma/client';
import { MigrationAbortError } from './errors';
import type { WritePlan } from './payload';

export const WRITE_BATCH_SIZE = 500;

export type LiveMetadata = {
  databaseName: string;
  serverAddress: string | null;
  serverPort: number | null;
  serverVersion: string;
  currentUser: string;
};

export type MigrationIdSets = {
  companyId: string;
  warehouseId: string;
  productIds: string[];
  activeProductIds: string[];
  archivedProductIds: string[];
  shiftIds: string[];
  saleIds: string[];
  saleItemIds: string[];
  linkedSaleIds: string[];
  unlinkedSaleIds: string[];
};

export type TargetState = {
  products: number;
  activeProducts: number;
  archivedProducts: number;
  shifts: number;
  sales: number;
  saleItems: number;
  warehouseStocks: number;
  inventoryMovements: number;
  cashMovements: number;
  cashboxDaily: number;
  clients: number;
  suppliers: number;
  purchaseOrders: number;
  taxes: number;
  ncfSequences: number;
  openShifts: number;
};

export type TargetStateVerdict = 'FRESH' | 'ALREADY_APPLIED' | 'UNEXPECTED_STATE';

export function createTargetClient(databaseUrl: string): PrismaClient {
  return new PrismaClient({
    datasources: { db: { url: databaseUrl } },
  });
}

export async function readLiveMetadata(prisma: PrismaClient): Promise<LiveMetadata> {
  const rows = await prisma.$queryRaw<
    Array<{
      database_name: string;
      server_address: string | null;
      server_port: number | null;
      server_version: string;
      current_user: string;
    }>
  >`SELECT current_database() AS database_name,
           inet_server_addr()::text AS server_address,
           inet_server_port() AS server_port,
           version() AS server_version,
           current_user AS current_user`;
  const row = rows[0];
  if (!row) {
    throw new MigrationAbortError('TARGET_METADATA_UNAVAILABLE', 'No se pudo leer la metadata del destino', {});
  }
  return {
    databaseName: row.database_name,
    serverAddress: row.server_address,
    serverPort: row.server_port,
    serverVersion: row.server_version,
    currentUser: row.current_user,
  };
}

export function buildIdSets(plan: {
  companyId: string;
  warehouseId: string;
  writePlan: WritePlan;
}): MigrationIdSets {
  const products = plan.writePlan.products;
  return {
    companyId: plan.companyId,
    warehouseId: plan.warehouseId,
    productIds: products.map((product) => product.id),
    activeProductIds: products.filter((product) => product.archivedAt === null).map((product) => product.id),
    archivedProductIds: products.filter((product) => product.archivedAt !== null).map((product) => product.id),
    shiftIds: plan.writePlan.shifts.map((shift) => shift.id),
    saleIds: plan.writePlan.sales.map((sale) => sale.id),
    saleItemIds: plan.writePlan.saleItems.map((item) => item.id),
    linkedSaleIds: plan.writePlan.sales.filter((sale) => sale.cashSessionId !== null).map((sale) => sale.id),
    unlinkedSaleIds: plan.writePlan.sales.filter((sale) => sale.cashSessionId === null).map((sale) => sale.id),
  };
}

export async function readTargetState(
  prisma: PrismaClient,
  companyId: string,
): Promise<TargetState> {
  const [
    products,
    activeProducts,
    archivedProducts,
    shifts,
    openShifts,
    sales,
    saleItems,
    warehouseStocks,
    inventoryMovements,
    cashMovements,
    cashboxDaily,
    clients,
    suppliers,
    purchaseOrders,
    taxes,
    ncfSequences,
  ] = await Promise.all([
    prisma.product.count({ where: { companyId } }),
    prisma.product.count({ where: { companyId, archivedAt: null } }),
    prisma.product.count({ where: { companyId, archivedAt: { not: null } } }),
    prisma.cashSession.count({ where: { companyId } }),
    prisma.cashSession.count({ where: { companyId, status: 'OPEN' } }),
    prisma.sale.count({ where: { companyId } }),
    prisma.saleItem.count({ where: { sale: { companyId } } }),
    prisma.warehouseStock.count({ where: { companyId } }),
    prisma.inventoryMovement.count({ where: { companyId } }),
    prisma.cashMovement.count({ where: { companyId } }),
    prisma.cashboxDaily.count({ where: { companyId } }),
    prisma.client.count({ where: { companyId } }),
    prisma.supplier.count({ where: { companyId } }),
    prisma.purchaseOrder.count({ where: { companyId } }),
    prisma.tax.count({ where: { companyId } }),
    prisma.ncfSequence.count({ where: { companyId } }),
  ]);

  return {
    products,
    activeProducts,
    archivedProducts,
    shifts,
    openShifts,
    sales,
    saleItems,
    warehouseStocks,
    inventoryMovements,
    cashMovements,
    cashboxDaily,
    clients,
    suppliers,
    purchaseOrders,
    taxes,
    ncfSequences,
  };
}

/**
 * Classifies the destination before writing:
 *  - FRESH           : nothing of this migration profile is present
 *  - ALREADY_APPLIED : the full expected set is present (clean no-op)
 *  - UNEXPECTED_STATE: partial/foreign data -> abort, never overwrite
 */
export function classifyTargetState(
  state: TargetState,
  expected: {
    products: number;
    activeProducts: number;
    archivedProducts: number;
    shifts: number;
    sales: number;
    saleItems: number;
    warehouseStocks: number;
  },
): { verdict: TargetStateVerdict; details: string[] } {
  const details: string[] = [];
  const keys: Array<keyof typeof expected> = [
    'products',
    'activeProducts',
    'archivedProducts',
    'shifts',
    'sales',
    'saleItems',
    'warehouseStocks',
  ];

  const matches = keys.filter((key) => state[key] === expected[key]);
  const allMatch = matches.length === keys.length;
  const allEmpty = keys.every((key) => state[key] === 0);

  if (allMatch) return { verdict: 'ALREADY_APPLIED', details };
  if (allEmpty) return { verdict: 'FRESH', details };

  for (const key of keys) {
    if (state[key] !== 0 && state[key] !== expected[key]) {
      details.push(`${key}: encontrado ${state[key]}, esperado 0 (limpio) o ${expected[key]} (ya aplicado)`);
    }
  }
  for (const key of keys) {
    if (state[key] === 0 && expected[key] !== 0 && !allEmpty) {
      details.push(`${key}: ausente (0 de ${expected[key]})`);
    }
  }
  return { verdict: 'UNEXPECTED_STATE', details };
}

export function assertTargetStateAllowsWrite(verdict: TargetStateVerdict, details: string[]): void {
  if (verdict === 'UNEXPECTED_STATE') {
    throw new MigrationAbortError(
      'TARGET_STATE_UNEXPECTED',
      'El destino contiene un estado inesperado (importación parcial o datos ajenos): no se escribe nada',
      { details },
    );
  }
}

function chunk<T>(rows: T[], size = WRITE_BATCH_SIZE): T[][] {
  const batches: T[][] = [];
  for (let index = 0; index < rows.length; index += size) {
    batches.push(rows.slice(index, index + size));
  }
  return batches;
}

export type InsertCounts = {
  products: number;
  warehouseStocks: number;
  shifts: number;
  sales: number;
  saleItems: number;
};

/** Writes the whole plan inside ONE transaction (ordered batches). */
export async function insertPlan(
  prisma: PrismaClient,
  writePlan: WritePlan,
  options: { timeoutMs?: number } = {},
): Promise<InsertCounts> {
  const timeout = options.timeoutMs ?? 600_000;

  return prisma.$transaction(
    async (tx) => {
      const counts: InsertCounts = {
        products: 0,
        warehouseStocks: 0,
        shifts: 0,
        sales: 0,
        saleItems: 0,
      };

      // 1. Products
      for (const batch of chunk(writePlan.products)) {
        const result = await tx.product.createMany({ data: batch });
        counts.products += result.count;
      }

      // 2. Opening stock (active products only)
      for (const batch of chunk(writePlan.warehouseStocks)) {
        const result = await tx.warehouseStock.createMany({ data: batch });
        counts.warehouseStocks += result.count;
      }

      // 3. Historical shifts (all CLOSED)
      for (const batch of chunk(writePlan.shifts)) {
        const result = await tx.cashSession.createMany({ data: batch });
        counts.shifts += result.count;
      }

      // 4. Sales (linked and unlinked)
      for (const batch of chunk(writePlan.sales)) {
        const result = await tx.sale.createMany({ data: batch });
        counts.sales += result.count;
      }

      // 5. Sale items
      for (const batch of chunk(writePlan.saleItems)) {
        const result = await tx.saleItem.createMany({ data: batch });
        counts.saleItems += result.count;
      }

      return counts;
    },
    { timeout, maxWait: 60_000 },
  );
}

export type RollbackCounts = {
  saleItems: number;
  sales: number;
  shifts: number;
  warehouseStocks: number;
  products: number;
};

/**
 * Surgical rollback: deletes ONLY the deterministic id set of this migration profile,
 * in reverse order, always scoped by the locked company id. Never a wildcard delete.
 */
export async function deletePlan(
  prisma: PrismaClient,
  ids: MigrationIdSets,
  options: { timeoutMs?: number } = {},
): Promise<RollbackCounts> {
  const timeout = options.timeoutMs ?? 600_000;

  return prisma.$transaction(
    async (tx) => {
      const counts: RollbackCounts = {
        saleItems: 0,
        sales: 0,
        shifts: 0,
        warehouseStocks: 0,
        products: 0,
      };

      for (const batch of chunk(ids.saleItemIds)) {
        const result = await tx.saleItem.deleteMany({
          where: { id: { in: batch }, sale: { companyId: ids.companyId } },
        });
        counts.saleItems += result.count;
      }

      for (const batch of chunk(ids.saleIds)) {
        const result = await tx.sale.deleteMany({
          where: { id: { in: batch }, companyId: ids.companyId },
        });
        counts.sales += result.count;
      }

      for (const batch of chunk(ids.shiftIds)) {
        const result = await tx.cashSession.deleteMany({
          where: { id: { in: batch }, companyId: ids.companyId },
        });
        counts.shifts += result.count;
      }

      for (const batch of chunk(ids.activeProductIds)) {
        const result = await tx.warehouseStock.deleteMany({
          where: {
            companyId: ids.companyId,
            warehouseId: ids.warehouseId,
            productId: { in: batch },
          },
        });
        counts.warehouseStocks += result.count;
      }

      for (const batch of chunk(ids.productIds)) {
        const result = await tx.product.deleteMany({
          where: { id: { in: batch }, companyId: ids.companyId },
        });
        counts.products += result.count;
      }

      return counts;
    },
    { timeout, maxWait: 60_000 },
  );
}

/** Verifies that a sample of the deterministic ids actually exists (proves ownership of the state). */
export async function verifyDeterministicSample(
  prisma: PrismaClient,
  ids: MigrationIdSets,
): Promise<{ checked: number; found: number }> {
  const sample = (values: string[]) => values.slice(0, 3);
  const [products, shifts, sales, items] = await Promise.all([
    prisma.product.count({ where: { companyId: ids.companyId, id: { in: sample(ids.productIds) } } }),
    prisma.cashSession.count({ where: { companyId: ids.companyId, id: { in: sample(ids.shiftIds) } } }),
    prisma.sale.count({ where: { companyId: ids.companyId, id: { in: sample(ids.saleIds) } } }),
    prisma.saleItem.count({ where: { id: { in: sample(ids.saleItemIds) } } }),
  ]);
  return { checked: 12, found: products + shifts + sales + items };
}
