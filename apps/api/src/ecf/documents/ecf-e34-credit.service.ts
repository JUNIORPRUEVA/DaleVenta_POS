import { Injectable } from "@nestjs/common";
import { Prisma, type EcfCreditReservationState } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { fingerprint } from "./ecf-document-idempotency.service";
import { centAmount, creditAvailability, e34Conflict, readFiscalSnapshot, validateE34Original } from "./ecf-e34-integrity.policy";
import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";
import { EcfEmissionService } from "./ecf-emission.service";

@Injectable()
export class EcfE34CreditService {
  constructor(private readonly prisma: PrismaService) {}

  // Full E34 preparation: validates the original's fiscal eligibility, prepares the
  // local note and reserves the credit idempotently. No network, no emission; the
  // reservation is what later authorizes dispatchOnce (see EcfEmissionService).
  async prepareNote(user: TenantUser, input: {
    originalId: string; document: EcfFiscalDocument; metadata: EcfIssuanceMetadata;
    sourceType?: "SALE" | "COTIZACION" | "MANUAL"; sourceId?: string; clientRequestId?: string;
  }) {
    const companyId = requireTenant(user);
    if (input.document.type !== "E34") e34Conflict("E34_NOTE_TYPE_REQUIRED");
    const original = await this.prisma.ecfElectronicDocument.findFirst({ where: { id: input.originalId, companyId } });
    if (!original) e34Conflict("E34_ORIGINAL_NOT_FOUND");
    if (original.status !== "DGII_ACCEPTED") e34Conflict("E34_ORIGINAL_NOT_FISCALLY_ACCEPTED");
    if (!["E31", "E32"].includes(original.documentType)) e34Conflict("E34_REFERENCE_TYPE_UNSUPPORTED");
    const document = await new EcfEmissionService(this.prisma).prepare(user, input);
    const reservation = await this.reserve(user, input.originalId, document.id);
    return { document, reservation };
  }

  // Internal only: no controller, sender, fiscal numbering or external calls.
  async reserve(user: TenantUser, originalId: string, creditId: string) {
    const companyId = requireTenant(user);
    return this.prisma.$transaction(async (tx) => {
      await this.lockDocuments(tx, companyId, [originalId, creditId]);
      const original = await tx.ecfElectronicDocument.findFirst({ where: { id: originalId, companyId } });
      const note = await tx.ecfElectronicDocument.findFirst({ where: { id: creditId, companyId } });
      if (!original || !note) e34Conflict("E34_ORIGINAL_NOT_FOUND");
      const requestFingerprint = fingerprint({ originalId, creditId, payload: note.payloadFingerprint, summary: note.payloadSummary });
      const existing = await tx.ecfCreditReservation.findUnique({ where: { companyId_creditDocumentId: { companyId, creditDocumentId: creditId } } });
      if (existing) {
        if (existing.requestFingerprint !== requestFingerprint || existing.originalDocumentId !== originalId) e34Conflict("E34_IDEMPOTENCY_PAYLOAD_MISMATCH");
        return existing;
      }
      if (!["LOCAL_VALIDATED", "READY_TO_SEND"].includes(note.status)) e34Conflict("E34_NOTE_NOT_LOCALLY_READY");
      const verified = validateE34Original(original, note);
      await this.assertEvidence(tx, companyId, originalId, "DGII_ACCEPTED", verified.original.evidenceRef, verified.original.evidenceHash);
      const balance = await this.balanceInTransaction(tx, companyId, originalId, verified.originalTotal);
      if (verified.amount.gt(balance.availableAmount)) e34Conflict("E34_INSUFFICIENT_FISCAL_BALANCE");
      await tx.ecfElectronicDocument.updateMany({ where: { id: creditId, companyId, originalDocumentId: null }, data: { originalDocumentId: originalId } });
      await tx.$queryRaw`SELECT set_config('fullpos.ecf_actor', ${user.id}, true)`;
      const reservation = await tx.ecfCreditReservation.create({ data: {
        companyId, originalDocumentId: originalId, creditDocumentId: creditId,
        amount: verified.amount, requestFingerprint,
      } });
      return reservation;
    });
  }

  async balance(user: TenantUser, originalId: string) {
    const companyId = requireTenant(user);
    return this.prisma.$transaction(async (tx) => {
      await this.lockDocuments(tx, companyId, [originalId]);
      const original = await tx.ecfElectronicDocument.findFirst({ where: { id: originalId, companyId } });
      if (!original) e34Conflict("E34_ORIGINAL_NOT_FOUND");
      if (!["E31", "E32"].includes(original.documentType)) e34Conflict("E34_REFERENCE_TYPE_UNSUPPORTED");
      const snapshot = readFiscalSnapshot(original);
      if (original.status !== "DGII_ACCEPTED") e34Conflict("E34_ORIGINAL_NOT_FISCALLY_ACCEPTED");
      await this.assertEvidence(tx, companyId, originalId, "DGII_ACCEPTED", snapshot.evidenceRef, snapshot.evidenceHash);
      return this.balanceInTransaction(tx, companyId, originalId, centAmount(snapshot.total));
    });
  }

