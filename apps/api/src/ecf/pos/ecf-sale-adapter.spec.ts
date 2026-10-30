import { mapSaleSnapshotToEcfDocument } from "./ecf-sale-adapter";
import { validateEcfDocument } from "../fiscal-core/ecf-validator";

describe("mapSaleSnapshotToEcfDocument", () => {
  it("maps a stable sale snapshot without touching sales services", () => {
    const document = mapSaleSnapshotToEcfDocument({
      type: "E31",
      issueDate: "2026-10-14",
      currency: "DOP",
      seller: { legalName: "FULLTECH SRL", taxId: "132109122" },
      buyer: { legalName: "Cliente", taxId: "00100000000" },
      lines: [
        {
          name: "Producto",
          quantity: 1,
          unitPrice: 100,
          taxCategory: "ITBIS_18",
          goodServiceIndicator: "GOOD",
        },
      ],
      totals: {
        subtotal: 100,
        taxableBase: 100,
        exemptAmount: 0,
        discountAmount: 0,
        itbisAmount: 18,
        total: 118,
      },
    });

    expect(validateEcfDocument(document).ok).toBe(true);
    expect(document.type).toBe("E31");
  });
});
