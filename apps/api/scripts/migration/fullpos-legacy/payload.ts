/**
 * Pure mapping from planned entities to the exact target write payloads.
 *
 * This is the payload the (future, unauthorized) execute path would insert, and it
 * is what the tests assert: imported history must carry ZERO operational effects.
 *
 * Encoded invariants (verified against the current cloud code):
 *  - SaleItem.inventoryTrackedSnapshot = false
 *      -> the cancellation (sales.service.ts:2248), return (2446/2536/2675) and refund
 *         paths all skip stock mutations, so browsing/cancelling imported history can
 *         never deduct or restore stock.
 *  - Sale.customerId = null and NO Client row is ever built (customers out of scope).
 *  - Sale.commissionRate = 0 and Sale.commissionAmount = 0 (no artificial 10% commission;
 *    payroll auto-commission aggregates sale.commissionAmount by user+period).
 *  - fiscalTaxEnabled = false, fiscalPriceMode = NO_TAX, ncf = null: NON-FISCAL history.
 *  - Product.source / ProductSource stays LOCAL-compatible: ProductSource enum is NOT
 *    written (company.productSource stays NULL, which the resolver treats as LOCAL) and
 *    `SaleItem.productSource` is written as LOCAL so nothing is treated as external.
 *  - Shift: status CLOSED with a real closedAt (closedSessions() orders by closedAt DESC
 *    with take 60; a NULL closedAt would sort first in Postgres and hide real shifts).
 */

import {
  LEGACY_OPERATOR_UNKNOWN,
  TARGET_COMPANY_ID,
  TARGET_OWNER_USER_ID,
  UNIT_OF_MEASURE_CODE,
} from './constants';
import type {
  MigrationPlan,
  PlannedProduct,
  PlannedSale,
  PlannedSaleItem,
  PlannedShift,
} from './types';

export const CANCELLATION_REASON_LEGACY = 'Cancelada en el sistema anterior (FullPOS Local)';

export type ProductWritePayload = {
  id: string;
  companyId: string;
  unitOfMeasureId: string;
  nombre: string;
  codigo: string;
  categoria: string;
  costo: string;
  precio: string;
  stock: string;
  itemType: 'PRODUCT';
  trackInventory: boolean;
  taxTreatment: 'INHERIT';
  taxRate: null;
  taxPriceMode: null;
  imagen: null;
  imageStorageProvider: null;
  imageKey: null;
  archivedAt: string | null;
};

export type WarehouseStockWritePayload = {
  companyId: string;
  warehouseId: string;
  productId: string;
  quantity: string;
};

export type ShiftWritePayload = {
  id: string;
  companyId: string;
  openedByUserId: string;
  userName: string;
  businessDate: string;
  status: 'CLOSED';
  openedAt: string;
  closedAt: string;
  initialAmount: string;
  closingAmount: string;
  expectedAmount: string;
  difference: string;
  terminalId: null;
  note: null;
};

export type SaleWritePayload = {
  id: string;
  companyId: string;
  userId: string;
  customerId: null;
  /** Mapped imported shift, or NULL when the legacy shift is outside the migration window. */
  cashSessionId: string | null;
  terminalId: null;
  clientRequestId: string;
  saleDate: string;
  note: null;
  paymentMethod: 'cash';
  paymentCashAmount: string;
  paymentTransferAmount: string;
  cashReceived: string;
  changeAmount: string;
  creditAmount: string;
  creditPaidAmount: string;
  creditBalance: string;
  creditStatus: 'none';
  kind: 'invoice';
  status: 'PAID' | 'CANCELLED';
  totalSold: string;
  fiscalTaxEnabled: false;
  fiscalPriceMode: 'NO_TAX';
  taxableBase: string;
  taxAmount: string;
  exemptAmount: string;
  discountAmount: string;
  fiscalVoucherType: null;
  ncf: null;
  ncfExpirationDate: null;
  totalCost: string;
  totalProfit: string;
  commercialProfit: string;
  netTaxProfit: string;
  commercialMargin: null;
  netTaxMargin: null;
  commissionRate: string;
  commissionAmount: string;
  cancelledAt: string | null;
  cancelledById: null;
  cancellationReason: string | null;
  inventoryRestoredAt: null;
  isDeleted: false;
};

