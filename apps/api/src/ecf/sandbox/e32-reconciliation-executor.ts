import { ConflictException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { EcfElectronicDocument, EcfSandboxE32Trial } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import { ALANUBE_E32_QUERY } from "../alanube/contracts/alanube-e32-query.generated";
import { canTransitionEcfDocument } from "../documents/ecf-document-state-machine";
import { fingerprint } from "../documents/ecf-document-idempotency.service";
import { digestEvidence } from "../documents/ecf-evidence.policy";
import {
  E32_COMPATIBILITY_PROFILE,
  prepareE32CompatibilityReconciliationPlan,
  type E32CompatibilityAssessment,
} from "./alanube-dom-e32-compatibility";
import { isE32UatTarget, type E32TrialManifest } from "./e32-sandbox.policy";

// Dedicated, internal executor for ONE authorized Sandbox reconciliation. It is
// not a generic fiscal status updater: it only moves a single document from
// UNKNOWN_RESULT to HUMAN_REVIEW_REQUIRED, binds the observed provider identity,
// and records append-only audit evidence. It never emits HTTP, never grants DGII
// acceptance, never releases a sequence and never resets the consumed trial.
export const E32_RECONCILIATION_TARGET_STATUS = "HUMAN_REVIEW_REQUIRED" as const;
export const E32_RECONCILIATION_REASON = "E32_PROVIDER_ACCEPTED_OBSERVED";
const GET_CONTRACT = ALANUBE_E32_QUERY.checkinvoices;
const HASH64 = /^[a-f0-9]{64}$/;
const ULID = /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/;
const ENCF = /^E32\d{10}$/;
const RNC = /^\d{9,11}$/;

export type E32ReconciliationRequest = {
  companyId: string;
  actorUserId: string;
  operationId: string;
  documentId: string;
  trialId: string;
  remoteId: string;
  encf: string;
  rnc: string;
  // SHA-256 of the raw provider GET bytes, verified locally against the sealed
  // DPAPI archive. The DPAPI archive itself never reaches this executor.
  rawSha256: string;
  evidenceChainVerified: boolean;
  encryptedArchiveVerified: boolean;
  // Compatibility assessment produced by assessAlanubeDomE32Compatibility for
  // this exact operation. Correlation is re-checked against DB-loaded values.
  assessment: E32CompatibilityAssessment;
};

type Loaded = {
  document: EcfElectronicDocument;
  trial: EcfSandboxE32Trial;
  manifest: E32TrialManifest;
  postBodySha256: string | null;
  postAttempts: number;
  dbQueryAttempts: number;
};

export type E32ReconciliationPlanOutcome = {
  mode: "DRY_RUN";
  plan: ReturnType<typeof prepareE32CompatibilityReconciliationPlan>;
};

export type E32ReconciliationApplyOutcome = {
  mode: "APPLY";
  result: "APPLIED" | "ALREADY_RECONCILED";
  plan: ReturnType<typeof prepareE32CompatibilityReconciliationPlan>;
  documentStatus: string;
  remoteId: string;
  encf: string;
};

export type E32ReconciliationOptions = {
  // Defaults to false: dry-run never writes. Applying requires an explicit flag
  // and separate authorization at the caller (CLI/service).
  execute?: boolean;
  // Optional caller transaction. Used by tests to compose and roll back
  // synthetic fixtures, and by callers that already own the atomic transaction.
  client?: Prisma.TransactionClient;
};

export class E32ReconciliationExecutor {
  constructor(private readonly prisma: PrismaService) {}

  async reconcile(
    request: E32ReconciliationRequest,
    options: E32ReconciliationOptions = {},
  ): Promise<E32ReconciliationPlanOutcome | E32ReconciliationApplyOutcome> {
    if (
      process.env.APP_ENV !== "uat" ||
      process.env.UAT_LOCAL_ONLY !== "true" ||
      !isE32UatTarget(process.env.DATABASE_URL)
    ) {
      throw new ConflictException("E32_RECONCILIATION_UAT_REQUIRED");
    }
    if (options.client) return this.run(options.client, request, options.execute === true);
    // Dry-run is the default; it reads a consistent snapshot and writes nothing.
    return this.prisma.$transaction(
      (tx) => this.run(tx, request, options.execute === true),
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
    );
  }

  private async run(
    tx: Prisma.TransactionClient,
    request: E32ReconciliationRequest,
    execute: boolean,
  ): Promise<E32ReconciliationPlanOutcome | E32ReconciliationApplyOutcome> {
    if (execute) {
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${request.companyId}::uuid AND id = ${request.documentId}::uuid FOR UPDATE`;
    }
    const loaded = await this.load(tx, request);
    this.assertCorrelated(request, loaded);
    const plan = await this.buildPlan(tx, request, loaded);
    if (!execute) return { mode: "DRY_RUN" as const, plan };

    const replay = await tx.ecfElectronicDocumentAttempt.findFirst({
      where: {
        companyId: request.companyId,
        documentId: request.documentId,
        operation: "QUERY_PROVIDER",
        idempotencyKey: plan.idempotencyKey,
      },
    });
    if (replay) {
      if (replay.requestFingerprint === request.rawSha256) {
        return {
          mode: "APPLY" as const,
          result: "ALREADY_RECONCILED" as const,
          plan,
          documentStatus: loaded.document.status,
          remoteId: request.remoteId,
          encf: request.encf,
        };
      }
      throw new ConflictException("E32_RECONCILIATION_REPLAY_CONFLICT");
    }
    if (plan.result !== "READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION") {
      throw new ConflictException("E32_RECONCILIATION_PRECONDITIONS_NOT_MET");
    }
    return this.applyWithinTransaction(tx, request, loaded, plan);
  }

  private async load(tx: Prisma.TransactionClient, request: E32ReconciliationRequest): Promise<Loaded> {
    const document = await tx.ecfElectronicDocument.findFirst({
      where: { companyId: request.companyId, id: request.documentId },
    });
    if (!document) throw new ConflictException("E32_RECONCILIATION_DOCUMENT_NOT_FOUND");
    const trial = await tx.ecfSandboxE32Trial.findFirst({
      where: { companyId: request.companyId, id: request.trialId },
    });
    if (!trial) throw new ConflictException("E32_RECONCILIATION_TRIAL_NOT_FOUND");
    const postEvent = await tx.ecfSandboxE32TrialEvent.findFirst({
      where: { companyId: request.companyId, trialId: trial.id, kind: "POST_OBSERVATION" },
      orderBy: { createdAt: "asc" },
    });
    const postAttempts = await tx.ecfElectronicDocumentAttempt.count({
      where: { companyId: request.companyId, documentId: document.id, operation: "SEND_TO_PROVIDER" },
    });
    const dbQueryAttempts = await tx.ecfElectronicDocumentAttempt.count({
      where: { companyId: request.companyId, documentId: document.id, operation: "QUERY_PROVIDER" },
    });
    return {
      document,
      trial,
      manifest: trial.manifest as unknown as E32TrialManifest,
      postBodySha256: postEvent?.bodySha256 ?? null,
      postAttempts,
      dbQueryAttempts,
    };
  }

  private assertCorrelated(request: E32ReconciliationRequest, loaded: Loaded) {
    const { document, trial, manifest } = loaded;
    if (document.documentType !== "E32") throw new ConflictException("E32_RECONCILIATION_TYPE_REQUIRED");
    if (trial.documentId !== document.id) throw new ConflictException("E32_RECONCILIATION_DOCUMENT_TRIAL_MISMATCH");
    const expectedSlot = trial.mode === "SANDBOX" ? "FIRST_E32_SANDBOX" : `MOCK_ONLY:${request.companyId}`;
    if (!["SANDBOX", "MOCK_ONLY"].includes(trial.mode) || trial.slot !== expectedSlot) {
      throw new ConflictException("E32_RECONCILIATION_SLOT_INVALID");
    }
    if (manifest.clientRequestId !== request.operationId) {
      throw new ConflictException("E32_RECONCILIATION_OPERATION_MISMATCH");
    }
    if (document.idempotencyKey !== `ecf:v2:${request.companyId}:E32:REQUEST:${request.operationId}`) {
      throw new ConflictException("E32_RECONCILIATION_IDENTITY_MISMATCH");
    }
    if (manifest.metadata?.encf !== request.encf) throw new ConflictException("E32_RECONCILIATION_ENCF_MISMATCH");
    if (manifest.sender?.taxId !== request.rnc) throw new ConflictException("E32_RECONCILIATION_RNC_MISMATCH");
    if (!ULID.test(request.remoteId) || !ENCF.test(request.encf) || !RNC.test(request.rnc)) {
      throw new ConflictException("E32_RECONCILIATION_IDENTITY_INVALID");
    }
    if (!HASH64.test(request.rawSha256)) throw new ConflictException("E32_RECONCILIATION_EVIDENCE_HASH_INVALID");
    if (request.evidenceChainVerified !== true || request.encryptedArchiveVerified !== true) {
      throw new ConflictException("E32_RECONCILIATION_EVIDENCE_UNVERIFIED");
    }
    const assessment = request.assessment;
    if (assessment.profile !== E32_COMPATIBILITY_PROFILE) {
      throw new ConflictException("E32_RECONCILIATION_PROFILE_REQUIRED");
    }
    const correlation = assessment.correlation;
    if (
      correlation.companyId !== request.companyId ||
      correlation.operationId !== request.operationId ||
      correlation.remoteId !== request.remoteId ||
      correlation.encf !== request.encf ||
      correlation.rnc !== request.rnc
    ) {
      throw new ConflictException("E32_RECONCILIATION_CORRELATION_MISMATCH");
    }
    // Only a fully compatible, provider-declared ACCEPTED observation for review.
    if (
      assessment.observedProviderOutcome !== "ACCEPTED" ||
      assessment.proposedLocalStatus !== "HUMAN_REVIEW_REQUIRED"
    ) {
      throw new ConflictException("E32_RECONCILIATION_OUTCOME_NOT_REVIEWABLE");
    }
    // A compatibility assessment never carries fiscal authority; reject forged ones.
    if (assessment.canUpdateFiscalStatus !== false || assessment.canApplyReconciliation !== false) {
      throw new ConflictException("E32_RECONCILIATION_AUTHORITY_VIOLATION");
    }
    if (!canTransitionEcfDocument(document.status, E32_RECONCILIATION_TARGET_STATUS).ok) {
      throw new ConflictException("E32_RECONCILIATION_TRANSITION_INVALID");
    }
  }

  private async buildPlan(tx: Prisma.TransactionClient, request: E32ReconciliationRequest, loaded: Loaded) {
    const conflicts = await tx.ecfElectronicDocument.count({
      where: {
        companyId: request.companyId,
        id: { not: loaded.document.id },
        OR: [{ externalProviderId: request.remoteId }, { externalDocumentNumber: request.encf }],
      },
    });
    return prepareE32CompatibilityReconciliationPlan({
      companyId: request.companyId,
      operationId: request.operationId,
      documentId: loaded.document.id,
      trialId: loaded.trial.id,
      remoteId: request.remoteId,
      encf: request.encf,
      responseSha256: request.rawSha256,
      postResponseSha256: loaded.postBodySha256 ?? "",
      manifestFingerprint: loaded.trial.manifestFingerprint,
      payloadFingerprint: loaded.trial.payloadFingerprint,
      documentStatus: loaded.document.status,
      trialState: loaded.trial.state,
      externalProviderId: loaded.document.externalProviderId,
      externalDocumentNumber: loaded.document.externalDocumentNumber,
      postAttempts: loaded.postAttempts,
      dbQueryAttempts: loaded.dbQueryAttempts,
      evidenceChainVerified: request.evidenceChainVerified,
      encryptedArchiveVerified: request.encryptedArchiveVerified,
      noConflictingReference: conflicts === 0,
      assessment: request.assessment,
    });
  }

  private async applyWithinTransaction(
    tx: Prisma.TransactionClient,
    request: E32ReconciliationRequest,
    loaded: Loaded,
    plan: ReturnType<typeof prepareE32CompatibilityReconciliationPlan>,
  ): Promise<E32ReconciliationApplyOutcome> {
    const { document, trial } = loaded;
    // Bind the observed provider identity first: a later evidence receipt freezes
    // these correlation columns at the database level.
    const changed = await tx.ecfElectronicDocument.updateMany({
      where: {
        companyId: request.companyId,
        id: document.id,
        status: "UNKNOWN_RESULT",
        externalProviderId: null,
        externalDocumentNumber: null,
      },
      data: {
        status: E32_RECONCILIATION_TARGET_STATUS,
        externalProviderId: request.remoteId,
        externalDocumentNumber: request.encf,
        safeErrorCode: E32_RECONCILIATION_REASON,
        safeErrorMessage:
          "Resultado del proveedor observado (ACCEPTED, Sandbox); requiere revisión humana. No reemitir.",
        updatedByUserId: request.actorUserId,
      },
    });
    if (changed.count !== 1) throw new ConflictException("E32_RECONCILIATION_CONCURRENT_CHANGE");

    await tx.ecfElectronicDocumentStatusLog.create({
      data: {
        companyId: request.companyId,
        documentId: document.id,
        statusBefore: "UNKNOWN_RESULT",
        statusAfter: E32_RECONCILIATION_TARGET_STATUS,
        reasonCode: E32_RECONCILIATION_REASON,
        safeMessage:
          "Conciliación local de observación Alanube Sandbox; no es aceptación ni certificación DGII.",
        changedByUserId: request.actorUserId,
        metadata: {
          observedProvider: { legalStatus: "ACCEPTED", providerStatus: "FINISHED", sequenceConsumed: true },
          compatibilityProfile: request.assessment.profile,
          appliedCompatibilityRules: plan.proposed?.appliedRules ?? [],
          publishedValidation:
            plan.proposed?.publishedValidation ??
            (request.assessment.publishedContract.ok ? "OFFICIAL_SCHEMA_VALID" : "OFFICIAL_SCHEMA_INVALID"),
          receiptTrust: "PROVIDER_DECLARED",
          responseSha256: request.rawSha256,
          dgiiAcceptance: false,
        } as Prisma.InputJsonValue,
      },
    });

    const attempt = await tx.ecfElectronicDocumentAttempt.create({
      data: {
        companyId: request.companyId,
        documentId: document.id,
        operation: "QUERY_PROVIDER",
        idempotencyKey: plan.idempotencyKey,
        requestFingerprint: request.rawSha256,
        statusBefore: "UNKNOWN_RESULT",
        statusAfter: E32_RECONCILIATION_TARGET_STATUS,
        createdByUserId: request.actorUserId,
      },
    });

    await tx.ecfEvidenceReceipt.create({
      data: {
        companyId: request.companyId,
        documentId: document.id,
        attemptId: attempt.id,
        source: "PROVIDER_RESPONSE",
        eventKey: `reconcile:${request.operationId}`,
        rawSha256: request.rawSha256,
        correlationHash: fingerprint({
          companyId: request.companyId,
          operationId: request.operationId,
          documentId: document.id,
          remoteId: request.remoteId,
          encf: request.encf,
          rnc: request.rnc,
          responseSha256: request.rawSha256,
          manifestFingerprint: trial.manifestFingerprint,
          payloadFingerprint: trial.payloadFingerprint,
          profile: request.assessment.profile,
        }),
        operationKeyHash: digestEvidence(document.idempotencyKey),
        documentFingerprint: document.payloadFingerprint,
        requestFingerprint: trial.payloadFingerprint,
        trustLevel: "PROVIDER_DECLARED",
        authenticity: "BLOCKED_PENDING_PROVIDER_CONTRACT",
        validationCode: request.assessment.publishedContract.ok ? "OFFICIAL_SCHEMA_VALID" : "OFFICIAL_SCHEMA_INVALID",
        observationCode: E32_RECONCILIATION_REASON,
        schemaSha256: GET_CONTRACT.schemaSha256,
        httpStatus: 200,
        actorUserId: request.actorUserId,
      },
    });

    // Append-only trial history. The consumed trial state itself is never changed.
    await tx.ecfSandboxE32TrialEvent.create({
      data: {
        companyId: request.companyId,
        trialId: trial.id,
        kind: "RECONCILIATION",
        safeCode: "E32_HUMAN_REVIEW_OBSERVED",
        bodySha256: request.rawSha256,
        httpStatus: 200,
      },
    });

    return {
      mode: "APPLY" as const,
      result: "APPLIED" as const,
      plan,
      documentStatus: E32_RECONCILIATION_TARGET_STATUS,
      remoteId: request.remoteId,
      encf: request.encf,
    };
  }
}
