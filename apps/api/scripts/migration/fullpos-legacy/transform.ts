/**
 * Pure transformation logic: legacy SQLite rows -> planned target entities.
 *
 * No I/O, no database access, no side effects. Every function is deterministic:
 * the same input always produces the same output (ids included).
 *
 * Locked rules implemented here:
 *  - the 50 DEMO products (code prefix DEMO-) are excluded entirely
 *  - sales that reference a DEMO product are excluded as whole documents, and a
 *    sale mixing DEMO + real products ABORTS the migration
 *  - the demo-only cash session is excluded (derived from data, asserted = locked id)
 *  - archived real products keep legacy stock ONLY in the manifest (operational stock = 0)
 *  - opening stock is never reconstructed from the sales or the movement ledger
 *  - historical cost/profit always comes from sale_items.purchase_price_snapshot
 *  - customers are never created (customerId stays NULL)
 *  - commission is neutralised (commissionRate/commissionAmount = 0)
 */

import {
  DEFAULT_CATEGORY_FALLBACK,
  DEMO_PRODUCT_CODE_PREFIX,
  HISTORICAL_SHIFT_POLICY,
  HISTORICAL_SHIFT_WINDOW,
  LEGACY_OPERATOR_UNKNOWN,
  LEGACY_TABLE,
  SHIFT_OMISSION_REASON,
} from './constants';
import { deriveTargetId } from './deterministic-uuid';
import { MigrationAbortError } from './errors';
import { assertDemoShiftIsLocked } from './guards';
import {
  centsFromMicro,
  centsFromNumber,
  formatCents,
  formatMicro,
  isoFromEpochMs,
  microFromNumber,
  multiplyMicroByCents,
  sumBigInt,
} from './money';
import type {
  DemoBlock,
  ExcludedRecord,
  LegacyCashSession,
  LegacyCategory,
  LegacyProduct,
  LegacySale,
  LegacySaleItem,
  MigrationPlan,
  PlannedProduct,
  PlannedSale,
  PlannedSaleItem,
  PlannedShift,
  ShiftPolicySummary,
  StockException,
} from './types';

const LEGACY_SALE_STATUS_COMPLETED = 'completed';
const LEGACY_SALE_STATUS_CANCELLED = 'cancelled';

export type MigrationInput = {
  products: LegacyProduct[];
  categories: LegacyCategory[];
  cashSessions: LegacyCashSession[];
  sales: LegacySale[];
  saleItems: LegacySaleItem[];
};

/** DEMO products are identified by their code prefix (data-driven, not by a hardcoded id list). */
export function selectDemoProductIds(products: readonly LegacyProduct[]): number[] {
  return products
    .filter((product) => product.code.trim().toUpperCase().startsWith(DEMO_PRODUCT_CODE_PREFIX))
    .map((product) => product.id)
    .sort((a, b) => a - b);
}

/**
 * A sale that contains both a DEMO product and a real product cannot be excluded
 * as a whole document. That situation aborts the migration.
 */
export function assertNoMixedDemoSales(
  saleItems: readonly LegacySaleItem[],
  demoProductIds: ReadonlySet<number>,
): void {
  const itemsBySale = new Map<number, { demo: number; real: number }>();
  for (const item of saleItems) {
    const bucket = itemsBySale.get(item.sale_id) ?? { demo: 0, real: 0 };
    if (item.product_id !== null && demoProductIds.has(item.product_id)) {
      bucket.demo += 1;
    } else {
      bucket.real += 1;
    }
    itemsBySale.set(item.sale_id, bucket);
  }

  const mixed = [...itemsBySale.entries()]
    .filter(([, bucket]) => bucket.demo > 0 && bucket.real > 0)
    .map(([saleId, bucket]) => ({ saleId, ...bucket }));

  if (mixed.length > 0) {
    throw new MigrationAbortError(
      'MIXED_DEMO_SALE',
      'Hay ventas que mezclan productos DEMO con productos reales: no se pueden excluir como documento completo',
      { mixed },
    );
  }
}

function resolveDemoSaleIds(
  saleItems: readonly LegacySaleItem[],
  demoProductIds: ReadonlySet<number>,
): number[] {
  const ids = new Set<number>();
  for (const item of saleItems) {
    if (item.product_id !== null && demoProductIds.has(item.product_id)) {
      ids.add(item.sale_id);
    }
  }
  return [...ids].sort((a, b) => a - b);
}

