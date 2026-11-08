import { DOSA_STARTUP_BLOCKED, validateDosaEmissionStartup } from "./dosa-emission.startup";

/**
 * Validación de configuración al arrancar.
 *
 * Regla de compatibilidad que se comprueba aquí: con la emisión APAGADA (valor
 * por defecto) no se exige nada. Un despliegue sin emisión es un estado válido y
 * no debe impedir el arranque.
 */
describe("validateDosaEmissionStartup", () => {
  it("sin emisión habilitada no exige nada", () => {
    const result = validateDosaEmissionStartup({});
    expect(result.ok).toBe(true);
    expect(result.problems).toHaveLength(0);
  });

  it("con emisión habilitada exige DOSA_BASE_URL", () => {
    const result = validateDosaEmissionStartup({
      DOSA_EMISSION_ENABLED: "true",
      DOSA_EMISSION_ENVIRONMENT: "TEST",
      DOSA_TEST_API_KEY: "sk_test_X",
    });
    expect(result.ok).toBe(false);
    expect(result.problems).toContain(DOSA_STARTUP_BLOCKED.baseUrlRequired);
  });

  it("rechaza una URL que no es HTTPS fuera de UAT local", () => {
    const result = validateDosaEmissionStartup({
      DOSA_EMISSION_ENABLED: "true",
      DOSA_EMISSION_ENVIRONMENT: "TEST",
      DOSA_TEST_API_KEY: "sk_test_X",
      DOSA_BASE_URL: "http://dosasystem.com",
    });
    expect(result.ok).toBe(false);
    expect(result.problems.join(",")).toContain(DOSA_STARTUP_BLOCKED.baseUrlNotHttps);
  });

  it("permite HTTP contra un servidor local declarado como UAT", () => {
    const result = validateDosaEmissionStartup({
      DOSA_EMISSION_ENABLED: "true",
      DOSA_EMISSION_ENVIRONMENT: "TEST",
      DOSA_TEST_API_KEY: "sk_test_X",
      DOSA_BASE_URL: "http://127.0.0.1:1234",
      APP_ENV: "uat",
    });
    expect(result.ok).toBe(true);
  });

  it("rechaza un ambiente desconocido", () => {
    const result = validateDosaEmissionStartup({
      DOSA_EMISSION_ENABLED: "true",
      DOSA_EMISSION_ENVIRONMENT: "STAGING",
      DOSA_TEST_API_KEY: "sk_test_X",
      DOSA_BASE_URL: "https://dosasystem.com",
    });
    expect(result.ok).toBe(false);
    expect(result.problems.join(",")).toContain(DOSA_STARTUP_BLOCKED.environmentUnknown);
  });

  it("PRODUCCIÓN configurada pero no autorizada es una ADVERTENCIA, no un bloqueo", () => {
    const result = validateDosaEmissionStartup({
      DOSA_EMISSION_ENABLED: "true",
      DOSA_EMISSION_ENVIRONMENT: "PRODUCTION",
      DOSA_PRODUCTION_EMISSION_ENABLED: "false",
      DOSA_PRODUCTION_API_KEY: "sk_prod_X",
      DOSA_BASE_URL: "https://dosasystem.com",
    });
    // La compuerta rechazará cada emisión con su motivo; el arranque es válido.
    expect(result.ok).toBe(true);
    expect(result.warnings).toContain(DOSA_STARTUP_BLOCKED.productionNotAuthorized);
  });

  it("un transporte FAKE fuera de UAT local es un impedimento de arranque", () => {
    const result = validateDosaEmissionStartup({
      DOSA_EMISSION_ENABLED: "true",
      DOSA_EMISSION_ENVIRONMENT: "TEST",
      DOSA_TEST_API_KEY: "sk_test_X",
      DOSA_BASE_URL: "https://dosasystem.com",
      DOSA_EMISSION_TRANSPORT: "FAKE",
    });
    expect(result.ok).toBe(false);
    expect(result.problems.join(",")).toContain("ECF_DOSA_FAKE_TRANSPORT_FORBIDDEN");
  });

  it("una URL sin scheme se rechaza", () => {
    const result = validateDosaEmissionStartup({
      DOSA_EMISSION_ENABLED: "true",
      DOSA_EMISSION_ENVIRONMENT: "TEST",
      DOSA_TEST_API_KEY: "sk_test_X",
      DOSA_BASE_URL: "dosasystem.com",
    });
    expect(result.ok).toBe(false);
    expect(result.problems.join(",")).toContain(DOSA_STARTUP_BLOCKED.baseUrlNotHttp);
  });
});
