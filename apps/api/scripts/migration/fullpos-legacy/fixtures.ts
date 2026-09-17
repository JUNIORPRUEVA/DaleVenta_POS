/**
 * Deterministic synthetic fixtures for the migrator tests.
 *
 * The "golden" fixture deliberately reproduces the SHAPE and the AUTHORITATIVE
 * aggregates of the audited legacy database (Phase 2 / 2.5):
 *
 *   50 DEMO products (ids 1-50, codes DEMO-001..050, stock total 1,420.00)
 *   91 real products (87 active + 4 archived, one archived with legacy stock -1.00)
 *   114 cash sessions (1 demo-only + 113 real, all CLOSED) → newest 50 imported
 *   7,184 sales (5 DEMO + 7,179 real: 7,176 completed + 3 cancelled)
 *   9,751 sale items (5 DEMO + 9,746 real)
 *
 *   revenue 1,095,535.00 · cost 742,332.88 · profit 353,202.12 · ITBIS (real) 0.00
 *   DEMO subtotal 11,150.00 · DEMO ITBIS 2,007.00
 *
 * No I/O: pure data construction, so the tests never touch a database.
 */

import type {
  LegacyCashSession,
  LegacyCategory,
  LegacyProduct,
  LegacySale,
  LegacySaleItem,
} from './types';
import type { MigrationInput } from './transform';
import { HISTORICAL_SHIFT_WINDOW } from './constants';

const DEMO_PRODUCT_COUNT = 50;
const REAL_PRODUCT_FIRST_ID = 51;
const REAL_ACTIVE_COUNT = 87;
const REAL_ARCHIVED_COUNT = 4;

const DEMO_SESSION_ID = 1;
const SHIFT_COUNT = 114;
/** Sales carried by the newest `HISTORICAL_SHIFT_WINDOW` sessions (they keep a shift link). */
const SALES_LINKED_TO_IMPORTED_SHIFTS = 3930;

const DEMO_SALE_IDS = [1, 2, 3, 4, 5];
const DEMO_SALE_BLUEPRINT = [
  { productId: 33, subtotal: 1150, itbis: 207, cost: 760 },
  { productId: 33, subtotal: 1150, itbis: 207, cost: 760 },
  { productId: 33, subtotal: 1150, itbis: 207, cost: 760 },
  { productId: 14, subtotal: 3400, itbis: 612, cost: 2400 },
  { productId: 26, subtotal: 4300, itbis: 774, cost: 3200 },
];

const COMPLETED_SALES = 7176;
const CANCELLED_SALES = 3;
const REAL_SALES = COMPLETED_SALES + CANCELLED_SALES;

const COMPLETED_ITEMS = 9742;
const CANCELLED_ITEMS = 4;

/** item prices/costs chosen so the totals match the audited database exactly */
const STD_PRICE = 112.4;
const STD_COST = 76.16;
const TAIL_PRICE = 296.6;
const TAIL_COST = 192.32;

const CANCELLED_PRICES = [100, 100, 100, 50];
const CANCELLED_COSTS = [66, 66, 66, 68];

/** 2 items for the first N completed sales, 1 item for the rest */
const COMPLETED_SALES_WITH_TWO_ITEMS = 2566;

const CYCLIC_CATEGORY_IDS = Array.from({ length: 20 }, (_, index) => 11 + index);
const ACTIVE_WITHOUT_CATEGORY = 7;

function dayIso(offsetDays: number): string {
  const base = Date.UTC(2026, 5, 4); // 2026-06-04
  return new Date(base + offsetDays * 86_400_000).toISOString().slice(0, 10);
}

function epochMs(offsetMinutes: number): number {
  return Date.UTC(2026, 5, 4, 15, 0, 0) + offsetMinutes * 60_000;
}