/** Sessions whose sales are ALL demo sales (and that have at least one sale). */
export function selectDemoOnlyShiftIds(
  cashSessions: readonly LegacyCashSession[],
  sales: readonly LegacySale[],
  demoSaleIds: ReadonlySet<number>,
): number[] {
  const salesBySession = new Map<number, LegacySale[]>();
  for (const sale of sales) {
    if (sale.session_id === null) continue;
    const bucket = salesBySession.get(sale.session_id) ?? [];
    bucket.push(sale);
    salesBySession.set(sale.session_id, bucket);
  }

  const demoOnly: number[] = [];
  for (const session of cashSessions) {
    const sessionSales = salesBySession.get(session.id) ?? [];
    if (sessionSales.length === 0) continue;
    const allDemo = sessionSales.every((sale) => demoSaleIds.has(sale.id));
    if (allDemo) demoOnly.push(session.id);
  }
  return demoOnly.sort((a, b) => a - b);
}

/* ------------------------------------------------------------------ */
/* Products                                                            */
/* ------------------------------------------------------------------ */

export function planProducts(params: {
  products: readonly LegacyProduct[];
  categories: readonly LegacyCategory[];
  demoProductIds: ReadonlySet<number>;
}): { products: PlannedProduct[]; excluded: ExcludedRecord[]; stockExceptions: StockException[] } {
  const categoryNameById = new Map(params.categories.map((c) => [c.id, c.name.trim()]));
  const products: PlannedProduct[] = [];
  const excluded: ExcludedRecord[] = [];
  const stockExceptions: StockException[] = [];

  for (const product of params.products) {
    if (params.demoProductIds.has(product.id)) {
      excluded.push({
        reason: 'DEMO_PRODUCT',
        legacyTable: LEGACY_TABLE.products,
        legacyId: product.id,
        detail: `Producto sintético DEMO (${product.code}) excluido por completo`,
      });
      continue;
    }

    const isArchived = product.is_active === 0 || product.deleted_at_ms !== null;
    if (isArchived && product.deleted_at_ms === null) {
      throw new MigrationAbortError(
        'UNEXPECTED_PRODUCT_STATE',
        'Producto inactivo sin fecha de borrado legacy',
        { legacyProductId: product.id, code: product.code },
      );
    }

    const legacyStockMicro = microFromNumber(product.stock);
    if (!isArchived && legacyStockMicro < 0n) {
      throw new MigrationAbortError(
        'NEGATIVE_ACTIVE_STOCK',
        'Producto activo con stock negativo en el origen',
        { legacyProductId: product.id, code: product.code, stock: formatCents(legacyStockMicro) },
      );
    }

    const operationalStockMicro = isArchived ? 0n : legacyStockMicro;

    if (isArchived && legacyStockMicro !== 0n) {
      stockExceptions.push({
        kind: 'NEGATIVE_ARCHIVED_STOCK',
        legacyProductId: product.id,
        code: product.code,
        name: product.name,
        legacyStock: formatMicro(legacyStockMicro),
        operationalStock: formatMicro(operationalStockMicro),
        detail:
          'Producto archivado: el stock legacy NO se migra como stock operativo (se conserva en el manifiesto). ' +
          'Se detectó en orígenes legacy con nota "sin stock" (venta sin existencias).',
      });
    }

    const legacyCategoryName = product.category_id === null ? null : categoryNameById.get(product.category_id) ?? null;
    const hasCategory = legacyCategoryName !== null && legacyCategoryName.length > 0;

    products.push({
      legacyId: product.id,
      targetId: deriveTargetId(LEGACY_TABLE.products, product.id),
      code: product.code,
      name: product.name,
      categoria: hasCategory ? (legacyCategoryName as string) : DEFAULT_CATEGORY_FALLBACK,
      categoriaFromLegacy: hasCategory,
      costCents: centsFromNumber(product.purchase_price),
      priceCents: centsFromNumber(product.sale_price),
      legacyStockMicro,
      operationalStockMicro,
      isArchived,
      archivedAtIso: isArchived ? isoFromEpochMs(product.deleted_at_ms) : null,
      legacyStockMinMicro: microFromNumber(product.stock_min),
      imageStatus: product.image_path && product.image_path.trim().length > 0 ? 'PENDING' : 'NONE',
      legacyImagePath: product.image_path,
    });
  }

  products.sort((a, b) => a.legacyId - b.legacyId);
  return { products, excluded, stockExceptions };
}

/* ------------------------------------------------------------------ */
/* Shifts                                                              */
/* ------------------------------------------------------------------ */

