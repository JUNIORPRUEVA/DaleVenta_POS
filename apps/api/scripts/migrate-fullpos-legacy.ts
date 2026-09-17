/**
 * CLI: FullPOS Local (SQLite) -> FullPOS Cloud legacy migration.
 *
 * DEFAULT MODE IS DRY-RUN (zero writes).
 *
 * Usage (dry-run):
 *   npx ts-node --transpile-only -P tsconfig.scripts.json scripts/migrate-fullpos-legacy.ts \
 *     --source="C:\Users\pc\Documents\fullpods.db" \
 *     --target-snapshot=scripts/migration/fullpos-legacy/out/target-snapshot.json \
 *     --out-dir=scripts/migration/fullpos-legacy/out
 *
 * Usage (write, UAT rehearsal only — see EXECUTE_GUARDS / PRODUCTION_CUTOVER_GUARDS):
 *   --execute | --rollback | --verify  --environment=uat|production --database-url=...
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import {
  EXPECTED,
  EXPECTED_SOURCE_SHA256,
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_TERMINAL_ID,
  TARGET_WAREHOUSE_ID,
  EXECUTE_GUARDS,
  PRODUCTION_CUTOVER_GUARDS,
  PRODUCTION_TUNNEL_LOCAL_PORT,
  loadTargetSnapshotFile,
  manifestFingerprint,
  runDryRun,
  runExecute,
  runRollback,
  runVerify,
  runVerifyPreflight,
  type DryRunResult,
  type TargetSnapshot,
} from './migration/fullpos-legacy';

type Args = {
  source: string | null;
  sourceSha: string;
  targetSnapshot: string | null;
  skipTargetValidation: boolean;
  outDir: string;
  execute: boolean;
  rollback: boolean;
  verify: boolean;
  verifyPreflight: boolean;
  allowNewerSource: boolean;
  environment: string | null;
  databaseUrl: string | null;
  targetCompanyId: string | null;
  targetWarehouseId: string | null;
  confirmCompanyName: string | null;
  confirmWrite: boolean;
  productionConfirmationToken: string | null;
  productionViaSshTunnel: boolean;
  sshTunnelLocalPort: number;
};

const DEFAULT_OUT_DIR = join('scripts', 'migration', 'fullpos-legacy', 'out');

function parseArgs(argv: readonly string[]): Args {
  const value = (name: string): string | null => {
    const prefix = `--${name}=`;
    const match = argv.find((arg) => arg.startsWith(prefix));
    if (match) return match.slice(prefix.length);
    const index = argv.indexOf(`--${name}`);
    if (index >= 0 && index + 1 < argv.length && !argv[index + 1].startsWith('--')) {
      return argv[index + 1];
    }
    return null;
  };

  return {
    source: value('source') ?? (process.env.FULLPOS_LEGACY_DB ?? null),
    sourceSha: value('source-sha256') ?? EXPECTED_SOURCE_SHA256,
    targetSnapshot: value('target-snapshot'),
    skipTargetValidation: argv.includes('--skip-target-validation'),
    outDir: value('out-dir') ?? DEFAULT_OUT_DIR,
    execute: argv.includes('--execute'),
    rollback: argv.includes('--rollback'),
    verify: argv.includes('--verify'),
    verifyPreflight: argv.includes('--verify-preflight'),
    allowNewerSource: argv.includes('--allow-newer-source'),
    environment: value('environment'),
    databaseUrl: value('database-url') ?? (process.env.MIGRATION_DATABASE_URL ?? null),
    targetCompanyId: value('target-company-id'),
    targetWarehouseId: value('target-warehouse-id'),
    confirmCompanyName: value('confirm-company-name'),
    confirmWrite: argv.includes('--confirm-write'),
    productionConfirmationToken: value('confirm-production-cutover'),
    productionViaSshTunnel: argv.includes('--production-via-ssh-tunnel'),
    sshTunnelLocalPort: Number(value('ssh-tunnel-local-port') ?? PRODUCTION_TUNNEL_LOCAL_PORT),
  };
}

function printLine(): void {
  console.log('─'.repeat(78));
}

function printDryRun(result: DryRunResult): void {
  const totals = result.plan.totals;

  printLine();
  console.log('FULLPOS LOCAL -> FULLPOS CLOUD · MIGRADOR FASE 3 · DRY-RUN (0 escrituras)');
  printLine();
  console.log(`Origen      : ${result.source.path}`);
  console.log(`SHA256      : ${result.source.sha256}`);
  console.log(`SHA256 esp. : ${result.source.expectedSha256}  →  ${result.source.sha256Matches ? 'COINCIDE' : 'DIFIERE'}`);
  console.log(
    `Integridad  : ${result.source.integrityCheck} · FK violations: ${result.source.foreignKeyViolations} · user_version: ${result.source.userVersion}`,
  );
  console.log(`Destino     : ${TARGET_COMPANY_NAME} (${TARGET_COMPANY_ID})`);
  console.log(`Almacén     : ${TARGET_WAREHOUSE_ID}`);
  console.log(`Terminal    : ${TARGET_TERMINAL_ID}`);
  console.log(
    `Validación destino: ${result.targetValidation.status} — ${result.targetValidation.detail}`,
  );

  printLine();
  console.log('DEMO EXCLUIDO');
  console.log(`  productos : ${result.plan.demo.productCount} (esperado ${EXPECTED.demoProducts})`);
  console.log(`  ventas    : ${result.plan.demo.saleCount} (esperado ${EXPECTED.demoSales})`);
  console.log(`  líneas    : ${result.plan.demo.saleItemCount} (esperado ${EXPECTED.demoSaleItems})`);
  console.log(`  turnos    : ${result.plan.demo.shiftCount} (esperado ${EXPECTED.demoShifts})`);
  console.log(`  stock     : ${result.manifest.demo.stock}`);
  console.log(`  ITBIS     : ${result.manifest.demo.itbis}`);

  printLine();
  console.log('PLAN DE IMPORTACIÓN');
  console.log(
    `  productos : ${totals.products} (activos ${totals.activeProducts} · archivados ${totals.archivedProducts})`,
  );
  console.log(
    `  stock     : ${result.manifest.totals.openingStock as string} (positivos ${totals.activeStockPositive} · cero ${totals.activeStockZero} · negativos ${totals.activeStockNegative})`,
  );
  console.log(
    `  turnos    : ${totals.shifts} importados de ${totals.sourceRealShifts} reales · ${totals.shiftsNotImported} omitidos por antigüedad (política ${result.plan.shiftPolicy.policy})`,
  );
  console.log(
    `  vínculos  : ${totals.salesLinkedToImportedShifts} ventas ligadas a un turno importado · ${totals.salesWithoutShiftLink} ventas con cashSessionId = NULL (turno fuera de la ventana)`,
  );
  console.log(
    `  ventana   : turno importado más antiguo ${result.plan.shiftPolicy.boundary.oldestImportedClosedAt} · turno omitido más reciente ${result.plan.shiftPolicy.boundary.newestNotImportedClosedAt}`,
  );
  console.log(
    `  ventas    : ${totals.sales} (completadas ${totals.completedSales} · canceladas ${totals.cancelledSales})`,
  );
  console.log(`  líneas    : ${totals.saleItems}`);
  console.log(
    `  ingresos  : ${result.manifest.totals.revenue as string} · costo ${result.manifest.totals.cost as string} · utilidad ${result.manifest.totals.profit as string}`,
  );
  console.log(`  ITBIS     : ${result.manifest.totals.itbis as string} · NCF: ${totals.ncf}`);
  console.log(`  imágenes  : ${totals.imagesPending} referencias pendientes (no bloquean el dry-run)`);

  printLine();
  console.log('EXCLUSIONES Y EXCEPCIONES');
  console.log(`  registros excluidos  : ${result.plan.excluded.length}`);
  console.log(`  excepciones de stock : ${result.plan.stockExceptions.length}`);
  for (const exception of result.plan.stockExceptions) {
    console.log(
      `    · producto ${exception.legacyProductId} (${exception.code}) stock legacy ${exception.legacyStock} → operativo ${exception.operationalStock}`,
    );
  }

  printLine();
  console.log(`RECONCILIACIÓN: ${result.reconciliation.verdict} (${result.reconciliation.checks.length} checks, ${result.reconciliation.failures.length} fallos)`);
  for (const failure of result.reconciliation.failures) {
    console.log(`  ✗ ${failure.metric}: esperado ${failure.expected}, obtenido ${failure.actual}`);
  }
  printLine();
}

function writeArtifacts(args: Args, result: DryRunResult): { manifestPath: string; reportPath: string } {
  const outDir = resolve(args.outDir);
  mkdirSync(outDir, { recursive: true });

  const manifestPath = join(outDir, 'manifest-fullpos-legacy.json');
  const reportPath = join(outDir, 'dry-run-report.json');

  writeFileSync(manifestPath, result.manifestJson, 'utf8');
  writeFileSync(
    reportPath,
    `${JSON.stringify(
      {
        generatedAt: result.generatedAt,
        mode: 'DRY_RUN',
        productionWrites: 0,
        source: result.source,
        targetValidation: result.targetValidation,
        totals: result.manifest.totals,
        demo: result.manifest.demo,
        stockExceptions: result.plan.stockExceptions,
        excludedCount: result.plan.excluded.length,
        reconciliation: result.reconciliation,
        manifestSha256: result.manifestSha256,
        fingerprint: manifestFingerprint(result.manifest),
      },
      null,
      2,
    )}\n`,
    'utf8',
  );

  return { manifestPath, reportPath };
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  if (args.verifyPreflight) {
    if (!args.databaseUrl) {
      console.error('Falta --database-url=<conexión del destino> (o MIGRATION_DATABASE_URL).');
      process.exitCode = 1;
      return;
    }
    const result = await runVerifyPreflight({
      sourcePath: args.source ?? '',
      databaseUrl: args.databaseUrl,
      environment: args.environment,
      targetCompanyId: args.targetCompanyId,
      targetWarehouseId: args.targetWarehouseId,
      sourceSha256: args.sourceSha,
      confirmCompanyName: args.confirmCompanyName,
      confirmWrite: true,
      productionConfirmationToken: args.productionConfirmationToken,
      productionViaSshTunnel: args.productionViaSshTunnel,
      sshTunnelLocalPort: args.sshTunnelLocalPort,
      execute: true,
    });

    const outDir = resolve(args.outDir);
    mkdirSync(outDir, { recursive: true });
    const artifact = join(outDir, 'preflight-verification.json');
    writeFileSync(
      artifact,
      `${JSON.stringify(
        {
          generatedAt: new Date().toISOString(),
          mode: 'VERIFY_PREFLIGHT_READ_ONLY',
          verdict: result.verdict,
          environment: result.environment,
          source: result.source,
          classification: result.classification,
          baseline: result.baseline,
          license: result.license,
          checks: result.checks,
          failures: result.failures,
          durationMs: result.durationMs,
        },
        null,
        2,
      )}\n`,
      'utf8',
    );

    printLine();
    console.log('VERIFICACIÓN PRE-VUELO AUTENTICADA (read-only, 0 escrituras)');
    printLine();
    console.log(`Veredicto : ${result.verdict}`);
    console.log(`Entorno   : ${result.environment.classification} · ${result.environment.description}`);
    console.log(`Servidor  : ${result.environment.server} · base ${result.environment.database}`);
    console.log(`Origen    : ${result.source.sha256} (coincide)`);
    console.log(
      `Baseline  : products ${result.baseline.products} · stocks ${result.baseline.warehouseStocks} · turnos ${result.baseline.shifts} · ventas ${result.baseline.sales} · líneas ${result.baseline.saleItems} → ${result.classification}`,
    );
    console.log(
      `Licencia  : ${result.license.status}/${result.license.plan}/${result.license.licenseStatus} · trialEndsAt ${result.license.trialEndsAt} · usable=${result.license.isUsable} · maxProducts ${result.license.maxProducts} (en uso ${result.license.billableProducts}) · usuarios activos ${result.license.activeUsers}/${result.license.maxUsers}`,
    );
    console.log(
      `Checks    : ${result.checks.length} (${result.failures.length} fallos) · ${result.durationMs} ms`,
    );
    for (const failure of result.failures) {
      console.log(`  ✗ ${failure.metric}: esperado ${failure.expected}, obtenido ${failure.actual}`);
    }
    console.log(`Artefacto : ${artifact}`);
    printLine();
    if (result.verdict !== 'GO') {
      process.exitCode = 1;
    }
    return;
  }

  if (args.verify) {
    if (!args.databaseUrl) {
      console.error('Falta --database-url=<conexión del destino> (o MIGRATION_DATABASE_URL).');
      process.exitCode = 1;
      return;
    }
    const result = await runVerify({
      sourcePath: args.source ?? '',
      databaseUrl: args.databaseUrl,
      environment: args.environment,
      targetCompanyId: args.targetCompanyId,
      targetWarehouseId: args.targetWarehouseId,
      sourceSha256: args.sourceSha,
      confirmCompanyName: args.confirmCompanyName,
      confirmWrite: true,
      productionConfirmationToken: args.productionConfirmationToken,
      productionViaSshTunnel: args.productionViaSshTunnel,
      sshTunnelLocalPort: args.sshTunnelLocalPort,
      execute: true,
    });

    const outDir = resolve(args.outDir);
    mkdirSync(outDir, { recursive: true });
    const artifact = join(outDir, 'destination-verification.json');
    writeFileSync(
      artifact,
      `${JSON.stringify(
        {
          generatedAt: new Date().toISOString(),
          mode: 'VERIFY_READ_ONLY',
          verdict: result.verdict,
          environment: result.environment,
          state: result.state,
          reconciliation: result.reconciliation,
          otherTenants: result.otherTenants,
          durationMs: result.durationMs,
        },
        null,
        2,
      )}\n`,
      'utf8',
    );

    printLine();
    console.log('VERIFICACIÓN READ-ONLY DEL DESTINO (0 escrituras)');
    printLine();
    console.log(`Veredicto : ${result.verdict}`);
    console.log(`Entorno   : ${result.environment.classification} · ${result.environment.description}`);
    console.log(
      `Estado    : products ${result.state.products} (activos ${result.state.activeProducts} · archivados ${result.state.archivedProducts}) · stocks ${result.state.warehouseStocks} · turnos ${result.state.shifts} · ventas ${result.state.sales} · líneas ${result.state.saleItems}`,
    );
    console.log(
      `Reconciliación DB: ${result.reconciliation.verdict} (${result.reconciliation.checks.length} checks, ${result.reconciliation.failures.length} fallos)`,
    );
    for (const failure of result.reconciliation.failures) {
      console.log(`  ✗ ${failure.metric}: esperado ${failure.expected}, obtenido ${failure.actual}`);
    }
    console.log(
      `Otros tenants: empresas ${result.otherTenants.companies} · products fuera del tenant ${result.otherTenants.productsByOtherTenants} · sales fuera del tenant ${result.otherTenants.salesByOtherTenants}`,
    );
    console.log(`Artefacto : ${artifact}`);
    console.log(`Duración  : ${result.durationMs} ms`);
    printLine();
    if (result.verdict !== 'GO') {
      process.exitCode = 1;
    }
    return;
  }

  if (args.rollback) {
    if (!args.databaseUrl) {
      console.error('Falta --database-url=<conexión UAT local> (o MIGRATION_DATABASE_URL).');
      process.exitCode = 1;
      return;
    }
    const result = await runRollback({
      sourcePath: args.source ?? '',
      databaseUrl: args.databaseUrl,
      environment: args.environment,
      targetCompanyId: args.targetCompanyId,
      targetWarehouseId: args.targetWarehouseId,
      sourceSha256: args.sourceSha,
      confirmCompanyName: args.confirmCompanyName,
      confirmWrite: args.confirmWrite,
      productionConfirmationToken: args.productionConfirmationToken,
      productionViaSshTunnel: args.productionViaSshTunnel,
      sshTunnelLocalPort: args.sshTunnelLocalPort,
      execute: true,
    });
    printLine();
    console.log('ROLLBACK QUIRÚRGICO (solo ids deterministas de este perfil)');
    printLine();
    console.log(`Entorno : ${result.environment.classification} · ${result.environment.description}`);
    console.log(
      `Borrado : saleItems ${result.deleted.saleItems} · sales ${result.deleted.sales} · shifts ${result.deleted.shifts} · warehouseStocks ${result.deleted.warehouseStocks} · products ${result.deleted.products}`,
    );
    console.log(`Después : ${JSON.stringify(result.after)}`);
    console.log(`Duración: ${result.durationMs} ms`);
    printLine();
    return;
  }

  if (args.execute) {
    if (!args.databaseUrl) {
      console.error('Falta --database-url=<conexión UAT local> (o MIGRATION_DATABASE_URL).');
      process.exitCode = 1;
      return;
    }
    const result = await runExecute({
      sourcePath: args.source ?? '',
      databaseUrl: args.databaseUrl,
      environment: args.environment,
      targetCompanyId: args.targetCompanyId,
      targetWarehouseId: args.targetWarehouseId,
      sourceSha256: args.sourceSha,
      confirmCompanyName: args.confirmCompanyName,
      confirmWrite: args.confirmWrite,
      productionConfirmationToken: args.productionConfirmationToken,
      productionViaSshTunnel: args.productionViaSshTunnel,
      sshTunnelLocalPort: args.sshTunnelLocalPort,
      execute: true,
    });

    printLine();
    console.log('EJECUCIÓN UAT (escritura real en base desechable no productiva)');
    printLine();
    console.log(`Veredicto : ${result.verdict}`);
    console.log(`Entorno   : ${result.environment.classification} · ${result.environment.description}`);
    console.log(`Servidor  : ${result.environment.server} · base ${result.environment.database}`);
    console.log(
      `Insertado : products ${result.counts.products} · warehouseStocks ${result.counts.warehouseStocks} · shifts ${result.counts.shifts} · sales ${result.counts.sales} · saleItems ${result.counts.saleItems}`,
    );
    console.log(`Duración  : ${result.durationMs} ms`);
    console.log(
      `Reconciliación DB: ${result.reconciliation.verdict} (${result.reconciliation.checks.length} checks, ${result.reconciliation.failures.length} fallos)`,
    );
    for (const failure of result.reconciliation.failures) {
      console.log(`  ✗ ${failure.metric}: esperado ${failure.expected}, obtenido ${failure.actual}`);
    }
    printLine();
    return;
  }

  if (!args.source) {
    console.error('Falta --source=<ruta de fullpods.db> (o la variable FULLPOS_LEGACY_DB).');
    process.exitCode = 1;
    return;
  }

  if (!args.targetSnapshot && !args.skipTargetValidation) {
    console.error(
      'Falta --target-snapshot=<archivo.json>. El dry-run debe validar el destino antes de continuar.\n' +
        'Use --skip-target-validation solo para una verificación parcial sin destino (NUNCA para ejecutar).',
    );
    process.exitCode = 1;
    return;
  }

  let snapshot: TargetSnapshot | null = null;
  if (args.targetSnapshot) {
    snapshot = loadTargetSnapshotFile(args.targetSnapshot);
  }

  const result = await runDryRun({
    sourcePath: args.source,
    targetSnapshot: snapshot,
    expectedSha256: args.sourceSha,
    warehouseId: TARGET_WAREHOUSE_ID,
    requireCleanBaseline: true,
  });

  printDryRun(result);

  if (!result.source.sha256Matches && !args.allowNewerSource) {
    console.log('SHA del origen distinto al esperado: revise si es la captura final de cutover.');
  }

  const artifacts = writeArtifacts(args, result);
  const fingerprint = manifestFingerprint(result.manifest);
  console.log(`Manifiesto : ${artifacts.manifestPath}`);
  console.log(`SHA256     : ${result.manifestSha256}`);
  console.log(`Digest     : ${fingerprint.contentDigest}  (contenido, sin timestamps)`);
  console.log(
    `IDs        : products ${fingerprint.idSets.products} · shifts ${fingerprint.idSets.shifts}`,
  );
  console.log(
    `             sales ${fingerprint.idSets.sales} · saleItems ${fingerprint.idSets.saleItems} · warehouseScope ${fingerprint.idSets.warehouseStockScope}`,
  );
  console.log(`Reporte    : ${artifacts.reportPath}`);
  console.log('');
  console.log(
    result.targetValidation.status === 'PASSED'
      ? 'DRY-RUN COMPLETO: destino validado, reconciliación GO, 0 escrituras.'
      : 'DRY-RUN PARCIAL: destino NO validado. No usar esta salida para ejecutar.',
  );
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error('');
  console.error(
    process.argv.includes('--execute') ||
      process.argv.includes('--rollback') ||
      process.argv.includes('--verify') ||
      process.argv.includes('--verify-preflight')
      ? 'EJECUCIÓN ABORTADA (sin escrituras parciales):'
      : 'FALLO DEL DRY-RUN (sin escrituras):',
  );
  console.error(message);
  if (
    process.argv.includes('--execute') ||
    process.argv.includes('--rollback') ||
    process.argv.includes('--verify') ||
    process.argv.includes('--verify-preflight')
  ) {
    console.error('');
    console.error(`Guards requeridos: ${EXECUTE_GUARDS.join(' ')}`);
    console.error(`Cutover producción: ${PRODUCTION_CUTOVER_GUARDS.join(' ')}`);
  }
  process.exitCode = 1;
});
