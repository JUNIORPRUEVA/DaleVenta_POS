import {
  DOSA_QUERY_AUTH_HEADER,
  DosaApiClient,
  readDosaQueryAuthConfig,
  type DosaQueryAuthConfig,
  type DosaFetchLike,
} from "./dosa-api.client";
import {
  DOSA_ECF_CREDIT_NOTE_PATH,
  DOSA_ECF_EMISSION_PATH,
} from "./dosa-ecf.contract";

/**
 * Cliente de consultas DOSA: `X-Dosa-Secret-Key`, sin firma por solicitud.
 *
 * Estas pruebas fijan dos cosas que importan más que el propio GET:
 *
 * 1. **No se toca la red** sin configuración explícita y completa.
 * 2. Este cliente **nunca** llama a una ruta de emisión, aunque se lo pidan.
 */

const SECRET = "sk_clave_de_consulta_no_real";
const BASE = "https://dosasystem.example";

function config(
  overrides: Partial<DosaQueryAuthConfig> = {},
): DosaQueryAuthConfig {
  return {
    baseUrl: BASE,
    secretKey: SECRET,
    enabled: true,
    timeoutMs: 5_000,
    ...overrides,
  };
}

function recordingFetch(status = 200, body: unknown = { ok: true }) {
  const calls: Array<{ url: string; init: { method: string; headers: Record<string, string> } }> = [];
  const impl: DosaFetchLike = async (url, init) => {
    calls.push({ url, init });
    return {
      status,
      async text() {
        return JSON.stringify(body);
      },
    };
  };
  return { impl, calls };
}

describe("DosaApiClient — consultas con X-Dosa-Secret-Key", () => {
  it("envía la clave en X-Dosa-Secret-Key y no en la URL", async () => {
    const { impl, calls } = recordingFetch();
    const client = new DosaApiClient(config(), impl);

    const result = await client.getJson("/fe/api/consulta/estado");

    expect(result.ok).toBe(true);
    expect(calls).toHaveLength(1);
    expect(calls[0].init.method).toBe("GET");
    expect(calls[0].init.headers[DOSA_QUERY_AUTH_HEADER]).toBe(SECRET);
    expect(calls[0].url).not.toContain(SECRET);
    expect(calls[0].url).toBe(`${BASE}/fe/api/consulta/estado`);
  });

  it("por defecto está APAGADO: no se hace ninguna llamada", async () => {
    const { impl, calls } = recordingFetch();
    const client = new DosaApiClient(config({ enabled: false }), impl);

    const result = await client.getJson("/fe/api/consulta/estado");

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_QUERY_NOT_CONFIGURED",
    });
    expect(calls).toHaveLength(0);
  });

  it("sin clave secreta no se hace ninguna llamada", async () => {
    const { impl, calls } = recordingFetch();
    const client = new DosaApiClient(config({ secretKey: null }), impl);

    const result = await client.getJson("/x");

    expect((result as { reason: string }).reason).toContain("SECRET_KEY_MISSING");
    expect(calls).toHaveLength(0);
  });

  it("rechaza una clave que no es de consulta (evita usar la de emisión)", async () => {
    const { impl, calls } = recordingFetch();
    // Una API Key de emisión no empieza por `sk_`.
    const client = new DosaApiClient(config({ secretKey: "clave-de-emision" }), impl);

    const result = await client.getJson("/x");

    expect((result as { reason: string }).reason).toContain("SECRET_KEY_MALFORMED");
    expect(calls).toHaveLength(0);
  });

  it("sin base URL no se hace ninguna llamada", async () => {
    const { impl, calls } = recordingFetch();
    const client = new DosaApiClient(config({ baseUrl: "" }), impl);

    const result = await client.getJson("/x");

    expect((result as { reason: string }).reason).toContain("BASE_URL_MISSING");
    expect(calls).toHaveLength(0);
  });

  it.each([
    ["EnviarFactura", DOSA_ECF_EMISSION_PATH],
    ["NotaDesdeFactura", DOSA_ECF_CREDIT_NOTE_PATH],
  ])("nunca llama a la ruta de emisión %s", async (_label, path) => {
    const { impl, calls } = recordingFetch();
    const client = new DosaApiClient(config(), impl);

    const result = await client.getJson(path);

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_QUERY_NOT_FOR_EMISSION",
    });
    expect(calls).toHaveLength(0);
  });

  it("exige una ruta absoluta", async () => {
    const { impl, calls } = recordingFetch();
    const client = new DosaApiClient(config(), impl);

    const result = await client.getJson("sin-barra");

    expect(result).toMatchObject({ ok: false, code: "ECF_DOSA_QUERY_INVALID_PATH" });
    expect(calls).toHaveLength(0);
  });

  it("un error HTTP no se presenta como éxito", async () => {
    const { impl } = recordingFetch(500, { error: "boom" });
    const client = new DosaApiClient(config(), impl);

    const result = await client.getJson("/fe/api/consulta/estado");

    expect(result).toMatchObject({
      ok: false,
      status: 500,
      code: "ECF_DOSA_QUERY_HTTP_ERROR",
    });
  });

  it("un cuerpo que no es JSON no se inventa: queda en null", async () => {
    const impl: DosaFetchLike = async () => ({
      status: 200,
      async text() {
        return "<html>no json</html>";
      },
    });
    const client = new DosaApiClient(config(), impl);

    const result = await client.getJson("/x");

    expect(result).toMatchObject({ ok: true, status: 200, body: null });
  });

  it("describeReadiness informa presencia de la clave, nunca su valor", () => {
    const client = new DosaApiClient(config());
    const readiness = client.describeReadiness();

    expect(readiness.ready).toBe(true);
    expect(readiness.hasSecretKey).toBe(true);
    expect(JSON.stringify(readiness)).not.toContain(SECRET);
  });
});

describe("readDosaQueryAuthConfig", () => {
  it("sin variables queda apagado y sin clave", () => {
    const config = readDosaQueryAuthConfig({});
    expect(config.enabled).toBe(false);
    expect(config.secretKey).toBeNull();
    expect(config.baseUrl).toBe("");
  });

  it("solo se enciende con el valor exacto true", () => {
    expect(
      readDosaQueryAuthConfig({ DOSA_API_QUERIES_ENABLED: "TRUE" }).enabled,
    ).toBe(true);
    expect(
      readDosaQueryAuthConfig({ DOSA_API_QUERIES_ENABLED: "1" }).enabled,
    ).toBe(false);
  });

  it("quita la barra final de la base URL", () => {
    expect(
      readDosaQueryAuthConfig({ DOSA_BASE_URL: "https://dosasystem.com///" }).baseUrl,
    ).toBe("https://dosasystem.com");
  });

  it("una espera inválida cae al valor por defecto", () => {
    const config = readDosaQueryAuthConfig({ DOSA_QUERY_TIMEOUT_MS: "cero" });
    expect(config.timeoutMs).toBe(15_000);
  });
});
