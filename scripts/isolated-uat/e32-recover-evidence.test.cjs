const { test } = require('node:test');
const assert = require('node:assert/strict');
const { getOnce, assess, endpoint } = require('./e32-recover-evidence.cjs');
const schema = require('../../apps/api/dist/ecf/alanube/contracts/alanube-e32-query.generated.js').ALANUBE_E32_QUERY.checkinvoices.responses['200'];
const fixture = () => ({ id: '01M4Y3DEPXXG27G8BNQGMNQ04B', documentNumber: 'E320009805001', companyIdentification: '132109122',
  status: 'REGISTERED', legalStatus: 'ACCEPTED', sequenceConsumed: true });
test('single mocked GET uses only exact Sandbox resource and disables redirects', async () => {
  let calls = 0;
  const result = await getOnce(async (url, options) => {
    calls++; assert.equal(url, endpoint); assert.equal(options.method, 'GET'); assert.equal(options.redirect, 'manual');
    assert.equal(options.body, undefined); return new Response(JSON.stringify(fixture()), { status: 200 });
  }, 'synthetic-token');
  assert.equal(calls, 1); assert.equal(result.httpStatus, 200);
  assert.equal(assess(200, JSON.parse(result.raw), schema).sufficientForProviderReview, true);
});
test('wrong identity, emitter, missing sequence and strict schema failures cannot reconcile', () => {
  for (const change of [{ id: '01FVJ1528AQRBC7D6K2TGVE5S5' }, { documentNumber: 'E320009805002' },
    { companyIdentification: '101000001' }, { sequenceConsumed: undefined }, { sequenceConsumed: false },
    { stampDate: null }, { legalStatus: 'REJECTED' }])
    assert.equal(assess(200, { ...fixture(), ...change }, schema).sufficientForProviderReview, false);
  assert.equal(assess(200, {}, schema).sufficientForProviderReview, false);
  assert.equal(assess(201, fixture(), schema).sufficientForProviderReview, false);
});
test('redirect is recorded without following it', async () => {
  let calls = 0;
  const result = await getOnce(async () => { calls++; return new Response(null, { status: 302, headers: { location: 'https://production.invalid' } }); }, 'synthetic-token');
  assert.equal(calls, 1); assert.equal(result.failure, 'REDIRECT_BLOCKED'); assert.equal(result.httpStatus, 302);
});
test('network error never retries and oversized body is rejected', async () => {
  let calls = 0;
  const result = await getOnce(async () => { calls++; throw Error('synthetic network error'); }, 'synthetic-token');
  assert.equal(calls, 1); assert.equal(result.failure, 'NETWORK_OR_BODY_ERROR');
  assert.equal((await getOnce(async () => new Response('x'.repeat(65537), { status: 200 }), 'synthetic-token')).raw, null);
});
test('schema failure diagnostics retain exact field without logging response values', () => {
  const result = assess(200, { ...fixture(), stampDate: null, privateSecret: 'synthetic-private-marker' }, schema);
  assert.deepEqual(result.schemaErrors, [{ path: '/stampDate', keyword: 'type' }]);
  assert.equal(JSON.stringify(result).includes('synthetic-private-marker'), false);
});
