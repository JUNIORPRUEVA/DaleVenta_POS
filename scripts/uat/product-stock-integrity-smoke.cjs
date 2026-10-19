const assert = require('node:assert/strict');
const fs = require('node:fs');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');

async function main() {
  const target = new URL(process.env.DATABASE_URL);
  assert.equal(process.env.APP_ENV, 'uat');
  assert.equal(process.env.UAT_LOCAL_ONLY, 'true');
  assert.equal(target.hostname, '127.0.0.1');
  assert.equal(target.port, '56548');
  const disposable = process.env.FULLPOS_DISPOSABLE_PHASE12 === 'true';
  const expectedDb = disposable ? 'daleventa_offline_safe_48h_phase12_uat' : 'daleventa_offline_safe_48h_uat';
  const expectedPort = disposable ? '46552' : '46548';
  assert.equal(target.pathname, '/' + expectedDb);
  assert.equal(process.env.PORT, expectedPort);
  const base = 'http://127.0.0.1:' + expectedPort;
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  try {
    assert.equal((await db.query('select current_database() as name')).rows[0].name, expectedDb);
    let token;
    async function request(path, method = 'GET', payload, status = [200, 201]) {
      const response = await fetch(base + path, {
        method, signal: AbortSignal.timeout(30000),
        headers: { 'content-type': 'application/json', 'x-client-device-id': 'phase11-smoke-device',
          ...(token ? { authorization: `Bearer ${token}` } : {}) },
        ...(payload ? { body: JSON.stringify(payload) } : {}),
      });
      const body = await response.json();
      assert.ok(status.includes(response.status), `${method} ${path}: status ${response.status}, code ${body.code || body.errorCode || 'unknown'}`);
      return body;
    }
    const login = await request('/auth/login', 'POST', { email: process.env.UAT_ADMIN_EMAIL, password: process.env.UAT_ADMIN_PASSWORD });
    token = login.accessToken;
    assert.ok(token);
    const companyId = login.user.companyId;
    assert.ok(companyId);
    const authorization = await request('/auth/offline-emergency/authorize', 'POST', {});
    assert.ok(authorization.allowedOperations.includes('catalog.products.create'));
    assert.ok(authorization.allowedOperations.includes('catalog.products.stock'));
    const cash = await request('/cash/state');
    const shiftId = cash.activeSession?.shiftId || cash.userOpenShift?.id;
    assert.ok(shiftId, 'An existing UAT cash session is required; this smoke never changes shifts.');
    const runId = `phase11-${Date.now()}`;
    const operationId = randomUUID();
    const payload = { operationId, nombre: runId, codigo: runId, categoria: 'UAT phase11', precio: 100, costo: 40, stock: 0 };
    const concurrent = await Promise.all(Array.from({ length: 5 }, () => request('/products', 'POST', payload)));
    assert.deepEqual([...new Set(concurrent.map(product => product.id))], [operationId]);
    await request('/products', 'POST', payload); // recovered response after a discarded confirmation
    for (const changed of [{ precio: 101 }, { stock: 1 }, { taxTreatment: 'EXEMPT' }]) {
      const conflict = await request('/products', 'POST', { ...payload, ...changed }, [409]);
      assert.equal(conflict.code, 'PRODUCT_IDEMPOTENCY_PAYLOAD_MISMATCH');
    }
    const stockOperationId = randomUUID();
    const stockPayload = { operationId: stockOperationId, delta: 20, reason: runId };
    await Promise.all(Array.from({ length: 5 }, () => request(`/products/${operationId}/stock`, 'PATCH', stockPayload)));
    await request(`/products/${operationId}/stock`, 'PATCH', stockPayload);
    for (const changed of [{ delta: 21 }, { reason: 'different' }, { stock: 20, delta: undefined }]) {
      const conflict = await request(`/products/${operationId}/stock`, 'PATCH', { ...stockPayload, ...changed }, [409]);
      assert.equal(conflict.code, 'INVENTORY_OPERATION_PAYLOAD_MISMATCH');
    }
    const saleRequestId = randomUUID();
    const salePayload = {
      clientRequestId: saleRequestId, originCashSessionId: shiftId, paymentMethod: 'cash',
      paymentCashAmount: 400, cashReceived: 400, expectedTotalSold: 400,
      items: [{ productId: operationId, qty: 4, priceSoldUnit: 100 }],
    };
    const sales = await Promise.all(Array.from({ length: 5 }, () => request('/sales', 'POST', salePayload)));
    const saleId = sales[0].id || sales[0].sale?.id;
    assert.ok(saleId);
    assert.equal(new Set(sales.map(sale => sale.id || sale.sale?.id)).size, 1);
    await request('/products', 'POST', payload); // replay after stock/sale changed the current product
    await request(`/products/${operationId}/stock`, 'PATCH', stockPayload);
    const product = (await db.query('select id, stock, create_payload_hash from "Product" where company_id=$1 and id=$2', [companyId, operationId])).rows;
    assert.equal(product.length, 1);
    assert.equal(Number(product[0].stock), 16);
    assert.ok(product[0].create_payload_hash);
    const movements = (await db.query('select operation_id, quantity_delta, source_type from inventory_movements where company_id=$1 and product_id=$2 order by created_at', [companyId, operationId])).rows;
    assert.equal(movements.length, 2);
    assert.equal(movements.filter(m => m.operation_id === stockOperationId).length, 1);
    assert.equal(movements.reduce((total, m) => total + Number(m.quantity_delta), 0), 16);
    const saleRows = (await db.query('select id, "cashSessionId", "totalSold" from "Sale" where company_id=$1 and client_request_id=$2', [companyId, saleRequestId])).rows;
    assert.equal(saleRows.length, 1);
    assert.equal(saleRows[0].cashSessionId, shiftId);
    assert.equal(Number(saleRows[0].totalSold), 400);
    const result = { status: 'PASS', runId, companyId, productId: operationId, stockOperationId, saleRequestId, saleId, shiftId,
      productCount: 1, entryCount: 1, saleCount: 1, movementCount: 2, stock: 16, concurrentRetries: 5,
      evidenceScope: 'HTTP + PostgreSQL; GUI and real lost network response are separate validations' };
    fs.mkdirSync('.uat/evidence', { recursive: true });
    fs.writeFileSync(`.uat/evidence/${runId}-product-stock-integrity.json`, JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
