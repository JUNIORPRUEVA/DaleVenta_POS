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
  assert.equal(target.pathname, '/daleventa_offline_safe_48h_phase12_uat');
  assert.equal(process.env.PORT, '46552');
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  try {
    assert.equal((await db.query('select current_database() as name')).rows[0].name, target.pathname.slice(1));
    let token;
    async function request(path, method = 'GET', payload, statuses = [200, 201]) {
      const response = await fetch('http://127.0.0.1:46552' + path, {
        method, signal: AbortSignal.timeout(15000),
        headers: { 'content-type': 'application/json', 'x-client-device-id': 'phase12-clone-device',
          ...(token ? { authorization: `Bearer ${token}` } : {}) },
        ...(payload ? { body: JSON.stringify(payload) } : {}),
      });
      const body = await response.json();
      assert.ok(statuses.includes(response.status), `${method} ${path}: ${response.status} ${body.code || body.errorCode || 'unknown'}`);
      return { body, status: response.status };
    }
    const login = (await request('/auth/login', 'POST', { email: process.env.UAT_ADMIN_EMAIL, password: process.env.UAT_ADMIN_PASSWORD })).body;
    token = login.accessToken;
    assert.ok(token);
    const companyId = login.user.companyId;
    assert.ok(companyId);
    const runId = `phase12-${Date.now()}`;
    const legacy = (await request('/products', 'POST', {
      nombre: runId + '-legacy', codigo: runId + '-legacy', categoria: 'UAT phase12', precio: 100, costo: 40, stock: 0,
    })).body;
    assert.ok(legacy.id);
    await request(`/products/${legacy.id}/stock`, 'PATCH', { delta: 20, reason: runId });
    const cash = (await request('/cash/state')).body;
    const shiftId = cash.activeSession?.shiftId || cash.userOpenShift?.id;
    assert.ok(shiftId);
    const legacySalePayload = {
      paymentMethod: 'cash', paymentCashAmount: 400, cashReceived: 400, expectedTotalSold: 400,
      items: [{ productId: legacy.id, qty: 4, priceSoldUnit: 100 }],
    };
    const missingSession = await request('/sales', 'POST', legacySalePayload, [409]);
    assert.equal(missingSession.body.code, 'LEGACY_MISSING_SESSION');
    // Verified 69dd871b (declares +130) sends request/time/device but no origin turn.
    const legacy130RequestId = randomUUID();
    const legacy130 = await request('/sales', 'POST', { ...legacySalePayload,
      clientRequestId: legacy130RequestId, saleOccurredAt: new Date().toISOString(),
      deviceFingerprint: 'phase13-legacy130' }, [409]);
    assert.equal(legacy130.body.code, 'LEGACY_MISSING_SESSION');
    assert.equal(Number((await db.query('select count(*) from "Sale" where company_id=$1 and client_request_id=$2',
      [companyId, legacy130RequestId])).rows[0].count), 0);
    const sale = (await request('/sales', 'POST', { ...legacySalePayload, originCashSessionId: shiftId })).body;
    const saleId = sale.id || sale.sale?.id;
    const legacyStock = (await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, legacy.id])).rows;
    assert.equal(Number(legacyStock[0].stock), 16);
    assert.equal((await db.query('select "cashSessionId" from "Sale" where company_id=$1 and id=$2', [companyId, saleId])).rows[0].cashSessionId, shiftId);
    const productId = randomUUID();
    const barcode = runId + '-barcode';
    await request('/products', 'POST', { operationId: productId, nombre: barcode, codigo: barcode, categoria: 'UAT phase12', precio: 100, costo: 40, stock: 0 });
    const barcodeConflict = await request('/products', 'POST', { operationId: randomUUID(), nombre: barcode + '-other', codigo: barcode, categoria: 'UAT phase12', precio: 100, costo: 40, stock: 0 }, [409]);
    await request(`/products/${productId}/stock`, 'PATCH', { operationId: randomUUID(), delta: 20, reason: runId });
    await request(`/products/${productId}/stock`, 'PATCH', { operationId: randomUUID(), delta: 5, reason: runId + '-remote' });
    const blockedOperation = randomUUID();
    const inventoryConflict = await request(`/products/${productId}/stock`, 'PATCH', { operationId: blockedOperation, stock: 30, expectedCurrentStock: 20, reason: runId }, [409]);
    assert.equal(Number((await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, productId])).rows[0].stock), 25);
    assert.equal(Number((await db.query('select count(*) from inventory_movements where company_id=$1 and operation_id=$2', [companyId, blockedOperation])).rows[0].count), 0);
    const incremental = { operationId: randomUUID(), delta: 20, reason: runId + '-increment' };
    await request(`/products/${productId}/stock`, 'PATCH', incremental);
    await request(`/products/${productId}/stock`, 'PATCH', incremental);
    assert.equal(Number((await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, productId])).rows[0].stock), 45);
    const recovery = JSON.parse(fs.readFileSync('.uat/evidence/phase11-quote-recovery-dto.json', 'utf8'));
    assert.equal(recovery.companyId, companyId);
    assert.equal(Object.hasOwn(recovery.dto, 'customerId'), false);
    // Exactly one send in a disposable PostgreSQL clone; never retries quotes.
    const quote = (await request('/cotizaciones', 'POST', recovery.dto)).body;
    const quoteId = quote.id || quote.cotizacion?.id;
    assert.ok(quoteId);
    const saved = (await db.query('select id,total from "Cotizacion" where company_id=$1 and id=$2', [companyId, quoteId])).rows;
    assert.equal(saved.length, 1);
    assert.equal(Number(saved[0].total), 390);
    const result = { status: 'PASS', runId, database: target.pathname.slice(1), companyId,
      legacyDtoWithoutOperationId: { productId: legacy.id, saleId, shiftId, stock: 16, duplicateRetrySafetyNotProven: true,
        saleWithoutTurn: '409 LEGACY_MISSING_SESSION', saleWithExplicitTurn: 'PASS' },
      legacy130Snapshot: { revision: '69dd871b', status: legacy130.status, code: legacy130.body.code, savedSales: 0,
        scope: 'Payload shape from verified source snapshot, not a commercial binary' },
      barcodeConflict: barcodeConflict.status, inventoryConflict: inventoryConflict.status, remoteStockBeforeIncrement: 25,
      incrementalAfterRemoteChange: { stock: 45, replayAppliedOnce: true },
      quoteCopySend: { quoteId, total: 390, originalModified: false, replayNotAttempted: true },
      scope: 'HTTP fixtures + PostgreSQL, not old Windows binary compatibility or GUI' };
    fs.writeFileSync('.uat/evidence/phase12-compatibility-smoke.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