export type ShiftPlan = {
  shifts: PlannedShift[];
  excluded: ExcludedRecord[];
  /** Real CLOSED legacy sessions intentionally NOT migrated (older than the window). Never failures. */
  notImportedLegacyIds: number[];
  /** Real legacy sessions skipped because they are not CLOSED (reported, never fatal). */
  skippedNotClosedLegacyIds: number[];
  boundary: {
    oldestImportedClosedAt: string | null;
    newestNotImportedClosedAt: string | null;
  };
};

/**
 * Selects the historical shifts to migrate.
 *
 * LOCKED RULE: from the real (non-DEMO) CLOSED legacy sessions, take the newest
 * `window` (50) ordered by `closed_at_ms DESC` (legacy id as deterministic tie-break).
 * Everything older is intentionally omitted, never treated as an error, and the sales
 * of those sessions are still imported with `cashSessionId = NULL`.
 *
 * The window is 50 because the Cloud history screen already retrieves up to 60 CLOSED
 * shifts; importing 50 leaves room for future shifts without touching that endpoint.
 */
export function planShifts(params: {
  cashSessions: readonly LegacyCashSession[];
  demoShiftIds: ReadonlySet<number>;
  window?: number;
}): ShiftPlan {
  const window = params.window ?? HISTORICAL_SHIFT_WINDOW;
  const excluded: ExcludedRecord[] = [];
  const skippedNotClosedLegacyIds: number[] = [];
  const candidates: LegacyCashSession[] = [];

  for (const session of params.cashSessions) {
    if (params.demoShiftIds.has(session.id)) {
      excluded.push({
        reason: 'DEMO_SHIFT',
        legacyTable: LEGACY_TABLE.cashSessions,
        legacyId: session.id,
        detail: 'Turno que solo contiene ventas DEMO: excluido por completo',
      });
      continue;
    }

    // Only real CLOSED sessions are eligible. A non-CLOSED session is reported and skipped
    // (never imported as open historical cash state, never an abort).
    if (session.status.trim().toUpperCase() !== 'CLOSED') {
      skippedNotClosedLegacyIds.push(session.id);
      continue;
    }

    // A CLOSED session without a close timestamp cannot be ordered deterministically.
    if (session.closed_at_ms === null) {
      throw new MigrationAbortError(
        'UNEXPECTED_SHIFT_STATE',
        'Turno legacy CLOSED sin fecha de cierre',
        { legacySessionId: session.id },
      );
    }

    candidates.push(session);
  }

  // Deterministic selection: newest historical close first, legacy id as tie-break.
  const ordered = [...candidates].sort((a, b) => {
    const byClose = (b.closed_at_ms as number) - (a.closed_at_ms as number);
    return byClose !== 0 ? byClose : b.id - a.id;
  });

  const selected = ordered.slice(0, window);
  const omitted = ordered.slice(window);

  const shifts: PlannedShift[] = selected
    .map((session) => {
      if (!session.business_date || session.business_date.trim().length === 0) {
        throw new MigrationAbortError(
          'UNEXPECTED_SHIFT_STATE',
          'Turno legacy sin fecha de negocio',
          { legacySessionId: session.id },
        );
      }
      return {
        legacyId: session.id,
        targetId: deriveTargetId(LEGACY_TABLE.cashSessions, session.id),
        businessDate: session.business_date.trim(),
        status: 'CLOSED' as const,
        legacyUserName: session.user_name,
        openedAtIso: isoFromEpochMs(session.opened_at_ms) as string,
        closedAtIso: isoFromEpochMs(session.closed_at_ms) as string,
        initialAmountCents: centsFromNumber(session.initial_amount),
        closingAmountCents: centsFromNumber(session.closing_amount ?? 0),
        expectedAmountCents: centsFromNumber(session.expected_cash ?? 0),
        differenceCents: centsFromNumber(session.difference ?? 0),
        salesCount: 0,
      };
    })
    .sort((a, b) => a.legacyId - b.legacyId);

  const oldestImportedClosedAt =
    selected.length > 0
      ? isoFromEpochMs(Math.min(...selected.map((session) => session.closed_at_ms as number)))
      : null;
  const newestNotImportedClosedAt =
    omitted.length > 0
      ? isoFromEpochMs(Math.max(...omitted.map((session) => session.closed_at_ms as number)))
      : null;

  return {
    shifts,
    excluded,
    notImportedLegacyIds: omitted.map((session) => session.id).sort((a, b) => a - b),
    skippedNotClosedLegacyIds,
    boundary: { oldestImportedClosedAt, newestNotImportedClosedAt },
  };
}

