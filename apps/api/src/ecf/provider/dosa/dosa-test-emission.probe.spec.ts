import {
  DOSA_PROBE_ALLOWED_ORIGIN,
  DOSA_PROBE_BLOCKED,
  DosaE31TestProbe,
  assessProbeReadiness,
  probeAuthorizationToken,
  totalsAreCoherent,
  type DosaProbeConfig,
  type DosaProbeEvidence,
} from "./dosa-test-emission.probe";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import type { DosaHttpResponse, DosaHttpTransport } from "./dosa-emission.client";

/**
 * Probador E31 de TEST.
 *
 * Todo simulado: no hay red, no hay clave real y no hay base de datos. Lo que se
 * demuestra es que el probador **se niega** a enviar cuando algo no cuadra, y
 * que cuando envía lo hace una sola vez y deja evidencia sin la clave.
 */

const ENCF = "E31000113500";
const RNC = "133306001";

function baseConfig(overrides: Partial<DosaProbeConfig> = {}): DosaProbeConfig {
  return {
    environment: "TEST",
    baseUrl: DOSA_PROBE_ALLOWED_ORIGIN,
    apiKey: "CLAVE-TEST-SINTETICA",
    testRnc: RNC,
    sequenceRange: { prefix: "E31", from: 113500, to: 115500 },
    timeoutMs: 50,
    ...overrides,
  };
}

function e31(overrides: Partial<DosaEcfRequestBody["encabezado"]> = {}): DosaEcfRequestBody {
  return {
    encabezado: {
      version: "1.0",
      idDoc: { tipoeCF: "31", eNCF: ENCF, fechaEmision: "03-11-2026" },
      emisor: { RNCEmisor: RNC, RazonSocialEmisor: "EMPRESA DE PRUEBA" },
      totales: {
        MontoGravadoTotal: "100.00",
        MontoGravadoI1: "100.00",
        MontoExento: "0.00",
        ITBIS1: "18",
        TotalITBIS: "18.00",
        MontoTotal: "118.00",
      },
      ...overrides,
    },
    detallesItems: [
      {
        numeroLinea: 1,
        indicadorFacuracionPlaceholder: undefined,
        indicadorFacturacion: 1,
        nombreItem: "PRUEBA",
        indicadorBienoServicio: 2,
        cantidadItem: "1",
        precioUnitarioItem: "100.00",
        montoItem: "100.00",
      } as never,
    ],
  };
}

class CountingTransport implements DosaHttpTransport {
  readonly calls: Array<{ url: string; body: string; apiKey: string }> = [];
  constructor(private readonly respond: () => DosaHttpResponse | Promise<DosaHttpResponse>) {}
  async post(url: string, init: { headers: Record<string, string>; body: string }) {
    this.calls.push({ url, body: init.body, apiKey: init.headers["X-API-KEY"] });
    return this.respond();
  }
}

const OK_BODY = JSON.stringify({
  trackId: "t-1",
  codigo: "1",
  estado: "Aceptado",
  rnc: RNC,
  encf: ENCF,
  url: "https://ecf.dgii.gov.do/testecf/consulta?encf=E31000113500",
  codigoSeguridad: "ABC123",
  fechaFirma: "03-11-2026 10:00:00",
  secuenciaUtilizada: true,
  mensajes: [],
});

