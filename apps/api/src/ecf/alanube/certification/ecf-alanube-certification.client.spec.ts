import { ConfigService } from "@nestjs/config";

import { AlanubeRealHttpTransport } from "../alanube-real-http.transport";
import type {
  AlanubeHttpTransport,
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "../alanube-safe-http.types";
import { EcfAlanubeCertificationClient } from "./ecf-alanube-certification.client";
import type { EcfSetTestsInput } from "./ecf-alanube-certification.contracts";

/** Transporte falso: responde lo que pida cada prueba y anota la petición. */
class _FakeTransport implements AlanubeHttpTransport {
  readonly calls: AlanubeSafeRequest[] = [];
  constructor(private readonly reply: (request: AlanubeSafeRequest) => AlanubeTransportResult) {}
  async execute(request: AlanubeSafeRequest): Promise<AlanubeTransportResult> {
    this.calls.push(request);
    return this.reply(request);
  }
}

function ok(body: unknown, statusCode = 200): AlanubeTransportResult {
  return {
    ok: true,
    response: {
      statusCode,
      headers: { "content-type": "application/json" },
      body,
      requestId: "r",
    },
  };
}

function failed(
  errorCode: "TIMEOUT" | "NETWORK_ERROR" | "INVALID_RESPONSE" | "CONFIGURATION_ERROR",
): AlanubeTransportResult {
  return { ok: false, errorCode, safeMessage: "fallo simulado", requestId: "r" };
}

function config(overrides: Record<string, string> = {}) {
  const values: Record<string, string> = {
    ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
    ALANUBE_TIMEOUT_MS: "9000",
    ...overrides,
  };
  return {
    get: (key: string) => values[key],
  } as unknown as ConfigService;
}

function client(transport: AlanubeHttpTransport, overrides?: Record<string, string>) {
  return new EcfAlanubeCertificationClient(config(overrides), transport);
}

const ctx = { token: "token-de-prueba", idempotencyKey: "idem-1" };

const setTests: EcfSetTestsInput = {
  idCompany: "company-1",
  retryNumber: 0,
  billingIndicator: "1",
  itemName: "Servicio",
  goodServiceIndicator: "1",
  itemDescription: "Descripción",
  unitPriceItem: 100,
};

describe("cliente de certificación — peticiones que construye", () => {
  it("usa la base del sandbox, el token y un requestId determinista", async () => {
    const transport = new _FakeTransport(() =>
      ok({ name: "Alanube", taxId: "132109122" }),
    );
    const result = await client(transport).getProviderInfo(ctx);
    expect(result.ok).toBe(true);

    const request = transport.calls[0];
    expect(request.url).toBe("https://sandbox.alanube.co/dom/v1/provider-info");
    expect(request.method).toBe("GET");
    expect(request.headers.Authorization).toBe("Bearer token-de-prueba");
    expect(request.requestId).toBe("idem-1");
    expect(request.timeoutMs).toBe(9000);
  });

  it("la consulta del set usa el id del set Y el idCompany", async () => {
    const transport = new _FakeTransport(() =>
      ok({ status: "APPROVED", documentsInfo: { zipUrl: "https://zip/1" } }),
    );
    const result = await client(transport).checkSetTests("set-1", "company-1", ctx);
    expect(result.ok).toBe(true);
    expect(transport.calls[0].url).toBe(
      "https://sandbox.alanube.co/dom/v1/check-set-tests/set-1/idCompany/company-1",
    );
  });

  it("no llama al transporte si los identificadores están cruzados", async () => {
    const transport = new _FakeTransport(() => ok({}));
    const result = await client(transport).checkSetTests("same", "same", ctx);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.kind).toBe("UNCONFIGURED");
      expect(result.code).toBe("ECF_ALANUBE_IDENTIFIERS_SWAPPED");
    }
    expect(transport.calls).toHaveLength(0);
  });

  it("no llama al transporte con una URL que no sea el sandbox oficial", async () => {
    const transport = new _FakeTransport(() => ok({}));
    const result = await client(transport, {
      ALANUBE_BASE_URL: "https://api.alanube.co/dom/v1",
    }).getProviderInfo(ctx);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("ECF_ALANUBE_BASE_URL_INVALID");
    expect(transport.calls).toHaveLength(0);
  });

  it("sin token no se ejecuta nada", async () => {
    const transport = new _FakeTransport(() => ok({}));
    const result = await client(transport).getProviderInfo({
      token: "",
      idempotencyKey: "x",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("ECF_ALANUBE_TOKEN_REQUIRED");
    expect(transport.calls).toHaveLength(0);
  });
});

describe("cliente de certificación — interpretación de respuestas", () => {
  it("marca como simulado lo que viene del simulador", async () => {
    const transport = new _FakeTransport(() =>
      ok({ name: "Alanube", taxId: "132109122", mark: "SIMULATED_NOT_OFFICIAL" }),
    );
    const result = await client(transport).getProviderInfo(ctx);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.simulated).toBe(true);
  });

  it("un timeout en una ESCRITURA es incierto (no se reintenta a ciegas)", async () => {
    const transport = new _FakeTransport(() => failed("TIMEOUT"));
    const result = await client(transport).createSetTests(setTests, ctx);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.kind).toBe("UNCERTAIN");
      expect(result.detail).toContain("reconciliar");
    }
  });

  it("un timeout en una LECTURA sí es reintentable", async () => {
    const transport = new _FakeTransport(() => failed("TIMEOUT"));
    const result = await client(transport).getProviderInfo(ctx);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("RETRYABLE");
  });

  it("429 es reintentable y no incierto", async () => {
    const transport = new _FakeTransport(() => ok({}, 429));
    const result = await client(transport).signHabilitation(
      { idCompany: "company-1", xml: "<xml/>" },
      ctx,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.kind).toBe("RETRYABLE");
      expect(result.code).toBe("ECF_ALANUBE_RATE_LIMITED");
    }
  });

  it("500 en escritura es incierto; en lectura, reintentable", async () => {
    const write = await client(new _FakeTransport(() => ok({}, 500))).createSetTests(
      setTests,
      ctx,
    );
    expect(write.ok).toBe(false);
    if (!write.ok) expect(write.kind).toBe("UNCERTAIN");

    const read = await client(new _FakeTransport(() => ok({}, 500))).getCompanyInfo(
      "company-1",
      ctx,
    );
    expect(read.ok).toBe(false);
    if (!read.ok) expect(read.kind).toBe("RETRYABLE");
  });

  it("4xx es un rechazo definitivo", async () => {
    const transport = new _FakeTransport(() => ok({}, 422));
    const result = await client(transport).createSetTests(setTests, ctx);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("REJECTED");
  });

  it("2xx con cuerpo ilegible en escritura es incierto", async () => {
    const transport = new _FakeTransport(() => ok("<html>error</html>"));
    const result = await client(transport).signHabilitation(
      { idCompany: "company-1", xml: "<xml/>" },
      ctx,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("UNCERTAIN");
  });

  it("2xx con cuerpo ilegible en lectura es un fallo de contrato", async () => {
    const transport = new _FakeTransport(() => ok("<html>error</html>"));
    const result = await client(transport).getProviderInfo(ctx);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("CONTRACT_MISMATCH");
  });

  it("las llamadas reales deshabilitadas se informan como no configuradas", async () => {
    const transport = new _FakeTransport(() => failed("CONFIGURATION_ERROR"));
    const result = await client(transport).getProviderInfo(ctx);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("CONTRACT_MISMATCH");
  });

  it("parsea las URLs de la compañía y el enlace firmado", async () => {
    const company = await client(
      new _FakeTransport(() =>
        ok({
          id: "company-1",
          name: "Empresa Demo",
          companyUrls: { receptionUrl: "https://r", authenticationUrl: "https://a" },
        }),
      ),
    ).getCompanyInfo("company-1", ctx);
    expect(company.ok).toBe(true);
    if (company.ok) {
      expect(company.value.companyUrls.receptionUrl).toBe("https://r");
      expect(company.value.companyUrls.commercialApprovalUrl).toBeNull();
    }

    const signature = await client(
      new _FakeTransport(() => ok({ signedDocumentUrl: "https://firmado" })),
    ).signHabilitation({ idCompany: "company-1", xml: "<xml/>" }, ctx);
    expect(signature.ok).toBe(true);
    if (signature.ok) expect(signature.value.signedDocumentUrl).toBe("https://firmado");
  });
});

describe("cliente de certificación — el transporte real sigue bloqueando escrituras", () => {
  it("el transporte real rechaza un POST de certificación sin salir a la red", async () => {
    const result = await new AlanubeRealHttpTransport().execute({
      method: "POST",
      url: "https://sandbox.alanube.co/dom/v1/set-tests",
      headers: { Authorization: "Bearer x" },
      body: { idCompany: "c" },
      timeoutMs: 1000,
      requestId: "r",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errorCode).toBe("CONFIGURATION_ERROR");
  });

  it("el transporte real no reconoce las rutas de certificación todavía", async () => {
    const result = await new AlanubeRealHttpTransport().execute({
      method: "GET",
      url: "https://sandbox.alanube.co/dom/v1/check-set-tests/set-1/idCompany/company-1",
      headers: { Authorization: "Bearer x" },
      timeoutMs: 1000,
      requestId: "r",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errorCode).toBe("CONFIGURATION_ERROR");
  });
});
