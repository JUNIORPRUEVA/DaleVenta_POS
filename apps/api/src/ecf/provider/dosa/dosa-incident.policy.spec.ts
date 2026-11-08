import {
  DOSA_INCIDENT_MAX_ATTEMPTS,
  DOSA_INCIDENT_STATUS,
  backoffDelayMs,
  describeIncidentKind,
  incidentKeyOf,
  isDosaIncidentResolution,
  isRetryableIncident,
  isTerminalIncidentStatus,
  severityOfIncident,
} from "./dosa-incident.policy";

describe("dosa-incident.policy — catálogo y reintentos", () => {
  it("solo la vinculación de postulación es reintentable", () => {
    expect(isRetryableIncident("POSTULATION_NOT_BOUND")).toBe(true);
    // Nada que pueda rotar material, activar o resolver identidad se reintenta.
    expect(isRetryableIncident("CREDENTIAL_CONFLICT_REVIEW")).toBe(false);
    expect(isRetryableIncident("EVENT_CREDENTIALS_NOT_STORED")).toBe(false);
    expect(isRetryableIncident("CREDENTIAL_AWAITING_CONFIRMATION")).toBe(false);
    expect(isRetryableIncident("EVENT_TYPE_UNKNOWN")).toBe(false);
  });

  it("un conflicto de credenciales es lo más severo", () => {
    expect(severityOfIncident("CREDENTIAL_CONFLICT_REVIEW")).toBe("ALTA");
    expect(severityOfIncident("EVENT_CREDENTIALS_NOT_STORED")).toBe("ALTA");
    expect(severityOfIncident("CREDENTIAL_AWAITING_CONFIRMATION")).toBe("MEDIA");
    expect(severityOfIncident("POSTULATION_NOT_BOUND")).toBe("BAJA");
  });

  it("cada tipo tiene una descripción legible y sin datos sensibles", () => {
    const description = describeIncidentKind("CREDENTIAL_CONFLICT_REVIEW");
    expect(description).toContain("revisión");
    expect(description.toLowerCase()).not.toContain("api");
  });
});

describe("dosa-incident.policy — deduplicación", () => {
  it("la misma incidencia produce siempre la misma clave", () => {
    const a = incidentKeyOf({ kind: "POSTULATION_NOT_BOUND", subjectRef: "POST-1" });
    const b = incidentKeyOf({ kind: "POSTULATION_NOT_BOUND", subjectRef: " post-1 " });
    expect(a).toBe(b);
  });

  it("sujetos distintos son incidencias distintas", () => {
    expect(incidentKeyOf({ kind: "POSTULATION_NOT_BOUND", subjectRef: "POST-1" })).not.toBe(
      incidentKeyOf({ kind: "POSTULATION_NOT_BOUND", subjectRef: "POST-2" }),
    );
  });

  it("sin sujeto, la clave es solo el tipo (una incidencia agregada)", () => {
    expect(incidentKeyOf({ kind: "EVENT_TYPE_UNKNOWN", subjectRef: null })).toBe(
      "EVENT_TYPE_UNKNOWN",
    );
  });
});

describe("dosa-incident.policy — backoff", () => {
  it("crece exponencialmente con techo", () => {
    expect(backoffDelayMs(1)).toBe(5 * 60_000);
    expect(backoffDelayMs(2)).toBe(10 * 60_000);
    expect(backoffDelayMs(3)).toBe(20 * 60_000);
    expect(backoffDelayMs(50)).toBe(6 * 60 * 60_000);
  });

  it("tolera intentos inválidos sin producir NaN", () => {
    expect(backoffDelayMs(0)).toBe(5 * 60_000);
    expect(Number.isFinite(backoffDelayMs(Number.NaN))).toBe(true);
  });

  it("el límite de intentos es finito", () => {
    expect(Number.isFinite(DOSA_INCIDENT_MAX_ATTEMPTS)).toBe(true);
    expect(DOSA_INCIDENT_MAX_ATTEMPTS).toBeGreaterThan(1);
  });
});

describe("dosa-incident.policy — estados y resoluciones", () => {
  it("solo RESOLVED y CLOSED son terminales", () => {
    expect(isTerminalIncidentStatus(DOSA_INCIDENT_STATUS.RESOLVED)).toBe(true);
    expect(isTerminalIncidentStatus(DOSA_INCIDENT_STATUS.CLOSED)).toBe(true);
    expect(isTerminalIncidentStatus(DOSA_INCIDENT_STATUS.OPEN)).toBe(false);
    expect(isTerminalIncidentStatus(DOSA_INCIDENT_STATUS.ESCALATED)).toBe(false);
  });

  it("acepta solo motivos del catálogo", () => {
    expect(isDosaIncidentResolution("FALSE_POSITIVE")).toBe(true);
    expect(isDosaIncidentResolution("porque si")).toBe(false);
    expect(isDosaIncidentResolution(undefined)).toBe(false);
  });
});
