import {
  correctionReasonRefusal,
  requiresCorrectionReason,
} from "./ecf-dgii-correction.policy";

describe("motivo obligatorio en correcciones y rechazos", () => {
  it("exige motivo cuando el expediente vuelve al cliente", () => {
    expect(requiresCorrectionReason("REQUIRES_CORRECTION")).toBe(true);
    expect(requiresCorrectionReason("REJECTED")).toBe(true);
  });

  it("no exige motivo en los estados de avance normal", () => {
    for (const state of [
      "PREPARING_REQUIREMENTS",
      "APPLICATION_PENDING",
      "IN_PROGRESS",
      "TESTS_PENDING",
      "IN_CERTIFICATION",
      "APPROVED",
    ]) {
      expect(requiresCorrectionReason(state)).toBe(false);
      expect(
        correctionReasonRefusal({ nextState: state, incomingReason: null }),
      ).toBeNull();
    }
  });

  it("rechaza una corrección sin motivo", () => {
    expect(
      correctionReasonRefusal({
        nextState: "REQUIRES_CORRECTION",
        incomingReason: "   ",
        existingReason: null,
      }),
    ).toBe("ECF_DGII_CORRECTION_REASON_REQUIRED");
  });

  it("rechaza un rechazo sin motivo", () => {
    expect(
      correctionReasonRefusal({ nextState: "REJECTED" }),
    ).toBe("ECF_DGII_CORRECTION_REASON_REQUIRED");
  });

  it("acepta el motivo entrante", () => {
    expect(
      correctionReasonRefusal({
        nextState: "REQUIRES_CORRECTION",
        incomingReason: "Falta la cédula del representante",
      }),
    ).toBeNull();
  });

  it("acepta un motivo ya registrado en el expediente", () => {
    expect(
      correctionReasonRefusal({
        nextState: "REJECTED",
        existingReason: "Expediente incompleto",
      }),
    ).toBeNull();
  });

  it("un estado ausente no exige motivo", () => {
    expect(requiresCorrectionReason(null)).toBe(false);
    expect(requiresCorrectionReason(undefined)).toBe(false);
  });
});
