import {
  DGII_EXTERNAL_FINDINGS,
  DGII_MANUAL_ONLY_STEP_KEYS,
  DGII_NOT_COVERED_BY_DELEGATED_SIGNATURE,
  DGII_OPERATIONS_WITHOUT_AUTHORIZED_API,
  findingOf,
  hasAuthorizedApi,
  isCoveredByDelegatedSignature,
} from "./dgii-external-dependencies.policy";
import {
  ECF_ACTIVATION_CLASS,
  ECF_ACTIVATION_CLASS_BY_KEY,
  ECF_STEPS_REQUIRING_OFFICIAL_CONFIRMATION,
  ECF_ACTIVATION_STATUS,
  activationClassOf,
  resolveStepStatus,
} from "./ecf-dgii-activation.policy";

/**
 * Hallazgos de la auditoría externa (CA5244, CA5388, CA5241 y Norma 10-21 art.
 * 14) traducidos a garantías comprobables.
 *
 * Lo que se prueba aquí no es documentación: es que el motor no pueda convertir
 * una operación administrativa sin API autorizada en un paso automático, y que
 * la delegación de firma no cierre jamás la declaración jurada.
 */
describe("dependencias externas de la DGII", () => {
  it("documenta los cuatro hallazgos con su referencia", () => {
    expect(DGII_EXTERNAL_FINDINGS).toHaveLength(4);
    for (const finding of DGII_EXTERNAL_FINDINGS) {
      expect(finding.reference.trim().length).toBeGreaterThan(0);
      expect(finding.statement.trim().length).toBeGreaterThan(0);
      expect(finding.notAssumed.trim().length).toBeGreaterThan(0);
    }
    expect(findingOf("PROVIDER_EXCLUSIVITY")?.reference).toContain("CA5244");
    expect(findingOf("DELEGATION_REQUEST")?.reference).toContain("CA5388");
    expect(findingOf("CERTIFICATE_IDENTITY")?.reference).toContain("CA5241");
  });

  it("declara las cinco operaciones sin API autorizada y las ubica en el catálogo", () => {
    expect(DGII_OPERATIONS_WITHOUT_AUTHORIZED_API).toHaveLength(5);
    const keys = DGII_OPERATIONS_WITHOUT_AUTHORIZED_API.map((op) => op.key);
    expect(new Set(keys).size).toBe(keys.length);
    for (const operation of DGII_OPERATIONS_WITHOUT_AUTHORIZED_API) {
      // El paso citado existe de verdad en el catálogo del motor.
      expect(ECF_ACTIVATION_CLASS_BY_KEY[operation.stepKey]).toBeDefined();
      expect(hasAuthorizedApi(operation.stepKey)).toBe(false);
    }
  });

  it("ninguna de esas operaciones puede clasificarse como automática o del proveedor", () => {
    for (const operation of DGII_OPERATIONS_WITHOUT_AUTHORIZED_API) {
      expect(activationClassOf(operation.stepKey)).toBe(
        ECF_ACTIVATION_CLASS.CLIENT_ACTION,
      );
      expect(DGII_MANUAL_ONLY_STEP_KEYS.has(operation.stepKey)).toBe(true);
    }
    // Aunque el catálogo se reclasificara por error, la garantía se mantiene.
    const catalog = ECF_ACTIVATION_CLASS_BY_KEY as Record<string, string>;
    const original = catalog.DGII_POSTULATION;
    try {
      catalog.DGII_POSTULATION = ECF_ACTIVATION_CLASS.AUTOMATIC_LOCAL;
      expect(activationClassOf("DGII_POSTULATION")).toBe(
        ECF_ACTIVATION_CLASS.CLIENT_ACTION,
      );
    } finally {
      catalog.DGII_POSTULATION = original;
    }
  });

  it("una respuesta técnica correcta no cierra esas operaciones", () => {
    for (const operation of DGII_OPERATIONS_WITHOUT_AUTHORIZED_API) {
      const status = resolveStepStatus({
        key: operation.stepKey,
        className: activationClassOf(operation.stepKey),
        transportOk: true,
        simulated: false,
      });
      expect(status).not.toBe(ECF_ACTIVATION_STATUS.COMPLETED);
      expect(status).toBe(ECF_ACTIVATION_STATUS.AWAITING_CLIENT);
    }
  });

  it("la delegación de firma no cubre la declaración jurada", () => {
    expect(isCoveredByDelegatedSignature("SWORN_DECLARATION")).toBe(false);
    expect(DGII_NOT_COVERED_BY_DELEGATED_SIGNATURE.has("SWORN_DECLARATION")).toBe(
      true,
    );
    // Los dos actos siguen siendo pasos distintos que exigen confirmación.
    expect(ECF_STEPS_REQUIRING_OFFICIAL_CONFIRMATION.has("SWORN_DECLARATION")).toBe(
      true,
    );
    expect(
      ECF_STEPS_REQUIRING_OFFICIAL_CONFIRMATION.has("XML_SIGNATURE"),
    ).toBe(false);
  });
});
