import {
  classifyDosaResponse,
  isDosaOutcomeFinal,
} from "./dosa-response.mapper";
import {
  DOSA_EMISSION_BLOCKED,
  DosaEmissionClient,
  freezeDosaHttpRequest,
  emissionPathFor,
  readDosaEmissionConfig,
  redactDosaHeaders,
  type DosaEmissionConfig,
  type DosaHttpResponse,
  type DosaHttpTransport,
  type DosaReplayInfo,
} from "./dosa-emission.client";
import {
  DOSA_ECF_CREDIT_NOTE_PATH,
  DOSA_ECF_EMISSION_PATH,
  type DosaEcfRequestBody,
} from "./dosa-ecf.contract";

/**
 * Pruebas del clasificador de respuestas y del cliente de emisión.
 *
 * Todo es sintético y **sin red**: el transporte real nunca se usa aquí.
 */

const BODY: DosaEcfRequestBody = {
  encabezado: {
    version: "1.0",
    idDoc: {
      tipoeCF: "31",
      eNCF: "E310000000001",
      fechaEmision: "02-11-2026",
    },
    emisor: { RNCEmisor: "133306001", RazonSocialEmisor: "PRUEBA SRL" },
    totales: {
      MontoGravadoTotal: "100000.00",
      MontoGravadoI1: "100000.00",
      MontoExento: "0.00",
      ITBIS1: "18",
      TotalITBIS: "18000.00",
      MontoTotal: "118000.00",
    },
  },
  detallesItems: [],
};

