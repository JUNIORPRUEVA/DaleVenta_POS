import type {
  AlanubeHttpTransport,
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "./alanube-safe-http.types";

/**
 * SIMULADOR LOCAL DE ALANUBE — artefacto de PRUEBA, no un contrato.
 *
 * Reproduce los escenarios que la operación real puede encontrarse (aceptación,
 * rechazo, timeout, 429, 500, respuesta duplicada, fuera de orden, reinicio…)
 * sin red, sin credenciales y sin efectos fiscales.
 *
 * Límites deliberados:
 *  - La forma del cuerpo simulado es NUESTRA, no la del proveedor. No pretende
 *    ser el contrato oficial ni sustituye a `alanube-dom-schemas.generated.ts`.
 *  - Nunca declara aceptación de la DGII: eso lo decide la evidencia fiscal
 *    correlacionada, no un 200 del proveedor.
 *  - No se conecta a producción ni habilita el despacho real: es un transporte
 *    más, y el proveedor de transporte solo lo elige cuando las llamadas reales
 *    están deshabilitadas.
 */

export type AlanubeSimulationScenario =
  | "RECEIVED"
  | "PROVIDER_ACCEPTED"
  | "PROVIDER_REJECTED"
  | "DGII_ACCEPTED_SIMULATED"
  | "DGII_REJECTED_SIMULATED"
  | "TIMEOUT"
  | "RATE_LIMITED"
  | "SERVER_ERROR"
  | "DUPLICATE_RESPONSE"
  | "OUT_OF_ORDER"
  | "CONNECTION_LOST"
  | "IDEMPOTENT_RETRY"
  | "MALFORMED_RESPONSE"
  | "UNKNOWN_RESULT"
  | "PROCESS_RESTART"
  | "PENDING_RECOVERY";

/** Todos los escenarios que el simulador sabe reproducir. */
export const ALANUBE_SIMULATION_SCENARIOS: readonly AlanubeSimulationScenario[] = [
  "RECEIVED",
  "PROVIDER_ACCEPTED",
  "PROVIDER_REJECTED",
  "DGII_ACCEPTED_SIMULATED",
  "DGII_REJECTED_SIMULATED",
  "TIMEOUT",
  "RATE_LIMITED",
  "SERVER_ERROR",
  "DUPLICATE_RESPONSE",
  "OUT_OF_ORDER",
  "CONNECTION_LOST",
  "IDEMPOTENT_RETRY",
  "MALFORMED_RESPONSE",
  "UNKNOWN_RESULT",
  "PROCESS_RESTART",
  "PENDING_RECOVERY",
];

const SIMULATION_MARK = "SIMULATED_NOT_OFFICIAL";

/**
 * Respuesta simulada para un escenario. `remoteId` se calcula de forma estable a
 * partir del `requestId` para que un reintento idempotente devuelva EL MISMO
 * identificador remoto, que es justo lo que hay que poder demostrar.
 */
export function simulateAlanubeResponse(
  scenario: AlanubeSimulationScenario,
  request: AlanubeSafeRequest,
): AlanubeTransportResult {
  const remoteId = `sim-${request.requestId}`;
  const ok = (statusCode: number, body: unknown): AlanubeTransportResult => ({
    ok: true,
    response: {
      statusCode,
      headers: { "content-type": "application/json" },
      body,
      requestId: request.requestId,
    },
  });
  const failed = (
    errorCode:
      | "TIMEOUT"
      | "NETWORK_ERROR"
      | "INVALID_RESPONSE"
      | "PROVIDER_REJECTED"
      | "REDIRECT_BLOCKED"
      | "PRODUCTION_BLOCKED"
      | "CONFIGURATION_ERROR",
    safeMessage: string,
  ): AlanubeTransportResult => ({
    ok: false,
    errorCode,
    safeMessage,
    requestId: request.requestId,
  });

  switch (scenario) {
    case "RECEIVED":
      return ok(200, { id: remoteId, documentStatus: "RECEIVED", mark: SIMULATION_MARK });
    case "PROVIDER_ACCEPTED":
      return ok(200, { id: remoteId, documentStatus: "PROVIDER_ACCEPTED", mark: SIMULATION_MARK });
    case "PROVIDER_REJECTED":
      return ok(200, { id: remoteId, documentStatus: "PROVIDER_REJECTED", mark: SIMULATION_MARK });
    case "DGII_ACCEPTED_SIMULATED":
      return ok(200, { id: remoteId, documentStatus: "DGII_ACCEPTED", mark: SIMULATION_MARK });
    case "DGII_REJECTED_SIMULATED":
      return ok(200, { id: remoteId, documentStatus: "DGII_REJECTED", mark: SIMULATION_MARK });
    case "TIMEOUT":
      return failed("TIMEOUT", "El proveedor no respondió a tiempo.");
    case "RATE_LIMITED":
      return ok(429, { id: null, documentStatus: null, mark: SIMULATION_MARK });
    case "SERVER_ERROR":
      return ok(500, { id: null, documentStatus: null, mark: SIMULATION_MARK });
    case "DUPLICATE_RESPONSE":
      return ok(200, { id: remoteId, documentStatus: "PROVIDER_ACCEPTED", mark: SIMULATION_MARK });
    case "OUT_OF_ORDER":
      return ok(200, { id: remoteId, documentStatus: "PROVIDER_ACCEPTED", mark: SIMULATION_MARK });
    case "CONNECTION_LOST":
      return failed("NETWORK_ERROR", "Se perdió la conexión con el proveedor.");
    case "IDEMPOTENT_RETRY":
      return ok(200, { id: remoteId, documentStatus: "PROVIDER_ACCEPTED", mark: SIMULATION_MARK });
    case "MALFORMED_RESPONSE":
      // 200 con un cuerpo que no es el contrato: debe fallar cerrado.
      return ok(200, "<html>gateway error</html>");
    case "UNKNOWN_RESULT":
      return ok(200, { id: remoteId, documentStatus: "SOMETHING_ELSE", mark: SIMULATION_MARK });
    case "PROCESS_RESTART":
      return ok(200, { id: remoteId, documentStatus: "RECEIVED", mark: SIMULATION_MARK });
    case "PENDING_RECOVERY":
      return ok(200, { id: remoteId, documentStatus: "RECEIVED", mark: SIMULATION_MARK });
    default: {
      const exhaustive: never = scenario;
      return failed("CONFIGURATION_ERROR", `Escenario no soportado: ${String(exhaustive)}`);
    }
  }
}

/**
 * Transporte simulado por GUION: devuelve la respuesta del escenario indicado en
 * cada llamada y registra lo que se le pidió, con las credenciales redactadas.
 *
 * `repeatLast` mantiene la última respuesta del guion cuando se agota, que es lo
 * que permite modelar un reintento contra el mismo proveedor.
 */
export class AlanubeScenarioTransport implements AlanubeHttpTransport {
  readonly calls: AlanubeSafeRequest[] = [];

  constructor(
    private readonly scenarios: readonly AlanubeSimulationScenario[],
    private readonly options: { repeatLast?: boolean } = { repeatLast: true },
  ) {
    if (scenarios.length === 0) {
      throw new Error("ALANUBE_SIMULATION_SCRIPT_REQUIRED");
    }
  }

  async execute(request: AlanubeSafeRequest): Promise<AlanubeTransportResult> {
    const index = Math.min(this.calls.length, this.scenarios.length - 1);
    const scenario = this.scenarios[index];
    this.calls.push({
      ...request,
      headers: redactHeaders(request.headers),
      body: request.body === undefined ? undefined : "[REDACTED]",
    });
    return simulateAlanubeResponse(scenario, request);
  }
}

function redactHeaders(headers: Record<string, string>) {
  const copy = { ...headers };
  for (const key of Object.keys(copy)) {
    if (key.toLowerCase() === "authorization") {
      copy[key] = "[REDACTED]";
    }
  }
  return copy;
}
