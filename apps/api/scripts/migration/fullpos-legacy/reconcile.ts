/**
 * Reconciliation of the dry-run against the authoritative Phase 2 / 2.5 figures.
 * Pure function: no I/O.
 *
 * Any mismatch makes the dry-run NO-GO (and therefore blocks the execute path).
 */

import { EXPECTED, HISTORICAL_SHIFT_POLICY } from './constants';
import { formatCents } from './money';
import type { MigrationPlan, ReconciliationCheck, ReconciliationReport } from './types';

type CheckInput = { metric: string; expected: string; actual: string };

/** Exported so the database-side reconciliation can build the same check shape. */
export function buildCheck({ metric, expected, actual }: CheckInput): ReconciliationCheck {
  return { metric, expected, actual, ok: expected === actual };
}

export function buildReconciliation(
  plan: MigrationPlan,
  generatedAt: string = new Date().toISOString(),
): ReconciliationReport {
  const totals = plan.totals;
  const importedShiftIds = new Set(plan.shifts.map((shift) => shift.targetId));

  const checks: ReconciliationCheck[] = [
    buildCheck({ metric: 'products', expected: String(EXPECTED.products), actual: String(totals.products) }),
    buildCheck({
      metric: 'active_products',
      expected: String(EXPECTED.activeProducts),
      actual: String(totals.activeProducts),
    }),
    buildCheck({
      metric: 'archived_products',
      expected: String(EXPECTED.archivedProducts),
      actual: String(totals.archivedProducts),
    }),
    buildCheck({
      metric: 'opening_stock',
      expected: EXPECTED.openingStock,
      actual: formatCents(totals.openingStockCents),
    }),
    buildCheck({
      metric: 'active_stock_positive',
      expected: String(EXPECTED.activeStockPositive),
      actual: String(totals.activeStockPositive),
    }),
    buildCheck({
      metric: 'active_stock_zero',
      expected: String(EXPECTED.activeStockZero),
      actual: String(totals.activeStockZero),
    }),
    buildCheck({
      metric: 'active_stock_negative',
      expected: String(EXPECTED.activeStockNegative),
      actual: String(totals.activeStockNegative),
    }),
    buildCheck({
      metric: 'archived_operational_stock',
      expected: EXPECTED.archivedOperationalStock,
      actual: formatCents(totals.archivedOperationalStockCents),
    }),
    buildCheck({ metric: 'shifts', expected: String(EXPECTED.shifts), actual: String(totals.shifts) }),
    buildCheck({
      metric: 'shift_policy',
      expected: HISTORICAL_SHIFT_POLICY,
      actual: plan.shiftPolicy.policy,
    }),
    buildCheck({
      metric: 'source_real_shifts',
      expected: String(EXPECTED.sourceRealShifts),
      actual: String(totals.sourceRealShifts),
    }),
    buildCheck({
      metric: 'historical_shifts_not_imported',
      expected: String(EXPECTED.shiftsNotImported),
      actual: String(totals.shiftsNotImported),
    }),
    buildCheck({
      metric: 'sales_linked_to_imported_shifts',
      expected: String(EXPECTED.salesLinkedToImportedShifts),
      actual: String(totals.salesLinkedToImportedShifts),
    }),
    buildCheck({
      metric: 'sales_without_shift_link',
      expected: String(EXPECTED.salesWithoutShiftLink),
      actual: String(totals.salesWithoutShiftLink),
    }),
    buildCheck({ metric: 'sales', expected: String(EXPECTED.sales), actual: String(totals.sales) }),
    buildCheck({
      metric: 'completed_sales',
      expected: String(EXPECTED.completedSales),
      actual: String(totals.completedSales),
    }),
    buildCheck({
      metric: 'cancelled_sales',
      expected: String(EXPECTED.cancelledSales),
      actual: String(totals.cancelledSales),
    }),
    buildCheck({
      metric: 'sale_items',
      expected: String(EXPECTED.saleItems),
      actual: String(totals.saleItems),
    }),
    buildCheck({
      metric: 'revenue',
      expected: EXPECTED.revenue,
      actual: formatCents(totals.revenueCents),
    }),
    buildCheck({ metric: 'cost', expected: EXPECTED.cost, actual: formatCents(totals.costCents) }),
    buildCheck({ metric: 'profit', expected: EXPECTED.profit, actual: formatCents(totals.profitCents) }),
    buildCheck({ metric: 'itbis', expected: EXPECTED.itbis, actual: formatCents(totals.itbisCents) }),
    buildCheck({ metric: 'ncf', expected: String(EXPECTED.ncf), actual: String(totals.ncf) }),
    buildCheck({
      metric: 'customers_created',
      expected: String(EXPECTED.customersCreated),
      actual: String(totals.customersCreated),
    }),
    buildCheck({
      metric: 'legacy_users_created',
      expected: String(EXPECTED.legacyUsersCreated),
      actual: String(totals.legacyUsersCreated),
    }),
    buildCheck({
      metric: 'suppliers_created',
      expected: String(EXPECTED.suppliersCreated),
      actual: String(totals.suppliersCreated),
    }),
    buildCheck({
      metric: 'purchases_created',
      expected: String(EXPECTED.purchasesCreated),
      actual: String(totals.purchasesCreated),
    }),
    buildCheck({
      metric: 'inventory_movements_imported',
      expected: String(EXPECTED.inventoryMovementsImported),
      actual: String(totals.inventoryMovementsImported),
    }),
    buildCheck({
      metric: 'cash_movements_imported',
      expected: String(EXPECTED.cashMovementsImported),
      actual: String(totals.cashMovementsImported),
    }),
    buildCheck({
      metric: 'cashbox_daily_imported',
      expected: String(EXPECTED.cashboxDailyImported),
      actual: String(totals.cashboxDailyImported),
    }),
    buildCheck({
      metric: 'demo_products_imported',
      expected: String(EXPECTED.demoProductsImported),
      actual: String(plan.products.filter((p) => plan.demo.productIds.includes(p.legacyId)).length),
    }),
    buildCheck({
      metric: 'demo_sales_imported',
      expected: String(EXPECTED.demoSalesImported),
      actual: String(plan.sales.filter((s) => plan.demo.saleIds.includes(s.legacyId)).length),
    }),
    buildCheck({
      metric: 'demo_sale_items_imported',
      expected: String(EXPECTED.demoSaleItemsImported),
      actual: String(plan.saleItems.filter((i) => plan.demo.saleItemIds.includes(i.legacyId)).length),
    }),
    buildCheck({
      metric: 'demo_shifts_imported',
      expected: String(EXPECTED.demoShiftsImported),
      actual: String(plan.shifts.filter((s) => plan.demo.shiftIds.includes(s.legacyId)).length),
    }),
    buildCheck({
      metric: 'demo_products_excluded',
      expected: String(EXPECTED.demoProducts),
      actual: String(plan.demo.productCount),
    }),
    buildCheck({
      metric: 'demo_sales_excluded',
      expected: String(EXPECTED.demoSales),
      actual: String(plan.demo.saleCount),
    }),
    buildCheck({
      metric: 'demo_sale_items_excluded',
      expected: String(EXPECTED.demoSaleItems),
      actual: String(plan.demo.saleItemCount),
    }),
    buildCheck({
      metric: 'demo_shifts_excluded',
      expected: String(EXPECTED.demoShifts),
      actual: String(plan.demo.shiftCount),
    }),
    buildCheck({
      metric: 'demo_stock_excluded',
      expected: EXPECTED.demoStock,
      actual: formatCents(plan.demo.stockCents),
    }),
    buildCheck({
      metric: 'demo_itbis_excluded',
      expected: EXPECTED.demoItbis,
      actual: formatCents(plan.demo.itbisCents),
    }),
    buildCheck({
      metric: 'all_shifts_closed',
      expected: 'true',
      actual: String(plan.shifts.every((shift) => shift.status === 'CLOSED')),
    }),
    buildCheck({
      metric: 'sales_link_is_imported_shift_or_null',
      expected: 'true',
      actual: String(
        plan.sales.every(
          (sale) => sale.targetShiftId === null || importedShiftIds.has(sale.targetShiftId),
        ),
      ),
    }),
    buildCheck({
      metric: 'all_imported_shifts_closed',
      expected: 'true',
      actual: String(plan.shifts.every((shift) => shift.status === 'CLOSED')),
    }),
    buildCheck({
      metric: 'all_sales_itbis_zero',
      expected: EXPECTED.itbis,
      actual: formatCents(
        plan.sales.reduce((acc, sale) => acc + sale.itbisCents, 0n),
      ),
    }),
    buildCheck({
      metric: 'distinct_target_ids',
      expected: String(
        plan.products.length + plan.shifts.length + plan.sales.length + plan.saleItems.length,
      ),
      actual: String(
        new Set([
          ...plan.products.map((p) => p.targetId),
          ...plan.shifts.map((s) => s.targetId),
          ...plan.sales.map((s) => s.targetId),
          ...plan.saleItems.map((i) => i.targetId),
        ]).size,
      ),
    }),
  ];

  const failures = checks.filter((check) => !check.ok);

  return {
    generatedAt,
    checks,
    failures,
    verdict: failures.length === 0 ? 'GO' : 'NO-GO',
  };
}
