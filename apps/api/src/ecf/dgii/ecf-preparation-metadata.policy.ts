/**
 * Metadatos NO sensibles de la preparación e-CF.
 *
 * Sirve a la pantalla para dos cosas concretas: conocer la URL del tutorial
 * (configurable sin publicar la app) y saber si el modo de PRUEBA está
 * disponible. Nunca devuelve credenciales, URLs del proveedor ni secretos.
 */

export const ECF_SIMULATION_BADGE = "MODO DE PRUEBA — NO SE ENVIARÁ NADA A DGII";

export type EcfSimulationEnv = {
  /** Interruptor del orquestador. */
  orchestrator: string | null | undefined;
  alanubeEnv: string | null | undefined;
  activationTransport: string | null | undefined;
  /** Empresa de prueba autorizada; si está definida, limita el modo. */
  allowedCompanyId: string | null | undefined;
};

export type EcfSimulationState = {
  available: boolean;
  badge: string;
  /** Motivo por el que NO está disponible, o `null`. */
  reason: string | null;
};

/**
 * Decide si el modo de prueba puede usarse para una empresa.
 *
 * Falla cerrado: cada condición debe cumplirse de forma explícita. Que el
 * feature flag esté encendido NO basta, y este modo nunca habilita operaciones
 * oficiales: solo el recorrido simulado.
 */
export function evaluateSimulationMode(
  env: EcfSimulationEnv,
  companyId: string,
): EcfSimulationState {
  const orchestrator = (env.orchestrator ?? "").trim().toLowerCase();
  const alanubeEnv = (env.alanubeEnv ?? "sandbox").trim().toLowerCase();
  const transport = (env.activationTransport ?? "simulated").trim().toLowerCase();

  const deny = (reason: string): EcfSimulationState => ({
    available: false,
    badge: ECF_SIMULATION_BADGE,
    reason,
  });

  if (orchestrator !== "enabled") {
    return deny(
      "El motor de certificación no está habilitado en este entorno.",
    );
  }
  if (alanubeEnv !== "sandbox") {
    return deny("El entorno del proveedor no es de pruebas.");
  }
  if (transport !== "simulated") {
    return deny("El transporte de activación no es simulado.");
  }
  const allowed = (env.allowedCompanyId ?? "").trim();
  if (allowed.length > 0 && allowed !== companyId) {
    return deny("Esta empresa no está autorizada para el escenario de prueba.");
  }
  return { available: true, badge: ECF_SIMULATION_BADGE, reason: null };
}

/**
 * URL del tutorial, validada.
 *
 * Solo se acepta `https` absoluta: una URL `javascript:` o con credenciales
 * embebidas se descarta y la pantalla mantiene el marcador de posición.
 */
export function sanitizeVideoUrl(raw: string | null | undefined): string | null {
  const value = (raw ?? "").trim();
  if (value.length === 0) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return null;
    if (url.username || url.password) return null;
    return url.toString();
  } catch {
    return null;
  }
}
