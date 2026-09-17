/**
 * PHASE 4 UAT rehearsal (integration).
 *
 * This spec performs REAL writes, so it is skipped unless a disposable local UAT
 * database is explicitly provided:
 *
 *   UAT_DATABASE_URL=postgresql://user@127.0.0.1:55432/daleventa_uat_local
 *   FULLPOS_LEGACY_DB=C:\path\to\fullpods.db        (optional, default fixture path)
 *
 * It proves, against PostgreSQL itself:
 *   import -> idempotency (no-op) -> isolation canary -> surgical rollback -> reimport
 *
 * It never runs against production: `runExecute`/`runRollback` pass through the same
 * environment guard (protected database names, loopback only, live metadata check).
 */

import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { PrismaClient } from '@prisma/client';
import {
  EXPECTED,
  EXPECTED_SOURCE_SHA256,
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_WAREHOUSE_ID,
} from '../constants';
import { describeDatabaseUrl, parseDatabaseUrl } from '../environment-guard';
import { runExecute, runRollback, runVerify, runVerifyPreflight } from '../migrator';
import { readTargetState } from '../writer';
import { readDecoyState, seedUatFoundation, UAT_DECOY } from './uat-foundation';

const UAT_DATABASE_URL = process.env.UAT_DATABASE_URL ?? '';
const SOURCE_PATH =
  process.env.FULLPOS_LEGACY_DB ?? join(process.env.USERPROFILE ?? '', 'Documents', 'fullpods.db');

const enabled = UAT_DATABASE_URL.length > 0 && existsSync(SOURCE_PATH);
const maybe = enabled ? describe : describe.skip;

const EXECUTE_OPTIONS = {
  sourcePath: SOURCE_PATH,
  databaseUrl: UAT_DATABASE_URL,
  environment: 'uat',
  targetCompanyId: TARGET_COMPANY_ID,
  targetWarehouseId: TARGET_WAREHOUSE_ID,
  sourceSha256: EXPECTED_SOURCE_SHA256,
  confirmCompanyName: TARGET_COMPANY_NAME,
  confirmWrite: true,
  execute: true,
} as const;

