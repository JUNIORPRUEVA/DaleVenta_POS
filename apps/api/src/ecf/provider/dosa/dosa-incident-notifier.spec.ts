import {
  LoggingDosaIncidentNotifier,
  isNotifiableSeverity,
} from "./dosa-incident-notifier";

/**
 * Aviso de incidencias: qué interrumpe a una persona y qué no.
 *
 * El contrato tiene tres garantías que se comprueban aquí:
 *  1. Solo las severidades altas generan aviso (las bajas se acumulan en la
 *     bandeja; avisar de todas es la forma más rápida de que nadie lea nada).
 *  2. El aviso no incluye datos del cliente ni secretos.
 *  3. El canal por defecto no hace ninguna llamada externa.
 */
describe("isNotifiableSeverity", () => {
  it("avisa de las severidades altas", () => {
    for (const severity of ["HIGH", "CRITICAL", "high", " AlTA ", "crítica"]) {
      expect(isNotifiableSeverity(severity)).toBe(true);
    }
  });

  it("no avisa de las severidades bajas o medias", () => {
    for (const severity of ["LOW", "MEDIUM", "INFO", "", "  "]) {
      expect(isNotifiableSeverity(severity)).toBe(false);
    }
  });
});

describe("LoggingDosaIncidentNotifier", () => {
  let warnSpy: jest.SpyInstance;

  beforeEach(() => {
    warnSpy = jest
      .spyOn(require("@nestjs/common").Logger.prototype, "warn")
      .mockImplementation(() => undefined);
  });

  afterEach(() => {
    warnSpy.mockRestore();
  });

  it("registra la incidencia con severidad alta", async () => {
    const notifier = new LoggingDosaIncidentNotifier();

    await notifier.notify({
      companyId: "11111111-1111-4111-8111-111111111111",
      incidentId: "22222222-2222-4222-8222-222222222222",
      kind: "CREDENTIAL_CONFLICT_REVIEW",
      severity: "HIGH",
      occurrences: 1,
    });

    expect(warnSpy).toHaveBeenCalledTimes(1);
    const payload = JSON.parse(String(warnSpy.mock.calls[0][0]));
    expect(payload).toMatchObject({
      event: "ECF_DOSA_INCIDENT",
      kind: "CREDENTIAL_CONFLICT_REVIEW",
      severity: "HIGH",
      occurrences: 1,
      inbox: "/ecf/platform/dosa/incidents",
    });
  });

  it("no registra nada cuando la severidad no lo merece", async () => {
    const notifier = new LoggingDosaIncidentNotifier();

    await notifier.notify({
      companyId: "11111111-1111-4111-8111-111111111111",
      incidentId: "22222222-2222-4222-8222-222222222222",
      kind: "EVENT_TYPE_UNKNOWN",
      severity: "LOW",
      occurrences: 7,
    });

    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("el aviso no contiene credenciales ni RNC", async () => {
    const notifier = new LoggingDosaIncidentNotifier();

    await notifier.notify({
      companyId: "11111111-1111-4111-8111-111111111111",
      incidentId: "22222222-2222-4222-8222-222222222222",
      kind: "EVENT_CREDENTIALS_NOT_STORED",
      severity: "CRITICAL",
      occurrences: 1,
    });

    const serialized = String(warnSpy.mock.calls[0][0]);
    expect(serialized).not.toMatch(/api[_-]?key/i);
    expect(serialized).not.toMatch(/secret/i);
    expect(serialized).not.toMatch(/:rnc|"rnc"/i);
    expect(serialized).not.toMatch(/sk_/);
  });
});
