// Run against the combined image and an isolated local/UAT API. No production.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';

const base = process.env.PUBLIC_WEB_TEST_URL ?? 'http://127.0.0.1:4016';
assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(new URL(base).hostname),
  'This test creates disposable accounts and only permits localhost.');
const results = [];
async function request(path, { token, body, method = body ? 'POST' : 'GET' } = {}) {
  const response = await fetch(`${base}/api${path}`, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: response.status, data: await response.json() };
}
const password = randomBytes(24).toString('base64url');
const email = `astro.qa.${Date.now()}@example.invalid`;
const payload = { firstName: 'QA Astro', commercialName: 'QA Astro Local',
  businessType: 'Ferretería', phone: '8095550100', email, password,
  confirmPassword: password };

assert.equal((await request('/health')).status, 200);
assert.equal((await request('/auth/me')).status, 401);
results.push('health and protected API proxy');
const registration = await request('/auth/register-business', { body: payload });
assert.equal(registration.status, 201);
assert.ok(registration.data.accessToken && registration.data.refreshToken);
assert.equal(registration.data.activeMembership.role, 'OWNER');
assert.equal(registration.data.requiresOnboarding, true);
const companyId = registration.data.activeCompany.id;
results.push('minimal registration creates company + OWNER + onboarding session');
assert.equal((await request('/auth/register-business', { body: payload })).status, 409);
results.push('duplicate email rejected without a second account');
const login = await request('/auth/login', { body: { email, password } });
assert.equal(login.status, 201);
assert.equal(login.data.activeCompany.id, companyId);
assert.equal((await request('/auth/login', { body: { email, password: password + 'x' } })).status, 401);
results.push('existing account login and invalid credentials');
const token = login.data.accessToken;
const ticket = await request('/auth/handoff/ticket', { token, body: { platform: 'web' } });
assert.equal(ticket.status, 201);
assert.equal(ticket.data.expiresIn, 120);
const exchanges = await Promise.all([1, 2].map(() =>
  request('/auth/handoff/exchange', { body: { ticket: ticket.data.ticket } })));
assert.deepEqual(exchanges.map((x) => x.status).sort(), [200, 401]);
const active = exchanges.find((x) => x.status === 200).data;
assert.equal(active.activeCompany.id, companyId);
assert.equal(active.user.email, email);
assert.ok(active.accessToken && active.refreshToken);
assert.equal((await request('/auth/handoff/exchange', { body: { ticket: ticket.data.ticket } })).status, 401);
assert.equal((await request('/auth/handoff/exchange', { body: { ticket: 'not-a-real-ticket' } })).status, 401);
assert.equal((await request('/auth/me', { token: active.accessToken })).status, 200);
results.push('handoff consumes once under concurrent exchange and preserves tenant');
const welcome = await request('/onboarding/welcome', { token: active.accessToken });
assert.equal(welcome.status, 200);
const activation = await request('/onboarding/activation', { token: active.accessToken });
assert.equal(activation.status, 200);
results.push('new company welcome and activation APIs are available');

for (const path of ['/', '/login', '/registro', '/registro/negocio', '/preparando', '/recuperar']) {
  const r = await fetch(base + path, { headers: { 'Accept-Encoding': 'br' } });
  assert.equal(r.status, 200, path);
  const html = await r.text();
  assert.ok(!html.includes('flutter_bootstrap.js'), `${path} must serve Astro`);
  assert.ok(html.includes('/_astro/'), `${path} must contain Astro assets`);
}
const preparing = await (await fetch(base + '/preparando')).text();
assert.ok(preparing.includes('data-app-url="/home"'));
for (const path of ['/home', '/cotizaciones', '/reset-password?token=qa-placeholder', '/ecf']) {
  const r = await fetch(base + path);
  assert.equal(r.status, 200, path);
  assert.ok((await r.text()).includes('flutter_bootstrap.js'), `${path} must keep Flutter`);
}
const manifest = await (await fetch(base + '/manifest.json')).json();
assert.equal(manifest.start_url, './home');
results.push('Astro public routes, Brotli negotiation, Flutter routes and PWA entry');
console.log(JSON.stringify({ passed: results.length, checks: results }, null, 2));
