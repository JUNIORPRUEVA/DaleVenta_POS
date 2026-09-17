/**
 * Immutable local manifest for the legacy migration.
 *
 * The manifest is the audit artifact and the rollback source: it holds the
 * legacy -> target id pairs derived from the deterministic UUIDv5 namespace,
 * the excluded DEMO block, the stock exceptions and the reconciliation result.
 *
 * It never contains secrets, credentials or customer-identifying data beyond the
 * legacy business names already present in the tenant's own catalog.
 */

import { createHash } from 'node:crypto';
import {
  EXPECTED_SOURCE_SHA256,
  MIGRATION_VERSION,
  SOURCE_SYSTEM,
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_OWNER_USER_ID,
  TARGET_TERMINAL_ID,
  TARGET_WAREHOUSE_ID,
  LEGACY_OPERATOR_UNKNOWN,
} from './constants';
import { formatCents, formatMicro } from './money';
import type { MigrationPlan, ReconciliationReport } from './types';

export type Manifest = {
  manifestVersion: number;
  migrationVersion: string;
  sourceSystem: string;
  generatedAt: string;
  source: {
    path: string;
    sha256: string;
    expectedSha256: string;
    sha256Matches: boolean;
    integrityCheck: string;
    foreignKeyViolations: number;
    userVersion: number;
  };
  target: {
    companyId: string;
    companyName: string;
    warehouseId: string;
    terminalId: string;
    ownerUserId: string;
  };
  totals: Record<string, string | number>;
  historicalShiftPolicy: {
    policy: string;
    window: number;
    reason: string;
    sourceRealShifts: number;
    imported: number;
    notImported: number;
    notImportedLegacyIds: number[];
    skippedNotClosedLegacyIds: number[];
    boundary: { oldestImportedClosedAt: string | null; newestNotImportedClosedAt: string | null };
  };
  products: Array<{
    legacyId: number;
    targetId: string;
    code: string;
    name: string;
    status: 'ACTIVE' | 'ARCHIVED';
    legacyStock: string;
    operationalStock: string;
    legacyStockMin: string;
    categoria: string;
    categoriaFromLegacy: boolean;
    imageStatus: string;
    legacyImagePath: string | null;
    archivedAt: string | null;
  }>;
  shifts: Array<{
    legacySessionId: number;
    targetId: string;
    businessDate: string;
    status: string;
    legacyUserName: string;
    legacyOperator: string;
    salesCount: number;
    openedAt: string;
    closedAt: string;
    initialAmount: string;
    closingAmount: string;
    expectedAmount: string;
    difference: string;
  }>;
  sales: Array<{
    legacyId: number;
    targetId: string;
    localCode: string;
    saleDate: string;
    status: string;
    legacySessionId: number | null;
    targetCashSessionId: string | null;
    legacyOperator: string;
    userId: string;
    customerId: null;
    revenue: string;
    cost: string;
    profit: string;
    itemCount: number;
    commissionRate: string;
    commissionAmount: string;
  }>;
  saleItems: Array<{
    legacyId: number;
    targetId: string;
    legacySaleId: number;
    targetSaleId: string;
    legacyProductId: number;
    targetProductId: string;
    productCodeSnapshot: string;
    productNameSnapshot: string;
    qty: string;
    unitPrice: string;
    historicalCost: string;
    lineTotal: string;
    lineDiscount: string;
    subtotalCost: string;
    profit: string;
  }>;
  excluded: Array<{
    reason: string;
    legacyTable: string;
    legacyId: number;
    detail: string;
  }>;
  stockExceptions: Array<{
    kind: string;
    legacyProductId: number;
    code: string;
    name: string;
    legacyStock: string;
    operationalStock: string;
    detail: string;
  }>;
  notMigrated: Array<{ entity: string; reason: string }>;
  demo: {
    productIds: number[];
    saleIds: number[];
    saleItemIds: number[];
    shiftIds: number[];
    productCount: number;
    saleCount: number;
    saleItemCount: number;
    shiftCount: number;
    stock: string;
    itbis: string;
    revenue: string;
  };
  reconciliation: {
    verdict: string;
    generatedAt: string;
    checks: Array<{ metric: string; expected: string; actual: string; ok: boolean }>;
    failures: number;
  };
};