describe("assessProbeReadiness", () => {
  it("un E31 coherente en TEST está listo", () => {
    const readiness = assessProbeReadiness({
      config: baseConfig(),
      body: e31(),
      encf: ENCF,
    });
    expect(readiness).toEqual({ allowed: true, blockedReasons: [] });
  });

  it("solo TEST: producción queda fuera", () => {
    const readiness = assessProbeReadiness({
      config: baseConfig({ environment: "PRODUCTION" }),
      body: e31(),
      encf: ENCF,
    });
    expect(readiness.allowed).toBe(false);
    expect(readiness.blockedReasons).toContain(
      DOSA_PROBE_BLOCKED.notTestEnvironment,
    );
  });

  it("rechaza cualquier URL que no sea la documentada", () => {
    for (const baseUrl of [
      "https://ecf.dgii.gov.do",
      "https://dosasystem.com.evil.example",
      "http://dosasystem.com",
      "https://dosasystem.com/otra",
      "",
    ]) {
      const readiness = assessProbeReadiness({
        config: baseConfig({ baseUrl }),
        body: e31(),
        encf: ENCF,
      });
      expect(readiness.blockedReasons).toContain(
        DOSA_PROBE_BLOCKED.unroutableBaseUrl,
      );
    }
  });

  it("exige que el RNC emisor sea el RNC de prueba", () => {
    const body = e31();
    body.encabezado.emisor.RNCEmisor = "101742186";
    const readiness = assessProbeReadiness({ config: baseConfig(), body, encf: ENCF });
    expect(readiness.blockedReasons).toContain(DOSA_PROBE_BLOCKED.rncMismatch);
  });

  it("acepta el RNC con formato separado (normaliza)", () => {
    const body = e31();
    body.encabezado.emisor.RNCEmisor = "1-33-306-001";
    const readiness = assessProbeReadiness({ config: baseConfig(), body, encf: ENCF });
    expect(readiness.allowed).toBe(true);
  });

  it("rechaza un e-NCF fuera del rango autorizado", () => {
    for (const encf of ["E31000113499", "E31000115501", "E32000113500", "E31ABC"]) {
      const readiness = assessProbeReadiness({
        config: baseConfig(),
        body: e31(),
        encf,
      });
      expect(readiness.blockedReasons).toContain(
        DOSA_PROBE_BLOCKED.encfOutsideRange,
      );
    }
  });

  it("rechaza un documento que no es E31", () => {
    const body = e31();
    (body.encabezado.idDoc as { tipoeCF: string }).tipoeCF = "32";
    const readiness = assessProbeReadiness({ config: baseConfig(), body, encf: ENCF });
    expect(readiness.blockedReasons).toContain(
      DOSA_PROBE_BLOCKED.unsupportedType,
    );
  });

  it("rechaza totales incoherentes", () => {
    const body = e31();
    body.encabezado.totales.MontoTotal = "999.00";
    const readiness = assessProbeReadiness({ config: baseConfig(), body, encf: ENCF });
    expect(readiness.blockedReasons).toContain(
      DOSA_PROBE_BLOCKED.totalsIncoherent,
    );
  });

  it("rechaza sin clave o sin RNC de prueba", () => {
    expect(
      assessProbeReadiness({
        config: baseConfig({ apiKey: "" }),
        body: e31(),
        encf: ENCF,
      }).blockedReasons,
    ).toContain(DOSA_PROBE_BLOCKED.apiKeyMissing);
    expect(
      assessProbeReadiness({
        config: baseConfig({ testRnc: "" }),
        body: e31(),
        encf: ENCF,
      }).blockedReasons,
    ).toContain(DOSA_PROBE_BLOCKED.testRncMissing);
  });
});

describe("totalsAreCoherent", () => {
  it("acepta un E31 que cuadra", () => {
    expect(totalsAreCoherent(e31())).toBe(true);
  });

  it("detecta una línea que no cuadra con cantidad × precio", () => {
    const body = e31();
    body.detallesItems[0].montoItem = "90.00";
    expect(totalsAreCoherent(body)).toBe(false);
  });

  it("detecta un total que no es la suma de sus partes", () => {
    const body = e31();
    body.encabezado.totales.TotalITBIS = "10.00";
    expect(totalsAreCoherent(body)).toBe(false);
  });

  it("rechaza importes sin dos decimales", () => {
    const body = e31();
    body.encabezado.totales.MontoTotal = "118";
    expect(totalsAreCoherent(body)).toBe(false);
  });
});