/* ------------------------------------------------------------------ */
/* Sales + sale items                                                  */
/* ------------------------------------------------------------------ */

export function planSalesAndItems(params: {
  sales: readonly LegacySale[];
  saleItems: readonly LegacySaleItem[];
  demoSaleIds: ReadonlySet<number>;
  productById: ReadonlyMap<number, PlannedProduct>;
  /** Every real session present in the source (used only to detect dangling references). */
  sourceShiftIds: ReadonlySet<number>;
  /** Only the shifts inside the migration window get a target id. */
  shiftIdByLegacySession: ReadonlyMap<number, string>;
}): {
  sales: PlannedSale[];
  saleItems: PlannedSaleItem[];
  excluded: ExcludedRecord[];
} {
  const itemsBySale = new Map<number, LegacySaleItem[]>();
  for (const item of params.saleItems) {
    const bucket = itemsBySale.get(item.sale_id) ?? [];
    bucket.push(item);
    itemsBySale.set(item.sale_id, bucket);
  }

  const sales: PlannedSale[] = [];
  const saleItems: PlannedSaleItem[] = [];
  const excluded: ExcludedRecord[] = [];

  for (const sale of params.sales) {
    if (params.demoSaleIds.has(sale.id)) {
      excluded.push({
        reason: 'DEMO_SALE',
        legacyTable: LEGACY_TABLE.sales,
        legacyId: sale.id,
        detail: `Venta DEMO (${sale.local_code}) excluida como documento completo`,
      });
      for (const item of itemsBySale.get(sale.id) ?? []) {
        excluded.push({
          reason: 'DEMO_SALE_ITEM',
          legacyTable: LEGACY_TABLE.saleItems,
          legacyId: item.id,
          detail: `Línea DEMO de la venta ${sale.id} excluida`,
        });
      }
      continue;
    }

    const status = sale.status.trim().toLowerCase();
    if (status !== LEGACY_SALE_STATUS_COMPLETED && status !== LEGACY_SALE_STATUS_CANCELLED) {
      throw new MigrationAbortError('UNKNOWN_SALE_STATUS', 'Estado de venta legacy no soportado', {
        legacySaleId: sale.id,
        status: sale.status,
      });
    }

    // EVERY sale is imported. The shift link is optional: a sale whose legacy shift falls
    // outside the migration window keeps cashSessionId = NULL (never discarded, never remapped).
    if (sale.session_id !== null && !params.sourceShiftIds.has(sale.session_id)) {
      throw new MigrationAbortError(
        'SALE_SHIFT_UNKNOWN',
        'La venta apunta a un turno que no existe en el origen',
        { legacySaleId: sale.id, legacySessionId: sale.session_id },
      );
    }
    const targetShiftId =
      sale.session_id === null
        ? null
        : params.shiftIdByLegacySession.get(sale.session_id) ?? null;

    const legacyItems = itemsBySale.get(sale.id) ?? [];
    if (legacyItems.length === 0) {
      throw new MigrationAbortError('SALE_WITHOUT_ITEMS', 'Venta legacy sin líneas', {
        legacySaleId: sale.id,
      });
    }

    let revenueCents = 0n;
    let costCents = 0n;

    for (const item of legacyItems) {
      if (item.product_id === null) {
        throw new MigrationAbortError('SALE_ITEM_WITHOUT_PRODUCT', 'Línea de venta sin producto', {
          legacySaleItemId: item.id,
        });
      }
      const product = params.productById.get(item.product_id);
      if (!product) {
        throw new MigrationAbortError(
          'SALE_ITEM_PRODUCT_NOT_MIGRATED',
          'La línea apunta a un producto que no se migra',
          { legacySaleItemId: item.id, legacyProductId: item.product_id },
        );
      }

      const qtyMicro = microFromNumber(item.qty);
      const unitPriceCents = centsFromNumber(item.unit_price);
      const costUnitCents = centsFromNumber(item.purchase_price_snapshot);
      const lineTotalCents = centsFromNumber(item.total_line);
      const lineDiscountCents = centsFromNumber(item.discount_line);
      const subtotalCostCents = multiplyMicroByCents(qtyMicro, costUnitCents);
      const profitCents = lineTotalCents - subtotalCostCents;

      revenueCents += lineTotalCents;
      costCents += subtotalCostCents;

      saleItems.push({
        legacyId: item.id,
        targetId: deriveTargetId(LEGACY_TABLE.saleItems, item.id),
        legacySaleId: sale.id,
        targetSaleId: deriveTargetId(LEGACY_TABLE.sales, sale.id),
        legacyProductId: item.product_id,
        targetProductId: product.targetId,
        productCodeSnapshot: item.product_code_snapshot,
        productNameSnapshot: item.product_name_snapshot,
        qtyMicro,
        unitPriceCents,
        costUnitCents,
        lineTotalCents,
        lineDiscountCents,
        subtotalCostCents,
        profitCents,
      });
    }

    const declaredSubtotalCents = centsFromNumber(sale.subtotal);
    if (declaredSubtotalCents !== revenueCents) {
      throw new MigrationAbortError(
        'SALE_TOTAL_MISMATCH',
        'El subtotal de la venta no coincide con la suma de sus líneas',
        {
          legacySaleId: sale.id,
          declaredSubtotal: formatCents(declaredSubtotalCents),
          sumOfLines: formatCents(revenueCents),
        },
      );
    }

    const itbisCents = centsFromNumber(sale.itbis_amount);
    const declaredTotalCents = centsFromNumber(sale.total);
    if (declaredTotalCents !== revenueCents + itbisCents) {
      throw new MigrationAbortError(
        'SALE_TOTAL_MISMATCH',
        'El total de la venta no coincide con subtotal + ITBIS',
        {
          legacySaleId: sale.id,
          declaredTotal: formatCents(declaredTotalCents),
          computed: formatCents(revenueCents + itbisCents),
        },
      );
    }

    const isCancelled = status === LEGACY_SALE_STATUS_CANCELLED;

    sales.push({
      legacyId: sale.id,
      targetId: deriveTargetId(LEGACY_TABLE.sales, sale.id),
      localCode: sale.local_code,
      saleDateIso: isoFromEpochMs(sale.created_at_ms) as string,
      status: isCancelled ? 'CANCELLED' : 'PAID',
      cancelledAtIso: isCancelled ? isoFromEpochMs(sale.updated_at_ms) : null,
      legacySessionId: sale.session_id,
      targetShiftId,
      legacyOperator: LEGACY_OPERATOR_UNKNOWN,
      revenueCents,
      itbisCents,
      costCents,
      profitCents: revenueCents - costCents,
      itemCount: legacyItems.length,
    });
  }

  sales.sort((a, b) => a.legacyId - b.legacyId);
  saleItems.sort((a, b) => a.legacyId - b.legacyId);
  return { sales, saleItems, excluded };
}

