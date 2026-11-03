import { missingAlanubeOfficialRequiredFields } from "./alanube-official-required-fields";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";
import { validE31WithItbis, validE32Simple, validE34Partial } from "../fiscal-core/ecf-fixtures";

describe("Alanube official required-field presence (not complete schema validation)", () => {
  it.each([validE31WithItbis, validE32Simple, validE34Partial])("keeps local $type draft blocked with explicit missing official fields", (fixture) => {
    const mapping = mapEcfToAlanubeDom(fixture);
    expect(missingAlanubeOfficialRequiredFields(fixture.type, mapping.payload)).toContain("idDoc.encf");
    expect(missingAlanubeOfficialRequiredFields(fixture.type, mapping.payload)).not.toContain("sender.rnc");
    expect(mapping.contractStatus).toBe("BLOCKED_PENDING_SCHEMA");
  });

  it("distinguishes type-specific required metadata without inventing it", () => {
    const payload = { idDoc: { encf: "E310000000001", sequenceDueDate: "2026-12-31", incomeType: 1, paymentType: 1 },
      sender: { rnc: "synthetic", companyName: "Synthetic UAT", address: "Synthetic", stampDate: "2026-10-14" },
      buyer: { rnc: "synthetic", companyName: "Synthetic buyer" }, totals: { totalAmount: 0 }, itemDetails: [{}] };
    expect(missingAlanubeOfficialRequiredFields("E31", payload)).toEqual([]);
    expect(missingAlanubeOfficialRequiredFields("E34", payload)).toContain("informationReference.modificationCode");
    // Presence success does not approve the payload or permit sending it.
  });
});
