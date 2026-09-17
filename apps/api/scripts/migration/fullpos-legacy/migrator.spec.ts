/**
 * End-to-end dry-run: reads a real SQLite file (synthetic, generated in a temp folder),
 * transforms it, validates the target snapshot and produces the manifest.
 *
 * Covers required test cases 38 (zero DB writes), 39 (rerun determinism),
 * 40 (missing images do not block) and re-checks the authoritative totals end to end.
 *
 * The tests are skipped when `node:sqlite` is unavailable (Node < 22); the migrator
 * CLI itself requires Node >= 22 in the same way.
 */

import { mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EXPECTED, TARGET_COMPANY_ID, TARGET_COMPANY_NAME, TARGET_WAREHOUSE_ID } from './constants';
import { buildGoldenFixture } from './fixtures';
import { runDryRun } from './migrator';
import { isNodeSqliteAvailable, sha256File } from './source-reader';
import { buildSnapshot } from './test-support';
import type { MigrationInput } from './transform';

type SqliteRunStatement = {
  run(...params: unknown[]): unknown;
};
type SqliteWritable = {
  prepare(sql: string): SqliteRunStatement;
  exec(sql: string): void;
  close(): void;
};

const DDL = `
CREATE TABLE products (
  id INTEGER PRIMARY KEY, code TEXT NOT NULL, name TEXT NOT NULL, category_id INTEGER,
  purchase_price REAL NOT NULL, sale_price REAL NOT NULL, stock REAL NOT NULL, stock_min REAL NOT NULL,
  is_active INTEGER NOT NULL, deleted_at_ms INTEGER, image_path TEXT
);
CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE cash_sessions (
  id INTEGER PRIMARY KEY, user_name TEXT NOT NULL, status TEXT NOT NULL, business_date TEXT,
  opened_at_ms INTEGER NOT NULL, closed_at_ms INTEGER, initial_amount REAL NOT NULL,
  closing_amount REAL, expected_cash REAL, difference REAL
);
CREATE TABLE sales (
  id INTEGER PRIMARY KEY, local_code TEXT NOT NULL, status TEXT NOT NULL, session_id INTEGER,
  subtotal REAL NOT NULL, itbis_amount REAL NOT NULL, total REAL NOT NULL,
  created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
);
CREATE TABLE sale_items (
  id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL, product_id INTEGER,
  product_code_snapshot TEXT NOT NULL, product_name_snapshot TEXT NOT NULL, qty REAL NOT NULL,
  unit_price REAL NOT NULL, purchase_price_snapshot REAL NOT NULL, discount_line REAL NOT NULL,
  total_line REAL NOT NULL, created_at_ms INTEGER NOT NULL
);
`;

function createFixtureDatabase(dir: string, fixture: MigrationInput): string {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { DatabaseSync } = require('node:sqlite') as {
    DatabaseSync: new (path: string) => SqliteWritable;
  };
  const file = join(dir, 'fullpods-fixture.db');
  const db = new DatabaseSync(file);
  db.exec('PRAGMA journal_mode = MEMORY');
  db.exec('PRAGMA synchronous = OFF');
  db.exec(DDL);
  db.exec('BEGIN');

  const productStmt = db.prepare(
    'INSERT INTO products (id, code, name, category_id, purchase_price, sale_price, stock, stock_min, is_active, deleted_at_ms, image_path) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
  );
  for (const product of fixture.products) {
    productStmt.run(
      product.id,
      product.code,
      product.name,
      product.category_id,
      product.purchase_price,
      product.sale_price,
      product.stock,
      product.stock_min,
      product.is_active,
      product.deleted_at_ms,
      product.image_path,
    );
  }

  const categoryStmt = db.prepare('INSERT INTO categories (id, name) VALUES (?,?)');
  for (const category of fixture.categories) categoryStmt.run(category.id, category.name);

  const sessionStmt = db.prepare(
    'INSERT INTO cash_sessions (id, user_name, status, business_date, opened_at_ms, closed_at_ms, initial_amount, closing_amount, expected_cash, difference) VALUES (?,?,?,?,?,?,?,?,?,?)',
  );
  for (const session of fixture.cashSessions) {
    sessionStmt.run(
      session.id,
      session.user_name,
      session.status,
      session.business_date,
      session.opened_at_ms,
      session.closed_at_ms,
      session.initial_amount,
      session.closing_amount,
      session.expected_cash,
      session.difference,
    );
  }

  const saleStmt = db.prepare(
    'INSERT INTO sales (id, local_code, status, session_id, subtotal, itbis_amount, total, created_at_ms, updated_at_ms) VALUES (?,?,?,?,?,?,?,?,?)',
  );
  for (const sale of fixture.sales) {
    saleStmt.run(
      sale.id,
      sale.local_code,
      sale.status,
      sale.session_id,
      sale.subtotal,
      sale.itbis_amount,
      sale.total,
      sale.created_at_ms,
      sale.updated_at_ms,
    );
  }

  const itemStmt = db.prepare(
    'INSERT INTO sale_items (id, sale_id, product_id, product_code_snapshot, product_name_snapshot, qty, unit_price, purchase_price_snapshot, discount_line, total_line, created_at_ms) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
  );
  for (const item of fixture.saleItems) {
    itemStmt.run(
      item.id,
      item.sale_id,
      item.product_id,
      item.product_code_snapshot,
      item.product_name_snapshot,
      item.qty,
      item.unit_price,
      item.purchase_price_snapshot,
      item.discount_line,
      item.total_line,
      item.created_at_ms,
    );
  }

  db.exec('COMMIT');
  db.close();
  return file;
}

