const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');

async function main() {
  const target = new URL(process.env.DATABASE_URL);
  assert.equal(process.env.APP_ENV, 'uat'); assert.equal(process.env.UAT_LOCAL_ONLY, 'true');
  assert.equal(target.hostname, '127.0.0.1'); assert.equal(target.port, '56548');
  assert.equal(target.pathname, '/daleventa_offline_safe_48h_phase12_uat');
  const root = path.resolve(process.argv[3]);
  assert.equal(root.toLowerCase(), path.resolve('.uat/phase16-process-bench').toLowerCase());
  const spec = JSON.parse(fs.readFileSync(path.join(root, 'spec.json'), 'utf8'));
  let token;
  async function request(route, method = 'GET', payload) {
    const response = await fetch('http://127.0.0.1:46552' + route, {
      method, signal: AbortSignal.timeout(15000),
      headers: { 'content-type': 'application/json', 'x-client-device-id': 'phase16-process-bench',
        ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(payload ? { body: JSON.stringify(payload) } : {}),
    });
    const body = await response.json();
    assert.ok([200,201].includes(response.status), `${method} ${route}: ${response.status} ${body.code || 'unknown'}`);
    return body;
  }
  const login = await request('/auth/login', 'POST', { email: process.env.UAT_ADMIN_EMAIL, password: process.env.UAT_ADMIN_PASSWORD });
  token = login.accessToken; assert.ok(token);
  const companyId = login.user.companyId, userId = login.user.id;
  if (process.argv[2] === 'setup') {
    const cash = await request('/cash/state'); const shiftId = cash.activeSession.shiftId;
    for (const item of spec) {
      const dir = path.join(root, item.name); fs.mkdirSync(dir);
      const productId = randomUUID(), operationId = randomUUID(), nonce = randomUUID();
      const product = { operationId: productId, nombre: `phase16-${item.name}-${nonce}`,
        codigo: `phase16-${nonce}`, categoria: 'UAT phase16', precio: 100, costo: 40, stock: 0 };
      if (item.kind !== 'product') {
        await request('/products', 'POST', product);
        if (item.kind === 'sale') await request(`/products/${productId}/stock`, 'PATCH', { operationId: randomUUID(), delta: 20, reason: 'phase16 isolated setup' });
      }
      const salePayload = { clientRequestId: operationId, originCashSessionId: shiftId,
        saleOccurredAt: new Date().toISOString(), deviceFingerprint: 'phase16-process-bench',
        paymentMethod: 'cash', paymentCashAmount: 400, cashReceived: 400, expectedTotalSold: 400,
        items: [{ productId, qty: 4, priceSoldUnit: 100, inventoryTrackedSnapshot: true }] };
      const payload = item.kind === 'sale' ? salePayload : item.kind === 'product' ? product :
        { id: productId, operationId, delta: 20, reason: 'phase16 isolated stock' };
      const type = item.kind === 'sale' ? 'sales.create' : item.kind === 'product' ? 'catalog.products.create' : 'catalog.products.stock';
      fs.writeFileSync(path.join(dir, 'fixture.json'), JSON.stringify({ ...item, companyId, userId, shiftId, productId,
        operationId: item.kind === 'product' ? productId : operationId, nonce, payload, type }), { flag: 'wx' });
    }
    console.log(`PASS: ${spec.length} disposable fixtures prepared in clone46552`);
    return;
  }
  assert.equal(process.argv[2], 'audit');
  const db = new Client({ connectionString: process.env.DATABASE_URL }); await db.connect();
  try {
    const results = [];
    for (const item of spec) {
      const fixture = JSON.parse(fs.readFileSync(path.join(root, item.name, 'fixture.json'), 'utf8'));
      assert.equal(fixture.companyId, companyId); assert.equal(fixture.userId, userId);
      const committed = ['G','H','I','J','L'].includes(item.stage);
      const products = (await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, fixture.productId])).rows;
      if (item.kind === 'product') assert.equal(products.length, committed ? 1 : 0);
      else assert.equal(products.length, 1);
      if (products.length) assert.equal(Number(products[0].stock), item.kind === 'sale' ? (committed ? 16 : 20) : (item.kind === 'stock' && committed ? 20 : 0));
      const sales = (await db.query('select id,"cashSessionId","totalSold","paymentCashAmount" from "Sale" where company_id=$1 and client_request_id=$2', [companyId, fixture.operationId])).rows;
      assert.equal(sales.length, item.kind === 'sale' && committed ? 1 : 0);
      if (sales.length) {
        assert.equal(sales[0].cashSessionId, fixture.shiftId); assert.equal(Number(sales[0].totalSold), 400);
        assert.equal(Number(sales[0].paymentCashAmount), 400);
        const movements = await db.query('select id from inventory_movements where company_id=$1 and source_id=$2 and source_type=$3', [companyId, sales[0].id, 'SALE']);
        assert.equal(movements.rows.length, 1);
      }
      if (item.kind === 'stock') {
        const entries = await db.query('select id from inventory_movements where company_id=$1 and operation_id=$2', [companyId, fixture.operationId]);
        assert.equal(entries.rows.length, committed ? 1 : 0);
      }
      results.push({ name: item.name, kind: item.kind, stage: item.stage, committed, status: 'PASS',
        stock: products.length ? Number(products[0].stock) : null, sales: sales.length, originalTurnPreserved: true });
    }
    let native = null;
    const marker = '.uat/phase16-native-bank/committed.json';
    if (fs.existsSync(marker)) {
      const operation = JSON.parse(fs.readFileSync(marker, 'utf8'));
      assert.equal(operation.companyId, companyId); assert.equal(operation.userId, userId);
      const sales = (await db.query('select id,"cashSessionId","totalSold","paymentCashAmount" from "Sale" where company_id=$1 and client_request_id=$2', [companyId, operation.requestId])).rows;
      assert.equal(sales.length, 1); assert.equal(sales[0].id, operation.remoteSaleId);
      assert.equal(sales[0].cashSessionId, operation.shiftId); assert.equal(Number(sales[0].totalSold), 400);
      assert.equal(Number(sales[0].paymentCashAmount), 400);
      const product = (await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, operation.productId])).rows;
      assert.equal(Number(product[0].stock), 16);
      const moves = (await db.query('select id from inventory_movements where company_id=$1 and source_id=$2 and source_type=$3', [companyId, sales[0].id, 'SALE'])).rows;
      assert.equal(moves.length, 1);
      native = { status:'PASS', requestId:operation.requestId, saleId:sales[0].id, stock:16, total:400,
        originalTurn:operation.shiftId, sales:1, saleMovements:1 };
    }
    fs.writeFileSync('.uat/evidence/phase16-process-postgres.json', JSON.stringify({ status: 'PASS', database: target.pathname.slice(1), results, native }, null, 2));
    console.log(`PASS: ${results.length} recovered/aborted fixtures reconciled in scoped PostgreSQL`);
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
