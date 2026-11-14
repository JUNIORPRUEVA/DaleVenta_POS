import { ecfPrintView } from "./ecf-print-view";
import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";

const fiscal: EcfFiscalDocument = {
  type: "E34", issueDate: "2026-11-13", currency: "DOP",
  sender: { legalName: "Emisor sintético", taxId: "101000001" },
  lines: [
    { lineNumber: 1, name: "Gravado", goodServiceIndicator: "GOOD", quantity: "2.5", unitPrice: "40", discountAmount: "10", taxCategory: "ITBIS_18", taxRate: ".18", unitOfMeasure: "UNIT" },
    { lineNumber: 2, name: "Exento", goodServiceIndicator: "GOOD", quantity: "1", unitPrice: "20", taxCategory: "EXEMPT", taxRate: "0" },
  ],
  totals: { subtotal: "110", taxableBase: "90", exemptAmount: "20", discountAmount: "10", itbisAmount: "16.20", total: "126.20" },
  reference: { originalENcf: "E310000000001", originalIssueDate: "2026-11-12", modificationReason: "Devolución parcial" },
};
const row = { id: "synthetic", documentType: "E34", environment: "SANDBOX", status: "HUMAN_REVIEW_REQUIRED",
  externalDocumentNumber: "E340000000001", fiscalDocument: fiscal,
  payloadSummary: { emission: { payload: { informationReference: { modificationCode: 3 } } },
    privateRawResponse: "must-not-leak", printStamp: { qrUrl: "https://ecf.dgii.gov.do/testecf/ConsultaTimbre", securityCode: "ABC123", signedAt: "13-11-2026 12:00:00" } } };

describe("public fiscal print projection", () => {
  it("prints only the note's credited quantities, tax and discount, with reference", () => {
    const view = ecfPrintView(row)!;
    expect(view).toMatchObject({ state: "SIGNED", total: "126.20", originalEncf: "E310000000001", expiresAt: null,
      modificationText: "Corrige montos del NCF modificado", originalIssueDate: "2026-11-12", modificationReason: "Devolución parcial" });
    expect(view.lines).toMatchObject([
      { quantity: "2.5", taxableBase: "90.00", taxAmount: "16.20", discount: "10.00", total: "106.20" },
      { exemptAmount: "20.00", taxAmount: "0.00", total: "20.00", taxExempt: true },
    ]);
    expect(JSON.stringify(view)).not.toContain("must-not-leak");
  });
  it("never exposes a stamp for rejected or unclassified documents", () => {
    expect(ecfPrintView({ ...row, environment: null })).toBeNull();
    expect(ecfPrintView({ ...row, fiscalDocument: {} })).toBeNull();
    expect(ecfPrintView({ ...row, status: "DGII_REJECTED" })).toMatchObject({ state: "REJECTED", qrUrl: null });
    expect(ecfPrintView({ ...row, payloadSummary: {} })).toMatchObject({ state: "PENDING", securityCode: null });
  });
});
