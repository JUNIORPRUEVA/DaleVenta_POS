import {
  ECF_DGII_REQUIREMENT_CATALOG,
  PRODUCTION_EMISSION_IMPLEMENTED,
  authorizationRefusal,
  buildRequirementProgress,
  evaluateEcfEmissionGate,
  evidenceGrantsOfficialAuthorization,
  evidenceLevel,
  evidenceQualityRefusal,
  evidenceReviewRefusal,
  evidenceSupportsOfficialAuthorization,
  hasOfficialAuthorization,
  isTerminalState,
  isTransitionAllowed,
  stateUpdateRefusal,
  type EcfEmissionGateInput,
} from "./ecf-dgii-habilitation.policy";

const OFFICIAL = {
  state: "APPROVED",
  authorizationSource: "DGII_OFFICIAL_RECORD",
  authorizationEvidenceId: "11111111-1111-1111-1111-111111111111",
  authorizedAt: new Date("2026-10-16T00:00:00.000Z"),
  externalId: "DGII-OFFICIAL-1",
};

describe("ecf-dgii-habilitation — autorización oficial", () => {
  it("solo reconoce la autorización con las cinco condiciones verificadas", () => {
    expect(hasOfficialAuthorization(OFFICIAL)).toBe(true);
    expect(hasOfficialAuthorization({ ...OFFICIAL, state: "IN_CERTIFICATION" })).toBe(false);
    expect(hasOfficialAuthorization({ ...OFFICIAL, authorizationEvidenceId: null })).toBe(false);
    expect(hasOfficialAuthorization({ ...OFFICIAL, authorizedAt: null })).toBe(false);
    expect(hasOfficialAuthorization({ ...OFFICIAL, externalId: null })).toBe(false);
    expect(hasOfficialAuthorization(null)).toBe(false);
    expect(hasOfficialAuthorization(undefined)).toBe(false);
  });

  it("no acepta una declaración manual como autorización oficial", () => {
    // El estado dice APPROVED, pero la fuente no es oficial: NO autoriza.
    expect(
      hasOfficialAuthorization({ ...OFFICIAL, authorizationSource: "MANUAL_OPERATOR_DECLARATION" }),
    ).toBe(false);
    expect(
      hasOfficialAuthorization({ ...OFFICIAL, authorizationSource: "PROVIDER_CONFIRMATION" }),
    ).toBe(false);
    expect(hasOfficialAuthorization({ ...OFFICIAL, authorizationSource: "NONE" })).toBe(false);
  });
});

describe("ecf-dgii-habilitation — transiciones", () => {
  it("permite las transiciones declaradas y es idempotente consigo misma", () => {
    expect(isTransitionAllowed("NOT_STARTED", "PREPARING_REQUIREMENTS")).toBe(true);
    expect(isTransitionAllowed("IN_CERTIFICATION", "APPROVED")).toBe(true);
    expect(isTransitionAllowed("APPROVED", "REJECTED")).toBe(true);
    expect(isTransitionAllowed("IN_PROGRESS", "IN_PROGRESS")).toBe(true);
  });

  it("rechaza saltos no declarados y estados desconocidos", () => {
    expect(isTransitionAllowed("NOT_STARTED", "APPROVED")).toBe(false);
    expect(isTransitionAllowed("NOT_STARTED", "IN_PROGRESS")).toBe(false);
    expect(isTransitionAllowed("TESTS_PENDING", "APPROVED")).toBe(false);
    expect(isTransitionAllowed("NOT_STARTED", "INVENTADO")).toBe(false);
    expect(isTransitionAllowed("INVENTADO", "APPROVED")).toBe(false);
  });

  it("marca APPROVED y REJECTED como terminales", () => {
    expect(isTerminalState("APPROVED")).toBe(true);
    expect(isTerminalState("REJECTED")).toBe(true);
    expect(isTerminalState("IN_CERTIFICATION")).toBe(false);
  });

  it("impide declarar APPROVED sin autorización oficial registrada", () => {
    expect(stateUpdateRefusal("IN_CERTIFICATION", "APPROVED", false)).toBe(
      "ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD",
    );
    expect(stateUpdateRefusal("IN_CERTIFICATION", "APPROVED", true)).toBeNull();
  });

  it("informa transición no permitida y estado desconocido", () => {
    expect(stateUpdateRefusal("NOT_STARTED", "APPROVED", true)).toBe(
      "ECF_DGII_TRANSITION_NOT_ALLOWED",
    );
    expect(stateUpdateRefusal("NOT_STARTED", "LO_QUE_SEA", true)).toBe(
      "ECF_DGII_STATE_UNKNOWN",
    );
  });
});

