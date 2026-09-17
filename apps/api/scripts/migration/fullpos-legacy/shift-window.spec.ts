/**
 * Historical shift window policy: LATEST_50_REAL_CLOSED.
 *
 * Proves the 15 requirements of the scope adjustment:
 * demo shift excluded, exactly the 50 newest real CLOSED sessions selected by
 * closed_at_ms DESC, 63 older sessions intentionally omitted (not failures), every
 * sale still imported (linked or with cashSessionId NULL), and no change to the
 * existing Cloud shift-history code.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  HISTORICAL_SHIFT_POLICY,
  HISTORICAL_SHIFT_WINDOW,
  SHIFT_OMISSION_REASON,
  TARGET_WAREHOUSE_ID,
} from './constants';
import { buildGoldenFixture, buildMinimalInput } from './fixtures';
import { formatCents } from './money';
import { buildWritePlan } from './payload';
import { planMigration } from './transform';

const fixture = buildGoldenFixture();
const plan = planMigration(fixture);

/** Independent reimplementation of the locked rule, used to cross-check the migrator. */
function expectedSelection(sessions: typeof fixture.cashSessions, window = HISTORICAL_SHIFT_WINDOW) {
  return sessions
    .filter((session) => session.id !== 1 && session.status.trim().toUpperCase() === 'CLOSED')
    .sort((a, b) => {
      const byClose = (b.closed_at_ms as number) - (a.closed_at_ms as number);
      return byClose !== 0 ? byClose : b.id - a.id;
    })
    .slice(0, window)
    .map((session) => session.id);
}

