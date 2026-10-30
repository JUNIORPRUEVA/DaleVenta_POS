import { Injectable } from "@nestjs/common";
import { EcfEnvironment, Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { ECF_ALLOWED_DOCUMENT_TYPES } from "../ecf.constants";
import { ALANUBE_OFFICIAL_REQUIRED_FIELDS } from "../alanube/alanube-official-required-fields";
import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";
import { mapSaleSnapshotToEcfDocument } from "../pos/ecf-sale-adapter";
import { EcfSaleFiscalAdapter, type EcfSaleFiscalSnapshot } from "../pos/ecf-sale-fiscal.adapter";
import { fiscalFailure, type EcfFiscalResult } from "../pos/ecf-sale-fiscal.policy";
import {
  buildCreditLines,
  type EcfCreditLineRequest,
  type EcfRefundKind,
} from "./ecf-credit-note.policy";
import { EcfE34CreditService } from "./ecf-e34-credit.service";
import { e34Conflict, readFiscalSnapshot } from "./ecf-e34-integrity.policy";
import { EcfDocumentIdempotencyService } from "./ecf-document-idempotency.service";
import { EcfEmissionService } from "./ecf-emission.service";
import { dec } from "../fiscal-core/ecf-money";

export type EcfPreparationInput = {
  saleId: string;
  /**
   * Solo E31. E32 no pasa por el orquestador genérico: consumiría un cupo de un
   * solo uso y tiene su propio flujo de sandbox. Mezclarlos permitiría emitir
   * consumidor final con numeración de crédito fiscal.
   */
  documentType: "E31";
  /**
   * Forma de pago según el contrato DOM. El esquema del proveedor declara el
   * enum [1, 2] para E31, así que solo se aceptan esos dos códigos. No se deduce
   * de `Sale.paymentMethod`: el repositorio no contiene un mapeo oficial
   * verificado, e inventarlo produciría un comprobante inválido.
   */
  paymentType: 1 | 2;
  incomeType?: 1 | 2 | 3 | 4 | 5 | 6;
  sequenceDueDate?: string;
  paymentDeadline?: string;
};

export type EcfPreparationResult = {
  documentId: string;
  documentType: "E31" | "E32";
  status: string;
  encf: string | null;
  saleId: string;
  evidence: EcfSaleFiscalSnapshot["evidence"];
};

export type EcfCreditNoteInput = {
  originalDocumentId: string;
  /**
   * Identificador de ESTA operación. Ancla la idempotencia y la numeración: así
   * pueden existir varias notas parciales sobre el mismo original y un reintento
   * reutiliza el e-NCF ya consumido.
   */
  clientRequestId: string;
  refundKind: EcfRefundKind;
  /** Solo para notas parciales: qué líneas y cantidades se acreditan. */
  lines?: EcfCreditLineRequest[];
  /** enum [1,2,3,4] del contrato. Se elige explícitamente: el proveedor no
   * documenta la semántica de cada código en el esquema publicado. */
  modificationCode: 1 | 2 | 3 | 4;
  modificationReason: string;
  paymentType: 1 | 2;
  /** enum [0,1] del contrato, exigido por `idDoc` para E34. */
  creditNoteIndicator: 0 | 1;
  sequenceDueDate?: string;
};

export type EcfCreditNoteResult = {
  documentId: string;
  encf: string | null;
  status: string;
  originalDocumentId: string;
  originalEncf: string;
  reservationState: string;
  reservedAmount: string;
};

/**
 * Preparación de CONSUMO (E32). El tipo se elige explícitamente: la aplicación
 * no deduce E31/E32 a partir de si la venta tiene o no cliente, porque ese
 * criterio fiscal no está confirmado en el contrato del proveedor.
 */
export type EcfConsumoPreparationInput = {
  saleId: string;
  documentType: "E32";
  /** enum [1,2] del contrato DOM. Se elige explícitamente. */
  paymentType: 1 | 2;
  incomeType?: 1 | 2 | 3 | 4 | 5 | 6;
  sequenceDueDate?: string;
  paymentDeadline?: string;
};

export type EcfConsumoPreparationResult = {
  documentId: string;
  documentType: "E32";
  status: string;
  /**
   * Siempre `null`: E32 no toma numeración del rango de la empresa. Su e-NCF
   * llega con el cupo único de sandbox, nunca desde este flujo.
   */
  encf: null;
  numberingState: "PENDING_SANDBOX_SLOT";
  saleId: string;
  evidence: EcfSaleFiscalSnapshot["evidence"];
};

/**
 * Prepara un comprobante electrónico a partir de una VENTA real.
 *
 * Preparar no es emitir: crea un borrador local validado y consume la
 * numeración si corresponde. No contacta al proveedor ni declara aceptación.
 */
@Injectable()
export class EcfPreparationService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Contrato de error: la validación de PREPARACIÓN se devuelve como resultado
   * (`EcfFiscalResult`), mientras que las guardas del orquestador (numeración,
   * bloqueo de contrato, divergencia) lanzan excepciones de dominio con código,
   * como en el resto del módulo. Ambas son seguras: ninguna crea borrador.
   */
  async prepareFromSale(
    user: TenantUser,
    input: EcfPreparationInput,
  ): Promise<EcfFiscalResult<EcfPreparationResult>> {
    const companyId = requireTenant(user);

    if ((input.documentType as string) !== "E31") {
      return fiscalFailure(
        "ECF_TYPE_REQUIRES_SANDBOX_FLOW",
        "Solo E31 se prepara desde una venta; E32 se gestiona en su flujo de cupo único de sandbox.",
      );
    }

    const enabled = await this.assertCompanyCanPrepare(user, companyId, input.documentType);
    if (!enabled.ok) return enabled;

    const built = await new EcfSaleFiscalAdapter(this.prisma).build(user, {
      saleId: input.saleId,
      documentType: input.documentType,
    });
    if (!built.ok) return built;

    const document = mapSaleSnapshotToEcfDocument(built.value.snapshot);
    // Una venta no puede producir DOS comprobantes fiscales de tipos distintos.
    // La guarda es simétrica con la del flujo de consumo: sin ella, preparar E32
    // y después E31 dejaría dos borradores sobre la misma venta.
    const conflicting = await this.prisma.ecfElectronicDocument.findFirst({
      where: {
        companyId,
        sourceType: "SALE",
        sourceId: built.value.saleId,
        documentType: { not: input.documentType },
      },
      select: { documentType: true },
    });
    if (conflicting) {
      return fiscalFailure(
        "ECF_SALE_ALREADY_PREPARED_AS_OTHER_TYPE",
        `La venta ya tiene un comprobante ${conflicting.documentType} preparado; `
          + "no se prepara un segundo tipo sobre la misma venta.",
      );
    }
    const metadata: EcfIssuanceMetadata = {
      paymentType: input.paymentType,
      ...(input.incomeType ? { incomeType: input.incomeType } : {}),
      ...(input.sequenceDueDate ? { sequenceDueDate: input.sequenceDueDate } : {}),
      ...(input.paymentDeadline ? { paymentDeadline: input.paymentDeadline } : {}),
    } as EcfIssuanceMetadata;

    // E31 y E34 toman su e-NCF del rango de la empresa (lo asigna el
    // orquestador); E32 lo recibe informado.
    const metadataCheck = this.assertContractMetadata(input.documentType, metadata);
    if (!metadataCheck.ok) return metadataCheck;

    const prepared = await new EcfEmissionService(this.prisma).prepare(user, {
      document,
      metadata,
      // La identidad fiscal se ancla en la VENTA, nunca en la venta + un id de
      // petición: el módulo lo rechaza y, además, así una misma venta no puede
      // producir dos comprobantes (la segunda preparación reutiliza el mismo
      // documento y, si los datos cambiaron, se bloquea por divergencia).
      sourceType: "SALE",
      sourceId: built.value.saleId,
    });

    const emission = (prepared.payloadSummary as Record<string, unknown> | null)
      ?.emission as { encf?: string } | undefined;

    return {
      ok: true,
      value: {
        documentId: prepared.id,
        documentType: input.documentType,
        status: prepared.status,
        encf: emission?.encf ?? null,
        saleId: built.value.saleId,
        evidence: built.value.evidence,
      },
    };
  }

  /**
   * Prepara localmente un comprobante de CONSUMO (E32) a partir de una venta.
   *
   * E32 es un flujo INDEPENDIENTE del genérico: aquí NO se asigna e-NCF, NO se
   * consume el rango de numeración de la empresa y NO se contacta al proveedor.
   * El comprobante queda como borrador validado en local, listo para su cupo
   * único de sandbox. La validación del esquema contratado se hace cuando el
   * cupo entrega el e-NCF: sin número no se puede construir el payload.
   */
  async prepareConsumoFromSale(
    user: TenantUser,
    input: EcfConsumoPreparationInput,
  ): Promise<EcfFiscalResult<EcfConsumoPreparationResult>> {
    const companyId = requireTenant(user);

    if ((input.documentType as string) !== "E32") {
      return fiscalFailure(
        "ECF_CONSUMO_TYPE_REQUIRED",
        "La preparación de consumo solo admite E32; E31 usa el flujo de crédito fiscal.",
      );
    }

    const enabled = await this.assertCompanyCanPrepare(user, companyId, input.documentType);
    if (!enabled.ok) return enabled;

    const built = await new EcfSaleFiscalAdapter(this.prisma).build(user, {
      saleId: input.saleId,
      documentType: input.documentType,
    });
    if (!built.ok) return built;

    // Una venta no puede producir DOS comprobantes fiscales distintos. Si ya se
    // preparó como crédito fiscal, se rechaza en vez de dejar dos borradores:
    // el usuario debe decidir cuál corresponde antes de continuar.
    const conflicting = await this.prisma.ecfElectronicDocument.findFirst({
      where: {
        companyId,
        sourceType: "SALE",
        sourceId: built.value.saleId,
        documentType: { not: "E32" },
      },
      select: { id: true, documentType: true, status: true },
    });
    if (conflicting) {
      return fiscalFailure(
        "ECF_SALE_ALREADY_PREPARED_AS_OTHER_TYPE",
        `La venta ya tiene un comprobante ${conflicting.documentType} preparado; `
          + "no se prepara un segundo tipo sobre la misma venta.",
      );
    }

    const document = mapSaleSnapshotToEcfDocument(built.value.snapshot);
    const prepared = await new EcfDocumentIdempotencyService(this.prisma).prepareLocalDocument({
      companyId,
      userId: user.id,
      sourceType: "SALE",
      sourceId: built.value.saleId,
      document,
    });

    return {
      ok: true,
      value: {
        documentId: prepared.id,
        documentType: "E32",
        status: prepared.status,
        encf: null,
        numberingState: "PENDING_SANDBOX_SLOT",
        saleId: built.value.saleId,
        evidence: built.value.evidence,
      },
    };
  }

  /**
   * Prepara una nota de crédito E34 sobre un comprobante original aceptado.
   *
   * Las líneas y su clasificación fiscal salen del ORIGINAL (por el mismo
   * adaptador de ventas), nunca de la petición: el cliente solo decide QUÉ se
   * acredita. Solo se reserva el crédito fiscal — no se toca inventario, caja,
   * turnos, pagos ni abonos, y no se emite nada.
   */
  async prepareCreditNote(
    user: TenantUser,
    input: EcfCreditNoteInput,
  ): Promise<EcfFiscalResult<EcfCreditNoteResult>> {
    const companyId = requireTenant(user);

    if (!input.clientRequestId?.trim()) {
      return fiscalFailure(
        "ECF_CLIENT_REQUEST_ID_REQUIRED",
        "Cada nota de crédito requiere un identificador de operación.",
      );
    }
    if (!input.modificationReason?.trim()) {
      return fiscalFailure(
        "ECF_CREDIT_REASON_REQUIRED",
        "La nota de crédito requiere un motivo de modificación.",
      );
    }

    const enabled = await this.assertCompanyCanPrepare(user, companyId, "E34");
    if (!enabled.ok) return enabled;

    // Siempre por empresa: un identificador ajeno se comporta como inexistente.
    const original = await this.prisma.ecfElectronicDocument.findFirst({
      where: { id: input.originalDocumentId, companyId },
    });
    if (!original || !["E31", "E32"].includes(original.documentType)) {
      return fiscalFailure(
        "ECF_CREDIT_ORIGINAL_NOT_FOUND",
        "El comprobante original no existe para esta empresa o no es acreditable.",
      );
    }
    if (original.status !== "DGII_ACCEPTED") {
      return fiscalFailure(
        "ECF_CREDIT_ORIGINAL_NOT_ACCEPTED",
        "El comprobante original no está fiscalmente aceptado.",
      );
    }
    if (original.sourceType !== "SALE" || !original.sourceId) {
      return fiscalFailure(
        "ECF_CREDIT_ORIGINAL_WITHOUT_SOURCE",
        "El original no conserva su venta de origen; requiere revisión supervisada.",
      );
    }
    if (!original.externalDocumentNumber) {
      return fiscalFailure(
        "ECF_CREDIT_ORIGINAL_WITHOUT_ENCF",
        "El comprobante original no tiene e-NCF registrado.",
      );
    }

    // La referencia apunta a lo que el ORIGINAL tiene REGISTRADO (su instantánea
    // fiscal), no a la fecha de la venta: es la evidencia de cuándo y con qué
    // e-NCF se emitió. La regla de integridad E34 compara contra ese valor.
    const originalSnapshot = readFiscalSnapshot(original);

    // Líneas autoritativas del original, reutilizando el adaptador de ventas.
    const snapshot = await new EcfSaleFiscalAdapter(this.prisma).build(user, {
      saleId: original.sourceId,
      documentType: original.documentType as "E31" | "E32",
    });
    if (!snapshot.ok) return snapshot;

    const credit = buildCreditLines({
      originalLines: snapshot.value.snapshot.lines,
      refundKind: input.refundKind,
      requested: input.lines,
    });
    if (!credit.ok) return credit;

    const seller = snapshot.value.snapshot.seller;
    const buyer = snapshot.value.snapshot.buyer ?? {};
    const document: EcfFiscalDocument = {
      type: "E34",
      issueDate: new Date().toISOString().slice(0, 10),
      currency: originalSnapshot.currency as "DOP" | "USD" | "EUR",
      sender: {
        legalName: seller.legalName,
        taxId: seller.taxId,
        address: seller.address,
        phone: seller.phone,
        email: seller.email,
      },
      buyer: {
        legalName: buyer.legalName,
        taxId: buyer.taxId,
        address: buyer.address,
      },
      lines: credit.value.lines,
      totals: credit.value.totals,
      reference: {
        originalType: original.documentType as "E31" | "E32",
        originalENcf: originalSnapshot.encf,
        originalIssueDate: originalSnapshot.issueDate,
        modificationReason: input.modificationReason.trim(),
        refundKind: input.refundKind,
      },
    };

    const metadata = {
      paymentType: input.paymentType,
      creditNoteIndicator: input.creditNoteIndicator,
      modificationCode: input.modificationCode,
      ...(input.sequenceDueDate ? { sequenceDueDate: input.sequenceDueDate } : {}),
    } as EcfIssuanceMetadata;

    const metadataCheck = this.assertContractMetadata("E34", metadata);
    if (!metadataCheck.ok) return metadataCheck;

    // Pre-chequeo ADVISORY antes de consumir numeración. Preparar consume un
    // e-NCF y ese número NO se devuelve al pool, así que una nota que no cabe en
    // el saldo no debe gastar uno. La autoridad sigue siendo la guarda
    // transaccional de `reserve()`.
    //
    // Se OMITE cuando la operación ya existe: un reintento idempotente encuentra
    // el saldo consumido por su PROPIA reserva y rechazarlo rompería la
    // idempotencia (el mismo `clientRequestId` debe devolver el mismo documento).
    const idempotency = new EcfDocumentIdempotencyService(this.prisma);
    const replay = await this.prisma.ecfElectronicDocument.findUnique({
      where: {
        companyId_idempotencyKey: {
          companyId,
          idempotencyKey: idempotency.operationKeyFor({
            companyId,
            document,
            clientRequestId: input.clientRequestId,
          }),
        },
      },
      select: { id: true },
    });
    if (!replay) {
      const balance = await new EcfE34CreditService(this.prisma).balance(
        user,
        original.id,
      );
      if (dec(document.totals.total).gt(dec(balance.availableAmount))) {
        e34Conflict("E34_INSUFFICIENT_FISCAL_BALANCE");
      }
    }

    const note = await new EcfE34CreditService(this.prisma).prepareNote(user, {
      originalId: original.id,
      document,
      metadata,
      clientRequestId: input.clientRequestId,
    });

    const emission = (
      note.document.payloadSummary as Record<string, unknown> | null
    )?.emission as { encf?: string } | undefined;

    return {
      ok: true,
      value: {
        documentId: note.document.id,
        encf: emission?.encf ?? null,
        status: note.document.status,
        originalDocumentId: original.id,
        originalEncf: original.externalDocumentNumber,
        reservationState: note.reservation.state,
        reservedAmount: String(note.reservation.amount),
      },
    };
  }

  /**
   * Campos `idDoc.*` que el contrato oficial exige para este tipo. Se derivan
   * del esquema embebido, así que la exigencia viene del contrato y no de una
   * lista inventada aquí. El e-NCF se controla aparte (lo asigna el servidor).
   */
  private assertContractMetadata(
    documentType: "E31" | "E34",
    metadata: EcfIssuanceMetadata,
  ): EcfFiscalResult<true> {
    const required = ALANUBE_OFFICIAL_REQUIRED_FIELDS[documentType]
      .filter((path) => path.startsWith("idDoc."))
      .map((path) => path.slice("idDoc.".length))
      .filter((key) => key !== "encf");
    const record = metadata as Record<string, unknown>;
    const missing = required.filter((key) => {
      const value = record[key];
      return value === undefined || value === null || value === "";
    });
    if (missing.length > 0) {
      return fiscalFailure(
        "ECF_METADATA_REQUIRED",
        `Faltan datos fiscales exigidos por el contrato para ${documentType}: ${missing.join(", ")}.`,
      );
    }
    return { ok: true, value: true };
  }

  /**
   * Solo se prepara en empresas habilitadas, en Sandbox y con el tipo permitido.
   * La preparación consume numeración, así que el interruptor de empresa manda.
   */
  private async assertCompanyCanPrepare(
    user: TenantUser,
    companyId: string,
    documentType: string,
  ): Promise<EcfFiscalResult<true>> {
    const config = await this.prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId },
    });
    if (!config?.enabled) {
      return fiscalFailure(
        "ECF_COMPANY_DISABLED",
        "La facturación electrónica está apagada para esta empresa.",
      );
    }
    if (config.environment !== EcfEnvironment.SANDBOX) {
      return fiscalFailure(
        "ECF_ENVIRONMENT_BLOCKED",
        "Solo el ambiente Sandbox está permitido.",
      );
    }
    if (config.productionEnabled) {
      return fiscalFailure(
        "ECF_PRODUCTION_BLOCKED",
        "La empresa tiene habilitada la producción; esta operación no está autorizada.",
      );
    }
    const allowed = this.allowedTypes(config.allowedTypes);
    if (allowed.length > 0 && !allowed.includes(documentType)) {
      return fiscalFailure(
        "ECF_DOCUMENT_TYPE_NOT_ALLOWED",
        `El tipo ${documentType} no está habilitado para esta empresa.`,
      );
    }
    if (!user?.id) {
      return fiscalFailure("ECF_ACTOR_REQUIRED", "Se requiere un usuario identificado.");
    }
    return { ok: true, value: true };
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
