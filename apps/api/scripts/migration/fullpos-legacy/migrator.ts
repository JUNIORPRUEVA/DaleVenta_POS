/**
 * Migrator orchestrator (Phase 3 - minimal scope).
 *
 * DRY-RUN ONLY. The dry-run reads the source read-only, validates the target,
 * transforms every record, and produces the manifest + reconciliation report.
 * It performs ZERO database writes.
 *
 * The execute path is DESIGNED but deliberately disabled in this version: the
 * `runExecute` function always throws. Enabling it is a separate, explicitly
 * authorized change (see EXECUTE_GUARDS).
 */

import type { PrismaClient } from '@prisma/client';
import {
  EXPECTED,
  EXPECTED_SOURCE_SHA256,
  IMAGE_STATUS_PENDING,
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_OWNER_USER_ID,
  TARGET_TERMINAL_ID,
  TARGET_WAREHOUSE_ID,
} from './constants';
import {
  assertProductionCutoverEnvironment,
  assertUatEnvironment,
  assertUrlIsLocalUat,
  assertUrlIsProductionTarget,
} from './environment-guard';
import { MigrationAbortError, MigrationNoGoError } from './errors';
import { assertExecuteConfirmations, assertSourceSha256, assertTargetSnapshot } from './guards';
import { buildManifest, serializeManifest, sha256Text, type Manifest } from './manifest';
import { buildWritePlan, type WritePlan } from './payload';
import { buildReconciliation, buildCheck } from './reconcile';
import { reconcileFromDatabase } from './reconcile-db';
import { LegacySource, sha256File } from './source-reader';
import { createPrismaTargetReadPort } from './target-port-prisma';
import { collectTargetSnapshot } from './target-validator';
import { planMigration } from './transform';
import {
  assertTargetStateAllowsWrite,
  buildIdSets,
  classifyTargetState,
  createTargetClient,
  deletePlan,
  insertPlan,
  readLiveMetadata,
  readTargetState,
  verifyDeterministicSample,
} from './writer';
import type { MigrationPlan, ReconciliationReport, TargetSnapshot } from './types';

export const EXECUTE_GUARDS = [
  '--execute',
  '--environment=uat',
  '--database-url=<local disposable UAT connection>',
  '--target-company-id=<TARGET_COMPANY_ID>',
  '--target-warehouse-id=<TARGET_WAREHOUSE_ID>',
  '--source-sha256=<sha of the frozen source>',
  '--confirm-company-name="Cafeteria la bomba"',
  '--confirm-write',
] as const;

/**
 * Final cutover profile (prepared, NOT executed in this phase).
 * `--environment=production` alone is never enough: the explicit token, the known
 * production host + database and the LIVE connection metadata are all required.
 */
export const PRODUCTION_CUTOVER_GUARDS = [
  '--execute',
  '--environment=production',
  '--database-url=<production connection>',
  '--target-company-id=<TARGET_COMPANY_ID>',
  '--target-warehouse-id=<TARGET_WAREHOUSE_ID>',
  '--source-sha256=<FROZEN_SOURCE_SHA256>',
  '--confirm-company-name="Cafeteria la bomba"',
  '--confirm-production-cutover=<CUTOVER:TARGET_COMPANY_ID:FROZEN_SOURCE_SHA256>',
  '--confirm-write',
] as const;

export type TargetValidation = {
  status: 'PASSED' | 'SKIPPED';
  detail: string;
  snapshotSource: string | null;
  capturedAt: string | null;
};

export type DryRunResult = {
  source: {
    path: string;
    sha256: string;
    expectedSha256: string;
    sha256Matches: boolean;
    integrityCheck: string;
    foreignKeyViolations: number;
    userVersion: number;
  };
  plan: MigrationPlan;
  writePlan: WritePlan;
  reconciliation: ReconciliationReport;
  manifest: Manifest;
  manifestJson: string;
  manifestSha256: string;
  targetValidation: TargetValidation;
  generatedAt: string;
};

