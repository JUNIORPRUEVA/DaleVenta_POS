import {
  ALERT_DIAGNOSIS_FALLBACK_TEXT,
  diagnosisDeadline,
  resolveAlertReadiness,
} from './guardian.alert.readiness';

/**
 * Regla de readiness de alertas (Fase 4).
 *
 * Lo que se protege:
 * - SEV1 nunca espera a la IA (un crítico no puede quedarse sin aviso).
 * - SEV2/SEV3 esperan al diagnóstico hasta el plazo.
 * - Al vencer el plazo se envía con texto de respaldo.
 */
describe('readiness de alertas según diagnóstico', () => {
  const receivedAt = new Date('2026-10-28T10:00:00.000Z');

  const at = (secondsAfter: number) => new Date(receivedAt.getTime() + secondsAfter * 1000);

  it('SEV1 se envía de inmediato aunque no haya diagnóstico', () => {
    const readiness = resolveAlertReadiness({
      severity: 'SEV1',
      receivedAt,
      diagnosisStatus: null,
      now: at(0),
      waitSeconds: 90,
    });
    expect(readiness.ready).toBe(true);
    expect(readiness.reason).toBe('SEV1_IMMEDIATE');
    expect(readiness.deadlineAt).toBeNull();
  });

  it('SEV2/SEV3 esperan mientras el diagnóstico está pendiente o corriendo', () => {
    for (const severity of ['SEV2', 'SEV3']) {
      for (const status of ['PENDING', 'RUNNING', null] as const) {
        const readiness = resolveAlertReadiness({
          severity,
          receivedAt,
          diagnosisStatus: status,
          now: at(30),
          waitSeconds: 90,
        });
        expect(readiness.ready).toBe(false);
        expect(readiness.reason).toBe('AWAITING_DIAGNOSIS');
        expect(readiness.deadlineAt?.toISOString()).toBe('2026-10-28T10:01:30.000Z');
      }
    }
  });

  it('se envía en cuanto el diagnóstico está DONE (antes del plazo)', () => {
    const readiness = resolveAlertReadiness({
      severity: 'SEV2',
      receivedAt,
      diagnosisStatus: 'DONE',
      now: at(5),
      waitSeconds: 90,
    });
    expect(readiness.ready).toBe(true);
    expect(readiness.reason).toBe('DIAGNOSIS_DONE');
  });

  it('al vencer el plazo se envía aunque el diagnóstico haya fallado', () => {
    for (const status of ['FAILED', 'RUNNING', 'PENDING', null] as const) {
      const readiness = resolveAlertReadiness({
        severity: 'SEV2',
        receivedAt,
        diagnosisStatus: status,
        now: at(90),
        waitSeconds: 90,
      });
      expect(readiness.ready).toBe(true);
      expect(readiness.reason).toBe('DEADLINE_REACHED');
    }
  });

  it('con espera 0 se mantiene el comportamiento anterior (envío inmediato)', () => {
    const readiness = resolveAlertReadiness({
      severity: 'SEV2',
      receivedAt,
      diagnosisStatus: null,
      now: at(0),
      waitSeconds: 0,
    });
    expect(readiness.ready).toBe(true);
    expect(readiness.reason).toBe('WAIT_DISABLED');
    expect(readiness.deadlineAt).toBeNull();
  });

  it('el plazo se calcula desde la recepción del incidente y nunca es negativo', () => {
    expect(diagnosisDeadline({ receivedAt, waitSeconds: 90 })?.toISOString()).toBe(
      '2026-10-28T10:01:30.000Z',
    );
    expect(diagnosisDeadline({ receivedAt, waitSeconds: 0 })).toBeNull();
    expect(diagnosisDeadline({ receivedAt, waitSeconds: -10 })).toBeNull();
  });

  it('el texto de respaldo es el mismo que usa la plantilla aprobada', () => {
    expect(ALERT_DIAGNOSIS_FALLBACK_TEXT).toBe('Información pendiente de confirmar.');
  });
});
