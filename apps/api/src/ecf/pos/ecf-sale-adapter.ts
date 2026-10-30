import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";

export type EcfSaleSnapshotLine = {
  name: string;
  quantity: string | number;
  unitPrice: string | number;
  discountAmount?: string | number;
  taxCategory: "ITBIS_18" | "ITBIS_16" | "ITBIS_0" | "EXEMPT";
  goodServiceIndicator: "GOOD" | "SERVICE";
};

export type EcfSaleSnapshot = {
  type: "E31" | "E32";
  issueDate: string;
  currency: "DOP" | "USD" | "EUR";
  seller: { legalName: string; taxId: string; tradeName?: string; address?: string; phone?: string; email?: string };
  buyer?: { legalName?: string; taxId?: string; address?: string; phone?: string; email?: string };
  lines: EcfSaleSnapshotLine[];
  totals: EcfFiscalDocument["totals"];
};

export function mapSaleSnapshotToEcfDocument(
  sale: EcfSaleSnapshot,
): EcfFiscalDocument {
  return {
    type: sale.type,
    issueDate: sale.issueDate,
    currency: sale.currency,
    sender: sale.seller,
    buyer: sale.buyer,    totals: sale.totals,
    lines: sale.lines.map((line, index) => ({
      lineNumber: index + 1,
      name: line.name,
      goodServiceIndicator: line.goodServiceIndicator,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discountAmount: line.discountAmount ?? 0,
      taxCategory: line.taxCategory,
      taxRate: line.taxCategory === "ITBIS_18" ? 0.18 : line.taxCategory === "ITBIS_16" ? 0.16 : 0,
    })),
  };
}
