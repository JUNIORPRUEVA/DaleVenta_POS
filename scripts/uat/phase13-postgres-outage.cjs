const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');
const container = 'fullpos_phase13_failure_postgres';
const abrupt = process.env.FULLPOS_PHASE16_ABRUPT_PG === 'true';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
  assert.equal(process.env.APP_ENV, 'uat');
  assert.equal(process.env.UAT_LOCAL_ONLY, 'true');
  const label = execFileSync('docker', ['inspect', '--format', '{{index .Config.Labels "fullpos.uat.phase"}}', container], { encoding: 'utf8' }).trim();
  assert.equal(label, '13');
  let token;
  async function request(path, payload) {
    const response = await fetch('http://127.0.0.1:46554' + path, {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-client-device-id': 'phase13-outage',
        ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(30000),
    });
    return { status: response.status, body: await response.json() };
  }
  const login = await request('/auth/login', { email: process.env.UAT_ADMIN_EMAIL, password: process.env.UAT_ADMIN_PASSWORD });
  assert.ok([200, 201].includes(login.status));
  token = login.body.accessToken;
  const companyId = login.body.user.companyId;
  const operationId = randomUUID();
  const payload = { operationId, nombre: 'phase13-outage-' + operationId, categoria: 'UAT phase13', precio: 100, costo: 40, stock: 0 };
  let failed;
  execFileSync('docker', abrupt ? ['kill', '--signal=KILL', container] : ['stop', container], { stdio: 'ignore' });
  try {
    failed = await request('/products', payload);
    assert.ok([500, 503].includes(failed.status));
  } finally { execFileSync('docker', ['start', container], { stdio: 'ignore' }); }
  let ready = false;
  for (let attempt = 0; attempt < 30; attempt++) {
    try { execFileSync('docker', ['exec', container, 'pg_isready', '-h', '127.0.0.1', '-U', 'daleventa_offline_safe_48h_user', '-d', 'daleventa_offline_safe_48h_failure_uat'], { stdio: 'ignore' }); ready = true; break; } catch { await pause(500); }
  }
  assert.ok(ready);
  const connection = new URL(process.env.DATABASE_URL);
  assert.equal(connection.hostname, '127.0.0.1');
  assert.equal(connection.port, '56548');
  assert.equal(connection.pathname, '/daleventa_offline_safe_48h_uat');
  connection.port = '56593'; connection.pathname = '/daleventa_offline_safe_48h_failure_uat';
  const db = new Client({ connectionString: connection.toString() });
  await db.connect();
  try {
    const count = async () => Number((await db.query('select count(*) from "Product" where company_id=$1 and id=$2', [companyId, operationId])).rows[0].count);
    assert.equal(await count(), 0);
    const recoveryStatuses = [];
    for (let attempt = 0; attempt < 5; attempt++) {
      const recovered = await request('/products', payload);
      recoveryStatuses.push(recovered.status);
      if ([200, 201].includes(recovered.status)) break;
      assert.ok([500, 503].includes(recovered.status));
      await pause(1000);
    }
    assert.ok([200, 201].includes(recoveryStatuses.at(-1)), `Recovery statuses: ${recoveryStatuses}`);
    assert.ok([200, 201].includes((await request('/products', payload)).status));
    assert.equal(await count(), 1);
    const result = { status: 'PASS', container, failedStatus: failed.status, companyId, operationId,
      countBeforeRetry: 0, countAfterRetries: 1, recoveryStatuses, manualPostgresStopped: false,
      interruption: abrupt ? 'SIGKILL of disposable PostgreSQL container; not host power loss' : 'graceful container stop' };
    fs.writeFileSync(abrupt ? '.uat/evidence/phase16-postgres-outage.json' : '.uat/evidence/phase13-postgres-outage.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