const NOT_MIGRATED: Array<{ entity: string; reason: string }> = [
  { entity: 'clients', reason: 'Fuera de alcance (Fase 3): las ventas históricas usan customerId = NULL.' },
  { entity: 'legacy_users', reason: 'No se crean usuarios legacy; no se migran PIN, hash ni credenciales.' },
  { entity: 'suppliers', reason: 'Fuera de alcance (Fase 3).' },
  { entity: 'purchases', reason: 'Fuera de alcance (Fase 3): órdenes de compra incompletas, sin recepciones.' },
  { entity: 'purchase_items', reason: 'Fuera de alcance (Fase 3).' },
  { entity: 'stock_movements', reason: 'Ledger inconsistente: no se reconstruye stock ni se reimporta el movimiento.' },
  { entity: 'cash_movements', reason: 'Fuera de alcance: no se importan gastos ni ajustes de caja.' },
  { entity: 'cashbox_daily', reason: 'No es requerido por ninguna lectura de turnos (verificado en el código).' },
  { entity: 'expenses', reason: 'Fuera de alcance (Fase 3).' },
  { entity: 'audit_log', reason: 'Sin modelo destino compatible.' },
  { entity: 'backup_history', reason: 'Estado técnico local de la máquina.' },
  { entity: 'sync_outbox_product_sync_outbox', reason: 'Estado técnico de sincronización.' },
  { entity: 'fiscal_ncf', reason: 'La empresa no factura fiscalmente: 0 NCF, 0 ITBIS real, sin Tax ni NcfSequence.' },
  { entity: 'legacy_configuration', reason: 'Fuera de alcance: la configuración del tenant destino no se modifica.' },
  { entity: 'demo_data', reason: 'Excluido por decisión bloqueada (productos, ventas, líneas y turno DEMO).' },
];

function stockString(micro: bigint): string {
  return formatMicro(micro);
}

function qtyString(micro: bigint): string {
  return formatMicro(micro);
}