describe('historical shift window', () => {
  it('exposes the locked policy', () => {
    expect(plan.shiftPolicy.policy).toBe(HISTORICAL_SHIFT_POLICY);
    expect(plan.shiftPolicy.policy).toBe('LATEST_50_REAL_CLOSED');
    expect(plan.shiftPolicy.window).toBe(50);
    expect(plan.shiftPolicy.reason).toBe(SHIFT_OMISSION_REASON);
    expect(plan.shiftPolicy.reason).toBe('OLDER_THAN_MIGRATION_SHIFT_WINDOW');
  });

  it('1. excludes demo shift id 1', () => {
    expect(plan.demo.shiftIds).toEqual([1]);
    expect(plan.shifts.some((shift) => shift.legacyId === 1)).toBe(false);
    expect(plan.excluded.filter((entry) => entry.reason === 'DEMO_SHIFT')).toHaveLength(1);
  });

  it('2. selects exactly the 50 newest real CLOSED sessions', () => {
    expect(plan.shifts).toHaveLength(50);
    const selected = plan.shifts.map((shift) => shift.legacyId).sort((a, b) => a - b);
    expect(selected).toEqual(expectedSelection(fixture.cashSessions).sort((a, b) => a - b));
  });

  it('3. selects by closed_at_ms DESC (oldest selected is newer than any omitted)', () => {
    const selectedIds = new Set(plan.shifts.map((shift) => shift.legacyId));
    const closeById = new Map(fixture.cashSessions.map((session) => [session.id, session.closed_at_ms as number]));
    const oldestSelected = Math.min(...[...selectedIds].map((id) => closeById.get(id) as number));
    const newestOmitted = Math.max(
      ...plan.shiftPolicy.notImportedLegacyIds.map((id) => closeById.get(id) as number),
    );
    expect(oldestSelected).toBeGreaterThan(newestOmitted);
  });

  it('4. reports a deterministic boundary between imported and omitted shifts', () => {
    expect(plan.shiftPolicy.boundary.oldestImportedClosedAt).not.toBeNull();
    expect(plan.shiftPolicy.boundary.newestNotImportedClosedAt).not.toBeNull();
    // Boundary must mirror the real selection.
    const selectedClosed = fixture.cashSessions
      .filter((session) => plan.shifts.some((shift) => shift.legacyId === session.id))
      .map((session) => session.closed_at_ms as number);
    expect(new Date(plan.shiftPolicy.boundary.oldestImportedClosedAt as string).getTime()).toBe(
      Math.min(...selectedClosed),
    );
    const rerun = planMigration(buildGoldenFixture());
    expect(rerun.shiftPolicy.boundary).toEqual(plan.shiftPolicy.boundary);
  });

  it('5. leaves the 63 older source sessions out without treating them as failures', () => {
    expect(plan.shiftPolicy.sourceRealShifts).toBe(113);
    expect(plan.shiftPolicy.notImported).toBe(63);
    expect(plan.shiftPolicy.notImportedLegacyIds).toHaveLength(63);
    const imported = new Set(plan.shifts.map((shift) => shift.legacyId));
    for (const legacyId of plan.shiftPolicy.notImportedLegacyIds) {
      expect(imported.has(legacyId)).toBe(false);
    }
    // Omitted shifts are NOT exclusions/errors: `excluded` only holds DEMO records.
    expect(plan.excluded.every((entry) => entry.reason.startsWith('DEMO_'))).toBe(true);
    expect(plan.shiftPolicy.skippedNotClosedLegacyIds).toEqual([]);
  });

  it('6. links sales of imported shifts to the mapped CashSession UUID', () => {
    const shiftByLegacyId = new Map(plan.shifts.map((shift) => [shift.legacyId, shift.targetId]));
    const linked = plan.sales.filter((sale) => sale.targetShiftId !== null);
    expect(linked).toHaveLength(3930);
    for (const sale of linked.slice(0, 500)) {
      expect(sale.targetShiftId).toBe(shiftByLegacyId.get(sale.legacySessionId as number));
    }
    // No sale is linked to a shift outside the window.
    for (const sale of plan.sales) {
      if (sale.targetShiftId !== null) {
        expect(shiftByLegacyId.has(sale.legacySessionId as number)).toBe(true);
      }
    }
  });

  it('7. keeps older-shift sales with cashSessionId = NULL', () => {
    const importedLegacyShiftIds = new Set(plan.shifts.map((shift) => shift.legacyId));
    const unlinked = plan.sales.filter((sale) => sale.targetShiftId === null);
    expect(unlinked).toHaveLength(3249);
    for (const sale of unlinked.slice(0, 500)) {
      expect(importedLegacyShiftIds.has(sale.legacySessionId as number)).toBe(false);
    }
  });

  it('8-9. imports every real sale, even when its shift is outside the window', () => {
    expect(plan.sales).toHaveLength(7179);
    expect(plan.totals.sales).toBe(7179);
    expect(plan.totals.salesLinkedToImportedShifts + plan.totals.salesWithoutShiftLink).toBe(7179);

    const sourceSaleIds = fixture.sales
      .filter((sale) => sale.id > 5) // 1..5 are the DEMO sales
      .map((sale) => sale.id)
      .sort((a, b) => a - b);
    const plannedSaleIds = plan.sales.map((sale) => sale.legacyId).sort((a, b) => a - b);
    expect(plannedSaleIds).toEqual(sourceSaleIds);
    expect(plan.sales.every((sale) => sale.targetId.length > 0)).toBe(true);
  });

  it('10. keeps all 9,746 sale items', () => {
    expect(plan.saleItems).toHaveLength(9746);
    expect(plan.totals.saleItems).toBe(9746);
  });

  it('11. keeps revenue, cost and profit unchanged', () => {
    expect(formatCents(plan.totals.revenueCents)).toBe('1095535.00');
    expect(formatCents(plan.totals.costCents)).toBe('742332.88');
    expect(formatCents(plan.totals.profitCents)).toBe('353202.12');
    expect(plan.totals.products).toBe(91);
    expect(plan.totals.activeProducts).toBe(87);
    expect(plan.totals.archivedProducts).toBe(4);
    expect(formatCents(plan.totals.openingStockCents)).toBe('1557.00');
  });

  it('12-13. generates no CashboxDaily and no CashMovement', () => {
    const writePlan = buildWritePlan(plan, { warehouseId: TARGET_WAREHOUSE_ID });
    expect(Object.keys(writePlan)).toEqual([
      'products',
      'warehouseStocks',
      'shifts',
      'sales',
      'saleItems',
    ]);
    expect(writePlan.shifts).toHaveLength(50);
    expect(writePlan.sales.filter((sale) => sale.cashSessionId === null)).toHaveLength(3249);
  });

  it('14. reruns produce identical ids for the 50 selected sessions', () => {
    const rerun = planMigration(buildGoldenFixture());
    expect(rerun.shifts.map((shift) => shift.targetId)).toEqual(plan.shifts.map((shift) => shift.targetId));
    expect(rerun.shifts.map((shift) => shift.legacyId)).toEqual(plan.shifts.map((shift) => shift.legacyId));
    expect(rerun.sales.map((sale) => sale.targetShiftId)).toEqual(
      plan.sales.map((sale) => sale.targetShiftId),
    );
  });

  it('15. does not modify the existing Cloud shift-history code', () => {
    const servicePath = join(__dirname, '..', '..', '..', 'src', 'cash', 'cash.service.ts');
    const source = readFileSync(servicePath, 'utf8');
    // closedSessions() must still be the untouched take:60 window over CLOSED sessions.
    expect(source).toContain('async closedSessions(');
    expect(source).toContain('take: 60');
    expect(source).toContain('status: "CLOSED"');
    expect(source).not.toContain('skip:');
    expect(source).not.toMatch(/paginat/i);
  });

  it('imports all available sessions when fewer than the window exist', () => {
    const minimal = planMigration(buildMinimalInput());
    expect(minimal.shifts).toHaveLength(1);
    expect(minimal.shiftPolicy.imported).toBe(1);
    expect(minimal.shiftPolicy.notImported).toBe(0);
    expect(minimal.shiftPolicy.notImportedLegacyIds).toEqual([]);
    expect(minimal.shiftPolicy.boundary.newestNotImportedClosedAt).toBeNull();
  });
});
