import {
  ALANUBE_DOM_SANDBOX_HOST,
  isSandboxAccessAllowed,
  sandboxAccessRefusal,
  type SandboxAccessEnv,
} from "./alanube-sandbox-access.policy";

/**
 * Política de acceso al sandbox de Alanube.
 *
 * Fuente oficial: `https://developer.alanube.co/docs/autenticación.md`
 * (actualizado 2025-09-23) — JWT suministrado por Alanube, enviado como
 * `Authorization: Bearer <token>`; el ejemplo oficial usa
 * `https://sandbox.alanube.co/dom/v1/company`.
 *
 * Estas pruebas fijan que el transporte REAL exige una configuración completa y
 * coherente: sin token de pruebas referenciado, sin entorno sandbox o con una URL
 * de producción, NO se construye y se permanece en el simulador local.
 */
describe("Alanube sandbox access policy", () => {
  const requested: SandboxAccessEnv = {
    ALANUBE_HTTP_TRANSPORT_ENABLED: "true",
    ALANUBE_ENABLE_REAL_CALLS: "true",
    ALANUBE_ENV: "sandbox",
    ALANUBE_BASE_URL: `https://${ALANUBE_DOM_SANDBOX_HOST}/dom/v1`,
    ALANUBE_TOKEN_SECRET_REF: "secret://alanube/sandbox-token",
  };

  it("permite el transporte real solo con la configuración de sandbox completa", () => {
    expect(sandboxAccessRefusal(requested)).toBeNull();
    expect(isSandboxAccessAllowed(requested)).toBe(true);
  });

  it("no valida nada si el transporte real no se pidió", () => {
    // Sin interruptores: no hay acceso que conceder ni error que reportar.
    expect(sandboxAccessRefusal({})).toBeNull();
    expect(isSandboxAccessAllowed({})).toBe(false);
    expect(
      isSandboxAccessAllowed({ ...requested, ALANUBE_ENABLE_REAL_CALLS: "false" }),
    ).toBe(false);
    expect(
      isSandboxAccessAllowed({
        ...requested,
        ALANUBE_HTTP_TRANSPORT_ENABLED: "false",
      }),
    ).toBe(false);
  });

  it("exige un token de pruebas referenciado", () => {
    const { ALANUBE_TOKEN_SECRET_REF: _omit, ...withoutToken } = requested;
    expect(sandboxAccessRefusal(withoutToken)).toBe(
      "ALANUBE_SANDBOX_REFUSED_TOKEN_REFERENCE_REQUIRED",
    );
    expect(
      sandboxAccessRefusal({ ...requested, ALANUBE_TOKEN_SECRET_REF: "   " }),
    ).toBe("ALANUBE_SANDBOX_REFUSED_TOKEN_REFERENCE_REQUIRED");
    // Un token en claro no es una referencia válida.
    expect(
      sandboxAccessRefusal({
        ...requested,
        ALANUBE_TOKEN_SECRET_REF: "eyJhbGciOiJIUzI1NiJ9.token",
      }),
    ).toBe("ALANUBE_SANDBOX_REFUSED_TOKEN_REFERENCE_INVALID");
    expect(
      sandboxAccessRefusal({ ...requested, ALANUBE_TOKEN_SECRET_REF: "env://ok" }),
    ).toBeNull();
  });

  it("exige entorno sandbox", () => {
    expect(
      sandboxAccessRefusal({ ...requested, ALANUBE_ENV: "production" }),
    ).toBe("ALANUBE_SANDBOX_REFUSED_ENVIRONMENT");
    expect(sandboxAccessRefusal({ ...requested, ALANUBE_ENV: "" })).toBe(
      "ALANUBE_SANDBOX_REFUSED_ENVIRONMENT",
    );
  });

  it("rechaza la URL de producción y la infraestructura remota conocida", () => {
    for (const url of [
      "https://api.alanube.co/dom/v1",
      "https://puerto.easypanel.host/dom/v1",
      "https://daleventapos-backend.gcdndd.easypanel.host",
      "https://x.hostinger.com",
    ]) {
      expect(
        sandboxAccessRefusal({ ...requested, ALANUBE_BASE_URL: url }),
      ).toBe("ALANUBE_SANDBOX_REFUSED_PRODUCTION_URL");
    }
  });

  it("exige HTTPS y el host oficial de sandbox", () => {
    expect(
      sandboxAccessRefusal({
        ...requested,
        ALANUBE_BASE_URL: `http://${ALANUBE_DOM_SANDBOX_HOST}/dom/v1`,
      }),
    ).toBe("ALANUBE_SANDBOX_REFUSED_INSECURE_TRANSPORT");
    expect(
      sandboxAccessRefusal({
        ...requested,
        ALANUBE_BASE_URL: "https://otro-proveedor.example.com/dom/v1",
      }),
    ).toBe("ALANUBE_SANDBOX_REFUSED_NOT_SANDBOX_HOST");
    expect(
      sandboxAccessRefusal({ ...requested, ALANUBE_BASE_URL: "no-es-una-url" }),
    ).toBe("ALANUBE_SANDBOX_REFUSED_BASE_URL_INVALID");
    expect(
      sandboxAccessRefusal({ ...requested, ALANUBE_BASE_URL: "" }),
    ).toBe("ALANUBE_SANDBOX_REFUSED_BASE_URL_REQUIRED");
  });

  it("falla cerrado: nunca permite el real con configuración incompleta", () => {
    const broken: SandboxAccessEnv[] = [
      { ...requested, ALANUBE_TOKEN_SECRET_REF: undefined },
      { ...requested, ALANUBE_ENV: "production" },
      { ...requested, ALANUBE_BASE_URL: "https://api.alanube.co/dom/v1" },
      { ALANUBE_HTTP_TRANSPORT_ENABLED: "true", ALANUBE_ENABLE_REAL_CALLS: "true" },
    ];
    for (const env of broken) {
      expect(isSandboxAccessAllowed(env)).toBe(false);
    }
  });
});
