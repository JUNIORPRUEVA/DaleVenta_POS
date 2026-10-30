import type { AlanubeSafeRequest } from "./alanube-safe-http.types";
import { classifyAlanubeTransportResult } from "./alanube-error-classifier";
import { decideAlanubeRetry } from "./alanube-retry.policy";
import {
  ALANUBE_SIMULATION_SCENARIOS,
  AlanubeScenarioTransport,
  simulateAlanubeResponse,
  type AlanubeSimulationScenario,
} from "./alanube-scenario.transport";

/**
 * Simulador de Alanube: reproduce los 16 escenarios de operación y fija los
 * invariantes que NO pueden romperse, sin red y sin credenciales. Nada aquí
 * declara aceptación de la DGII: el simulador no tiene esa potestad.
 */
function request(requestId = "req-1"): AlanubeSafeRequest {
  return {
    method: "POST",
    url: "https://sandbox.example.test/dom/v1/invoice",
    headers: { authorization: "Bearer SECRET-MUST-NOT-LEAK", "content-type": "application/json" },
    body: { encf: "E310000000001" },
    timeoutMs: 5000,
    requestId,
  };
}

function scenarioTransport(...scenarios: AlanubeSimulationScenario[]) {
  return new AlanubeScenarioTransport(scenarios);
}

describe("simulador Alanube — escenarios", () => {
  it("reproduce exactamente los 16 escenarios pedidos", () => {
    expect(ALANUBE_SIMULATION_SCENARIOS).toHaveLength(16);
    expect(new Set(ALANUBE_SIMULATION_SCENARIOS).size).toBe(16);
  });

  it.each([...ALANUBE_SIMULATION_SCENARIOS])(
    "el escenario %s produce una respuesta coherente y reproducible",
    (scenario) => {
      const first = simulateAlanubeResponse(scenario, request());
      const second = simulateAlanubeResponse(scenario, request());
      // Determinista: el mismo escenario con la misma petición da lo mismo.
      expect(second).toEqual(first);
    },
  );

  it("marca toda respuesta simulada como NO oficial", () => {
    for (const scenario of ALANUBE_SIMULATION_SCENARIOS) {
      const result = simulateAlanubeResponse(scenario, request());
      if (!result.ok) continue;
      const body = result.response.body;
      if (typeof body !== "object" || body === null) continue;
      expect((body as { mark?: string }).mark).toBe("SIMULATED_NOT_OFFICIAL");
    }
  });
});

describe("simulador Alanube — invariantes fiscales", () => {
  it("NINGÚN 200 del proveedor se convierte en aceptación fiscal", () => {
    for (const scenario of ALANUBE_SIMULATION_SCENARIOS) {
      const result = simulateAlanubeResponse(scenario, request());
      if (!result.ok) continue;
      // 429 y 500 tienen su propia clase (límite / resultado desconocido) y se
      // comprueban aparte: este invariante es sobre una llamada HTTP correcta.
      if (result.response.statusCode !== 200) continue;
      const classified = classifyAlanubeTransportResult(result, "EMISSION");
      // Un 200 del proveedor es siempre "resultado por interpretar": nunca una
      // aceptación. Y exige revisión humana.
      expect(classified.class).toBe("UNKNOWN_OUTCOME");
      expect(classified.requiresHumanReview).toBe(true);
    }
  });

  it("la clasificación nunca devuelve una clase de aceptación", () => {
    const acceptanceLike = ["ACCEPTED", "DGII_ACCEPTED", "PROVIDER_ACCEPTED", "OK", "SUCCESS"];
    for (const scenario of ALANUBE_SIMULATION_SCENARIOS) {
      const result = simulateAlanubeResponse(scenario, request());
      const classified = classifyAlanubeTransportResult(result, "EMISSION");
      expect(acceptanceLike).not.toContain(classified.class);
    }
  });

  it("un cuerpo ilegible falla cerrado: 200 con HTML no se interpreta como válido", () => {
    const result = simulateAlanubeResponse("MALFORMED_RESPONSE", request());
    expect(result.ok).toBe(true);
    const classified = classifyAlanubeTransportResult(result, "EMISSION");
    expect(classified.class).toBe("UNKNOWN_OUTCOME");
    expect(classified.requiresHumanReview).toBe(true);
  });

  it("un estado desconocido del proveedor no se interpreta como aceptado", () => {
    const result = simulateAlanubeResponse("UNKNOWN_RESULT", request());
    const classified = classifyAlanubeTransportResult(result, "EMISSION");
    expect(classified.class).toBe("UNKNOWN_OUTCOME");
    expect(classified.requiresHumanReview).toBe(true);
  });

  it("la emisión NUNCA se reintenta, en ninguno de los 16 escenarios", () => {
    for (const scenario of ALANUBE_SIMULATION_SCENARIOS) {
      const result = simulateAlanubeResponse(scenario, request());
      const classified = classifyAlanubeTransportResult(result, "EMISSION");
      for (const attempt of [0, 1, 2]) {
        const decision = decideAlanubeRetry({
          operation: "EMISSION",
          errorClass: classified.class,
          attempt,
          idempotent: true,
        });
        expect(decision.retry).toBe(false);
      }
    }
  });

  it("un timeout o una caída de red SÍ se reintentan al leer, con espera creciente", () => {
    for (const scenario of ["TIMEOUT", "CONNECTION_LOST"] as const) {
      const result = simulateAlanubeResponse(scenario, request());
      const classified = classifyAlanubeTransportResult(result, "READ");
      expect(classified.retryable).toBe(true);

      const first = decideAlanubeRetry({ operation: "READ", errorClass: classified.class, attempt: 0, idempotent: true });
      const second = decideAlanubeRetry({ operation: "READ", errorClass: classified.class, attempt: 1, idempotent: true });
      expect(first.retry).toBe(true);
      expect(second.retry).toBe(true);
      if (first.retry && second.retry) {
        expect(second.delayMs).toBeGreaterThan(first.delayMs);
      }
    }
  });

  it("429 se reintenta al leer y el 500 queda como resultado desconocido", () => {
    const limited = classifyAlanubeTransportResult(simulateAlanubeResponse("RATE_LIMITED", request()), "READ");
    expect(limited.class).toBe("RATE_LIMIT");
    expect(limited.retryable).toBe(true);
    expect(limited.requiresHumanReview).toBe(false);

    const server = classifyAlanubeTransportResult(simulateAlanubeResponse("SERVER_ERROR", request()), "EMISSION");
    expect(server.class).toBe("UNKNOWN_OUTCOME");
    expect(server.requiresHumanReview).toBe(true);
  });

  it("se agota al tercer intento: no hay reintento infinito", () => {
    const classified = classifyAlanubeTransportResult(simulateAlanubeResponse("TIMEOUT", request()), "READ");
    const decision = decideAlanubeRetry({ operation: "READ", errorClass: classified.class, attempt: 3, idempotent: true });
    expect(decision).toEqual({ retry: false, reason: "MAX_ATTEMPTS" });
  });

  it("una reclamación de emisión sin idempotencia verificada no se reintenta", () => {
    const decision = decideAlanubeRetry({
      operation: "EMISSION",
      errorClass: "TIMEOUT",
      attempt: 0,
      idempotent: false,
    });
    expect(decision).toEqual({ retry: false, reason: "NON_IDEMPOTENT_EMISSION" });
  });
});

