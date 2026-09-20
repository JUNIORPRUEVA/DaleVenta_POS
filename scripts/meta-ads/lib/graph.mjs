/**
 * Meta Graph / Marketing API client for the FullPOS campaign migration.
 *
 * Design rules (non negotiable):
 *  - Zero third-party dependencies: only node built-ins + the official Meta host.
 *  - Secrets are read from disk into memory and NEVER printed, logged, serialized
 *    or persisted. Every string that leaves this module goes through the redactor.
 *  - `appsecret_proof` is computed locally (HMAC-SHA256 of the access token with
 *    the app secret) so server-side calls are not rejected as insecure.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(fileURLToPath(new URL('../../../', import.meta.url)));
export const DEFAULT_ENV_FILE = path.join(ROOT, 'apps', 'api', '.env');
export const OUT_DIR = path.join(ROOT, 'scripts', 'meta-ads', 'out');
export const LOG_DIR = path.join(OUT_DIR, 'logs');
export const API_HOST = 'https://graph.facebook.com';

export const SECRET_KEYS = ['META_ACCESS_TOKEN', 'META_APP_ID', 'META_APP_SECRET'];

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Meta throttles per ad account; a small global gap avoids self-inflicted 17s. */
const MIN_INTERVAL_MS = Number(process.env.META_ADS_MIN_INTERVAL_MS ?? 2500);
let lastCallAt = 0;
async function throttle() {
  const wait = MIN_INTERVAL_MS - (Date.now() - lastCallAt);
  if (wait > 0) await sleep(wait);
  lastCallAt = Date.now();
}

/* ------------------------------------------------------------------ */
/* secrets                                                             */
/* ------------------------------------------------------------------ */

