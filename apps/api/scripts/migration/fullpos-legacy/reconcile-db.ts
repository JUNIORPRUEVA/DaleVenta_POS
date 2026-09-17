/**
 * Post-write reconciliation read directly from PostgreSQL.
 *
 * This is the evidence that the migration actually landed correctly in the target
 * database (not just in the in-memory plan): counts, money totals, stock invariant,
 * shift links, fiscal/commission neutrality and the absence of out-of-scope rows.
 */

import type { PrismaClient } from '@prisma/client';
import { formatCents, parseCents } from './money';
import { buildCheck } from './reconcile';
import type { ReconciliationCheck, ReconciliationReport } from './types';
import type { MigrationIdSets } from './writer';

type ExpectedCounts = {
  products: number;
  activeProducts: number;
  archivedProducts: number;
  shifts: number;
  sales: number;
  saleItems: number;
  warehouseStocks: number;
};

function decimalToCents(value: unknown): bigint {
  if (value === null || value === undefined) return 0n;
  const text = String(value);
  return parseCents(text.includes('.') ? text : `${text}.00`);
}

export async function reconcileFromDatabase(
  prisma: PrismaClient,
  ids: MigrationIdSets,
  expected: ExpectedCounts,
): Promise<ReconciliationReport> {
  const companyId = ids.companyId;
  const warehouseId = ids.warehouseId;
  const generatedAt = new Date().toISOString();

  const [
    products,
    activeProducts,
    archivedProducts,
    shifts,
    openShifts,
    sales,
    saleItems,
    warehouseStocks,
    linkedSales,
    unlinkedSales,
    saleTotals,
    itemTotals,
    stockAgg,
    negativeStock,
    cashMovements,
    cashboxDaily,
    inventoryMovements,
    clients,
    suppliers,
    purchaseOrders,
    taxes,
    ncfSequences,
    demoProducts,
    ncfSales,
    commissionAgg,
    trackedItems,
    stockMismatch,
  ] = await Promise.all([
    prisma.product.count({ where: { companyId } }),
    prisma.product.count({ where: { companyId, archivedAt: null } }),
    prisma.product.count({ where: { companyId, archivedAt: { not: null } } }),
    prisma.cashSession.count({ where: { companyId } }),
    prisma.cashSession.count({ where: { companyId, status: 'OPEN' } }),
    prisma.sale.count({ where: { companyId } }),
    prisma.saleItem.count({ where: { sale: { companyId } } }),
    prisma.warehouseStock.count({ where: { companyId } }),
    prisma.sale.count({ where: { companyId, cashSessionId: { not: null } } }),
    prisma.sale.count({ where: { companyId, cashSessionId: null } }),
    prisma.sale.aggregate({
      where: { companyId },
      _sum: { totalSold: true, totalCost: true, totalProfit: true, taxAmount: true, commissionAmount: true },
    }),
    prisma.saleItem.aggregate({
      where: { sale: { companyId } },
      _sum: { subtotalSold: true, subtotalCost: true, profit: true },
    }),
    prisma.warehouseStock.aggregate({
      where: { companyId },
      _sum: { quantity: true },
    }),
    prisma.product.count({ where: { companyId, stock: { lt: 0 } } }),
    prisma.cashMovement.count({ where: { companyId } }),
    prisma.cashboxDaily.count({ where: { companyId } }),
    prisma.inventoryMovement.count({ where: { companyId } }),
    prisma.client.count({ where: { companyId } }),
    prisma.supplier.count({ where: { companyId } }),
    prisma.purchaseOrder.count({ where: { companyId } }),
    prisma.tax.count({ where: { companyId } }),
    prisma.ncfSequence.count({ where: { companyId } }),
    prisma.product.count({ where: { companyId, codigo: { startsWith: 'DEMO-' } } }),
    prisma.sale.count({ where: { companyId, ncf: { not: null } } }),
    prisma.sale.count({ where: { companyId, commissionAmount: { not: 0 } } }),
    prisma.saleItem.count({ where: { sale: { companyId }, inventoryTrackedSnapshot: true } }),
    prisma.$queryRaw<Array<{ mismatches: bigint }>>`
      SELECT COUNT(*)::bigint AS mismatches
        FROM "Product" p
        LEFT JOIN (
          SELECT product_id, SUM(quantity) AS total
            FROM warehouse_stocks
           WHERE company_id = ${companyId}::uuid
             AND warehouse_id = ${warehouseId}::uuid
           GROUP BY product_id
        ) ws ON ws.product_id = p.id
       WHERE p.company_id = ${companyId}::uuid
         AND p.stock <> COALESCE(ws.total, 0)`,
  ]);

  const checks: ReconciliationCheck[] = [
    buildCheck({ metric: 'db_products', expected: String(expected.products), actual: String(products) }),
    buildCheck({
      metric: 'db_active_products',
      expected: String(expected.activeProducts),
      actual: String(activeProducts),
    }),
    buildCheck({
      metric: 'db_archived_products',
      expected: String(expected.archivedProducts),
      actual: String(archivedProducts),
    }),
    buildCheck({ metric: 'db_shifts', expected: String(expected.shifts), actual: String(shifts) }),
    buildCheck({ metric: 'db_open_shifts', expected: '0', actual: String(openShifts) }),
    buildCheck({ metric: 'db_sales', expected: String(expected.sales), actual: String(sales) }),
    buildCheck({
      metric: 'db_sale_items',
      expected: String(expected.saleItems),
      actual: String(saleItems),
    }),
    buildCheck({
      metric: 'db_warehouse_stocks',
      expected: String(expected.warehouseStocks),
      actual: String(warehouseStocks),
    }),
    buildCheck({ metric: 'db_linked_sales', expected: '3930', actual: String(linkedSales) }),
    buildCheck({ metric: 'db_unlinked_sales', expected: '3249', actual: String(unlinkedSales) }),
    buildCheck({
      metric: 'db_revenue',
      expected: '1095535.00',
      actual: formatCents(decimalToCents(saleTotals._sum.totalSold)),
    }),
    buildCheck({
      metric: 'db_cost',
      expected: '742332.88',
      actual: formatCents(decimalToCents(saleTotals._sum.totalCost)),
    }),
    buildCheck({
      metric: 'db_profit',
      expected: '353202.12',
      actual: formatCents(decimalToCents(saleTotals._sum.totalProfit)),
    }),
    buildCheck({
      metric: 'db_item_revenue',
      expected: '1095535.00',
      actual: formatCents(decimalToCents(itemTotals._sum.subtotalSold)),
    }),
    buildCheck({
      metric: 'db_item_cost',
      expected: '742332.88',
      actual: formatCents(decimalToCents(itemTotals._sum.subtotalCost)),
    }),
    buildCheck({
      metric: 'db_item_profit',
      expected: '353202.12',
      actual: formatCents(decimalToCents(itemTotals._sum.profit)),
    }),
    buildCheck({
      metric: 'db_stock_total',
      expected: '1557.00',
      actual: formatCents(decimalToCents(stockAgg._sum.quantity)),
    }),
    buildCheck({ metric: 'db_negative_stock', expected: '0', actual: String(negativeStock) }),
    buildCheck({
      metric: 'db_stock_reconciled_products',
      expected: '0',
      actual: String(stockMismatch[0]?.mismatches ?? -1),
    }),
    buildCheck({
      metric: 'db_itbis',
      expected: '0.00',
      actual: formatCents(decimalToCents(saleTotals._sum.taxAmount)),
    }),
    buildCheck({
      metric: 'db_commission',
      expected: '0.00',
      actual: formatCents(decimalToCents(saleTotals._sum.commissionAmount)),
    }),
    buildCheck({ metric: 'db_ncf_sales', expected: '0', actual: String(ncfSales) }),
    buildCheck({ metric: 'db_commission_sales', expected: '0', actual: String(commissionAgg) }),
    buildCheck({ metric: 'db_tracked_items', expected: '0', actual: String(trackedItems) }),
    buildCheck({ metric: 'db_cash_movements', expected: '0', actual: String(cashMovements) }),
    buildCheck({ metric: 'db_cashbox_daily', expected: '0', actual: String(cashboxDaily) }),
    buildCheck({ metric: 'db_inventory_movements', expected: '0', actual: String(inventoryMovements) }),
    buildCheck({ metric: 'db_clients', expected: '0', actual: String(clients) }),
    buildCheck({ metric: 'db_suppliers', expected: '0', actual: String(suppliers) }),
    buildCheck({ metric: 'db_purchase_orders', expected: '0', actual: String(purchaseOrders) }),
    buildCheck({ metric: 'db_taxes', expected: '0', actual: String(taxes) }),
    buildCheck({ metric: 'db_ncf_sequences', expected: '0', actual: String(ncfSequences) }),
    buildCheck({ metric: 'db_demo_products', expected: '0', actual: String(demoProducts) }),
  ];

  const failures = checks.filter((check) => !check.ok);
  return {
    generatedAt,
    checks,
    failures,
    verdict: failures.length === 0 ? 'GO' : 'NO-GO',
  };
}
