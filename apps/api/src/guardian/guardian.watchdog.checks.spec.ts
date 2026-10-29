import {
  classifyWorkerHeartbeat,
  emptyWatchdogState,
  evaluateGuardianHealth,
  planWatchdogNotifications,
  WATCHDOG_CODES,
  type WatchdogSnapshot,
} from './guardian.watchdog.checks';

function snapshot(overrides: Partial<WatchdogSnapshot> = {}): WatchdogSnapshot {
  return {
    databaseReachable: true,
    stuckMinutes: 30,
    sev1UnackMinutes: 60,
    heartbeatStaleMinutes: 10,
    alertsPendingStuck: 0,
    diagnosesPendingStuck: 0,
    incidentsUnprocessed: 0,
    alertProviderFailures: 0,
    sev1Unacknowledged: 0,
    staleWorkers: [],
    ...overrides,
  };
}

describe('guardian watchdog — evaluación', () => {
  it('no reporta hallazgos cuando todo esta sano', () => {
    expect(evaluateGuardianHealth(snapshot())).toEqual([]);
  });

  it('trata la base inaccesible como CRITICO, nunca como estado sano', () => {
    const findings = evaluateGuardianHealth(
      snapshot({ databaseReachable: false, databaseError: 'ECONNREFUSED' }),
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].code).toBe(WATCHDOG_CODES.databaseUnreachable);
    expect(findings[0].severity).toBe('CRITICAL');
    expect(findings[0].detail).toContain('ECONNREFUSED');
  });

  it('ignora el resto de contadores cuando la base no responde', () => {
    const findings = evaluateGuardianHealth(
      snapshot({ databaseReachable: false, alertsPendingStuck: 99, sev1Unacknowledged: 5 }),
    );
    expect(findings.map((finding) => finding.code)).toEqual([WATCHDOG_CODES.databaseUnreachable]);
  });

  it('detecta el worker de alertas detenido', () => {
    const findings = evaluateGuardianHealth(snapshot({ alertsPendingStuck: 3 }));
    expect(findings.map((finding) => finding.code)).toContain(WATCHDOG_CODES.alertsStuck);
    expect(findings[0].count).toBe(3);
  });

  it('detecta el worker de IA detenido', () => {
    const findings = evaluateGuardianHealth(snapshot({ diagnosesPendingStuck: 2 }));
    expect(findings.map((finding) => finding.code)).toContain(WATCHDOG_CODES.diagnosisStuck);
  });

  it('detecta la cola de incidentes acumulada', () => {
    const findings = evaluateGuardianHealth(snapshot({ incidentsUnprocessed: 7 }));
    const finding = findings.find((item) => item.code === WATCHDOG_CODES.incidentsUnprocessed);
    expect(finding?.severity).toBe('WARNING');
    expect(finding?.count).toBe(7);
  });

  it('detecta fallos persistentes de proveedor', () => {
    const findings = evaluateGuardianHealth(snapshot({ alertProviderFailures: 4 }));
    expect(findings.map((finding) => finding.code)).toContain(WATCHDOG_CODES.alertProviderFailing);
  });

  it('detecta SEV1 sin procesar', () => {
    const findings = evaluateGuardianHealth(snapshot({ sev1Unacknowledged: 1 }));
    const finding = findings.find((item) => item.code === WATCHDOG_CODES.sev1Unacknowledged);
    expect(finding?.severity).toBe('CRITICAL');
  });

  it('detecta un worker muerto aunque la cola este vacia (latido)', () => {
    const findings = evaluateGuardianHealth(
      snapshot({ staleWorkers: [{ workerName: 'alerts', ageMinutes: 42 }] }),
    );
    const finding = findings.find((item) => item.code === WATCHDOG_CODES.workerHeartbeatStale);
    expect(finding?.severity).toBe('CRITICAL');
    expect(finding?.detail).toContain('alerts');
  });

  it('acumula varios problemas en el mismo ciclo', () => {
    const findings = evaluateGuardianHealth(
      snapshot({ alertsPendingStuck: 1, sev1Unacknowledged: 2, incidentsUnprocessed: 3 }),
    );
    expect(findings).toHaveLength(3);
  });
});