describe("classifyDosaResponse", () => {
  it("codigo 1 es aceptado según la tabla pública", () => {
    const result = classifyDosaResponse({ data: { codigo: 1 } });
    expect(result.outcome).toBe("ACCEPTED");
    expect(result.codigo).toBe(1);
    expect(result.codigoType).toBe("number");
  });

  it("codigo 2 es rechazado", () => {
    expect(classifyDosaResponse({ data: { codigo: 2 } }).outcome).toBe(
      "REJECTED",
    );
  });

  it("codigo 3 está en proceso", () => {
    expect(classifyDosaResponse({ data: { codigo: 3 } }).outcome).toBe(
      "IN_PROCESS",
    );
  });

  it("codigo 4 es aceptado condicional", () => {
    expect(classifyDosaResponse({ data: { codigo: 4 } }).outcome).toBe(
      "CONDITIONALLY_ACCEPTED",
    );
  });

  it("codigo 0 queda SIN RESOLVER: no se interpreta como aceptado ni rechazado", () => {
    const result = classifyDosaResponse({ data: { codigo: 0 } });
    expect(result.outcome).toBe("UNRESOLVED");
    expect(result.unresolvedReason).toContain("DOSA_STATUS_TABLE_CONFLICT");
  });

  it("codigo desconocido no se adivina", () => {
    const result = classifyDosaResponse({ data: { codigo: 77 } });
    expect(result.outcome).toBe("UNRESOLVED");
    expect(result.unresolvedReason).toContain("DOSA_STATUS_CODE_UNKNOWN");
  });

  it("trata `codigo` como valor observado: '1' texto no es igual a 1 número", () => {
    const asNumber = classifyDosaResponse({ data: { codigo: 1 } });
    const asText = classifyDosaResponse({ data: { codigo: "1" } });
    expect(asNumber.codigoType).toBe("number");
    expect(asText.codigoType).toBe("string");
    expect(asText.codigo).toBe("1");
    expect(asText.outcome).toBe("ACCEPTED");
  });

  it("reconoce los tres estados DGII en texto", () => {
    expect(
      classifyDosaResponse({ data: { estado: "Aceptado" } }).outcome,
    ).toBe("ACCEPTED");
    expect(
      classifyDosaResponse({ data: { estado: "Aceptado Condicional" } }).outcome,
    ).toBe("CONDITIONALLY_ACCEPTED");
    expect(
      classifyDosaResponse({ data: { estado: "Rechazado" } }).outcome,
    ).toBe("REJECTED");
  });

  it("si el texto y el código se contradicen, queda sin resolver", () => {
    const result = classifyDosaResponse({
      data: { codigo: 1, estado: "Rechazado" },
    });
    expect(result.outcome).toBe("UNRESOLVED");
    expect(result.unresolvedReason).toContain(
      "DOSA_STATUS_TEXT_CODE_CONFLICT",
    );
  });

  it("sin codigo no se inventa un estado", () => {
    const result = classifyDosaResponse({ data: {} });
    expect(result.outcome).toBe("UNRESOLVED");
    expect(result.codigoType).toBe("absent");
  });

  it("construye los datos de QR desde los campos reales de la respuesta", () => {
    const result = classifyDosaResponse({
      codigo: "1",
      encf: "E310000000001",
      rnc: "101742186",
      url: "https://ecf.dgii.gov.do/testecf/consulta?encf=E310000000001",
      codigoSeguridad: "EAkbyR",
      fechaFirma: "15-11-2025 14:46:41",
    });
    expect(result.qr).toEqual({
      consultaUrl: "https://ecf.dgii.gov.do/testecf/consulta?encf=E310000000001",
      codigoSeguridad: "EAkbyR",
      fechaFirma: "15-11-2025 14:46:41",
      encf: "E310000000001",
      rnc: "101742186",
      complete: true,
    });
  });

  it("el QR queda incompleto si falta el codigo de seguridad", () => {
    const result = classifyDosaResponse({
      codigo: "1",
      encf: "E310000000001",
      rnc: "101742186",
      url: "https://ecf.dgii.gov.do/testecf/consulta",
    });
    expect(result.qr?.complete).toBe(false);
  });

  it("propaga secuenciaUtilizada, que es lo que dice si se consumio la secuencia", () => {
    expect(
      classifyDosaResponse({ codigo: "1", secuenciaUtilizada: true })
        .secuenciaUtilizada,
    ).toBe(true);
    expect(
      classifyDosaResponse({ codigo: "2", secuenciaUtilizada: false })
        .secuenciaUtilizada,
    ).toBe(false);
    expect(classifyDosaResponse({ codigo: "1" }).secuenciaUtilizada).toBeNull();
  });

  it("502 con 'Error de envío' significa que la DGII no recibio nada", () => {
    const result = classifyDosaResponse({
      estado: "Error de envío",
      mensaje: "No se pudo conectar con la DGII",
    });
    expect(result.outcome).toBe("NOT_RECEIVED");
    expect(result.safeToRetrySameEncf).toBe(true);
    expect(result.impliesFiscalAuthorization).toBe(false);
  });

  it("solo NOT_RECEIVED autoriza reintentar con el mismo eNCF", () => {
    expect(classifyDosaResponse({ codigo: "1" }).safeToRetrySameEncf).toBe(false);
    expect(classifyDosaResponse({ codigo: "2" }).safeToRetrySameEncf).toBe(false);
    expect(classifyDosaResponse({ codigo: "3" }).safeToRetrySameEncf).toBe(false);
    expect(classifyDosaResponse({ codigo: "0" }).safeToRetrySameEncf).toBe(false);
  });

  it("recoge los mensajes del proveedor", () => {
    const result = classifyDosaResponse({
      data: { codigo: 2, mensajes: ["Error 1001: RNC del emisor"] },
    });
    expect(result.mensajes).toContain("Error 1001: RNC del emisor");
  });

  it("nunca declara autorización fiscal ni aprobación DGII", () => {
    const accepted = classifyDosaResponse({ data: { codigo: 1 } });
    expect(accepted.impliesFiscalAuthorization).toBe(false);
    expect(accepted.isDgiiApproval).toBe(false);
  });

  it("distingue estados finales de provisionales", () => {
    expect(isDosaOutcomeFinal("ACCEPTED")).toBe(true);
    expect(isDosaOutcomeFinal("CONDITIONALLY_ACCEPTED")).toBe(true);
    expect(isDosaOutcomeFinal("IN_PROCESS")).toBe(false);
    expect(isDosaOutcomeFinal("UNRESOLVED")).toBe(false);
  });
});

class FakeTransport implements DosaHttpTransport {
  readonly calls: Array<{ url: string; headers: Record<string, string> }> = [];
  constructor(
    private readonly responder: (
      attempt: number,
    ) => Promise<DosaHttpResponse> | DosaHttpResponse,
  ) {}

  async post(url: string, init: { headers: Record<string, string> }) {
    this.calls.push({ url, headers: init.headers });
    return this.responder(this.calls.length);
  }
}

function config(overrides: Partial<DosaEmissionConfig> = {}): DosaEmissionConfig {
  return {
    enabled: true,
    environment: "TEST",
    baseUrl: "https://sandbox.test",
    apiKey: "TEST-KEY-SECRETA",
    apiKeyIsProduction: false,
    productionEnabled: false,
    testRnc: "133306001",
    timeoutMs: 50,
    breakerThreshold: 3,
    breakerCooldownMs: 60_000,
    ...overrides,
  };
}

