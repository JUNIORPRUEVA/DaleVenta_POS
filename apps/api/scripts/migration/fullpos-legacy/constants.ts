/**
 * FullPOS Local (SQLite) -> FullPOS Cloud migration.
 * Phase 3 - MINIMAL scope: products, opening stock, historical shifts, sales, sale items, cost/profit.
 *
 * Every identifier below is LOCKED. A divergence aborts the run (see guards.ts).
 * This module performs no I/O.
 */

export const MIGRATION_VERSION = '1.0.0';
export const SOURCE_SYSTEM = 'FULLPOS_LOCAL_SQLITE';

/**
 * Fixed UUIDv5 namespace for this migration.
 * IMMUTABLE: changing it changes every derived target id (and would break rollback/idempotency).
 */
export const MIGRATION_NAMESPACE_UUID = '6f1c4b1e-8f2a-4c3d-9b7e-2a5d1c0f9e11';

export const EXPECTED_SOURCE_SHA256 =
  'A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA';

export const TARGET_COMPANY_ID = 'f3651f62-be10-41aa-bde7-663cf990eae8';
export const TARGET_COMPANY_NAME = 'Cafeteria la bomba';
export const TARGET_WAREHOUSE_ID = 'ffc9ef9b-9157-418d-8aa1-94112278bb68';
export const TARGET_TERMINAL_ID = '00931697-e152-48bc-9e44-02023e14d465';
export const TARGET_OWNER_USER_ID = 'adc4bf90-41b3-4e20-99eb-f37d398200f5';

/** Legacy product code prefix that identifies the synthetic DEMO block. */
export const DEMO_PRODUCT_CODE_PREFIX = 'DEMO-';

/** Legacy cash session that only contains DEMO sales (derived from data, asserted against this). */
export const DEMO_CASH_SESSION_ID = 1;

/** Legacy categories never used by real products; kept for documentation only. */
export const DEMO_CATEGORY_MAX_ID = 10;

/** Product.categoria is NOT NULL in production and is never empty; legacy NULL categories get this value. */
export const DEFAULT_CATEGORY_FALLBACK = 'General';

/** Existing global UnitOfMeasure used by every imported product (never modified). */
export const UNIT_OF_MEASURE_CODE = 'UNIT';

export const LEGACY_TABLE = {
  products: 'products',
  categories: 'categories',
  cashSessions: 'cash_sessions',
  sales: 'sales',
  saleItems: 'sale_items',
} as const;

export type LegacyTableName = (typeof LEGACY_TABLE)[keyof typeof LEGACY_TABLE];

/** Authoritative dry-run targets (Phase 2 / 2.5). Any mismatch => NO-GO. */
export const EXPECTED = {
  products: 91,
  activeProducts: 87,
  archivedProducts: 4,
  openingStock: '1557.00',
  activeStockPositive: 75,
  activeStockZero: 12,
  activeStockNegative: 0,
  archivedOperationalStock: '0.00',
  legacyArchivedNegativeStock: '0.00',
  sales: 7179,
  completedSales: 7176,
  cancelledSales: 3,
  saleItems: 9746,
  revenue: '1095535.00',
  cost: '742332.88',
  profit: '353202.12',
  itbis: '0.00',
  ncf: 0,
  /** Imported historical shifts: the newest 50 real CLOSED sessions. */
  shifts: 50,
  /** Real (non-DEMO) CLOSED sessions present in the source. */
  sourceRealShifts: 113,
  /** Real sessions intentionally NOT migrated (older than the window). */
  shiftsNotImported: 63,
  /** Imported sales linked to one of the 50 imported shifts. */
  salesLinkedToImportedShifts: 3930,
  /** Imported sales kept with cashSessionId = NULL (their shift is outside the window). */
  salesWithoutShiftLink: 3249,
  customersCreated: 0,
  clientsCreated: 0,
  legacyUsersCreated: 0,
  suppliersCreated: 0,
  purchasesCreated: 0,
  inventoryMovementsImported: 0,
  cashMovementsImported: 0,
  cashboxDailyImported: 0,
  demoProductsImported: 0,
  demoSalesImported: 0,
  demoSaleItemsImported: 0,
  demoShiftsImported: 0,
  demoProducts: 50,
  demoSales: 5,
  demoSaleItems: 5,
  demoShifts: 1,
  demoStock: '1420.00',
  demoItbis: '2007.00',
} as const;

/** Legacy operator attribution is UNKNOWN: the source has no per-sale operator column. */
export const LEGACY_OPERATOR_UNKNOWN = 'UNKNOWN';

export const IMAGE_STATUS_PENDING = 'PENDING';

/* ------------------------------------------------------------------ */
/* Historical shift window (locked business requirement)              */
/* ------------------------------------------------------------------ */

/**
 * The customer only needs recent shift history, and the Cloud history screen
 * already retrieves up to 60 CLOSED shifts (cash.service.ts `closedSessions()`
 * orders by closedAt DESC, take 60). Importing the 50 newest real shifts keeps
 * room for future shifts inside that existing window WITHOUT touching the
 * endpoint, adding pagination or changing the take:60 behaviour.
 */
export const HISTORICAL_SHIFT_POLICY = 'LATEST_50_REAL_CLOSED';
export const HISTORICAL_SHIFT_WINDOW = 50;
export const SHIFT_OMISSION_REASON = 'OLDER_THAN_MIGRATION_SHIFT_WINDOW';

/** Sales are NEVER discarded: those whose legacy shift falls outside the window keep cashSessionId = NULL. */
export const SHIFT_LINK_OUTSIDE_WINDOW = null;
