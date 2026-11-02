import {
  DOSA_LAB_APP_ENVS,
  assertDosaSignatureLabSafety,
  isLocalLabEnvironment,
  isLoopbackDatabaseUrl,
  readDosaSignatureConfig,
  requestsUnverifiedStrategy,
  type DosaSafetyEnv,
} from "./dosa-webhook-signature.policy";

/**
 * La estrategia `UNVERIFIED_PLAINTEXT_SECRET` no puede activarse fuera de un
 * laboratorio local, **ni por error de configuración**.
 *
 * Estas pruebas son negativas a propósito: cada entorno prohibido debe degradar
 * a `BLOCKED` y, en el arranque, impedir que la aplicación levante.
 */

const LOOPBACK_DB =
  "postgresql://postgres:clave@127.0.0.1:56700/dosa_validation?schema=public";

function labEnv(overrides: Partial<DosaSafetyEnv> = {}): DosaSafetyEnv {
  return {
    DOSA_WEBHOOK_SIGNATURE_STRATEGY: "UNVERIFIED_PLAINTEXT_SECRET",
    DOSA_WEBHOOK_SECRET: "a".repeat(64),
    NODE_ENV: "development",
    APP_ENV: "local",
    DATABASE_URL: LOOPBACK_DB,
    ...overrides,
  };
}

describe("isLoopbackDatabaseUrl", () => {
  it("acepta loopback y rechaza todo lo demás", () => {
    expect(isLoopbackDatabaseUrl(LOOPBACK_DB)).toBe(true);
    expect(isLoopbackDatabaseUrl("postgresql://u:p@localhost:5432/d")).toBe(true);
    expect(
      isLoopbackDatabaseUrl("postgresql://u:p@db.produccion.example.com:5432/d"),
    ).toBe(false);
    expect(isLoopbackDatabaseUrl("postgresql://u:p@10.0.0.5:5432/d")).toBe(false);
    expect(isLoopbackDatabaseUrl("")).toBe(false);
    expect(isLoopbackDatabaseUrl(undefined)).toBe(false);
    expect(isLoopbackDatabaseUrl("no-es-una-url")).toBe(false);
  });
});

describe("isLocalLabEnvironment", () => {
  it("exige NODE_ENV, APP_ENV y base de loopback a la vez", () => {
    expect(isLocalLabEnvironment(labEnv())).toBe(true);
    expect(DOSA_LAB_APP_ENVS.length).toBeGreaterThan(0);

    // NODE_ENV producción gana a todo lo demás.
    expect(isLocalLabEnvironment(labEnv({ NODE_ENV: "production" }))).toBe(false);
    expect(
      isLocalLabEnvironment(labEnv({ NODE_ENV: "PRODUCTION", APP_ENV: "test" })),
    ).toBe(false);

    // APP_ENV no de laboratorio.
    expect(isLocalLabEnvironment(labEnv({ APP_ENV: "staging" }))).toBe(false);
    expect(isLocalLabEnvironment(labEnv({ APP_ENV: "uat" }))).toBe(false);
    expect(isLocalLabEnvironment(labEnv({ APP_ENV: "production" }))).toBe(false);
    expect(isLocalLabEnvironment(labEnv({ APP_ENV: "" }))).toBe(false);
    expect(isLocalLabEnvironment(labEnv({ APP_ENV: undefined }))).toBe(false);

    // Base remota: aunque el resto diga laboratorio, no lo es.
    expect(
      isLocalLabEnvironment(
        labEnv({
          DATABASE_URL: "postgresql://u:p@db.remota.example.com:5432/d",
        }),
      ),
    ).toBe(false);
    expect(isLocalLabEnvironment(labEnv({ DATABASE_URL: undefined }))).toBe(false);
  });
});

