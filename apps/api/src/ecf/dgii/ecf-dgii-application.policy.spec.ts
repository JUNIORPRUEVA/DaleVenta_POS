import { missingDraftFields, submitRefusal, ECF_DGII_CONSENT_PURPOSE, ECF_DGII_CONSENT_VERSION } from "./ecf-dgii-application.policy";

const complete = {
  company: { rnc: "131000001", legalName: "Empresa", address: "Calle 1" },
  representative: {
    fullName: "Ana Pérez",
    identification: "001-0000000-1",
    email: "ana@example.test",
  },
};

describe("DGII application field validation", () => {
  it("versions the complete internal-review consent and rejects the prior version", () => {
    expect(ECF_DGII_CONSENT_VERSION).toBe("2026-10-31.v2");
    const paragraphs = ECF_DGII_CONSENT_PURPOSE.split("\n\n");
    expect(paragraphs).toHaveLength(3);
    expect(paragraphs[0]).toContain("Autorizo expresamente a FullPOS Cloud");
    expect(paragraphs[0]).toContain("trámites oficiales que correspondan al contribuyente o a su representante autorizado.");
    expect(paragraphs[1]).toContain("Entiendo que la revisión interna realizada por FullPOS Cloud");
    expect(paragraphs[1]).toContain("por parte de la DGII o proveedores externos.");
    expect(paragraphs[1]).toContain("Los datos serán tratados para las finalidades autorizadas y bajo controles de seguridad y confidencialidad.");
    expect(paragraphs[2]).toBe("Esta aceptación autoriza únicamente la revisión interna del expediente. No constituye presentación oficial ante la DGII ni habilitación para emitir comprobantes electrónicos.");
    expect(submitRefusal({ payload: complete, consentVersion: "2026-10-19.v1" })).toBe("ECF_DGII_CONSENT_VERSION_UNKNOWN");
    expect(submitRefusal({ payload: complete, consentVersion: ECF_DGII_CONSENT_VERSION })).toBeNull();
  });
  it("accepts a complete, valid application", () => {
    expect(missingDraftFields(complete)).toEqual([]);
  });

  it("requires correction of invalid RNC, identification and email", () => {
    const payload = {
      company: { ...complete.company, rnc: "123" },
      representative: { ...complete.representative, identification: "12", email: "wrong" },
    };
    expect(missingDraftFields(payload)).toEqual([
      "company.rnc",
      "representative.identification",
      "representative.email",
    ]);
    expect(submitRefusal({ payload, consentVersion: ECF_DGII_CONSENT_VERSION })).toBe("ECF_DGII_DRAFT_INCOMPLETE");
  });
});