describe("DosaEmissionClient — puertas cerradas", () => {  it("sin bandera no hace ni una petición", async () => {
    const transport = new FakeTransport(() => ({ status: 200, body: "{}" }));
    const client = new DosaEmissionClient(
      transport,
      config({ enabled: false }),
    );
    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.disabled,
    });
    expect(transport.calls).toHaveLength(0);
  });

  it("producción sin bandera propia está bloqueada", async () => {
    const transport = new FakeTransport(() => ({ status: 200, body: "{}" }));
    const client = new DosaEmissionClient(
      transport,
      config({ environment: "PRODUCTION", apiKeyIsProduction: true }),
    );
    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.productionNotAuthorized,
    });
    expect(transport.calls).toHaveLength(0);
  });

  it("clave de TEST apuntando a producción se rechaza", async () => {
    const transport = new FakeTransport(() => ({ status: 200, body: "{}" }));
    const client = new DosaEmissionClient(
      transport,
      config({
        environment: "PRODUCTION",
        productionEnabled: true,
        apiKeyIsProduction: false,
      }),
    );
    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.keyEnvironmentMismatch,
    });
    expect(transport.calls).toHaveLength(0);
  });

  it("sin clave o sin baseUrl no envía", async () => {
    const transport = new FakeTransport(() => ({ status: 200, body: "{}" }));
    const noKey = new DosaEmissionClient(transport, config({ apiKey: "" }));
    expect(await noKey.sendEcf({ body: BODY, idempotencyKey: "k1" })).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.apiKeyMissing,
    });

    const noUrl = new DosaEmissionClient(transport, config({ baseUrl: "" }));
    expect(await noUrl.sendEcf({ body: BODY, idempotencyKey: "k1" })).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.baseUrlMissing,
    });
    expect(transport.calls).toHaveLength(0);
  });
});

describe("DosaEmissionClient — endpoint por tipo de comprobante", () => {
  it("las facturas van a EnviarFactura y la nota de crédito a NotaDesdeFactura", () => {
    // El proveedor documenta DOS rutas distintas. Enviar una nota de crédito a
    // `EnviarFactura` es un error de contrato, no un detalle.
    expect(emissionPathFor(BODY)).toBe(DOSA_ECF_EMISSION_PATH);

    const e32 = { ...BODY, encabezado: { ...BODY.encabezado, idDoc: { ...BODY.encabezado.idDoc, tipoeCF: "32" as const } } };
    expect(emissionPathFor(e32)).toBe(DOSA_ECF_EMISSION_PATH);

    const e34 = {
      ...BODY,
      encabezado: { ...BODY.encabezado, idDoc: { ...BODY.encabezado.idDoc, tipoeCF: "34" as const } },
    };
    expect(emissionPathFor(e34)).toBe(`${DOSA_ECF_CREDIT_NOTE_PATH}?nuevoENCF=E310000000001&tipoeCF=34&fechaEmision=02-11-2026`);
    expect(DOSA_ECF_CREDIT_NOTE_PATH).toBe("/fe/api/emision/ecf/NotaDesdeFactura");
  });

  it("un E34 sale por la ruta de notas de crédito", async () => {
    const transport = new FakeTransport(() => ({
      status: 200,
      body: JSON.stringify({ codigo: "1", estado: "Aceptado" }),
    }));
    const client = new DosaEmissionClient(transport, config());
    const e34 = {
      ...BODY,
      encabezado: { ...BODY.encabezado, idDoc: { ...BODY.encabezado.idDoc, tipoeCF: "34" as const } },
    };

    await client.sendEcf({ body: e34, idempotencyKey: "k-e34" });

    expect(transport.calls[0].url).toBe(
      `${config().baseUrl}${DOSA_ECF_CREDIT_NOTE_PATH}?nuevoENCF=E310000000001&tipoeCF=34&fechaEmision=02-11-2026`,
    );
  });
});

