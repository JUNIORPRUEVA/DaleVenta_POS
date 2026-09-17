/**
 * Transformation rules of the legacy migrator.
 *
 * Covers required test cases 1-18, 25-28 (structural + authoritative aggregates).
 * Everything runs on pure fixtures: no database, no I/O.
 */

import { DEFAULT_CATEGORY_FALLBACK, LEGACY_OPERATOR_UNKNOWN, LEGACY_TABLE } from './constants';
import { buildGoldenFixture, buildMinimalInput, GOLDEN_FIXTURE_EXPECTED } from './fixtures';
import { formatCents, formatMicro } from './money';
import { planMigration } from './transform';

describe('planMigration · golden fixture', () => {
  const plan = planMigration(buildGoldenFixture());

  it('1. excludes the 50 DEMO products', () => {
    expect(plan.demo.productCount).toBe(50);
    expect(plan.demo.productIds).toHaveLength(50);
    expect(plan.products.some((product) => product.code.startsWith('DEMO-'))).toBe(false);
    expect(plan.excluded.filter((entry) => entry.reason === 'DEMO_PRODUCT')).toHaveLength(50);
  });

  it('2. excludes the 5 DEMO sales', () => {
    expect(plan.demo.saleCount).toBe(5);
    expect(plan.demo.saleIds).toEqual([1, 2, 3, 4, 5]);
    expect(plan.sales.some((sale) => plan.demo.saleIds.includes(sale.legacyId))).toBe(false);
  });

  it('3. excludes the DEMO cash session', () => {
    expect(plan.demo.shiftIds).toEqual([1]);
    expect(plan.shifts.some((shift) => shift.legacyId === 1)).toBe(false);
    expect(plan.excluded.filter((entry) => entry.reason === 'DEMO_SHIFT')).toHaveLength(1);
  });

  it('4. aborts when a sale mixes DEMO and real products', () => {
    const input = buildMinimalInput();
    // Add a real line to the DEMO sale -> mixed document
    input.saleItems.push({
      id: 99,
      sale_id: 1,
      product_id: 51,
      product_code_snapshot: 'REAL-051',
      product_name_snapshot: 'Real',
      qty: 1,
      unit_price: 150,
      purchase_price_snapshot: 100,
      discount_line: 0,
      total_line: 150,
      created_at_ms: 1,
    });
    expect(() => planMigration(input)).toThrow(/MIXED_DEMO_SALE/);
  });

  it('5-7. imports 91 products: 87 active + 4 archived', () => {
    expect(plan.totals.products).toBe(91);
    expect(plan.totals.activeProducts).toBe(87);
    expect(plan.totals.archivedProducts).toBe(4);
    expect(plan.totals.products).toBe(GOLDEN_FIXTURE_EXPECTED.products);
  });

  it('8. archived products get operational stock 0 and keep the legacy stock in the manifest', () => {
    const archived = plan.products.filter((product) => product.isArchived);
    expect(archived).toHaveLength(4);
    for (const product of archived) {
      expect(product.operationalStockMicro).toBe(0n);
      expect(product.archivedAtIso).not.toBeNull();
    }
    const negative = archived.find((product) => product.legacyStockMicro < 0n);
    expect(negative).toBeDefined();
    expect(formatMicro(negative!.legacyStockMicro)).toBe('-1.000000');
  });

  it('9. documents the legacy -1 as a stock exception', () => {
    expect(plan.stockExceptions).toHaveLength(1);
    const exception = plan.stockExceptions[0];
    expect(exception.kind).toBe('NEGATIVE_ARCHIVED_STOCK');
    expect(exception.legacyStock).toBe('-1.000000');
    expect(exception.operationalStock).toBe('0.000000');
  });

  it('10-11. opening stock 1,557.00 with 75 positive and 12 zero', () => {
    expect(formatCents(plan.totals.openingStockCents)).toBe('1557.00');
    expect(plan.totals.activeStockPositive).toBe(75);
    expect(plan.totals.activeStockZero).toBe(12);
    expect(plan.totals.activeStockNegative).toBe(0);
    expect(plan.totals.archivedOperationalStockCents).toBe(0n);
  });

  it('12-14. imports 7,179 sales: 7,176 completed + 3 cancelled', () => {
    expect(plan.totals.sales).toBe(7179);
    expect(plan.totals.completedSales).toBe(7176);
    expect(plan.totals.cancelledSales).toBe(3);
  });

  it('15. imports 9,746 sale items', () => {
    expect(plan.totals.saleItems).toBe(9746);
    expect(plan.saleItems).toHaveLength(9746);
  });

  it('16-18. revenue, cost and profit match the audited figures', () => {
    expect(formatCents(plan.totals.revenueCents)).toBe('1095535.00');
    expect(formatCents(plan.totals.costCents)).toBe('742332.88');
    expect(formatCents(plan.totals.profitCents)).toBe('353202.12');
    expect(
      formatCents(plan.totals.revenueCents - plan.totals.costCents),
    ).toBe(formatCents(plan.totals.profitCents));
  });

  it('19. no customer is created and every sale keeps customerId null', () => {
    expect(plan.totals.customersCreated).toBe(0);
    // The plan carries no client entity at all.
    expect(Object.keys(plan)).not.toContain('clients');
  });

  it('25. historical cost comes from purchase_price_snapshot', () => {
    // The golden fixture uses cost 76.16 on every real line.
    expect(plan.saleItems[0].costUnitCents).toBe(7616n);
    expect(plan.saleItems[0].subtotalCostCents).toBe(7616n);
  });

  it('26-27. imports 50 historical shifts (newest real CLOSED), all CLOSED', () => {
    expect(plan.totals.shifts).toBe(50);
    expect(plan.shifts.every((shift) => shift.status === 'CLOSED')).toBe(true);
    expect(plan.shifts.every((shift) => shift.closedAtIso.length > 0)).toBe(true);
  });

  it('28. every linked sale points to an imported shift, and the rest are NULL', () => {
    const shiftIds = new Set(plan.shifts.map((shift) => shift.targetId));
    for (const sale of plan.sales) {
      if (sale.targetShiftId === null) continue;
      expect(shiftIds.has(sale.targetShiftId)).toBe(true);
    }
    expect(plan.totals.salesLinkedToImportedShifts).toBe(3930);
    expect(plan.totals.salesWithoutShiftLink).toBe(3249);
    const linkedSale = plan.sales.find((sale) => sale.targetShiftId !== null);
    const shift = plan.shifts.find((entry) => entry.targetId === linkedSale?.targetShiftId);
    expect(shift?.legacyId).toBe(linkedSale?.legacySessionId);
  });

  it('counters per shift count only sales linked to imported shifts', () => {
    const totalCounted = plan.shifts.reduce((acc, shift) => acc + shift.salesCount, 0);
    expect(totalCounted).toBe(plan.totals.salesLinkedToImportedShifts);
    expect(totalCounted).toBe(3930);
  });

  it('never claims a real operator for historical sales', () => {
    expect(plan.sales.every((sale) => sale.legacyOperator === LEGACY_OPERATOR_UNKNOWN)).toBe(true);
  });

  it('falls back to the deterministic category when the legacy category is missing', () => {
    const withoutCategory = plan.products.filter((product) => !product.categoriaFromLegacy);
    expect(withoutCategory.length).toBeGreaterThan(0);
    expect(withoutCategory.every((product) => product.categoria === DEFAULT_CATEGORY_FALLBACK)).toBe(true);
    const fromLegacy = plan.products.filter((product) => product.categoriaFromLegacy);
    expect(fromLegacy.every((product) => product.categoria.startsWith('CAT-'))).toBe(true);
  });

  it('keeps every excluded record auditable', () => {
    const reasons = new Set(plan.excluded.map((entry) => entry.reason));
    expect(reasons).toEqual(
      new Set(['DEMO_PRODUCT', 'DEMO_SALE', 'DEMO_SALE_ITEM', 'DEMO_SHIFT']),
    );
    expect(plan.excluded.filter((entry) => entry.reason === 'DEMO_SALE_ITEM')).toHaveLength(5);
    expect(
      plan.excluded.every(
        (entry) =>
          entry.legacyTable === LEGACY_TABLE.products ||
          entry.legacyTable === LEGACY_TABLE.sales ||
          entry.legacyTable === LEGACY_TABLE.saleItems ||
          entry.legacyTable === LEGACY_TABLE.cashSessions,
      ),
    ).toBe(true);
  });
});

