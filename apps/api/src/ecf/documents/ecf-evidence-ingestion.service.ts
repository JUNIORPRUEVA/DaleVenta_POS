import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { validateAlanubeOfficialResponse } from "../alanube/alanube-schema-validator";
import { interpretAlanubeResponse } from "../alanube/alanube-response-interpreter";
import { validateAlanubeWebhookEnvelope } from "../alanube/alanube-webhook.contract";
import type { EcfDocumentType } from "../fiscal-core/ecf-fiscal-document";
import { fingerprint } from "./ecf-document-idempotency.service";
import { digestEvidence, ECF_EVIDENCE_SOURCES, EcfEvidenceAuthenticityVerifier, evidenceConflict, evidenceTrust, parseEvidence, type EvidenceSource } from "./ecf-evidence.policy";

// Local envelope, NOT an Alanube wire contract. Internal only; never accepts companyId.
export type EvidenceIntake = {
  documentId: string; attemptId: string; operationKey: string;
  documentFingerprint: string; requestFingerprint: string;
  source: EvidenceSource; eventKey: string; raw: Buffer;
  expectedHash?: string; httpStatus?: number;
};

@Injectable()
export class EcfEvidenceIngestionService {
  constructor(private readonly prisma: PrismaService, private readonly verifier: EcfEvidenceAuthenticityVerifier) {}

