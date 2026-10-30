// Exactly one specifically authorized GET. No fiscal sender or database writes.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync, spawnSync } = require('node:child_process');
const { Pool } = require('pg');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const root = path.resolve(__dirname, '../..');
const directory = path.join(root, 'artifacts/e32-first-trial');
const remoteId = '01M4Y3DEPXXG27G8BNQGMNQ04B';
const endpoint = `https://sandbox.alanube.co/dom/v1/invoices/${remoteId}`;
const tenant = 'e7df7640-04ea-4000-9135-0c4451822205';
const operation = '959afb04-b593-4282-b40d-212ed800b507';
const trialId = '2d552e31-4d6b-4ee2-a2b7-7caaf75484dd';
const encf = 'E320009805001';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function json(name) {
  const file = fs.realpathSync(path.join(directory, name));
  if (!file.startsWith(fs.realpathSync(directory) + path.sep) || fs.statSync(file).size > 65536) throw Error('EVIDENCE_PATH_REFUSED');
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}
function createEvidence(name, value) {
  fs.writeFileSync(path.join(directory, name), JSON.stringify(value, null, 2), { flag: 'wx' });
}
async function getOnce(fetchImpl, token) {
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 15000);
  let httpStatus = null;
  try {
    const response = await fetchImpl(endpoint, { method: 'GET', redirect: 'manual', signal: controller.signal,
      headers: { authorization: `Bearer ${token}`, accept: 'application/json' } });
    httpStatus = response.status;
    if (httpStatus >= 300 && httpStatus < 400) return { httpStatus, failure: 'REDIRECT_BLOCKED', raw: null };
    const reader = response.body?.getReader(), chunks = []; let size = 0;
    if (reader) try {
      while (true) { const chunk = await reader.read(); if (chunk.done) break;
        size += chunk.value.length; if (size > 65536) { await reader.cancel(); throw Error('RESPONSE_SIZE_LIMIT'); } chunks.push(chunk.value); }
    } finally { reader.releaseLock(); }
    return { httpStatus, raw: Buffer.concat(chunks), failure: null };
  } catch { return { httpStatus, raw: null, failure: controller.signal.aborted ? 'TIMEOUT' : 'NETWORK_OR_BODY_ERROR' }; }
  finally { clearTimeout(timer); }
}
function assess(httpStatus, body, schema) {
  const ajv = new Ajv({ allErrors: true, strictSchema: false, strictTypes: false, coerceTypes: false, useDefaults: false, removeAdditional: false });
  addFormats(ajv); ajv.addFormat('ulid', /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/);
  const validator = ajv.compile(schema), schemaValid = Boolean(validator(body));
  const r = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const checks = { HTTP_200: httpStatus === 200, OFFICIAL_GET_SCHEMA: schemaValid,
    REMOTE_ID_MATCH: r.id === remoteId, ENCF_MATCH: r.documentNumber === encf,
    EMITTER_MATCH: r.companyIdentification === '132109122',
    ACCEPTED: r.legalStatus === 'ACCEPTED', SEQUENCE_CONSUMED: r.sequenceConsumed === true,
    STATUS_KNOWN: ['REGISTERED', 'TO_SEND', 'WAITING_RESPONSE', 'TO_NOTIFY', 'FINISHED'].includes(r.status) };
  return { checks, sufficientForProviderReview: Object.values(checks).every(Boolean),
    schemaErrors: (validator.errors || []).slice(0, 40).map(e => ({ path: (e.instancePath + (e.keyword === 'required' ? '/' + e.params.missingProperty : '')).slice(0, 256), keyword: e.keyword })),
    observation: { remoteId: /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(r.id || '') ? r.id : null,
      encf: /^E32\d{10}$/.test(r.documentNumber || '') ? r.documentNumber : null,
      status: checks.STATUS_KNOWN ? r.status : null,
      legalStatus: ['ACCEPTED', 'ACCEPTED_WITH_OBSERVATIONS', 'REJECTED'].includes(r.legalStatus) ? r.legalStatus : null,
      sequenceConsumed: typeof r.sequenceConsumed === 'boolean' ? r.sequenceConsumed : null,
      emitterRnc: typeof r.companyIdentification === 'string' && /^\d{9,11}$/.test(r.companyIdentification) ? r.companyIdentification : null,
      trackId: typeof r.trackId === 'string' && /^[0-9a-f-]{36}$/i.test(r.trackId) ? r.trackId : null },
    canUpdateFiscalStatus: false, canRetryGet: false, canRetryPost: false };
}
function verifySavedEvidence(evaluateCompatibility) {
  const evidence = json('recovery-get-observation.json');
  const file = fs.realpathSync(path.join(directory, 'recovery-get-response.dpapi'));
  if (!file.startsWith(fs.realpathSync(directory) + path.sep) || fs.statSync(file).size > 2 * 1024 * 1024) throw Error('ENCRYPTED_EVIDENCE_REFUSED');
  const decrypted = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
    '$ErrorActionPreference="Stop"; Import-Module "$PSHOME\\Modules\\Microsoft.PowerShell.Security\\Microsoft.PowerShell.Security.psd1"; $secure=ConvertTo-SecureString ([Console]::In.ReadToEnd().Trim()); $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); try { [Console]::Out.Write([Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }'],
  { input: fs.readFileSync(file, 'utf8'), encoding: 'utf8', windowsHide: true, maxBuffer: 128 * 1024 });
  if (decrypted.status !== 0 || !/^[A-Za-z0-9+/=]+$/.test(decrypted.stdout || '')) throw Error('ENCRYPTED_EVIDENCE_UNAVAILABLE');
  const raw = Buffer.from(decrypted.stdout, 'base64');
  if (raw.length > 65536 || sha(raw) !== evidence.responseSha256) throw Error('ENCRYPTED_EVIDENCE_HASH_MISMATCH');
  const contract = require(path.join(root, 'apps/api/dist/ecf/alanube/contracts/alanube-e32-query.generated.js')).ALANUBE_E32_QUERY.checkinvoices;
  if (evidence.schemaSha256 !== contract.schemaSha256) throw Error('RECOVERY_CONTRACT_CHANGED');
  const body = JSON.parse(raw.toString('utf8'));
  const assessment = assess(evidence.httpStatus, body, contract.responses['200']);
  const field = key => ({ type: body[key] === null ? 'null' : typeof body[key],
    value: typeof body[key] === 'string' && /^[0-9T:.+ /Z-]{1,64}$/.test(body[key]) ? body[key] : body[key] === null ? null : '[OMITTED]' });
  return { evidence, assessment, encryptedArchiveHashMatches: true,
    compatibilityAssessment: evaluateCompatibility ? evaluateCompatibility(body, evidence) : null,
    contractFieldDiagnostics: { stampDate: field('stampDate'), trackId: field('trackId'), signatureDate: field('signatureDate') } };
}
async function main() {
  const execute = process.argv[2] === '--execute-authorized-one-get';
  if (process.argv.length !== 3 || (!execute && process.argv[2] !== '--check')) throw Error('MODE_REQUIRED');
  if (path.basename(root) !== 'FULLPOS-ECF-ALANUBE' || execFileSync('git', ['branch', '--show-current'], { cwd: root, encoding: 'utf8', windowsHide: true }).trim() !== 'feature/ecf-alanube') throw Error('WORKTREE_REQUIRED');
  const url = new URL(process.env.DATABASE_URL || '');
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || url.hostname !== '127.0.0.1' || url.port !== '56550' || url.pathname !== '/fullpos_alanube_uat' || url.search || url.hash ||
      process.env.APP_ENV !== 'uat' || process.env.UAT_LOCAL_ONLY !== 'true' || process.env.ALANUBE_ENV !== 'sandbox' || process.env.ALANUBE_BASE_URL !== 'https://sandbox.alanube.co/dom/v1' ||
      ['ALANUBE_ENABLE_REAL_CALLS', 'ECF_EMISSION_ENABLED', 'ECF_ALANUBE_AUTH_TESTS_ENABLED'].some(k => (process.env[k] || 'false') !== 'false') ||
      execFileSync('docker', ['port', 'fullpos_alanube_uat_postgres', '5432/tcp'], { encoding: 'utf8', windowsHide: true }).trim() !== '127.0.0.1:56550') throw Error('ISOLATION_REQUIRED');
  for (const file of ['real-get-observation.json', 'recovery-get-claim.json', 'recovery-get-observation.json', 'recovery-get-response.dpapi'])
    if (fs.existsSync(path.join(directory, file))) throw Error('EXISTING_GET_EVIDENCE_DO_NOT_RETRY');
  const post = json('real-post-observation.json'), manifest = json('manifest.json'), payload = json('payload.json');
  const tokenFile = path.join(root, 'apps/api/.secrets/alanube-sandbox-token.securestring.xml');
  const credentialPredatesPost = fs.statSync(tokenFile).mtimeMs <= Date.parse(post.observedAtUtc);
  if (!credentialPredatesPost || post.remoteId !== remoteId || post.documentNumber !== encf || post.clientRequestId !== operation ||
      post.trialId !== trialId || post.legalStatus !== 'ACCEPTED' || post.sequenceConsumed !== true || manifest.companyTarget !== 'TOKEN_PRIMARY') throw Error('ORIGINAL_CORRELATION_REQUIRED');
  const { fingerprint } = require(path.join(root, 'apps/api/dist/ecf/documents/ecf-document-idempotency.service.js'));
  const contract = require(path.join(root, 'apps/api/dist/ecf/alanube/contracts/alanube-e32-query.generated.js')).ALANUBE_E32_QUERY.checkinvoices;
  if (contract.endpoint !== '/invoices/{id}' || !contract.responses['200']) throw Error('OFFICIAL_PRIMARY_GET_CONTRACT_REQUIRED');
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1, connectionTimeoutMillis: 5000 });
  const client = await pool.connect(); let locked = false;
  try {
    locked = (await client.query('SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS locked', [tenant + ':E32_RECOVERY_GET:' + remoteId])).rows[0].locked;
    if (!locked) throw Error('QUERY_ALREADY_IN_PROGRESS');
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const { rows: [row] } = await client.query(`SELECT t.state,t.manifest_fingerprint,t.payload_fingerprint,t.document_id,d.status,d.idempotency_key,
      (SELECT count(*)::int FROM ecf_electronic_document_attempts a WHERE a.company_id=t.company_id AND a.document_id=t.document_id AND a.operation='SEND_TO_PROVIDER') posts,
      (SELECT count(*)::int FROM ecf_electronic_document_attempts a WHERE a.company_id=t.company_id AND a.document_id=t.document_id AND a.operation='QUERY_PROVIDER') queries
      FROM ecf_sandbox_e32_trials t JOIN ecf_electronic_documents d ON d.company_id=t.company_id AND d.id=t.document_id
      JOIN companies c ON c.id=t.company_id AND c.slug='fullpos-alanube-uat-access' AND c.name='SYNTHETIC Fullpos Alanube UAT Access'
      WHERE t.company_id=$1::uuid AND t.id=$2::uuid AND t.slot='FIRST_E32_SANDBOX' AND t.mode='SANDBOX'`, [tenant, trialId]);
    const events = (await client.query('SELECT http_status,body_sha256 FROM ecf_sandbox_e32_trial_events WHERE company_id=$1::uuid AND trial_id=$2::uuid AND kind=\'POST_OBSERVATION\'', [tenant, trialId])).rows;
    if (!row || row.state !== 'UNKNOWN_RESULT' || row.status !== 'UNKNOWN_RESULT' || row.posts !== 1 || row.queries !== 0 ||
        row.idempotency_key !== `ecf:v2:${tenant}:E32:REQUEST:${operation}` || fingerprint(manifest) !== row.manifest_fingerprint || fingerprint(payload) !== row.payload_fingerprint ||
        post.manifestFingerprint !== row.manifest_fingerprint || post.payloadFingerprint !== row.payload_fingerprint || events.length !== 1 || events[0].http_status !== 201 || events[0].body_sha256 !== post.responseSha256) throw Error('LOCAL_CHAIN_OR_QUERY_STATE_INVALID');
    const context = { operation, tenant, trialId, documentId: row.document_id, endpoint, method: 'GET',
      postResponseSha256: post.responseSha256, manifestFingerprint: row.manifest_fingerprint, payloadFingerprint: row.payload_fingerprint,
      schemaSha256: contract.schemaSha256, source: contract.source, credentialPredatesOriginalPost: credentialPredatesPost };
    if (!execute) { console.log(JSON.stringify({ result: 'GET_PREFLIGHT_PASS', ...context, authenticatedRequests: 0 })); return; }
    const token = process.env.ALANUBE_SANDBOX_TOKEN;
    if (!token || !token.trim() || /[\r\n]/.test(token)) throw Error('SANDBOX_PROTECTED_TOKEN_REQUIRED');
    createEvidence('recovery-get-claim.json', { ...context, authorization: 'user-specific-read-only-recovery-2026-10-14', claimedAtUtc: new Date().toISOString(), maxGets: 1, noRetry: true });
    const result = await getOnce(globalThis.fetch, token);
    let body = null; if (result.raw) try { body = JSON.parse(result.raw.toString('utf8')); } catch { /* Invalid JSON remains evidence, never acceptance. */ }
    const assessment = assess(result.httpStatus, body, contract.responses['200']);
    let encryptedArchiveSaved = false;
    if (result.raw) {
      // DPAPI CurrentUser via a private pipe. Never put plaintext in files/args/logs.
      const encryption = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
        '$ErrorActionPreference="Stop"; Import-Module "$PSHOME\\Modules\\Microsoft.PowerShell.Security\\Microsoft.PowerShell.Security.psd1"; $data=[Console]::In.ReadToEnd(); $secure=ConvertTo-SecureString $data -AsPlainText -Force; ConvertFrom-SecureString $secure'],
      { input: result.raw.toString('base64'), encoding: 'utf8', windowsHide: true, maxBuffer: 4 * 1024 * 1024 });
      if (encryption.status === 0 && /^[0-9a-f]+\s*$/i.test(encryption.stdout || '')) {
        fs.writeFileSync(path.join(directory, 'recovery-get-response.dpapi'), encryption.stdout.trim(), { flag: 'wx' }); encryptedArchiveSaved = true;
      }
    }
    const evidence = { ...context, queriedAtUtc: new Date().toISOString(), authenticatedGetAttempts: 1, fiscalPosts: 0,
      httpStatus: result.httpStatus, transportFailure: result.failure, responseSha256: result.raw ? sha(result.raw) : null,
      responseBytes: result.raw?.length ?? null, encryptedArchiveSaved, assessment,
      historicalPostUnchanged: sha(fs.readFileSync(path.join(directory, 'real-post-observation.json'))) === postFileHash,
      databaseStatesModified: false };
    createEvidence('recovery-get-observation.json', evidence);
    console.log(JSON.stringify(evidence, null, 2));
  } finally {
    delete process.env.ALANUBE_SANDBOX_TOKEN;
    await client.query('ROLLBACK').catch(() => {});
    if (locked) await client.query('SELECT pg_advisory_unlock(hashtextextended($1,0))', [tenant + ':E32_RECOVERY_GET:' + remoteId]);
    client.release(); await pool.end();
  }
}
const postFileHash = require.main === module ? sha(fs.readFileSync(path.join(directory, 'real-post-observation.json'))) : null;
if (require.main === module) main().catch(() => { delete process.env.ALANUBE_SANDBOX_TOKEN; console.error('BLOCKED: E32_RECOVERY_STOPPED; inspect claim/evidence, NEVER retry automatically.'); process.exitCode = 2; });
module.exports = { getOnce, assess, endpoint, verifySavedEvidence };
