/**
 * Read-only reader for the legacy FullPOS SQLite database.
 *
 * Safety:
 *  - the database is opened with `readOnly: true`
 *  - `PRAGMA query_only = 1` is applied immediately
 *  - only SELECT statements are issued (no PRAGMA that writes, no VACUUM, no journal switch)
 *  - the SHA256 of the file is verified before any row is read
 *
 * `node:sqlite` is loaded lazily so that environments without it (Node < 22) can still
 * import this module; only an actual open fails.
 */

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { MigrationAbortError } from './errors';
import type {
  LegacyCashSession,
  LegacyCategory,
  LegacyProduct,
  LegacySale,
  LegacySaleItem,
} from './types';

type SqliteStatement = {
  all(...params: unknown[]): unknown[];
  get(...params: unknown[]): unknown;
};

type SqliteDatabase = {
  prepare(sql: string): SqliteStatement;
  exec(sql: string): void;
  close(): void;
};

type SqliteModule = {
  DatabaseSync: new (path: string, options?: { readOnly?: boolean }) => SqliteDatabase;
};

export function isNodeSqliteAvailable(): boolean {
  try {
    loadNodeSqlite();
    return true;
  } catch {
    return false;
  }
}

function loadNodeSqlite(): SqliteModule {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const module = require('node:sqlite') as SqliteModule;
  if (!module || typeof module.DatabaseSync !== 'function') {
    throw new Error('node:sqlite no está disponible en este runtime');
  }
  return module;
}

export function sha256File(filePath: string): string {
  const hash = createHash('sha256');
  hash.update(readFileSync(filePath));
  return hash.digest('hex').toUpperCase();
}

export class LegacySource {
  private constructor(
    private readonly db: SqliteDatabase,
    readonly path: string,
    readonly sha256: string,
  ) {}

  static open(filePath: string): LegacySource {
    const { DatabaseSync } = loadNodeSqlite();
    let db: SqliteDatabase;
    try {
      db = new DatabaseSync(filePath, { readOnly: true });
    } catch (error) {
      throw new MigrationAbortError('SOURCE_OPEN_FAILED', 'No se pudo abrir la base legacy en modo solo lectura', {
        path: filePath,
        cause: error instanceof Error ? error.message : String(error),
      });
    }
    db.exec('PRAGMA query_only = 1');
    const sha256 = sha256File(filePath);
    return new LegacySource(db, filePath, sha256);
  }

  /** Read-only integrity metadata (never repairs anything). */
  integrity(): { integrityCheck: string; foreignKeyViolations: number; userVersion: number; queryOnly: number } {
    const integrityRow = this.db.prepare('PRAGMA integrity_check').get() as Record<string, unknown> | undefined;
    const integrityCheck = integrityRow ? String(Object.values(integrityRow)[0]) : 'unknown';
    const fkViolations = this.db.prepare('PRAGMA foreign_key_check').all() as unknown[];
    const userVersionRow = this.db.prepare('PRAGMA user_version').get() as Record<string, unknown> | undefined;
    const queryOnlyRow = this.db.prepare('PRAGMA query_only').get() as Record<string, unknown> | undefined;
    return {
      integrityCheck,
      foreignKeyViolations: fkViolations.length,
      userVersion: userVersionRow ? Number(Object.values(userVersionRow)[0]) : -1,
      queryOnly: queryOnlyRow ? Number(Object.values(queryOnlyRow)[0]) : -1,
    };
  }

  products(): LegacyProduct[] {
    return this.db
      .prepare(
        `SELECT id, code, name, category_id, purchase_price, sale_price, stock, stock_min,
                is_active, deleted_at_ms, image_path
           FROM products
          ORDER BY id`,
      )
      .all() as LegacyProduct[];
  }

  categories(): LegacyCategory[] {
    return this.db
      .prepare('SELECT id, name FROM categories ORDER BY id')
      .all() as LegacyCategory[];
  }

  cashSessions(): LegacyCashSession[] {
    return this.db
      .prepare(
        `SELECT id, user_name, status, business_date, opened_at_ms, closed_at_ms,
                initial_amount, closing_amount, expected_cash, difference
           FROM cash_sessions
          ORDER BY id`,
      )
      .all() as LegacyCashSession[];
  }

  sales(): LegacySale[] {
    return this.db
      .prepare(
        `SELECT id, local_code, status, session_id, subtotal, itbis_amount, total,
                created_at_ms, updated_at_ms
           FROM sales
          ORDER BY id`,
      )
      .all() as LegacySale[];
  }

  saleItems(): LegacySaleItem[] {
    return this.db
      .prepare(
        `SELECT id, sale_id, product_id, product_code_snapshot, product_name_snapshot,
                qty, unit_price, purchase_price_snapshot, discount_line, total_line, created_at_ms
           FROM sale_items
          ORDER BY id`,
      )
      .all() as LegacySaleItem[];
  }

  /** Every table of the source, used only for the report inventory. */
  tableCounts(): Array<{ table: string; rows: number }> {
    const tables = this.db
      .prepare(
        `SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name`,
      )
      .all() as Array<{ name: string }>;
    return tables.map((row) => ({
      table: row.name,
      rows: Number(
        Object.values(
          this.db.prepare(`SELECT count(*) AS c FROM "${row.name}"`).get() as Record<string, unknown>,
        )[0],
      ),
    }));
  }

  close(): void {
    this.db.close();
  }
}
