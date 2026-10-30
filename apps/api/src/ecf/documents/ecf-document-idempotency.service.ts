import { createHash } from "node:crypto";
import { BadRequestException, ConflictException, Injectable } from "@nestjs/common";
import {
  EcfElectronicDocumentOperation,
  EcfElectronicDocumentStatus,
  EcfElectronicDocumentType,
  Prisma,
} from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";

export type PrepareEcfDocumentInput = {
  companyId: string;
  userId?: string;
  sourceType?: "SALE" | "COTIZACION" | "MANUAL";
  sourceId?: string;
  clientRequestId?: string;
  document: EcfFiscalDocument;
};

@Injectable()
export class EcfDocumentIdempotencyService {
  constructor(private readonly prisma: PrismaService) {}

  // Internal recovery primitive only: no sender/worker or HTTP endpoint is enabled.
  async recordUnknownOutcome(companyId: string, documentId: string,
    reason: "TIMEOUT" | "NETWORK_ERROR" | "PROCESS_RESTART" | "RESPONSE_PENDING_REVIEW") {
    return this.prisma.$transaction(async (tx) => {
      const changed = await tx.ecfElectronicDocument.updateMany({
        where: { id: documentId, companyId, status: "SEND_IN_PROGRESS" },
        data: { status: "UNKNOWN_RESULT", safeErrorCode: reason,
          safeErrorMessage: "Resultado desconocido; conciliar antes de cualquier nuevo envío." },
      });
      if (changed.count === 0) {
        const existing = await tx.ecfElectronicDocument.findFirst({ where: { id: documentId, companyId } });
        if (existing?.status === "UNKNOWN_RESULT") return existing;
        throw new ConflictException("ECF_DOCUMENT_NOT_IN_PROGRESS");
      }
      await tx.ecfElectronicDocumentStatusLog.create({ data: {
        companyId, documentId, statusBefore: "SEND_IN_PROGRESS", statusAfter: "UNKNOWN_RESULT",
        reasonCode: reason, safeMessage: "Requiere conciliación o revisión humana; no reintentar emisión.",
      } });
      return tx.ecfElectronicDocument.findFirstOrThrow({ where: { id: documentId, companyId } });
    });
  }

