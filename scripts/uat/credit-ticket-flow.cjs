// Disposable loopback PostgreSQL/API only. Retains all synthetic evidence.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { spawn, spawnSync } = require('node:child_process');
const { PrismaClient } = require('@prisma/client');
const root = path.resolve(__dirname, '../..');
const dir = path.join(root, '.uat/credit-ticket');
const url = 'postgresql://postgres@127.0.0.1:14626/fullpos_credit_ticket_20261126';
const base = 'http://127.0.0.1:14627';
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/(TOKEN|SECRET|PASSWORD|KEY|URL|SMTP|WHATSAPP|GUARDIAN|DOSA|OPENAI|APPYRA|R2_|CLOUD|PGHOST|PGPORT|PGDATABASE|PGUSER)/i.test(key)));
Object.assign(env, { DATABASE_URL: url, APP_ENV: 'uat', UAT_LOCAL_ONLY: 'true',
  UAT_EXPECTED_DB_NAME: 'fullpos_credit_ticket_20261126', UAT_EXPECTED_DB_PORT: '14626',
  HOST: '127.0.0.1', PORT: '14627', JWT_SECRET: crypto.randomBytes(48).toString('base64url'),
  DOSA_EMISSION_ENABLED: 'false', DOSA_PRODUCTION_EMISSION_ENABLED: 'false',
  LICENSE_WA_DRY_RUN: 'true', ALANUBE_ENABLE_REAL_CALLS: 'false',
});
const db = new PrismaClient({ datasources: { db: { url } } });
let child;
const checks = [];
async function request(route, { token, body, method, status = body ? 201 : 200 } = {}) {
  const response = await fetch(base + route, { method: method || (body ? 'POST' : 'GET'),
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  const data = await response.json();
  assert.equal(response.status, status, `${route}: ${response.status} ${JSON.stringify(data).slice(0, 250)}`);
  return data;
}
async function main() {
  fs.mkdirSync(dir, { recursive: true });
  for (const file of ['.env', 'apps/api/.env']) assert.equal(fs.existsSync(path.join(root, file)), false, 'Private checkout required');
  if (process.argv.includes('--init')) {
    const migrated = spawnSync(process.execPath, [require.resolve('prisma/build/index.js'), 'migrate', 'deploy', '--schema', 'apps/api/prisma/schema.prisma'],
      { cwd: root, env, windowsHide: true, encoding: 'utf8' });
    fs.writeFileSync(path.join(dir, 'migrations.log'), migrated.stdout + migrated.stderr);
    assert.equal(migrated.status, 0, 'Isolated migration failed; inspect migrations.log');
  }
  const log = fs.openSync(path.join(dir, 'api.log'), 'a');
  const alreadyRunning = await fetch(base + '/health', { signal: AbortSignal.timeout(1000) }).then(() => true).catch(() => false);
  assert.equal(alreadyRunning, false, 'Lab port already occupied; do not test an unknown API');
  child = spawn(process.execPath, ['dist/main.js'], { cwd: path.join(root, 'apps/api'), env, windowsHide: true, stdio: ['ignore', log, log] });
  fs.writeFileSync(path.join(dir, 'owned-api-pid.json'), JSON.stringify({ pid: child.pid, port: 14627, root }));
  let ready = false;
  for (let i = 0; i < 400; i++) {
    if (child.exitCode != null) throw Error('Own API exited; inspect api.log');
    try { const response = await fetch(base + '/health', { signal: AbortSignal.timeout(1000) }); if (response.ok) { ready = true; break; } } catch {}
    await new Promise(resolve => setTimeout(resolve, 300));
  }
  assert.ok(ready, 'API readiness');
  assert.equal(child.exitCode, null, 'Own API must be alive');
  const run = crypto.randomUUID();
  async function account(suffix) {
    const password = crypto.randomBytes(24).toString('hex') + 'aA1!';
    return request('/auth/register-business', { body: { commercialName: `Credit lab ${suffix} ${run}`, firstName: 'Prueba', lastName: 'Credito', email: `${suffix}-${run}@example.test`, password, confirmPassword: password, phone: '8095550100' } });
  }
  const a = await account('a'), b = await account('b');
  const token = a.accessToken, companyId = a.user.companyId;
  const api = (route, body, status) => request(route, { token, body, status });
  const cash = await api('/cash/sessions/open', { openingAmount: 0 });
  const sessionId = cash.shiftId;
  const customer = await api('/clients', { nombre: 'Cliente de credito', telefono: '8095550101' });
  const product = await api('/products', { nombre: `Producto credito ${run}`, categoria: 'UAT', precio: 2500, costo: 1000, stock: 20, operationId: crypto.randomUUID() });
  async function sale() {
    return api('/sales', { clientRequestId: crypto.randomUUID(), originCashSessionId: sessionId,
      customerId: customer.id, paymentMethod: 'credit', paymentCashAmount: 1000, paymentTransferAmount: 0,
      cashReceived: 1000, changeAmount: 0, creditAmount: 1500, expectedTotalSold: 2500,
      items: [{ productId: product.id, qty: 1, priceSoldUnit: 2500 }] });
  }
  const first = await sale();
  const id = first.id || first.sale?.id;
  const snapshot = async saleId => JSON.parse(JSON.stringify(await db.sale.findFirstOrThrow({ where: { id: saleId, companyId }, include: { items: true, creditPayments: true } })));
  const before = await snapshot(id);
  const readable = await api(`/sales/${id}`);
  assert.equal(readable.id, id);
  await request(`/sales/${id}`, { token: b.accessToken, status: 404 });
  assert.equal(Number(before.totalSold), 2500); assert.equal(Number(before.creditPaidAmount), 1000); assert.equal(Number(before.creditBalance), 1500);
  checks.push('2500 sale persists 1000 paid and 1500 pending; detail GET is available and tenant isolated');
  const payment = { operationId: crypto.randomUUID(), operationCashSessionId: sessionId, paidAt: new Date().toISOString(), cashAmount: 500, transferAmount: 0 };
  const firstPayment = await api(`/sales/${id}/credit-payments`, payment);
  assert.equal(Number(firstPayment.sale.creditBalance), 1000);
  await api(`/sales/${id}/credit-payments`, payment);
  const afterRetry = await snapshot(id); assert.equal(afterRetry.creditPayments.length, 1); assert.equal(Number(afterRetry.creditPaidAmount), 1500);
  checks.push('500 collection and identical retry retain one ledger event and 1000 pending');
  await api(`/sales/${id}/credit-payments`, { ...payment, cashAmount: 600 }, 409);
  await request(`/sales/${id}/credit-payments`, { token: b.accessToken, body: payment, status: 404 });
  const second = await sale(), secondId = second.id || second.sale?.id;
  await api(`/sales/${secondId}/credit-payments`, payment, 409);
  assert.equal(Number((await snapshot(secondId)).creditBalance), 1500);
  checks.push('changed amount, other company and other sale cannot reuse payment identity');
  const finalPayment = { ...payment, operationId: crypto.randomUUID(), paidAt: new Date().toISOString(), cashAmount: 0, transferAmount: 1000 };
  await api(`/sales/${id}/credit-payments`, finalPayment);
  const settled = await snapshot(id);
  assert.equal(Number(settled.creditBalance), 0); assert.equal(Number(settled.creditPaidAmount), 2500); assert.equal(settled.creditStatus, 'paid');
  await api(`/sales/${id}/credit-payments`, { ...finalPayment, operationId: crypto.randomUUID(), transferAmount: 1 }, 400);
  checks.push('transfer settles original invoice; overpayment rejected');
  const raced = await sale(), raceId = raced.id || raced.sale?.id;
  const attempts = await Promise.all([0, 1].map(async () => {
    const response = await fetch(`${base}/sales/${raceId}/credit-payments`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ ...payment, operationId: crypto.randomUUID(), paidAt: new Date().toISOString(), cashAmount: 1500 }) });
    return response.status;
  }));
  assert.equal(attempts.filter(status => status === 201).length, 1);
  assert.ok(attempts.some(status => status === 409 || status === 400));
  const raceAfter = await snapshot(raceId); assert.equal(raceAfter.creditPayments.length, 1); assert.equal(Number(raceAfter.creditBalance), 0);
  checks.push('concurrent settlement commits one payment, rolls back the other');
  const nativeId = await prepareNative();
  fs.writeFileSync(path.join(dir, 'evidence.json'), JSON.stringify({ result: 'PASS', checks, before, afterRetry, settled, raceAfter, nativeId }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', checks }));
  if (process.argv.includes('--serve')) {
    console.log('Local credit API remains available for the native test. No production services.');
    await new Promise(resolve => { process.once('SIGINT', resolve); process.once('SIGTERM', resolve); });
  }
  async function prepareNative() {
  const nativeAccount = await account('native');
  const nativeApi = (route, body) => request(route, { token: nativeAccount.accessToken, body });
  const nativeCash = await nativeApi('/cash/sessions/open', { openingAmount: 0 });
  const nativeCustomer = await nativeApi('/clients', { nombre: 'Cliente de credito', telefono: '8095550101' });
  const nativeProduct = await nativeApi('/products', { nombre: `Producto credito nativo ${run}`, categoria: 'UAT', precio: 2500, costo: 1000, stock: 20, operationId: crypto.randomUUID() });
  const nativeSale = await nativeApi('/sales', { clientRequestId: crypto.randomUUID(), originCashSessionId: nativeCash.shiftId,
    customerId: nativeCustomer.id, paymentMethod: 'credit', paymentCashAmount: 1000, paymentTransferAmount: 0,
    cashReceived: 1000, changeAmount: 0, creditAmount: 1500, expectedTotalSold: 2500,
    items: [{ productId: nativeProduct.id, qty: 1, priceSoldUnit: 2500 }] });
  const nativeId = nativeSale.id || nativeSale.sale?.id;
  fs.writeFileSync(path.join(dir, 'native-fixture.json'), JSON.stringify({ base, token: nativeAccount.accessToken,
    user: nativeAccount.user, saleId: nativeId, sessionId: nativeCash.shiftId, companyId: nativeAccount.user.companyId }));
  return nativeId;
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(async () => { if (child) child.kill(); await db.$disconnect(); });
