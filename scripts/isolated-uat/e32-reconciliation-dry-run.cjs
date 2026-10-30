// Fixed-operation, read-only diagnostic. No login, provider client or apply mode.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { Pool } = require('pg');
const root = path.resolve(__dirname, '../..');
const tenant = 'e7df7640-04ea-4000-9135-0c4451822205';
const operation = '959afb04-b593-4282-b40d-212ed800b507';
const trialId = '2d552e31-4d6b-4ee2-a2b7-7caaf75484dd';
const encf = 'E320009805001';
async function main() {
  const writeProposal = process.argv.length === 3 && process.argv[2] === '--write-proposal';
  if ((process.argv.length !== 2 && !writeProposal) || path.basename(root) !== 'FULLPOS-ECF-ALANUBE' ||
      execFileSync('git', ['branch', '--show-current'], { cwd: root, encoding: 'utf8', windowsHide: true }).trim() !== 'feature/ecf-alanube') throw Error('WORKTREE_REQUIRED');
  const url = new URL(process.env.DATABASE_URL || '');
  if (process.env.APP_ENV !== 'uat' || process.env.UAT_LOCAL_ONLY !== 'true' || !['postgres:', 'postgresql:'].includes(url.protocol) ||
      url.hostname !== '127.0.0.1' || url.port !== '56550' || url.pathname !== '/fullpos_alanube_uat' || url.search || url.hash ||
      execFileSync('docker', ['port', 'fullpos_alanube_uat_postgres', '5432/tcp'], { encoding: 'utf8', windowsHide: true }).trim() !== '127.0.0.1:56550') throw Error('ISOLATED_UAT_REQUIRED');
  const { fingerprint } = require(path.join(root, 'apps/api/dist/ecf/documents/ecf-document-idempotency.service.js'));
  const directory = fs.realpathSync(path.join(root, 'artifacts/e32-first-trial'));
  function json(name) {
    const file = fs.realpathSync(path.join(directory, name));
    if (!file.startsWith(directory + path.sep) || fs.statSync(file).size > 65536) throw Error('LOCAL_EVIDENCE_REFUSED');
    return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  }
  const observed = json('real-post-observation.json');
  const manifest = json('manifest.json');
  const payload = json('payload.json');
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1, connectionTimeoutMillis: 5000 });
  const client = await pool.connect();
  try {
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    await client.query("SET LOCAL statement_timeout = '5s'");
    const { rows: [row] } = await client.query(`SELECT t.state,t.manifest_fingerprint,t.payload_fingerprint,t.document_id,
      d.status,d.safe_error_code,d.external_provider_id,d.external_document_number,d.idempotency_key,
      (SELECT count(*)::int FROM ecf_electronic_document_attempts a WHERE a.company_id=t.company_id AND a.document_id=t.document_id AND a.operation='SEND_TO_PROVIDER') post_attempts,
      (SELECT count(*)::int FROM ecf_electronic_document_attempts a WHERE a.company_id=t.company_id AND a.document_id=t.document_id AND a.operation='QUERY_PROVIDER') get_attempts
      FROM ecf_sandbox_e32_trials t JOIN ecf_electronic_documents d ON d.company_id=t.company_id AND d.id=t.document_id
      JOIN companies c ON c.id=t.company_id AND c.slug='fullpos-alanube-uat-access' AND c.name='SYNTHETIC Fullpos Alanube UAT Access'
      WHERE t.company_id=$1::uuid AND t.id=$2::uuid AND t.mode='SANDBOX' AND t.slot='FIRST_E32_SANDBOX'`, [tenant, trialId]);
    if (!row) throw Error('EXACT_SYNTHETIC_OPERATION_REQUIRED');
    const { rows: events } = await client.query(`SELECT kind,safe_code,http_status,body_sha256 FROM ecf_sandbox_e32_trial_events
      WHERE company_id=$1::uuid AND trial_id=$2::uuid AND kind='POST_OBSERVATION'`, [tenant, trialId]);
    const chainMatches = observed.method === 'POST' && observed.httpStatus === 201 && observed.trialId === trialId &&
      manifest.clientRequestId === operation && observed.clientRequestId === operation && observed.documentNumber === encf && manifest.metadata.encf === encf &&
      observed.manifestFingerprint === row.manifest_fingerprint && fingerprint(manifest) === row.manifest_fingerprint &&
      observed.payloadFingerprint === row.payload_fingerprint && fingerprint(payload) === row.payload_fingerprint &&
      row.idempotency_key === `ecf:v2:${tenant}:E32:REQUEST:${operation}` && events.length === 1 &&
      events[0].http_status === observed.httpStatus && events[0].body_sha256 === observed.responseSha256;
    let recoveredGet = null, reconciliationPlan = null;
    if (fs.existsSync(path.join(directory, 'recovery-get-observation.json'))) {
      const compatibility = require(path.join(root, 'apps/api/dist/ecf/sandbox/alanube-dom-e32-compatibility.js'));
      const verified = require('./e32-recover-evidence.cjs').verifySavedEvidence((body, evidence) =>
        compatibility.assessAlanubeDomE32Compatibility(evidence.httpStatus, body, {
          provider:'ALANUBE_DOM',environment:'SANDBOX',endpoint:'GET_E32_TOKEN_PRIMARY',companyId:tenant,verifiedCompanyId:tenant,
          operationId:operation,remoteId:observed.remoteId,encf,rnc:manifest.sender.taxId,issueDate:manifest.issueDate,
          totalAmount:payload.totals.totalAmount,expectedLegalStatus:observed.legalStatus,expectedSequenceConsumed:observed.sequenceConsumed,
        }));
      const recovery = verified.evidence;
      const recoveryChainMatches = recovery.operation === operation && recovery.tenant === tenant && recovery.trialId === trialId &&
        recovery.documentId === row.document_id && recovery.method === 'GET' && recovery.postResponseSha256 === observed.responseSha256 &&
        recovery.manifestFingerprint === row.manifest_fingerprint && recovery.payloadFingerprint === row.payload_fingerprint &&
        recovery.endpoint === 'https://sandbox.alanube.co/dom/v1/invoices/01M4Y3DEPXXG27G8BNQGMNQ04B';
      recoveredGet = { queriedAtUtc: recovery.queriedAtUtc, httpStatus: recovery.httpStatus, responseSha256: recovery.responseSha256,
        recoveryChainMatches, encryptedArchiveHashMatches: verified.encryptedArchiveHashMatches,
        assessment: verified.assessment, compatibilityAssessment:verified.compatibilityAssessment, contractFieldDiagnostics: verified.contractFieldDiagnostics };
      const { rows: [conflicts] } = await client.query(`SELECT count(*)::int AS n FROM ecf_electronic_documents
        WHERE company_id=$1::uuid AND id<>$2::uuid AND (external_provider_id=$3 OR external_document_number=$4)`,[tenant,row.document_id,observed.remoteId,encf]);
      reconciliationPlan = compatibility.prepareE32CompatibilityReconciliationPlan({
        companyId:tenant,operationId:operation,documentId:row.document_id,trialId,remoteId:observed.remoteId,encf,
        responseSha256:recovery.responseSha256,postResponseSha256:observed.responseSha256,manifestFingerprint:row.manifest_fingerprint,payloadFingerprint:row.payload_fingerprint,
        documentStatus:row.status,trialState:row.state,externalProviderId:row.external_provider_id,externalDocumentNumber:row.external_document_number,
        postAttempts:row.post_attempts,dbQueryAttempts:row.get_attempts,evidenceChainVerified:chainMatches&&recoveryChainMatches,
        encryptedArchiveVerified:verified.encryptedArchiveHashMatches,noConflictingReference:conflicts.n===0,assessment:verified.compatibilityAssessment,
      });
    }
    const recoveryBlockers = recoveredGet
      ? [...(!recoveredGet.recoveryChainMatches ? ['RECOVERY_CHAIN_MISMATCH'] : []),
        ...(!recoveredGet.assessment.checks.OFFICIAL_GET_SCHEMA ? ['OFFICIAL_GET_SCHEMA_INVALID'] : []),
        ...(!recoveredGet.assessment.sufficientForProviderReview ? ['RECOVERY_REQUIRES_REVIEW'] : [])]
      : ['ORIGINAL_RESPONSE_AND_VALIDATION_DIAGNOSTICS_MISSING'];
    let proposalArtifact = null;
    if (writeProposal) {
      if (reconciliationPlan?.result !== 'READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION') throw Error('PROPOSAL_BLOCKED');
      const file = path.join(directory, 'recovery-get-reconciliation-proposal.json');
      const bytes = JSON.stringify(reconciliationPlan, null, 2);
      if (fs.existsSync(file)) {
        if (fs.readFileSync(file, 'utf8') !== bytes) throw Error('PROPOSAL_DIVERGENCE_REQUIRES_REVIEW');
        proposalArtifact = 'ALREADY_EXISTS_IDENTICAL';
      } else { fs.writeFileSync(file, bytes, { flag:'wx' }); proposalArtifact = 'SAVED_NOT_APPLIED'; }
    }
    console.log(JSON.stringify({ mode: 'READ_ONLY', operation, encf, local: row, chainMatches, recoveredGet, reconciliationPlan, proposalArtifact,
      providerObservation: { remoteId: observed.remoteId, status: observed.providerStatus, legalStatus: observed.legalStatus, sequenceConsumed: observed.sequenceConsumed },
      originalResponseAvailable: false, originalSchemaAndCompanyMatchReproducible: false,
      historicalCorrelationFailureDetailAvailable: false, canApplyReconciliation: false, canRetryPost: false,
      reviewReconciliationBlockers: reconciliationPlan?.result === 'READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION'
        ? ['SEPARATE_RECONCILIATION_AUTHORIZATION_REQUIRED'] : recoveryBlockers,
      blockers: [...(!chainMatches ? ['EVIDENCE_CHAIN_MISMATCH'] : []), ...recoveryBlockers, 'FISCAL_AUTHENTICITY_NOT_VERIFIED'],
    }, null, 2));
    await client.query('COMMIT');
  } finally { await client.query('ROLLBACK').catch(() => {}); client.release(); await pool.end(); }
}
main().catch(() => { console.error('BLOCKED: READ_ONLY_E32_DIAGNOSTIC_FAILED; no credentials or provider response logged.'); process.exitCode = 2; });