  async ingest(user: TenantUser, input: EvidenceIntake) {
    const companyId = requireTenant(user);
    if (!ECF_EVIDENCE_SOURCES.includes(input.source) || !/^[A-Za-z0-9_.:-]{3,128}$/.test(input.eventKey) ||
        !/^[a-f0-9]{64}$/.test(input.documentFingerprint) || !/^[a-f0-9]{64}$/.test(input.requestFingerprint) ||
        !input.operationKey || input.operationKey.length > 160 ||
        (input.httpStatus !== undefined && (!Number.isInteger(input.httpStatus) || input.httpStatus < 100 || input.httpStatus > 599))) evidenceConflict("ECF_EVIDENCE_METADATA_INVALID");
    const body = parseEvidence(input.raw, input.expectedHash);
    const rawSha256 = digestEvidence(input.raw);
    // External tenant claims are never used to select a document; reject ambiguity.
    if (["companyId", "company_id", "tenantId", "company"].some((key) => key in body)) evidenceConflict("ECF_EVIDENCE_TENANT_CLAIM_FORBIDDEN");
    const trust = evidenceTrust(input.source, await this.verifier.verify(input.raw, input.source));
    const correlationHash = fingerprint({ documentId: input.documentId, attemptId: input.attemptId,
      operationKeyHash: digestEvidence(input.operationKey), documentFingerprint: input.documentFingerprint,
      requestFingerprint: input.requestFingerprint, source: input.source, eventKey: input.eventKey,
      httpStatus: input.httpStatus ?? null, rawSha256, ...trust });
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id = ${input.documentId}::uuid FOR UPDATE`;
      await tx.$queryRaw`SELECT id FROM ecf_electronic_document_attempts WHERE company_id = ${companyId}::uuid AND document_id = ${input.documentId}::uuid AND id = ${input.attemptId}::uuid FOR UPDATE`;
      const document = await tx.ecfElectronicDocument.findFirst({ where: { companyId, id: input.documentId } });
      const attempt = await tx.ecfElectronicDocumentAttempt.findFirst({ where: { companyId, documentId: input.documentId, id: input.attemptId } });
      if (!document || !attempt) evidenceConflict("ECF_EVIDENCE_CORRELATION_NOT_FOUND");
      if (document.payloadFingerprint !== input.documentFingerprint || document.idempotencyKey !== input.operationKey ||
          attempt.requestFingerprint !== input.requestFingerprint) evidenceConflict("ECF_EVIDENCE_OPERATION_MISMATCH");
      if (!["E31", "E32", "E34"].includes(document.documentType)) evidenceConflict("ECF_EVIDENCE_TYPE_UNSUPPORTED");
      if (document.externalProviderId && await tx.ecfElectronicDocument.findFirst({ where: {
        companyId, externalProviderId: document.externalProviderId, id: { not: document.id },
      }, select: { id: true } })) evidenceConflict("ECF_EVIDENCE_REMOTE_ASSOCIATION_AMBIGUOUS");
      let validationCode = "INTERNAL_OBJECT_ONLY", observationCode = "NO_FISCAL_AUTHORITY", schemaSha256: string | null = null;
      if (input.source === "WEBHOOK") {
        const validated = validateAlanubeWebhookEnvelope(body);
        if (!validated.ok || validated.envelope.eventId !== input.eventKey) evidenceConflict("ECF_EVIDENCE_WEBHOOK_INVALID");
        const envelope = validated.envelope;
        // A remote-only identifier is insufficient. Require a known local association.
        if (!envelope.documentExternalId || envelope.documentExternalId !== document.externalProviderId || envelope.companyExternalId) evidenceConflict("ECF_EVIDENCE_REMOTE_ID_MISMATCH");
        validationCode = "LOCAL_WEBHOOK_ENVELOPE_ONLY";
        observationCode = "WEBHOOK_UNVERIFIED";
      } else if (input.source === "PROVIDER_RESPONSE" || input.source === "SYNTHETIC") {
        if (input.httpStatus === undefined) evidenceConflict("ECF_EVIDENCE_HTTP_REQUIRED");
        if (body.id !== undefined && (!document.externalProviderId || body.id !== document.externalProviderId)) evidenceConflict("ECF_EVIDENCE_REMOTE_ID_MISMATCH");
        const validation = validateAlanubeOfficialResponse(document.documentType as EcfDocumentType, input.httpStatus, body);
        schemaSha256 = validation.schemaSha256 || null;
        validationCode = validation.ok ? "OFFICIAL_SCHEMA_VALID" : "OFFICIAL_SCHEMA_INVALID";
        observationCode = interpretAlanubeResponse({ statusCode: input.httpStatus, headers: {}, body, requestId: "quarantined" }, document.documentType as EcfDocumentType).safeCode;
      }
      // Fiscal references from external payloads are not bound or assigned here.
      if (body.encf !== undefined && body.encf !== document.externalDocumentNumber) evidenceConflict("ECF_EVIDENCE_FISCAL_REFERENCE_MISMATCH");
      const key = { companyId_source_eventKey: { companyId, source: input.source, eventKey: input.eventKey } };
      const existing = await tx.ecfEvidenceReceipt.findUnique({ where: key });
      if (existing) {
        if (existing.correlationHash !== correlationHash) evidenceConflict("ECF_EVIDENCE_REPLAY_CONFLICT");
        return existing;
      }
      // Serialize source/event across different documents as well as same-document retries.
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${companyId + ":" + input.source + ":" + input.eventKey}, 0))::text`;
      const replay = await tx.ecfEvidenceReceipt.findUnique({ where: key });
      if (replay) {
        if (replay.correlationHash !== correlationHash) evidenceConflict("ECF_EVIDENCE_REPLAY_CONFLICT");
        return replay;
      }
      return tx.ecfEvidenceReceipt.create({ data: {
        companyId, documentId: document.id, attemptId: attempt.id, source: input.source, eventKey: input.eventKey,
        rawSha256, correlationHash, operationKeyHash: digestEvidence(input.operationKey),
        documentFingerprint: input.documentFingerprint, requestFingerprint: input.requestFingerprint,
        ...trust, validationCode, observationCode, schemaSha256, httpStatus: input.httpStatus, actorUserId: user.id,
      } });
    });
  }

  async reconciliation(user: TenantUser, documentId: string) {
    const companyId = requireTenant(user);
    // Read-only consistent snapshot. Never queries provider or releases reservations.
    return this.prisma.$transaction(async (tx) => {
      const document = await tx.ecfElectronicDocument.findFirst({ where: { companyId, id: documentId } });
      if (!document) evidenceConflict("ECF_EVIDENCE_CORRELATION_NOT_FOUND");
      const receipts = await tx.ecfEvidenceReceipt.findMany({ where: { companyId, documentId }, orderBy: [{ receivedAt: "asc" }, { id: "asc" }] });
      const reservation = await tx.ecfCreditReservation.findUnique({ where: { companyId_creditDocumentId: { companyId, creditDocumentId: documentId } } });
      const hasMultiplePayloads = new Set(receipts.map((receipt) => receipt.rawSha256)).size > 1;
      const requiresManualReview = !document.externalProviderId || hasMultiplePayloads ||
        receipts.some((receipt) => receipt.validationCode === "OFFICIAL_SCHEMA_INVALID");
      return { documentId, status: document.status, receiptCount: receipts.length,
        hasMultiplePayloads, requiresManualReview,
        nextAction: requiresManualReview ? "MANUAL_REVIEW" : "WAIT_FOR_OFFICIAL_QUERY_CONTRACT",
        canQueryProvider: false, canUpdateFiscalStatus: false, canRetryFiscalPost: false, canReleaseReservation: false,
        reservationState: reservation?.state ?? null, reasonCode: "BLOCKED_PENDING_PROVIDER_CONTRACT" } as const;
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
  }
}
