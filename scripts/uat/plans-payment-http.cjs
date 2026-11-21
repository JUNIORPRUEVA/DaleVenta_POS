// Actual HTTP multipart + SQL, exclusively the dedicated synthetic billing DB.
const assert = require('node:assert/strict'), fs = require('node:fs/promises'), crypto = require('node:crypto');
const { PrismaClient } = require('@prisma/client');
const PDFDocument = require('pdfkit');
const { Client } = require('pg');
const db = new PrismaClient({ datasources: { db: { url: 'postgresql://postgres@127.0.0.1:56562/fullpos_plans_payment_20261121' } } });
const base = 'http://127.0.0.1:4018', scenarios = [];
async function request(route, token, body, method = body ? 'POST' : 'GET') {
  const response = await fetch(base + route, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body && !(body instanceof FormData) ? { 'content-type': 'application/json' } : {}) }, ...(body ? { body: body instanceof FormData ? body : JSON.stringify(body) } : {}) });
  return { status: response.status, data: await response.json().catch(() => ({})) };
}
function expect(r, status) { assert.equal(r.status, status, `HTTP ${r.status}: ${r.data.code || r.data.message || ''}`); return r.data; }
async function account(label) {
  const password = crypto.randomBytes(24).toString('base64url') + 'aA1!';
  const email = `plans-${crypto.randomUUID()}@example.test`;
  const result = expect(await request('/auth/register-business', null, { commercialName: `Synthetic plans ${label}`, firstName: 'Synthetic', lastName: 'Plans', email, password, confirmPassword: password, phone: '8095550100' }), 201);
  return { token: result.accessToken, user: result.user, email, password };
}
async function pdf(label) {
  return new Promise(resolve => {
    const doc = new PDFDocument(), chunks = [];
    doc.on('data', b => chunks.push(b)); doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.text(`COMPROBANTE SINTETICO SIN VALIDEZ. NO ES UN PAGO. ${label} ${crypto.randomUUID()}`); doc.end();
  });
}
async function upload(token, orderId, bytes) {
  const body = new FormData(); body.append('file', new Blob([bytes], { type: 'application/pdf' }), 'comprobante-prueba.pdf');
  return request(`/license/orders/${orderId}/evidence`, token, body);
}
async function main() {
  expect(await request('/health'), 200);
  if (process.argv.includes('--cancel-race-only')) { await cancelRace(); return; }
  const a = await account('A'), b = await account('B');
  const plans = expect(await request('/license/plans'), 200).plans; assert.equal(plans.length, 4);
  const plan = plans.find(p => p.code === 'pro'); assert.ok(plan);
  const concurrent = await account('Concurrent');
  const simultaneous = await Promise.all([1, 2, 3].map(() => request('/license/orders', concurrent.token, { planCode: 'pro', months: 3 })));
  const simultaneousOrders = simultaneous.map(r => expect(r, 201));
  assert.equal(new Set(simultaneousOrders.map(o => o.id)).size, 1, 'Simultaneous creation must share one pending order');
  scenarios.push('three simultaneous create requests reuse one pending order');
  const quote = expect(await request('/license/orders/quote?planCode=pro&months=3', a.token), 200);
  const order = expect(await request('/license/orders', a.token, { planCode: 'pro', months: 3 }), 201);
  assert.equal(order.amount, quote.amountDue); assert.equal(order.months, 3);
  assert.equal(expect(await request('/license/orders', a.token, { planCode: 'pro', months: 3 }), 201).id, order.id);
  scenarios.push('catalog and three-month quote/order agree; repeated creation reuses the order');
  const before = await db.company.findUniqueOrThrow({ where: { id: a.user.companyId }, select: { licenseStatus: true, planCode: true, licenseExpiresAt: true, maxUsers: true, maxProducts: true } });
  const bytes = await pdf('valid file, unverified bank payment');
  expect(await upload(b.token, order.id, bytes), 404);
  expect(await upload(null, order.id, bytes), 401);
  expect(await upload(a.token, order.id, Buffer.from('executable renamed as pdf')), 400);
  assert.equal(await db.licensePaymentEvidence.count({ where: { companyId: a.user.companyId, orderId: order.id } }), 0);
  scenarios.push('foreign company, absent authentication and false file signature rejected without evidence writes');
  const result = expect(await upload(a.token, order.id, bytes), 201);
  assert.equal(result.ok, true); assert.equal(result.activated, false); assert.equal(result.order.id, order.id);
  assert.equal(result.order.status, 'EVIDENCE_RECEIVED'); assert.ok(result.evidence.id);
  assert.deepEqual(await db.company.findUniqueOrThrow({ where: { id: a.user.companyId }, select: { licenseStatus: true, planCode: true, licenseExpiresAt: true, maxUsers: true, maxProducts: true } }), before);
  expect(await upload(a.token, order.id, bytes), 409);
  assert.equal(await db.licensePaymentEvidence.count({ where: { companyId: a.user.companyId, orderId: order.id } }), 1);
  scenarios.push('real PDF stored for review; no unverified activation; retry cannot duplicate evidence');
  const expired = expect(await request('/license/orders', b.token, { planCode: 'pro', months: 1 }), 201);
  await db.licensePaymentOrder.updateMany({ where: { id: expired.id, companyId: b.user.companyId }, data: { expiresAt: new Date(Date.now() - 1000) } });
  expect(await upload(b.token, expired.id, await pdf('expired order')), 409);
  assert.equal(await db.licensePaymentEvidence.count({ where: { companyId: b.user.companyId, orderId: expired.id } }), 0);
  scenarios.push('an expired order cannot accept a new receipt even before a history refresh');
  const list = expect(await request('/license/orders', a.token), 200).orders;
  assert.equal(list.find(o => o.id === order.id).evidences?.[0]?.id, result.evidence.id, 'History must retain evidence metadata');
  const download = await fetch(`${base}/license/orders/${order.id}/evidence/${result.evidence.id}`, { headers: { authorization: `Bearer ${a.token}` } });
  assert.equal(download.status, 200); assert.deepEqual(Buffer.from(await download.arrayBuffer()), bytes);
  assert.equal((await fetch(`${base}/license/orders/${order.id}/evidence/${result.evidence.id}`, { headers: { authorization: `Bearer ${b.token}` } })).status, 404);
  scenarios.push('history exposes the receipt metadata; authenticated owner downloads original bytes; foreign company cannot');
  await cancelRace();
  const native = await account('Native');
  const nativeOrder = expect(await request('/license/orders', native.token, { planCode: 'pro', months: 3 }), 201);
  const proof = await pdf('native Windows upload');
  await fs.writeFile('.uat/plans-payment/native-proof.pdf', proof);
  await fs.writeFile('.uat/plans-payment/native-fixture.json', JSON.stringify({ api: base, ...native, orderId: nativeOrder.id, planCode: 'pro' }), { mode: 0o600 });
  await fs.writeFile('.uat/plans-payment/http-result.json', JSON.stringify({ result: 'PASS', scenarios, outboundPayment: false, automaticActivation: false }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', scenarios }));
}
async function cancelRace() {
  const owner = await account('Receipt versus cancel');
  const order = expect(await request('/license/orders', owner.token, { planCode: 'pro', months: 3 }), 201);
  const marker = `uat_plans_receipt_${Date.now()}`;
  const client = new Client({ host: '127.0.0.1', port: 56562, user: 'postgres', database: 'fullpos_plans_payment_20261121' });
  await client.connect();
  await client.query(`CREATE FUNCTION ${marker}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.order_id='${order.id}'::uuid THEN PERFORM pg_advisory_xact_lock(19787,24113); END IF; RETURN NEW; END $$`);
  await client.query(`CREATE TRIGGER ${marker} BEFORE INSERT ON license_payment_evidence FOR EACH ROW EXECUTE FUNCTION ${marker}()`);
  let sending, cancelling;
  try {
    await client.query('SELECT pg_advisory_lock(19787,24113)');
    sending = upload(owner.token, order.id, await pdf('concurrent upload and cancel'));
    let waiting = false;
    for (let i = 0; i < 40; i++) {
      const rows = await db.$queryRaw`SELECT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND classid=19787::oid AND objid=24113::oid AND NOT granted) AS waiting`;
      if (rows[0].waiting) { waiting = true; break; }
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert.equal(waiting, true, 'Real upload must reach its locked receipt transaction');
    cancelling = request(`/license/orders/${order.id}/cancel`, owner.token, {});
    await new Promise(resolve => setTimeout(resolve, 200));
    await client.query('SELECT pg_advisory_unlock(19787,24113)');
    expect(await sending, 201); expect(await cancelling, 409);
    const persisted = await db.licensePaymentOrder.findFirstOrThrow({ where: { companyId: owner.user.companyId, id: order.id }, include: { evidences: true } });
    assert.equal(persisted.status, 'EVIDENCE_RECEIVED'); assert.equal(persisted.evidences.length, 1);
    scenarios.push('cancel waits for the real upload transaction and cannot overwrite the received receipt');
  } finally {
    await client.query('SELECT pg_advisory_unlock(19787,24113)').catch(() => {});
    await Promise.allSettled([sending, cancelling].filter(Boolean));
    await client.query(`DROP TRIGGER ${marker} ON license_payment_evidence`);
    await client.query(`DROP FUNCTION ${marker}()`); await client.end();
  }
}
main().catch(e => { console.error(e.name + ': ' + e.message); process.exitCode = 1; }).finally(() => db.$disconnect());
