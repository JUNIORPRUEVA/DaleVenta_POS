/**
 * Target write payload invariants (the exact rows a future authorized execute would insert).
 *
 * Covers required test cases 19-24 and 29-31: no customers, no commissions,
 * no fiscal objects, no cash movements, no purchases, no legacy inventory movements,
 * and the local code preserved in clientRequestId.
 */

import { EXPECTED, TARGET_COMPANY_ID, TARGET_OWNER_USER_ID, TARGET_TERMINAL_ID, TARGET_WAREHOUSE_ID } from './constants';
import { buildGoldenFixture } from './fixtures';
import { buildWritePlan, CANCELLATION_REASON_LEGACY } from './payload';
import { planMigration } from './transform';

describe('buildWritePlan', () => {
  const plan = planMigration(buildGoldenFixture());
  const writePlan = buildWritePlan(plan, { warehouseId: TARGET_WAREHOUSE_ID });

  it('19. keeps customerId null on every historical sale', () => {
    expect(writePlan.sales).toHaveLength(7179);
    expect(writePlan.sales.every((sale) => sale.customerId === null)).toBe(true);
  });

  it('20. generates no Client rows at all', () => {
    expect(Object.keys(writePlan)).toEqual([
      'products',
      'warehouseStocks',
      'shifts',
      'sales',
      'saleItems',
    ]);
    expect(Object.keys(writePlan)).not.toContain('clients');
  });

  it('21-22. neutralises commission on every sale', () => {
    expect(writePlan.sales.every((sale) => sale.commissionRate === '0.0000')).toBe(true);
    expect(writePlan.sales.every((sale) => sale.commissionAmount === '0.00')).toBe(true);
  });

  it('23. generates no fiscal or NCF object', () => {
    expect(writePlan.sales.every((sale) => sale.fiscalTaxEnabled === false)).toBe(true);
    expect(writePlan.sales.every((sale) => sale.fiscalPriceMode === 'NO_TAX')).toBe(true);
    expect(writePlan.sales.every((sale) => sale.ncf === null)).toBe(true);
    expect(writePlan.sales.every((sale) => sale.fiscalVoucherType === null)).toBe(true);
    expect(writePlan.sales.every((sale) => sale.taxAmount === '0.00')).toBe(true);
    expect(writePlan.sales.every((sale) => sale.taxableBase === '0.00')).toBe(true);
    expect(Object.keys(writePlan)).not.toContain('taxes');
    expect(Object.keys(writePlan)).not.toContain('ncfSequences');
  });

  it('24. preserves the legacy local code in clientRequestId', () => {
    const sample = writePlan.sales.find((sale) => sale.clientRequestId === 'V-IDEM-6');
    expect(sample).toBeDefined();
    expect(writePlan.sales.every((sale) => sale.clientRequestId.startsWith('V-IDEM-'))).toBe(true);
    const codes = new Set(writePlan.sales.map((sale) => sale.clientRequestId));
    expect(codes.size).toBe(writePlan.sales.length);
  });

  it('29. generates no CashMovement rows', () => {
    expect(Object.keys(writePlan)).not.toContain('cashMovements');
  });

  it('30. generates no PurchaseOrder rows', () => {
    expect(Object.keys(writePlan)).not.toContain('purchaseOrders');
    expect(Object.keys(writePlan)).not.toContain('purchaseOrderItems');
  });

  it('31. generates no legacy InventoryMovement rows', () => {
    expect(Object.keys(writePlan)).not.toContain('inventoryMovements');
  });

  it('writes all rows inside the locked tenant', () => {
    expect(writePlan.products.every((row) => row.companyId === TARGET_COMPANY_ID)).toBe(true);
    expect(writePlan.warehouseStocks.every((row) => row.companyId === TARGET_COMPANY_ID)).toBe(true);
    expect(writePlan.shifts.every((row) => row.companyId === TARGET_COMPANY_ID)).toBe(true);
    expect(writePlan.sales.every((row) => row.companyId === TARGET_COMPANY_ID)).toBe(true);
    expect(
      writePlan.warehouseStocks.every((row) => row.warehouseId === TARGET_WAREHOUSE_ID),
    ).toBe(true);
  });

  it('attributes history to the tenant owner without pretending it was the operator', () => {
    expect(writePlan.sales.every((sale) => sale.userId === TARGET_OWNER_USER_ID)).toBe(true);
    const manifestOwners = new Set(plan.sales.map((sale) => sale.legacyOperator));
    expect([...manifestOwners]).toEqual(['UNKNOWN']);
  });

  it('creates one WarehouseStock row per ACTIVE product so Product.stock stays reconciled', () => {
    const active = writePlan.products.filter((product) => product.archivedAt === null);
    expect(active).toHaveLength(EXPECTED.products - EXPECTED.archivedProducts);
    expect(writePlan.warehouseStocks).toHaveLength(active.length);
    for (const product of active) {
      const stock = writePlan.warehouseStocks.find((row) => row.productId === product.id);
      expect(stock?.quantity).toBe(product.stock);
    }
  });

  it('keeps archived products out of the opening stock and with zero stock', () => {
    const archived = writePlan.products.filter((product) => product.archivedAt !== null);
    expect(archived).toHaveLength(EXPECTED.archivedProducts);
    for (const product of archived) {
      expect(Number(product.stock)).toBe(0);
      expect(writePlan.warehouseStocks.some((row) => row.productId === product.id)).toBe(false);
    }
    const totalStock = writePlan.products.reduce((sum, product) => sum + Number(product.stock), 0);
    expect(totalStock).toBe(Number(EXPECTED.openingStock));
    const stockSum = writePlan.warehouseStocks.reduce((sum, row) => sum + Number(row.quantity), 0);
    expect(stockSum).toBe(Number(EXPECTED.openingStock));
  });

  it('imports historical lines with inventory tracking disabled (no stock side effects)', () => {
    expect(writePlan.saleItems.every((item) => item.inventoryTrackedSnapshot === false)).toBe(true);
    expect(writePlan.saleItems.every((item) => item.productSource === 'LOCAL')).toBe(true);
    expect(writePlan.saleItems.every((item) => item.warehouseId === null)).toBe(true);
  });

  it('keeps the 50 imported shifts CLOSED with a real closedAt and no live terminal/cash state', () => {
    expect(writePlan.shifts).toHaveLength(50);
    expect(writePlan.shifts.every((shift) => shift.status === 'CLOSED')).toBe(true);
    expect(writePlan.shifts.every((shift) => shift.closedAt !== null)).toBe(true);
    expect(writePlan.shifts.every((shift) => shift.terminalId === null)).toBe(true);
    expect(writePlan.sales.every((sale) => sale.terminalId === null)).toBe(true);
  });

  it('links sales to imported shifts and leaves the older ones unlinked', () => {
    const shiftIds = new Set(writePlan.shifts.map((shift) => shift.id));
    const linked = writePlan.sales.filter((sale) => sale.cashSessionId !== null);
    const unlinked = writePlan.sales.filter((sale) => sale.cashSessionId === null);
    expect(linked).toHaveLength(3930);
    expect(unlinked).toHaveLength(3249);
    expect(linked.every((sale) => shiftIds.has(sale.cashSessionId as string))).toBe(true);
    // No placeholder shift is created for the older sessions.
    expect(writePlan.shifts).toHaveLength(50);
  });

  it('reproduces the audited cost/profit columns on the sale', () => {
    const totalCost = writePlan.sales.reduce((acc, sale) => acc + BigInt(Math.round(Number(sale.totalCost) * 100)), 0n);
    const totalProfit = writePlan.sales.reduce((acc, sale) => acc + BigInt(Math.round(Number(sale.totalProfit) * 100)), 0n);
    const totalSold = writePlan.sales.reduce((acc, sale) => acc + BigInt(Math.round(Number(sale.totalSold) * 100)), 0n);
    expect(totalSold).toBe(109553500n);
    expect(totalCost + totalProfit).toBe(totalSold);
  });

  it('marks cancelled history as cancelled without touching stock', () => {
    const cancelled = writePlan.sales.filter((sale) => sale.status === 'CANCELLED');
    expect(cancelled).toHaveLength(3);
    expect(cancelled.every((sale) => sale.cancelledAt !== null)).toBe(true);
    expect(cancelled.every((sale) => sale.cancellationReason === CANCELLATION_REASON_LEGACY)).toBe(true);
    expect(cancelled.every((sale) => sale.inventoryRestoredAt === null)).toBe(true);
    expect(cancelled.every((sale) => sale.cancelledById === null)).toBe(true);
  });

  it('archives the withdrawn products and gives them no operational stock', () => {
    const archived = writePlan.products.filter((product) => product.archivedAt !== null);
    expect(archived).toHaveLength(4);
    expect(archived.every((product) => product.stock === '0.000000')).toBe(true);
  });

  it('uses the global UNIT unit of measure and never invents tax columns', () => {
    expect(writePlan.products.every((product) => product.unitOfMeasureId === 'UNIT')).toBe(true);
    expect(writePlan.products.every((product) => product.taxRate === null)).toBe(true);
    expect(writePlan.products.every((product) => product.taxPriceMode === null)).toBe(true);
    expect(writePlan.products.every((product) => product.categoria.trim().length > 0)).toBe(true);
    expect(writePlan.products.every((product) => product.imagen === null)).toBe(true);
  });

  it('publishes the locked terminal for the target tenant contract', () => {
    expect(TARGET_TERMINAL_ID).toBe('00931697-e152-48bc-9e44-02023e14d465');
    expect(writePlan.sales.every((sale) => sale.kind === 'invoice')).toBe(true);
    expect(writePlan.sales.every((sale) => sale.isDeleted === false)).toBe(true);
  });
});