const describeWithSqlite = isNodeSqliteAvailable() ? describe : describe.skip;

describeWithSqlite('runDryRun (synthetic SQLite source)', () => {
  let dir: string;
  let dbFile: string;
  let shaBefore: string;
  let listingBefore: string[];

  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), 'fullpos-legacy-'));
    dbFile = createFixtureDatabase(dir, buildGoldenFixture());
    shaBefore = sha256File(dbFile);
    listingBefore = readdirSync(dir).sort();
  });

  afterAll(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it('reconciles to GO with the authoritative totals and writes nothing to the source', async () => {
    const result = await runDryRun({
      sourcePath: dbFile,
      targetSnapshot: buildSnapshot(),
      expectedSha256: shaBefore,
      warehouseId: TARGET_WAREHOUSE_ID,
      generatedAt: '2026-09-16T00:00:00.000Z',
    });

    // 38. the source file and its folder are untouched
    expect(sha256File(dbFile)).toBe(shaBefore);
    expect(readdirSync(dir).sort()).toEqual(listingBefore);

    expect(result.reconciliation.verdict).toBe('GO');
    expect(result.reconciliation.failures).toEqual([]);
    expect(result.source.sha256Matches).toBe(true);
    expect(result.source.integrityCheck).toBe('ok');
    expect(result.source.foreignKeyViolations).toBe(0);
    expect(result.targetValidation.status).toBe('PASSED');

    // authoritative totals (cases 5, 6, 7, 10, 11, 12, 13, 14, 15, 16, 17, 18, 26)
    expect(result.plan.totals.products).toBe(EXPECTED.products);
    expect(result.plan.totals.activeProducts).toBe(EXPECTED.activeProducts);
    expect(result.plan.totals.archivedProducts).toBe(EXPECTED.archivedProducts);
    expect(result.plan.totals.shifts).toBe(EXPECTED.shifts);
    expect(result.plan.totals.sourceRealShifts).toBe(EXPECTED.sourceRealShifts);
    expect(result.plan.totals.shiftsNotImported).toBe(EXPECTED.shiftsNotImported);
    expect(result.plan.totals.salesLinkedToImportedShifts).toBe(EXPECTED.salesLinkedToImportedShifts);
    expect(result.plan.totals.salesWithoutShiftLink).toBe(EXPECTED.salesWithoutShiftLink);
    expect(result.manifest.historicalShiftPolicy.policy).toBe('LATEST_50_REAL_CLOSED');
    expect(result.manifest.historicalShiftPolicy.notImported).toBe(63);
    expect(result.plan.totals.sales).toBe(EXPECTED.sales);
    expect(result.plan.totals.completedSales).toBe(EXPECTED.completedSales);
    expect(result.plan.totals.cancelledSales).toBe(EXPECTED.cancelledSales);
    expect(result.plan.totals.saleItems).toBe(EXPECTED.saleItems);
    expect(result.manifest.totals.openingStock).toBe(EXPECTED.openingStock);
    expect(result.manifest.totals.revenue).toBe(EXPECTED.revenue);
    expect(result.manifest.totals.cost).toBe(EXPECTED.cost);
    expect(result.manifest.totals.profit).toBe(EXPECTED.profit);
    expect(result.manifest.totals.itbis).toBe(EXPECTED.itbis);
    expect(result.manifest.totals.ncf).toBe(EXPECTED.ncf);

    // 40. missing image files must not block the dry-run
    expect(result.plan.totals.imagesPending).toBeGreaterThan(0);
    expect(result.manifest.products.some((product) => product.imageStatus === 'PENDING')).toBe(true);
  });

  it('39. produces identical ids, manifest and hash on a rerun', async () => {
    const first = await runDryRun({
      sourcePath: dbFile,
      targetSnapshot: buildSnapshot(),
      expectedSha256: shaBefore,
      warehouseId: TARGET_WAREHOUSE_ID,
      generatedAt: '2026-09-16T00:00:00.000Z',
    });
    const second = await runDryRun({
      sourcePath: dbFile,
      targetSnapshot: buildSnapshot(),
      expectedSha256: shaBefore,
      warehouseId: TARGET_WAREHOUSE_ID,
      generatedAt: '2026-09-16T00:00:00.000Z',
    });

    expect(second.manifestSha256).toBe(first.manifestSha256);
    expect(second.manifestJson).toBe(first.manifestJson);
    expect(second.plan.sales.map((sale) => sale.targetId)).toEqual(
      first.plan.sales.map((sale) => sale.targetId),
    );
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('marks the run as PARTIAL when the target is not validated', async () => {
    const result = await runDryRun({
      sourcePath: dbFile,
      targetSnapshot: null,
      expectedSha256: shaBefore,
      warehouseId: TARGET_WAREHOUSE_ID,
      generatedAt: '2026-09-16T00:00:00.000Z',
    });
    expect(result.targetValidation.status).toBe('SKIPPED');
    expect(result.reconciliation.verdict).toBe('GO');
  });

  it('aborts on a source hash mismatch (case 34)', async () => {
    await expect(
      runDryRun({
        sourcePath: dbFile,
        targetSnapshot: buildSnapshot(),
        expectedSha256: 'DEADBEEF',
        warehouseId: TARGET_WAREHOUSE_ID,
        generatedAt: '2026-09-16T00:00:00.000Z',
      }),
    ).rejects.toThrow(/SOURCE_HASH_MISMATCH/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('aborts when the target snapshot points to another tenant (case 37)', async () => {
    const snapshot = buildSnapshot();
    snapshot.warehouse = { ...snapshot.warehouse!, companyId: '99999999-9999-4999-8999-999999999999' };
    await expect(
      runDryRun({
        sourcePath: dbFile,
        targetSnapshot: snapshot,
        expectedSha256: shaBefore,
        warehouseId: TARGET_WAREHOUSE_ID,
        generatedAt: '2026-09-16T00:00:00.000Z',
      }),
    ).rejects.toThrow(/TARGET_WAREHOUSE_OTHER_TENANT/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('refuses to execute without the explicit write confirmation (case 41)', async () => {
    const { runExecute } = await import('./migrator');
    await expect(
      runExecute({
        sourcePath: dbFile,
        databaseUrl: 'postgresql://user@127.0.0.1:55432/daleventa_uat_local',
        environment: 'uat',
        targetCompanyId: TARGET_COMPANY_ID,
        targetWarehouseId: TARGET_WAREHOUSE_ID,
        sourceSha256: shaBefore,
        confirmCompanyName: TARGET_COMPANY_NAME,
        confirmWrite: false,
        execute: true,
      }),
    ).rejects.toThrow(/WRITE_NOT_CONFIRMED/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('refuses the production profile without the explicit cutover token (case 42)', async () => {
    const { runExecute } = await import('./migrator');
    await expect(
      runExecute({
        sourcePath: dbFile,
        databaseUrl: 'postgresql://user@127.0.0.1:55432/daleventa_uat_local',
        environment: 'production',
        targetCompanyId: TARGET_COMPANY_ID,
        targetWarehouseId: TARGET_WAREHOUSE_ID,
        sourceSha256: shaBefore,
        confirmCompanyName: TARGET_COMPANY_NAME,
        confirmWrite: true,
        execute: true,
      }),
    ).rejects.toThrow(/PRODUCTION_CUTOVER_NOT_CONFIRMED/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('refuses the production profile on a non-production host before opening a connection (case 42b)', async () => {
    const { runExecute } = await import('./migrator');
    const { productionCutoverConfirmationToken } = await import('./environment-guard');
    await expect(
      runExecute({
        sourcePath: dbFile,
        // correct token, but the destination is not the known production host/database
        databaseUrl: 'postgresql://user@127.0.0.1:55432/daleventa',
        environment: 'production',
        targetCompanyId: TARGET_COMPANY_ID,
        targetWarehouseId: TARGET_WAREHOUSE_ID,
        sourceSha256: shaBefore,
        confirmCompanyName: TARGET_COMPANY_NAME,
        confirmWrite: true,
        productionConfirmationToken: productionCutoverConfirmationToken(),
        execute: true,
      }),
    ).rejects.toThrow(/PRODUCTION_TARGET_NOT_ALLOWED/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('refuses to execute when the confirmed target ids are not the locked ones (case 43)', async () => {
    const { runExecute } = await import('./migrator');
    await expect(
      runExecute({
        sourcePath: dbFile,
        databaseUrl: 'postgresql://user@127.0.0.1:55432/daleventa_uat_local',
        environment: 'uat',
        targetCompanyId: '11111111-1111-4111-8111-111111111111',
        targetWarehouseId: TARGET_WAREHOUSE_ID,
        sourceSha256: shaBefore,
        confirmCompanyName: TARGET_COMPANY_NAME,
        confirmWrite: true,
        execute: true,
      }),
    ).rejects.toThrow(/TARGET_COMPANY_MISMATCH/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('refuses to execute without --execute (case 44)', async () => {
    const { runExecute } = await import('./migrator');
    await expect(
      runExecute({
        sourcePath: dbFile,
        databaseUrl: 'postgresql://user@127.0.0.1:55432/daleventa_uat_local',
        environment: 'uat',
        targetCompanyId: TARGET_COMPANY_ID,
        targetWarehouseId: TARGET_WAREHOUSE_ID,
        sourceSha256: shaBefore,
        confirmCompanyName: TARGET_COMPANY_NAME,
        confirmWrite: true,
        execute: false,
      }),
    ).rejects.toThrow(/EXECUTE_FLAG_REQUIRED/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('refuses to execute against production before opening any connection (case 45)', async () => {
    const { runExecute } = await import('./migrator');
    await expect(
      runExecute({
        sourcePath: dbFile,
        databaseUrl: 'postgresql://user@31.97.99.70:5432/daleventa_pos',
        environment: 'uat',
        targetCompanyId: TARGET_COMPANY_ID,
        targetWarehouseId: TARGET_WAREHOUSE_ID,
        sourceSha256: shaBefore,
        confirmCompanyName: TARGET_COMPANY_NAME,
        confirmWrite: true,
        execute: true,
      }),
    ).rejects.toThrow(/PRODUCTION_FORBIDDEN/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('refuses a non-UAT destination before opening any connection (case 46)', async () => {
    const { runExecute } = await import('./migrator');
    await expect(
      runExecute({
        sourcePath: dbFile,
        databaseUrl: 'postgresql://user@192.168.1.20:5432/daleventa_uat_local',
        environment: 'uat',
        targetCompanyId: TARGET_COMPANY_ID,
        targetWarehouseId: TARGET_WAREHOUSE_ID,
        sourceSha256: shaBefore,
        confirmCompanyName: TARGET_COMPANY_NAME,
        confirmWrite: true,
        execute: true,
      }),
    ).rejects.toThrow(/ENVIRONMENT_NOT_VERIFIED/);
    expect(sha256File(dbFile)).toBe(shaBefore);
  });

  it('exposes a manifest that can be written and re-hashed locally', async () => {
    const result = await runDryRun({
      sourcePath: dbFile,
      targetSnapshot: buildSnapshot(),
      expectedSha256: shaBefore,
      warehouseId: TARGET_WAREHOUSE_ID,
      generatedAt: '2026-09-16T00:00:00.000Z',
    });
    const manifestFile = join(dir, 'manifest.json');
    writeFileSync(manifestFile, result.manifestJson, 'utf8');
    expect(sha256File(manifestFile)).toBe(result.manifestSha256);
    expect(result.manifest.excluded.length).toBe(50 + 5 + 5 + 1);
    expect(result.manifest.stockExceptions).toHaveLength(1);
    expect(result.manifest.notMigrated.length).toBeGreaterThan(0);
  });
});
