import { BadRequestException, ConflictException, Injectable } from "@nestjs/common";
import type { EcfEnvironment, Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { checkDeclaredRangeWithinAuthorization } from "./ecf-dgii-authorized-sequences.policy";
import { EcfDgiiAuthorizedSequencesService } from "./ecf-dgii-authorized-sequences.service";

import { lockNumberingEnvironment, numberingEnvironment } from "./ecf-numbering-environment";
import { hasReviewedLegacyTestProof } from "../ecf-reviewed-test-readiness";

type Tx = Prisma.TransactionClient;
export type EcfSequenceDocumentType = "E31" | "E32" | "E34";

// Los tres tipos que consumen el rango e-CF de la empresa. E32 (consumo) entra
// aquí porque el POS emite facturas de consumo con su propia numeración
// autorizada; antes estaba reservado al cupo único de sandbox, que solo servía
// para pruebas y dejaba los comprobantes reales sin número fiscal.
const ALLOCATABLE: readonly EcfSequenceDocumentType[] = ["E31", "E32", "E34"];
// e-NCF = letter + 2-digit type + 10 digits (13 characters total).
const ENCF_PATTERN = /^E(31|32|34)\d{10}$/;
const MAX_SEQUENCE_NUMBER = 9_999_999_999;

type SequenceRow = {
  id: string; company_id: string; document_type: string; prefix: string; start_number: number;
  next_number: number; end_number: number; valid_until: Date | null; active: boolean;
};

// Server-side e-CF numbering. A number is consumed permanently at allocation
// time: next_number only ever increases, so a consumed e-NCF can never be
// handed out again — not after a cancellation, a failed emission, or a retry.
@Injectable()
export class EcfSequenceService {
  constructor(private readonly prisma: PrismaService) {}

  /** Formats an e-NCF from its prefix and sequence number. */
  static encf(prefix: string, number: number) {
    return `${prefix}${String(number).padStart(10, "0")}`;
  }

  private assertType(documentType: string): EcfSequenceDocumentType {
    if (!ALLOCATABLE.includes(documentType as EcfSequenceDocumentType)) {
      // Un tipo desconocido no está «pendiente»: no tiene contrato, no tiene
      // autorización y no hay forma de numerarlo. Se rechaza con un motivo que
      // el operador puede accionar, no con un código seco.
      const normalized = `${documentType ?? ""}`.trim().toUpperCase();
      throw new ConflictException(
        `ECF_SEQUENCE_TYPE_UNSUPPORTED: Tipo de comprobante no numerable: ` +
          `${normalized || "(vacío)"}. Tipos admitidos: ${ALLOCATABLE.join(", ")}.`,
      );
    }
    return documentType as EcfSequenceDocumentType;
  }

  /**
   * El rango declarado debe caber dentro de lo que la DGII autorizó a ESTA
   * empresa para ESE tipo. Sin autorización registrada no se declara nada: es la
   * compuerta que impide pedir más números de los aprobados.
   */
  private async assertWithinAuthorization(
    companyId: string,
    documentType: EcfSequenceDocumentType,
    range: { startNumber: number; endNumber: number },
    environment: EcfEnvironment,
  ) {
    const authorization = await new EcfDgiiAuthorizedSequencesService(
      this.prisma,
    ).findFor(companyId, documentType, environment);
    const check = checkDeclaredRangeWithinAuthorization(range, authorization);
    if (!check.ok) {
      throw new ConflictException(`${check.code}: ${check.message}`);
    }
  }

  /**
   * Comprueba el número concreto que se va a entregar contra la autorización de
   * la DGII. Se ejecuta DENTRO de la transacción que bloquea la secuencia, así
   * que ni una llamada concurrente ni un camino alternativo pueden saltárselo.
   */
  private async assertNumberWithinAuthorization(
    tx: Tx,
    companyId: string,
    documentType: EcfSequenceDocumentType,
    number: number,
    environment: EcfEnvironment,
  ) {
    const authorization = await tx.ecfDgiiAuthorizedSequence.findUnique({
      where: { companyId_documentType: { companyId, documentType, environment } },
    });
    const check = checkDeclaredRangeWithinAuthorization(
      { startNumber: number, endNumber: number },
      authorization === null
        ? null
        : {
            authorizationNumber: authorization.authorizationNumber,
            rangeFrom: authorization.rangeFrom,
            rangeTo: authorization.rangeTo,
            approvedQuantity: authorization.approvedQuantity,
            expiresAt: authorization.expiresAt,
          },
    );
    if (!check.ok) {
      throw new ConflictException(`${check.code}: ${check.message}`);
    }
  }

  private assertRange(input: { startNumber: number; endNumber: number }) {
    const valid = Number.isInteger(input.startNumber) && Number.isInteger(input.endNumber)
      && input.startNumber >= 1 && input.endNumber >= input.startNumber
      && input.endNumber <= MAX_SEQUENCE_NUMBER;
    if (!valid) throw new BadRequestException("ECF_SEQUENCE_RANGE_INVALID");
  }

  private parseValidUntil(value: Date | string | null | undefined) {
    if (value === undefined || value === null) return null;
    const parsed = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(parsed.getTime())) throw new BadRequestException("ECF_SEQUENCE_VALID_UNTIL_INVALID");
    return parsed;
  }

  /** Legacy TEST allocations retain their original ledger/environment. Their
   * reviewed frontier must still protect a newly declared SANDBOX range.
   * It is a lower bound only, never a copied authorization or counter reset.
   */
  private async assertLegacyTestFrontier(tx: Tx, companyId: string, type: EcfSequenceDocumentType, number: number, environment: EcfEnvironment) {
    if (environment !== "SANDBOX") return;
    const documents = await tx.ecfElectronicDocument.findMany({ where: { companyId, documentType: type,
      OR: [{ environment: null }, { environment: "SANDBOX" }],
      payloadSummary: { path: ["controlledTest", "environment"], equals: "TEST" } }, take: 101,
      select: { id: true, environment: true, status: true, sourceType: true, sourceId: true, payloadFingerprint: true, payloadSummary: true,
        statusLogs: { where: { companyId, reasonCode: "LEGACY_TEST_ENVIRONMENT_CLASSIFIED" },
          orderBy: { createdAt: "desc" }, take: 1, select: { metadata: true } } } });
    if (!documents.length) return;
    const reviewRequired = () => new ConflictException("ECF_SEQUENCE_LEGACY_TEST_REVIEW_REQUIRED");
    if (documents.length > 100 || documents.some(doc => doc.environment !== "SANDBOX" || !hasReviewedLegacyTestProof(doc))) throw reviewRequired();
    const identities = documents.map(doc => {
      const summary = doc.payloadSummary as { emission?: { encf?: string } } | null;
      const review = doc.statusLogs[0].metadata as { originalAllocationId?: string };
      const encf = summary?.emission?.encf ?? "";
      if (!new RegExp(`^${type}\\d{10}$`).test(encf) || !/^[a-f0-9-]{36}$/i.test(review.originalAllocationId ?? "")) throw reviewRequired();
      return { documentId: doc.id, allocationId: review.originalAllocationId!, encf };
    });
    const ledger = await tx.ecfSequenceAuditLog.findMany({ where: { companyId, id: { in: identities.map(row => row.allocationId) }, action: "ALLOCATED", type },
      select: { id: true, documentId: true, sequenceId: true, encf: true } });
    if (identities.some(row => !ledger.some(log => log.id === row.allocationId && log.documentId === row.documentId && log.encf === row.encf && log.sequenceId))) throw reviewRequired();
    const ranges = await tx.ecfSequence.findMany({ where: { companyId, id: { in: ledger.map(row => row.sequenceId!) } }, select: { id: true, nextNumber: true } });
    if (ledger.some(row => !ranges.some(range => range.id === row.sequenceId))) throw reviewRequired();
    const minimum = Math.max(...identities.map(row => Number(row.encf.slice(3)) + 1), ...ranges.map(range => range.nextNumber));
    if (number < minimum) throw new ConflictException({ code: "ECF_SEQUENCE_LEGACY_TEST_REUSE_BLOCKED",
      message: `La empresa ya utilizó numeración de pruebas. Inicia en ${minimum} o posterior.`, minimumStartNumber: minimum });
  }

  /** Tenant-scoped read of the company ranges. */
  async list(user: TenantUser) {
    const companyId = requireTenant(user);
    return this.prisma.ecfSequence.findMany({ where: { companyId, environment: await numberingEnvironment(this.prisma, companyId) }, orderBy: [{ documentType: "asc" }, { createdAt: "asc" }] });
  }

  /** Registers the first range for a company/documentType. One active range per type. */
  async register(user: TenantUser, input: {
    documentType: string; startNumber: number; endNumber: number; validUntil?: Date | string | null; expectedEnvironment?: EcfEnvironment;
  }) {
    const companyId = requireTenant(user);
    const documentType = this.assertType(input.documentType);
    const environment = await numberingEnvironment(this.prisma, companyId);
    if (input.expectedEnvironment && input.expectedEnvironment !== environment) throw new ConflictException("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    this.assertRange(input);
    await this.assertWithinAuthorization(companyId, documentType, input, environment);
    const validUntil = this.parseValidUntil(input.validUntil);
    return this.prisma.$transaction(async (tx) => {
      await lockNumberingEnvironment(tx, companyId, environment);
      await this.assertLegacyTestFrontier(tx, companyId, documentType, input.startNumber, environment);
      const existing = await tx.ecfSequence.findFirst({ where: { companyId, environment, documentType, active: true } });
      if (existing) throw new ConflictException("ECF_SEQUENCE_ALREADY_EXISTS");
      return tx.ecfSequence.create({ data: { companyId, environment, documentType, prefix: documentType,
        startNumber: input.startNumber, nextNumber: input.startNumber, endNumber: input.endNumber, validUntil } });
    });
  }

  /**
   * Replaces the active range. The new range can never start below the consumed
   * frontier, so numbers already handed out are structurally impossible to reuse.
   */
  async renew(user: TenantUser, input: {
    documentType: string; startNumber: number; endNumber: number; validUntil?: Date | string | null; expectedEnvironment?: EcfEnvironment;
  }) {
    const companyId = requireTenant(user);
    const documentType = this.assertType(input.documentType);
    const environment = await numberingEnvironment(this.prisma, companyId);
    if (input.expectedEnvironment && input.expectedEnvironment !== environment) throw new ConflictException("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    this.assertRange(input);
    await this.assertWithinAuthorization(companyId, documentType, input, environment);
    const validUntil = this.parseValidUntil(input.validUntil);
    return this.prisma.$transaction(async (tx) => {
      await lockNumberingEnvironment(tx, companyId, environment);
      await this.assertLegacyTestFrontier(tx, companyId, documentType, input.startNumber, environment);
      await tx.$queryRaw`SELECT id FROM ecf_sequences WHERE company_id = ${companyId}::uuid AND document_type = ${documentType} AND environment = ${environment}::ecf_environment FOR UPDATE`;
      const current = await tx.ecfSequence.findFirst({ where: { companyId, environment, documentType, active: true } });
      if (!current) throw new ConflictException("ECF_SEQUENCE_NOT_FOUND");
      if (input.startNumber < current.nextNumber) throw new ConflictException("ECF_SEQUENCE_REUSE_BLOCKED");
      await tx.ecfSequence.updateMany({ where: { companyId, environment, documentType, active: true }, data: { active: false } });
      const created = await tx.ecfSequence.create({ data: { companyId, environment, documentType, prefix: documentType,
        startNumber: input.startNumber, nextNumber: input.startNumber, endNumber: input.endNumber, validUntil } });
      await tx.ecfSequenceAuditLog.create({ data: { companyId, environment, sequenceId: created.id, userId: user.id,
        encf: EcfSequenceService.encf(documentType, input.startNumber), type: documentType, action: "RENEWED" } });
      return created;
    });
  }

  /**
   * Allocates and permanently consumes the next e-NCF for the company.
   * Concurrency-safe: the range row is locked FOR UPDATE before it is incremented.
   * With an operationKey, the same operation can never allocate twice: the ledger
   * carries a unique (company, operation_key) index, so a retry re-reads the e-NCF
   * it already consumed instead of burning a second number.
   */
  async allocate(user: TenantUser, documentType: string, options: { documentId?: string; operationKey?: string; tx?: Tx; environment?: EcfEnvironment } = {}) {
    const companyId = requireTenant(user);
    if (options.environment && options.environment !== await numberingEnvironment(this.prisma, companyId)) {
      throw new ConflictException("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    }
    if (options.operationKey) {
      const recorded = await this.alreadyAllocated(companyId, options.operationKey);
      if (recorded) return recorded;
    }
    const run = (tx: Tx) => this.allocateIn(tx, { companyId, userId: user.id, documentType,
      documentId: options.documentId, operationKey: options.operationKey, environment: options.environment });
    return options.tx ? run(options.tx) : this.prisma.$transaction(run);
  }

  /** Reads back an allocation already performed for the same operation key, if any. */
  async alreadyAllocated(companyId: string, operationKey: string) {
    const environment = await numberingEnvironment(this.prisma, companyId);
    const row = await this.prisma.ecfSequenceAuditLog.findFirst({
      where: { companyId, environment, operationKey, action: "ALLOCATED" } });
    return row ? { encf: row.encf, sequenceId: row.sequenceId, type: row.type, validUntil: null } : null;
  }

  /** Transaction-aware variant, for callers that must allocate inside their own unit of work. */
  async allocateIn(tx: Tx, params: { companyId: string; userId: string; documentType: string;
    documentId?: string; operationKey?: string; environment?: EcfEnvironment }) {
    const type = this.assertType(params.documentType);
    const environment = await numberingEnvironment(tx, params.companyId);
    await lockNumberingEnvironment(tx, params.companyId, environment);
    if (params.environment && params.environment !== environment) throw new ConflictException("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    const rows = await tx.$queryRaw<SequenceRow[]>`
      SELECT id, company_id, document_type, prefix, start_number, next_number, end_number, valid_until, active
      FROM ecf_sequences
      WHERE company_id = ${params.companyId}::uuid
        AND document_type = ${type}
        AND environment = ${environment}::ecf_environment
        AND active = true
      ORDER BY created_at ASC
      FOR UPDATE
    `;
    const now = new Date();
    const sequence = rows.find((row) => row.active
      && (!row.valid_until || row.valid_until.getTime() >= now.getTime())
      && row.next_number <= row.end_number);
    if (!sequence) throw new BadRequestException("ECF_SEQUENCE_EXHAUSTED");
    await this.assertLegacyTestFrontier(tx, params.companyId, type, sequence.next_number, environment);
    const encf = EcfSequenceService.encf(sequence.prefix, sequence.next_number);
    if (!ENCF_PATTERN.test(encf)) throw new ConflictException("ECF_SEQUENCE_PREFIX_INVALID");
    // Blindaje de último paso: NINGÚN e-NCF sale fuera del rango que la DGII
    // autorizó a esta empresa para este tipo, aunque alguien llame al asignador
    // sin pasar por `register`. Sin autorización declarada no se entrega número.
    await this.assertNumberWithinAuthorization(
      tx,
      params.companyId,
      type,
      sequence.next_number,
      environment,
    );
    // Consumed permanently: the increment is the only mutation, and it is inside
    // the locked transaction, so two concurrent allocations can never collide.
    const claimed = await tx.ecfSequence.updateMany({
      where: { id: sequence.id, companyId: params.companyId, environment },
      data: { nextNumber: { increment: 1 } },
    });
    if (claimed.count !== 1) throw new ConflictException("ECF_SEQUENCE_NOT_FOUND");
    await tx.ecfSequenceAuditLog.create({ data: { companyId: params.companyId, environment, sequenceId: sequence.id,
      documentId: params.documentId ?? null, userId: params.userId, operationKey: params.operationKey ?? null,
      encf, type, action: "ALLOCATED" } });
    return { encf, sequenceId: sequence.id, type, validUntil: sequence.valid_until };
  }
}
