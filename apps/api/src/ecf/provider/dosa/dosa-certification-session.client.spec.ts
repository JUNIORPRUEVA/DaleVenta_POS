import {
  DOSA_CERTIFICATION_SESSIONS_PATH,
  DOSA_SESSION_AUTH_HEADER,
  DosaCertificationSessionClient,
  isDosaEmailValid,
  normalizeDosaRnc,
  readDosaSessionConfig,
  redactSessionUrl,
  type DosaFetchLike,
  type DosaSessionConfig,
} from "./dosa-certification-session.client";

/**
 * Contrato de sesiones de DOSA — probado con un servidor **simulado**.
 *
 * Ninguna prueba de este archivo toca la red: `fetchImpl` está siempre inyectado
 * y, además, se comprueba que el cliente no lo llama cuando la configuración no
 * está completa. Ese es el punto: en desarrollo no debe existir ninguna
 * solicitud real.
 */

const SECRET = "sk_clave_de_prueba_no_real";

const BASE = "https://dosasystem.test";
const RETURN = "https://fullpos.test/ecf/certificacion/";

function config(overrides: Partial<DosaSessionConfig> = {}): DosaSessionConfig {
  return {
    baseUrl: BASE,
    secretKey: SECRET,
    enabled: true,
    timeoutMs: 1_000,
    allowedReturnOrigins: ["https://fullpos.test"],
    ...overrides,
  };
}

type Captured = { url: string; body: unknown; headers: Record<string, string> };

function transport(
  status: number,
  payload: unknown,
  captured?: Captured[],
): DosaFetchLike {
  return async (url, init) => {
    captured?.push({
      url,
      body: init.body ? JSON.parse(init.body) : null,
      headers: init.headers,
    });
    const text = typeof payload === "string" ? payload : JSON.stringify(payload);
    return { status, text: async () => text };
  };
}

function created(overrides: Record<string, unknown> = {}) {
  return {
    url: "https://dosasystem.test/certificacion/sesion/abc",
    path: "/certificacion/sesion/abc",
    token: "tok_1234567890",
    expires_at: new Date(Date.now() + 7 * 24 * 3600_000).toISOString(),
    postulacion_id: "post-1",
    prueba: true,
    ...overrides,
  };
}

const validRequest = { rncEmisor: "133080206", correo: "empresa@fulltech.test" };

