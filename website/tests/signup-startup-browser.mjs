// Real browser + built Astro/Flutter + real isolated local API/PostgreSQL.
// Run explicitly after building both sites and starting a disposable local API.
// PLAYWRIGHT_MODULE may point to an installed Playwright entry point.
import assert from 'node:assert/strict';
import { createServer, request as httpRequest } from 'node:http';
import { readFile, stat, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
const root = fileURLToPath(new URL('../../', import.meta.url));
const app = resolve(root, 'apps/fulltech_app/build/web');
const site = resolve(root, 'website/dist');
const evidence = resolve(root, '.uat/signup-startup');
await mkdir(evidence, { recursive: true });
const base = 'http://127.0.0.1:14974';
const api = 'http://127.0.0.1:14973';
const records = [];
const diagnostics = [];
const counts = new Map();
function databaseSnapshot() {
  const result = spawnSync('docker', ['exec', 'fullpos_signup_startup_20261127',
    'psql', '-U', 'postgres', '-d', 'fullpos_signup_startup_local', '-t', '-A', '-c',
    `SELECT json_build_object(
      'users', (SELECT count(*) FROM users),
      'companies', (SELECT count(*) FROM companies),
      'members', (SELECT count(*) FROM company_members),
      'duplicateEmails', (SELECT count(*) FROM (SELECT email FROM users GROUP BY email HAVING count(*)>1) d),
      'tickets', (SELECT count(*) FROM session_handoff_tickets),
      'usedTickets', (SELECT count(*) FROM session_handoff_tickets WHERE used_at IS NOT NULL),
      'sales', (SELECT count(*) FROM "Sale"),
      'cashMovements', (SELECT count(*) FROM cash_movements));`],
    { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 0, 'Isolated database snapshot must succeed');
  return JSON.parse(result.stdout.trim());
}
const contentTypes = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json',
  '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };
const server = createServer(async (req, res) => {
  const path = new URL(req.url, base).pathname;
  if (path === '/env.js') {
    res.writeHead(200, { 'Content-Type': 'text/javascript', 'Cache-Control': 'no-store' });
    res.end(`window.API_BASE_URL=${JSON.stringify(base + '/api')};window.API_TIMEOUT_MS="15000";window.META_PIXEL_ID="";window.MARKETING_ANALYTICS_DEBUG="";`);
    return;
  }
  if (path.startsWith('/api/')) {
    const key = `${req.method} ${path}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
    const upstream = httpRequest(`${api}${req.url.slice(4)}`, {
      method: req.method, headers: { ...req.headers, host: '127.0.0.1:14973' },
    }, response => { res.writeHead(response.statusCode, response.headers); response.pipe(res); });
    upstream.on('error', () => { res.writeHead(502); res.end('{}'); });
    res.on('close', () => upstream.destroy());
    req.pipe(upstream);
    return;
  }
  try {
    let file;
    if (['/home', '/home/'].includes(path)) file = resolve(app, 'index.html');
    else {
      file = resolve(site, `.${path}`);
      if (!file.startsWith(site)) throw new Error('outside site');
      try { if ((await stat(file)).isDirectory()) file = resolve(file, 'index.html'); }
      catch { file = extname(path) ? resolve(app, `.${path}`) : resolve(app, 'index.html'); }
      if (!file.startsWith(site) && !file.startsWith(app)) throw new Error('outside builds');
    }
    const data = await readFile(file);
    res.writeHead(200, { 'Content-Type': contentTypes[extname(file)] ?? 'application/octet-stream',
      'Cache-Control': 'no-store' });
    res.end(data);
  } catch { res.writeHead(404); res.end('Not found'); }
});
await new Promise(resolve => server.listen(14974, '127.0.0.1', resolve));
const browser = await chromium.launch({ headless: true });
const contexts = [];
async function context() {
  const ctx = await browser.newContext({ locale: 'es-DO', serviceWorkers: 'block' });
  contexts.push(ctx);
  // Never let a local acceptance test contact a remote service.
  await ctx.route('**/*', route => {
    const url = new URL(route.request().url());
    if (['http:', 'https:'].includes(url.protocol) && url.hostname !== '127.0.0.1') return route.abort();
    return route.continue();
  });
  return ctx;
}
async function json(path, { token, body } = {}) {
  const response = await fetch(`${api}${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(10000),
  });
  assert.ok(response.ok, `Local API ${path}: HTTP ${response.status}`);
  return response.json();
}
async function newTicket(token) {
  return (await json('/auth/handoff/ticket', { token, body: { platform: 'web' } })).ticket;
}
async function stored(page) {
  return page.evaluate(() => ({
    access: JSON.parse(localStorage.getItem('flutter.uat.accessToken') ?? 'null'),
    user: JSON.parse(JSON.parse(localStorage.getItem('flutter.uat.authUserSnapshot') ?? '"null"')),
  }));
}
async function recovered(page) {
  await page.waitForURL('**/login?access=retry', { timeout: 40000 });
  assert.equal(await page.locator('[data-form-alert]').isVisible(), true);
  assert.match(await page.locator('[data-form-alert]').innerText(), /Tu cuenta sigue disponible/);
  const saved = await stored(page);
  assert.equal(saved.access, null);
  assert.equal(saved.user, null);
}

try {
  const before = databaseSnapshot();
  assert.equal((await fetch(`${api}/health`)).status, 200);
  const email = `signup.startup.${Date.now()}@example.invalid`;
  const password = `Qa!${randomBytes(18).toString('hex')}`;
  const ctx = await context();
  const page = await ctx.newPage();
  page.on('pageerror', error => diagnostics.push({ event: 'pageerror', name: error.name,
    message: error.message.replace(/https?:\/\/[^\s]+/g, '[url]').slice(0, 500) }));
  page.on('response', response => { if (response.status() >= 400) diagnostics.push({
    event: 'response', path: new URL(response.url()).pathname, status: response.status() }); });
  page.on('requestfailed', request => diagnostics.push({ event: 'requestfailed', path: new URL(request.url()).pathname }));
  page.on('console', message => { if (message.type() === 'error' || message.type() === 'warning' ||
    /\[AppError\]|^message:|^type:|^context:|Unsupported|fromEnvironment/.test(message.text())) diagnostics.push({
    event: 'console', message: message.text().replace(/https?:\/\/[^\s]+/g, '[url]')
      .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*/g, '[token]').slice(0, 1800) }); });
  const errors = [];
  page.on('pageerror', error => errors.push(error.name));
  await page.goto(`${base}/registro/`);
  await page.locator('[name=firstName]').fill('QA Registro');
  await page.locator('[name=email]').fill(email);
  await page.locator('[name=password]').fill(password);
  await page.locator('[data-submit]').click();
  await page.waitForURL(url => url.pathname.replace(/\/$/, '') === '/registro/negocio');
  await page.locator('[name=commercialName]').fill('QA Arranque Local');
  await page.locator('[name=phone]').fill('8095550100');
  await page.locator('[data-niche-open]').click();
  await page.locator('[data-niche-option="Ferretería"]').click();
  const started = Date.now();
  const companyLoaded = page.waitForResponse(response =>
    new URL(response.url()).pathname === '/api/settings' && response.status() === 200, { timeout: 45000 });
  await page.locator('[data-submit]').dblclick();
  await page.waitForURL(url => url.pathname === '/home', { timeout: 45000 });
  await Promise.race([
    page.locator('#app-loader').waitFor({ state: 'detached', timeout: 45000 }),
    page.locator('#startup-recovery').waitFor({ state: 'visible', timeout: 45000 })
      .then(() => { throw new Error('Startup recovery appeared; see browser-diagnostics.json'); }),
  ]);
  const identity = await stored(page);
  assert.ok(identity.access && identity.user);
  assert.equal(identity.user.email, email);
  const me = await json('/auth/me', { token: identity.access });
  assert.equal(me.user?.id ?? me.id, identity.user.id);
  assert.equal(counts.get('POST /api/auth/register-business'), 1);
  assert.equal(counts.get('POST /api/auth/handoff/exchange'), 1);
  assert.equal(new URL(page.url()).searchParams.has('handoff'), false);
  await companyLoaded;
  const semantics = page.locator('flt-semantics-placeholder');
  if (await semantics.count()) await semantics.dispatchEvent('click');
  await page.getByText('Bienvenido a FullPOS', { exact: true }).waitFor({ timeout: 30000 });
  await page.screenshot({ path: resolve(evidence, '01-registration-entry.png') });
  records.push({ case: 'full-form registration, double submit, durable matching identity, first frame',
    result: 'PASS', elapsedMs: Date.now() - started, pageErrorNames: errors });

  // Reload with the same durable identity: no one-use ticket is sent again.
  await page.reload();
  await page.locator('#app-loader').waitFor({ state: 'detached', timeout: 45000 });
  assert.equal((await stored(page)).user.id, identity.user.id);
  assert.equal(counts.get('POST /api/auth/handoff/exchange'), 1);
  records.push({ case: 'reload restores same identity without replaying handoff', result: 'PASS' });

  const other = await json('/auth/register-business', { body: {
    firstName: 'QA Otra Empresa', commercialName: 'QA Aislamiento Registro',
    email: `signup.other.${Date.now()}@example.invalid`, password, confirmPassword: password,
    phone: '8095550101', businessType: 'Ferretería',
  } });
  const nextTicket = await newTicket(other.accessToken);
  await page.goto(`${base}/home?handoff=${encodeURIComponent(nextTicket)}`);
  await page.locator('#app-loader').waitFor({ state: 'detached', timeout: 45000 });
  const next = await stored(page);
  assert.notEqual(next.user.id, identity.user.id);
  assert.notEqual(next.user.companyId, identity.user.companyId);
  assert.equal(next.user.id, other.user.id);
  assert.equal(next.user.companyId, other.activeCompany.id);
  records.push({ case: 'a new handoff replaces the old user and company together', result: 'PASS' });

  for (const mode of ['expired', '503', 'timeout', 'blocked-storage']) {
    const c = await context();
    const p = await c.newPage();
    const ticket = mode === 'expired' ? 'expired-local-fixture' : await newTicket(identity.access);
    let attempts = 0;
    if (mode === '503' || mode === 'timeout') {
      await c.route('**/api/auth/handoff/exchange', async route => {
        attempts++;
        if (mode === '503') return route.fulfill({ status: 503, contentType: 'application/json', body: '{}' });
        await new Promise(resolve => setTimeout(resolve, 27000));
        try { await route.continue(); } catch { /* Page has left the expired attempt. */ }
      });
    }
    if (mode === 'blocked-storage') await c.addInitScript(() => {
      Storage.prototype.setItem = () => { throw new DOMException('Blocked', 'SecurityError'); };
    });
    await p.goto(`${base}/home?handoff=${encodeURIComponent(ticket)}`);
    await recovered(p);
    if (mode === '503' || mode === 'timeout') assert.equal(attempts, 1);
    await p.screenshot({ path: resolve(evidence, `recovery-${mode}.png`) });
    records.push({ case: `${mode}: clear recovery, no partial identity or automatic replay`, result: 'PASS' });
    await c.close();
  }

  for (const mode of ['bootstrap-404', 'engine-404', 'download-stalled']) {
    const c = await context();
    const p = await c.newPage();
    if (mode === 'bootstrap-404') await c.route('**/flutter_bootstrap.js', route => route.fulfill({ status: 404, body: '' }));
    if (mode === 'engine-404') await c.route('**/canvaskit/**', route => route.fulfill({ status: 404, body: '' }));
    if (mode === 'download-stalled') {
      await p.clock.install();
      await c.route('**/flutter_bootstrap.js', async () => { await new Promise(() => {}); });
    }
    await p.goto(`${base}/home`, { waitUntil: 'domcontentloaded' });
    if (mode === 'download-stalled') await p.clock.fastForward(46000);
    await p.locator('#startup-recovery').waitFor({ state: 'visible', timeout: 50000 });
    assert.equal(await p.locator('#startup-recovery a').getAttribute('href'), '/login?access=retry');
    await p.screenshot({ path: resolve(evidence, `startup-${mode}.png`) });
    records.push({ case: `${mode}: startup cover replaced by actionable recovery`, result: 'PASS' });
    await c.close();
  }
  const after = databaseSnapshot();
  assert.equal(after.users, before.users + 2);
  assert.equal(after.companies, before.companies + 2);
  assert.equal(after.members, before.members + 2);
  assert.equal(after.duplicateEmails, 0);
  assert.equal(after.sales, before.sales);
  assert.equal(after.cashMovements, before.cashMovements);
  records.push({ case: 'persisted data: exactly two companies/users, no duplicates or financial operations',
    result: 'PASS', before, after });
  console.log(JSON.stringify({ results: records, productionContacted: false }, null, 2));
} finally {
  if (!records.length && contexts[0]?.pages()[0]) {
    await contexts[0].pages()[0].screenshot({ path: resolve(evidence, 'first-attempt.png') }).catch(() => {});
    diagnostics.push(await contexts[0].pages()[0].evaluate(() => ({
      event: 'engine-state', canvasKit: !!window.flutterCanvasKit,
      stage: window.fullposWebStartupStage,
      resources: performance.getEntriesByType('resource').map(entry => ({
        path: new URL(entry.name).pathname, ms: Math.round(entry.duration), size: entry.decodedBodySize,
      })),
    })).catch(() => ({ event: 'engine-state-unavailable' })));
  }
  await writeFile(resolve(evidence, 'browser-results.json'), JSON.stringify(records, null, 2));
  await writeFile(resolve(evidence, 'browser-diagnostics.json'), JSON.stringify(diagnostics, null, 2));
  await browser.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
