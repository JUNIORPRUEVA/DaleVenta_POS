import { ConflictException, Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";
import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import type { EcfDocumentType, EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";
import { EcfDocumentIdempotencyService, fingerprint } from "./ecf-document-idempotency.service";
import { EcfEvidenceIngestionService } from "./ecf-evidence-ingestion.service";
import { EcfBlockedAuthenticityVerifier } from "./ecf-evidence-authenticity.service";
import { EcfSequenceService } from "./ecf-sequence.service";
import { assessEcfProviderResponse } from "./ecf-provider-response";

// Generic emission orchestrator for E31/E34 (E32 keeps its dedicated single-use
// Sandbox service). It reuses the shared idempotency, evidence and state modules.
// It NEVER grants fiscal acceptance: a correlated provider observation always
// lands in HUMAN_REVIEW_REQUIRED for a human, never in DGII_ACCEPTED.
export type EcfEmissionWireRequest = { method: "POST"; path: string; body: unknown; requestId: string };
export type EcfEmissionWireResult =
  | { ok: true; statusCode: number; body: unknown }
  | { ok: false; errorCode: "TIMEOUT" | "NETWORK_ERROR" | "BLOCKED"; safeMessage: string };
export interface EcfEmissionWire { execute(input: EcfEmissionWireRequest): Promise<EcfEmissionWireResult>; }

type EmissionSummary = { encf: string; senderTaxId: string; fingerprint: string; payload: unknown };

@Injectable()
export class EcfEmissionService {
  constructor(private readonly prisma: PrismaService) {}

  private assertType(type: EcfDocumentType) {
    if (!["E31", "E34"].includes(type)) throw new ConflictException("ECF_EMISSION_TYPE_UNSUPPORTED");
  }

  // Prepares and persists a local, contracted draft. No network. Idempotent.
  async prepare(user: TenantUser, input: {
    document: EcfFiscalDocument; metadata: EcfIssuanceMetadata;
    sourceType?: "SALE" | "COTIZACION" | "MANUAL"; sourceId?: string; clientRequestId?: string;
  }) {
    const companyId = requireTenant(user);
    this.assertType(input.document.type);
    // The payload embeds the e-NCF, so numbering is resolved before mapping. When
    // the caller does not fix the number, the server allocates and permanently
    // consumes the next one from the company range. A consumed number is never
    // returned to the pool, not even when the contract validation below fails.
    // Clave de operación estable: un reintento de la MISMA operación (misma
    // petición con clientRequestId, o la MISMA venta origen) debe reutilizar el
    // número ya consumido en lugar de gastar otro y divergir después. Se usa el
    // mismo anclaje que la identidad de idempotencia del documento.
    const operationKey =
      input.clientRequestId ??
      (input.sourceId ? `${input.sourceType ?? "MANUAL"}:${input.sourceId}` : undefined);
    const encf = await this.resolveEncf(user, companyId, input.document.type, input.metadata.encf, operationKey);
    const metadata = { ...input.metadata, encf };
    const mapping = mapEcfToAlanubeDom(input.document, metadata);
    if (mapping.schemaValidation?.ok !== true) throw new ConflictException("ECF_EMISSION_CONTRACT_BLOCKED");
    if (!new RegExp(`^${input.document.type}\\d{10}$`).test(encf)) {
      throw new ConflictException("ECF_EMISSION_ENCF_REQUIRED");
    }
    const document = await new EcfDocumentIdempotencyService(this.prisma).prepareLocalDocument({
      companyId, userId: user.id, sourceType: input.sourceType, sourceId: input.sourceId, clientRequestId: input.clientRequestId,
      document: input.document,
    });
    const emission: EmissionSummary = { encf, senderTaxId: input.document.sender.taxId,
      fingerprint: fingerprint(mapping.payload), payload: mapping.payload };
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id = ${document.id}::uuid FOR UPDATE`;
      const current = await tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } });
      const summary = (current.payloadSummary as Record<string, unknown> | null) ?? {};
      const existing = summary.emission as EmissionSummary | undefined;
      // Same operation must map to the same contracted payload; divergence is refused.
      if (existing && existing.fingerprint !== emission.fingerprint) throw new ConflictException("ECF_EMISSION_PAYLOAD_DIVERGENCE");
      await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: document.id },
        data: { payloadSummary: { ...summary, emission } as unknown as Prisma.InputJsonValue } });
      // Return the persisted row so callers see the stored emission summary.
      return tx.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } });
    });
  }

  // Numbering. A caller-supplied e-NCF is honoured (E32 sandbox flow, migrations);
  // otherwise the server allocates from the company range. The allocation is keyed
  // by the operation so a retry reuses the number it already consumed.
  private async resolveEncf(user: TenantUser, companyId: string, documentType: EcfDocumentType,
    provided: string | undefined, operationKey?: string) {
    if (provided) return provided;
    const sequences = new EcfSequenceService(this.prisma);
    try {
      return (await sequences.allocate(user, documentType, { operationKey })).encf;
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002" && operationKey) {
        const recorded = await sequences.alreadyAllocated(companyId, operationKey);
        if (recorded) return recorded.encf;
      }
      throw error;
    }
  }

  // Single dispatch attempt. Claims and commits the attempt BEFORE the network so
  // a crash or timeout can never produce a second POST for the same document.
  async dispatchOnce(user: TenantUser, documentId: string, wire: EcfEmissionWire) {
    const companyId = requireTenant(user);
    const claim = await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id = ${documentId}::uuid FOR UPDATE`;
      const document = await tx.ecfElectronicDocument.findFirst({ where: { companyId, id: documentId } });
      if (!document) throw new ConflictException("ECF_EMISSION_DOCUMENT_NOT_FOUND");
      this.assertType(document.documentType as EcfDocumentType);
      if (!["LOCAL_VALIDATED", "READY_TO_SEND"].includes(document.status)) throw new ConflictException("ECF_EMISSION_NOT_READY");
      if (document.externalProviderId) throw new ConflictException("ECF_EMISSION_ALREADY_ASSOCIATED");
      const emission = (document.payloadSummary as Record<string, unknown> | null)?.emission as EmissionSummary | undefined;
      if (!emission?.payload || !emission.encf) throw new ConflictException("ECF_EMISSION_NOT_PREPARED");
      const previous = await tx.ecfElectronicDocumentAttempt.count({ where: { companyId, documentId, operation: "SEND_TO_PROVIDER" } });
      if (previous !== 0) throw new ConflictException("ECF_EMISSION_ALREADY_ATTEMPTED");
      // E34 can NEVER be dispatched without a valid, active credit reservation
      // for THIS note and a matching original. Preparation alone is not emission.
      if (document.documentType === "E34") {
        const reservation = await tx.ecfCreditReservation.findUnique({
          where: { companyId_creditDocumentId: { companyId, creditDocumentId: documentId } } });
        if (!reservation) throw new ConflictException("E34_DISPATCH_REQUIRES_RESERVATION");
        if (reservation.state !== "RESERVED") throw new ConflictException("E34_RESERVATION_NOT_ACTIVE");
        if (!document.originalDocumentId || document.originalDocumentId !== reservation.originalDocumentId) {
          throw new ConflictException("E34_ORIGINAL_REFERENCE_REQUIRED");
        }
      }
      const claimed = await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: documentId, status: document.status },
        data: { status: "SEND_IN_PROGRESS" } });
      if (claimed.count !== 1) throw new ConflictException("ECF_EMISSION_CONCURRENT_CLAIM");
      await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId, statusBefore: document.status,
        statusAfter: "SEND_IN_PROGRESS", reasonCode: "EMISSION_DISPATCH_CLAIMED", changedByUserId: user.id } });
      const attempt = await tx.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId,
        operation: "SEND_TO_PROVIDER", idempotencyKey: document.idempotencyKey, requestFingerprint: emission.fingerprint,
        statusBefore: document.status, statusAfter: "SEND_IN_PROGRESS", createdByUserId: user.id } });
      return { attempt: attempt.id, emission, documentType: document.documentType as EcfDocumentType,
        idempotencyKey: document.idempotencyKey, payloadFingerprint: document.payloadFingerprint };
    });

    let result: EcfEmissionWireResult;
    try { result = await wire.execute({ method: "POST", path: "/invoices", body: claim.emission.payload, requestId: claim.attempt }); }
    catch { result = { ok: false, errorCode: "NETWORK_ERROR", safeMessage: "ECF_RESULT_UNKNOWN" }; }

    const body = result.ok ? result.body : null;
    const record = body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};
    const remoteConflict = typeof record.id === "string" && Boolean(await this.prisma.ecfElectronicDocument.findFirst({
      where: { companyId, externalProviderId: record.id, id: { not: documentId } }, select: { id: true } }));
    const observation = assessEcfProviderResponse(result.ok ? result.statusCode : 0, body, {
      documentType: claim.documentType, expectedEncf: claim.emission.encf, expectedTaxId: claim.emission.senderTaxId, remoteConflict,
    });
    if (result.ok && result.statusCode >= 200 && result.statusCode < 300 && observation.correlated) {
      await this.prisma.$transaction(async (tx) => {
        const changed = await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: documentId, status: "SEND_IN_PROGRESS" },
          data: { status: "HUMAN_REVIEW_REQUIRED", safeErrorCode: observation.safeCode,
            safeErrorMessage: "Resultado del proveedor observado; requiere revisión de evidencia fiscal. No reemitir." } });
        if (changed.count !== 1) throw new ConflictException("ECF_EMISSION_DOCUMENT_CHANGED");
        await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId, statusBefore: "SEND_IN_PROGRESS",
          statusAfter: "HUMAN_REVIEW_REQUIRED", reasonCode: observation.safeCode, changedByUserId: user.id,
          metadata: observation as unknown as Prisma.InputJsonValue } });
      });
      // Bind the observed identity BEFORE ingesting evidence: the receipt freezes
      // the correlation columns at the database level.
      await this.prisma.ecfElectronicDocument.updateMany({ where: { companyId, id: documentId, externalProviderId: null },
        data: { externalProviderId: observation.remoteId, externalDocumentNumber: claim.emission.encf } });
      const raw = Buffer.from(JSON.stringify(body));
      await new EcfEvidenceIngestionService(this.prisma, new EcfBlockedAuthenticityVerifier()).ingest(user, {
        documentId, attemptId: claim.attempt, operationKey: claim.idempotencyKey,
        documentFingerprint: claim.payloadFingerprint, requestFingerprint: claim.emission.fingerprint,
        source: "PROVIDER_RESPONSE", eventKey: `emission:${claim.attempt}`, raw,
        httpStatus: result.statusCode,
      });
    } else {
      await new EcfDocumentIdempotencyService(this.prisma).recordUnknownOutcome(companyId, documentId,
        result.ok ? "RESPONSE_PENDING_REVIEW" : result.errorCode === "TIMEOUT" ? "TIMEOUT" : "NETWORK_ERROR");
    }
    return { result: "STOPPED_REVIEW_REQUIRED" as const, canRetryPost: false as const,
      correlated: observation.correlated, documentType: claim.documentType, observation,
      httpStatus: result.ok ? result.statusCode : null, sequenceConsumed: observation.sequenceConsumed } as const;
  }
}