describe("DosaCertificationSessionClient — contrato de sesiones", () => {
  it("envía el RNC y el correo en el cuerpo y la clave solo en la cabecera", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created(), captured),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(true);
    expect(captured).toHaveLength(1);
    expect(captured[0].url).toBe(`${BASE}${DOSA_CERTIFICATION_SESSIONS_PATH}`);
    expect(captured[0].body).toEqual({
      rnc_emisor: "133080206",
      correo: "empresa@fulltech.test",
    });
    expect(captured[0].headers[DOSA_SESSION_AUTH_HEADER]).toBe(SECRET);
    // La clave NUNCA va en el cuerpo ni en la URL.
    expect(JSON.stringify(captured[0].body)).not.toContain(SECRET);
    expect(captured[0].url).not.toContain(SECRET);
  });

  it("no devuelve ni registra la clave secreta en el resultado", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created()),
    );
    const result = await client.createSession(validRequest);

    expect(JSON.stringify(result)).not.toContain(SECRET);
  });

  it("normaliza la sesión creada y conserva `prueba`", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created({ prueba: false, postulacion_id: 987 })),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.status).toBe(201);
    expect(result.session.postulacionId).toBe("987");
    expect(result.session.prueba).toBe(false);
    expect(result.session.token).toBe("tok_1234567890");
    expect(result.session.path).toBe("/certificacion/sesion/abc");
  });

  it("incluye return_url solo cuando se aporta y está permitido", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created(), captured),
    );

    await client.createSession({ ...validRequest, returnUrl: RETURN });

    expect(captured[0].body).toEqual({
      rnc_emisor: "133080206",
      correo: "empresa@fulltech.test",
      return_url: RETURN,
    });
  });

  it("rechaza un return_url de un origen no permitido sin tocar la red", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created(), captured),
    );

    const result = await client.createSession({
      ...validRequest,
      returnUrl: "https://atacante.test/robo",
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_RETURN_URL_NOT_ALLOWED");
    expect(captured).toHaveLength(0);
  });

  it("rechaza un return_url por http aunque el origen esté en la lista", async () => {
    const client = new DosaCertificationSessionClient(
      config({ allowedReturnOrigins: ["http://fullpos.test"] }),
      transport(201, created()),
    );

    const result = await client.createSession({
      ...validRequest,
      returnUrl: "http://fullpos.test/ecf/certificacion/",
    });

    expect(result.ok).toBe(false);
  });

  it.each([
    [400, "DOSA_SESSION_BAD_STATUS"],
    [401, "DOSA_SESSION_BAD_STATUS"],
    [403, "DOSA_SESSION_BAD_STATUS"],
    [404, "DOSA_SESSION_BAD_STATUS"],
    [429, "DOSA_SESSION_BAD_STATUS"],
  ])("traduce el HTTP %i a un fallo cerrado sin incertidumbre", async (status, code) => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(status, { message: "no" }),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(code);
    expect(result.status).toBe(status);
    expect(result.uncertain).toBeUndefined();
  });

  it("marca el 500 como incierto: DOSA pudo crear la sesión", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(500, "boom"),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_NETWORK_UNCERTAIN");
    expect(result.uncertain).toBe(true);
  });

  it("marca el corte de red como incierto en lugar de fallar en silencio", async () => {
    const client = new DosaCertificationSessionClient(config(), async () => {
      throw new Error("ECONNRESET");
    });

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_NETWORK_UNCERTAIN");
    expect(result.uncertain).toBe(true);
  });

  it("rechaza una respuesta 201 sin url usable", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created({ url: "http://dosasystem.test/x" })),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_MALFORMED_RESPONSE");
    // El 201 confirma que el proveedor pudo crear la sesión: no se reintenta.
    expect(result.uncertain).toBe(true);
  });

  it("rechaza una url de otro dominio aunque sea https", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created({ url: "https://otro-sitio.test/sesion/abc" })),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
  });

  it("rechaza un token vacío o demasiado corto", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created({ token: "" })),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_MALFORMED_RESPONSE");
  });

  it("rechaza un path que no sea absoluto", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created({ path: "certificacion/sesion/abc" })),
    );

    expect((await client.createSession(validRequest)).ok).toBe(false);
  });

  it("rechaza postulacion_id ausente y prueba no booleana", async () => {
    const sinId = new DosaCertificationSessionClient(
      config(),
      transport(201, created({ postulacion_id: null })),
    );
    const sinPrueba = new DosaCertificationSessionClient(
      config(),
      transport(201, created({ prueba: "si" })),
    );

    expect((await sinId.createSession(validRequest)).ok).toBe(false);
    expect((await sinPrueba.createSession(validRequest)).ok).toBe(false);
  });

  it("detecta una sesión que llega ya caducada", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(
        201,
        created({ expires_at: new Date(Date.now() - 60_000).toISOString() }),
      ),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_EXPIRED");
    expect(result.uncertain).toBe(true);
  });

  it("rechaza una respuesta 201 que no sea JSON", async () => {
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, "<html>error</html>"),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_MALFORMED_RESPONSE");
    expect(result.uncertain).toBe(true);
  });

  it("rechaza una base HTTP porque la clave viajaría sin TLS", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config({ baseUrl: "http://dosasystem.test" }),
      transport(201, created(), captured),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_BASE_URL_INVALID");
    expect(captured).toHaveLength(0);
  });

  it("no toca la red si la bandera está apagada", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config({ enabled: false }),
      transport(201, created(), captured),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_DISABLED");
    expect(captured).toHaveLength(0);
  });

  it("no toca la red si falta la clave secreta", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config({ secretKey: null }),
      transport(201, created(), captured),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_SECRET_MISSING");
    expect(captured).toHaveLength(0);
  });

  it("rechaza una clave con forma incorrecta", async () => {
    const client = new DosaCertificationSessionClient(
      config({ secretKey: "no-es-una-clave" }),
      transport(201, created()),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_SECRET_MALFORMED");
  });

  it("nunca apunta a una ruta de emisión", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config({ baseUrl: "https://dosasystem.test/fe/api/emision/ecf/EnviarFactura" }),
      transport(201, created(), captured),
    );

    const result = await client.createSession(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_BASE_URL_INVALID");
    expect(captured).toHaveLength(0);
  });

  it("rechaza un RNC que no tiene 9 ni 11 dígitos", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created(), captured),
    );

    const result = await client.createSession({
      rncEmisor: "1330",
      correo: "empresa@fulltech.test",
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_RNC_INVALID");
    expect(captured).toHaveLength(0);
  });

  it("rechaza una empresa sin correo válido antes de llamar al proveedor", async () => {
    const captured: Captured[] = [];
    const client = new DosaCertificationSessionClient(
      config(),
      transport(201, created(), captured),
    );

    const result = await client.createSession({ rncEmisor: "133080206", correo: "  " });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("DOSA_SESSION_EMAIL_INVALID");
    expect(captured).toHaveLength(0);
  });
});

