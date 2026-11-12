import {
  FakeDosaHttpTransport,
  resolveFakeTransportSelection,
} from "./dosa-emission.fake-transport";

/**
 * Selección del transporte FALSO: la puerta que no puede abrirse por accidente.
 *
 * Lo que se fija aquí:
 *  1. Sin variable, o con `FETCH`, se usa el transporte real (no se devuelve FAKE).
 *  2. `FAKE` fuera de una UAT local **lanza**: un despliegue que herede la
 *     variable no arranca apuntando a un transporte falso.
 *  3. Un valor desconocido lanza: no hay "modo parecido" que se acepte en
 *     silencio.
 *  4. El transporte falso no abre red: devuelve una respuesta y guarda la
 *     petición para inspección.
 */
describe("resolveFakeTransportSelection", () => {
  it("sin variable usa el transporte real", () => {
    expect(resolveFakeTransportSelection({})).toBeNull();
  });

  it("FETCH explícito usa el transporte real", () => {
    expect(
      resolveFakeTransportSelection({ DOSA_EMISSION_TRANSPORT: "FETCH", APP_ENV: "uat" }),
    ).toBeNull();
  });

  it("FAKE se acepta en UAT declarada con APP_ENV", () => {
    expect(
      resolveFakeTransportSelection({
        DOSA_EMISSION_TRANSPORT: "FAKE",
        APP_ENV: "uat",
      }),
    ).toBe("FAKE");
  });

  it("FAKE se acepta con UAT_LOCAL_ONLY", () => {
    expect(
      resolveFakeTransportSelection({
        DOSA_EMISSION_TRANSPORT: "fake",
        UAT_LOCAL_ONLY: "true",
      }),
    ).toBe("FAKE");
  });

  it("FAKE fuera de UAT local LANZA (no hay fallback silencioso)", () => {
    expect(() =>
      resolveFakeTransportSelection({
        DOSA_EMISSION_TRANSPORT: "FAKE",
        APP_ENV: "production",
      }),
    ).toThrow(/ECF_DOSA_FAKE_TRANSPORT_FORBIDDEN/);
  });

  it("FAKE sin entorno declarado LANZA", () => {
    expect(() =>
      resolveFakeTransportSelection({ DOSA_EMISSION_TRANSPORT: "FAKE" }),
    ).toThrow(/ECF_DOSA_FAKE_TRANSPORT_FORBIDDEN/);
  });

  it("un valor desconocido LANZA y nombra la variable", () => {
    expect(() =>
      resolveFakeTransportSelection({ DOSA_EMISSION_TRANSPORT: "MOCK" }),
    ).toThrow(/ECF_DOSA_TRANSPORT_UNKNOWN/);
  });
});

describe("FakeDosaHttpTransport", () => {
  it("captura la petición y responde sin abrir conexiones", async () => {
    const transport = new FakeDosaHttpTransport();
    const body = JSON.stringify({
      encabezado: { idDoc: { eNCF: "E310000000042" } },
    });

    const response = await transport.post("https://dosa.fake.invalid/invoices", {
      headers: { "X-API-KEY": "sk_test_FICTICIA" },
      body,
      signal: new AbortController().signal,
    });

    expect(transport.requests).toHaveLength(1);
    expect(transport.requests[0]).toMatchObject({
      url: "https://dosa.fake.invalid/invoices",
      body,
    });
    expect(transport.requests[0].headers["X-API-KEY"]).toBe("sk_test_FICTICIA");

    const parsed = JSON.parse(response.body) as Record<string, unknown>;
    // Devuelve el e-NCF recibido y NO declara aceptación fiscal.
    expect(parsed.encf).toBe("E310000000042");
    expect(JSON.stringify(parsed)).not.toMatch(/DGII|ACEPTAD[OA]\s+por/i);
    expect(response.status).toBe(200);
  });

  it("reset limpia la captura sin tocar la respuesta", async () => {
    const transport = new FakeDosaHttpTransport();
    await transport.post("https://dosa.fake.invalid/invoices", {
      headers: {},
      body: "{}",
      signal: new AbortController().signal,
    });
    expect(transport.requests).toHaveLength(1);
    transport.reset();
    expect(transport.requests).toHaveLength(0);
  });
});