/** Minimal KEY=VALUE parser. Never logs nor returns anything but the parsed map. */
export function loadSecrets(envFile = DEFAULT_ENV_FILE) {
  if (!fs.existsSync(envFile)) {
    throw new Error(`Env file not found: ${path.relative(ROOT, envFile)}`);
  }
  const raw = fs.readFileSync(envFile, 'utf8');
  const map = {};
  for (const line of raw.split(/\r?\n/)) {
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    let value = m[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    map[m[1]] = value;
  }
  // Process environment wins when present, so the caller can override the file.
  for (const key of SECRET_KEYS) {
    if (process.env[key]) map[key] = process.env[key];
  }
  return map;
}

/** PRESENT / MISSING report only. Values are never returned to a caller. */
export function envPresence(secrets) {
  return Object.fromEntries(
    SECRET_KEYS.map((k) => [k, secrets[k] ? `PRESENT (${secrets[k].length} chars)` : 'MISSING']),
  );
}

/* ------------------------------------------------------------------ */
/* redaction                                                           */
/* ------------------------------------------------------------------ */

export function makeRedactor(secrets = {}) {
  const literals = SECRET_KEYS.map((k) => secrets[k]).filter((v) => typeof v === 'string' && v.length >= 6);
  return function redact(input) {
    let s = typeof input === 'string' ? input : String(input);
    for (const literal of literals) s = s.split(literal).join('[REDACTED]');
    // Query strings / form bodies.
    s = s.replace(/(?<![A-Za-z0-9_])(access_token|appsecret_proof|app_secret|client_secret|input_token)=[^&\s"']+/gi, '$1=[REDACTED]');
    // JSON / object dumps. The lookbehind keeps keys such as META_ACCESS_TOKEN intact.
    s = s.replace(/"(?<![A-Za-z0-9_])((?:access_token|appsecret_proof|app_secret|client_secret|input_token))"\s*:\s*"[^"]*"/gi, '"$1": "[REDACTED]"');
    s = s.replace(/(?<![A-Za-z0-9_])((?:access_token|appsecret_proof|app_secret|client_secret|input_token))\s*:\s*"?[A-Za-z0-9._-]{12,}"?/gi, '$1: [REDACTED]');
    s = s.replace(/EAA[A-Za-z0-9_-]{10,}/g, '[REDACTED_TOKEN]');
    s = s.replace(/Bearer\s+[A-Za-z0-9._-]{10,}/gi, 'Bearer [REDACTED]');
    return s;
  };
}

/* ------------------------------------------------------------------ */
/* logger                                                              */
/* ------------------------------------------------------------------ */

export class Logger {
  constructor(redact, name = 'meta') {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    this.redact = redact;
    this.file = path.join(LOG_DIR, `${name}.log`);
    this.echo = process.env.META_ADS_QUIET !== '1';
  }

  #emit(level, message, data) {
    let line = `[${new Date().toISOString()}] ${level} ${message}`;
    if (data !== undefined) {
      let serialized;
      try {
        serialized = JSON.stringify(data);
      } catch {
        serialized = String(data);
      }
      line += ` ${serialized}`;
    }
    line = this.redact(line);
    fs.appendFileSync(this.file, `${line}\n`, 'utf8');
    if (this.echo) process.stdout.write(`${line}\n`);
    return line;
  }

  info(message, data) {
    return this.#emit('INFO ', message, data);
  }

  warn(message, data) {
    return this.#emit('WARN ', message, data);
  }

  error(message, data) {
    return this.#emit('ERROR', message, data);
  }

  step(message, data) {
    return this.#emit('STEP ', message, data);
  }

  /** Persists an artifact. The serialized payload is redacted before writing. */
  writeJson(name, payload) {
    fs.mkdirSync(OUT_DIR, { recursive: true });
    const target = path.join(OUT_DIR, name);
    fs.writeFileSync(target, `${this.redact(JSON.stringify(payload, null, 2))}\n`, 'utf8');
    this.info(`artifact written: out/${name}`);
    return target;
  }
}

export function readJson(name) {
  const target = path.join(OUT_DIR, name);
  if (!fs.existsSync(target)) return null;
  return JSON.parse(fs.readFileSync(target, 'utf8'));
}

/* ------------------------------------------------------------------ */
/* errors + low level transport                                        */
/* ------------------------------------------------------------------ */

export class GraphError extends Error {
  constructor(payload, { status, method, endpoint, version }) {
    const e = payload?.error ?? {};
    super(e.error_user_msg || e.message || `Graph API error (HTTP ${status})`);
    this.name = 'GraphError';
    this.code = e.code;
    this.subcode = e.error_subcode;
    this.type = e.type;
    this.fbtrace = e.fbtrace_id;
    this.userTitle = e.error_user_title;
    this.userMsg = e.error_user_msg;
    this.errorData = e.error_data;
    this.blameFieldSpecs = e.error_data?.blame_field_specs;
    this.status = status;
    this.method = method;
    this.endpoint = `/${version}/${endpoint}`;
  }

  get isTransient() {
    return [1, 2, 4, 32, 341, 613].includes(Number(this.code));
  }

  /** Account-level throttling: Meta asks to wait, not to retry immediately. */
  get isRateLimited() {
    return [17, 80004, 80005].includes(Number(this.code));
  }

  /** A field/parameter complaint is the only case where narrowing is meaningful. */
  get isFieldError() {
    return /nonexisting field|Invalid parameter|does not exist|Unknown path components/i.test(String(this.message));
  }

  toJSON() {
    return {
      message: this.message,
      type: this.type,
      code: this.code,
      error_subcode: this.subcode,
      error_user_title: this.userTitle,
      error_user_msg: this.userMsg,
      error_data: this.errorData,
      http_status: this.status,
      request: `${this.method} ${this.endpoint}`,
      fbtrace_id: this.fbtrace,
    };
  }
}

/**
 * Single transport primitive. `params` objects/arrays are JSON encoded, which is
 * what the Marketing API expects for `targeting`, `promoted_object`, `filtering`, ...
 */
export async function callGraph({
  version,
  method = 'GET',
  endpoint,
  params = {},
  token,
  accessTokenParam = true,
  proof,
  redact = (s) => s,
  retries = 3,
}) {  const clean = String(endpoint).replace(/^\/+/, '');
  const url = new URL(`${API_HOST}/${version}/${clean}`);
  const encode = (v) => (typeof v === 'string' ? v : JSON.stringify(v));
  const writableParams = Object.entries(params).filter(([, v]) => v !== undefined && v !== null);

  const init = { method, headers: {} };
  if (method === 'POST') {
    // Params travel in the body; objects/arrays are JSON encoded as Meta expects.
    const body = new URLSearchParams();
    if (accessTokenParam && token) body.set('access_token', token);
    if (proof) body.set('appsecret_proof', proof);
    for (const [k, v] of writableParams) body.set(k, encode(v));
    init.body = body;
  } else {
    for (const [k, v] of writableParams) url.searchParams.set(k, encode(v));
    if (accessTokenParam && token) url.searchParams.set('access_token', token);
    if (proof) url.searchParams.set('appsecret_proof', proof);
  }

  let attempt = 0;
  let rateLimitWaits = 0;
  for (;;) {
    attempt += 1;
    await throttle();
    let response;
    try {
      response = await fetch(url, init);
    } catch (err) {
      if (attempt > retries) {
        throw new Error(`Network failure calling ${method} ${redact(`/${version}/${clean}`)}: ${redact(String(err.message))}`);
      }
      await sleep(1500 * attempt);
      continue;
    }

    const text = await response.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      json = null;
    }

    if (response.ok && json && !json.error) return json;

    const payload = json ?? { error: { message: text.slice(0, 500), code: 'NON_JSON' } };
    const error = new GraphError(payload, { status: response.status, method, endpoint: clean, version });
    if (error.isRateLimited && rateLimitWaits < 3) {
      rateLimitWaits += 1;
      const waitMs = 45000 * rateLimitWaits;
      // eslint-disable-next-line no-console
      console.warn(`[meta] rate limited on ${method} ${clean}; waiting ${waitMs} ms (attempt ${rateLimitWaits}/3)`);
      await sleep(waitMs);
      continue;
    }
    if (error.isTransient && attempt <= retries) {
      await sleep(2000 * attempt);
      continue;
    }
    throw error;
  }
}

/* ------------------------------------------------------------------ */
/* client                                                              */
/* ------------------------------------------------------------------ */

export class MetaClient {
  constructor({ version, token, appId, appSecret, logger, redact }) {
    this.version = version;
    this.token = token;
    this.appId = appId;
    this.appSecret = appSecret;
    this.logger = logger;
    this.redact = redact ?? ((s) => s);
    this.proof = crypto.createHmac('sha256', appSecret).update(token).digest('hex');
    this.calls = 0;
  }

  async get(endpoint, params = {}) {
    return this.#call('GET', endpoint, params);
  }

  async post(endpoint, params = {}) {
    return this.#call('POST', endpoint, params);
  }

  async #call(method, endpoint, params) {
    this.calls += 1;
    return callGraph({
      version: this.version,
      method,
      endpoint,
      params,
      token: this.token,
      proof: this.proof,
      redact: this.redact,
    });
  }

  /** Follows cursors (never the `paging.next` URL, which carries the token). */
  async all(endpoint, params = {}, { limit = 100, maxPages = 100 } = {}) {
    const items = [];
    let after = null;
    for (let page = 0; page < maxPages; page += 1) {
      const query = { ...params, limit };
      if (after) query.after = after;
      const res = await this.get(endpoint, query);
      const data = res?.data ?? [];
      items.push(...data);
      const next = res?.paging?.next;
      after = res?.paging?.cursors?.after;
      if (!next || !after) break;
    }
    return items;
  }

  /** Token introspection via the app access token (never logged). */
  async debugToken() {
    const appToken = `${this.appId}|${this.appSecret}`;
    const res = await callGraph({
      version: this.version,
      method: 'GET',
      endpoint: 'debug_token',
      params: { input_token: this.token, access_token: appToken },
      accessTokenParam: false,
      redact: this.redact,
    });
    return res.data;
  }
}

