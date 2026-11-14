import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";
import { dec, money, moneyString } from "../fiscal-core/ecf-money";

const LABELS: Record<string, string> = {
  E31: "Factura de Crédito Fiscal Electrónica",
  E32: "Factura de Consumo Electrónica",
  E34: "Nota de Crédito Electrónica",
};

/** Explicit public projection. Never return raw provider payloads. */
export function ecfPrintView(row: {
  id: string; documentType: string; environment: string | null; status: string;
  externalDocumentNumber: string | null; payloadSummary: unknown; fiscalDocument: unknown; printStamp?: unknown;
}) {
  const summary = (row.payloadSummary ?? {}) as Record<string, any>;
  const fiscal = row.fiscalDocument as EcfFiscalDocument | null;
  if (!fiscal || !LABELS[row.documentType] || !row.environment ||
      !Array.isArray(fiscal.lines) || !fiscal.totals || !fiscal.sender) return null;
  const stamp = (row.printStamp ?? summary.printStamp) as Record<string, any> | null;
  const rejected = ["DGII_REJECTED", "PROVIDER_REJECTED", "CANCELLED"].includes(row.status);
  const complete = !rejected && stamp && typeof stamp.qrUrl === "string" && typeof stamp.securityCode === "string" && typeof stamp.signedAt === "string";
  const metadata = summary.emission?.payload?.idDoc;
  return {
    documentId: row.id, documentType: row.documentType, label: LABELS[row.documentType],
    environment: row.environment, state: rejected ? "REJECTED" : row.status === "DGII_STATUS_PENDING"
      ? complete && stamp?.contingencyLegend ? "CONTINGENCY" : "PENDING" : complete ? "SIGNED" : "PENDING",
    contingencyLegend: row.status === "DGII_STATUS_PENDING" ? stamp?.contingencyLegend ?? null : null,
    encf: row.externalDocumentNumber ?? summary.emission?.encf ?? null,
    issueDate: fiscal.issueDate, total: String(fiscal.totals.total),
    subtotal: String(fiscal.totals.subtotal),
    currency: fiscal.currency,
    taxableBase: String(fiscal.totals.taxableBase),
    exemptAmount: String(fiscal.totals.exemptAmount),
    itbisAmount: String(fiscal.totals.itbisAmount),
    discountAmount: String(fiscal.totals.discountAmount),
    lines: fiscal.lines.map((line) => {
      const amount = money(dec(line.quantity).mul(line.unitPrice).minus(line.discountAmount ?? 0));
      const tax = money(amount.mul(line.taxRate));
      return {
        name: line.name, quantity: String(line.quantity), unitPrice: String(line.unitPrice),
        unitOfMeasure: line.unitOfMeasure ?? null,
        discount: moneyString(line.discountAmount ?? 0),
        taxableBase: line.taxCategory === "EXEMPT" ? "0.00" : moneyString(amount),
        exemptAmount: line.taxCategory === "EXEMPT" ? moneyString(amount) : "0.00",
        taxAmount: moneyString(tax), total: moneyString(amount.plus(tax)),
        taxExempt: line.taxCategory === "EXEMPT",
      };
    }),
    issuerName: fiscal.sender.legalName, issuerRnc: fiscal.sender.taxId,
    issuerAddress: fiscal.sender.address ?? null,
    buyerName: fiscal.buyer?.legalName ?? null, buyerRnc: fiscal.buyer?.taxId ?? null,
    expiresAt: row.documentType === "E31" ? metadata?.sequenceDueDate ?? null : null,
    originalEncf: fiscal.reference?.originalENcf ?? null,
    originalIssueDate: fiscal.reference?.originalIssueDate ?? null,
    modificationReason: fiscal.reference?.modificationReason ?? null,
    modificationText: row.documentType === "E34" ? ({1: "Anula el NCF modificado", 2: "Corrige texto del comprobante fiscal modificado", 3: "Corrige montos del NCF modificado"} as Record<string, string>)[String(metadata?.modificationCode ?? summary.emission?.payload?.informationReference?.modificationCode)] ?? null : null,
    qrUrl: complete ? stamp.qrUrl : null, securityCode: complete ? stamp.securityCode : null,
    signedAt: complete ? stamp.signedAt : null,
  };
}
