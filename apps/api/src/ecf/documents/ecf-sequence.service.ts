import { BadRequestException, ConflictException, Injectable } from "@nestjs/common";
import type { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";

type Tx = Prisma.TransactionClient;
export type EcfSequenceDocumentType = "E31" | "E34";

// Only the document types that use a company e-CF range. E32 keeps its own
// single-use sandbox slot: it is deliberately NOT allocatable here.
const ALLOCATABLE: readonly EcfSequenceDocumentType[] = ["E31", "E34"];
// e-NCF = letter + 2-digit type + 10 digits (13 characters total).
const ENCF_PATTERN = /^E(31|34)\d{10}$/;
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
      throw new ConflictException("ECF_SEQUENCE_TYPE_UNSUPPORTED");
    }
    return documentType as EcfSequenceDocumentType;
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

  /** Tenant-scoped read of the company ranges. */
  async list(user: TenantUser) {
    const companyId = requireTenant(user);
    return this.prisma.ecfSequence.findMany({ where: { companyId }, orderBy: [{ documentType: "asc" }, { createdAt: "asc" }] });
  }

  /** Registers the first range for a company/documentType. One active range per type. */
  async register(user: TenantUser, input: {
    documentType: string; startNumber: number; endNumber: number; validUntil?: Date | string | null;
  }) {
    const companyId = requireTenant(user);
    const documentType = this.assertType(input.documentType);
    this.assertRange(input);
    const validUntil = this.parseValidUntil(input.validUntil);
    return this.prisma.$transaction(async (tx) => {
      const existing = await tx.ecfSequence.findFirst({ where: { companyId, documentType, active: true } });
      if (existing) throw new ConflictException("ECF_SEQUENCE_ALREADY_EXISTS");
      return tx.ecfSequence.create({ data: { companyId, documentType, prefix: documentType,
        startNumber: input.startNumber, nextNumber: input.startNumber, endNumber: input.endNumber, validUntil } });
    });
  }

  /**
   * Replaces the active range. The new range can never start below the consumed
   * frontier, so numbers already handed out are structurally impossible to reuse.
   */
  async renew(user: TenantUser, input: {
    documentType: string; startNumber: number; endNumber: number; validUntil?: Date | string | null;
  }) {
    const companyId = requireTenant(user);
    const documentType = this.assertType(input.documentType);
    this.assertRange(input);
    const validUntil = this.parseValidUntil(input.validUntil);
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM ecf_sequences WHERE company_id = ${companyId}::uuid AND document_type = ${documentType} FOR UPDATE`;
      const current = await tx.ecfSequence.findFirst({ where: { companyId, documentType, active: true } });
      if (!current) throw new ConflictException("ECF_SEQUENCE_NOT_FOUND");
      if (input.startNumber < current.nextNumber) throw new ConflictException("ECF_SEQUENCE_REUSE_BLOCKED");
      await tx.ecfSequence.updateMany({ where: { companyId, documentType, active: true }, data: { active: false } });
      const created = await tx.ecfSequence.create({ data: { companyId, documentType, prefix: documentType,
        startNumber: input.startNumber, nextNumber: input.startNumber, endNumber: input.endNumber, validUntil } });
      await tx.ecfSequenceAuditLog.create({ data: { companyId, sequenceId: created.id, userId: user.id,
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
  async allocate(user: TenantUser, documentType: string, options: { documentId?: string; operationKey?: string; tx?: Tx } = {}) {
    const companyId = requireTenant(user);
    if (options.operationKey) {
      const recorded = await this.alreadyAllocated(companyId, options.operationKey);
      if (recorded) return recorded;
    }
    const run = (tx: Tx) => this.allocateIn(tx, { companyId, userId: user.id, documentType,
      documentId: options.documentId, operationKey: options.operationKey });
    return options.tx ? run(options.tx) : this.prisma.$transaction(run);
  }

  /** Reads back an allocation already performed for the same operation key, if any. */
  async alreadyAllocated(companyId: string, operationKey: string) {
    const row = await this.prisma.ecfSequenceAuditLog.findFirst({
      where: { companyId, operationKey, action: "ALLOCATED" } });
    return row ? { encf: row.encf, sequenceId: row.sequenceId, type: row.type, validUntil: null } : null;
  }

  /** Transaction-aware variant, for callers that must allocate inside their own unit of work. */
  async allocateIn(tx: Tx, params: { companyId: string; userId: string; documentType: string;
    documentId?: string; operationKey?: string }) {
    const type = this.assertType(params.documentType);
    const rows = await tx.$queryRaw<SequenceRow[]>`
      SELECT id, company_id, document_type, prefix, start_number, next_number, end_number, valid_until, active
      FROM ecf_sequences
      WHERE company_id = ${params.companyId}::uuid
        AND document_type = ${type}
        AND active = true
      ORDER BY created_at ASC
      FOR UPDATE
    `;
    const now = new Date();
    const sequence = rows.find((row) => row.active
      && (!row.valid_until || row.valid_until.getTime() >= now.getTime())
      && row.next_number <= row.end_number);
    if (!sequence) throw new BadRequestException("ECF_SEQUENCE_EXHAUSTED");
    const encf = EcfSequenceService.encf(sequence.prefix, sequence.next_number);
    if (!ENCF_PATTERN.test(encf)) throw new ConflictException("ECF_SEQUENCE_PREFIX_INVALID");
    // Consumed permanently: the increment is the only mutation, and it is inside
    // the locked transaction, so two concurrent allocations can never collide.
    await tx.ecfSequence.update({ where: { id: sequence.id }, data: { nextNumber: { increment: 1 } } });
    await tx.ecfSequenceAuditLog.create({ data: { companyId: params.companyId, sequenceId: sequence.id,
      documentId: params.documentId ?? null, userId: params.userId, operationKey: params.operationKey ?? null,
      encf, type, action: "ALLOCATED" } });
    return { encf, sequenceId: sequence.id, type, validUntil: sequence.valid_until };
  }
}
