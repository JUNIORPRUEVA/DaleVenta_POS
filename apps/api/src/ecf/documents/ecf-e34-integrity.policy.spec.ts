import { centAmount, creditAvailability, validateE34Original } from "./ecf-e34-integrity.policy";
import { dec } from "../fiscal-core/ecf-money";

function pair() {
  const original = { id: "original", companyId: "tenant", documentType: "E31", status: "DGII_ACCEPTED",
    externalDocumentNumber: "E310000000001", externalProviderId: "synthetic-provider-id",
    fiscalSnapshot: { total: "118.00", currency: "DOP", issueDate: "2026-10-14", issuerRnc: "101000001",
      encf: "E310000000001", evidenceRef: "uat://synthetic", evidenceHash: "a".repeat(64) } };
  const note = { id: "note", companyId: "tenant", documentType: "E34", originalDocumentId: null,
    payloadSummary: { total: "59.00", currency: "DOP", issueDate: "2026-10-14",
      reference: { originalENcf: "E310000000001", originalIssueDate: "2026-10-14", originalType: "E31" } } };
  return { original, note };
}
describe("E34 conservative local integrity policy", () => {
  it("verifies separate original identity, fiscal evidence, currency and reference", () => {
    const { original, note } = pair();
    expect(validateE34Original(original as any, note as any).amount.toFixed(2)).toBe("59.00");
  });
  it.each(["LOCAL_VALIDATED", "PROVIDER_ACCEPTED", "UNKNOWN_RESULT", "CANCELLED", "DGII_REJECTED"])("does not treat %s as fiscal acceptance", (status) => {
    const { original, note } = pair();
    expect(() => validateE34Original({ ...original, status } as any, note as any)).toThrow("E34_ORIGINAL_NOT_FISCALLY_ACCEPTED");
  });
  it.each(["currency", "reference", "issueDate"])("blocks incompatible note %s", (field) => {
    const { original, note } = pair();
    (note.payloadSummary as any)[field] = field === "currency" ? "USD" : field === "issueDate" ? "2026-02-30" : {};
    expect(() => validateE34Original(original as any, note as any)).toThrow();
  });
  it.each(["1.005", "-1", "0", "NaN", "Infinity", "1e2", 1.01, null])("rejects noncanonical/invalid monetary input %s", (value) => {
    expect(() => centAmount(value)).toThrow();
  });
  it("uses exact decimals and holds unknown and reserved amounts without applying them", () => {
    const result = creditAvailability(dec("1.00"), [
      { state: "APPLIED", amount: dec("0.10") }, { state: "RESERVED", amount: dec("0.20") },
      { state: "UNKNOWN_RESULT", amount: dec("0.30") }, { state: "REJECTED", amount: dec("0.50") },
    ]);
    expect(result).toMatchObject({ availableAmount: "0.40", creditedAmount: "0.10", reservedAmount: "0.20", unknownAmount: "0.30", rejectedAmount: "0.50" });
    expect(() => creditAvailability(dec(1), [{ state: "APPLIED", amount: dec("1.01") }])).toThrow("E34_BALANCE_INTEGRITY_VIOLATION");
  });
});
