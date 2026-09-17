/**
 * Idempotency + id-set logic of the write path (pure, no database connection).
 *
 * The destination must be either completely clean (FRESH) or exactly the expected
 * imported set (ALREADY_APPLIED). Anything in between aborts with ZERO writes:
 * the migration never overwrites or completes a partial import.
 */

import { assertTargetStateAllowsWrite, buildIdSets, classifyTargetState, type TargetState } from './writer';
import type { WritePlan } from './payload';

const EXPECTED = {
  products: 91,
  activeProducts: 87,
  archivedProducts: 4,
  shifts: 50,
  sales: 7179,
  saleItems: 9746,
  warehouseStocks: 87,
};

function state(overrides: Partial<TargetState> = {}): TargetState {
  return {
    products: 0,
    activeProducts: 0,
    archivedProducts: 0,
    shifts: 0,
    sales: 0,
    saleItems: 0,
    warehouseStocks: 0,
    inventoryMovements: 0,
    cashMovements: 0,
    cashboxDaily: 0,
    clients: 0,
    suppliers: 0,
    purchaseOrders: 0,
    taxes: 0,
    ncfSequences: 0,
    openShifts: 0,
    ...overrides,
  };
}

function imported(overrides: Partial<TargetState> = {}): TargetState {
  return state({
    products: EXPECTED.products,
    activeProducts: EXPECTED.activeProducts,
    archivedProducts: EXPECTED.archivedProducts,
    shifts: EXPECTED.shifts,
    sales: EXPECTED.sales,
    saleItems: EXPECTED.saleItems,
    warehouseStocks: EXPECTED.warehouseStocks,
    ...overrides,
  });
}

describe('classifyTargetState', () => {
  it('reports FRESH for an untouched company', () => {
    expect(classifyTargetState(state(), EXPECTED).verdict).toBe('FRESH');
  });

  it('reports ALREADY_APPLIED when the whole expected set is present', () => {
    expect(classifyTargetState(imported(), EXPECTED).verdict).toBe('ALREADY_APPLIED');
  });

  it('reports UNEXPECTED_STATE for a partially imported set', () => {
    const result = classifyTargetState(state({ products: 40, warehouseStocks: 40 }), EXPECTED);
    expect(result.verdict).toBe('UNEXPECTED_STATE');
    expect(result.details.join(' ')).toMatch(/products/);
  });

  it('reports UNEXPECTED_STATE when only a few rows differ', () => {
    expect(classifyTargetState(imported({ saleItems: EXPECTED.saleItems - 1 }), EXPECTED).verdict).toBe(
      'UNEXPECTED_STATE',
    );
    expect(classifyTargetState(imported({ products: EXPECTED.products + 1 }), EXPECTED).verdict).toBe(
      'UNEXPECTED_STATE',
    );
  });

  it('ignores out-of-scope entities: they are rejected by the foreign-row gate instead', () => {
    const result = classifyTargetState(state({ clients: 3 }), EXPECTED);
    expect(result.verdict).toBe('FRESH');
    expect(result.details).toEqual([]);
  });
});

describe('assertTargetStateAllowsWrite', () => {
  it('allows a fresh or already-applied destination', () => {
    expect(() => assertTargetStateAllowsWrite('FRESH', [])).not.toThrow();
    expect(() => assertTargetStateAllowsWrite('ALREADY_APPLIED', [])).not.toThrow();
  });

  it('aborts on an unexpected destination', () => {
    expect(() => assertTargetStateAllowsWrite('UNEXPECTED_STATE', ['products: 40'])).toThrow(
      /TARGET_STATE_UNEXPECTED/,
    );
  });
});

describe('buildIdSets', () => {
  const writePlan = {
    products: [
      { id: '00000000-0000-4000-8000-000000000001', archivedAt: null },
      { id: '00000000-0000-4000-8000-000000000002', archivedAt: '2026-01-01T00:00:00.000Z' },
    ],
    warehouseStocks: [{ productId: '00000000-0000-4000-8000-000000000001' }],
    shifts: [{ id: '00000000-0000-4000-8000-000000000010' }],
    sales: [
      { id: '00000000-0000-4000-8000-000000000020', cashSessionId: '00000000-0000-4000-8000-000000000010' },
      { id: '00000000-0000-4000-8000-000000000021', cashSessionId: null },
    ],
    saleItems: [{ id: '00000000-0000-4000-8000-000000000030' }],
  } as unknown as WritePlan;

  const ids = buildIdSets({
    companyId: 'f3651f62-be10-41aa-bde7-663cf990eae8',
    warehouseId: 'ffc9ef9b-9157-418d-8aa1-94112278bb68',
    writePlan,
  });

  it('separates active from archived products', () => {
    expect(ids.productIds).toHaveLength(2);
    expect(ids.activeProductIds).toEqual(['00000000-0000-4000-8000-000000000001']);
    expect(ids.archivedProductIds).toEqual(['00000000-0000-4000-8000-000000000002']);
  });

  it('separates linked from unlinked sales', () => {
    expect(ids.linkedSaleIds).toEqual(['00000000-0000-4000-8000-000000000020']);
    expect(ids.unlinkedSaleIds).toEqual(['00000000-0000-4000-8000-000000000021']);
  });

  it('keeps the locked tenant ids', () => {
    expect(ids.companyId).toBe('f3651f62-be10-41aa-bde7-663cf990eae8');
    expect(ids.warehouseId).toBe('ffc9ef9b-9157-418d-8aa1-94112278bb68');
    expect(ids.shiftIds).toEqual(['00000000-0000-4000-8000-000000000010']);
    expect(ids.saleItemIds).toEqual(['00000000-0000-4000-8000-000000000030']);
  });
});