describe("readDosaSignatureConfig — degradación por entorno", () => {
  it("por defecto (sin variable) queda BLOCKED", () => {
    // Los parámetros de tiempo se rellenan siempre con su valor seguro por
    // defecto, aunque la estrategia esté bloqueada.
    expect(readDosaSignatureConfig({})).toEqual({
      strategy: "BLOCKED",
      secret: null,
      timestampUnit: "seconds",
      toleranceSeconds: 300,
    });
  });

  it("un valor basura nunca activa nada", () => {
    for (const value of ["1", "true", "HMAC", "UNVERIFIED", " "]) {
      expect(
        readDosaSignatureConfig(labEnv({ DOSA_WEBHOOK_SIGNATURE_STRATEGY: value })),
      ).toMatchObject({ strategy: "BLOCKED" });
    }
  });

  it("en laboratorio local sí se aplica la estrategia no verificada", () => {
    const config = readDosaSignatureConfig(labEnv());
    expect(config.strategy).toBe("UNVERIFIED_PLAINTEXT_SECRET");
    expect(config.downgradedFrom).toBeUndefined();
  });

  it("en NODE_ENV=production se degrada y se explica por qué", () => {
    const config = readDosaSignatureConfig(labEnv({ NODE_ENV: "production" }));
    expect(config.strategy).toBe("BLOCKED");
    expect(config.downgradedFrom).toBe("UNVERIFIED_PLAINTEXT_SECRET");
    expect(config.downgradeReason).toBe("NOT_A_LOCAL_LAB_ENVIRONMENT");
  });

  it("en un APP_ENV no autorizado se degrada", () => {
    for (const appEnv of ["staging", "uat", "production", "qa-cloud"]) {
      expect(readDosaSignatureConfig(labEnv({ APP_ENV: appEnv }))).toMatchObject({
        strategy: "BLOCKED",
        downgradeReason: "NOT_A_LOCAL_LAB_ENVIRONMENT",
      });
    }
  });

  it("con base remota se degrada aunque APP_ENV diga local", () => {
    expect(
      readDosaSignatureConfig(
        labEnv({ DATABASE_URL: "postgresql://u:p@db.remota.example.com:5432/d" }),
      ),
    ).toMatchObject({ strategy: "BLOCKED" });
  });

  it("el secreto se conserva como valor pero nunca se aplica si está bloqueado", () => {
    const config = readDosaSignatureConfig(labEnv({ NODE_ENV: "production" }));
    expect(config.strategy).toBe("BLOCKED");
    expect(config.secret).toBe("a".repeat(64));
  });
});

describe("assertDosaSignatureLabSafety — barrera de arranque", () => {
  it("no opina si la estrategia no es la no verificada", () => {
    expect(() => assertDosaSignatureLabSafety({})).not.toThrow();
    expect(() =>
      assertDosaSignatureLabSafety({ DOSA_WEBHOOK_SIGNATURE_STRATEGY: "BLOCKED" }),
    ).not.toThrow();
  });

  it("deja arrancar en laboratorio local", () => {
    expect(requestsUnverifiedStrategy(labEnv())).toBe(true);
    expect(() => assertDosaSignatureLabSafety(labEnv())).not.toThrow();
  });

  it("IMPIDE arrancar en producción", () => {
    expect(() =>
      assertDosaSignatureLabSafety(labEnv({ NODE_ENV: "production" })),
    ).toThrow(/refused startup/);
  });

  it("IMPIDE arrancar con base remota", () => {
    expect(() =>
      assertDosaSignatureLabSafety(
        labEnv({ DATABASE_URL: "postgresql://u:p@db.remota.example.com:5432/d" }),
      ),
    ).toThrow(/refused startup/);
  });

  it("IMPIDE arrancar con APP_ENV no autorizado", () => {
    for (const appEnv of ["staging", "uat", "production"]) {
      expect(() =>
        assertDosaSignatureLabSafety(labEnv({ APP_ENV: appEnv })),
      ).toThrow(/refused startup/);
    }
  });

  it("IMPIDE arrancar si falta el contexto de entorno por completo", () => {
    expect(() =>
      assertDosaSignatureLabSafety({
        DOSA_WEBHOOK_SIGNATURE_STRATEGY: "UNVERIFIED_PLAINTEXT_SECRET",
        DOSA_WEBHOOK_SECRET: "a".repeat(64),
      }),
    ).toThrow(/refused startup/);
  });
});
