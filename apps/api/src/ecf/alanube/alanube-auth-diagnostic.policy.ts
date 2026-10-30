export const ALANUBE_AUTH_DIAGNOSTIC_ENDPOINT =
  "https://sandbox.alanube.co/dom/v1/company";

export type AlanubeAuthDiagnosticPolicyResult =
  | { ok: true }
  | { ok: false; code: string; safeMessage: string };

export function assertAlanubeAuthDiagnosticPolicy(input: {
  method: string;
  url: string;
  environment: string;
  realCallsEnabled: boolean;
  emissionEnabled: boolean;
  authTestsEnabled: boolean;
}): AlanubeAuthDiagnosticPolicyResult {
  if (input.environment !== "sandbox") {
    return { ok: false, code: "PRODUCTION_BLOCKED", safeMessage: "Solo Sandbox está permitido." };
  }
  if (input.emissionEnabled) {
    return { ok: false, code: "EMISSION_BLOCKED", safeMessage: "La emisión debe permanecer bloqueada." };
  }
  if (input.realCallsEnabled) {
    return { ok: false, code: "GLOBAL_REAL_CALLS_BLOCKED", safeMessage: "No se permite habilitar llamadas reales globales." };
  }
  if (input.authTestsEnabled) {
    return { ok: false, code: "GLOBAL_AUTH_TESTS_BLOCKED", safeMessage: "La prueba debe ser efímera, no global." };
  }
  if (input.method !== "GET") {
    return { ok: false, code: "METHOD_NOT_ALLOWED", safeMessage: "Solo GET está permitido." };
  }
  try {
    const url = new URL(input.url);
    const expected = new URL(ALANUBE_AUTH_DIAGNOSTIC_ENDPOINT);
    if (
      url.protocol !== "https:" ||
      url.hostname !== expected.hostname ||
      url.pathname !== expected.pathname ||
      url.search ||
      url.username ||
      url.password
    ) {
      return { ok: false, code: "ENDPOINT_NOT_ALLOWED", safeMessage: "Endpoint de diagnóstico no permitido." };
    }
  } catch {
    return { ok: false, code: "INVALID_URL", safeMessage: "URL inválida." };
  }
  return { ok: true };
}