export function buildManifest(params: {
  plan: MigrationPlan;
  reconciliation: ReconciliationReport;
  source: {
    path: string;
    sha256: string;
    integrityCheck: string;
    foreignKeyViolations: number;
    userVersion: number;
  };
  generatedAt: string;
  warehouseId: string;
}): Manifest {
  const { plan, reconciliation, source, generatedAt } = params;

  return {
    manifestVersion: 1,
    migrationVersion: MIGRATION_VERSION,
    sourceSystem: SOURCE_SYSTEM,
    generatedAt,
    source: {
      path: source.path,
      sha256: source.sha256,
      expectedSha256: EXPECTED_SOURCE_SHA256,
      sha256Matches: source.sha256.toUpperCase() === EXPECTED_SOURCE_SHA256.toUpperCase(),
      integrityCheck: source.integrityCheck,
      foreignKeyViolations: source.foreignKeyViolations,
      userVersion: source.userVersion,
    },
    target: {
      companyId: TARGET_COMPANY_ID,
      companyName: TARGET_COMPANY_NAME,
      warehouseId: params.warehouseId,
      terminalId: TARGET_TERMINAL_ID,
      ownerUserId: TARGET_OWNER_USER_ID,
    },
    totals: {
      products: plan.totals.products,
      activeProducts: plan.totals.activeProducts,
      archivedProducts: plan.totals.archivedProducts,
      openingStock: formatCents(plan.totals.openingStockCents),
      archivedOperationalStock: formatCents(plan.totals.archivedOperationalStockCents),
      shifts: plan.totals.shifts,
      sourceRealShifts: plan.totals.sourceRealShifts,
      historicalShiftsNotImported: plan.totals.shiftsNotImported,
      salesLinkedToImportedShifts: plan.totals.salesLinkedToImportedShifts,
      salesWithoutShiftLink: plan.totals.salesWithoutShiftLink,
      sales: plan.totals.sales,
      completedSales: plan.totals.completedSales,
      cancelledSales: plan.totals.cancelledSales,
      saleItems: plan.totals.saleItems,
      revenue: formatCents(plan.totals.revenueCents),
      cost: formatCents(plan.totals.costCents),
      profit: formatCents(plan.totals.profitCents),
      itbis: formatCents(plan.totals.itbisCents),
      ncf: plan.totals.ncf,
      customersCreated: plan.totals.customersCreated,
      legacyUsersCreated: plan.totals.legacyUsersCreated,
      suppliersCreated: plan.totals.suppliersCreated,
      purchasesCreated: plan.totals.purchasesCreated,
      inventoryMovementsImported: plan.totals.inventoryMovementsImported,
      cashMovementsImported: plan.totals.cashMovementsImported,
      cashboxDailyImported: plan.totals.cashboxDailyImported,
      imagesPending: plan.totals.imagesPending,
    },
    historicalShiftPolicy: {
      policy: plan.shiftPolicy.policy,
      window: plan.shiftPolicy.window,
      reason: plan.shiftPolicy.reason,
      sourceRealShifts: plan.shiftPolicy.sourceRealShifts,
      imported: plan.shiftPolicy.imported,
      notImported: plan.shiftPolicy.notImported,
      notImportedLegacyIds: plan.shiftPolicy.notImportedLegacyIds,
      skippedNotClosedLegacyIds: plan.shiftPolicy.skippedNotClosedLegacyIds,
      boundary: plan.shiftPolicy.boundary,
    },
    products: plan.products.map((product) => ({
      legacyId: product.legacyId,
      targetId: product.targetId,
      code: product.code,
      name: product.name,
      status: product.isArchived ? 'ARCHIVED' : 'ACTIVE',
      legacyStock: stockString(product.legacyStockMicro),
      operationalStock: stockString(product.operationalStockMicro),
      legacyStockMin: stockString(product.legacyStockMinMicro),
      categoria: product.categoria,
      categoriaFromLegacy: product.categoriaFromLegacy,
      imageStatus: product.imageStatus,
      legacyImagePath: product.legacyImagePath,
      archivedAt: product.archivedAtIso,
    })),
    shifts: plan.shifts.map((shift) => ({
      legacySessionId: shift.legacyId,
      targetId: shift.targetId,
      businessDate: shift.businessDate,
      status: shift.status,
      legacyUserName: shift.legacyUserName,
      legacyOperator: LEGACY_OPERATOR_UNKNOWN,
      salesCount: shift.salesCount,
      openedAt: shift.openedAtIso,
      closedAt: shift.closedAtIso,
      initialAmount: formatCents(shift.initialAmountCents),
      closingAmount: formatCents(shift.closingAmountCents),
      expectedAmount: formatCents(shift.expectedAmountCents),
      difference: formatCents(shift.differenceCents),
    })),
    sales: plan.sales.map((sale) => ({
      legacyId: sale.legacyId,
      targetId: sale.targetId,
      localCode: sale.localCode,
      saleDate: sale.saleDateIso,
      status: sale.status,
      legacySessionId: sale.legacySessionId,
      targetCashSessionId: sale.targetShiftId,
      legacyOperator: sale.legacyOperator,
      userId: TARGET_OWNER_USER_ID,
      customerId: null,
      revenue: formatCents(sale.revenueCents),
      cost: formatCents(sale.costCents),
      profit: formatCents(sale.profitCents),
      itemCount: sale.itemCount,
      commissionRate: '0.0000',
      commissionAmount: '0.00',
    })),
    saleItems: plan.saleItems.map((item) => ({
      legacyId: item.legacyId,
      targetId: item.targetId,
      legacySaleId: item.legacySaleId,
      targetSaleId: item.targetSaleId,
      legacyProductId: item.legacyProductId,
      targetProductId: item.targetProductId,
      productCodeSnapshot: item.productCodeSnapshot,
      productNameSnapshot: item.productNameSnapshot,
      qty: qtyString(item.qtyMicro),
      unitPrice: formatCents(item.unitPriceCents),
      historicalCost: formatCents(item.costUnitCents),
      lineTotal: formatCents(item.lineTotalCents),
      lineDiscount: formatCents(item.lineDiscountCents),
      subtotalCost: formatCents(item.subtotalCostCents),
      profit: formatCents(item.profitCents),
    })),
    excluded: plan.excluded.map((entry) => ({
      reason: entry.reason,
      legacyTable: entry.legacyTable,
      legacyId: entry.legacyId,
      detail: entry.detail,
    })),
    stockExceptions: plan.stockExceptions.map((exception) => ({
      kind: exception.kind,
      legacyProductId: exception.legacyProductId,
      code: exception.code,
      name: exception.name,
      legacyStock: exception.legacyStock,
      operationalStock: exception.operationalStock,
      detail: exception.detail,
    })),
    notMigrated: NOT_MIGRATED,
    demo: {
      productIds: plan.demo.productIds,
      saleIds: plan.demo.saleIds,
      saleItemIds: plan.demo.saleItemIds,
      shiftIds: plan.demo.shiftIds,
      productCount: plan.demo.productCount,
      saleCount: plan.demo.saleCount,
      saleItemCount: plan.demo.saleItemCount,
      shiftCount: plan.demo.shiftCount,
      stock: formatCents(plan.demo.stockCents),
      itbis: formatCents(plan.demo.itbisCents),
      revenue: formatCents(plan.demo.revenueCents),
    },
    reconciliation: {
      verdict: reconciliation.verdict,
      generatedAt: reconciliation.generatedAt,
      checks: reconciliation.checks,
      failures: reconciliation.failures.length,
    },
  };
}