  async transition(user: TenantUser, creditId: string, state: EcfCreditReservationState) {
    const companyId = requireTenant(user);
    const known = await this.prisma.ecfCreditReservation.findUnique({ where: { companyId_creditDocumentId: { companyId, creditDocumentId: creditId } } });
    if (!known) e34Conflict("E34_RESERVATION_NOT_FOUND");
    return this.prisma.$transaction(async (tx) => {
      await this.lockDocuments(tx, companyId, [known.originalDocumentId, creditId]);
      const reservation = await tx.ecfCreditReservation.findUniqueOrThrow({ where: { companyId_creditDocumentId: { companyId, creditDocumentId: creditId } } });
      if (reservation.state === state) return reservation;
      if (!["RESERVED", "UNKNOWN_RESULT"].includes(reservation.state) || state === "RESERVED") e34Conflict("E34_RESERVATION_TRANSITION_INVALID");
      const note = await tx.ecfElectronicDocument.findFirstOrThrow({ where: { id: creditId, companyId } });
      if (state === "CANCELLED") {
        if (reservation.state !== "RESERVED" || !["LOCAL_VALIDATED", "READY_TO_SEND", "CANCELLED"].includes(note.status)) e34Conflict("E34_UNKNOWN_OR_SUBMITTED_CANNOT_RELEASE");
      } else if (state === "APPLIED" || state === "REJECTED") {
        const expected = state === "APPLIED" ? "DGII_ACCEPTED" : "DGII_REJECTED";
        if (note.status !== expected) e34Conflict("E34_OUTCOME_EVIDENCE_REQUIRED");
        const evidence = readFiscalSnapshot(note);
        const original = await tx.ecfElectronicDocument.findFirstOrThrow({ where: { id: known.originalDocumentId, companyId } });
        const verified = validateE34Original(original, note);
        if (note.originalDocumentId !== original.id || !centAmount(evidence.total).eq(reservation.amount) ||
            !verified.amount.eq(reservation.amount) || evidence.issuerRnc !== verified.original.issuerRnc) e34Conflict("E34_OUTCOME_SNAPSHOT_MISMATCH");
        await this.assertEvidence(tx, companyId, creditId, expected, evidence.evidenceRef, evidence.evidenceHash);
      } else if (state !== "UNKNOWN_RESULT") e34Conflict("E34_RESERVATION_TRANSITION_INVALID");
      await tx.$queryRaw`SELECT set_config('fullpos.ecf_actor', ${user.id}, true)`;
      const updated = await tx.ecfCreditReservation.update({ where: { companyId_creditDocumentId: { companyId, creditDocumentId: creditId } }, data: { state } });
      return updated;
    });
  }

  private async lockDocuments(tx: Prisma.TransactionClient, companyId: string, ids: string[]) {
    // Stable row ordering prevents opposite original/note lock orders.
    await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id IN (${Prisma.join(ids.map((id) => Prisma.sql`${id}::uuid`))}) ORDER BY id FOR UPDATE`;
  }

  private async assertEvidence(tx: Prisma.TransactionClient, companyId: string, documentId: string,
    status: "DGII_ACCEPTED" | "DGII_REJECTED", ref: string, hash: string) {
    const log = await tx.ecfElectronicDocumentStatusLog.findFirst({ where: { companyId, documentId, statusAfter: status,
      metadata: { path: ["evidenceHash"], equals: hash } }, orderBy: { createdAt: "desc" } });
    if (!log || (log.metadata as Record<string, unknown> | null)?.evidenceRef !== ref) e34Conflict("E34_OUTCOME_EVIDENCE_REQUIRED");
  }

  private async balanceInTransaction(tx: Prisma.TransactionClient, companyId: string, originalId: string, total: Prisma.Decimal) {
    const untracked = await tx.ecfElectronicDocument.count({ where: { companyId, originalDocumentId: originalId,
      documentType: "E34", status: { notIn: ["LOCAL_DRAFT", "LOCAL_VALIDATION_PENDING", "LOCAL_VALIDATED", "READY_TO_SEND", "CANCELLED"] },
      creditReservation: { is: null } } });
    if (untracked) e34Conflict("E34_UNTRACKED_CREDITS_REQUIRE_REVIEW");
    const reservations = await tx.ecfCreditReservation.findMany({ where: { companyId, originalDocumentId: originalId }, select: { state: true, amount: true } });
    return creditAvailability(total, reservations);
  }
}
