// Authorized-reconciliation executor for the first E32 Sandbox document.
// Dry-run by default: reads local sealed evidence + UAT state and prints the
// proposed changes. It never emits HTTP and never writes unless EXPLICITLY
// authorized (--execute + --authorization + E32_RECONCILIATION_APPLY_ENABLED).
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const tenant = 'e7df7640-04ea-4000-9135-0c4451822205';
const operation = '959afb04-b593-4282-b40d-212ed800b507';
const trialId = '2d552e31-4d6b-4ee2-a2b7-7caaf75484dd';
const encf = 'E320009805001';
const directory = path.join(root, 'artifacts/e32-first-trial');
function localJson(name) {
  const file = fs.realpathSync(path.join(directory, name));
  if (!file.startsWith(fs.realpathSync(directory) + path.sep) || fs.statSync(file).size > 65536) throw Error('LOCAL_EVIDENCE_REFUSED');
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}
async function main() {
  const execute = process.argv.includes('--execute');
  const authorizationAt = process.argv.indexOf('--authorization');
  const authorization = authorizationAt > 0 ? process.argv[authorizationAt + 1] : null;
  const known = process.argv.slice(2).filter((arg, index, list) => arg !== '--execute' && arg !== '--authorization' &&
    (index === 0 || list[index - 1] !== '--authorization'));
  if (known.length || path.basename(root) !== 'FULLPOS-ECF-ALANUBE' ||
      execFileSync('git', ['branch', '--show-current'], { cwd: root, encoding: 'utf8', windowsHide: true }).trim() !== 'feature/ecf-alanube') throw Error('WORKTREE_REQUIRED');
  const url = new URL(process.env.DATABASE_URL || '');
  if (process.env.APP_ENV !== 'uat' || process.env.UAT_LOCAL_ONLY !== 'true' || !['postgres:', 'postgresql:'].includes(url.protocol) ||
      url.hostname !== '127.0.0.1' || url.port !== '56550' || url.pathname !== '/fullpos_alanube_uat' || url.search || url.hash ||
      execFileSync('docker', ['port', 'fullpos_alanube_uat_postgres', '5432/tcp'], { encoding: 'utf8', windowsHide: true }).trim() !== '127.0.0.1:56550') throw Error('ISOLATED_UAT_REQUIRED');
  // Applying is impossible unless a human explicitly enables it AND cites an
  // authorization reference. Both are absent by default.
  if (execute && (process.env.E32_RECONCILIATION_APPLY_ENABLED !== 'true' || !authorization || !/^[A-Za-z0-9_.:-]{3,128}$/.test(authorization))) {
    throw Error('RECONCILIATION_APPLY_NOT_AUTHORIZED');
  }
  const { PrismaService } = require(path.join(root, 'apps/api/dist/prisma/prisma.service.js'));
  const { E32ReconciliationExecutor } = require(path.join(root, 'apps/api/dist/ecf/sandbox/e32-reconciliation-executor.js'));
  const compatibility = require(path.join(root, 'apps/api/dist/ecf/sandbox/alanube-dom-e32-compatibility.js'));
  const { verifySavedEvidence } = require('./e32-recover-evidence.cjs');
  const observed = localJson('real-post-observation.json');
  const manifest = localJson('manifest.json');
  const payload = localJson('payload.json');
  const prisma = new PrismaService();
  await prisma.$connect();
  try {
    const trial = await prisma.ecfSandboxE32Trial.findFirst({ where: { companyId: tenant, id: trialId } });
    const document = await prisma.ecfElectronicDocument.findFirst({ where: { companyId: tenant, id: trial?.documentId } });
    if (!trial || !document) throw Error('EXACT_SYNTHETIC_OPERATION_REQUIRED');
    const events = await prisma.ecfSandboxE32TrialEvent.findMany({ where: { companyId: tenant, trialId, kind: 'POST_OBSERVATION' } });
    const chainMatches = observed.method === 'POST' && observed.httpStatus === 201 && observed.trialId === trialId &&
      manifest.clientRequestId === operation && observed.clientRequestId === operation && observed.documentNumber === encf &&
      observed.manifestFingerprint === trial.manifestFingerprint && observed.payloadFingerprint === trial.payloadFingerprint &&
      document.idempotencyKey === `ecf:v2:${tenant}:E32:REQUEST:${operation}` && events.length === 1 &&
      events[0].httpStatus === observed.httpStatus && events[0].bodySha256 === observed.responseSha256;
    const verified = verifySavedEvidence((body, evidence) => compatibility.assessAlanubeDomE32Compatibility(evidence.httpStatus, body, {
      provider: 'ALANUBE_DOM', environment: 'SANDBOX', endpoint: 'GET_E32_TOKEN_PRIMARY', companyId: tenant, verifiedCompanyId: tenant,
      operationId: operation, remoteId: observed.remoteId, encf, rnc: manifest.sender.taxId, issueDate: manifest.issueDate,
      totalAmount: payload.totals.totalAmount, expectedLegalStatus: observed.legalStatus, expectedSequenceConsumed: observed.sequenceConsumed,
    }));
    const evidenceOk = chainMatches && verified.encryptedArchiveHashMatches;
    const request = {
      companyId: tenant, actorUserId: document.createdByUserId, operationId: operation, documentId: document.id, trialId,
      remoteId: observed.remoteId, encf, rnc: manifest.sender.taxId, rawSha256: verified.evidence.responseSha256,
      evidenceChainVerified: evidenceOk, encryptedArchiveVerified: verified.encryptedArchiveHashMatches,
      assessment: verified.compatibilityAssessment,
    };
    const outcome = await new E32ReconciliationExecutor(prisma).reconcile(request, { execute });
    console.log(JSON.stringify({ mode: outcome.mode, result: outcome.result ?? outcome.plan?.result ?? null,
      authorization: execute ? authorization : null, evidenceVerification: verified.assessment?.checks ?? null,
      currentDocument: { id: document.id, status: document.status, externalProviderId: document.externalProviderId, externalDocumentNumber: document.externalDocumentNumber },
      trialState: trial.state, proposed: outcome.plan?.proposed ?? null, blockers: outcome.plan?.result === 'READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION' ? [] : (outcome.plan?.result ? ['PRECONDITIONS_NOT_MET'] : []),
      canGrantDgiiAcceptance: false, providerCalls: 0, databaseStatesModified: execute ? 'AUTHORIZED_CHANGE' : false }, null, 2));
  } finally { await prisma.$disconnect(); }
}
main().catch((error) => { console.error(`BLOCKED: E32_RECONCILIATION_EXECUTOR_REFUSED (${error?.message ?? 'unknown'}); no network, no credentials, no writes.`); process.exitCode = 2; });
