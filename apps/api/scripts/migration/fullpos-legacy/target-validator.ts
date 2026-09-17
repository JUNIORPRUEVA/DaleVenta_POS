/**
 * Read-only target validation.
 *
 * The snapshot describes the locked tenant and its baseline; `assertTargetSnapshot`
 * (guards.ts) aborts when anything diverges.
 *
 * Two sources are supported:
 *  - LIVE: a read-only port over the target database (only SELECT/count operations)
 *  - OFFLINE: a JSON snapshot produced by an authorized read-only query
 *
 * This module never writes. The port interface keeps the core testable without a database.
 */

import { readFileSync } from 'node:fs';
import { MigrationAbortError } from './errors';
import type { TargetSnapshot } from './types';

export type TargetReadPort = {
  company(id: string): Promise<TargetSnapshot['company']>;
  warehouse(id: string): Promise<TargetSnapshot['warehouse']>;
  terminal(id: string): Promise<TargetSnapshot['terminal']>;
  user(id: string): Promise<TargetSnapshot['ownerUser']>;
  baseline(companyId: string): Promise<TargetSnapshot['baseline']>;
};

export async function collectTargetSnapshot(
  port: TargetReadPort,
  ids: { companyId: string; warehouseId: string; terminalId: string; ownerUserId: string },
  capturedAt: string,
): Promise<TargetSnapshot> {
  const [company, warehouse, terminal, ownerUser, baseline] = await Promise.all([
    port.company(ids.companyId),
    port.warehouse(ids.warehouseId),
    port.terminal(ids.terminalId),
    port.user(ids.ownerUserId),
    port.baseline(ids.companyId),
  ]);

  return {
    source: 'LIVE_READ_ONLY',
    capturedAt,
    company,
    warehouse,
    terminal,
    ownerUser,
    baseline,
    notes: [],
  };
}

export function parseTargetSnapshot(json: string, capturedAt = new Date().toISOString()): TargetSnapshot {
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch (error) {
    throw new MigrationAbortError('TARGET_SNAPSHOT_INVALID', 'El snapshot de destino no es JSON válido', {
      cause: error instanceof Error ? error.message : String(error),
    });
  }
  const snapshot = parsed as Partial<TargetSnapshot>;
  const required = ['company', 'warehouse', 'terminal', 'ownerUser', 'baseline'];
  const missing = required.filter((key) => !(key in (snapshot as Record<string, unknown>)));
  if (missing.length > 0) {
    throw new MigrationAbortError('TARGET_SNAPSHOT_INVALID', 'Faltan claves en el snapshot de destino', {
      missing,
    });
  }
  return {
    source: 'OFFLINE_READ_ONLY',
    capturedAt: snapshot.capturedAt ?? capturedAt,
    company: snapshot.company ?? null,
    warehouse: snapshot.warehouse ?? null,
    terminal: snapshot.terminal ?? null,
    ownerUser: snapshot.ownerUser ?? null,
    baseline: snapshot.baseline as TargetSnapshot['baseline'],
    notes: Array.isArray(snapshot.notes) ? snapshot.notes : [],
  };
}

export function loadTargetSnapshotFile(filePath: string): TargetSnapshot {
  let content: string;
  try {
    content = readFileSync(filePath, 'utf8');
  } catch (error) {
    throw new MigrationAbortError('TARGET_SNAPSHOT_UNREADABLE', 'No se pudo leer el snapshot de destino', {
      path: filePath,
      cause: error instanceof Error ? error.message : String(error),
    });
  }
  return parseTargetSnapshot(content);
}

/** Read-only SQL used to produce the offline snapshot (documented for the operator). */
export const TARGET_SNAPSHOT_SQL = {
  company:
    'SELECT id, name, status, plan, license_status, product_source, max_products FROM companies WHERE id = :companyId',
  warehouse:
    'SELECT id, company_id, name, code, is_active FROM warehouses WHERE id = :warehouseId',
  terminal:
    'SELECT id, company_id, name, code, is_active, default_warehouse_id FROM terminals WHERE id = :terminalId',
  ownerUser: 'SELECT id, company_id, blocked FROM users WHERE id = :ownerUserId',
  baseline: [
    'SELECT count(*) FROM "Product" WHERE company_id = :companyId',
    'SELECT count(*) FROM "Product" WHERE company_id = :companyId AND archived_at IS NULL',
    'SELECT count(*) FROM "Sale" WHERE company_id = :companyId',
    'SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId" WHERE s.company_id = :companyId',
    'SELECT count(*) FROM warehouse_stocks WHERE company_id = :companyId',
    'SELECT count(*) FROM inventory_movements WHERE company_id = :companyId',
    'SELECT count(*) FROM cash_sessions WHERE company_id = :companyId',
    'SELECT count(*) FROM cashbox_daily WHERE company_id = :companyId',
    'SELECT count(*) FROM cash_movements WHERE company_id = :companyId',
    'SELECT count(*) FROM "Client" WHERE company_id = :companyId',
    'SELECT count(*) FROM suppliers WHERE company_id = :companyId',
    'SELECT count(*) FROM purchase_orders WHERE company_id = :companyId',
    'SELECT count(*) FROM taxes WHERE company_id = :companyId',
    'SELECT count(*) FROM ncf_sequences WHERE company_id = :companyId',
  ],
} as const;
