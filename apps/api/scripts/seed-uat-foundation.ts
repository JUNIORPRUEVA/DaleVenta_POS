/**
 * Seeds the locked tenant foundation in a DISPOSABLE LOCAL UAT database so the
 * legacy migration can be rehearsed against the real Cloud schema.
 *
 * Usage (local UAT only):
 *   npx ts-node -P tsconfig.scripts.json --transpile-only scripts/seed-uat-foundation.ts \
 *     --environment=uat --database-url=<postgresql://…@127.0.0.1:port/daleventa_uat_local> \
 *     --include-decoy --confirm-write
 *
 * It refuses any non-loopback / production-looking destination through the same
 * guard used by the migration execute path. It never prints credentials.
 */

import { assertUatEnvironment, describeDatabaseUrl } from './migration/fullpos-legacy/environment-guard';
import {
  readDecoyState,
  seedUatFoundation,
  UAT_DECOY,
  UAT_OWNER_EMAIL,
} from './migration/fullpos-legacy/uat/uat-foundation';
import { createTargetClient, readLiveMetadata } from './migration/fullpos-legacy/writer';

function argValue(name: string): string | null {
  const prefix = `--${name}=`;
  const found = process.argv.slice(2).find((arg) => arg.startsWith(prefix));
  return found ? found.slice(prefix.length) : null;
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  const databaseUrl = argValue('database-url') ?? process.env.MIGRATION_DATABASE_URL ?? null;
  const environment = argValue('environment');
  const includeDecoy = argv.includes('--include-decoy');

  if (!databaseUrl || !environment || !argv.includes('--confirm-write')) {
    console.error(
      'Faltan argumentos: --environment=uat --database-url=<conexión UAT local> --confirm-write [--include-decoy]',
    );
    process.exitCode = 1;
    return;
  }

  const prisma = createTargetClient(databaseUrl);
  try {
    const metadata = await readLiveMetadata(prisma);
    const guard = assertUatEnvironment({ environment, url: databaseUrl, metadata });

    const summary = await seedUatFoundation(prisma, { includeDecoy });

    console.log('');
    console.log('UAT FOUNDATION SEED (base desechable local)');
    console.log(`Entorno : ${guard.classification} · ${describeDatabaseUrl(databaseUrl)}`);
    console.log(`Servidor: ${metadata.serverAddress}:${metadata.serverPort} · ${metadata.databaseName}`);
    console.log(`Empresa : ${summary.companyId}`);
    console.log(`Almacén : ${summary.warehouseId}`);
    console.log(`Terminal: ${summary.terminalId}`);
    console.log(`Owner   : ${summary.ownerUserId} (${UAT_OWNER_EMAIL})`);
    console.log(
      `Clave   : ${summary.passwordGenerated ? 'generada localmente y NO impresa' : 'tomada de UAT_OWNER_PASSWORD'}`,
    );
    if (includeDecoy) {
      console.log(`Decoy   : ${UAT_DECOY.companyId} (canario de aislamiento multi-tenant)`);
      console.log(`Decoy row counts: ${JSON.stringify(await readDecoyState(prisma))}`);
    }
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error('');
  console.error('SEED UAT ABORTADO (sin escrituras):');
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