/**
 * Resolves the highest Graph API version that the app can actually use.
 * Probing is required because Meta invalidates whole version names: an unknown
 * version answers code 100 ("Object with ID 'v99.0' does not exist"), while a
 * retired one answers code 2635.
 */
export async function resolveApiVersion({ token, appId, appSecret, redact, probeEndpoint = 'me', probeParams = { fields: 'id,name' }, candidates }) {
  const list =
    candidates ??
    ['v31.0', 'v30.0', 'v29.0', 'v28.0', 'v27.0', 'v26.0', 'v25.0', 'v24.0', 'v23.0', 'v22.0', 'v21.0', 'v20.0'];
  const attempts = [];
  for (const version of list) {
    const proof = crypto.createHmac('sha256', appSecret).update(token).digest('hex');
    try {
      const data = await callGraph({
        version,
        method: 'GET',
        endpoint: probeEndpoint,
        params: probeParams,
        token,
        proof,
        redact,
        retries: 0,
      });
      attempts.push({ version, ok: true });
      return { version, mode: 'probe-ok', attempts, data };
    } catch (err) {
      // An unknown version answers "Unsupported get request. Object with ID 'vNN.0'
      // does not exist, cannot be loaded due to missing permissions, or does not
      // support this operation" (codes 100 / 2500). A retired one answers 2635.
      const unknownVersion =
        /Unsupported get request|Unknown path components|Object with ID '?v\d/i.test(String(err.message)) ||
        Number(err.code) === 2500;
      const retired = Number(err.code) === 2635;
      attempts.push({ version, ok: false, code: err.code, subcode: err.subcode, retired, unknownVersion, message: err.message });
      if (unknownVersion || retired) continue;
      // Any other error means the version itself is valid (auth/permission/etc).
      return { version, mode: 'probe-valid-other-error', attempts, error: err };
    }
  }
  return { version: null, mode: 'no-usable-version', attempts };
}
