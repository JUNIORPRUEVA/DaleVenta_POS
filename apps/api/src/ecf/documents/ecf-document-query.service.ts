import { Injectable, NotFoundException } from "@nestjs/common";
import { EcfElectronicDocumentStatus, Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import {
  contractAllowsEmission,
  ECF_ALANUBE_CONTRACT_REGISTRY,
} from "../ecf-contract-registry";
import { ECF_ALLOWED_DOCUMENT_TYPES } from "../ecf.constants";
import {
  ECF_GROUP_STATUSES,
  type EcfStatusGroup,
  type ListEcfDocumentsQueryDto,
  type RegisterEcfSequenceDto,
} from "../dto/ecf-documents.dto";
import { EcfE34CreditService } from "./ecf-e34-credit.service";
import { EcfSequenceService } from "./ecf-sequence.service";

const LIST_SELECT = {
  id: true,
  documentType: true,
  status: true,
  externalDocumentNumber: true,
  internalDocumentNumber: true,
  sourceType: true,
  sourceId: true,
  originalDocumentId: true,
  safeErrorCode: true,
  safeErrorMessage: true,
  createdAt: true,
  updatedAt: true,
  // Se proyecta solo lo imprescindible para la bandeja: importe y referencia
  // al original. NUNCA se devuelve el resumen completo (contendría el payload
  // contratado con el proveedor).
  payloadSummary: true,
} satisfies Prisma.EcfElectronicDocumentSelect;

// Read model for the client applications. It is a projection of the persisted
// fiscal state: it never mutates a document, never emits and never promotes a
// status. Every query is scoped by the authenticated company.
@Injectable()
export class EcfDocumentQueryService {
  constructor(private readonly prisma: PrismaService) {}

  /** What this company may do right now. Drives which UI affordances exist. */
  async capabilities(user: TenantUser) {
    const companyId = requireTenant(user);
    const config = await this.prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId },
    });
    const allowed = this.allowedTypes(config?.allowedTypes);
    return {
      enabled: config?.enabled === true,
      environment: config?.environment ?? "SANDBOX",
      certificationStatus: config?.certificationStatus ?? "NOT_STARTED",
      productionEnabled: config?.productionEnabled === true,
      allowedTypes: allowed,
      // FACT: ninguna ruta HTTP alcanza el TRANSPORTE REAL. La única ruta que
      // llega a `EcfEmissionService.dispatchOnce` es
      // `POST /ecf/documents/:id/simulate-dispatch`, que usa el transporte
      // simulado y se niega en tiempo de petición si el transporte real
      // estuviera seleccionado. La emisión real sigue siendo un paso operativo
      // controlado, no una acción de UI.
      emissionPathAvailable: false,
      simulatedDispatchPathAvailable: true,
      documentTypes: ECF_ALLOWED_DOCUMENT_TYPES.map((documentType) => {
        const entry = ECF_ALANUBE_CONTRACT_REGISTRY.find(
          (item) => item.documentType === documentType,
        );
        return {
          documentType,
          contractStatus: entry?.status ?? "UNVERIFIED",
          contractAllowsEmission: contractAllowsEmission(documentType),
          allowedForCompany: allowed.includes(documentType),
          // E32 keeps its own single-use sandbox slot and is never allocated
          // from the company numbering range.
          allocatable: documentType !== "E32",
        };
      }),
    };
  }

  async list(user: TenantUser, query: ListEcfDocumentsQueryDto) {
    const companyId = requireTenant(user);
    const take = query.take ?? 25;
    const skip = query.skip ?? 0;
    const where: Prisma.EcfElectronicDocumentWhereInput = { companyId };
    if (query.documentType) where.documentType = query.documentType;
    if (query.status) where.status = query.status;
    else if (query.group) where.status = { in: ECF_GROUP_STATUSES[query.group] };
    const search = query.search?.trim();
    if (search) {
      where.OR = [
        { externalDocumentNumber: { contains: search, mode: "insensitive" } },
        { internalDocumentNumber: { contains: search, mode: "insensitive" } },
      ];
    }
    const [total, rows] = await Promise.all([
      this.prisma.ecfElectronicDocument.count({ where }),
      this.prisma.ecfElectronicDocument.findMany({
        where,
        orderBy: { createdAt: "desc" },
        take,
        skip,
        select: LIST_SELECT,
      }),
    ]);
    return { total, take, skip, items: rows.map((row) => this.toListItem(row)) };
  }

  /** Counters per functional bucket, for badges and alerts. */
  async summary(user: TenantUser) {
    const companyId = requireTenant(user);
    const rows = await this.prisma.ecfElectronicDocument.groupBy({
      by: ["status"],
      where: { companyId },
      _count: { _all: true },
    });
    const byStatus: Record<string, number> = {};
    const byGroup: Record<EcfStatusGroup, number> = {
      PENDING: 0,
      REQUIRES_REVIEW: 0,
      ACCEPTED: 0,
      REJECTED: 0,
      CANCELLED: 0,
    };
    for (const row of rows) {
      byStatus[row.status] = row._count._all;
      const group = this.groupOf(row.status);
      if (group) byGroup[group] += row._count._all;
    }
    return { total: Object.values(byStatus).reduce((a, b) => a + b, 0), byStatus, byGroup };
  }

  /**
   * Full traceability view of one document: status, e-NCF, every transition and
   * every attempt. Evidence is summarised (count + digest), never re-exposed.
   */
  async detail(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    const document = await this.prisma.ecfElectronicDocument.findFirst({
      where: { id, companyId },
      select: {
        ...LIST_SELECT,
        externalProviderId: true,
        payloadFingerprint: true,
        fiscalSnapshot: true,
        statusLogs: {
          orderBy: { createdAt: "desc" },
          take: 100,
          select: {
            id: true,
            statusBefore: true,
            statusAfter: true,
            reasonCode: true,
            changedByUserId: true,
            createdAt: true,
          },
        },
        attempts: {
          orderBy: { createdAt: "desc" },
          select: {
            id: true,
            operation: true,
            statusBefore: true,
            statusAfter: true,
            createdAt: true,
          },
        },
        creditReservation: {
          select: { state: true, amount: true, createdAt: true, updatedAt: true },
        },
        originalDocument: {
          select: {
            id: true,
            documentType: true,
            status: true,
            externalDocumentNumber: true,
          },
        },
        _count: { select: { evidenceReceipts: true } },
      },
    });
    // Cross-company ids are indistinguishable from a missing document: no
    // existence leak (IDOR signal) for another tenant's identifier.
    if (!document) throw new NotFoundException("Comprobante e-CF no encontrado");
    const { _count, ...rest } = document;
    return {
      ...this.toListItem(rest),
      externalProviderId: document.externalProviderId,
      payloadFingerprint: document.payloadFingerprint,
      fiscalSnapshot: document.fiscalSnapshot ?? null,
      statusLogs: document.statusLogs.map((log) => ({
        id: log.id,
        statusBefore: log.statusBefore,
        statusAfter: log.statusAfter,
        reasonCode: log.reasonCode,
        hasActor: Boolean(log.changedByUserId),
        createdAt: log.createdAt,
      })),
      attempts: document.attempts,
      creditReservation: document.creditReservation
        ? {
            state: document.creditReservation.state,
            amount: document.creditReservation.amount.toString(),
            createdAt: document.creditReservation.createdAt,
            updatedAt: document.creditReservation.updatedAt,
          }
        : null,
      originalDocument: document.originalDocument,
      evidenceReceipts: _count.evidenceReceipts,
    };
  }

  /**
   * Originals that may still receive an E34 credit note. The available balance
   * comes from the shared fiscal-balance policy (never recomputed here).
   */
  async eligibleOriginals(user: TenantUser, take = 50) {
    const companyId = requireTenant(user);
    const candidates = await this.prisma.ecfElectronicDocument.findMany({
      where: {
        companyId,
        documentType: { in: ["E31", "E32"] },
        status: EcfElectronicDocumentStatus.DGII_ACCEPTED,
      },
      orderBy: { createdAt: "desc" },
      take: Math.min(Math.max(take, 1), 100),
      select: LIST_SELECT,
    });
    const credit = new EcfE34CreditService(this.prisma);
    const items: Array<ReturnType<typeof this.toListItem> & { availableAmount: string }> = [];
    for (const candidate of candidates) {
      try {
        const balance = await credit.balance(user, candidate.id);
        if (Number(balance.availableAmount) > 0) {
          items.push({ ...this.toListItem(candidate), availableAmount: balance.availableAmount });
        }
      } catch {
        // Not eligible (missing fiscal evidence, untracked credits pending review):
        // it is simply not offered as an E34 original.
      }
    }
    return { items };
  }

  async listSequences(user: TenantUser) {
    const rows = await new EcfSequenceService(this.prisma).list(user);
    return {
      items: rows.map((row) => ({
        id: row.id,
        documentType: row.documentType,
        prefix: row.prefix,
        startNumber: row.startNumber,
        nextNumber: row.nextNumber,
        endNumber: row.endNumber,
        validUntil: row.validUntil,
        active: row.active,
        consumed: Math.max(0, row.nextNumber - row.startNumber),
        remaining: Math.max(0, row.endNumber - row.nextNumber + 1),
      })),
    };
  }

  async registerSequence(user: TenantUser, dto: RegisterEcfSequenceDto) {
    const created = await new EcfSequenceService(this.prisma).register(user, {
      documentType: dto.documentType,
      startNumber: dto.startNumber,
      endNumber: dto.endNumber,
      validUntil: dto.validUntil ?? null,
    });
    return { id: created.id, documentType: created.documentType, startNumber: created.startNumber,
      endNumber: created.endNumber, validUntil: created.validUntil, active: created.active };
  }

  async renewSequence(user: TenantUser, dto: RegisterEcfSequenceDto) {
    const renewed = await new EcfSequenceService(this.prisma).renew(user, {
      documentType: dto.documentType,
      startNumber: dto.startNumber,
      endNumber: dto.endNumber,
      validUntil: dto.validUntil ?? null,
    });
    return { id: renewed.id, documentType: renewed.documentType, startNumber: renewed.startNumber,
      endNumber: renewed.endNumber, validUntil: renewed.validUntil, active: renewed.active };
  }

  private toListItem(row: {
    id: string;
    documentType: string;
    status: string;
    externalDocumentNumber: string | null;
    internalDocumentNumber: string | null;
    sourceType: string | null;
    sourceId: string | null;
    originalDocumentId: string | null;
    safeErrorCode: string | null;
    safeErrorMessage: string | null;
    createdAt: Date;
    updatedAt: Date;
    payloadSummary?: unknown;
  }) {
    const summary = (row.payloadSummary as Record<string, unknown> | null) ?? {};
    const reference = (summary.reference as Record<string, unknown> | undefined) ?? {};
    const receiver = (summary.receiver as Record<string, unknown> | undefined) ?? {};
    const emission = (summary.emission as Record<string, unknown> | undefined) ?? {};
    // El e-NCF se consume al preparar y queda en el resumen de emisión; el
    // despacho es quien fija `external_document_number`. La bandeja debe mostrar
    // el número que el comprobante YA tiene consumido, no un hueco: un borrador
    // sin su número visible es imposible de conciliar contra el rango.
    const reservedEncf =
      typeof emission.encf === "string" && emission.encf ? emission.encf : null;
    return {
      id: row.id,
      documentType: row.documentType,
      status: row.status,
      statusGroup: this.groupOf(row.status),
      // The e-NCF is only meaningful once assigned by the server numbering range.
      encf: row.externalDocumentNumber ?? reservedEncf,
      externalDocumentNumber: row.externalDocumentNumber,
      internalDocumentNumber: row.internalDocumentNumber,
      sourceType: row.sourceType,
      sourceId: row.sourceId,
      originalDocumentId: row.originalDocumentId,
      /** Importe del comprobante, tal como se preparó. */
      total: typeof summary.total === "string" ? summary.total : null,
      currency: typeof summary.currency === "string" ? summary.currency : null,
      /** Referencia al e-NCF original cuando el comprobante es una nota E34. */
      originalEncf:
        typeof reference.originalENcf === "string" ? reference.originalENcf : null,
      /**
       * Receptor congelado al preparar. Es `null` cuando el comprobante no
       * exigía receptor o cuando se preparó antes de persistir este dato: en
       * ese caso la bandeja NO reconstruye el nombre desde el cliente actual,
       * porque eso mostraría algo distinto de lo preparado.
       */
      receiverName:
        typeof receiver.legalName === "string" ? receiver.legalName : null,
      receiverTaxId:
        typeof receiver.taxId === "string" ? receiver.taxId : null,
      safeErrorCode: row.safeErrorCode,
      safeErrorMessage: row.safeErrorMessage,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  private groupOf(status: string): EcfStatusGroup | null {
    for (const group of Object.keys(ECF_GROUP_STATUSES) as EcfStatusGroup[]) {
      if (ECF_GROUP_STATUSES[group].includes(status as EcfElectronicDocumentStatus)) {
        return group;
      }
    }
    return null;
  }

  private allowedTypes(value: Prisma.JsonValue | null | undefined): string[] {
    if (!Array.isArray(value)) return [];
    return value.filter(
      (item): item is string =>
        typeof item === "string" &&
        (ECF_ALLOWED_DOCUMENT_TYPES as readonly string[]).includes(item),
    );
  }
}
