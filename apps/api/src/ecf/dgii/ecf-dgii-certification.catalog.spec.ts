import { ECF_DGII_CERTIFICATION_CATALOG } from "./ecf-dgii-certification.catalog";

describe("ECF_DGII_CERTIFICATION_CATALOG", () => {
  it("keeps legal/provider dependent steps explicit and evidence-gated", () => {
    expect(ECF_DGII_CERTIFICATION_CATALOG).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          key: "DGII_POSTULATION",
          automation: "DGII_DEPENDENT",
          requiresEvidence: true,
          blocksProductionEmission: true,
        }),
        expect.objectContaining({
          key: "FINAL_AUTHORIZATION",
          automation: "MANUAL_REQUIRED",
          requiresEvidence: true,
          blocksProductionEmission: true,
        }),
      ]),
    );
  });
});