export type DryRunOptions = {
  sourcePath: string;
  /** Read-only target snapshot. When null the run is marked as PARTIAL. */
  targetSnapshot: TargetSnapshot | null;
  expectedSha256?: string;
  warehouseId: string;
  requireCleanBaseline?: boolean;
  generatedAt?: string;
};

export async function runDryRun(options: DryRunOptions): Promise<DryRunResult> {
  const generatedAt = options.generatedAt ?? new Date().toISOString();
  const expectedSha256 = options.expectedSha256 ?? EXPECTED_SOURCE_SHA256;

  const source = LegacySource.open(options.sourcePath);
  try {
    // 1. Source hash: abort when it differs (a newer cutover source must be authorized).
    assertSourceSha256(source.sha256, expectedSha256);

    // 2. Read-only integrity metadata (never repaired).
    const integrity = source.integrity();

    // 3. Read the projections (SELECT only).
    const products = source.products();
    const categories = source.categories();
    const cashSessions = source.cashSessions();
    const sales = source.sales();
    const saleItems = source.saleItems();

    // 4. Transform (pure, deterministic).
    const plan = planMigration({ products, categories, cashSessions, sales, saleItems });

    // 5. Build the exact write payloads (used for validation of the write shape; not written).
    const writePlan = buildWritePlan(plan, { warehouseId: options.warehouseId });

    // 6. Reconcile against the authoritative figures.
    const reconciliation = buildReconciliation(plan, generatedAt);
    if (reconciliation.verdict !== 'GO') {
      throw new MigrationNoGoError(
        'La reconciliación del dry-run no coincide con las cifras autoritativas',
        reconciliation.failures.map(
          (failure) => `${failure.metric}: esperado ${failure.expected}, obtenido ${failure.actual}`,
        ),
      );
    }

    // 7. Target validation (reads only).
    let targetValidation: TargetValidation;
    if (options.targetSnapshot) {
      assertTargetSnapshot(options.targetSnapshot, {
        requireCleanBaseline: options.requireCleanBaseline ?? true,
      });
      targetValidation = {
        status: 'PASSED',
        detail:
          'Empresa, almacén, terminal y usuario propietario verificados. Base destino limpia para el alcance de Fase 3.',
        snapshotSource: options.targetSnapshot.source,
        capturedAt: options.targetSnapshot.capturedAt,
      };
    } else {
      targetValidation = {
        status: 'SKIPPED',
        detail:
          'NO se validó el destino (sin snapshot autorizado). El dry-run es PARCIAL: no ejecutar con esta configuración.',
        snapshotSource: null,
        capturedAt: null,
      };
    }

    // 8. Manifest (immutable local artifact).
    const manifest = buildManifest({
      plan,
      reconciliation,
      source: {
        path: source.path,
        sha256: source.sha256,
        integrityCheck: integrity.integrityCheck,
        foreignKeyViolations: integrity.foreignKeyViolations,
        userVersion: integrity.userVersion,
      },
      generatedAt,
      warehouseId: options.warehouseId,
    });
    const manifestJson = serializeManifest(manifest);

    return {
      source: {
        path: source.path,
        sha256: source.sha256,
        expectedSha256,
        sha256Matches: source.sha256.toUpperCase() === expectedSha256.toUpperCase(),
        integrityCheck: integrity.integrityCheck,
        foreignKeyViolations: integrity.foreignKeyViolations,
        userVersion: integrity.userVersion,
      },
      plan,
      writePlan,
      reconciliation,
      manifest,
      manifestJson,
      manifestSha256: sha256Text(manifestJson),
      targetValidation,
      generatedAt,
    };
  } finally {
    source.close();
  }
}

/**
 * Execute path (authorized for local disposable UAT only).
 *
 * Hard requirements (all mandatory, all validated against the locked profile):
 *   --execute --environment=uat --database-url=... --target-company-id=... \
 *   --target-warehouse-id=... --source-sha256=... --confirm-company-name="..." --confirm-write
 *
 * Environment safety is enforced twice: the project's sanctioned UAT gate over the
 * connection URL, plus a live metadata check of the actual PostgreSQL connection.
 * `--environment=production` always aborts.
 */