describe("ecf-dgii-habilitation — registro de autorización", () => {
  it("exige una fuente distinta de NONE", () => {
    expect(authorizationRefusal({ source: "NONE" })).toBe(
      "ECF_DGII_VERIFICATION_SOURCE_REQUIRED",
    );
    expect(authorizationRefusal({ source: "INVENTADA" })).toBe(
      "ECF_DGII_VERIFICATION_SOURCE_UNKNOWN",
    );
  });

  it("exige evidencia e identificador externo para la fuente oficial", () => {
    expect(authorizationRefusal({ source: "DGII_OFFICIAL_RECORD" })).toBe(
      "ECF_DGII_OFFICIAL_EVIDENCE_REQUIRED",
    );
    expect(
      authorizationRefusal({ source: "DGII_OFFICIAL_RECORD", evidenceId: "e1" }),
    ).toBe("ECF_DGII_OFFICIAL_EXTERNAL_ID_REQUIRED");
    expect(
      authorizationRefusal({ source: "DGII_OFFICIAL_RECORD", evidenceId: "e1", externalId: "x" }),
    ).toBeNull();
  });

  it("no exige evidencia para una declaración manual o del proveedor", () => {
    expect(authorizationRefusal({ source: "MANUAL_OPERATOR_DECLARATION" })).toBeNull();
    expect(authorizationRefusal({ source: "PROVIDER_CONFIRMATION" })).toBeNull();
  });
});

describe("ecf-dgii-habilitation — progreso de requisitos", () => {
  it("cruza el catálogo con las etapas reales y calcula el porcentaje", () => {
    const progress = buildRequirementProgress([
      { stepKey: "FISCAL_CONFIG", status: "COMPLETED" },
      { stepKey: "REQUIREMENTS", status: "CONFIRMED" },
      { stepKey: "DIGITAL_CERTIFICATE", status: "IN_PROGRESS" },
    ]);
    expect(progress.total).toBe(ECF_DGII_REQUIREMENT_CATALOG.length);
    expect(progress.resolvedCount).toBe(2);
    expect(progress.percent).toBe(
      Math.round((2 / ECF_DGII_REQUIREMENT_CATALOG.length) * 100),
    );
    expect(progress.pendingMandatory).toContain("DIGITAL_CERTIFICATE");
    expect(progress.pendingMandatory).not.toContain("REQUIREMENTS");
  });

  it("sin etapas queda todo pendiente y ninguna obligación resuelta", () => {
    const progress = buildRequirementProgress([]);
    expect(progress.resolvedCount).toBe(0);
    expect(progress.percent).toBe(0);
    expect(progress.mandatoryResolved).toBe(0);
    expect(progress.pendingMandatory.length).toBe(progress.mandatoryTotal);
  });

  it("no declara resuelto un requisito solo por estar iniciado", () => {
    const progress = buildRequirementProgress([
      { stepKey: "SET_TESTS", status: "IN_PROGRESS" },
    ]);
    const setTests = progress.requirements.find((item) => item.stepKey === "SET_TESTS");
    expect(setTests?.resolved).toBe(false);
  });
});

