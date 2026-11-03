import {
  ECF_SIMULATION_BADGE,
  evaluateSimulationMode,
  sanitizeVideoUrl,
} from "./ecf-preparation-metadata.policy";

const ready = {
  orchestrator: "enabled",
  alanubeEnv: "sandbox",
  activationTransport: "simulated",
  allowedCompanyId: null as string | null,
};

describe("modo de prueba — condiciones", () => {
  it("solo se habilita con orquestador, sandbox y transporte simulado", () => {
    const state = evaluateSimulationMode(ready, "c1");
    expect(state.available).toBe(true);
    expect(state.badge).toBe(ECF_SIMULATION_BADGE);
    expect(state.badge).toContain("NO SE ENVIARÁ NADA A DGII");
    expect(state.reason).toBeNull();
  });

  it("el feature flag por sí solo no habilita nada", () => {
    expect(
      evaluateSimulationMode({ ...ready, activationTransport: "real" }, "c1").available,
    ).toBe(false);
    expect(
      evaluateSimulationMode({ ...ready, alanubeEnv: "production" }, "c1").available,
    ).toBe(false);
    expect(
      evaluateSimulationMode({ ...ready, orchestrator: "disabled" }, "c1").available,
    ).toBe(false);
  });

  it("respeta la empresa de prueba autorizada", () => {
    const withCompany = { ...ready, allowedCompanyId: "empresa-ok" };
    expect(evaluateSimulationMode(withCompany, "empresa-ok").available).toBe(true);
    const denied = evaluateSimulationMode(withCompany, "otra-empresa");
    expect(denied.available).toBe(false);
    expect(denied.reason).toContain("no está autorizada");
  });

  it("explica el motivo cuando no está disponible", () => {
    const state = evaluateSimulationMode(
      { ...ready, orchestrator: "disabled" },
      "c1",
    );
    expect(state.reason).toBeTruthy();
  });
});

describe("URL del tutorial", () => {
  it("acepta solo https sin credenciales", () => {
    expect(sanitizeVideoUrl("https://cdn.fullpos.test/tutorial.mp4")).toBe(
      "https://cdn.fullpos.test/tutorial.mp4",
    );
    expect(sanitizeVideoUrl("http://inseguro.test/v.mp4")).toBeNull();
    expect(sanitizeVideoUrl("javascript:alert(1)")).toBeNull();
    expect(sanitizeVideoUrl("https://user:pass@cdn.test/v.mp4")).toBeNull();
    expect(sanitizeVideoUrl("   ")).toBeNull();
    expect(sanitizeVideoUrl(null)).toBeNull();
  });
});
