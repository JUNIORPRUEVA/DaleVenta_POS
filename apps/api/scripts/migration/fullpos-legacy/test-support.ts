/**
 * Shared test helpers (not a test file: it has no `describe`/`it`).
 * Keeping `buildSnapshot` here prevents one spec from re-executing another spec's tests.
 */

import {
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_OWNER_USER_ID,
  TARGET_TERMINAL_ID,
  TARGET_WAREHOUSE_ID,
} from './constants';
import type { TargetSnapshot } from './types';

export const OTHER_TENANT_ID = '99999999-9999-4999-8999-999999999999';

export function buildSnapshot(overrides: Partial<TargetSnapshot> = {}): TargetSnapshot {
  const base: TargetSnapshot = {
    source: 'OFFLINE_READ_ONLY',
    capturedAt: '2026-09-16T00:00:00.000Z',
    company: {
      id: TARGET_COMPANY_ID,
      name: TARGET_COMPANY_NAME,
      status: 'ACTIVE',
      plan: 'STANDARD',
      licenseStatus: 'TRIAL',
      productSource: null,
      maxProducts: 100,
    },
    warehouse: {
      id: TARGET_WAREHOUSE_ID,
      companyId: TARGET_COMPANY_ID,
      name: 'Main Warehouse',
      code: 'MAIN',
      isActive: true,
    },
    terminal: {
      id: TARGET_TERMINAL_ID,
      companyId: TARGET_COMPANY_ID,
      name: 'Default Terminal',
      code: 'DEFAULT',
      isActive: true,
      defaultWarehouseId: TARGET_WAREHOUSE_ID,
    },
    ownerUser: { id: TARGET_OWNER_USER_ID, companyId: TARGET_COMPANY_ID, blocked: false },
    baseline: {
      productsTotal: 0,
      productsNonArchived: 0,
      sales: 0,
      saleItems: 0,
      warehouseStocks: 0,
      inventoryMovements: 0,
      cashSessions: 0,
      cashboxDaily: 0,
      cashMovements: 0,
      clients: 0,
      suppliers: 0,
      purchaseOrders: 0,
      taxes: 0,
      ncfSequences: 0,
    },
    notes: [],
  };
  return { ...base, ...overrides };
}
