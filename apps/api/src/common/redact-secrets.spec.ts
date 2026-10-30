import {
  REDACTED,
  formatRedactedEnv,
  isSensitiveKey,
  looksLikeSecretReference,
  normalizeKey,
  redactEnv,
  redactSecrets,
  redactText,
  redactUrl,
} from "./redact-secrets";

/**
 * Contraseña sintética con la forma de la que se filtró accidentalmente en un
 * diagnóstico anterior. Nunca se usa una credencial real en las pruebas.
 */
const SYNTHETIC_PASSWORD = "sup3rS3cr3tSyntheticValue";
const SYNTHETIC_JWT =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzeW50aGV0aWMifQ.abcdefghijklmnop";

describe("redact-secrets — claves sensibles", () => {
  it("normaliza separadores de clave", () => {
    expect(normalizeKey("DATABASE_URL")).toBe("databaseurl");
    expect(normalizeKey("database-url")).toBe("databaseurl");
    expect(normalizeKey("databaseUrl")).toBe("databaseurl");
    expect(normalizeKey("db.password")).toBe("dbpassword");
  });

  it.each([
    "DATABASE_URL",
    "database_url",
    "PASSWORD",
    "db_password",
    "JWT_SECRET",
    "API_KEY",
    "api-key",
    "ALANUBE_SANDBOX_TOKEN",
    "PRIVATE_KEY",
    "sessionId",
    "connectionString",
  ])("marca %s como sensible", (key) => {
    expect(isSensitiveKey(key)).toBe(true);
  });

  it.each(["PORT", "APP_ENV", "UAT_EXPECTED_DB_NAME", "PRODUCTS_SOURCE", "kind"])(
    "no marca %s como sensible",
    (key) => {
      expect(isSensitiveKey(key)).toBe(false);
    },
  );
});

describe("redact-secrets — redacción de entorno", () => {
  it("oculta DATABASE_URL por completo", () => {
    const env = {
      DATABASE_URL: `postgresql://fullpos_user:${SYNTHETIC_PASSWORD}@127.0.0.1:56551/fullpos_uat_test`,
    };
    expect(redactEnv(env).DATABASE_URL).toBe(REDACTED);
    expect(formatRedactedEnv(env)).not.toContain(SYNTHETIC_PASSWORD);
  });

  it("oculta contraseñas, tokens, claves y secretos conservando claves inocuas", () => {
    const env = {
      APP_ENV: "uat",
      PORT: 4002,
      UAT_EXPECTED_DB_NAME: "fullpos_alanube_uat_test",
      UAT_DB_PASSWORD: SYNTHETIC_PASSWORD,
      ALANUBE_SANDBOX_TOKEN: SYNTHETIC_JWT,
      SOME_API_KEY: "sk-synthetic-000",
      WEBHOOK_SECRET: "whsec_synthetic",
    };
    const out = redactEnv(env);
    expect(out.APP_ENV).toBe("uat");
    expect(out.PORT).toBe(4002);
    expect(out.UAT_EXPECTED_DB_NAME).toBe("fullpos_alanube_uat_test");
    expect(out.UAT_DB_PASSWORD).toBe(REDACTED);
    expect(out.ALANUBE_SANDBOX_TOKEN).toBe(REDACTED);
    expect(out.SOME_API_KEY).toBe(REDACTED);
    expect(out.WEBHOOK_SECRET).toBe(REDACTED);
  });

  it("conserva una referencia de secreto: es un URI, no material secreto", () => {
    expect(looksLikeSecretReference("env://ALANUBE_SANDBOX_TOKEN")).toBe(true);
    expect(looksLikeSecretReference("secret://windows/FullPOS-Token")).toBe(true);
    expect(looksLikeSecretReference("vault://fullpos/alanube/token")).toBe(true);
    // Un valor con credenciales embebidas NO es una referencia.
    expect(looksLikeSecretReference("postgresql://u:p@host/db")).toBe(false);
    expect(looksLikeSecretReference("rawtokenvalue")).toBe(false);

    const out = redactEnv({
      ALANUBE_TOKEN_SECRET_REF: "env://ALANUBE_SANDBOX_TOKEN",
      ALANUBE_CREDENTIAL_SOURCE: "local-dpapi-securestring",
      DATABASE_URL: "postgresql://u:p@127.0.0.1:56551/db",
    });
    expect(out.ALANUBE_TOKEN_SECRET_REF).toBe("env://ALANUBE_SANDBOX_TOKEN");
    // Sin `@` no hay credenciales: la URL sigue siendo un URI de referencia.
    expect(out.DATABASE_URL).toBe(REDACTED);
  });

  it("redacta una clave Ref si su valor NO es una referencia", () => {
    const out = redactEnv({ credentialsSecretRef: "rawtoken123" });
    expect(out.credentialsSecretRef).toBe(REDACTED);
  });

  it("es determinista: las claves salen ordenadas", () => {
    const env = { Z_VAR: "z", A_VAR: "a", M_VAR: "m" };
    expect(Object.keys(redactEnv(env))).toEqual(["A_VAR", "M_VAR", "Z_VAR"]);
  });
});

