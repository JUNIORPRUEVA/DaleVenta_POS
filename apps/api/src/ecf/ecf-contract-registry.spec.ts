import { contractAllowsEmission, ECF_ALANUBE_CONTRACT_REGISTRY } from "./ecf-contract-registry";

describe("ECF_ALANUBE_CONTRACT_REGISTRY", () => {
  it("registers E31/E32/E34 as partial official contracts and blocks emission", () => {
    expect(ECF_ALANUBE_CONTRACT_REGISTRY.map((entry) => entry.documentType).sort()).toEqual([
      "E31",
      "E32",
      "E34",
    ]);
    expect(ECF_ALANUBE_CONTRACT_REGISTRY.every((entry) => entry.status === "PARTIAL_OFFICIAL")).toBe(true);
    expect(contractAllowsEmission("E31")).toBe(false);
  });
});