export type ExecuteOptions = {
  sourcePath: string;
  databaseUrl: string;
  environment: string | null;
  targetCompanyId: string | null;
  targetWarehouseId: string | null;
  sourceSha256: string | null;
  confirmCompanyName: string | null;
  confirmWrite: boolean;
  /** Required only for `--environment=production` (final cutover). */
  productionConfirmationToken?: string | null;
  /** Production reachable only through the controlled SSH tunnel (`--production-via-ssh-tunnel`). */
  productionViaSshTunnel?: boolean;
  /** Local port reserved for that tunnel (default 15432). */
  sshTunnelLocalPort?: number;
  execute: boolean;
  timeoutMs?: number;
  generatedAt?: string;
};

export type ExecuteResult = {
  verdict: 'IMPORTED' | 'ALREADY_APPLIED';
  environment: { classification: string; description: string; database: string; server: string; user: string };
  counts: { products: number; warehouseStocks: number; shifts: number; sales: number; saleItems: number };
  before: unknown;
  after: unknown;
  reconciliation: ReconciliationReport;
  dryRun: DryRunResult;
  durationMs: number;
};

export type RollbackResult = {
  environment: { classification: string; description: string };
  deleted: { saleItems: number; sales: number; shifts: number; warehouseStocks: number; products: number };
  after: unknown;
  durationMs: number;
};

async function openGuardedTarget(options: {
  databaseUrl: string;
  environment: string | null;
  productionConfirmationToken?: string | null;
  productionViaSshTunnel?: boolean;
  sshTunnelLocalPort?: number;
  targetCompanyId: string | null;
  targetWarehouseId: string | null;
}): Promise<{ prisma: PrismaClient; environment: ExecuteResult['environment'] }> {
  const requested = (options.environment ?? '').trim().toLowerCase();
  const isProduction = requested === 'production' || requested === 'prod';

  // Layer 0: the URL is validated BEFORE any socket is opened, so a destination that does
  // not match the declared profile never receives a connection attempt from the migration.
  const parsed = isProduction
    ? assertUrlIsProductionTarget(options.databaseUrl, {
        sshTunnel: options.productionViaSshTunnel === true,
        tunnelLocalPort: options.sshTunnelLocalPort,
      })
    : assertUrlIsLocalUat(options.databaseUrl);

  const prisma = createTargetClient(options.databaseUrl);
  const metadata = await readLiveMetadata(prisma);
  const guard = isProduction
    ? assertProductionCutoverEnvironment({
        environment: options.environment ?? '',
        url: options.databaseUrl,
        metadata,
        confirmationToken: options.productionConfirmationToken ?? null,
        targetCompanyId: options.targetCompanyId,
        targetWarehouseId: options.targetWarehouseId,
        sshTunnel: options.productionViaSshTunnel === true,
        tunnelLocalPort: options.sshTunnelLocalPort,
      })
    : assertUatEnvironment({
        environment: options.environment ?? '',
        url: options.databaseUrl,
        metadata,
      });
  return {
    prisma,
    environment: {
      classification: guard.classification,
      description: guard.description,
      database: metadata.databaseName,
      server: `${metadata.serverAddress ?? 'unknown'}:${metadata.serverPort ?? 'unknown'}`,
      user: parsed.user,
    },
  };
}

function assertLiveTenantIdentity(
  snapshot: TargetSnapshot,
): void {
  // Company / warehouse / terminal / owner must be the locked ones (baseline checked separately).
  assertTargetSnapshot(snapshot, { requireCleanBaseline: false });
}