  async prepareLocalDocument(input: PrepareEcfDocumentInput) {
    const payloadFingerprint = fingerprint(input.document);
    const idempotencyKey = this.idempotencyKey(input);
    try {
      return await this.prisma.$transaction(async (tx) => {
      const existing = await tx.ecfElectronicDocument.findUnique({
        where: {
          companyId_idempotencyKey: {
            companyId: input.companyId,
            idempotencyKey,
          },
        },
      });
      if (existing) {
        if (existing.payloadFingerprint !== payloadFingerprint) {
          throw new ConflictException(
            "IDEMPOTENCY_PAYLOAD_MISMATCH: la operación ya existe con otro contenido.",
          );
        }
        return existing;
      }
      const created = await tx.ecfElectronicDocument.create({
        data: {
          companyId: input.companyId,
          documentType: input.document.type as EcfElectronicDocumentType,
          status: EcfElectronicDocumentStatus.LOCAL_VALIDATED,
          sourceType: input.sourceType,
          sourceId: input.sourceId,
          payloadFingerprint,
          idempotencyKey,
          payloadSummary: this.summary(input.document) as Prisma.InputJsonValue,
          // Se guarda el documento COMPLETO, no un resumen: es lo que hace
          // reconstruible el comprobante. Se normaliza por JSON para que el
          // valor persistido sea exactamente el que reproduce la huella.
          fiscalDocument: JSON.parse(
            JSON.stringify(input.document),
          ) as Prisma.InputJsonValue,
          createdByUserId: input.userId,
          updatedByUserId: input.userId,
        },
      });
      await tx.ecfElectronicDocumentAttempt.create({
        data: {
          companyId: input.companyId,
          documentId: created.id,
          operation: EcfElectronicDocumentOperation.PREPARE,
          statusAfter: EcfElectronicDocumentStatus.LOCAL_VALIDATED,
          idempotencyKey,
          requestFingerprint: payloadFingerprint,
          createdByUserId: input.userId,
        },
      });
      await tx.ecfElectronicDocumentStatusLog.create({
        data: {
          companyId: input.companyId,
          documentId: created.id,
          statusAfter: EcfElectronicDocumentStatus.LOCAL_VALIDATED,
          reasonCode: "LOCAL_PREPARED",
          safeMessage: "Documento e-CF preparado localmente; no emitido.",
          changedByUserId: input.userId,
        },
      });
      return created;
      });
    } catch (error) {
      // A competing transaction may have committed the same operation first.
      // Read only after our failed transaction has rolled back (PostgreSQL).
      if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== "P2002") {
        throw error;
      }
      const existing = await this.prisma.ecfElectronicDocument.findUnique({
        where: { companyId_idempotencyKey: { companyId: input.companyId, idempotencyKey } },
      });
      if (!existing) throw error;
      if (existing.payloadFingerprint !== payloadFingerprint) {
        throw new ConflictException("IDEMPOTENCY_PAYLOAD_MISMATCH: la operación ya existe con otro contenido.");
      }
      return existing;
    }
  }

  /**
   * Clave de operación de una preparación, expuesta para comprobaciones
   * previas. Reutiliza el mismo generador que la idempotencia real: si el
   * formato cambiara, cambiaría en un solo sitio.
   */
  operationKeyFor(input: PrepareEcfDocumentInput) {
    return this.idempotencyKey(input);
  }

  private idempotencyKey(input: PrepareEcfDocumentInput) {
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuid.test(input.companyId)) throw new BadRequestException("ECF_COMPANY_ID_INVALID");
    if (!["E31", "E32", "E34"].includes(input.document.type)) {
      throw new BadRequestException("ECF_DOCUMENT_TYPE_INVALID");
    }
    const prefix = `ecf:v2:${input.companyId.toLowerCase()}:${input.document.type}:`;
    if (input.sourceId) {
      if (!uuid.test(input.sourceId) || !["SALE", "COTIZACION", "MANUAL"].includes(input.sourceType ?? "") || input.clientRequestId) {
        throw new BadRequestException("ECF_OPERATION_IDENTITY_INVALID");
      }
      return `${prefix}SOURCE:${input.sourceType}:${input.sourceId.toLowerCase()}`;
    }
    if (!input.clientRequestId || !uuid.test(input.clientRequestId) || (input.sourceType && input.sourceType !== "MANUAL")) {
      throw new BadRequestException("ECF_CLIENT_REQUEST_ID_REQUIRED");
    }
    return `${prefix}REQUEST:${input.clientRequestId.toLowerCase()}`;
  }

  private summary(document: EcfFiscalDocument) {
    const buyer = document.buyer;
    // La identidad del receptor se congela JUNTO al documento preparado: una
    // edición posterior del cliente no puede cambiar lo que ya se preparó. Si
    // el comprobante no exige receptor, no se inventa ninguno.
    const receiver =
      buyer && (buyer.legalName || buyer.taxId)
        ? {
            ...(buyer.legalName ? { legalName: buyer.legalName } : {}),
            ...(buyer.taxId ? { taxId: buyer.taxId } : {}),
          }
        : null;
    return {
      type: document.type,
      issueDate: document.issueDate,
      currency: document.currency,
      total: String(document.totals.total),
      lineCount: document.lines.length,
      hasReference: Boolean(document.reference),
      ...(receiver ? { receiver } : {}),
      ...(document.reference ? { reference: {
        originalENcf: document.reference.originalENcf,
        originalIssueDate: document.reference.originalIssueDate,
        originalType: document.reference.originalType,
      } } : {}),
    };
  }
}

export function fingerprint(value: unknown) {
  return createHash("sha256")
    .update(JSON.stringify(stable(value)))
    .digest("hex");
}

function stable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, item]) => [key, stable(item)]),
    );
  }
  return value;
}
