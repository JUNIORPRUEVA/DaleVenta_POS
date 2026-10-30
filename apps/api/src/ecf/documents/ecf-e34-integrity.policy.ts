import { ConflictException } from "@nestjs/common";
import { Prisma, type EcfElectronicDocument } from "@prisma/client";
import { dec, moneyString } from "../fiscal-core/ecf-money";

export type FiscalSnapshot = {
  total: string; currency: "DOP"; issueDate: string; issuerRnc: string;
  encf: string; evidenceRef: string; evidenceHash: string;
};
export function e34Conflict(code: string): never { throw new ConflictException(code); }

export function readFiscalSnapshot(document: EcfElectronicDocument): FiscalSnapshot {
  const snapshot = document.fiscalSnapshot as unknown as FiscalSnapshot | null;
  if (!snapshot || snapshot.currency !== "DOP" || !validDate(snapshot.issueDate) ||
      !/^\d{9,11}$/.test(snapshot.issuerRnc ?? "") ||
      !/^E(?:31|32|34)\d{10}$/.test(snapshot.encf ?? "") ||
      snapshot.encf !== document.externalDocumentNumber || !snapshot.encf.startsWith(document.documentType) || !document.externalProviderId ||
      typeof snapshot.evidenceRef !== "string" || !snapshot.evidenceRef.trim() ||
      !/^[0-9a-f]{64}$/.test(snapshot.evidenceHash ?? "")) e34Conflict("E34_FISCAL_EVIDENCE_REQUIRED");
  centAmount(snapshot.total);
  return snapshot;
}

export function centAmount(value: unknown): Prisma.Decimal {
  if (typeof value !== "string" || !/^\d+(?:\.\d{1,2})?$/.test(value)) e34Conflict("E34_AMOUNT_PRECISION_INVALID");
  const amount = dec(value);
  if (!amount.isFinite() || amount.lte(0) || amount.gte("1000000000000000000")) e34Conflict("E34_AMOUNT_INVALID");
  return amount;
}

export function validateE34Original(original: EcfElectronicDocument, note: EcfElectronicDocument) {
  if (original.companyId !== note.companyId || original.id === note.id) e34Conflict("E34_ORIGINAL_NOT_FOUND");
  // Conservative supported subset; this is not a claim that every other type
  // is legally forbidden by DGII.
  if (!["E31", "E32"].includes(original.documentType) || note.documentType !== "E34") e34Conflict("E34_REFERENCE_TYPE_UNSUPPORTED");
  if (original.status !== "DGII_ACCEPTED") e34Conflict("E34_ORIGINAL_NOT_FISCALLY_ACCEPTED");
  const snapshot = readFiscalSnapshot(original);
  if (!snapshot.encf.startsWith(original.documentType)) e34Conflict("E34_REFERENCE_MISMATCH");
  const summary = note.payloadSummary as Record<string, unknown> | null;
  const reference = summary?.reference as Record<string, unknown> | undefined;
  if (!summary || summary.currency !== snapshot.currency) e34Conflict("E34_CURRENCY_MISMATCH");
  if (!reference || reference.originalENcf !== snapshot.encf || reference.originalIssueDate !== snapshot.issueDate ||
      (reference.originalType && reference.originalType !== original.documentType) ||
      (note.originalDocumentId && note.originalDocumentId !== original.id)) e34Conflict("E34_REFERENCE_MISMATCH");
  if (!validDate(summary.issueDate) || String(summary.issueDate) < snapshot.issueDate) e34Conflict("E34_ISSUE_DATE_INVALID");
  return { original: snapshot, amount: centAmount(summary.total), originalTotal: centAmount(snapshot.total) };
}

export function creditAvailability(originalTotal: Prisma.Decimal, amounts: Array<{ state: string; amount: Prisma.Decimal }>) {
  const sum = (state: string) => amounts.filter((r) => r.state === state).reduce((a, r) => a.plus(r.amount), dec(0));
  const credited = sum("APPLIED"), reserved = sum("RESERVED"), unknown = sum("UNKNOWN_RESULT");
  const available = originalTotal.minus(credited).minus(reserved).minus(unknown);
  if (available.lt(0)) e34Conflict("E34_BALANCE_INTEGRITY_VIOLATION");
  return { originalAmount: moneyString(originalTotal), creditedAmount: moneyString(credited),
    reservedAmount: moneyString(reserved), unknownAmount: moneyString(unknown),
    rejectedAmount: moneyString(sum("REJECTED")), cancelledAmount: moneyString(sum("CANCELLED")),
    availableAmount: moneyString(available) };
}

function validDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.valueOf()) && date.toISOString().slice(0, 10) === value;
}
