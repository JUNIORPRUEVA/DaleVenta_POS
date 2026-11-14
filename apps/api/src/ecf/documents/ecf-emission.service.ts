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
import { numberingEnvironment } from "./ecf-numbering-environment";
import { assessEcfProviderResponse } from "./ecf-provider-response";
import type { EcfProviderObservation } from "./ecf-provider-response";

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
    // E32 se prepara y numera como cualquier otro tipo: su e-NCF sale del rango
    // autorizado de la empresa. Lo que se retiró es el cupo de sandbox de un
    // solo uso, no el tipo.
    if (!["E31", "E32", "E34"].includes(type)) {
      throw new ConflictException("ECF_EMISSION_TYPE_UNSUPPORTED");
    }
  }

  // Prepares and persists a local, contracted draft. No network. Idempotent.
  async prepare(user: TenantUser, input: {
    document: EcfFiscalDocument; metadata: EcfIssuanceMetadata;
    sourceType?: "SALE" | "COTIZACION" | "MANUAL"; sourceId?: string; clientRequestId?: string;
  }, transaction?: Prisma.TransactionClient) {
    const companyId = requireTenant(user);
    const environment = await numberingEnvironment(transaction ?? this.prisma, companyId);
    this.assertType(input.document.type);
    // The payload embeds the e-NCF, so numbering is resolved before mapping. When
    // the caller does not fix the number, the server allocates it. Standalone
    // preparation keeps committed allocations on later failure; a compound sale
    // transaction rolls back its uncommitted allocation together with the sale.
    // Clave de operación estable: un reintento de la MISMA operación (misma
    // petición con clientRequestId, o la MISMA venta origen) debe reutilizar el
    // número ya consumido en lugar de gastar otro y divergir después. Se usa el
    // mismo anclaje que la identidad de idempotencia del documento.
    const operationKey =
      input.clientRequestId ??
      (input.sourceId ? `${input.sourceType ?? "MANUAL"}:${input.sourceId}` : undefined);
    const encf = await this.resolveEncf(user, companyId, input.document.type, input.metadata.encf, operationKey, environment, transaction);
    const metadata = { ...input.metadata, encf };
    const mapping = mapEcfToAlanubeDom(input.document, metadata);
    if (mapping.schemaValidation?.ok !== true) throw new ConflictException("ECF_EMISSION_CONTRACT_BLOCKED");
    if (!new RegExp(`^${input.document.type}\\d{10}$`).test(encf)) {
      throw new ConflictException("ECF_EMISSION_ENCF_REQUIRED");
    }
    const document = await new EcfDocumentIdempotencyService(this.prisma).prepareLocalDocument({
      companyId, userId: user.id, sourceType: input.sourceType, sourceId: input.sourceId, clientRequestId: input.clientRequestId,
      document: input.document,
      environment,
    }, transaction);
    const emission: EmissionSummary = { encf, senderTaxId: input.document.sender.taxId,
      fingerprint: fingerprint(mapping.payload), payload: mapping.payload };
    const persist = async (tx: Prisma.TransactionClient) => {
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
    };
    return transaction ? persist(transaction) : this.prisma.$transaction(persist);
  }

  // Numbering. A caller-supplied e-NCF is honoured (E32 sandbox flow, migrations);
  // otherwise the server allocates from the company range. The allocation is keyed
  // by the operation so a retry reuses the number it already consumed.
  private async resolveEncf(user: TenantUser, companyId: string, documentType: EcfDocumentType,
    provided: string | undefined, operationKey?: string, environment?: "SANDBOX" | "PRODUCTION", transaction?: Prisma.TransactionClient) {
    if (provided) return provided;
    const sequences = new EcfSequenceService(this.prisma);
    try {
      return (await sequences.allocate(user, documentType, { operationKey, environment, tx: transaction })).encf;
    } catch (error) {
      if (!transaction && error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002" && operationKey) {
        const recorded = await sequences.alreadyAllocated(companyId, operationKey);
        if (recorded) return recorded.encf;
      }
      throw error;
    }
  }

  // Single logical dispatch claim, committed BEFORE the network. The generic
  // path never redispatches a document. A DOSA wire can recover an identical
  // request inside this live claim only with its server authorization/audit hook.
  //
  // `override` permite enviar el cuerpo del PROVEEDOR cuando no coincide con el
  // payload preparado por defecto (caso DOSA: su contrato no es el DOM interno).
  // La huella que se registra es SIEMPRE la del cuerpo realmente enviado, nunca
  // la del preparado, para que la evidencia no mienta sobre lo que salió.
  async dispatchOnce(
    user: TenantUser,
    documentId: string,
    wire: EcfEmissionWire,
    override?: {
      body: unknown;
      fingerprint: string;
      recoverPersisted?: boolean;
      onClaim?: (tx: Prisma.TransactionClient, input: { attemptId: string; recovering: boolean;
        documentFingerprint: string; idempotencyKey: string }) => Promise<void>;
      assertClaimOwner?: (tx: Prisma.TransactionClient, attemptId: string) => Promise<void>;
      printStamp?: (body: unknown, httpStatus: number) => { qrUrl: string; securityCode: string; signedAt: string } | null;
      afterEvidence?: (input: { receiptId: string; attemptId: string; httpStatus: number; body: unknown }) => Promise<void>;
      /**
       * Evaluador de la respuesta del proveedor. Por defecto se usa el de
       * Alanube; DOSA aporta el suyo porque su contrato de respuesta es
       * distinto. El evaluador puede proponer el estado del documento.
       */
      observe?: (input: { statusCode: number; body: unknown }) => EcfProviderObservation & {
        documentStatus?: string;
      };
    },
  ) {
    const companyId = requireTenant(user);
    const requestFingerprint = override?.fingerprint;
    const claim = await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id = ${documentId}::uuid FOR UPDATE`;
      const document = await tx.ecfElectronicDocument.findFirst({ where: { companyId, id: documentId } });
      if (!document) throw new ConflictException("ECF_EMISSION_DOCUMENT_NOT_FOUND");
      this.assertType(document.documentType as EcfDocumentType);
      const recovering = override?.recoverPersisted === true;
      if (recovering && !override?.onClaim) throw new ConflictException("ECF_RECOVERY_AUTHORIZATION_REQUIRED");
      const allowed = recovering ? ["UNKNOWN_RESULT", "SEND_IN_PROGRESS", "DGII_STATUS_PENDING"] : ["LOCAL_VALIDATED", "READY_TO_SEND"];
      if (!allowed.includes(document.status)) throw new ConflictException("ECF_EMISSION_NOT_READY");
      if (!recovering && document.externalProviderId) throw new ConflictException("ECF_EMISSION_ALREADY_ASSOCIATED");
      const emission = (document.payloadSummary as Record<string, unknown> | null)?.emission as EmissionSummary | undefined;
      if (!emission?.payload || !emission.encf) throw new ConflictException("ECF_EMISSION_NOT_PREPARED");
      const previous = await tx.ecfElectronicDocumentAttempt.count({ where: { companyId, documentId, operation: "SEND_TO_PROVIDER" } });
      if ((!recovering && previous !== 0) || (recovering && previous !== 1)) throw new ConflictException("ECF_EMISSION_ALREADY_ATTEMPTED");
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
        operation: recovering ? "QUERY_PROVIDER" : "SEND_TO_PROVIDER", idempotencyKey: recovering
          ? fingerprint({ operationKey: document.idempotencyKey, operation: "QUERY_PROVIDER", ordinal:
              1 + await tx.ecfElectronicDocumentAttempt.count({ where: { companyId, documentId, operation: "QUERY_PROVIDER" } }) })
          : document.idempotencyKey,
        requestFingerprint: requestFingerprint ?? emission.fingerprint,
        statusBefore: document.status, statusAfter: "SEND_IN_PROGRESS", createdByUserId: user.id } });
      await override?.onClaim?.(tx, { attemptId: attempt.id, recovering,
        documentFingerprint: document.payloadFingerprint, idempotencyKey: document.idempotencyKey });
      return { attempt: attempt.id, emission, documentType: document.documentType as EcfDocumentType,
        idempotencyKey: document.idempotencyKey, payloadFingerprint: document.payloadFingerprint };
    });

    const sentBody = override?.body ?? claim.emission.payload;
    let result: EcfEmissionWireResult;
    try { result = await wire.execute({ method: "POST", path: "/invoices", body: sentBody, requestId: claim.attempt }); }
    catch { result = { ok: false, errorCode: "NETWORK_ERROR", safeMessage: "ECF_RESULT_UNKNOWN" }; }

    const body = result.ok ? result.body : null;
    const record = body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};
    const remoteConflict = typeof record.id === "string" && Boolean(await this.prisma.ecfElectronicDocument.findFirst({
      where: { companyId, externalProviderId: record.id, id: { not: documentId } }, select: { id: true } }));
    const observation = override?.observe
      ? override.observe({ statusCode: result.ok ? result.statusCode : 0, body })
      : assessEcfProviderResponse(result.ok ? result.statusCode : 0, body, {
          documentType: claim.documentType, expectedEncf: claim.emission.encf, expectedTaxId: claim.emission.senderTaxId, remoteConflict,
        });
    if (result.ok && result.statusCode >= 200 && result.statusCode < 300 && observation.correlated) {
      // Estado propuesto por el evaluador del proveedor. Sin propuesta se sigue
      // usando `HUMAN_REVIEW_REQUIRED`, que es el valor conservador y el que
      // mantiene el comportamiento de Alanube sin cambios.
      const proposedStatus = (observation as { documentStatus?: string }).documentStatus ?? "HUMAN_REVIEW_REQUIRED";
      const printStamp = override?.printStamp?.(body, result.statusCode);
      await this.prisma.$transaction(async (tx) => {
        if (override?.assertClaimOwner) {
          await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id = ${documentId}::uuid FOR UPDATE`;
          await override.assertClaimOwner(tx, claim.attempt);
        }
        const stored = printStamp ? await tx.ecfElectronicDocument.findFirst({ where: { companyId, id: documentId }, select: { printStamp: true } }) : null;
        const prior = stored?.printStamp as { qrUrl?: string; securityCode?: string; signedAt?: string } | null;
        if (printStamp && prior && ["qrUrl", "securityCode", "signedAt"].some(key => prior[key as keyof typeof prior] !== printStamp[key as keyof typeof printStamp])) {
          throw new ConflictException("ECF_PRINT_IDENTITY_CHANGED");
        }
        const changed = await tx.ecfElectronicDocument.updateMany({ where: { companyId, id: documentId, status: "SEND_IN_PROGRESS" },
          data: { status: proposedStatus as never,
            ...(printStamp && !prior ? { printStamp } : {}),
            safeErrorCode: observation.safeCode,
            safeErrorMessage: "Resultado del proveedor observado; requiere revisión de evidencia fiscal. No reemitir." } });
        if (changed.count !== 1) throw new ConflictException("ECF_EMISSION_DOCUMENT_CHANGED");
        await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId, statusBefore: "SEND_IN_PROGRESS",
          statusAfter: proposedStatus as never, reasonCode: observation.safeCode, changedByUserId: user.id,
          metadata: observation as unknown as Prisma.InputJsonValue } });
      });
      // Bind the observed identity BEFORE ingesting evidence: the receipt freezes
      // the correlation columns at the database level.
      await this.prisma.ecfElectronicDocument.updateMany({ where: { companyId, id: documentId, externalProviderId: null },
        data: { externalProviderId: observation.remoteId, externalDocumentNumber: claim.emission.encf } });
      const raw = Buffer.from(JSON.stringify(body));
      const receipt = await new EcfEvidenceIngestionService(this.prisma, new EcfBlockedAuthenticityVerifier()).ingest(user, {
        documentId, attemptId: claim.attempt, operationKey: claim.idempotencyKey,
        documentFingerprint: claim.payloadFingerprint,
        requestFingerprint: requestFingerprint ?? claim.emission.fingerprint,
        source: "PROVIDER_RESPONSE", eventKey: `emission:${claim.attempt}`, raw,
        httpStatus: result.statusCode,
      });
      await override?.afterEvidence?.({ receiptId: receipt.id, attemptId: claim.attempt, httpStatus: result.statusCode, body });
    } else {
      await new EcfDocumentIdempotencyService(this.prisma).recordUnknownOutcome(companyId, documentId,
        result.ok ? "RESPONSE_PENDING_REVIEW" : result.errorCode === "TIMEOUT" ? "TIMEOUT" : "NETWORK_ERROR",
        override?.assertClaimOwner ? tx => override.assertClaimOwner!(tx, claim.attempt) : undefined);
    }
    return { result: "STOPPED_REVIEW_REQUIRED" as const, canRetryPost: false as const,
      correlated: observation.correlated, documentType: claim.documentType, observation,
      httpStatus: result.ok ? result.statusCode : null, sequenceConsumed: observation.sequenceConsumed } as const;
  }
}