describe('planMigration · strictness', () => {
  it('uses the historical snapshot and never the current product cost', () => {
    const input = buildMinimalInput();
    // current product cost is 100.00, the historical snapshot of the line is 999.00
    input.saleItems[1].purchase_price_snapshot = 999;
    const plan = planMigration(input);
    const item = plan.saleItems[0];
    expect(item.costUnitCents).toBe(99900n);
    expect(item.subtotalCostCents).toBe(99900n);
    expect(item.profitCents).toBe(15000n - 99900n);
  });

  it('aborts when a sale has no lines', () => {
    const input = buildMinimalInput();
    input.saleItems = input.saleItems.filter((item) => item.sale_id !== 2);
    expect(() => planMigration(input)).toThrow(/SALE_WITHOUT_ITEMS/);
  });

  it('aborts when a line points to a non-migrated (DEMO) product', () => {
    const input = buildMinimalInput();
    input.saleItems.push({
      id: 98,
      sale_id: 2,
      product_id: 1, // DEMO product
      product_code_snapshot: 'DEMO-001',
      product_name_snapshot: 'Demo',
      qty: 1,
      unit_price: 10,
      purchase_price_snapshot: 5,
      discount_line: 0,
      total_line: 10,
      created_at_ms: 3,
    });
    // sale 2 would then contain a DEMO line -> mixed document
    expect(() => planMigration(input)).toThrow(/MIXED_DEMO_SALE/);
  });

  it('aborts when a sale subtotal does not match its lines', () => {
    const input = buildMinimalInput();
    const sale = input.sales.find((entry) => entry.id === 2);
    if (sale) sale.subtotal = 999;
    expect(() => planMigration(input)).toThrow(/SALE_TOTAL_MISMATCH/);
  });

  it('aborts on an unknown sale status', () => {
    const input = buildMinimalInput();
    const sale = input.sales.find((entry) => entry.id === 2);
    if (sale) sale.status = 'pending';
    expect(() => planMigration(input)).toThrow(/UNKNOWN_SALE_STATUS/);
  });

  it('skips (never imports, never aborts on) an open legacy shift', () => {
    const input = buildMinimalInput();
    const session = input.cashSessions.find((entry) => entry.id === 2);
    if (session) session.status = 'OPEN';
    const plan = planMigration(input);
    expect(plan.shifts).toHaveLength(0);
    expect(plan.shiftPolicy.skippedNotClosedLegacyIds).toEqual([2]);
    // The sale is still imported, just without a shift link.
    expect(plan.sales.find((sale) => sale.legacyId === 2)?.targetShiftId).toBeNull();
  });

  it('aborts on a negative stock for an ACTIVE product', () => {
    const input = buildMinimalInput();
    const product = input.products.find((entry) => entry.id === 51);
    if (product) product.stock = -5;
    expect(() => planMigration(input)).toThrow(/NEGATIVE_ACTIVE_STOCK/);
  });

  it('aborts when an inactive product has no deletion date', () => {
    const input = buildMinimalInput();
    const product = input.products.find((entry) => entry.id === 51);
    if (product) {
      product.is_active = 0;
      product.deleted_at_ms = null;
    }
    expect(() => planMigration(input)).toThrow(/UNEXPECTED_PRODUCT_STATE/);
  });

  it('aborts when the demo-only shift is not the locked one', () => {
    const input = buildMinimalInput();
    const session = input.cashSessions.find((entry) => entry.id === 1);
    if (session) session.id = 7;
    const sale = input.sales.find((entry) => entry.id === 1);
    if (sale) sale.session_id = 7;
    expect(() => planMigration(input)).toThrow(/DEMO_SHIFT_UNEXPECTED/);
  });
});