maybe('PHASE 4 rehearsal against a disposable UAT database', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });

  beforeAll(async () => {
    // Guard: never point this spec at anything but a local, disposable database.
    const parsed = parseDatabaseUrl(UAT_DATABASE_URL);
    expect(parsed.isLoopback).toBe(true);
    expect(parsed.isProtectedDatabase).toBe(false);
    expect(parsed.isProtectedHost).toBe(false);
    await seedUatFoundation(prisma, { includeDecoy: true });
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it(
    'imports the whole profile without FK/constraint/Decimal failures',
    async () => {
      const result = await runExecute({ ...EXECUTE_OPTIONS });
      expect(['IMPORTED', 'ALREADY_APPLIED']).toContain(result.verdict);
      expect(result.reconciliation.verdict).toBe('GO');
      expect(result.reconciliation.failures).toEqual([]);
      expect(result.environment.classification).toBe('uat');

      const state = await readTargetState(prisma, TARGET_COMPANY_ID);
      expect(state.products).toBe(EXPECTED.products);
      expect(state.activeProducts).toBe(EXPECTED.activeProducts);
      expect(state.archivedProducts).toBe(EXPECTED.archivedProducts);
      expect(state.warehouseStocks).toBe(EXPECTED.activeProducts);
      expect(state.shifts).toBe(EXPECTED.shifts);
      expect(state.sales).toBe(EXPECTED.sales);
      expect(state.saleItems).toBe(EXPECTED.saleItems);
      expect(state.openShifts).toBe(0);
      console.log(`UAT rehearsal: ${result.verdict} en ${result.durationMs} ms (${describeDatabaseUrl(UAT_DATABASE_URL)})`);
    },
    180_000,
  );

  it(
    'is idempotent: a second run is a clean no-op',
    async () => {
      const before = await readTargetState(prisma, TARGET_COMPANY_ID);
      const result = await runExecute({ ...EXECUTE_OPTIONS });
      expect(result.verdict).toBe('ALREADY_APPLIED');
      expect(result.counts).toEqual({
        products: 0,
        warehouseStocks: 0,
        shifts: 0,
        sales: 0,
        saleItems: 0,
      });
      const after = await readTargetState(prisma, TARGET_COMPANY_ID);
      expect(after).toEqual(before);
    },
    180_000,
  );

  it(
    'verifies the imported state read-only without changing a single row',
    async () => {
      const before = await readTargetState(prisma, TARGET_COMPANY_ID);
      const result = await runVerify({ ...EXECUTE_OPTIONS });
      expect(result.verdict).toBe('GO');
      expect(result.reconciliation.verdict).toBe('GO');
      expect(result.reconciliation.failures).toEqual([]);
      expect(result.state.products).toBe(EXPECTED.products);
      expect(result.state.sales).toBe(EXPECTED.sales);
      expect(result.state.saleItems).toBe(EXPECTED.saleItems);
      expect(result.otherTenants.companies).toBe(2);
      expect(result.otherTenants.productsByOtherTenants).toBe(1);
      expect(await readTargetState(prisma, TARGET_COMPANY_ID)).toEqual(before);
    },
    180_000,
  );

  it('never touches another tenant (isolation canary)', async () => {
    const decoy = await readDecoyState(prisma);
    expect(decoy.products).toBe(1);
    expect(decoy.warehouseStocks).toBe(1);
    expect(decoy.cashSessions).toBe(1);
    expect(decoy.sales).toBe(1);
    expect(decoy.saleItems).toBe(1);
  });

  it(
    'rolls back surgically, restoring the clean baseline and keeping the other tenant intact',
    async () => {
      const result = await runRollback({ ...EXECUTE_OPTIONS });
      expect(result.deleted.products).toBe(EXPECTED.products);
      expect(result.deleted.warehouseStocks).toBe(EXPECTED.activeProducts);
      expect(result.deleted.shifts).toBe(EXPECTED.shifts);
      expect(result.deleted.sales).toBe(EXPECTED.sales);
      expect(result.deleted.saleItems).toBe(EXPECTED.saleItems);

      const state = await readTargetState(prisma, TARGET_COMPANY_ID);
      expect(state.products).toBe(0);
      expect(state.warehouseStocks).toBe(0);
      expect(state.shifts).toBe(0);
      expect(state.sales).toBe(0);
      expect(state.saleItems).toBe(0);
      expect(state.inventoryMovements).toBe(0);

      // The decoy tenant and the foundation rows must survive the rollback.
      const decoy = await readDecoyState(prisma);
      expect(decoy.products).toBe(1);
      expect(decoy.sales).toBe(1);
      expect(decoy.companies).toBe(2);
      expect(await prisma.user.count({ where: { id: UAT_DECOY.userId } })).toBe(1);
      expect(await prisma.company.count({ where: { id: TARGET_COMPANY_ID } })).toBe(1);
    },
    180_000,
  );

  it(
    'pre-cutover preflight passes on the clean baseline without changing a row',
    async () => {
      // Runs right after the rollback test, so the tenant is on the clean pre-cutover baseline.
      const before = await readTargetState(prisma, TARGET_COMPANY_ID);
      const preflight = await runVerifyPreflight({ ...EXECUTE_OPTIONS });

      expect(preflight.verdict).toBe('GO');
      expect(preflight.failures).toEqual([]);
      expect(preflight.classification).toBe('FRESH');
      expect(preflight.baseline.products).toBe(0);
      expect(preflight.baseline.sales).toBe(0);
      expect(preflight.license.isUsable).toBe(true);
      expect(preflight.license.maxProducts).toBeGreaterThanOrEqual(EXPECTED.activeProducts);
      expect(preflight.source.sha256.toUpperCase()).toBe(EXPECTED_SOURCE_SHA256);
      expect(preflight.checks.every((check) => check.ok)).toBe(true);
      expect(await readTargetState(prisma, TARGET_COMPANY_ID)).toEqual(before);
    },
    180_000,
  );

  it(
    'preflight aborts when the target company id is not the locked one',
    async () => {
      await expect(
        runVerifyPreflight({
          ...EXECUTE_OPTIONS,
          targetCompanyId: '11111111-1111-4111-8111-111111111111',
        }),
      ).rejects.toThrow(/TARGET_COMPANY_MISMATCH/);
    },
    60_000,
  );

  it(
    'reimports cleanly after a rollback (repeatable cutover)',
    async () => {
      const result = await runExecute({ ...EXECUTE_OPTIONS });
      expect(result.verdict).toBe('IMPORTED');
      expect(result.reconciliation.verdict).toBe('GO');
      const state = await readTargetState(prisma, TARGET_COMPANY_ID);
      expect(state.sales).toBe(EXPECTED.sales);
      expect(state.saleItems).toBe(EXPECTED.saleItems);
    },
    180_000,
  );
});