export type SaleItemWritePayload = {
  id: string;
  saleId: string;
  productId: string;
  productSource: 'LOCAL';
  sourceProductId: null;
  warehouseId: null;
  warehouseNameSnapshot: null;
  warehouseCodeSnapshot: null;
  productNameSnapshot: string;
  productImageSnapshot: null;
  qty: string;
  unitCodeSnapshot: string;
  unitNameSnapshot: string;
  unitSymbolSnapshot: string;
  unitPrecisionSnapshot: 0;
  inventoryTrackedSnapshot: false;
  priceSoldUnit: string;
  grossAmount: string;
  lineDiscountAmount: string;
  taxableBase: string;
  taxRate: string;
  taxAmount: string;
  exemptAmount: string;
  taxIncluded: false;
  taxExempt: true;
  costUnitSnapshot: string;
  subtotalSold: string;
  subtotalCost: string;
  profit: string;
  commercialProfit: string;
  netTaxProfit: string;
};

export type WritePlan = {
  products: ProductWritePayload[];
  warehouseStocks: WarehouseStockWritePayload[];
  shifts: ShiftWritePayload[];
  sales: SaleWritePayload[];
  saleItems: SaleItemWritePayload[];
};

const UOM_SNAPSHOT = {
  unitCodeSnapshot: UNIT_OF_MEASURE_CODE,
  unitNameSnapshot: 'Unidad',
  unitSymbolSnapshot: 'u',
  unitPrecisionSnapshot: 0 as const,
};

function decimalFromCents(cents: bigint): string {
  const negative = cents < 0n;
  const abs = negative ? -cents : cents;
  const integerPart = abs / 100n;
  const fraction = (abs % 100n).toString().padStart(2, '0');
  return `${negative ? '-' : ''}${integerPart.toString()}.${fraction}`;
}

function decimalFromMicro(micro: bigint): string {
  const negative = micro < 0n;
  const abs = negative ? -micro : micro;
  const integerPart = abs / 1_000_000n;
  const fraction = (abs % 1_000_000n).toString().padStart(6, '0');
  return `${negative ? '-' : ''}${integerPart.toString()}.${fraction}`;
}

export function buildProductPayload(product: PlannedProduct): ProductWritePayload {
  return {
    id: product.targetId,
    companyId: TARGET_COMPANY_ID,
    unitOfMeasureId: UNIT_OF_MEASURE_CODE,
    nombre: product.name,
    codigo: product.code,
    categoria: product.categoria,
    costo: decimalFromCents(product.costCents),
    precio: decimalFromCents(product.priceCents),
    // Archived products get NO operational stock (reconciliation invariant with WarehouseStock).
    stock: decimalFromMicro(product.operationalStockMicro),
    itemType: 'PRODUCT',
    trackInventory: true,
    taxTreatment: 'INHERIT',
    taxRate: null,
    taxPriceMode: null,
    imagen: null,
    imageStorageProvider: null,
    imageKey: null,
    archivedAt: product.archivedAtIso,
  };
}

export function buildWarehouseStockPayload(
  product: PlannedProduct,
  warehouseId: string,
): WarehouseStockWritePayload {
  return {
    companyId: TARGET_COMPANY_ID,
    warehouseId,
    productId: product.targetId,
    quantity: decimalFromMicro(product.operationalStockMicro),
  };
}

export function buildShiftPayload(shift: PlannedShift): ShiftWritePayload {
  return {
    id: shift.targetId,
    companyId: TARGET_COMPANY_ID,
    openedByUserId: TARGET_OWNER_USER_ID,
    // Snapshot of the legacy operator name (no legacy user is created).
    userName: shift.legacyUserName,
    businessDate: shift.businessDate,
    status: 'CLOSED',
    openedAt: shift.openedAtIso,
    closedAt: shift.closedAtIso,
    initialAmount: decimalFromCents(shift.initialAmountCents),
    closingAmount: decimalFromCents(shift.closingAmountCents),
    expectedAmount: decimalFromCents(shift.expectedAmountCents),
    difference: decimalFromCents(shift.differenceCents),
    terminalId: null,
    note: null,
  };
}

