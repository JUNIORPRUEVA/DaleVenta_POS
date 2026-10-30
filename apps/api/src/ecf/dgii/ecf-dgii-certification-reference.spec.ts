import { ECF_DGII_REQUIREMENT_CATALOG } from "./ecf-dgii-habilitation.policy";
import {
  ECF_CERTIFICATION_GAPS,
  ECF_CERTIFICATION_PREREQUISITES,
  ECF_CERTIFICATION_STAGES,
  ECF_CERTIFICATION_VERIFICATION_MAX_DAYS,
  ECF_SET_TESTS_CONTRACT,
  canDeclareCertified,
  missingCatalogKeys,
  stageOfCatalogKey,
  stageProgressOf,
} from "./ecf-dgii-certification-reference";

/**
 * Referencia del proceso oficial de certificación.
 *
 * Fija contra el documento de Alanube (ticket 4490) lo que el producto debe
 * respetar, y —lo más importante— que hoy NO puede declarar una certificación:
 * la etapa V (asignación de roles) no tiene pasos implementados.
 */
describe("referencia del proceso oficial de certificación e-CF", () => {
  it("declara las cinco etapas del instructivo en orden", () => {
    expect(ECF_CERTIFICATION_STAGES.map((stage) => stage.id)).toEqual([
      "I",
      "II",
      "III",
      "IV",
      "V",
    ]);
  });

  it("todas las claves del catálogo que usa la referencia existen de verdad", () => {
    // Invariante: si alguien renombra un paso del catálogo, esto falla antes de
    // que la pantalla muestre una etapa apuntando a un paso inexistente.
    expect(missingCatalogKeys()).toEqual([]);
  });

  it("la etapa V (roles) tiene su propio paso y ya no es un hueco", () => {
    const stageV = ECF_CERTIFICATION_STAGES.find((stage) => stage.id === "V");
    expect(stageV).toBeDefined();
    expect(stageV?.catalogKeys).toEqual(["ROLE_ASSIGNMENT"]);
    expect(stageV?.owner).toBe("CLIENT");
    expect(
      ECF_CERTIFICATION_GAPS.some((gap) => gap.key === "ROLE_ASSIGNMENT_STEP"),
    ).toBe(false);
  });

  it("no declara certificación sin evidencia oficial de roles, ni con todo resuelto", () => {
    const allKeys = ECF_DGII_REQUIREMENT_CATALOG.map((item) => item.key);
    // Con las 15 etapas resueltas pero sin evidencia oficial de asignación de
    // roles, la empresa sigue sin poder declararse certificada.
    expect(canDeclareCertified(allKeys)).toBe(false);
    // Y con la evidencia sí puede: la única condición que faltaba era esa.
    expect(
      canDeclareCertified(allKeys, { roleAssignmentEvidenced: true }),
    ).toBe(true);
    expect(
      stageProgressOf(allKeys).find((stage) => stage.id === "V")?.implemented,
    ).toBe(true);
  });

  it("el set de pruebas respeta las cantidades y nombres del documento", () => {
    expect(ECF_SET_TESTS_CONTRACT.documentsPerVoucherType).toBe(10);
    expect(ECF_SET_TESTS_CONTRACT.consumptionInvoices).toBe(1);
    expect(ECF_SET_TESTS_CONTRACT.consumptionMaxAmountDop).toBe(250000);
    expect(ECF_SET_TESTS_CONTRACT.requiredConsumptionXml).toBe(
      "E320000002000.xml",
    );
    expect(ECF_SET_TESTS_CONTRACT.resumesFolderPrefix).toBe("SET_TEST_RESUMES_");
    expect(ECF_SET_TESTS_CONTRACT.requestFields).toEqual([
      "idCompany",
      "retryNumber",
      "billingIndicator",
      "itemName",
      "goodServiceIndicator",
      "itemDescription",
      "unitPriceItem",
    ]);
    expect(ECF_SET_TESTS_CONTRACT.zipFields).toEqual([
      "documentsInfo.zipUrl",
      "resumesInfo.zipUrl",
    ]);
  });

  it("conserva los cinco insumos previos y el plazo de verificación", () => {
    expect(ECF_CERTIFICATION_PREREQUISITES).toHaveLength(5);
    expect(ECF_CERTIFICATION_VERIFICATION_MAX_DAYS).toBe(2);
  });

  it("sitúa cada clave del catálogo en su etapa", () => {
    expect(stageOfCatalogKey("DGII_POSTULATION")?.id).toBe("I");
    expect(stageOfCatalogKey("XML_SIGNATURE")?.id).toBe("II");
    expect(stageOfCatalogKey("SET_TESTS")?.id).toBe("III");
    expect(stageOfCatalogKey("SWORN_DECLARATION")?.id).toBe("IV");
    expect(stageOfCatalogKey("NO_EXISTE")).toBeNull();
  });

  it("declara los servicios externos que el proceso exige y no existen", () => {
    const keys = ECF_CERTIFICATION_GAPS.map((gap) => gap.key);
    expect(keys).toEqual(
      expect.arrayContaining([
        "PROVIDER_INFO_SERVICE",
        "COMPANY_INFO_SERVICE",
        "HABILITATION_SIGNING_SERVICE",
        "SET_TESTS_GENERATE_SERVICE",
        "SET_TESTS_QUERY_SERVICE",
      ]),
    );
  });
});
