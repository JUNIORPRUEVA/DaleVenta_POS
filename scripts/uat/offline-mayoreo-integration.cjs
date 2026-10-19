// Dedicated disposable integration clone. Never connects to a production host.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { randomUUID } = require('node:crypto');
const repo = path.resolve(__dirname, '../..');
const database = 'fullpos_offline_mayoreo144_uat';
const base = 'http://127.0.0.1:46554';
const mode = process.argv[2];
const source = process.argv[3];
assert.ok(source && path.basename(source) === '.env.mayoreo.uat.local');
for (const line of fs.readFileSync(source, 'utf8').split(/\r?\n/)) {
  const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (match) process.env[match[1]] = match[2].replace(/^"|"$/g, '');
}
const target = new URL(process.env.DATABASE_URL);
assert.equal(target.hostname, '127.0.0.1');
assert.equal(target.port, '56549');
assert.equal(target.pathname, '/fullpos_mayoreo_uat');
target.pathname = '/' + database;
Object.assign(process.env, {
  DATABASE_URL: target.href, APP_ENV: 'uat', UAT_LOCAL_ONLY: 'true',
  UAT_EXPECTED_DB_NAME: database, UAT_DB_NAME: database,
  UAT_EXPECTED_DB_PORT: '56549', PORT: '46554',
  RUN_SEED: 'false', RUN_MIGRATIONS: 'false', REDIS_ENABLED: 'false',
  UPLOAD_DIR: path.join(repo, '.uat/integration144/uploads'),
});