describe("ecf-dgii-habilitation — puerta de emisión", () => {
  const satisfied: EcfEmissionGateInput = {
    moduleEnabled: true,
    certificationStatus: "PRODUCTION_READY",
    productionEnabled: true,
    fiscalConfigurationValid: true,
    licenseAllowsEcf: true,
    environment: "uat",
    officialAuthorization: true,
    pendingMandatoryRequirements: [],
  };

  it("la emisión real NO está implementada y la constante lo declara", () => {
    expect(PRODUCTION_EMISSION_IMPLEMENTED).toBe(false);
  });

  it("nunca autoriza emisión real, ni con todas las condiciones satisfechas", () => {
    const gate = evaluateEcfEmissionGate(satisfied);
    expect(gate.realEmissionAuthorized).toBe(false);
    expect(gate.productionEmissionImplemented).toBe(false);
    expect(gate.blockers.map((b) => b.code)).toEqual([
      "ECF_REAL_EMISSION_NOT_IMPLEMENTED",
    ]);
  });

  it("autoriza el despacho simulado solo con módulo activo y entorno UAT local", () => {
    expect(evaluateEcfEmissionGate(satisfied).simulatedDispatchAuthorized).toBe(true);
    expect(
      evaluateEcfEmissionGate({ ...satisfied, moduleEnabled: false })
        .simulatedDispatchAuthorized,
    ).toBe(false);
    expect(
      evaluateEcfEmissionGate({ ...satisfied, environment: "production" })
        .simulatedDispatchAuthorized,
    ).toBe(false);
    expect(
      evaluateEcfEmissionGate({ ...satisfied, environment: "" })
        .simulatedDispatchAuthorized,
    ).toBe(false);
  });

  it("acumula todos los bloqueos para que la interfaz explique qué falta", () => {
    const gate = evaluateEcfEmissionGate({
      moduleEnabled: false,
      certificationStatus: "NOT_STARTED",
      productionEnabled: false,
      fiscalConfigurationValid: false,
      licenseAllowsEcf: false,
      environment: "production",
      officialAuthorization: false,
      pendingMandatoryRequirements: ["SET_TESTS", "SERVICE_URLS"],
    });
    const codes = gate.blockers.map((b) => b.code);
    expect(codes).toEqual(
      expect.arrayContaining([
        "ECF_MODULE_DISABLED",
        "ECF_FISCAL_CONFIGURATION_INVALID",
        "ECF_LICENSE_NOT_ALLOWED",
        "ECF_DGII_REQUIREMENTS_PENDING",
        "ECF_DGII_OFFICIAL_AUTHORIZATION_MISSING",
        "ECF_PRODUCTION_NOT_ENABLED",
        "ECF_CERTIFICATION_NOT_PRODUCTION_READY",
        "ECF_REAL_EMISSION_NOT_IMPLEMENTED",
        "ECF_ENVIRONMENT_NOT_LOCAL_UAT",
      ]),
    );
    expect(gate.realEmissionAuthorized).toBe(false);
    expect(gate.simulatedDispatchAuthorized).toBe(false);
  });

  it("describe el bloqueo de requisitos con su número pendiente", () => {
    const gate = evaluateEcfEmissionGate({
      ...satisfied,
      pendingMandatoryRequirements: ["SET_TESTS", "SERVICE_URLS"],
    });
    const pending = gate.blockers.find(
      (b) => b.code === "ECF_DGII_REQUIREMENTS_PENDING",
    );
    expect(pending?.message).toContain("2");
  });
});

describe("ecf-dgii-habilitation — nivel de evidencia", () => {
  it("combina origen y revisión en un nivel explícito", () => {
    expect(
      evidenceLevel({ source: "MANUAL_DECLARATION", reviewStatus: "PENDING" }),
    ).toBe("DECLARED_BY_COMPANY");
    expect(
      evidenceLevel({ source: "MANUAL_DECLARATION", reviewStatus: "REVIEWED" }),
    ).toBe("INTERNALLY_REVIEWED");
    expect(
      evidenceLevel({ source: "PROVIDER_ARTIFACT", reviewStatus: "PENDING" }),
    ).toBe("PROVIDER_ISSUED");
    expect(
      evidenceLevel({ source: "OFFICIAL_DOCUMENT", reviewStatus: "PENDING" }),
    ).toBe("OFFICIAL_DOCUMENT_PENDING_REVIEW");
    expect(
      evidenceLevel({ source: "OFFICIAL_DOCUMENT", reviewStatus: "REVIEWED" }),
    ).toBe("OFFICIAL_DOCUMENT_REVIEWED");
  });

  it("un artefacto del proveedor sigue siendo del proveedor aunque se revise", () => {
    expect(
      evidenceLevel({ source: "PROVIDER_ARTIFACT", reviewStatus: "REVIEWED" }),
    ).toBe("PROVIDER_ISSUED");
  });

  it("ninguna evidencia concede autorización por sí misma", () => {
    expect(evidenceGrantsOfficialAuthorization()).toBe(false);
  });
});

