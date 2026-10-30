/**
 * Política de acceso al SANDBOX de Alanube.
 *
 * Fuente oficial citada: `https://developer.alanube.co/docs/autenticación.md`
 * (actualizado 2025-09-23) — «se debe contar con un JWT que será suministrado por
 * Alanube» y se envía con `Authorization: Bearer <token>`. El ejemplo oficial usa
 * `https://sandbox.alanube.co/dom/v1/company`, que confirma el host de sandbox.
 *
 * Regla: activar el transporte REAL debe ser una decisión explícita y **completa**.
 * Si falta el token de pruebas, si el entorno no es sandbox o si la URL apunta a
 * producción, la fábrica NO construye el transporte real y se queda en el
 * simulador local (fallo cerrado, sin romper el arranque de la aplicación).
 *
 * Durante esta fase el transporte real permanece desactivado y no se ha hecho
 * ninguna llamada a Alanube.
 */

export type SandboxAccessEnv = {
  ALANUBE_ENABLE_REAL_CALLS?: string | undefined;
  ALANUBE_HTTP_TRANSPORT_ENABLED?: string | undefined;
  ALANUBE_ENV?: string | undefined;
  ALANUBE_BASE_URL?: string | undefined;
  ALANUBE_TOKEN_SECRET_REF?: string | undefined;
};

/** Host oficial del sandbox (confirmado en el ejemplo de la documentación). */
export const ALANUBE_DOM_SANDBOX_HOST = "sandbox.alanube.co";

/** Host de producción del DOM, según el contrato local curado del proyecto. */
export const ALANUBE_DOM_PRODUCTION_HOST = "api.alanube.co";

/** Marcadores que jamás deben aparecer en la URL de una integración de pruebas. */
const FORBIDDEN_URL_MARKERS = [
  ALANUBE_DOM_PRODUCTION_HOST,
  "easypanel",
  "gcdndd",
  "hostinger",
  "31.97.99.70",
];

function read(env: SandboxAccessEnv, key: keyof SandboxAccessEnv): string {
  return (env[key] ?? "").trim();
}

/** ¿El transporte real está pedido explícitamente? */
export function isRealTransportRequested(env: SandboxAccessEnv): boolean {
  return (
    read(env, "ALANUBE_HTTP_TRANSPORT_ENABLED").toLowerCase() === "true" &&
    read(env, "ALANUBE_ENABLE_REAL_CALLS").toLowerCase() === "true"
  );
}

/**
 * Motivo por el que NO se puede construir el transporte real.
 * `null` significa que la configuración de sandbox está completa y es coherente.
 */
export function sandboxAccessRefusal(env: SandboxAccessEnv): string | null {
  if (!isRealTransportRequested(env)) {
    // No se pidió el transporte real: nada que validar.
    return null;
  }

  const environment = read(env, "ALANUBE_ENV").toLowerCase();
  if (environment !== "sandbox") {
    return "ALANUBE_SANDBOX_REFUSED_ENVIRONMENT";
  }

  const rawUrl = read(env, "ALANUBE_BASE_URL");
  if (rawUrl === "") {
    return "ALANUBE_SANDBOX_REFUSED_BASE_URL_REQUIRED";
  }

  const lowered = rawUrl.toLowerCase();
  for (const marker of FORBIDDEN_URL_MARKERS) {
    if (lowered.includes(marker)) {
      return "ALANUBE_SANDBOX_REFUSED_PRODUCTION_URL";
    }
  }

  let host = "";
  let secure = false;
  try {
    const url = new URL(rawUrl);
    host = url.hostname.trim().toLowerCase();
    secure = url.protocol === "https:";
  } catch {
    return "ALANUBE_SANDBOX_REFUSED_BASE_URL_INVALID";
  }

  if (!secure) {
    return "ALANUBE_SANDBOX_REFUSED_INSECURE_TRANSPORT";
  }
  if (host !== ALANUBE_DOM_SANDBOX_HOST) {
    return "ALANUBE_SANDBOX_REFUSED_NOT_SANDBOX_HOST";
  }

  // El token es suministrado por Alanube y se referencia, nunca se incrusta.
  // Sin referencia válida no hay credencial de pruebas: sin llamada.
  const reference = read(env, "ALANUBE_TOKEN_SECRET_REF");
  if (reference === "") {
    return "ALANUBE_SANDBOX_REFUSED_TOKEN_REFERENCE_REQUIRED";
  }
  if (!/^(env|secret|vault|uat):\/\/[A-Za-z0-9._:/@-]+$/.test(reference)) {
    return "ALANUBE_SANDBOX_REFUSED_TOKEN_REFERENCE_INVALID";
  }

  return null;
}

/** `true` si la configuración permite construir el transporte real de sandbox. */
export function isSandboxAccessAllowed(env: SandboxAccessEnv): boolean {
  return isRealTransportRequested(env) && sandboxAccessRefusal(env) === null;
}
