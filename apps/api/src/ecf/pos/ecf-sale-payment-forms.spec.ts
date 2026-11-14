import { salePaymentForms } from "./ecf-sale-payment-forms";

describe("Original fiscal payment evidence", () => {
  it.each([["cash", "1"], ["transfer", "2"]])("maps %s without confusing it with payment type", (method, code) => {
    expect(salePaymentForms({ method, total: "118", cash: "0", transfer: "0" }))
      .toEqual([{ code, amount: "118.00" }]);
  });
  it("preserves mixed original payments, excluding subsequent credit collections", () => {
    expect(salePaymentForms({ method: "mixed", total: "118", cash: "40", transfer: "30", collectedCash: "10", collectedTransfer: "10" }))
      .toEqual([{ code: "1", amount: "30.00" }, { code: "2", amount: "20.00" }, { code: "4", amount: "68.00" }]);
  });
  it("records a fully credited original as credit", () => {
    expect(salePaymentForms({ method: "credit", total: "118", cash: "20", transfer: "0", collectedCash: "20" }))
      .toEqual([{ code: "4", amount: "118.00" }]);
  });
  it("rejects inconsistent evidence instead of declaring a payment", () => {
    expect(() => salePaymentForms({ method: "mixed", total: "118", cash: "120", transfer: "0" })).toThrow("INCOHERENT");
    expect(() => salePaymentForms({ method: "unknown", total: "118", cash: "0", transfer: "0" })).toThrow("UNSUPPORTED");
  });
});
