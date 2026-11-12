import { afterEach, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  saveSessionFromAuth, readSession, getAccessToken, clearSession,
  SiteSessionStorageError,
} from '../src/scripts/site-session.ts';

const originalFetch = globalThis.fetch;
let values;
const auth = () => ({
  accessToken: 'test-access', refreshToken: 'test-refresh',
  user: { email: 'qa@example.invalid' }, activeCompany: { name: 'QA' },
  requiresOnboarding: true,
});

beforeEach(() => {
  values = new Map();
  Object.defineProperty(globalThis, 'sessionStorage', { configurable: true, value: {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  } });
});
afterEach(() => { globalThis.fetch = originalFetch; delete globalThis.sessionStorage; });

test('persists a complete session across page reads and clears it on logout', () => {
  const saved = saveSessionFromAuth(auth());
  assert.deepEqual(readSession(), saved);
  clearSession();
  assert.equal(readSession(), null);
});

test('rejects an incomplete API response instead of storing an unusable session', () => {
  assert.throws(() => saveSessionFromAuth({ accessToken: 'test-access' }));
  assert.equal(readSession(), null);
});

test('reports blocked browser storage and removes any stale session', () => {
  saveSessionFromAuth(auth());
  globalThis.sessionStorage.setItem = () => { throw new Error('blocked'); };
  assert.throws(() => saveSessionFromAuth(auth()), SiteSessionStorageError);
  assert.equal(readSession(), null);
});

test('detects storage that silently discards writes', () => {
  globalThis.sessionStorage.setItem = () => {};
  assert.throws(() => saveSessionFromAuth(auth()), SiteSessionStorageError);
});

test('a valid access token does not trigger refresh', async () => {
  saveSessionFromAuth(auth());
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    assert.equal(url, '/api/auth/me');
    return new Response('{}', { status: 200 });
  };
  assert.equal(await getAccessToken('/api'), 'test-access');
  assert.equal(calls, 1);
});

test('refresh rotates tokens and preserves company/onboarding metadata', async () => {
  saveSessionFromAuth(auth());
  globalThis.fetch = async (url, options) => {
    if (url.endsWith('/me')) return new Response('{}', { status: 401 });
    assert.equal(url, '/api/auth/refresh');
    assert.equal(JSON.parse(options.body).refreshToken, 'test-refresh');
    return Response.json({ accessToken: 'test-access-next', refreshToken: 'test-refresh-next' });
  };
  assert.equal(await getAccessToken('/api'), 'test-access-next');
  assert.equal(readSession().companyName, 'QA');
  assert.equal(readSession().email, 'qa@example.invalid');
  assert.equal(readSession().requiresOnboarding, true);
  assert.equal(readSession().refreshToken, 'test-refresh-next');
});

test('rejected refresh clears expired credentials', async () => {
  saveSessionFromAuth(auth());
  globalThis.fetch = async () => new Response('{}', { status: 401 });
  assert.equal(await getAccessToken('/api'), null);
  assert.equal(readSession(), null);
});

test('a server outage does not erase an otherwise usable access token', async () => {
  saveSessionFromAuth(auth());
  globalThis.fetch = async () => new Response('{}', { status: 503 });
  assert.equal(await getAccessToken('/api'), 'test-access');
  assert.notEqual(readSession(), null);
});