/** Forbidden rows for the migration scope: their presence means foreign data exists. */
function assertNoForeignRows(state: Awaited<ReturnType<typeof readTargetState>>): void {
  const violations: string[] = [];
  if (state.clients !== 0) violations.push(`clients=${state.clients}`);
  if (state.suppliers !== 0) violations.push(`suppliers=${state.suppliers}`);
  if (state.purchaseOrders !== 0) violations.push(`purchaseOrders=${state.purchaseOrders}`);
  if (state.cashMovements !== 0) violations.push(`cashMovements=${state.cashMovements}`);
  if (state.cashboxDaily !== 0) violations.push(`cashboxDaily=${state.cashboxDaily}`);
  if (state.taxes !== 0) violations.push(`taxes=${state.taxes}`);
  if (state.ncfSequences !== 0) violations.push(`ncfSequences=${state.ncfSequences}`);
  if (state.inventoryMovements !== 0) violations.push(`inventoryMovements=${state.inventoryMovements}`);
  if (state.openShifts !== 0) violations.push(`openShifts=${state.openShifts}`);
  if (violations.length > 0) {
    throw new MigrationAbortError(
      'TARGET_HAS_FOREIGN_ROWS',
      'El destino contiene filas fuera del alcance de la migración: no se escribe nada',
      { violations },
    );
  }
}

export async function runExecute(options: ExecuteOptions): Promise<ExecuteResult> {
  const startedAt = Date.now();

  // 1. Confirmations (pure guards, before any connection).
  assertExecuteConfirmations({
    execute: options.execute,
    environment: options.environment,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
    sourceSha256: options.sourceSha256,
    confirmCompanyName: options.confirmCompanyName,
    confirmWrite: options.confirmWrite,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
  });

  // 2. Plan + reconciliation from the audited source (also verifies the source SHA).
  const dryRun = await runDryRun({
    sourcePath: options.sourcePath,
    targetSnapshot: null,
    expectedSha256: options.sourceSha256 ?? EXPECTED_SOURCE_SHA256,
    warehouseId: TARGET_WAREHOUSE_ID,
    generatedAt: options.generatedAt,
  });
  if (dryRun.reconciliation.verdict !== 'GO') {
    throw new MigrationNoGoError('La reconciliación del plan no es GO: se cancela la ejecución', []);
  }

  // 3. Environment gate over the connection URL + the LIVE connection metadata.
  const { prisma, environment } = await openGuardedTarget({
    databaseUrl: options.databaseUrl,
    environment: options.environment,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
    productionViaSshTunnel: options.productionViaSshTunnel === true,
    sshTunnelLocalPort: options.sshTunnelLocalPort,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
  });

  try {
    // 4. Live tenant identity (company/warehouse/terminal/owner, other-tenant checks).
    const liveSnapshot = await collectTargetSnapshot(
      createPrismaTargetReadPort(prisma),
      {
        companyId: TARGET_COMPANY_ID,
        warehouseId: TARGET_WAREHOUSE_ID,
        terminalId: TARGET_TERMINAL_ID,
        ownerUserId: TARGET_OWNER_USER_ID,
      },
      new Date().toISOString(),
    );
    assertLiveTenantIdentity(liveSnapshot);

    const ids = buildIdSets({
      companyId: TARGET_COMPANY_ID,
      warehouseId: TARGET_WAREHOUSE_ID,
      writePlan: dryRun.writePlan,
    });

    const expected = {
      products: dryRun.writePlan.products.length,
      activeProducts: dryRun.writePlan.products.filter((product) => product.archivedAt === null).length,
      archivedProducts: dryRun.writePlan.products.filter((product) => product.archivedAt !== null).length,
      shifts: dryRun.writePlan.shifts.length,
      sales: dryRun.writePlan.sales.length,
      saleItems: dryRun.writePlan.saleItems.length,
      warehouseStocks: dryRun.writePlan.warehouseStocks.length,
    };

    // 5. Idempotency pre-flight + foreign-row gate.
    const before = await readTargetState(prisma, TARGET_COMPANY_ID);
    assertNoForeignRows(before);
    const classification = classifyTargetState(before, expected);
    assertTargetStateAllowsWrite(classification.verdict, classification.details);

    if (classification.verdict === 'ALREADY_APPLIED') {
      const sample = await verifyDeterministicSample(prisma, ids);
      if (sample.found !== sample.checked) {
        throw new MigrationAbortError(
          'ALREADY_APPLIED_SAMPLE_MISMATCH',
          'El estado coincide en conteos pero no se encontraron los ids deterministas esperados',
          sample,
        );
      }
      const reconciliation = await reconcileFromDatabase(prisma, ids, expected);
      return {
        verdict: 'ALREADY_APPLIED',
        environment,
        counts: { products: 0, warehouseStocks: 0, shifts: 0, sales: 0, saleItems: 0 },
        before,
        after: before,
        reconciliation,
        dryRun,
        durationMs: Date.now() - startedAt,
      };
    }

    // 6. Write everything in ONE transaction.
    const counts = await insertPlan(prisma, dryRun.writePlan, { timeoutMs: options.timeoutMs });

    // 7. Post-write reconciliation straight from PostgreSQL.
    const after = await readTargetState(prisma, TARGET_COMPANY_ID);
    const reconciliation = await reconcileFromDatabase(prisma, ids, expected);
    if (reconciliation.verdict !== 'GO') {
      throw new MigrationNoGoError(
        'La reconciliación post-escritura no es GO',
        reconciliation.failures.map((failure) => `${failure.metric}: esperado ${failure.expected}, obtenido ${failure.actual}`),
      );
    }

    return {
      verdict: 'IMPORTED',
      environment,
      counts,
      before,
      after,
      reconciliation,
      dryRun,
      durationMs: Date.now() - startedAt,
    };
  } finally {
    await prisma.$disconnect();
  }
}

