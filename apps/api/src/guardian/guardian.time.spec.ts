/**
 * Fase 14 — Conversión UTC → hora dominicana en las alertas de Guardian.
 *
 * Regresión del defecto: `toLocaleString('es-DO', …)` sin `timeZone` formateaba
 * en la zona del contenedor (UTC), mostrando +4 h en cada alerta de WhatsApp.
 */
import { GuardianSeverity } from '@prisma/client';
import {
  GUARDIAN_TIME_ZONE,
  formatGuardianDateTime,
  formatGuardianTime,
} from './guardian.time';
import {
  buildGuardianAlertMessage,
  buildGuardianAlertTemplateParams,
} from './guardian.alert.service';

describe('Guardian — hora dominicana', () => {
  it('usa la zona America/Santo_Domingo', () => {
    expect(GUARDIAN_TIME_ZONE).toBe('America/Santo_Domingo');
  });

  it('convierte UTC-04:00 en horario de mañana', () => {
    // 12:00 UTC = 08:00 en Santo Domingo
    expect(formatGuardianDateTime(new Date('2026-10-30T12:00:00.000Z'))).toBe(
      '30/10/2026, 08:00 a. m.',
    );
  });

  it('formatea el mediodía y el inicio de la tarde', () => {
    // 16:00 UTC = 12:00 p. m.
    expect(formatGuardianDateTime(new Date('2026-10-30T16:00:00.000Z'))).toBe(
      '30/10/2026, 12:00 p. m.',
    );
    // 16:01 UTC = 12:01 p. m.
    expect(formatGuardianDateTime(new Date('2026-10-30T16:01:00.000Z'))).toBe(
      '30/10/2026, 12:01 p. m.',
    );
  });

  it('maneja la medianoche dominicana', () => {
    // 04:00 UTC = 00:00 del mismo día → 12:00 a. m.
    expect(formatGuardianDateTime(new Date('2026-10-30T04:00:00.000Z'))).toBe(
      '30/10/2026, 12:00 a. m.',
    );
  });

  it('cambia de día cuando en UTC todavía es el día siguiente', () => {
    // 02:00 UTC del 30 = 22:00 del 29 en Santo Domingo
    expect(formatGuardianDateTime(new Date('2026-10-30T02:00:00.000Z'))).toBe(
      '29/10/2026, 10:00 p. m.',
    );
    // 03:59 UTC del 30 = 23:59 del 29
    expect(formatGuardianDateTime(new Date('2026-10-30T03:59:00.000Z'))).toBe(
      '29/10/2026, 11:59 p. m.',
    );
    // 00:30 UTC del 30 = 20:30 del 29
    expect(formatGuardianDateTime(new Date('2026-10-30T00:30:00.000Z'))).toBe(
      '29/10/2026, 08:30 p. m.',
    );
  });

  it('mantiene el desfase de -4 h en todo el año (sin horario de verano)', () => {
    expect(formatGuardianDateTime(new Date('2026-01-15T15:00:00.000Z'))).toBe(
      '15/01/2026, 11:00 a. m.',
    );
    expect(formatGuardianDateTime(new Date('2026-07-15T15:00:00.000Z'))).toBe(
      '15/07/2026, 11:00 a. m.',
    );
  });

  it('no aplica doble conversión al reformatear el mismo instante', () => {
    const instant = new Date('2026-10-30T02:00:00.000Z');
    const first = formatGuardianDateTime(instant);
    const second = formatGuardianDateTime(instant);
    expect(first).toBe(second);
    expect(first).toBe('29/10/2026, 10:00 p. m.');
    // El instante original no se muta.
    expect(instant.toISOString()).toBe('2026-10-30T02:00:00.000Z');
  });

  it('acepta cadenas ISO en UTC y devuelve solo la hora con formatGuardianTime', () => {
    expect(formatGuardianTime('2026-10-30T12:00:00.000Z')).toBe('08:00 a. m.');
  });

  it('no rompe con una fecha inválida', () => {
    expect(formatGuardianDateTime(new Date('no-es-fecha'))).toBe('—');
  });
});

describe('Guardian — alerta con hora dominicana', () => {
  const base = {
    severity: GuardianSeverity.SEV1,
    companyName: 'FULLTECH, SRL',
    module: 'cash',
    operation: 'closeSession',
    occurredAt: new Date('2026-10-30T02:00:00.000Z'), // 29/10 22:00 en RD
    problem: 'Fallo al cerrar turno',
    diagnosis: 'Probable inconsistencia de cierre',
    impact: 'Caja puede quedar descuadrada',
    incidentId: 'abcd1234-0000-0000-0000-000000000000',
  };

  it('el mensaje de texto muestra la hora dominicana y no la UTC', () => {
    const text = buildGuardianAlertMessage(base);
    expect(text).toContain('29/10/2026, 10:00 p. m.');
    expect(text).not.toContain('02:00');
  });

  it('los parámetros de plantilla usan el mismo formato', () => {
    const params = buildGuardianAlertTemplateParams(base);
    expect(params).toContain('29/10/2026, 10:00 p. m.');
  });
});
