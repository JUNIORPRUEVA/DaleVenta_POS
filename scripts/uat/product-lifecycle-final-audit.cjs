// Additional final review; only synthetic fixtures in the dedicated local lab.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const crypto = require('node:crypto');
const { Client } = require('pg');
const { PrismaClient } = require('@prisma/client');
const base = 'http://127.0.0.1:4017';
const connection = { host: '127.0.0.1', port: 56562, user: 'postgres', database: 'fullpos_product_lifecycle_private' };
const db = new PrismaClient({ datasources: { db: { url: 'postgresql://postgres@127.0.0.1:56562/fullpos_product_lifecycle_private' } } });
const scenarios = [];
const delay = () => new Promise(resolve => setTimeout(resolve, 200));
async function req(route, token, body, method = body ? 'POST' : 'GET') {
  const r = await fetch(base + route, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
function expect(r, status) { assert.equal(r.status, status, `HTTP ${r.status}: ${r.data.code || r.data.message || ''}`); return r.data; }
async function main() {
  const fixture = JSON.parse(await fs.readFile('.uat/product-lifecycle/native-fixture.json', 'utf8'));
  const login = expect(await req('/auth/login', null, { email: fixture.email, password: fixture.password }), 201);
  const token = login.accessToken, companyId = login.user.companyId;
  async function create(stock) {
    return expect(await req('/products', token, { nombre: `Final audit ${crypto.randomUUID()}`, categoria: 'UAT', precio: 10, costo: 5, stock, operationId: crypto.randomUUID() }), 201);
  }
  async function snapshot(id) {
    return JSON.parse(JSON.stringify({
      product: await db.product.findFirst({ where: { companyId, id } }),
      stocks: await db.warehouseStock.findMany({ where: { companyId, productId: id }, orderBy: { id: 'asc' } }),
      movements: await db.inventoryMovement.findMany({ where: { companyId, productId: id }, orderBy: { id: 'asc' } }),
    }));
  }
  const quote = await db.cotizacion.create({ data: { companyId, createdByUserId: login.user.id, customerName: 'Synthetic final audit', customerPhone: '', subtotal: 10, itbisAmount: 0, total: 10 } });
  const client = new Client(connection); await client.connect();
  async function insert(id) {
    await client.query('INSERT INTO "CotizacionItem" (id,"cotizacionId","productId","productNameSnapshot",qty,"unitPrice","lineTotal") VALUES ($1,$2,$3,$4,1,10,10)', [crypto.randomUUID(), quote.id, id, 'Synthetic immutable snapshot']);
  }
  try {
    const referenceFirst = await create(0);
    const before = await snapshot(referenceFirst.id);
    await client.query('BEGIN'); await insert(referenceFirst.id);
    let completed = false;
    const deleting = req(`/products/${referenceFirst.id}`, token, null, 'DELETE').then(r => { completed = true; return r; });
    await delay(); assert.equal(completed, false, 'Delete must wait for the reference transaction');
    await client.query('COMMIT'); expect(await deleting, 409);
    assert.deepEqual(await snapshot(referenceFirst.id), before);
    assert.equal(await db.cotizacionItem.count({ where: { productId: referenceFirst.id, cotizacionId: quote.id } }), 1);
    scenarios.push('new reference wins delete race: product, stock and quote item retained');

    const deleteFirst = await create(0);
    expect(await req(`/products/${deleteFirst.id}`, token, null, 'DELETE'), 200);
    await assert.rejects(insert(deleteFirst.id), e => e.code === '23503');
    assert.equal(await db.product.count({ where: { companyId, id: deleteFirst.id } }), 0);
    assert.equal(await db.cotizacionItem.count({ where: { productId: deleteFirst.id, cotizacionId: quote.id } }), 0);
    assert.equal(await db.productLifecycleEvent.count({ where: { companyId, productId: deleteFirst.id, action: 'PRODUCT_DELETED' } }), 1);
    scenarios.push('delete wins race: stale reference rejected and durable deletion evidence retained');

    const pair = await Promise.all([create(7), create(7)]);
    const states = await Promise.all(pair.map(p => req(`/products/${p.id}/lifecycle`, token)));
    const operationId = crypto.randomUUID();
    const outcomes = await Promise.all(pair.map((p, i) => req(`/products/${p.id}/annul`, token, { operationId, expectedVersion: expect(states[i], 200).lifecycleVersion, reason: 'Synthetic competing command identity' })));
    assert.deepEqual(outcomes.map(r => r.status).sort(), [200, 409]);
    const rows = await db.product.findMany({ where: { companyId, id: { in: pair.map(p => p.id) } } });
    assert.equal(rows.filter(p => p.annulledAt).length, 1);
    assert.equal(rows.reduce((n, p) => n + Number(p.stock), 0), 7);
    assert.equal(await db.inventoryMovement.count({ where: { companyId, productId: { in: pair.map(p => p.id) }, sourceType: 'PRODUCT_ANNULMENT' } }), 1);
    assert.equal(await db.productLifecycleEvent.count({ where: { companyId, productId: { in: pair.map(p => p.id) }, action: 'PRODUCT_ANNULLED' } }), 1);
    scenarios.push('same command targeting two products: one success, one conflict, no extra compensation');

    const password = crypto.randomBytes(24).toString('base64url') + 'aA1!';
    const foreign = expect(await req('/auth/register-business', null, { commercialName: `Foreign audit ${Date.now()}`, firstName: 'Synthetic', lastName: 'Audit', email: `audit-${crypto.randomUUID()}@example.test`, password, confirmPassword: password, phone: '8095550100' }), 201);
    for (const ownerToken of [foreign.accessToken, null]) {
      const expected = ownerToken ? 404 : 401;
      for (const [suffix, method, body] of [
        ['', 'DELETE', null], ['/archive', 'PATCH', {}], ['/reactivate', 'PATCH', {}],
        ['/lifecycle', 'GET', null], ['/annul', 'POST', { operationId: crypto.randomUUID(), expectedVersion: 0, reason: 'Synthetic forbidden command' }],
      ]) expect(await req(`/products/${referenceFirst.id}${suffix}`, ownerToken, body, method), expected);
    }
    assert.deepEqual(await snapshot(referenceFirst.id), before);
    scenarios.push('all five lifecycle routes reject foreign company and missing authentication without changing stock or product');
    await fs.writeFile('.uat/product-lifecycle/deep-final-http.json', JSON.stringify({ result: 'PASS', scenarios }, null, 2));
    console.log(JSON.stringify({ result: 'PASS', scenarios }));
  } finally {
    await client.query('ROLLBACK').catch(() => {}); await client.end();
  }
}
main().catch(e => { console.error(e.name + ': ' + e.message); process.exitCode = 1; }).finally(() => db.$disconnect());