async function smoke() {
  const { Client } = require('pg');
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  let token;
  async function request(route, body, statuses = [200, 201], method = 'POST') {
    const response = await fetch(base + route, {
      method, signal: AbortSignal.timeout(30000),
      headers: { 'content-type': 'application/json', 'x-client-device-id': 'integration144',
        ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    const result = await response.json();
    assert.ok(statuses.includes(response.status), `${route}: HTTP ${response.status}, code ${result.code || result.error || 'unknown'}`);
    return result;
  }
  try {
    assert.equal((await db.query('select current_database() as name')).rows[0].name, database);
    const fixtureId = randomUUID();
    const password = randomUUID() + '!Aa1';
    const login = await request('/auth/register-business', {
      firstName: 'Integration', lastName: 'UAT', email: `${fixtureId}@example.test`,
      phone: '8095550000', password, confirmPassword: password,
      commercialName: `Offline Mayoreo UAT ${fixtureId}`, taxId: '121212121',
      businessPhone: '8095551111', address: 'Local disposable UAT', country: 'DO',
    });
    token = login.accessToken;
    assert.ok(token);
    const companyId = login.user.companyId || login.activeCompany.id;
    const authorization = await request('/auth/offline-emergency/authorize', {});
    assert.equal(authorization.companyId, companyId);
    assert.equal(authorization.userId, login.user.id);
    assert.equal(authorization.deviceFingerprint, 'integration144');
    assert.equal(authorization.maxOfflineHours, 48);
    assert.equal(Date.parse(authorization.validUntilUtc) - Date.parse(authorization.serverUtc), 48 * 3600000);
    assert.equal(authorization.capabilities.productPayloadHash, true);
    assert.equal(authorization.capabilities.inventoryPayloadHash, true);
    const cash = await request('/cash/state', null, [200], 'GET');
    let shiftId = cash.activeSession?.shiftId || cash.userOpenShift?.id;
    if (!shiftId) {
      const opened = await request('/cash/sessions/open', { openingAmount: 0, clientSessionId: randomUUID() });
      shiftId = opened.shiftId || opened.id || opened.session?.id;
    }
    assert.ok(shiftId);
    const id = randomUUID();
    const productDto = { operationId: id, nombre: `integration144-${id}`, codigo: id,
      categoria: 'Integration UAT', precio: 100, costo: 40, stock: 0 };
    const products = await Promise.all(Array.from({ length: 5 }, () => request('/products', productDto)));
    assert.equal(new Set(products.map(p => p.id)).size, 1);
    assert.equal(products[0].id, id);
    const entry = { operationId: randomUUID(), delta: 30, reason: 'integration144' };
    await Promise.all(Array.from({ length: 5 }, () => request(`/products/${id}/stock`, entry, [200], 'PATCH')));
    await request('/products', { ...productDto, precio: 101 }, [409]);
    await request(`/products/${id}/stock`, { ...entry, delta: 31 }, [409], 'PATCH');
    const countedConflict = await request(`/products/${id}/stock`, { operationId: randomUUID(), stock: 50,
      expectedCurrentStock: 20, reason: 'integration144 conflict' }, [409], 'PATCH');
    assert.ok(countedConflict.code);
    const saleDto = { clientRequestId: randomUUID(), originCashSessionId: shiftId,
      paymentMethod: 'cash', paymentCashAmount: 400, cashReceived: 400, expectedTotalSold: 400,
      deviceFingerprint: 'integration144', saleOccurredAt: new Date().toISOString(),
      items: [{ productId: id, qty: 4, priceSoldUnit: 100 }] };
    const sales = await Promise.all(Array.from({ length: 5 }, () => request('/sales', saleDto)));
    assert.equal(new Set(sales.map(s => s.id || s.sale?.id)).size, 1);
    await request('/sales', { ...saleDto, expectedTotalSold: 500 }, [409]);
    await request('/products', productDto);
    await request(`/products/${id}/stock`, entry, [200], 'PATCH');
    const product = (await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, id])).rows[0];
    assert.equal(Number(product.stock), 26);
    assert.equal(Number((await db.query('select count(*) from inventory_movements where company_id=$1 and operation_id=$2', [companyId, entry.operationId])).rows[0].count), 1);
    assert.equal(Number((await db.query('select count(*) from "Sale" where company_id=$1 and client_request_id=$2', [companyId, saleDto.clientRequestId])).rows[0].count), 1);
    const legacy = await request('/products', { nombre: `legacy144-${id}`, codigo: `legacy-${id}`, categoria: 'UAT', precio: 100, costo: 40, stock: 0 });
    await request(`/products/${legacy.id}/stock`, { delta: 2, reason: 'legacy online' }, [200], 'PATCH');
    const noTurn = { ...saleDto, clientRequestId: randomUUID(), originCashSessionId: undefined };
    const blocked = await request('/sales', noTurn, [409]);
    assert.equal(blocked.code, 'LEGACY_MISSING_SESSION');
    await request('/settings', { wholesalePriceListsEnabled: true }, [200], 'PATCH');
    const list = await request('/price-lists', { name: 'Integration Mayorista' });
    await request(`/price-lists/${list.id}/rules`, {
      productId: id, mode: 'FIXED_PRICE', fixedPrice: 80, minQuantity: 1,
      tiers: [{ minQuantity: 10, mode: 'FIXED_PRICE', fixedPrice: 70 }],
    });
    const resolved = await request('/price-lists/resolve-line', { productId: id, qty: 15, priceListId: list.id });
    assert.equal(Number(resolved.unitPrice), 70);
    const wholesaleDto = { ...saleDto, clientRequestId: randomUUID(),
      priceListId: list.id, priceListManualOverride: true,
      paymentCashAmount: 1050, cashReceived: 1050, expectedTotalSold: 1050,
      items: [{ productId: id, qty: 15, priceSoldUnit: 70 }] };
    const wholesale = await request('/sales', wholesaleDto);
    assert.equal(wholesale.priceListId, list.id);
    assert.equal(Number(wholesale.totalSold), 1050);
    await request(`/price-lists/${list.id}/rules`, {
      productId: id, mode: 'FIXED_PRICE', fixedPrice: 85, minQuantity: 1,
      tiers: [{ minQuantity: 10, mode: 'FIXED_PRICE', fixedPrice: 75 }],
    });
    const replay = await request('/sales', wholesaleDto);
    assert.equal(replay.id, wholesale.id);
    assert.equal(Number(replay.totalSold), 1050);
    assert.equal(Number((await db.query('select stock from "Product" where company_id=$1 and id=$2', [companyId, id])).rows[0].stock), 11);
    console.log(JSON.stringify({ status: 'PASS', database, grantHours: 48, capabilities: 2,
      concurrentRetries: 5, products: 1, stockEntries: 1, sales: 1, stock: 26,
      legacyOnlinePayload: 'PASS', legacyMissingTurn: 'safe rejection', payloadMismatch: 'PASS',
      wholesaleQuantity15: 1050, wholesaleReplayAfterRuleChange: 'same sale and total' }));
  } finally { await db.end(); }
}

if (mode === 'migrate') {
  const child = spawnSync(process.execPath, [path.join(repo, 'node_modules/prisma/build/index.js'), 'migrate', 'deploy'],
    { cwd: path.join(repo, 'apps/api'), env: process.env, stdio: 'inherit' });
  process.exitCode = child.status ?? 1;
} else if (mode === 'serve') {
  process.chdir(path.join(repo, 'apps/api'));
  require(path.join(repo, 'apps/api/dist/main.js'));
} else if (mode === 'smoke') {
  smoke().catch(error => { console.error(error.message); process.exitCode = 1; });
} else { throw new Error('Use migrate, serve or smoke'); }