describe("normalizeDosaRnc", () => {
  it.each([
    ["133080206", "133080206"],
    ["1-01-74218-6", "101742186"],
    ["402-1234567-8", "40212345678"],
  ])("normaliza %s", (input, expected) => {
    expect(normalizeDosaRnc(input)).toBe(expected);
  });

  it.each(["", "1234", "abcdefghi", "1330802064"])(
    "rechaza %s",
    (input) => {
      expect(normalizeDosaRnc(input)).toBeNull();
    },
  );
});

describe("isDosaEmailValid", () => {
  it.each(["empresa@fulltech.test", "a.b+tag@dominio.com.do"])(
    "acepta %s",
    (value) => expect(isDosaEmailValid(value)).toBe(true),
  );

  it.each(["", "sin-arroba", "a@b", "a@b.c", "dos@dos@dos.com"])(
    "rechaza %s",
    (value) => expect(isDosaEmailValid(value)).toBe(false),
  );
});

describe("redactSessionUrl", () => {
  it("quita query y fragmento, que es donde viaja la credencial", () => {
    expect(
      redactSessionUrl("https://dosasystem.test/certificacion/sesion/abc?token=xyz#t"),
    ).toBe("https://dosasystem.test/certificacion/sesion/abc");
  });

  it("no revienta con una url inválida", () => {
    expect(redactSessionUrl("no es una url")).toBe("<url-invalida>");
  });
});

describe("readDosaSessionConfig", () => {
  it("por defecto queda apagado y sin clave", () => {
    const parsed = readDosaSessionConfig({} as NodeJS.ProcessEnv);

    expect(parsed.enabled).toBe(false);
    expect(parsed.secretKey).toBeNull();
    expect(parsed.baseUrl).toBe("https://dosasystem.com");
    expect(parsed.allowedReturnOrigins).toEqual([]);
  });

  it("lee la bandera, la clave y los orígenes permitidos", () => {
    const parsed = readDosaSessionConfig({
      DOSA_CERTIFICATION_SESSIONS_ENABLED: "true",
      DOSA_SECRET_KEY: SECRET,
      DOSA_SESSION_ALLOWED_RETURN_ORIGINS:
        "https://fullposcloud.fulltechrd.com/, https://fullpos.test",
    } as NodeJS.ProcessEnv);

    expect(parsed.enabled).toBe(true);
    expect(parsed.secretKey).toBe(SECRET);
    expect(parsed.allowedReturnOrigins).toEqual([
      "https://fullposcloud.fulltechrd.com",
      "https://fullpos.test",
    ]);
  });

  it("acota el timeout a un máximo razonable", () => {
    const parsed = readDosaSessionConfig({
      DOSA_SESSION_TIMEOUT_MS: "999999",
    } as NodeJS.ProcessEnv);

    expect(parsed.timeoutMs).toBe(120_000);
  });
});
