/**
 * Types for the legacy (SQLite) source rows, the planned target entities,
 * the dry-run report and the immutable manifest.
 * Pure declarations: no I/O, no side effects.
 */

/* ------------------------------------------------------------------ */
/* Legacy source rows (read-only projections of the SQLite database)  */
/* ------------------------------------------------------------------ */

export type LegacyProduct = {
  id: number;
  code: string;
  name: string;
  category_id: number | null;
  purchase_price: number;
  sale_price: number;
  stock: number;
  stock_min: number;
  is_active: number;
  deleted_at_ms: number | null;
  image_path: string | null;
};

export type LegacyCategory = {
  id: number;
  name: string;
};

export type LegacyCashSession = {
  id: number;
  user_name: string;
  status: string;
  business_date: string | null;
  opened_at_ms: number;
  closed_at_ms: number | null;
  initial_amount: number;
  closing_amount: number | null;
  expected_cash: number | null;
  difference: number | null;
};

export type LegacySale = {
  id: number;
  local_code: string;
  status: string;
  session_id: number | null;
  subtotal: number;
  itbis_amount: number;
  total: number;
  created_at_ms: number;
  updated_at_ms: number;
};

export type LegacySaleItem = {
  id: number;
  sale_id: number;
  product_id: number | null;
  product_code_snapshot: string;
  product_name_snapshot: string;
  qty: number;
  unit_price: number;
  purchase_price_snapshot: number;
  discount_line: number;
  total_line: number;
  created_at_ms: number;
};

/* ------------------------------------------------------------------ */
/* Planned target entities                                             */
/* ------------------------------------------------------------------ */

export type PlannedProduct = {
  legacyId: number;
  targetId: string;
  code: string;
  name: string;
  categoria: string;
  categoriaFromLegacy: boolean;
  costCents: bigint;
  priceCents: bigint;
  /** Stock as stored in the legacy system (may be negative; archived products keep it in the manifest). */
  legacyStockMicro: bigint;
  /** Stock to write into Product.stock + WarehouseStock.quantity (0 for archived products). */
  operationalStockMicro: bigint;
  isArchived: boolean;
  archivedAtIso: string | null;
  legacyStockMinMicro: bigint;
  imageStatus: 'PENDING' | 'NONE';
  legacyImagePath: string | null;
};

export type PlannedShift = {
  legacyId: number;
  targetId: string;
  businessDate: string;
  status: 'CLOSED';
  legacyUserName: string;
  openedAtIso: string;
  closedAtIso: string;
  initialAmountCents: bigint;
  closingAmountCents: bigint;
  expectedAmountCents: bigint;
  differenceCents: bigint;
  /** Sales linked to this shift AFTER demo exclusion. */
  salesCount: number;
};

export type PlannedSale = {
  legacyId: number;
  targetId: string;
  localCode: string;
  saleDateIso: string;
  status: 'PAID' | 'CANCELLED';
  cancelledAtIso: string | null;
  /** Legacy session id (may be absent in the source; the target link is still optional). */
  legacySessionId: number | null;
  /** Mapped imported shift, or NULL when the legacy shift is outside the migration window. */
  targetShiftId: string | null;
  /** Always UNKNOWN: the legacy sales table has no operator column. Never the target owner's name. */
  legacyOperator: string;
  revenueCents: bigint;
  itbisCents: bigint;
  costCents: bigint;
  profitCents: bigint;
  itemCount: number;
};

export type PlannedSaleItem = {
  legacyId: number;
  targetId: string;
  legacySaleId: number;
  targetSaleId: string;
  legacyProductId: number;
  targetProductId: string;
  productCodeSnapshot: string;
  productNameSnapshot: string;
  qtyMicro: bigint;
  unitPriceCents: bigint;
  costUnitCents: bigint;
  lineTotalCents: bigint;
  lineDiscountCents: bigint;
  subtotalCostCents: bigint;
  profitCents: bigint;
};

/* ------------------------------------------------------------------ */
/* Exclusions / exceptions                                             */
/* ------------------------------------------------------------------ */

export type ExclusionReason =
  | 'DEMO_PRODUCT'
  | 'DEMO_SALE'
  | 'DEMO_SALE_ITEM'
  | 'DEMO_SHIFT';