describe("DosaE31TestProbe — autorización y envío", () => {
  it("sin token de autorización no hace ninguna petición", async () => {
    const transport = new CountingTransport(() => ({ status: 200, body: OK_BODY }));
    const evidence: DosaProbeEvidence[] = [];
    const probe = new DosaE31TestProbe({
      transport,
      config: baseConfig(),
      onEvidence: (item) => evidence.push(item),
    });

    const result = await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: null,
    });

    expect(result.ok).toBe(false);
    expect(result.blockedReasons).toContain(
      DOSA_PROBE_BLOCKED.notAuthorized,
    );
    expect(transport.calls).toHaveLength(0);
    expect(evidence).toHaveLength(1);
    expect(evidence[0].outcome).toBe("BLOCKED");
  });

  it("un token inventado tampoco envía", async () => {
    const transport = new CountingTransport(() => ({ status: 200, body: OK_BODY }));
    const probe = new DosaE31TestProbe({ transport, config: baseConfig() });
    const result = await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: "AUTHORIZE-OTRO-NCF",
    });
    expect(result.ok).toBe(false);
    expect(transport.calls).toHaveLength(0);
  });

  it("con el token correcto envía UNA vez al endpoint documentado", async () => {
    const transport = new CountingTransport(() => ({ status: 200, body: OK_BODY }));
    const probe = new DosaE31TestProbe({ transport, config: baseConfig() });

    const result = await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: probeAuthorizationToken(ENCF),
    });

    expect(result.ok).toBe(true);
    expect(transport.calls).toHaveLength(1);
    expect(transport.calls[0].url).toBe(
      "https://dosasystem.com/fe/api/emision/ecf/EnviarFactura",
    );
    expect(transport.calls[0].apiKey).toBe("CLAVE-TEST-SINTETICA");
    expect(result.evidence.classification?.outcome).toBe("ACCEPTED");
    expect(result.evidence.classification?.secuenciaUtilizada).toBe(true);
    expect(result.evidence.responseSha256).toHaveLength(64);
  });

  it("la evidencia NUNCA contiene la clave de la API", async () => {
    const transport = new CountingTransport(() => ({ status: 200, body: OK_BODY }));
    const evidence: DosaProbeEvidence[] = [];
    const probe = new DosaE31TestProbe({
      transport,
      config: baseConfig(),
      onEvidence: (item) => evidence.push(item),
    });

    await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: probeAuthorizationToken(ENCF),
    });

    const serialized = JSON.stringify(evidence);
    expect(serialized).not.toContain("CLAVE-TEST-SINTETICA");
    expect(evidence[0].apiKeyLength).toBe("CLAVE-TEST-SINTETICA".length);
  });

  it("un resultado incierto NO se reintenta y se marca como tal", async () => {
    let calls = 0;
    const transport: DosaHttpTransport = {
      async post(_url, init) {
        calls += 1;
        await new Promise<void>((_resolve, reject) => {
          init.signal.addEventListener("abort", () => reject(new Error("aborted")));
        });
        return { status: 200, body: OK_BODY };
      },
    };
    const probe = new DosaE31TestProbe({
      transport,
      config: baseConfig({ timeoutMs: 20 }),
    });

    const result = await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: probeAuthorizationToken(ENCF),
    });

    expect(result.ok).toBe(true);
    expect(result.evidence.outcome).toBe("UNCERTAIN");
    expect(calls).toBe(1);
    expect(result.evidence.safeToRetrySameEncf).toBe(false);
  });

  it("un 502 'Error de envío' es el único caso con reintento seguro", async () => {
    const transport = new CountingTransport(() => ({
      status: 502,
      body: JSON.stringify({ estado: "Error de envío", mensaje: "sin DGII" }),
    }));
    const probe = new DosaE31TestProbe({ transport, config: baseConfig() });

    const result = await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: probeAuthorizationToken(ENCF),
    });

    expect(result.evidence.classification?.outcome).toBe("NOT_RECEIVED");
    expect(result.evidence.safeToRetrySameEncf).toBe(true);
    expect(transport.calls).toHaveLength(1);
  });

  it("un rechazo de la DGII se conserva con su mensaje", async () => {
    const transport = new CountingTransport(() => ({
      status: 200,
      body: JSON.stringify({
        codigo: "2",
        estado: "Rechazado",
        mensajes: [{ valor: "RNC del emisor invalido", codigo: 1001 }],
      }),
    }));
    const probe = new DosaE31TestProbe({ transport, config: baseConfig() });

    const result = await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: probeAuthorizationToken(ENCF),
    });

    expect(result.evidence.classification?.outcome).toBe("REJECTED");
    expect(result.evidence.classification?.mensajes[0]).toContain("RNC");
  });

  it("un entorno no verificable bloquea antes de cualquier socket", async () => {
    const transport = new CountingTransport(() => ({ status: 200, body: OK_BODY }));
    const probe = new DosaE31TestProbe({
      transport,
      // Base URL no documentada: no se debe abrir conexión.
      config: baseConfig({ baseUrl: "https://endpoint-desconocido.example" }),
    });

    const result = await probe.run({
      body: e31(),
      encf: ENCF,
      authorizationToken: probeAuthorizationToken(ENCF),
    });

    expect(result.ok).toBe(false);
    expect(transport.calls).toHaveLength(0);
  });
});
