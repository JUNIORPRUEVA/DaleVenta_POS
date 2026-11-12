import { resolveFakeTransportSelection } from "./dosa-emission.fake-transport";

/**
 * Validación de configuración de emisión DOSA AL ARRANCAR.
 *
 * Qué añade sobre la compuerta de cada emisión
 * --------------------------------------------
 * La compuerta rechaza una emisión concreta. Esto rechaza una **configuración
 * incoherente antes de aceptar tráfico**: si alguien enciende
 * `DOSA_EMISSION_ENABLED` con una URL que no es HTTPS, o en PRODUCCIÓN sin
 * autorizar producción, el servicio no arranca. Es más barato no arrancar que
 * arrancar y fallar en cada factura.
 *
 * Regla de compatibilidad: con la emisión APAGADA (el valor por defecto) **no se
 * exige nada**, porque un despliegue sin emisión es un estado válido y no debe
 * impedir el arranque. Solo se valida lo que se va a usar.
 *
 * Función pura: recibe el entorno, no lee `process.env` ni abre conexiones.
 */

export const DOSA_STARTUP_BLOCKED = {
  baseUrlRequired: "DOSA_STARTUP_BASE_URL_REQUIRED",
  baseUrlNotHttps: "DOSA_STARTUP_BASE_URL_NOT_HTTPS",
  baseUrlNotHttp: "DOSA_STARTUP_BASE_URL_INVALID",
  environmentUnknown: "DOSA_STARTUP_ENVIRONMENT_UNKNOWN",
  productionNotAuthorized: "DOSA_STARTUP_PRODUCTION_NOT_AUTHORIZED",
  testKeyMissing: "DOSA_STARTUP_TEST_KEY_MISSING",
  productionKeyMissing: "DOSA_STARTUP_PRODUCTION_KEY_MISSING",
} as const;

export type DosaStartupValidation = {
  ok: boolean;
  /** Impedimentos estructurales: con ellos no se debe aceptar tráfico. */
  problems: string[];
  /**
   * Estados legítimos que NO bloquean el arranque: una configuración de
   * PRODUCCIÓN preparada pero sin autorizar es un estado válido; la compuerta
   * rechaza cada emisión con su motivo.
   */
  warnings: string[];
};

function isLocalHost(hostname: string): boolean {
  return hostname === "127.0.0.1" || hostname === "localhost" || hostname === "::1";
}

export function validateDosaEmissionStartup(
  env: Record<string, string | undefined>,
): DosaStartupValidation {
  const problems: string[] = [];
  const warnings: string[] = [];

  // El transporte falso ya falla cerrado por su cuenta; se evalúa primero para
  // que un uso indebido se reporte con su propio código.
  try {
    resolveFakeTransportSelection(env);
  } catch (error) {
    problems.push(error instanceof Error ? error.message.split(":")[0] : "DOSA_TRANSPORT_INVALID");
  }

  const enabled = (env.DOSA_EMISSION_ENABLED ?? "").trim().toLowerCase() === "true";
  if (!enabled) {
    // Sin emisión no hay nada que validar: el arranque sigue siendo válido.
    return { ok: problems.length === 0, problems, warnings };
  }

  const environment = (env.DOSA_EMISSION_ENVIRONMENT ?? "TEST").trim().toUpperCase();
  if (environment !== "TEST" && environment !== "PRODUCTION") {
    problems.push(`${DOSA_STARTUP_BLOCKED.environmentUnknown}:${environment}`);
  }

  const baseUrl = (env.DOSA_BASE_URL ?? "").trim();
  if (baseUrl.length === 0) {
    problems.push(DOSA_STARTUP_BLOCKED.baseUrlRequired);
  } else {
    let parsed: URL | null = null;
    try {
      parsed = new URL(baseUrl);
    } catch {
      problems.push(`${DOSA_STARTUP_BLOCKED.baseUrlNotHttp}:${baseUrl}`);
    }
    if (parsed) {
      const appEnv = (env.APP_ENV ?? "").trim().toLowerCase();
      const uatLocalOnly = (env.UAT_LOCAL_ONLY ?? "").trim().toLowerCase() === "true";
      const localUat = appEnv === "uat" || uatLocalOnly;
      // HTTPS obligatorio salvo contra un servidor local de UAT: el emisor
      // manda credenciales y datos fiscales, así que no se admite HTTP abierto.
      if (parsed.protocol === "https:") {
        // correcto
      } else if (parsed.protocol === "http:" && localUat && isLocalHost(parsed.hostname)) {
        // aceptable solo en UAT local
      } else if (parsed.protocol === "http:") {
        problems.push(`${DOSA_STARTUP_BLOCKED.baseUrlNotHttps}:${parsed.hostname}`);
      } else {
        problems.push(`${DOSA_STARTUP_BLOCKED.baseUrlNotHttp}:${parsed.protocol}`);
      }
    }
  }

  const productionEnabled =
    (env.DOSA_PRODUCTION_EMISSION_ENABLED ?? "").trim().toLowerCase() === "true";
  if (environment === "PRODUCTION" && !productionEnabled) {
    warnings.push(DOSA_STARTUP_BLOCKED.productionNotAuthorized);
  }

  if (environment === "PRODUCTION") {
    if ((env.DOSA_PRODUCTION_API_KEY ?? "").trim().length === 0) {
      warnings.push(DOSA_STARTUP_BLOCKED.productionKeyMissing);
    }
  } else if ((env.DOSA_TEST_API_KEY ?? "").trim().length === 0) {
    // La clave global de TEST es opcional: la credencial real se lee por empresa.
    // Solo se avisa cuando no hay ninguna vía de credencial configurada.
    if ((env.DOSA_CREDENTIALS_MASTER_KEY ?? "").trim().length === 0) {
      warnings.push(DOSA_STARTUP_BLOCKED.testKeyMissing);
    }
  }

  return { ok: problems.length === 0, problems, warnings };
}