export type ExcludedRecord = {
  reason: ExclusionReason;
  legacyTable: string;
  legacyId: number;
  detail: string;
};

export type StockException = {
  kind: 'NEGATIVE_ARCHIVED_STOCK';
  legacyProductId: number;
  code: string;
  name: string;
  legacyStock: string;
  operationalStock: string;
  detail: string;
};

/* ------------------------------------------------------------------ */
/* Migration plan + reports                                            */
/* ------------------------------------------------------------------ */

export type DemoBlock = {
  productIds: number[];
  saleIds: number[];
  saleItemIds: number[];
  shiftIds: number[];
  productCount: number;
  saleCount: number;
  saleItemCount: number;
  shiftCount: number;
  stockCents: bigint;
  itbisCents: bigint;
  revenueCents: bigint;
};

export type ShiftPolicySummary = {
  policy: string;
  window: number;
  reason: string;
  sourceRealShifts: number;
  imported: number;
  notImported: number;
  /** Legacy session ids intentionally left out (older than the window). Never failures. */
  notImportedLegacyIds: number[];
  /** Real legacy sessions skipped because they are not CLOSED (expected empty). */
  skippedNotClosedLegacyIds: number[];
  boundary: {
    oldestImportedClosedAt: string | null;
    newestNotImportedClosedAt: string | null;
  };
};

export type MigrationPlan = {
  products: PlannedProduct[];
  shifts: PlannedShift[];
  sales: PlannedSale[];
  saleItems: PlannedSaleItem[];
  excluded: ExcludedRecord[];
  stockExceptions: StockException[];
  demo: DemoBlock;
  shiftPolicy: ShiftPolicySummary;
  totals: {
    products: number;
    activeProducts: number;
    archivedProducts: number;
    openingStockCents: bigint;
    activeStockPositive: number;
    activeStockZero: number;
    activeStockNegative: number;
    archivedOperationalStockCents: bigint;
    shifts: number;
    sourceRealShifts: number;
    shiftsNotImported: number;
    salesLinkedToImportedShifts: number;
    salesWithoutShiftLink: number;
    sales: number;
    completedSales: number;
    cancelledSales: number;
    saleItems: number;
    revenueCents: bigint;
    costCents: bigint;
    profitCents: bigint;
    itbisCents: bigint;
    ncf: number;
    customersCreated: number;
    legacyUsersCreated: number;
    suppliersCreated: number;
    purchasesCreated: number;
    inventoryMovementsImported: number;
    cashMovementsImported: number;
    cashboxDailyImported: number;
    imagesPending: number;
  };
};

export type ReconciliationCheck = {
  metric: string;
  expected: string;
  actual: string;
  ok: boolean;
};

export type ReconciliationReport = {
  generatedAt: string;
  checks: ReconciliationCheck[];
  failures: ReconciliationCheck[];
  verdict: 'GO' | 'NO-GO';
};

/* ------------------------------------------------------------------ */
/* Target validation (read-only)                                      */
/* ------------------------------------------------------------------ */

export type TargetSnapshot = {
  source: 'LIVE_READ_ONLY' | 'OFFLINE_READ_ONLY';
  capturedAt: string;
  company: {
    id: string;
    name: string;
    status: string;
    plan: string;
    licenseStatus: string;
    productSource: string | null;
    maxProducts: number;
  } | null;
  warehouse: {
    id: string;
    companyId: string;
    name: string;
    code: string;
    isActive: boolean;
  } | null;
  terminal: {
    id: string;
    companyId: string;
    name: string;
    code: string;
    isActive: boolean;
    defaultWarehouseId: string;
  } | null;
  ownerUser: { id: string; companyId: string | null; blocked: boolean } | null;
  baseline: {
    productsTotal: number;
    productsNonArchived: number;
    sales: number;
    saleItems: number;
    warehouseStocks: number;
    inventoryMovements: number;
    cashSessions: number;
    cashboxDaily: number;
    cashMovements: number;
    clients: number;
    suppliers: number;
    purchaseOrders: number;
    taxes: number;
    ncfSequences: number;
  };
  /** Observations that do not abort but must be reported. */
  notes: string[];
};