/* ------------------------------------------------------------------ */
/* Orchestrator                                                        */
/* ------------------------------------------------------------------ */

export function planMigration(input: MigrationInput): MigrationPlan {
  const demoProductIdList = selectDemoProductIds(input.products);
  const demoProductIds = new Set(demoProductIdList);
  assertNoMixedDemoSales(input.saleItems, demoProductIds);

  const demoSaleIdList = resolveDemoSaleIds(input.saleItems, demoProductIds);
  const demoSaleIds = new Set(demoSaleIdList);

  const demoShiftIdList = selectDemoOnlyShiftIds(input.cashSessions, input.sales, demoSaleIds);
  assertDemoShiftIsLocked(demoShiftIdList);
  const demoShiftIds = new Set(demoShiftIdList);

  const productPlan = planProducts({
    products: input.products,
    categories: input.categories,
    demoProductIds,
  });
  const shiftPlan = planShifts({ cashSessions: input.cashSessions, demoShiftIds });

  const productById = new Map(productPlan.products.map((p) => [p.legacyId, p]));
  const shiftIdByLegacySession = new Map(shiftPlan.shifts.map((s) => [s.legacyId, s.targetId]));
  // Every real (non-DEMO) source session, whether or not it is inside the migration window.
  const sourceShiftIds = new Set(
    input.cashSessions
      .filter((session) => !demoShiftIds.has(session.id))
      .map((session) => session.id),
  );

  const salesPlan = planSalesAndItems({
    sales: input.sales,
    saleItems: input.saleItems,
    demoSaleIds,
    productById,
    sourceShiftIds,
    shiftIdByLegacySession,
  });

  // shift sales counters (imported sales only)
  const salesCountByShift = new Map<string, number>();
  for (const sale of salesPlan.sales) {
    if (sale.targetShiftId === null) continue;
    salesCountByShift.set(sale.targetShiftId, (salesCountByShift.get(sale.targetShiftId) ?? 0) + 1);
  }
  const shifts = shiftPlan.shifts.map((shift) => ({
    ...shift,
    salesCount: salesCountByShift.get(shift.targetId) ?? 0,
  }));

  const demoItems = input.saleItems.filter((item) => demoSaleIds.has(item.sale_id));
  const demoSales = input.sales.filter((sale) => demoSaleIds.has(sale.id));

  const demo: DemoBlock = {
    productIds: demoProductIdList,
    saleIds: demoSaleIdList,
    saleItemIds: demoItems.map((item) => item.id).sort((a, b) => a - b),
    shiftIds: demoShiftIdList,
    productCount: demoProductIdList.length,
    saleCount: demoSaleIdList.length,
    saleItemCount: demoItems.length,
    shiftCount: demoShiftIdList.length,
    stockCents: sumBigInt([
      ...input.products
        .filter((p) => demoProductIds.has(p.id))
        .map((p) => centsFromNumber(p.stock)),
    ]),
    itbisCents: sumBigInt(demoSales.map((sale) => centsFromNumber(sale.itbis_amount))),
    revenueCents: sumBigInt(demoSales.map((sale) => centsFromNumber(sale.total))),
  };

  const activeProducts = productPlan.products.filter((p) => !p.isArchived);
  const archivedProducts = productPlan.products.filter((p) => p.isArchived);

  const totals = {
    products: productPlan.products.length,
    activeProducts: activeProducts.length,
    archivedProducts: archivedProducts.length,
    openingStockCents: sumBigInt(activeProducts.map((p) => centsFromMicro(p.operationalStockMicro))),
    activeStockPositive: activeProducts.filter((p) => p.operationalStockMicro > 0n).length,
    activeStockZero: activeProducts.filter((p) => p.operationalStockMicro === 0n).length,
    activeStockNegative: activeProducts.filter((p) => p.operationalStockMicro < 0n).length,
    archivedOperationalStockCents: sumBigInt(archivedProducts.map((p) => p.operationalStockMicro)),
    shifts: shifts.length,
    sourceRealShifts: sourceShiftIds.size,
    shiftsNotImported: shiftPlan.notImportedLegacyIds.length,
    salesLinkedToImportedShifts: salesPlan.sales.filter((sale) => sale.targetShiftId !== null).length,
    salesWithoutShiftLink: salesPlan.sales.filter((sale) => sale.targetShiftId === null).length,
    sales: salesPlan.sales.length,
    completedSales: salesPlan.sales.filter((sale) => sale.status === 'PAID').length,
    cancelledSales: salesPlan.sales.filter((sale) => sale.status === 'CANCELLED').length,
    saleItems: salesPlan.saleItems.length,
    revenueCents: sumBigInt(salesPlan.sales.map((sale) => sale.revenueCents)),
    costCents: sumBigInt(salesPlan.sales.map((sale) => sale.costCents)),
    profitCents: sumBigInt(salesPlan.sales.map((sale) => sale.profitCents)),
    itbisCents: sumBigInt(salesPlan.sales.map((sale) => sale.itbisCents)),
    ncf: 0,
    customersCreated: 0,
    legacyUsersCreated: 0,
    suppliersCreated: 0,
    purchasesCreated: 0,
    inventoryMovementsImported: 0,
    cashMovementsImported: 0,
    cashboxDailyImported: 0,
    imagesPending: productPlan.products.filter((p) => p.imageStatus === 'PENDING').length,
  };

  const excluded: ExcludedRecord[] = [
    ...productPlan.excluded,
    ...shiftPlan.excluded,
    ...salesPlan.excluded,
  ].sort((a, b) =>
    a.legacyTable === b.legacyTable
      ? a.legacyId - b.legacyId
      : a.legacyTable.localeCompare(b.legacyTable),
  );

  const shiftPolicy: ShiftPolicySummary = {
    policy: HISTORICAL_SHIFT_POLICY,
    window: HISTORICAL_SHIFT_WINDOW,
    reason: SHIFT_OMISSION_REASON,
    sourceRealShifts: sourceShiftIds.size,
    imported: shifts.length,
    notImported: shiftPlan.notImportedLegacyIds.length,
    notImportedLegacyIds: shiftPlan.notImportedLegacyIds,
    skippedNotClosedLegacyIds: shiftPlan.skippedNotClosedLegacyIds,
    boundary: shiftPlan.boundary,
  };

  return {
    products: productPlan.products,
    shifts,
    sales: salesPlan.sales,
    saleItems: salesPlan.saleItems,
    excluded,
    stockExceptions: productPlan.stockExceptions,
    demo,
    shiftPolicy,
    totals,
  };
}