describe('guardian watchdog — deduplicación y recuperación', () => {
  const stuck = { code: 'ALERTS_STUCK', severity: 'CRITICAL' as const, detail: 'x', count: 1 };
  const t0 = new Date('2026-10-26T10:00:00.000Z');

  it('avisa la primera vez que aparece un hallazgo', () => {
    const plan = planWatchdogNotifications([stuck], emptyWatchdogState, t0, { reAlertMinutes: 60 });
    expect(plan.send.map((finding) => finding.code)).toEqual(['ALERTS_STUCK']);
    expect(plan.recovered).toEqual([]);
    expect(plan.healthy).toBe(false);
    expect(plan.nextState.activeCodes).toEqual(['ALERTS_STUCK']);
  });

  it('no repite el aviso en el siguiente ciclo', () => {
    const first = planWatchdogNotifications([stuck], emptyWatchdogState, t0, { reAlertMinutes: 60 });
    const second = planWatchdogNotifications([stuck], first.nextState, new Date(t0.getTime() + 5 * 60_000), {
      reAlertMinutes: 60,
    });
    expect(second.send).toEqual([]);
  });

  it('vuelve a avisar si el hallazgo sigue abierto pasado el intervalo', () => {
    const first = planWatchdogNotifications([stuck], emptyWatchdogState, t0, { reAlertMinutes: 60 });
    const later = new Date(t0.getTime() + 61 * 60_000);
    const second = planWatchdogNotifications([stuck], first.nextState, later, { reAlertMinutes: 60 });
    expect(second.send.map((finding) => finding.code)).toEqual(['ALERTS_STUCK']);
    expect(second.nextState.lastSentAt.ALERTS_STUCK).toBe(later.toISOString());
  });

  it('avisa la recuperación cuando desaparecen los hallazgos', () => {
    const first = planWatchdogNotifications([stuck], emptyWatchdogState, t0, { reAlertMinutes: 60 });
    const healed = planWatchdogNotifications([], first.nextState, new Date(t0.getTime() + 5 * 60_000), {
      reAlertMinutes: 60,
    });
    expect(healed.recovered).toEqual(['ALERTS_STUCK']);
    expect(healed.healthy).toBe(true);
    expect(healed.nextState.activeCodes).toEqual([]);
  });

  it('avisa de nuevo si el problema reaparece tras recuperarse', () => {
    const first = planWatchdogNotifications([stuck], emptyWatchdogState, t0, { reAlertMinutes: 60 });
    const healed = planWatchdogNotifications([], first.nextState, new Date(t0.getTime() + 60_000), {
      reAlertMinutes: 60,
    });
    const again = planWatchdogNotifications([stuck], healed.nextState, new Date(t0.getTime() + 120_000), {
      reAlertMinutes: 60,
    });
    expect(again.send.map((finding) => finding.code)).toEqual(['ALERTS_STUCK']);
  });

  it('deduplica por código: dos hallazgos distintos se avisan por separado', () => {
    const other = { code: 'SEV1_UNACKNOWLEDGED', severity: 'CRITICAL' as const, detail: 'y', count: 2 };
    const first = planWatchdogNotifications([stuck], emptyWatchdogState, t0, { reAlertMinutes: 60 });
    const second = planWatchdogNotifications([stuck, other], first.nextState, t0, { reAlertMinutes: 60 });
    expect(second.send.map((finding) => finding.code)).toEqual(['SEV1_UNACKNOWLEDGED']);
    expect(second.nextState.activeCodes).toEqual(['ALERTS_STUCK', 'SEV1_UNACKNOWLEDGED']);
  });
});

describe('guardian watchdog — clasificación de latidos para el panel', () => {
  it('sin latido devuelve missing', () => {
    expect(classifyWorkerHeartbeat(null, 10)).toBe('missing');
    expect(classifyWorkerHeartbeat(undefined, 10)).toBe('missing');
  });

  it('dentro del umbral devuelve ok', () => {
    expect(classifyWorkerHeartbeat(0, 10)).toBe('ok');
    expect(classifyWorkerHeartbeat(10, 10)).toBe('ok');
  });

  it('fuera del umbral devuelve stale', () => {
    expect(classifyWorkerHeartbeat(10.01, 10)).toBe('stale');
    expect(classifyWorkerHeartbeat(45, 10)).toBe('stale');
  });

  it('un umbral inválido cae en 10 minutos y nunca marca ok por defecto', () => {
    expect(classifyWorkerHeartbeat(5, Number.NaN)).toBe('ok');
    expect(classifyWorkerHeartbeat(15, 0)).toBe('stale');
  });
});
