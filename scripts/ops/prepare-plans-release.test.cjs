const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { buildManifest, parseArgs, EXPECTED_PENDING } = require('./prepare-plans-release.cjs');
const hash = value => createHash('sha256').update(value).digest('hex');
function fixture() {
  const historical = '20261101000000_synthetic_history';
  return { sourceCommit: 'a'.repeat(40),
    migrations: [{ name: historical, sql: Buffer.from('SELECT 1;\n') },
      ...EXPECTED_PENDING.map(name => ({ name, sql: Buffer.from('-- synthetic DDL fixture\n') }))],
    snapshot: { readOnly: true, companies: [{ name: 'MUST_NOT_EXPORT', licenseKey: 'MUST_NOT_EXPORT' }], migrations: [
      { migration_name: historical, checksum: hash('SELECT 1;\r\n'), finished_at: '2026-11-01', rolled_back_at: null },
      { migration_name: historical, checksum: 'old-failed-attempt', finished_at: null, rolled_back_at: '2026-11-01' },
    ] }, runtime: { readOnly: true, services: Object.fromEntries(['backend', 'pwa'].map(name => [name,
      { image: `ghcr.io/example/${name}@sha256:${'b'.repeat(64)}`, protectedConfigHash: 'c'.repeat(64) }])) } };
}
test('prepara solo el alcance exacto y conserva el historial CRLF sin exportar clientes', () => {
  const result = buildManifest(fixture());
  assert.equal(result.pendingMigrations.length, 7);
  assert.equal(result.historical.lineEndingEquivalent, 1);
  assert.equal(result.safeguards.customerBackfill, false);
  assert.equal(result.safeguards.productionChangesAuthorized, false);
  assert.equal(JSON.stringify(result).includes('MUST_NOT_EXPORT'), false);
});
test('rechaza SQL historico diferente', () => {
  const input = fixture(); input.migrations[0].sql = Buffer.from('SELECT 2;\n');
  assert.throws(() => buildManifest(input), /historical SQL/);
});
test('rechaza intentos pendientes sin resolver', () => {
  const input = fixture(); input.snapshot.migrations.push({ migration_name: 'failed', finished_at: null, rolled_back_at: null });
  assert.throws(() => buildManifest(input), /Unresolved/);
});
test('rechaza otra lista de pendientes aunque el numero coincida', () => {
  const input = fixture(); input.migrations[input.migrations.length - 1].name = '20261120000000_unreviewed';
  assert.throws(() => buildManifest(input), /reviewed scope/);
});
test('rechaza imagen mutable y falta de contexto de solo lectura', () => {
  const input = fixture(); input.runtime.services.backend.image = 'example:latest';
  assert.throws(() => buildManifest(input), /Immutable/);
  const other = fixture(); other.snapshot.readOnly = false;
  assert.throws(() => buildManifest(other), /Read-only/);
});
test('no dispone de opciones para aplicar ni ejecutar comandos remotos', () => {
  assert.throws(() => parseArgs(['--apply']), /no apply mode/);
  assert.throws(() => parseArgs(['--snapshot', 'x', '--runtime', 'y', '--command', 'ssh']), /no apply mode/);
  assert.deepEqual(parseArgs(['--snapshot', 'x', '--runtime', 'y']), { '--snapshot': 'x', '--runtime': 'y' });
});
