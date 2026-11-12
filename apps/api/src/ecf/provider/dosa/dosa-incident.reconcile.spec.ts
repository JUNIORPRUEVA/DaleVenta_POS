import { DOSA_INCIDENT_STATUS } from "./dosa-incident.policy";
import {
  outcomeOfAttempt,
  planIncidentActions,
  type DosaIncidentCandidate,
  type DosaIncidentOpenRow,
} from "./dosa-incident.reconcile";

const NOW = new Date("2026-11-07T12:00:00.000Z");

function candidate(
  overrides: Partial<DosaIncidentCandidate> = {},
): DosaIncidentCandidate {
  return {
    companyId: "company-a",
    rnc: "133080206",
    kind: "EVENT_CREDENTIALS_NOT_STORED",
    subjectType: "WEBHOOK_EVENT",
    subjectRef: "post-1",
    ...overrides,
  };
}

function row(overrides: Partial<DosaIncidentOpenRow> = {}): DosaIncidentOpenRow {
  return {
    id: "inc-1",
    incidentKey: "EVENT_CREDENTIALS_NOT_STORED:post-1",
    kind: "EVENT_CREDENTIALS_NOT_STORED",
    status: DOSA_INCIDENT_STATUS.OPEN,
    attempts: 0,
    nextAttemptAt: null,
    ...overrides,
  };
}

describe("planIncidentActions — creación y deduplicación", () => {
  it("una condición nueva crea una incidencia con su severidad", () => {
    const actions = planIncidentActions({
      candidates: [candidate()],
      openRows: [],
      now: NOW,
    });
    expect(actions).toHaveLength(1);
    expect(actions[0]).toMatchObject({
      type: "CREATE",
      incidentKey: "EVENT_CREDENTIALS_NOT_STORED:post-1",
      severity: "ALTA",
    });
  });

  it("una condición ya registrada NO crea otra: se toca", () => {
    const actions = planIncidentActions({
      candidates: [candidate()],
      openRows: [row()],
      now: NOW,
    });
    expect(actions).toHaveLength(1);
    expect(actions[0]).toMatchObject({ type: "TOUCH", id: "inc-1" });
  });

  it("el mismo candidato repetido en un barrido se procesa una vez", () => {
    const actions = planIncidentActions({
      candidates: [candidate(), candidate()],
      openRows: [],
      now: NOW,
    });
    expect(actions).toHaveLength(1);
  });

  it("una incidencia que ya no aparece se resuelve sola", () => {
    const actions = planIncidentActions({
      candidates: [],
      openRows: [row()],
      now: NOW,
    });
    expect(actions).toEqual([{ type: "RESOLVE", id: "inc-1" }]);
  });

  it("una incidencia escalada NO se cierra sola: espera a una persona", () => {
    const actions = planIncidentActions({
      candidates: [],
      openRows: [row({ status: DOSA_INCIDENT_STATUS.ESCALATED })],
      now: NOW,
    });
    expect(actions).toEqual([]);
  });
});

describe("planIncidentActions — reintento seguro", () => {
  it("una incidencia reintentable y vencida se reintenta", () => {
    const actions = planIncidentActions({
      candidates: [candidate({ kind: "POSTULATION_NOT_BOUND" })],
      openRows: [
        row({
          incidentKey: "POSTULATION_NOT_BOUND:post-1",
          kind: "POSTULATION_NOT_BOUND",
          attempts: 1,
          nextAttemptAt: new Date(NOW.getTime() - 1000),
        }),
      ],
      now: NOW,
    });
    expect(actions[0]).toMatchObject({ type: "RETRY" });
  });

  it("si todavía no toca, solo se toca la incidencia", () => {
    const actions = planIncidentActions({
      candidates: [candidate({ kind: "POSTULATION_NOT_BOUND" })],
      openRows: [
        row({
          incidentKey: "POSTULATION_NOT_BOUND:post-1",
          kind: "POSTULATION_NOT_BOUND",
          attempts: 1,
          nextAttemptAt: new Date(NOW.getTime() + 60_000),
        }),
      ],
      now: NOW,
    });
    expect(actions[0]).toMatchObject({ type: "TOUCH" });
  });

  it("un conflicto de credenciales NUNCA se reintenta solo", () => {
    const actions = planIncidentActions({
      candidates: [candidate({ kind: "CREDENTIAL_CONFLICT_REVIEW" })],
      openRows: [
        row({
          incidentKey: "CREDENTIAL_CONFLICT_REVIEW:post-1",
          kind: "CREDENTIAL_CONFLICT_REVIEW",
          attempts: 0,
          nextAttemptAt: null,
        }),
      ],
      now: NOW,
    });
    expect(actions[0]).toMatchObject({ type: "TOUCH" });
  });

  it("agotados los intentos se escala en vez de reintentar", () => {
    const actions = planIncidentActions({
      candidates: [candidate({ kind: "POSTULATION_NOT_BOUND" })],
      openRows: [
        row({
          incidentKey: "POSTULATION_NOT_BOUND:post-1",
          kind: "POSTULATION_NOT_BOUND",
          attempts: 99,
          nextAttemptAt: null,
        }),
      ],
      now: NOW,
    });
    expect(actions[0]).toMatchObject({ type: "ESCALATE" });
  });
});

describe("outcomeOfAttempt", () => {
  it("un éxito resuelve la incidencia", () => {
    const outcome = outcomeOfAttempt({ attempts: 2, now: NOW, succeeded: true });
    expect(outcome).toMatchObject({
      attempts: 3,
      status: DOSA_INCIDENT_STATUS.RESOLVED,
      nextAttemptAt: null,
      lastErrorCode: null,
    });
  });

  it("un fallo programa el siguiente intento con backoff", () => {
    const outcome = outcomeOfAttempt({ attempts: 0, now: NOW, succeeded: false });
    expect(outcome.status).toBe(DOSA_INCIDENT_STATUS.OPEN);
    expect(outcome.nextAttemptAt?.getTime()).toBe(NOW.getTime() + 5 * 60_000);
    expect(outcome.lastErrorCode).toBe("RETRY_FAILED");
  });

  it("al llegar al límite escala y deja de agendar", () => {
    const outcome = outcomeOfAttempt({
      attempts: 99,
      now: NOW,
      succeeded: false,
    });
    expect(outcome.status).toBe(DOSA_INCIDENT_STATUS.ESCALATED);
    expect(outcome.nextAttemptAt).toBeNull();
    expect(outcome.lastErrorCode).toBe("RETRY_EXHAUSTED");
  });
});
