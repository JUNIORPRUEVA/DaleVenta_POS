/* Preparación OFFLINE. No conecta al servidor ni aplica SQL, seed o configuración. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const EXPECTED_PENDING = [
  '20261115160000_add_company_usage_pulses',
  '20261116180000_license_plans_and_orders',
  '20261117170000_license_plan_requests',
  '20261117190000_evidence_insights',
  '20261117200000_provisional_activation',
  '20261117210000_evidence_validation',
  '20261119200000_license_override_multiwarehouse',
];
const hash = value => crypto.createHash('sha256').update(value).digest('hex');

function buildManifest({ sourceCommit, migrations, snapshot, runtime }) {
  if (!/^[a-f0-9]{40}$/i.test(sourceCommit)) throw Error('Invalid source commit');
  if (snapshot.readOnly !== true || runtime.readOnly !== true) throw Error('Read-only audit evidence required');
  const applied = new Map();
  for (const row of snapshot.migrations) {
    if (!row.finished_at && !row.rolled_back_at) throw Error('Unresolved migration attempt');
    if (!row.finished_at || row.rolled_back_at) continue;
    if (applied.has(row.migration_name) && applied.get(row.migration_name) !== row.checksum) {
      throw Error('Conflicting successful migration records');
    }
    applied.set(row.migration_name, row.checksum);
  }
  const pending = [];
  let exact = 0, lineEndingEquivalent = 0;
  const names = new Set();
  for (const item of [...migrations].sort((a, b) => a.name.localeCompare(b.name))) {
    if (!/^\d{14}_[a-z0-9_]+$/.test(item.name) || names.has(item.name)) throw Error('Invalid migration inventory');
    names.add(item.name);
    const checksum = hash(item.sql);
    if (!applied.has(item.name)) {
      pending.push({ name: item.name, sha256: checksum });
      continue;
    }
    if (checksum === applied.get(item.name)) { exact++; continue; }
    const crlf = Buffer.from(item.sql.toString('utf8').replace(/\r\n/g, '\n').replace(/\n/g, '\r\n'));
    if (hash(crlf) !== applied.get(item.name)) throw Error('Unexplained historical SQL difference');
    lineEndingEquivalent++;
  }
  if (JSON.stringify(pending.map(p => p.name)) !== JSON.stringify(EXPECTED_PENDING)) {
    throw Error('Pending migrations differ from reviewed scope; refresh the audit');
  }
  const services = {};
  for (const name of ['backend', 'pwa']) {
    const service = runtime.services?.[name];
    if (!service || !/^[a-f0-9]{64}$/i.test(service.protectedConfigHash ?? '') ||
        typeof service.image !== 'string' || !/@sha256:[a-f0-9]{64}$/i.test(service.image)) {
      throw Error('Immutable rollback image and protected configuration hash required');
    }
    services[name] = { rollbackImage: service.image, protectedConfigHash: service.protectedConfigHash };
  }
  return { formatVersion: 1, mode: 'OFFLINE_REVIEW_ONLY', sourceCommit,
    auditedAt: runtime.collectedAt ?? null, rollbackServices: services,
    historical: { exact, lineEndingEquivalent, unexplained: 0 }, pendingMigrations: pending,
    safeguards: { productionChangesAuthorized: false, automaticMigrations: false, generalSeed: false,
      customerBackfill: false, realInvoiceTests: false, whatsappRealSends: false },
    requiredApprovals: ['verified-backup-and-manual-migrations', 'catalog-initialization-only',
      'private-evidence-persistence-and-integrations', 'push-pr', 'merge-and-deploy'] };
}

function parseArgs(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    if (!['--snapshot', '--runtime', '--out-dir'].includes(key) || !args[i + 1] || args[i + 1].startsWith('--')) {
      throw Error('Only --snapshot, --runtime and optional --out-dir are supported; there is no apply mode');
    }
    if (options[key]) throw Error('Duplicate argument');
    options[key] = args[++i];
  }
  if (!options['--snapshot'] || !options['--runtime']) throw Error('Read-only snapshot and runtime files required');
  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const root = path.resolve(__dirname, '../..');
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
  if (git('status', '--porcelain')) throw Error('Commit and review the worktree before generating the release manifest');
  const sourceCommit = git('rev-parse', 'HEAD');
  const directory = path.join(root, 'apps/api/prisma/migrations');
  const migrations = fs.readdirSync(directory, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => ({
    name: e.name, sql: execFileSync('git', ['show', `${sourceCommit}:apps/api/prisma/migrations/${e.name}/migration.sql`], { cwd: root }),
  }));
  const readAudit = file => {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch { throw Error('Unable to read audit JSON; contents withheld'); }
  };
  const manifest = buildManifest({ sourceCommit, migrations,
    snapshot: readAudit(options['--snapshot']), runtime: readAudit(options['--runtime']) });
  const json = JSON.stringify(manifest, null, 2) + '\n';
  if (options['--out-dir']) {
    const output = path.resolve(options['--out-dir']);
    fs.mkdirSync(output, { recursive: true });
    fs.writeFileSync(path.join(output, 'manifest.json'), json, { flag: 'wx' });
    console.log(JSON.stringify({ prepared: true, sourceCommit, pendingMigrations: manifest.pendingMigrations.length, productionChanged: false }));
  } else process.stdout.write(json);
}

module.exports = { buildManifest, parseArgs, EXPECTED_PENDING };
if (require.main === module) {
  try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