export function buildGoldenFixture(): MigrationInput {
  const categories: LegacyCategory[] = CYCLIC_CATEGORY_IDS.map((id) => ({
    id,
    name: `CAT-${id}`,
  }));

  const products: LegacyProduct[] = [];

  // DEMO block: ids 1..50, stock total 1,420.00 (10 products x 142.00)
  for (let i = 1; i <= DEMO_PRODUCT_COUNT; i += 1) {
    products.push({
      id: i,
      code: `DEMO-${String(i).padStart(3, '0')}`,
      name: `Producto DEMO ${i}`,
      category_id: null,
      purchase_price: 10,
      sale_price: 20,
      stock: i <= 10 ? 142 : 0,
      stock_min: 0,
      is_active: 0,
      deleted_at_ms: epochMs(i),
      image_path: null,
    });
  }

  // Real active products: 87 (75 positive + 12 zero), stock total 1,557.00
  // (1 x 1,409.00 + 74 x 2.00 = 1,557.00)
  for (let index = 0; index < REAL_ACTIVE_COUNT; index += 1) {
    const id = REAL_PRODUCT_FIRST_ID + index;
    const stock = index === 0 ? 1409 : index < 75 ? 2 : 0;
    products.push({
      id,
      code: `REAL-${String(id).padStart(3, '0')}`,
      name: `Producto real ${id}`,
      category_id: index < ACTIVE_WITHOUT_CATEGORY ? null : CYCLIC_CATEGORY_IDS[index % 20],
      purchase_price: STD_COST,
      sale_price: STD_PRICE,
      stock,
      stock_min: index % 3 === 0 ? 1 : 0,
      is_active: 1,
      deleted_at_ms: null,
      image_path: `C:\\ProgramData\\FullPOS_PTV\\media\\products\\product_${1_780_000_000_000 + id}.jpg`,
    });
  }

  // Real archived products: 4, one with the documented legacy stock -1.00
  for (let index = 0; index < REAL_ARCHIVED_COUNT; index += 1) {
    const id = REAL_PRODUCT_FIRST_ID + REAL_ACTIVE_COUNT + index;
    products.push({
      id,
      code: `ARCH-${String(id).padStart(3, '0')}`,
      name: `Producto archivado ${id}`,
      category_id: CYCLIC_CATEGORY_IDS[index % 20],
      purchase_price: STD_COST,
      sale_price: STD_PRICE,
      stock: index === 0 ? -1 : 0,
      stock_min: 0,
      is_active: 0,
      deleted_at_ms: epochMs(1000 + index),
      image_path: null,
    });
  }

  const cashSessions: LegacyCashSession[] = [];
  for (let id = 1; id <= SHIFT_COUNT; id += 1) {
    cashSessions.push({
      id,
      user_name: id % 2 === 0 ? 'Cafeteria_caja' : 'Admin',
      status: 'CLOSED',
      business_date: dayIso(id - DEMO_SESSION_ID),
      opened_at_ms: epochMs(id * 60),
      closed_at_ms: epochMs(id * 60 + 30),
      initial_amount: id === DEMO_SESSION_ID ? 0 : 3500,
      closing_amount: id === DEMO_SESSION_ID ? 13157 : 1000 + id,
      expected_cash: id === DEMO_SESSION_ID ? 13157 : 1000 + id,
      difference: 0,
    });
  }

  const sales: LegacySale[] = [];
  const saleItems: LegacySaleItem[] = [];

  // DEMO sales: ids 1..5, each with exactly one DEMO line (never mixed)
  DEMO_SALE_IDS.forEach((saleId, index) => {
    const blueprint = DEMO_SALE_BLUEPRINT[index];
    sales.push({
      id: saleId,
      local_code: `V-IDEM-DEMO-${saleId}`,
      status: 'completed',
      session_id: DEMO_SESSION_ID,
      subtotal: blueprint.subtotal,
      itbis_amount: blueprint.itbis,
      total: blueprint.subtotal + blueprint.itbis,
      created_at_ms: epochMs(saleId),
      updated_at_ms: epochMs(saleId),
    });
    saleItems.push({
      id: saleId,
      sale_id: saleId,
      product_id: blueprint.productId,
      product_code_snapshot: `DEMO-${String(blueprint.productId).padStart(3, '0')}`,
      product_name_snapshot: `Producto DEMO ${blueprint.productId}`,
      qty: 1,
      unit_price: blueprint.subtotal,
      purchase_price_snapshot: blueprint.cost,
      discount_line: 0,
      total_line: blueprint.subtotal,
      created_at_ms: epochMs(saleId),
    });
  });

  // Real sales: ids 6..7184 (7,179).
  // Session layout mirrors the audited source: sessions 2..11 have no sales, the newest 50
  // sessions (65..114) carry the 3,930 sales that keep a shift link, and the older 53 sessions
  // with sales (12..64) carry the 3,249 sales imported with cashSessionId = NULL.
  const firstRealSaleId = DEMO_SALE_IDS.length + 1;
  const newestWindowSessionIds = Array.from(
    { length: HISTORICAL_SHIFT_WINDOW },
    (_, index) => SHIFT_COUNT - HISTORICAL_SHIFT_WINDOW + 1 + index,
  );
  const olderSessionIds = Array.from({ length: 53 }, (_, index) => 12 + index);
  let nextItemId = DEMO_SALE_IDS.length + 1;
  let completedItemIndex = 0;
  let cancelledItemIndex = 0;

  for (let index = 0; index < REAL_SALES; index += 1) {
    const saleId = firstRealSaleId + index;
    const isCancelled = index >= COMPLETED_SALES;
    const sessionId =
      index < SALES_LINKED_TO_IMPORTED_SHIFTS
        ? newestWindowSessionIds[index % newestWindowSessionIds.length]
        : olderSessionIds[(index - SALES_LINKED_TO_IMPORTED_SHIFTS) % olderSessionIds.length];
    const itemCount = isCancelled
      ? index === COMPLETED_SALES
        ? 2
        : 1
      : index < COMPLETED_SALES_WITH_TWO_ITEMS
        ? 2
        : 1;

    let subtotal = 0;
    for (let itemIndex = 0; itemIndex < itemCount; itemIndex += 1) {
      let price: number;
      let cost: number;
      if (isCancelled) {
        price = CANCELLED_PRICES[cancelledItemIndex];
        cost = CANCELLED_COSTS[cancelledItemIndex];
        cancelledItemIndex += 1;
      } else {
        completedItemIndex += 1;
        const isTail = completedItemIndex === COMPLETED_ITEMS;
        price = isTail ? TAIL_PRICE : STD_PRICE;
        cost = isTail ? TAIL_COST : STD_COST;
      }

      subtotal += price;
      saleItems.push({
        id: nextItemId,
        sale_id: saleId,
        product_id: REAL_PRODUCT_FIRST_ID + (nextItemId % REAL_ACTIVE_COUNT),
        product_code_snapshot: `REAL-${String(REAL_PRODUCT_FIRST_ID + (nextItemId % REAL_ACTIVE_COUNT)).padStart(3, '0')}`,
        product_name_snapshot: `Producto real ${REAL_PRODUCT_FIRST_ID + (nextItemId % REAL_ACTIVE_COUNT)}`,
        qty: 1,
        unit_price: price,
        purchase_price_snapshot: cost,
        discount_line: 0,
        total_line: price,
        created_at_ms: epochMs(10_000 + saleId),
      });
      nextItemId += 1;
    }

    sales.push({
      id: saleId,
      local_code: `V-IDEM-${saleId}`,
      status: isCancelled ? 'cancelled' : 'completed',
      session_id: sessionId,
      subtotal,
      itbis_amount: 0,
      total: subtotal,
      created_at_ms: epochMs(10_000 + saleId),
      updated_at_ms: epochMs(10_000 + saleId + (isCancelled ? 60 : 0)),
    });
  }

  return { products, categories, cashSessions, sales, saleItems };
}