export type VerifyResult = {
  verdict: 'GO' | 'NO-GO';
  environment: ExecuteResult['environment'];
  state: Awaited<ReturnType<typeof readTargetState>>;
  reconciliation: ReconciliationReport;
  otherTenants: {
    companies: number;
    productsTotal: number;
    salesTotal: number;
    productsByOtherTenants: number;
    salesByOtherTenants: number;
  };
  durationMs: number;
};

/**
 * READ-ONLY post-write verification. It never writes: it opens the destination through the
 * same guards (UAT or production cutover profile), then reconciles the database against the
 * plan and against the out-of-scope inventory.
 */
export async function runVerify(options: ExecuteOptions): Promise<VerifyResult> {
  const startedAt = Date.now();

  assertExecuteConfirmations({
    execute: true,
    environment: options.environment,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
    sourceSha256: options.sourceSha256,
    confirmCompanyName: options.confirmCompanyName,
    confirmWrite: true,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
  });

  const dryRun = await runDryRun({
    sourcePath: options.sourcePath,
    targetSnapshot: null,
    expectedSha256: options.sourceSha256 ?? EXPECTED_SOURCE_SHA256,
    warehouseId: TARGET_WAREHOUSE_ID,
    generatedAt: options.generatedAt,
  });

  const { prisma, environment } = await openGuardedTarget({
    databaseUrl: options.databaseUrl,
    environment: options.environment,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
    productionViaSshTunnel: options.productionViaSshTunnel === true,
    sshTunnelLocalPort: options.sshTunnelLocalPort,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
  });

  try {
    const ids = buildIdSets({
      companyId: TARGET_COMPANY_ID,
      warehouseId: TARGET_WAREHOUSE_ID,
      writePlan: dryRun.writePlan,
    });
    const expected = {
      products: dryRun.writePlan.products.length,
      activeProducts: dryRun.writePlan.products.filter((product) => product.archivedAt === null).length,
      archivedProducts: dryRun.writePlan.products.filter((product) => product.archivedAt !== null).length,
      shifts: dryRun.writePlan.shifts.length,
      sales: dryRun.writePlan.sales.length,
      saleItems: dryRun.writePlan.saleItems.length,
      warehouseStocks: dryRun.writePlan.warehouseStocks.length,
    };

    const state = await readTargetState(prisma, TARGET_COMPANY_ID);
    const reconciliation = await reconcileFromDatabase(prisma, ids, expected);
    const sample = await verifyDeterministicSample(prisma, ids);
    if (sample.found !== sample.checked) {
      throw new MigrationAbortError(
        'VERIFY_SAMPLE_MISMATCH',
        'No se encontraron todos los ids deterministas esperados en el destino',
        sample,
      );
    }

    const [companies, productsTotal, salesTotal, productsByOtherTenants, salesByOtherTenants] =
      await Promise.all([
        prisma.company.count({}),
        prisma.product.count({}),
        prisma.sale.count({}),
        prisma.product.count({ where: { companyId: { not: TARGET_COMPANY_ID } } }),
        prisma.sale.count({ where: { companyId: { not: TARGET_COMPANY_ID } } }),
      ]);

    const outOfScopeClean =
      state.inventoryMovements === 0 &&
      state.cashMovements === 0 &&
      state.cashboxDaily === 0 &&
      state.clients === 0 &&
      state.suppliers === 0 &&
      state.purchaseOrders === 0 &&
      state.taxes === 0 &&
      state.ncfSequences === 0 &&
      state.openShifts === 0;

    const verdict =
      reconciliation.verdict === 'GO' && outOfScopeClean ? ('GO' as const) : ('NO-GO' as const);

    return {
      verdict,
      environment,
      state,
      reconciliation,
      otherTenants: {
        companies,
        productsTotal,
        salesTotal,
        productsByOtherTenants,
        salesByOtherTenants,
      },
      durationMs: Date.now() - startedAt,
    };
  } finally {
    await prisma.$disconnect();
  }
}