describe("ecf-dgii-habilitation — revisión interna de evidencias", () => {
  it("rechaza una decisión ausente o desconocida", () => {
    expect(
      evidenceReviewRefusal({ decision: "PENDING", currentStatus: "PENDING" }),
    ).toBe("ECF_DGII_EVIDENCE_REVIEW_DECISION_REQUIRED");
    expect(
      evidenceReviewRefusal({ decision: "APROBAR", currentStatus: "PENDING" }),
    ).toBe("ECF_DGII_EVIDENCE_REVIEW_DECISION_UNKNOWN");
  });

  it("exige motivo para rechazar", () => {
    expect(
      evidenceReviewRefusal({ decision: "REJECTED", currentStatus: "PENDING" }),
    ).toBe("ECF_DGII_EVIDENCE_REJECTION_REASON_REQUIRED");
    expect(
      evidenceReviewRefusal({
        decision: "REJECTED",
        note: "El documento no es legible",
        currentStatus: "PENDING",
      }),
    ).toBeNull();
  });

  it("admite revisar y volver a revisar por otro usuario", () => {
    expect(
      evidenceReviewRefusal({ decision: "REVIEWED", currentStatus: "PENDING" }),
    ).toBeNull();
    expect(
      evidenceReviewRefusal({
        decision: "REVIEWED",
        currentStatus: "REVIEWED",
        reviewedBySameUser: false,
      }),
    ).toBeNull();
  });

  it("no reescribe la misma decisión sin cambio real", () => {
    expect(
      evidenceReviewRefusal({
        decision: "REVIEWED",
        currentStatus: "REVIEWED",
        reviewedBySameUser: true,
      }),
    ).toBe("ECF_DGII_EVIDENCE_REVIEW_UNCHANGED");
  });
});

describe("ecf-dgii-habilitation — calidad de la evidencia oficial", () => {
  it("solo un documento OFICIAL ya REVISADO puede sustentar la autorización", () => {
    expect(
      evidenceSupportsOfficialAuthorization({
        source: "OFFICIAL_DOCUMENT",
        reviewStatus: "REVIEWED",
      }),
    ).toBe(true);
    expect(
      evidenceSupportsOfficialAuthorization({
        source: "OFFICIAL_DOCUMENT",
        reviewStatus: "PENDING",
      }),
    ).toBe(false);
    expect(
      evidenceSupportsOfficialAuthorization({
        source: "MANUAL_DECLARATION",
        reviewStatus: "REVIEWED",
      }),
    ).toBe(false);
    expect(
      evidenceSupportsOfficialAuthorization({
        source: "PROVIDER_ARTIFACT",
        reviewStatus: "REVIEWED",
      }),
    ).toBe(false);
  });

  it("explica por qué una evidencia no sirve para la autorización", () => {
    expect(
      evidenceQualityRefusal({
        source: "MANUAL_DECLARATION",
        reviewStatus: "REVIEWED",
      }),
    ).toBe("ECF_DGII_AUTHORIZATION_REQUIRES_OFFICIAL_EVIDENCE");
    expect(
      evidenceQualityRefusal({
        source: "OFFICIAL_DOCUMENT",
        reviewStatus: "PENDING",
      }),
    ).toBe("ECF_DGII_AUTHORIZATION_REQUIRES_REVIEWED_EVIDENCE");
    expect(
      evidenceQualityRefusal({
        source: "OFFICIAL_DOCUMENT",
        reviewStatus: "REVIEWED",
      }),
    ).toBeNull();
  });

  it("una declaración manual revisada sigue sin autorizar nada", () => {
    // El caso peligroso: revisar una declaración manual no la vuelve oficial.
    const input = { source: "MANUAL_DECLARATION", reviewStatus: "REVIEWED" };
    expect(evidenceSupportsOfficialAuthorization(input)).toBe(false);
    expect(evidenceQualityRefusal(input)).not.toBeNull();
  });
});