describe("DosaEmissionClient — transporte", () => {
  it("envía la clave en X-API-KEY y clasifica la respuesta", async () => {    const transport = new FakeTransport(() => ({
      status: 200,
      body: JSON.stringify({ data: { codigo: 1, encf: "E310000000001" } }),
    }));
    const client = new DosaEmissionClient(transport, config());

    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result.ok).toBe(true);
    expect(transport.calls[0].headers["X-API-KEY"]).toBe("TEST-KEY-SECRETA");
    expect(transport.calls[0].url).toContain("/fe/api/emision/ecf/EnviarFactura");
    if (result.ok) {
      expect(result.classification.outcome).toBe("ACCEPTED");
      expect(result.classification.eNCF).toBe("E310000000001");
    }
  });

  it("redacta la cabecera sensible en el resultado", async () => {
    const transport = new FakeTransport(() => ({
      status: 200,
      body: JSON.stringify({ data: { codigo: 1 } }),
    }));
    const client = new DosaEmissionClient(transport, config());
    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.redactedHeaders["X-API-KEY"]).toContain("[REDACTED");
      expect(JSON.stringify(result.redactedHeaders)).not.toContain(
        "TEST-KEY-SECRETA",
      );
    }
  });

  it("timeout queda como NO CONFIRMADO y no se reintenta solo", async () => {
    // Transporte que respeta la señal de aborto, como haría `fetch`.
    const transport: DosaHttpTransport = {
      async post(_url, init) {
        await new Promise<void>((_resolve, reject) => {
          init.signal.addEventListener("abort", () => {
            const error = new Error("aborted");
            error.name = "AbortError";
            reject(error);
          });
        });
        return { status: 200, body: "{}" };
      },
    };
    let calls = 0;
    const counted: DosaHttpTransport = {
      post: (url, init) => {
        calls += 1;
        return transport.post(url, init);
      },
    };
    const client = new DosaEmissionClient(counted, config({ timeoutMs: 20 }));

    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toMatchObject({
      ok: false,
      transportFailure: "TIMEOUT",
      unconfirmed: true,
      retryPermitted: false,
    });
    expect(calls).toBe(1);
  });

  it("un error de red sin aborto se distingue del timeout", async () => {
    const transport = new FakeTransport(() => {
      throw new Error("ECONNREFUSED");
    });
    const client = new DosaEmissionClient(transport, config());

    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toMatchObject({
      ok: false,
      transportFailure: "NETWORK",
      unconfirmed: true,
    });
  });

  it("502 queda como NO CONFIRMADO (el comprobante pudo entrar)", async () => {
    const transport = new FakeTransport(() => ({ status: 502, body: "bad" }));
    const client = new DosaEmissionClient(transport, config());

    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toMatchObject({
      ok: false,
      transportFailure: "HTTP",
      unconfirmed: true,
      status: 502,
      retryPermitted: false,
    });
  });

  it("respuesta no interpretable no se convierte en aceptación", async () => {
    const transport = new FakeTransport(() => ({
      status: 200,
      body: "<html>portal</html>",
    }));
    const client = new DosaEmissionClient(transport, config());

    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toMatchObject({ ok: false, unconfirmed: true });
  });

  it("502 con 'Error de envío' permite reintentar con el mismo eNCF", async () => {
    const transport = new FakeTransport(() => ({
      status: 502,
      body: JSON.stringify({ estado: "Error de envío", mensaje: "sin conexion DGII" }),
    }));
    const client = new DosaEmissionClient(transport, config());

    const result = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(result).toMatchObject({
      ok: false,
      transportFailure: "HTTP",
      status: 502,
      unconfirmed: false,
      retryPermitted: true,
    });
    // Y como no se marco como enviado, la clave sigue disponible.
    const retry = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });
    expect(retry).not.toMatchObject({
      blockedReason: "DOSA_IDEMPOTENCY_KEY_ALREADY_SENT",
    });
  });

  it("la misma clave no se envía dos veces", async () => {
    const transport = new FakeTransport(() => ({
      status: 200,
      body: JSON.stringify({ data: { codigo: 1 } }),
    }));
    const client = new DosaEmissionClient(transport, config());

    await client.sendEcf({ body: BODY, idempotencyKey: "k1" });
    const second = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });

    expect(second).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.alreadySent,
    });
    expect(transport.calls).toHaveLength(1);
  });

  it("un envío simultáneo con la misma clave se rechaza", async () => {
    let release: (() => void) | null = null;
    const transport: DosaHttpTransport = {
      async post() {
        await new Promise<void>((resolve) => {
          release = resolve;
        });
        return { status: 200, body: JSON.stringify({ data: { codigo: 1 } }) };
      },
    };
    const client = new DosaEmissionClient(transport, config({
      breakerThreshold: 99,
    }));

    const first = client.sendEcf({ body: BODY, idempotencyKey: "k1" });
    const second = await client.sendEcf({ body: BODY, idempotencyKey: "k1" });
    expect(second).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.duplicateKey,
    });

    // @ts-expect-error asignado dentro del transporte
    release?.();
    await first;
  });

  it("abre el cortacircuitos tras fallos consecutivos", async () => {
    const transport = new FakeTransport(() => ({ status: 503, body: "down" }));
    let clock = 1_000;
    const client = new DosaEmissionClient(transport, config(), () => clock);

    for (const key of ["k1", "k2", "k3"]) {
      await client.sendEcf({ body: BODY, idempotencyKey: key });
    }
    expect(client.breakerState()).toBe("OPEN");

    const blocked = await client.sendEcf({ body: BODY, idempotencyKey: "k4" });
    expect(blocked).toEqual({
      ok: false,
      blockedReason: DOSA_EMISSION_BLOCKED.breakerOpen,
    });
    expect(transport.calls).toHaveLength(3);

    clock += 60_000;
    expect(client.breakerState()).toBe("CLOSED");
  });
});