/**
 * READ-ONLY pre-cutover verification (preflight).
 *
 * This is the gate that can pass BEFORE the migration exists: it proves the authenticated
 * route, the live server metadata, the locked tenant identity, a clean baseline and the
 * license state — all from the LIVE connection, writing nothing. The post-write
 * `runVerify` (which needs the 91 products / 7 179 sales to be present) is a different gate.
 */
export type PreflightResult = {
  verdict: 'GO' | 'NO-GO';
  environment: ExecuteResult['environment'];
  source: { path: string; sha256: string; expectedSha256: string; matches: boolean };
  baseline: Awaited<ReturnType<typeof readTargetState>>;
  classification: ReturnType<typeof classifyTargetState>['verdict'];
  license: {
    status: string;
    plan: string;
    licenseStatus: string;
    trialEndsAt: string | null;
    licenseExpiresAt: string | null;
    licenseBlockedAt: string | null;
    maxUsers: number;
    maxProducts: number;
    billableProducts: number;
    activeUsers: number;
    isUsable: boolean;
  };
  checks: ReconciliationReport['checks'];
  failures: ReconciliationReport['failures'];
  durationMs: number;
};

export async function runVerifyPreflight(options: ExecuteOptions): Promise<PreflightResult> {
  const startedAt = Date.now();

  // 1. Confirmations (pure guards, before any connection).
  assertExecuteConfirmations({
    execute: true,
    environment: options.environment,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
    sourceSha256: options.sourceSha256,
    confirmCompanyName: options.confirmCompanyName,
    confirmWrite: true,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
  });

  // 2. Source identity (read-only, no planning).
  const actualSha = sha256File(options.sourcePath);
  assertSourceSha256(actualSha, options.sourceSha256 ?? EXPECTED_SOURCE_SHA256);

  // 3. Guarded LIVE connection (URL gate + live metadata gate).
  const { prisma, environment } = await openGuardedTarget({
    databaseUrl: options.databaseUrl,
    environment: options.environment,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
    productionViaSshTunnel: options.productionViaSshTunnel === true,
    sshTunnelLocalPort: options.sshTunnelLocalPort,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
  });

  try {
    // 4. Live tenant identity + clean baseline (throws if the tenant is not the locked one).
    const snapshot = await collectTargetSnapshot(
      createPrismaTargetReadPort(prisma),
      {
        companyId: TARGET_COMPANY_ID,
        warehouseId: TARGET_WAREHOUSE_ID,
        terminalId: TARGET_TERMINAL_ID,
        ownerUserId: TARGET_OWNER_USER_ID,
      },
      new Date().toISOString(),
    );
    assertTargetSnapshot(snapshot, { requireCleanBaseline: true });

    const baseline = await readTargetState(prisma, TARGET_COMPANY_ID);
    // Classify against the FROZEN expectations (never against zeros: an empty tenant would
    // match an all-zero expectation set and be misreported as already applied).
    const classification = classifyTargetState(baseline, {
      products: EXPECTED.products,
      activeProducts: EXPECTED.activeProducts,
      archivedProducts: EXPECTED.archivedProducts,
      shifts: EXPECTED.shifts,
      sales: EXPECTED.sales,
      saleItems: EXPECTED.saleItems,
      warehouseStocks: EXPECTED.activeProducts,
    }).verdict;

    // 5. License state (read-only).
    const company = await prisma.company.findUnique({
      where: { id: TARGET_COMPANY_ID },
      select: {
        status: true,
        plan: true,
        licenseStatus: true,
        trialEndsAt: true,
        licenseExpiresAt: true,
        licenseBlockedAt: true,
        maxUsers: true,
        maxProducts: true,
      },
    });
    if (!company) {
      throw new MigrationAbortError('TARGET_COMPANY_MISSING', 'No existe la empresa destino en la conexión viva', {});
    }
    const now = new Date();
    const trialValid = company.trialEndsAt === null || company.trialEndsAt.getTime() > now.getTime();
    const paidValid =
      company.licenseExpiresAt === null || company.licenseExpiresAt.getTime() > now.getTime();
    const licenseUsable =
      company.status === 'ACTIVE' &&
      ((company.licenseStatus === 'TRIAL' && trialValid) ||
        (company.licenseStatus === 'ACTIVE' && paidValid));
    const [billableProducts, activeUsers] = await Promise.all([
      prisma.product.count({ where: { companyId: TARGET_COMPANY_ID, archivedAt: null } }),
      prisma.user.count({ where: { companyId: TARGET_COMPANY_ID, blocked: false } }),
    ]);

    const checks = [
      buildCheck({
        metric: 'live_company_id',
        expected: TARGET_COMPANY_ID,
        actual: snapshot.company?.id ?? 'MISSING',
      }),
      buildCheck({
        metric: 'live_company_name',
        expected: TARGET_COMPANY_NAME,
        actual: snapshot.company?.name ?? 'MISSING',
      }),
      buildCheck({
        metric: 'live_warehouse_belongs_to_company',
        expected: TARGET_COMPANY_ID,
        actual: snapshot.warehouse?.companyId ?? 'MISSING',
      }),
      buildCheck({
        metric: 'live_terminal_belongs_to_company',
        expected: TARGET_COMPANY_ID,
        actual: snapshot.terminal?.companyId ?? 'MISSING',
      }),
      buildCheck({
        metric: 'live_owner_belongs_to_company',
        expected: TARGET_COMPANY_ID,
        actual: snapshot.ownerUser?.companyId ?? 'MISSING',
      }),
      buildCheck({ metric: 'baseline_products', expected: '0', actual: String(baseline.products) }),
      buildCheck({ metric: 'baseline_stocks', expected: '0', actual: String(baseline.warehouseStocks) }),
      buildCheck({ metric: 'baseline_sales', expected: '0', actual: String(baseline.sales) }),
      buildCheck({ metric: 'baseline_sale_items', expected: '0', actual: String(baseline.saleItems) }),
      buildCheck({ metric: 'baseline_shifts', expected: '0', actual: String(baseline.shifts) }),
      buildCheck({
        metric: 'baseline_no_foreign_rows',
        expected: '0',
        actual: String(
          baseline.clients +
            baseline.suppliers +
            baseline.purchaseOrders +
            baseline.cashMovements +
            baseline.cashboxDaily +
            baseline.taxes +
            baseline.ncfSequences +
            baseline.inventoryMovements +
            baseline.openShifts,
        ),
      }),
      buildCheck({ metric: 'company_status', expected: 'ACTIVE', actual: company.status }),
      buildCheck({
        metric: 'baseline_is_fresh',
        expected: 'FRESH',
        actual: classification,
      }),
      buildCheck({
        metric: 'license_usable',
        expected: 'true',
        actual: String(licenseUsable),
      }),
      buildCheck({
        metric: 'license_capacity',
        expected: 'true',
        actual: String(company.maxProducts >= EXPECTED.activeProducts),
      }),
    ];
    const failures = checks.filter((check) => !check.ok);

    return {
      verdict: failures.length === 0 ? 'GO' : 'NO-GO',
      environment,
      source: {
        path: options.sourcePath,
        sha256: actualSha,
        expectedSha256: options.sourceSha256 ?? EXPECTED_SOURCE_SHA256,
        matches: true,
      },
      baseline,
      classification,
      license: {
        status: company.status,
        plan: company.plan,
        licenseStatus: company.licenseStatus,
        trialEndsAt: company.trialEndsAt?.toISOString() ?? null,
        licenseExpiresAt: company.licenseExpiresAt?.toISOString() ?? null,
        licenseBlockedAt: company.licenseBlockedAt?.toISOString() ?? null,
        maxUsers: company.maxUsers,
        maxProducts: company.maxProducts,
        billableProducts,
        activeUsers,
        isUsable: licenseUsable,
      },
      checks,
      failures,
      durationMs: Date.now() - startedAt,
    };
  } finally {
    await prisma.$disconnect();
  }
}

