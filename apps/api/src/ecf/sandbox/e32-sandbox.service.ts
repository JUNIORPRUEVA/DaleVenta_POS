import { ConflictException, ForbiddenException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { EcfDocumentIdempotencyService, fingerprint } from "../documents/ecf-document-idempotency.service";
import { EcfEvidenceIngestionService } from "../documents/ecf-evidence-ingestion.service";
import { EcfBlockedAuthenticityVerifier } from "../documents/ecf-evidence-authenticity.service";
import { digestEvidence } from "../documents/ecf-evidence.policy";
import { validateAlanubeE32QueryResponse } from "../alanube/alanube-schema-validator";
import { assessE32Response } from "./e32-response-assessment";
import { e32Preflight, e32SyntheticAddressAllowed, requiresSyntheticAddressScope, e32ResponseIdentityMatches, firstE32Document, isE32UatTarget, type E32TrialManifest, type E32TrialFacts } from "./e32-sandbox.policy";
import type { E32TrialWire } from "./e32-sandbox.wire";

export type E32TrialAuthorization = { manifestFingerprint: string; actorId: string; expiresAt: string; maxPosts: 1; maxQueries: 1; approvalReference: string };
function fail(code: string): never { throw new ConflictException(code); }

// Dedicated internal/CLI workflow. Not an HTTP controller or general fiscal sender.
export class E32SandboxService {
  constructor(private readonly prisma: PrismaService) {}
  private tenant(user: TenantUser) {
    if (!isE32UatTarget() || process.env.APP_ENV !== "uat" || process.env.UAT_LOCAL_ONLY !== "true") fail("E32_UAT_TARGET_REQUIRED");
    const companyId = requireTenant(user);
    if (user.role !== "ADMIN") throw new ForbiddenException("E32_TRIAL_ADMIN_REQUIRED");
    return companyId;
  }
  slot(user: TenantUser, manifest: E32TrialManifest) {
    return manifest.mode === "MOCK_ONLY" ? `MOCK_ONLY:${this.tenant(user)}` : "FIRST_E32_SANDBOX";
  }
  private async checkSyntheticAddress(companyId: string, manifest: E32TrialManifest) {
    if (!requiresSyntheticAddressScope(manifest)) return;
    const tenant = await this.prisma.company.findUnique({where:{id:companyId},select:{id:true,slug:true,name:true}});
    if (!e32SyntheticAddressAllowed(manifest,tenant,process.env)) fail("E32_SYNTHETIC_ADDRESS_SCOPE_REFUSED");
  }
  async prepare(user: TenantUser, manifest: E32TrialManifest, facts: E32TrialFacts) {
    const companyId = this.tenant(user), report = e32Preflight(manifest, facts);
    await this.checkSyntheticAddress(companyId,manifest);
    if (report.result !== "READY_FOR_AUTHORIZATION" || !report.payload) fail("E32_PREFLIGHT_BLOCKED");
    const slot = this.slot(user, manifest);
    const existing = await this.prisma.ecfSandboxE32Trial.findFirst({ where: { companyId, slot } });
    if (existing) {
      if (existing.manifestFingerprint !== report.manifestFingerprint) fail("E32_TRIAL_DIVERGENT_MANIFEST");
      return existing;
    }
    // Internal preparation is idempotent. No fiscalSnapshot is fabricated.
    const document = await new EcfDocumentIdempotencyService(this.prisma).prepareLocalDocument({ companyId,
      clientRequestId: manifest.clientRequestId, userId: user.id, document: firstE32Document(manifest.sender, manifest.issueDate) });
    try {
      return await this.prisma.ecfSandboxE32Trial.create({ data: { companyId, documentId: document.id, slot, mode: manifest.mode,
        manifest: manifest as unknown as Prisma.InputJsonValue, manifestFingerprint: report.manifestFingerprint!,
        payload: report.payload as unknown as Prisma.InputJsonValue, payloadFingerprint: report.payloadFingerprint! } });
    } catch (error) {
      if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== "P2002") throw error;
      const winner = await this.prisma.ecfSandboxE32Trial.findFirst({ where: { companyId, slot } });
      if (!winner || winner.manifestFingerprint !== report.manifestFingerprint) fail("E32_TRIAL_ALREADY_REGISTERED");
      return winner;
    }
  }

  async runOnce(user: TenantUser, trialId: string, grant: E32TrialAuthorization, facts: E32TrialFacts, wire: E32TrialWire) {
    const companyId = this.tenant(user);
    const trial = await this.prisma.ecfSandboxE32Trial.findFirst({ where: { companyId, id: trialId } });
    if (!trial) fail("E32_TRIAL_NOT_FOUND");
    const manifest = trial.manifest as unknown as E32TrialManifest;
    await this.checkSyntheticAddress(companyId,manifest);
    const preflight = e32Preflight(manifest, facts);
    if (preflight.result !== "READY_FOR_AUTHORIZATION" || grant.manifestFingerprint !== trial.manifestFingerprint ||
        fingerprint(manifest) !== trial.manifestFingerprint || fingerprint(trial.payload) !== trial.payloadFingerprint ||
        wire.mode !== trial.mode || grant.actorId !== user.id || grant.maxPosts !== 1 || grant.maxQueries !== 1 ||
        !grant.approvalReference?.trim() || !Number.isFinite(Date.parse(grant.expiresAt)) || Date.parse(grant.expiresAt) <= Date.now() ||
        Date.parse(grant.expiresAt) > Date.now() + 30 * 60 * 1000) fail("E32_TRIAL_AUTHORIZATION_INVALID");
    // Claim and attempt commit BEFORE touching the network. No transition back.
    const attempt = await this.prisma.$transaction(async tx => {
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id=${companyId}::uuid AND id=${trial.documentId}::uuid FOR UPDATE`;
      const d = await tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: trial.documentId } });
      if (Date.parse(grant.expiresAt) <= Date.now()) fail("E32_TRIAL_AUTHORIZATION_EXPIRED");
      if (d.documentType !== "E32" || d.payloadFingerprint !== fingerprint(firstE32Document(manifest.sender, manifest.issueDate)) ||
          d.idempotencyKey !== `ecf:v2:${companyId}:E32:REQUEST:${manifest.clientRequestId}` ||
          d.externalProviderId || !["LOCAL_VALIDATED","READY_TO_SEND"].includes(d.status)) fail("E32_TRIAL_DOCUMENT_CHANGED");
      const claimed = await tx.ecfSandboxE32Trial.updateMany({ where: { companyId, id: trial.id, state: "PREPARED" }, data: { state: "CLAIMED" } });
      if (claimed.count !== 1) fail("E32_TRIAL_ALREADY_CONSUMED");
      await tx.ecfSandboxE32TrialEvent.create({ data: { companyId, trialId: trial.id, kind: "AUTHORIZATION",
        safeCode: "EXPLICIT_SINGLE_SANDBOX_CONSENT", bodySha256: fingerprint(grant) } });
      await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: d.id }, data: { status: "SEND_IN_PROGRESS" } });
      await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId: d.id, statusBefore: d.status, statusAfter: "SEND_IN_PROGRESS", reasonCode: "AUTHORIZED_SINGLE_SANDBOX_TRIAL", changedByUserId: user.id } });
      return tx.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId: d.id, operation: "SEND_TO_PROVIDER", idempotencyKey: d.idempotencyKey,
        requestFingerprint: trial.payloadFingerprint, statusBefore: d.status, statusAfter: "SEND_IN_PROGRESS", createdByUserId: user.id } });
    });
    let result;
    try { result = await wire.execute({ method: "POST", path: "/invoices", body: trial.payload, requestId: attempt.id }); }
    catch { result = { ok: false as const, errorCode: "NETWORK_ERROR" as const, safeMessage: "E32_RESULT_UNKNOWN", requestId: attempt.id }; }
    const body = result.ok ? result.response.body : null;
    const raw = result.ok && result.rawBody ? result.rawBody : Buffer.from(JSON.stringify(body));
    const record = body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};
    const remoteConflict = typeof record.id === "string" && await this.prisma.ecfElectronicDocument.findFirst({where:{companyId,
      externalProviderId:record.id,id:{not:trial.documentId}},select:{id:true}});
    const assessment = assessE32Response(result.ok ? result.response.statusCode : 0, body,
      { manifest, remoteConflict: Boolean(remoteConflict) });
    const correlated = result.ok && assessment.correlated;
    if (!correlated) await new EcfDocumentIdempotencyService(this.prisma).recordUnknownOutcome(companyId, trial.documentId,
      result.ok ? "RESPONSE_PENDING_REVIEW" : result.errorCode === "TIMEOUT" ? "TIMEOUT" : "NETWORK_ERROR");
    // Commit the observation before optional binding/receipt/query. A failure in
    // downstream processing must leave the response hash and consumed latch.
    await this.prisma.$transaction(async tx => {
      if (correlated) {
        // A known provider observation requires review, not an invented unknown
        // network outcome, and is never automatically promoted to DGII_ACCEPTED.
        const changed = await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: trial.documentId, status: "SEND_IN_PROGRESS" },
          data: { status: "HUMAN_REVIEW_REQUIRED", safeErrorCode: assessment.safeCode,
            safeErrorMessage: "Resultado del proveedor observado; requiere revisión de evidencia fiscal. No reemitir." } });
        if (changed.count !== 1) fail("E32_RESULT_DOCUMENT_CHANGED");
        await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId: trial.documentId,
          statusBefore: "SEND_IN_PROGRESS", statusAfter: "HUMAN_REVIEW_REQUIRED", reasonCode: assessment.safeCode,
          changedByUserId: user.id, metadata: assessment as unknown as Prisma.InputJsonValue } });
      }
      await tx.ecfSandboxE32TrialEvent.create({ data: { companyId, trialId: trial.id, kind: "POST_OBSERVATION",
        safeCode: result.ok ? assessment.safeCode : result.errorCode,
        bodySha256: digestEvidence(raw), httpStatus: result.ok ? result.response.statusCode : null } });
      await tx.ecfSandboxE32Trial.updateMany({ where: { companyId, id: trial.id, state: "CLAIMED" }, data: { state: correlated ? "RESPONSE_RECORDED" : "UNKNOWN_RESULT" } });
    });
    if (correlated) {
      // First association only on this fresh, claimed local operation. It does
      // not authenticate fiscal status. Generic evidence triggers stay intact.
      await this.prisma.ecfElectronicDocument.updateMany({ where: { companyId, id: trial.documentId, externalProviderId: null },
        data: { externalProviderId: record.id as string, externalDocumentNumber: manifest.metadata.encf } });
      await new EcfEvidenceIngestionService(this.prisma, new EcfBlockedAuthenticityVerifier()).ingest(user, {
        documentId: trial.documentId, attemptId: attempt.id, operationKey: attempt.idempotencyKey,
        documentFingerprint: fingerprint(firstE32Document(manifest.sender, manifest.issueDate)), requestFingerprint: trial.payloadFingerprint,
        source: trial.mode === "MOCK_ONLY" ? "SYNTHETIC" : "PROVIDER_RESPONSE", eventKey: `first:${attempt.id}`, raw, httpStatus: 201,
      });
    }
    // Exactly one optional GET in this authorized run, never a retrying poller.
    const queryObservation = correlated ? await this.queryOnce(user, trial.id, wire) : null;
    return { result: "STOPPED_REVIEW_REQUIRED", dispatchAttempts: 1, remoteIdObserved: Boolean(assessment.remoteId),
      remoteIdBound: Boolean(correlated), canRetryPost: false,
      httpStatus: result.ok ? result.response.statusCode : null, providerStatus: assessment.providerStatus,
      observedLegalStatus: assessment.observedLegalStatus, sequenceConsumed: assessment.sequenceConsumed,
      assessment, queryObservation } as const;
  }

  async recoverClaimed(user: TenantUser, trialId: string) {
    const companyId = this.tenant(user);
    return this.prisma.$transaction(async tx => {
      const trial = await tx.ecfSandboxE32Trial.findFirst({ where: { companyId, id: trialId } });
      if (!trial) fail("E32_TRIAL_NOT_FOUND");
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id=${companyId}::uuid AND id=${trial.documentId}::uuid FOR UPDATE`;
      if (trial.state !== "CLAIMED") return { result: "STOPPED_REVIEW_REQUIRED", canRetryPost: false };
      const changed = await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: trial.documentId, status: "SEND_IN_PROGRESS" },
        data: { status: "UNKNOWN_RESULT", safeErrorCode: "PROCESS_RESTART" } });
      if (changed.count) await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId: trial.documentId,
        statusBefore: "SEND_IN_PROGRESS", statusAfter: "UNKNOWN_RESULT", reasonCode: "PROCESS_RESTART", changedByUserId: user.id } });
      await tx.ecfSandboxE32Trial.updateMany({ where: { companyId, id: trial.id, state: "CLAIMED" }, data: { state: "UNKNOWN_RESULT" } });
      return { result: "STOPPED_REVIEW_REQUIRED", canRetryPost: false };
    });
  }

  private async queryOnce(user: TenantUser, trialId: string, wire: E32TrialWire) {
    const companyId = this.tenant(user);
    const trial = await this.prisma.ecfSandboxE32Trial.findFirst({ where: { companyId, id: trialId } });
    if (!trial || trial.mode !== wire.mode) fail("E32_TRIAL_NOT_FOUND");
    const document = await this.prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: trial.documentId } });
    const manifest = trial.manifest as unknown as E32TrialManifest;
    if (!document.externalProviderId || !/^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(document.externalProviderId)) fail("E32_QUERY_REMOTE_ID_REQUIRED");
    // Persist a single query attempt before network, so restart cannot duplicate it.
    const attempt = await this.prisma.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId: document.id,
      operation: "QUERY_PROVIDER", idempotencyKey: document.idempotencyKey, requestFingerprint: trial.payloadFingerprint, createdByUserId: user.id } });
    let response;
    const queryPath = `/invoices/${document.externalProviderId}` + (manifest.companyTarget === "TOKEN_PRIMARY" ? "" : `/idCompany/${manifest.metadata.alanubeCompanyId}`);
    try { response = await wire.execute({ method: "GET", path: queryPath, requestId: attempt.id }); }
    catch { response = { ok: false as const }; }
    const body = response.ok ? response.response.body : null;
    const validation = response.ok ? validateAlanubeE32QueryResponse(response.response.statusCode, body) : null;
    const value = body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};
    const consistent = validation?.ok && response.ok && response.response.statusCode === 200 && value.id === document.externalProviderId &&
      e32ResponseIdentityMatches(value, manifest);
    // GET evidence is quarantined separately with its GET schema, never fed into
    // the POST validator and never mapped to DGII_ACCEPTED/REJECTED.
    await this.prisma.ecfSandboxE32TrialEvent.create({ data: { companyId, trialId: trial.id, kind: "GET_OBSERVATION",
      safeCode: consistent ? "E32_QUERY_CORRELATED_UNVERIFIED" : "E32_QUERY_REQUIRES_REVIEW", bodySha256: digestEvidence(response.ok && response.rawBody ? response.rawBody : JSON.stringify(body)),
      httpStatus: response.ok ? response.response.statusCode : null } });
    return { canUpdateFiscalStatus: false, consistent: Boolean(consistent), requiresReview: true,
      providerStatus: consistent ? value.status : null, observedLegalStatus: consistent ? value.legalStatus : null };
  }
}