/* ------------------------------------------------------------------ */
/* Targeted fixtures for the abort / exclusion rules                  */
/* ------------------------------------------------------------------ */

export function buildMinimalInput(overrides: Partial<MigrationInput> = {}): MigrationInput {
  const categories: LegacyCategory[] = [{ id: 11, name: 'AGUA' }];
  const products: LegacyProduct[] = [
    {
      id: 1,
      code: 'DEMO-001',
      name: 'Demo',
      category_id: null,
      purchase_price: 10,
      sale_price: 20,
      stock: 1420,
      stock_min: 0,
      is_active: 0,
      deleted_at_ms: epochMs(1),
      image_path: null,
    },
    {
      id: 51,
      code: 'REAL-051',
      name: 'Real',
      category_id: 11,
      purchase_price: 100,
      sale_price: 150,
      stock: 10,
      stock_min: 0,
      is_active: 1,
      deleted_at_ms: null,
      image_path: null,
    },
  ];
  const cashSessions: LegacyCashSession[] = [
    {
      id: 1,
      user_name: 'Admin',
      status: 'CLOSED',
      business_date: '2026-06-04',
      opened_at_ms: epochMs(60),
      closed_at_ms: epochMs(90),
      initial_amount: 0,
      closing_amount: 1357,
      expected_cash: 1357,
      difference: 0,
    },
    {
      id: 2,
      user_name: 'Admin',
      status: 'CLOSED',
      business_date: '2026-06-05',
      opened_at_ms: epochMs(120),
      closed_at_ms: epochMs(150),
      initial_amount: 0,
      closing_amount: 150,
      expected_cash: 150,
      difference: 0,
    },
  ];
  const sales: LegacySale[] = [
    {
      id: 1,
      local_code: 'V-IDEM-DEMO-1',
      status: 'completed',
      session_id: 1,
      subtotal: 1150,
      itbis_amount: 207,
      total: 1357,
      created_at_ms: epochMs(1),
      updated_at_ms: epochMs(1),
    },
    {
      id: 2,
      local_code: 'V-IDEM-2',
      status: 'completed',
      session_id: 2,
      subtotal: 150,
      itbis_amount: 0,
      total: 150,
      created_at_ms: epochMs(2),
      updated_at_ms: epochMs(2),
    },
  ];
  const saleItems: LegacySaleItem[] = [
    {
      id: 1,
      sale_id: 1,
      product_id: 1,
      product_code_snapshot: 'DEMO-001',
      product_name_snapshot: 'Demo',
      qty: 1,
      unit_price: 1150,
      purchase_price_snapshot: 760,
      discount_line: 0,
      total_line: 1150,
      created_at_ms: epochMs(1),
    },
    {
      id: 2,
      sale_id: 2,
      product_id: 51,
      product_code_snapshot: 'REAL-051',
      product_name_snapshot: 'Real',
      qty: 1,
      unit_price: 150,
      purchase_price_snapshot: 100,
      discount_line: 0,
      total_line: 150,
      created_at_ms: epochMs(2),
    },
  ];

  return { products, categories, cashSessions, sales, saleItems, ...overrides };
}

export const GOLDEN_FIXTURE_EXPECTED = {
  products: 91,
  activeProducts: 87,
  archivedProducts: 4,
  openingStock: '1557.00',
  sourceRealShifts: 113,
  shifts: 50,
  shiftsNotImported: 63,
  salesLinkedToImportedShifts: 3930,
  salesWithoutShiftLink: 3249,
  sales: 7179,
  completedSales: 7176,
  cancelledSales: 3,
  saleItems: 9746,
  revenue: '1095535.00',
  cost: '742332.88',
  profit: '353202.12',
} as const;