describe("recuperación DOSA con petición congelada y auditoría", () => {
  it.each(["NETWORK", "TIMEOUT", "HTTP_5XX"] as const)("recupera %s con los mismos bytes y destino", async failure => {
    const body = structuredClone(BODY);
    const settings = config({ timeoutMs: 5 });
    const frozen = freezeDosaHttpRequest(body);
    const calls: Array<{ url: string; body: string }> = [];
    const delays: number[] = [];
    const audits: DosaReplayInfo[] = [];
    const client = new DosaEmissionClient({ async post(url, input) {
      calls.push({ url, body: input.body });
      if (calls.length === 1) {
        body.encabezado.idDoc.eNCF = "E310000000999";
        settings.baseUrl = "https://must-not-be-used.test";
        if (failure === "HTTP_5XX") return { status: 503, body: "temporary" };
        if (failure === "TIMEOUT") return new Promise((_resolve, reject) => input.signal.addEventListener("abort", () => reject(Error("timeout"))));
        throw Error("connection lost");
      }
      return { status: 200, body: JSON.stringify({ estado: "Aceptado", codigo: "1" }) };
    } }, settings, Date.now, async ms => { delays.push(ms); });
    const result = await client.sendEcf({ body, idempotencyKey: "same-claim", onReplay: async event => { audits.push(event); return true; } });
    expect(result.ok).toBe(true);
    expect(calls).toHaveLength(2);
    expect(calls[0]).toEqual(calls[1]);
    expect(calls[0].body).toBe(frozen.bodyText);
    expect(calls[0].url).toBe(`https://sandbox.test${frozen.path}`);
    expect(audits[0]).toMatchObject({ ordinal: 2, reason: failure, bodyHash: frozen.bodyHash, requestHash: frozen.requestHash });
    expect(delays).toEqual([1000]);
  });

  it("limita la operación a tres llamadas y audita antes de cada repetición", async () => {
    const events: string[] = [];
    const delays: number[] = [];
    const client = new DosaEmissionClient({ async post() { events.push("post"); return { status: 503, body: "unavailable" }; } },
      config(), Date.now, async ms => { delays.push(ms); });
    const result = await client.sendEcf({ body: BODY, idempotencyKey: "bounded", onReplay: async event => {
      events.push(`audit:${event.ordinal}`); expect(event.previousResponseHash).toMatch(/^[a-f0-9]{64}$/); return true;
    } });
    expect(result).toMatchObject({ ok: false, transportFailure: "HTTP", status: 503 });
    expect(events).toEqual(["post", "audit:2", "post", "audit:3", "post"]);
    expect(delays).toEqual([1000, 3000]);
  });

  it.each([
    [200, "Aceptado"], [200, "Aceptado Condicional"], [200, "Rechazado"], [202, "Pendiente DGII"],
    [500, "Aceptado"], [500, "Rechazado"], [400, "Sin Resolver"],
  ])("no repite una respuesta observada %s/%s", async (status, estado) => {
    const transport = new FakeTransport(() => ({ status: Number(status), body: JSON.stringify({ estado }) }));
    const observer = jest.fn(async () => true);
    await new DosaEmissionClient(transport, config(), Date.now, async () => {}).sendEcf({ body: BODY, idempotencyKey: "observed", onReplay: observer });
    expect(transport.calls).toHaveLength(1);
    expect(observer).not.toHaveBeenCalled();
  });

  it("sin autorización de la auditoría conserva el resultado incierto y no repite", async () => {
    const transport = new FakeTransport(() => { throw Error("lost"); });
    const client = new DosaEmissionClient(transport, config(), Date.now, async () => {});
    const result = await client.sendEcf({ body: BODY, idempotencyKey: "denied", onReplay: async () => false });
    expect(result).toMatchObject({ ok: false, transportFailure: "NETWORK" });
    expect(transport.calls).toHaveLength(1);
  });

  it("mantiene exclusión durante la recuperación y luego bloquea otra emisión", async () => {
    let notify!: () => void;
    let release!: () => void;
    const entered = new Promise<void>(resolve => { notify = resolve; });
    const gate = new Promise<void>(resolve => { release = resolve; });
    const transport = new FakeTransport(attempt => attempt === 1 ? { status: 503, body: "temporary" } : { status: 200, body: '{"estado":"Aceptado"}' });
    const client = new DosaEmissionClient(transport, config(), Date.now, async () => {});
    const first = client.sendEcf({ body: BODY, idempotencyKey: "exclusive", onReplay: async () => { notify(); await gate; return true; } });
    await entered;
    expect(await client.sendEcf({ body: BODY, idempotencyKey: "exclusive" })).toEqual({ ok: false, blockedReason: DOSA_EMISSION_BLOCKED.duplicateKey });
    release(); expect((await first).ok).toBe(true);
    expect(await client.sendEcf({ body: BODY, idempotencyKey: "exclusive" })).toEqual({ ok: false, blockedReason: DOSA_EMISSION_BLOCKED.alreadySent });
    expect(transport.calls).toHaveLength(2);
  });

  it("congela también el e-NCF de la ruta E34", async () => {
    const body = structuredClone(BODY);
    body.encabezado.idDoc.tipoeCF = "34"; body.encabezado.idDoc.eNCF = "E340000000001";
    const urls: string[] = [];
    const client = new DosaEmissionClient({ async post(url) {
      urls.push(url);
      if (urls.length === 1) { body.encabezado.idDoc.eNCF = "E340000000099"; return { status: 503, body: "temporary" }; }
      return { status: 200, body: '{"estado":"Aceptado"}' };
    } }, config(), Date.now, async () => {});
    await client.sendEcf({ body, idempotencyKey: "credit", onReplay: async () => true });
    expect(urls).toHaveLength(2); expect(urls[0]).toBe(urls[1]);
    expect(urls[0]).toContain("nuevoENCF=E340000000001");
  });
});

