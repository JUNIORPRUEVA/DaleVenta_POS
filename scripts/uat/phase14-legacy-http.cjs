// Source-shaped historical request, NOT a distributed Windows binary.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { Client } = require('pg');

async function main() {
  const target = new URL(process.env.DATABASE_URL);
  assert.equal(process.env.APP_ENV, 'uat');
  assert.equal(process.env.UAT_LOCAL_ONLY, 'true');
  assert.equal(target.hostname, '127.0.0.1');
  assert.equal(target.port, '56548');
  assert.equal(target.pathname, '/daleventa_offline_safe_48h_phase12_uat');
  assert.equal(process.env.PORT, '46552');
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  let token;
  const request = async (path, method = 'GET', payload) => {
    const response = await fetch('http://127.0.0.1:46552' + path, {
      method, signal: AbortSignal.timeout(15000),
      headers: { 'content-type': 'application/json', 'x-client-device-id': 'phase14-source-shaped-130',
        ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(payload ? { body: JSON.stringify(payload) } : {}),
    });
    return { status: response.status, body: await response.json() };
  };
  try {
    assert.equal((await db.query('select current_database() as name')).rows[0].name, target.pathname.slice(1));
    const login = await request('/auth/login', 'POST', { email: process.env.UAT_ADMIN_EMAIL, password: process.env.UAT_ADMIN_PASSWORD });
    assert.equal(login.status, 201);
    token = login.body.accessToken;
    assert.ok(token);
    const companyId = login.body.user.companyId;
    const userId = login.body.user.id;
    const run = Date.now();
    const product = await request('/products', 'POST', { nombre: `phase14-legacy-${run}`, codigo: `phase14-legacy-${run}`, categoria: 'UAT phase14', precio: 100, costo: 40, stock: 0 });
    assert.equal(product.status, 201);
    const productId = product.body.id;
    assert.equal((await request(`/products/${productId}/stock`, 'PATCH', { delta: 20, reason: 'phase14 legacy isolated fixture' })).status, 200);
    const cash = await request('/cash/state');
    assert.equal(cash.status, 200);
    const shiftId = cash.body.activeSession.shiftId;
    const session = (await db.query('select id,company_id,"openedByUserId",status,"businessDate","openedAt","closedAt" from cash_sessions where company_id=$1 and id=$2', [companyId, shiftId])).rows[0];
    assert.ok(session);
    const payload = { paymentMethod: 'cash', paymentCashAmount: 400, cashReceived: 400,
      expectedTotalSold: 400, clientRequestId: `sale_req_${run}000`, saleOccurredAt: new Date().toISOString(),
      deviceFingerprint: 'phase14-source-shaped-130', items: [{ productId, qty: 4, priceSoldUnit: 100 }] };
    const stockBefore = Number((await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, productId])).rows[0].stock);
    const rejected = await request('/sales', 'POST', payload);
    assert.equal(rejected.status, 409);
    assert.equal(rejected.body.code, 'LEGACY_MISSING_SESSION');
    assert.equal(Number((await db.query('select count(*) from "Sale" where company_id=$1 and client_request_id=$2', [companyId, payload.clientRequestId])).rows[0].count), 0);
    assert.equal(Number((await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, productId])).rows[0].stock), stockBefore);
    const snapshots = ['69dd871b', '5278477e', '07664153'].map(revision => {
      const source = path => {
        const result = spawnSync('git', ['show', `${revision}:${path}`], { encoding: 'utf8' });
        assert.equal(result.status, 0); return result.stdout;
      };
      const sales = source('apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart');
      return { revision, version: source('apps/fulltech_app/pubspec.yaml').match(/^version:\s*(.+)$/m)[1],
        salesSourceSha256: createHash('sha256').update(sales).digest('hex'),
        emitsOrigin: sales.includes("'originCashSessionId': originCashSessionId"), binaryVerified: false };
    });
    const result = { status: 'PASS_SAFE_REJECTION', endpoint: 'POST http://127.0.0.1:46552/sales',
      companyId, userId, exactPayload: payload, response: rejected,
      availableCurrentSession: session, currentSessionIsNotOriginEvidence: true,
      operationSaved: false, stockBefore, stockAfter: stockBefore, snapshots,
      scope: 'Verified git source + HTTP/PostgreSQL fixture, no claim of distributed binary execution' };
    fs.writeFileSync('.uat/evidence/phase14-legacy-http.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