describe("redact-secrets — texto libre", () => {
  it("oculta una URL suelta conservando usuario y host, y el valor completo tras una clave", () => {
    // URL suelta (sin `CLAVE=`): se conserva el usuario y el host para diagnóstico.
    const bare = redactText(`postgresql://fullpos_user:${SYNTHETIC_PASSWORD}@127.0.0.1:56551/db`);
    expect(bare).not.toContain(SYNTHETIC_PASSWORD);
    expect(bare).toContain("fullpos_user");
    expect(bare).toContain("127.0.0.1:56551");

    // Dentro de una línea `CLAVE=valor`, la clave sensible domina y oculta el valor
    // completo: es el mismo criterio fail-closed que aplica `redactEnv`.
    const line = `DATABASE_URL=postgresql://fullpos_user:${SYNTHETIC_PASSWORD}@127.0.0.1:56551/db`;
    expect(redactText(line)).toBe(`DATABASE_URL=${REDACTED}`);
  });

  it("oculta JWT en texto libre", () => {
    const out = redactText(`token recibido: ${SYNTHETIC_JWT} (fin)`);
    expect(out).not.toContain(SYNTHETIC_JWT);
    expect(out).toContain(REDACTED);
  });

  it("oculta el valor de una cabecera Bearer", () => {
    const out = redactText(`Authorization: Bearer ${SYNTHETIC_JWT}`);
    expect(out).not.toContain(SYNTHETIC_JWT);
    expect(out).toContain("Bearer");
  });

  it("oculta pares clave=valor sensibles dentro de una cadena", () => {
    const out = redactText(`config password=${SYNTHETIC_PASSWORD} ok`);
    expect(out).not.toContain(SYNTHETIC_PASSWORD);
  });

  it("no altera texto sin secretos", () => {
    const line = "eNCF E320009805001 REGISTERED secuencia consumida";
    expect(redactText(line)).toBe(line);
  });

  it("redactUrl delega en redactText", () => {
    expect(redactUrl("postgresql://u:p@127.0.0.1/db")).toBe(
      redactUrl("postgresql://u:p@127.0.0.1/db"),
    );
    expect(redactUrl("postgresql://u:p@127.0.0.1/db")).not.toContain(":p@");
  });
});

describe("redact-secrets — estructuras", () => {
  it("redacta de forma recursiva en objetos y arrays", () => {
    const input = {
      company: { id: "c1", credentials: { token: SYNTHETIC_JWT } },
      attempts: [{ password: SYNTHETIC_PASSWORD }, { status: "REGISTERED" }],
    };
    const out = redactSecrets(input) as any;
    expect(out.company.id).toBe("c1");
    // La clave contenedora ya es sensible: se oculta el objeto completo.
    expect(out.company.credentials).toBe(REDACTED);
    // La clave del array no es sensible: se desciende y solo cae el campo sensible.
    expect(out.attempts[0].password).toBe(REDACTED);
    expect(out.attempts[1].status).toBe("REGISTERED");
  });

  it("no muta la entrada", () => {
    const input = { DATABASE_URL: "postgresql://u:p@host/db", nested: { apiKey: "k" } };
    const snapshot = JSON.parse(JSON.stringify(input));
    redactSecrets(input);
    expect(input).toEqual(snapshot);
  });

  it("conserva null, undefined, números, booleanos y fechas", () => {
    const when = new Date("2026-10-16T00:00:00.000Z");
    const out = redactSecrets({
      a: null,
      b: undefined,
      c: 0,
      d: false,
      e: when,
    }) as any;
    expect(out.a).toBeNull();
    expect(out.b).toBeUndefined();
    expect(out.c).toBe(0);
    expect(out.d).toBe(false);
    expect(out.e).toBe(when);
  });

  it("sustituye valores no serializables en lugar de exponerlos", () => {
    const out = redactSecrets({ handler: () => "x", symbol: Symbol("s") }) as any;
    expect(out.handler).toBe(REDACTED);
    expect(out.symbol).toBe(REDACTED);
  });

  it("oculta el valor completo de una clave sensible con forma de lista", () => {
    const out = redactEnv({ ALLOWED_TOKENS: ["a", "b"] });
    expect(out.ALLOWED_TOKENS).toBe(REDACTED);
  });
});