describe("readDosaEmissionConfig", () => {
  it("entorno vacío deja todo desactivado y en TEST", () => {
    const config = readDosaEmissionConfig({});
    expect(config.enabled).toBe(false);
    expect(config.environment).toBe("TEST");
    expect(config.apiKey).toBe("");
    expect(config.productionEnabled).toBe(false);
  });

  it("usa la clave de TEST solo en TEST", () => {
    const config = readDosaEmissionConfig({
      DOSA_TEST_API_KEY: "clave-test",
      DOSA_PRODUCTION_API_KEY: "clave-prod",
    });
    expect(config.environment).toBe("TEST");
    expect(config.apiKey).toBe("clave-test");
    expect(config.apiKeyIsProduction).toBe(false);
  });

  it("en PRODUCTION usa la clave de producción", () => {
    const config = readDosaEmissionConfig({
      DOSA_EMISSION_ENVIRONMENT: "PRODUCTION",
      DOSA_TEST_API_KEY: "clave-test",
      DOSA_PRODUCTION_API_KEY: "clave-prod",
    });
    expect(config.apiKey).toBe("clave-prod");
    expect(config.apiKeyIsProduction).toBe(true);
  });

  it("normaliza la barra final del baseUrl", () => {
    expect(readDosaEmissionConfig({ DOSA_BASE_URL: "https://x.test/" }).baseUrl).toBe(
      "https://x.test",
    );
  });
});

describe("redactDosaHeaders", () => {
  it("oculta claves pero conserva la longitud (para diagnosticar sin exponer)", () => {
    const redacted = redactDosaHeaders({
      "Content-Type": "application/json",
      "X-API-KEY": "secreto-largo-123",
    });
    expect(redacted["Content-Type"]).toBe("application/json");
    expect(redacted["X-API-KEY"]).toBe("[REDACTED:17]");
    expect(JSON.stringify(redacted)).not.toContain("secreto-largo-123");
  });
});
