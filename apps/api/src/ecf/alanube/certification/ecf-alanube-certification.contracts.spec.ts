import { ECF_CERTIFICATION_GAPS } from "../../dgii/ecf-dgii-certification-reference";
import {
  ECF_CERTIFICATION_CONTRACTS,
  ECF_CERTIFICATION_GAP_STATUS,
  buildCheckSetTestsRequest,
  buildCompanyEnrollRequest,
  buildCompanyInfoRequest,
  buildProviderInfoRequest,
  buildSetTestsRequest,
  buildSignHabilitationRequest,
  redactCertificationRequest,
  validateCompanyInfoResponse,
  validateIdCompany,
  validateProviderInfoResponse,
  validateSetTestsInput,
  validateSetTestsIdentifiers,
  validateSignHabilitationInput,
  type EcfSetTestsInput,
} from "./ecf-alanube-certification.contracts";

const setTests: EcfSetTestsInput = {
  idCompany: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  retryNumber: 0,
  billingIndicator: "1",
  itemName: "Servicio de prueba",
  goodServiceIndicator: "1",
  itemDescription: "Descripción de prueba",
  unitPriceItem: 100,
};

describe("contratos de certificación Alanube — rutas documentadas", () => {
  it("declara las seis operaciones con su método y ruta", () => {
    const routes = ECF_CERTIFICATION_CONTRACTS.map(
      (item) => `${item.method} ${item.path}`,
    );
    expect(routes).toEqual([
      "GET /provider-info",
      "POST /company",
      "GET /company/{idCompany}",
      "POST /sign-document/idCompany/{idCompany}",
      "POST /set-tests",
      "GET /check-set-tests/{id}/idCompany/{idCompany}",
    ]);
  });

  it("cada hueco de la referencia tiene un estado declarado", () => {
    for (const gap of ECF_CERTIFICATION_GAPS) {
      expect(ECF_CERTIFICATION_GAP_STATUS[gap.key]).toBeDefined();
    }
  });

  it("ningún hueco se declara IMPLEMENTED en esta fase", () => {
    // Honestidad: solo hay contratos, no cliente ni llamadas.
    for (const status of Object.values(ECF_CERTIFICATION_GAP_STATUS)) {
      expect(status).not.toBe("IMPLEMENTED");
    }
  });
});

describe("contratos de certificación Alanube — constructores", () => {
  it("provider-info es un GET sin cuerpo", () => {
    const request = buildProviderInfoRequest();
    expect(request.method).toBe("GET");
    expect(request.path).toBe("/provider-info");
    expect(request.body).toBeUndefined();
  });

  it("el alta de company viaja como asociada y con su certificado", () => {
    const request = buildCompanyEnrollRequest({
      type: "associated",
      legalName: "Empresa Demo SRL",
      taxId: "133020232",
      certificate: { p12: "BASE64", password: "secreto-de-prueba" },
    });
    expect(request.method).toBe("POST");
    expect(request.path).toBe("/company");
    expect(request.body?.type).toBe("associated");
    expect(request.body?.certificate).toEqual({
      p12: "BASE64",
      password: "secreto-de-prueba",
    });
  });

  it("company-info sustituye el idCompany en la ruta", () => {
    expect(buildCompanyInfoRequest("abc").path).toBe("/company/abc");
  });

  it("la consulta del set lleva el id del SET y el idCompany en ese orden", () => {
    const request = buildCheckSetTestsRequest("set-1", "company-1");
    expect(request.path).toBe("/check-set-tests/set-1/idCompany/company-1");
  });

  it("no se pueden intercambiar el id del set y el de la compañía", () => {
    // Si se invirtieran, la ruta tendría forma válida pero los datos irían
    // cruzados: la validación lo detecta antes de construir nada.
    expect(validateSetTestsIdentifiers("company-1", "company-1").ok).toBe(false);
    const swapped = validateSetTestsIdentifiers("company-1", "company-1");
    if (!swapped.ok) {
      expect(swapped.code).toBe("ECF_ALANUBE_IDENTIFIERS_SWAPPED");
    }
    expect(
      buildCheckSetTestsRequest("set-1", "company-1").path,
    ).not.toBe(buildCheckSetTestsRequest("company-1", "set-1").path);
  });

  it("exige ambos identificadores y rechaza vacíos o con espacios", () => {
    expect(validateSetTestsIdentifiers("", "c").ok).toBe(false);
    expect(validateSetTestsIdentifiers("s", "").ok).toBe(false);
    expect(validateSetTestsIdentifiers("con espacio", "c").ok).toBe(false);
    expect(validateSetTestsIdentifiers("s", "c")).toEqual({ ok: true });
  });

  it("la firma apunta a la ruta con idCompany y envía el XML", () => {
    const request = buildSignHabilitationRequest({
      idCompany: "abc",
      xml: "<xml/>",
    });
    expect(request.path).toBe("/sign-document/idCompany/abc");
    expect(request.body?.xml).toBe("<xml/>");
  });

  it("escapa el idCompany para no inyectar rutas", () => {
    const request = buildCompanyInfoRequest("../admin");
    expect(request.path).toBe("/company/..%2Fadmin");
  });

  it("set-tests envía exactamente los campos del contrato", () => {
    const request = buildSetTestsRequest(setTests);
    expect(request.body).toEqual({
      idCompany: setTests.idCompany,
      retryNumber: 0,
      billingIndicator: "1",
      itemName: "Servicio de prueba",
      goodServiceIndicator: "1",
      itemDescription: "Descripción de prueba",
      unitPriceItem: 100,
    });
  });
});