describe("simulador Alanube — identidad y trazabilidad", () => {
  it("un reintento idempotente conserva el MISMO identificador remoto", async () => {
    const transport = scenarioTransport("TIMEOUT", "IDEMPOTENT_RETRY");
    const first = await transport.execute(request("req-42"));
    const second = await transport.execute(request("req-42"));

    expect(first.ok).toBe(false);
    expect(second.ok).toBe(true);
    if (!second.ok) return;
    const body = second.response.body as { id: string };
    // Sin identidad estable no se puede reconciliar un resultado desconocido.
    expect(body.id).toBe("sim-req-42");
  });

  it("un reinicio del proceso recupera la misma identidad para la misma operación", async () => {
    const before = await scenarioTransport("PROCESS_RESTART").execute(request("req-7"));
    const after = await scenarioTransport("PENDING_RECOVERY").execute(request("req-7"));
    if (!before.ok || !after.ok) throw new Error("SIMULATION_EXPECTED_OK");
    expect((after.response.body as { id: string }).id).toBe(
      (before.response.body as { id: string }).id,
    );
  });

  it("una respuesta duplicada y otra fuera de orden quedan registradas", async () => {
    const transport = scenarioTransport("DUPLICATE_RESPONSE", "OUT_OF_ORDER");
    await transport.execute(request("req-1"));
    await transport.execute(request("req-2"));
    // Trazabilidad: cada llamada queda registrada, en orden.
    expect(transport.calls.map((call) => call.requestId)).toEqual(["req-1", "req-2"]);
  });

  it("el guion se repite al agotarse, para modelar reintentos contra el mismo proveedor", async () => {
    const transport = scenarioTransport("TIMEOUT");
    await transport.execute(request("req-1"));
    const third = await transport.execute(request("req-3"));
    expect(third.ok).toBe(false);
    expect(transport.calls).toHaveLength(2);
  });

  it("nunca filtra credenciales: cabecera y cuerpo quedan redactados", async () => {
    const transport = scenarioTransport("PROVIDER_ACCEPTED");
    await transport.execute(request("req-9"));
    const recorded = transport.calls[0];
    expect(recorded.headers.authorization).toBe("[REDACTED]");
    expect(recorded.body).toBe("[REDACTED]");
    expect(JSON.stringify(recorded)).not.toContain("SECRET-MUST-NOT-LEAK");
  });

  it("un guion vacío se rechaza en vez de simular en silencio", () => {
    expect(() => new AlanubeScenarioTransport([])).toThrow("ALANUBE_SIMULATION_SCRIPT_REQUIRED");
  });
});