export function buildSalePayload(sale: PlannedSale): SaleWritePayload {
  const revenue = decimalFromCents(sale.revenueCents);
  return {
    id: sale.targetId,
    companyId: TARGET_COMPANY_ID,
    userId: TARGET_OWNER_USER_ID,
    customerId: null,
    cashSessionId: sale.targetShiftId,
    terminalId: null,
    clientRequestId: sale.localCode,
    saleDate: sale.saleDateIso,
    note: null,
    paymentMethod: 'cash',
    paymentCashAmount: revenue,
    paymentTransferAmount: '0.00',
    cashReceived: revenue,
    changeAmount: '0.00',
    creditAmount: '0.00',
    creditPaidAmount: revenue,
    creditBalance: '0.00',
    creditStatus: 'none',
    kind: 'invoice',
    status: sale.status,
    totalSold: revenue,
    fiscalTaxEnabled: false,
    fiscalPriceMode: 'NO_TAX',
    taxableBase: '0.00',
    taxAmount: '0.00',
    exemptAmount: revenue,
    discountAmount: '0.00',
    fiscalVoucherType: null,
    ncf: null,
    ncfExpirationDate: null,
    totalCost: decimalFromCents(sale.costCents),
    totalProfit: decimalFromCents(sale.profitCents),
    commercialProfit: decimalFromCents(sale.profitCents),
    netTaxProfit: decimalFromCents(sale.profitCents),
    commercialMargin: null,
    netTaxMargin: null,
    commissionRate: '0.0000',
    commissionAmount: '0.00',
    cancelledAt: sale.cancelledAtIso,
    cancelledById: null,
    cancellationReason: sale.cancelledAtIso ? CANCELLATION_REASON_LEGACY : null,
    inventoryRestoredAt: null,
    isDeleted: false,
  };
}

export function buildSaleItemPayload(item: PlannedSaleItem): SaleItemWritePayload {
  return {
    id: item.targetId,
    saleId: item.targetSaleId,
    productId: item.targetProductId,
    productSource: 'LOCAL',
    sourceProductId: null,
    warehouseId: null,
    warehouseNameSnapshot: null,
    warehouseCodeSnapshot: null,
    productNameSnapshot: item.productNameSnapshot,
    productImageSnapshot: null,
    qty: decimalFromMicro(item.qtyMicro),
    ...UOM_SNAPSHOT,
    // Historical lines must never trigger stock mutations (cancel/return/refund gates).
    inventoryTrackedSnapshot: false,
    priceSoldUnit: decimalFromCents(item.unitPriceCents),
    grossAmount: decimalFromCents(item.lineTotalCents + item.lineDiscountCents),
    lineDiscountAmount: decimalFromCents(item.lineDiscountCents),
    taxableBase: '0.00',
    taxRate: '0.0000',
    taxAmount: '0.00',
    exemptAmount: decimalFromCents(item.lineTotalCents),
    taxIncluded: false,
    taxExempt: true,
    costUnitSnapshot: decimalFromCents(item.costUnitCents),
    subtotalSold: decimalFromCents(item.lineTotalCents),
    subtotalCost: decimalFromCents(item.subtotalCostCents),
    profit: decimalFromCents(item.profitCents),
    commercialProfit: decimalFromCents(item.profitCents),
    netTaxProfit: decimalFromCents(item.profitCents),
  };
}

/** Full target write plan (products, opening stock, shifts, sales, items). Nothing else. */
export function buildWritePlan(
  plan: MigrationPlan,
  options: { warehouseId: string },
): WritePlan {
  return {
    products: plan.products.map(buildProductPayload),
    // Opening stock rows are created ONLY for active (non-archived) products.
    // Archived products keep Product.stock = 0 and no WarehouseStock row, so
    // Product.stock == COALESCE(SUM(WarehouseStock.quantity), 0) still holds.
    warehouseStocks: plan.products
      .filter((product) => !product.isArchived)
      .map((product) => buildWarehouseStockPayload(product, options.warehouseId)),
    shifts: plan.shifts.map(buildShiftPayload),
    sales: plan.sales.map(buildSalePayload),
    saleItems: plan.saleItems.map(buildSaleItemPayload),
  };
}

/** Attribution used by the manifest: never claim the owner made historical sales. */
export function legacyOperatorLabel(): string {
  return LEGACY_OPERATOR_UNKNOWN;
}