export function serializeManifest(manifest: Manifest): string {
  return `${JSON.stringify(manifest, null, 2)}\n`;
}

export function sha256Text(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex').toUpperCase();
}

/**
 * Canonical serialization with sorted object keys, so the digest does not depend on
 * property order. The manifest file hash changes on every run because `generatedAt`
 * is regenerated; this digest is stable for the same source + plan.
 */
function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value) ?? 'null';
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableStringify(entry)).join(',')}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, entryValue]) => entryValue !== undefined)
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0));
  return `{${entries.map(([key, entryValue]) => `${JSON.stringify(key)}:${stableStringify(entryValue)}`).join(',')}}`;
}

export type ManifestFingerprint = {
  /** Digest of the manifest content with timestamps excluded (immutable per source+plan). */
  contentDigest: string;
  /** Digest of the deterministic target id sets (the rollback identity set). */
  idSets: {
    products: string;
    warehouseStockScope: string;
    shifts: string;
    sales: string;
    saleItems: string;
  };
  counts: {
    products: number;
    activeProducts: number;
    archivedProducts: number;
    warehouseStockScope: number;
    shifts: number;
    sales: number;
    saleItems: number;
  };
};

export function manifestFingerprint(manifest: Manifest): ManifestFingerprint {
  const { generatedAt: _manifestGeneratedAt, reconciliation, ...content } = manifest;
  const { generatedAt: _reconciliationGeneratedAt, ...reconciliationContent } = reconciliation;

  const digestOfIds = (ids: string[]): string => sha256Text([...ids].sort().join('\n'));
  const activeProducts = manifest.products.filter((product) => product.status === 'ACTIVE');

  return {
    contentDigest: sha256Text(
      stableStringify({ ...content, reconciliation: reconciliationContent }),
    ),
    idSets: {
      products: digestOfIds(manifest.products.map((product) => product.targetId)),
      // WarehouseStock rows have no deterministic id: their identity is
      // (companyId, warehouseId, productId of the active products).
      warehouseStockScope: digestOfIds(activeProducts.map((product) => product.targetId)),
      shifts: digestOfIds(manifest.shifts.map((shift) => shift.targetId)),
      sales: digestOfIds(manifest.sales.map((sale) => sale.targetId)),
      saleItems: digestOfIds(manifest.saleItems.map((item) => item.targetId)),
    },
    counts: {
      products: manifest.products.length,
      activeProducts: activeProducts.length,
      archivedProducts: manifest.products.length - activeProducts.length,
      warehouseStockScope: activeProducts.length,
      shifts: manifest.shifts.length,
      sales: manifest.sales.length,
      saleItems: manifest.saleItems.length,
    },
  };
}