describe("contratos de certificación Alanube — validaciones locales", () => {
  it("acepta un set de pruebas válido", () => {
    expect(validateSetTestsInput(setTests)).toEqual({ ok: true });
  });

  it("rechaza retryNumber fuera de 0..99", () => {
    for (const retryNumber of [-1, 100, 1.5]) {
      const result = validateSetTestsInput({ ...setTests, retryNumber });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.code).toBe("ECF_ALANUBE_RETRY_NUMBER_INVALID");
    }
  });

  it("rechaza campos obligatorios vacíos y precio no positivo", () => {
    const emptyItem = validateSetTestsInput({ ...setTests, itemName: "  " });
    expect(emptyItem.ok).toBe(false);
    if (!emptyItem.ok) {
      expect(emptyItem.code).toBe("ECF_ALANUBE_SET_TESTS_FIELD_REQUIRED");
    }
    const badPrice = validateSetTestsInput({ ...setTests, unitPriceItem: 0 });
    expect(badPrice.ok).toBe(false);
    if (!badPrice.ok) expect(badPrice.code).toBe("ECF_ALANUBE_UNIT_PRICE_INVALID");
  });

  it("rechaza idCompany vacío, con espacios o ausente", () => {
    for (const value of ["", "  ", "con espacio", null, 42]) {
      expect(validateIdCompany(value).ok).toBe(false);
    }
  });

  it("rechaza firmar sin XML", () => {
    const result = validateSignHabilitationInput({ idCompany: "abc", xml: "" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("ECF_ALANUBE_XML_REQUIRED");
  });

  it("valida la forma mínima de las respuestas", () => {
    expect(validateProviderInfoResponse({ name: "Alanube", taxId: "132109122" }))
      .toEqual({ ok: true });
    expect(validateProviderInfoResponse({ name: "Alanube" }).ok).toBe(false);
    expect(validateProviderInfoResponse(null).ok).toBe(false);
    expect(validateCompanyInfoResponse({ id: "abc" })).toEqual({ ok: true });
    expect(validateCompanyInfoResponse({}).ok).toBe(false);
  });
});

describe("contratos de certificación Alanube — la auditoría no lleva secretos", () => {
  it("redacta el certificado, la contraseña y el XML", () => {
    const enroll = redactCertificationRequest(
      buildCompanyEnrollRequest({
        type: "associated",
        legalName: "Empresa Demo SRL",
        taxId: "133020232",
        certificate: { p12: "BASE64-SECRETO", password: "clave-secreta" },
      }),
    );
    const serialized = JSON.stringify(enroll);
    expect(serialized).not.toContain("BASE64-SECRETO");
    expect(serialized).not.toContain("clave-secreta");
    expect(serialized).toContain("[REDACTED]");

    const sign = redactCertificationRequest(
      buildSignHabilitationRequest({ idCompany: "abc", xml: "<xml>secreto</xml>" }),
    );
    expect(JSON.stringify(sign)).not.toContain("secreto");
    expect(JSON.stringify(sign)).toContain("[REDACTED_XML]");
  });

  it("conserva operación, método y ruta para poder auditar", () => {
    const redacted = redactCertificationRequest(
      buildCheckSetTestsRequest("set-1", "company-1"),
    );
    expect(redacted).toMatchObject({
      operation: "SET_TESTS_CHECK",
      method: "GET",
      path: "/check-set-tests/set-1/idCompany/company-1",
    });
  });
});