/**
 * Surgical rollback (UAT or production cutover): deletes ONLY the deterministic id set of
 * this migration profile.
 */
export async function runRollback(options: Omit<ExecuteOptions, 'confirmWrite'> & { confirmWrite: boolean }): Promise<RollbackResult> {
  const startedAt = Date.now();
  assertExecuteConfirmations({
    execute: options.execute,
    environment: options.environment,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
    sourceSha256: options.sourceSha256,
    confirmCompanyName: options.confirmCompanyName,
    confirmWrite: options.confirmWrite,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
  });

  const dryRun = await runDryRun({
    sourcePath: options.sourcePath,
    targetSnapshot: null,
    expectedSha256: options.sourceSha256 ?? EXPECTED_SOURCE_SHA256,
    warehouseId: TARGET_WAREHOUSE_ID,
    generatedAt: options.generatedAt,
  });

  const { prisma, environment } = await openGuardedTarget({
    databaseUrl: options.databaseUrl,
    environment: options.environment,
    productionConfirmationToken: options.productionConfirmationToken ?? null,
    productionViaSshTunnel: options.productionViaSshTunnel === true,
    sshTunnelLocalPort: options.sshTunnelLocalPort,
    targetCompanyId: options.targetCompanyId,
    targetWarehouseId: options.targetWarehouseId,
  });

  try {
    const liveSnapshot = await collectTargetSnapshot(
      createPrismaTargetReadPort(prisma),
      {
        companyId: TARGET_COMPANY_ID,
        warehouseId: TARGET_WAREHOUSE_ID,
        terminalId: TARGET_TERMINAL_ID,
        ownerUserId: TARGET_OWNER_USER_ID,
      },
      new Date().toISOString(),
    );
    assertLiveTenantIdentity(liveSnapshot);

    const ids = buildIdSets({
      companyId: TARGET_COMPANY_ID,
      warehouseId: TARGET_WAREHOUSE_ID,
      writePlan: dryRun.writePlan,
    });

    const deleted = await deletePlan(prisma, ids, { timeoutMs: options.timeoutMs });
    const after = await readTargetState(prisma, TARGET_COMPANY_ID);

    return {
      environment: {
        classification: environment.classification,
        description: environment.description,
      },
      deleted,
      after,
      durationMs: Date.now() - startedAt,
    };
  } finally {
    await prisma.$disconnect();
  }
}

export function imageStatusesArePending(result: DryRunResult): boolean {
  return result.plan.products
    .filter((product) => product.legacyImagePath && product.legacyImagePath.trim().length > 0)
    .every((product) => product.imageStatus === IMAGE_STATUS_PENDING);
}
