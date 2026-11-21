// Dedicated synthetic billing lab. No production credentials or real transfers.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const { spawn, spawnSync } = require('node:child_process');
const { PrismaClient } = require('@prisma/client');
const root = path.resolve(__dirname, '../..');
const directory = path.join(root, '.uat/plans-payment');
const database = 'fullpos_plans_payment_20261121';
const url = `postgresql://postgres@127.0.0.1:56562/${database}`;
const source = 'postgresql://postgres@127.0.0.1:56562/fullpos_product_lifecycle_private';
fs.mkdirSync(directory, { recursive: true });
async function init() {
  const sourceDb = new PrismaClient({ datasources: { db: { url: source } } });
  try {
    const found = await sourceDb.$queryRaw`SELECT datname FROM pg_database WHERE datname=${database}`;
    if (!found.length) {
      const created = spawnSync('docker', ['exec', 'fullpos_product_lifecycle_private_7e92', 'createdb', '-U', 'postgres', database], { windowsHide: true, stdio: 'inherit' });
      if (created.status !== 0) throw Error('Cannot create dedicated synthetic database');
    }
    const migrated = spawnSync(process.execPath, [require.resolve('prisma/build/index.js'), 'migrate', 'deploy', '--schema', path.join(root, 'apps/api/prisma/schema.prisma')], { cwd: root, env: { ...process.env, DATABASE_URL: url }, windowsHide: true, stdio: 'inherit' });
    if (migrated.status !== 0) throw Error('Local migrations failed');
    const plans = await sourceDb.licensePlan.findMany();
    const target = new PrismaClient({ datasources: { db: { url } } });
    try {
      if (plans.length) await target.licensePlan.createMany({ data: plans, skipDuplicates: true });
      else if (await target.licensePlan.count() === 0) {
        const seeded = spawnSync(process.execPath, [require.resolve('ts-node/dist/bin.js'), '--transpile-only', '-P', 'tsconfig.scripts.json', 'scripts/seed-license-plans.ts'], {
          cwd: path.join(root, 'apps/api'), env: { ...process.env, DATABASE_URL: url }, windowsHide: true, stdio: 'inherit',
        });
        if (seeded.status !== 0) throw Error('Could not load canonical catalog into the empty synthetic database');
      }
    }
    finally { await target.$disconnect(); }
    console.log('Dedicated plans database ready; canonical catalog, no shared prices changed.');
  } finally { await sourceDb.$disconnect(); }
}
function serve() {
  for (const file of ['.env', 'apps/api/.env']) {
    if (fs.existsSync(path.join(root, file))) throw Error('This lab requires the existing private checkout without backend env files');
  }
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/(TOKEN|SECRET|PASSWORD|KEY|URL|SMTP|WHATSAPP|GUARDIAN|DOSA|OPENAI|APPYRA|R2_|CLOUD)/i.test(name)));
  Object.assign(env, {
    DATABASE_URL: url, APP_ENV: 'uat', UAT_LOCAL_ONLY: 'true',
    UAT_EXPECTED_DB_NAME: database, UAT_EXPECTED_DB_PORT: '56562',
    HOST: '127.0.0.1', PORT: '4018', JWT_SECRET: crypto.randomBytes(48).toString('base64url'),
    LICENSE_EVIDENCE_STORAGE_DRIVER: 'local', LICENSE_EVIDENCE_DIR: path.join(directory, 'private-evidence'),
    LICENSE_BANK_NAME: 'Banco de pruebas', LICENSE_BANK_ACCOUNT: '1234567890',
    LICENSE_BANK_HOLDER: 'Empresa de pruebas', LICENSE_WA_DRY_RUN: 'true',
    DOSA_EMISSION_ENABLED: 'false', DOSA_PRODUCTION_EMISSION_ENABLED: 'false',
    LICENSE_EVIDENCE_TEST_ACTIVATE: 'false',
  });
  const log = fs.openSync(path.join(directory, 'api.log'), 'a');
  const child = spawn(process.execPath, ['dist/main.js'], { cwd: path.join(root, 'apps/api'), env, windowsHide: true, stdio: ['ignore', log, log] });
  console.log(`Isolated plans API 4018, private storage and no outbound credentials; PID ${child.pid}.`);
  child.on('exit', code => { fs.closeSync(log); process.exitCode = code ?? 1; });
}
const command = process.argv[2];
if (command === 'init') init().catch(e => { console.error(e.message); process.exitCode = 1; });
else if (command === 'serve') serve();
else throw Error('Only init and serve are supported');
