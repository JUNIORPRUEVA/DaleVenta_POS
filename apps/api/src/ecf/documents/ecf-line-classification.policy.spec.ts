import {
  ECF_FISCALLY_FROZEN_STATUSES,
  effectiveLineClassification,
  isFiscallyFrozen,
  lineClassificationRefusal,
} from "./ecf-line-classification.policy";

/**
 * Clasificación fiscal supervisada (F1) — política pura.
 *
 * Lo que se fija aquí no es aritmética: es que la clasificación NO se pueda
 * adivinar y NO se pueda cambiar después de que el comprobante haya salido.
 */
describe("clasificación fiscal supervisada", () => {
  const base = {
    classification: "PRODUCT",
    reason: "El operador verificó que es mercancía",
    documentStatuses: ["LOCAL_VALIDATED"],
    currentClassification: null,
  };

  it("acepta solo BIEN o SERVICIO, nunca una inferencia", () => {
    expect(
      lineClassificationRefusal({ ...base, classification: "MERCANCIA" })?.code,
    ).toBe("ECF_LINE_CLASSIFICATION_UNKNOWN");
    expect(
      lineClassificationRefusal({ ...base, classification: "" })?.code,
    ).toBe("ECF_LINE_CLASSIFICATION_UNKNOWN");
    expect(
      lineClassificationRefusal({ ...base, classification: "SERVICE" }),
    ).toBeNull();
  });

  it("exige un motivo auditable", () => {
    expect(
      lineClassificationRefusal({ ...base, reason: "" })?.code,
    ).toBe("ECF_LINE_CLASSIFICATION_REASON_REQUIRED");
    expect(
      lineClassificationRefusal({ ...base, reason: "  a " })?.code,
    ).toBe("ECF_LINE_CLASSIFICATION_REASON_REQUIRED");
    expect(
      lineClassificationRefusal({ ...base, reason: "x".repeat(301) })?.code,
    ).toBe("ECF_LINE_CLASSIFICATION_REASON_REQUIRED");
  });

  it("un comprobante que ya salió no admite clasificación nueva", () => {
    for (const status of ECF_FISCALLY_FROZEN_STATUSES) {
      expect(
        lineClassificationRefusal({ ...base, documentStatuses: [status] })?.code,
      ).toBe("ECF_LINE_CLASSIFICATION_FISCALLY_FROZEN");
    }
    // Aunque coincida con la clasificación vigente: primero lo irreversible.
    expect(
      lineClassificationRefusal({
        ...base,
        documentStatuses: ["DGII_ACCEPTED"],
        currentClassification: "PRODUCT",
      })?.code,
    ).toBe("ECF_LINE_CLASSIFICATION_FISCALLY_FROZEN");
  });

  it("los estados LOCALES sí permiten clasificar: aún no ha salido nada", () => {
    for (const status of [
      "LOCAL_DRAFT",
      "LOCAL_VALIDATION_PENDING",
      "LOCAL_VALIDATED",
      "CANCELLED",
    ]) {
      expect(
        lineClassificationRefusal({ ...base, documentStatuses: [status] }),
      ).toBeNull();
    }
    expect(isFiscallyFrozen(["LOCAL_DRAFT", "CANCELLED"])).toBe(false);
    expect(isFiscallyFrozen([])).toBe(false);
    expect(isFiscallyFrozen(["LOCAL_DRAFT", "SEND_IN_PROGRESS"])).toBe(true);
  });

  it("repetir la misma decisión no crea ruido en el historial", () => {
    expect(
      lineClassificationRefusal({
        ...base,
        currentClassification: "PRODUCT",
      })?.code,
    ).toBe("ECF_LINE_CLASSIFICATION_UNCHANGED");
    // Cambiar de opinión SÍ se admite: se registra como un hecho nuevo.
    expect(
      lineClassificationRefusal({
        ...base,
        classification: "SERVICE",
        currentClassification: "PRODUCT",
      }),
    ).toBeNull();
  });

  it("la clasificación congelada en la venta manda sobre la supervisada", () => {
    expect(
      effectiveLineClassification({
        frozenSnapshot: "SERVICE",
        supervised: "PRODUCT",
      }),
    ).toBe("SERVICE");
    expect(
      effectiveLineClassification({
        frozenSnapshot: null,
        supervised: "PRODUCT",
      }),
    ).toBe("PRODUCT");
    // Sin ninguna de las dos, sigue sin saberse: no se inventa.
    expect(
      effectiveLineClassification({ frozenSnapshot: null, supervised: null }),
    ).toBeNull();
    // Una cadena vacía tampoco es una clasificación.
    expect(
      effectiveLineClassification({ frozenSnapshot: "", supervised: null }),
    ).toBeNull();
  });
});
