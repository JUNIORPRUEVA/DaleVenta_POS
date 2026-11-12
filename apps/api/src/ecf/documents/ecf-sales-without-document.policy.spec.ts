import {
  ECF_WITHOUT_DOCUMENT_ERRORS,
  ECF_WITHOUT_DOCUMENT_REASON_MAX_LENGTH,
  ECF_WITHOUT_DOCUMENT_WARNING,
  canRegisterSaleWithoutDocument,
  expectedDocumentTypeForSale,
  normalizeExpectedDocumentType,
  validateWithoutDocumentReason,
} from "./ecf-sales-without-document.policy";

describe("aviso de venta sin comprobante", () => {
  it("conserva el registro y la responsabilidad que protegen a la empresa", () => {
    // El texto se muestra antes de habilitar la excepción. Puede ser más
    // cercano y profesional, pero no puede perder las dos garantías que
    // importan: la venta queda registrada y la empresa responde por su uso.
    expect(ECF_WITHOUT_DOCUMENT_WARNING).toContain(
      "sin comprobante electrónico",
    );
    expect(ECF_WITHOUT_DOCUMENT_WARNING).toContain("usuario");
    expect(ECF_WITHOUT_DOCUMENT_WARNING).toContain("responsabilidad");
    expect(ECF_WITHOUT_DOCUMENT_WARNING).toContain("auditoría");
  });
});

describe("canRegisterSaleWithoutDocument", () => {
  it("exige la empresa habilitada Y la excepción habilitada", () => {
    expect(
      canRegisterSaleWithoutDocument({
        enabled: true,
        allowSalesWithoutEcf: true,
      }),
    ).toEqual({ ok: true });

    const withoutFlag = canRegisterSaleWithoutDocument({
      enabled: true,
      allowSalesWithoutEcf: false,
    });
    expect(withoutFlag).toEqual(
      expect.objectContaining({
        ok: false,
        code: ECF_WITHOUT_DOCUMENT_ERRORS.notAllowed,
      }),
    );

    const disabled = canRegisterSaleWithoutDocument({
      enabled: false,
      allowSalesWithoutEcf: true,
    });
    expect(disabled).toEqual(
      expect.objectContaining({
        ok: false,
        code: ECF_WITHOUT_DOCUMENT_ERRORS.ecfDisabled,
      }),
    );
  });

  it("falla cerrado cuando no hay configuración", () => {
    for (const config of [null, undefined, {}, { enabled: true }]) {
      expect(canRegisterSaleWithoutDocument(config as never).ok).toBe(false);
    }
  });
});

describe("validateWithoutDocumentReason", () => {
  it("acepta un motivo con contenido y lo normaliza", () => {
    const result = validateWithoutDocumentReason(
      "  Venta   de   prueba  interna sin factura ",
    );
    expect(result).toEqual({
      ok: true,
      reason: "Venta de prueba interna sin factura",
    });
  });

  it("rechaza motivos vacíos, cortos o demasiado largos", () => {
    for (const reason of [
      "",
      "   ",
      "sin",
      null,
      undefined,
      123,
      "x".repeat(ECF_WITHOUT_DOCUMENT_REASON_MAX_LENGTH + 1),
    ]) {
      expect(validateWithoutDocumentReason(reason)).toEqual(
        expect.objectContaining({
          ok: false,
          code: ECF_WITHOUT_DOCUMENT_ERRORS.reasonRequired,
        }),
      );
    }
  });
});

describe("expectedDocumentTypeForSale", () => {
  it("elige E31 con RNC y E32 sin identificar al receptor", () => {
    expect(expectedDocumentTypeForSale(true)).toBe("E31");
    expect(expectedDocumentTypeForSale(false)).toBe("E32");
  });
});

describe("normalizeExpectedDocumentType", () => {
  it("normaliza y acepta solo E31/E32", () => {
    expect(normalizeExpectedDocumentType(" e31 ")).toEqual({
      ok: true,
      value: "E31",
    });
    expect(normalizeExpectedDocumentType("E32")).toEqual({
      ok: true,
      value: "E32",
    });
  });

  it("trata vacío como «sin tipo declarado»", () => {
    for (const value of [undefined, null, "", "   "]) {
      expect(normalizeExpectedDocumentType(value)).toEqual({
        ok: true,
        value: null,
      });
    }
  });

  it("rechaza tipos que no se emiten desde una venta", () => {
    for (const value of ["E34", "B01", "E43"]) {
      expect(normalizeExpectedDocumentType(value)).toEqual({
        ok: false,
        code: ECF_WITHOUT_DOCUMENT_ERRORS.expectedTypeInvalid,
      });
    }
  });
});
