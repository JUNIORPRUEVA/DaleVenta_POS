import { addMonths } from '../orders/license-activation.service';
import {
  buildAdminEvidenceParams,
  buildReminderParams,
  formatDate,
  formatMoney,
  LICENSE_TEMPLATES,
} from './license.templates';
import { normalizePhone } from './meta-cloud.client';

describe('LICENSE_TEMPLATES', () => {
  it('usa los nombres aprobados en Meta', () => {
    expect(LICENSE_TEMPLATES).toEqual({
      ADMIN_EVIDENCE: 'licencia_pago_por_verificar',
      REMINDER_5D: 'licencia_por_vencer_5d',
      REMINDER_1D: 'licencia_por_vencer_1d',
    });
  });
});

describe('parametros de plantilla', () => {
  it('arma el aviso del comprobante con empresa, plan, monto y referencia', () => {
    const params = buildAdminEvidenceParams({
      companyName: 'Colmado La Fe',
      planName: 'FullPOS Pro',
      amount: 3500,
      reference: 'FP-2026-000123',
      receivedAt: new Date('2026-11-16T18:30:00.000Z'),
    });
    expect(params).toEqual([
      'Colmado La Fe',
      'FullPOS Pro',
      'RD$3,500',
      'FP-2026-000123',
      '16/11/2026',
    ]);
  });

  it('sin referencia pide generarla desde Planes', () => {
    const params = buildReminderParams({
      companyName: 'Colmado La Fe',
      planName: 'FullPOS Básico',
      periodEnd: new Date('2026-11-21T12:00:00.000Z'),
      reference: null,
    });
    expect(params[0]).toBe('Colmado La Fe');
    expect(params[1]).toBe('21/11/2026');
    expect(params[2]).toBe('Genera tu orden desde la seccion Planes');
  });

  it('formatea dinero y fechas de Republica Dominicana', () => {
    expect(formatMoney(1000)).toBe('RD$1,000');
    expect(formatMoney(2500.5)).toBe('RD$2,500.50');
    expect(formatDate(new Date('2026-01-01T02:00:00.000Z'))).toBe('31/12/2025');
  });
});

describe('normalizePhone', () => {
  it('deja solo digitos y descarta numeros incompletos', () => {
    expect(normalizePhone('+1 (829) 436-3936')).toBe('18294363936');
    expect(normalizePhone('123')).toBe('');
  });
});

describe('addMonths', () => {
  it('suma meses completos', () => {
    expect(
      addMonths(new Date('2026-11-16T12:00:00.000Z'), 1).toISOString(),
    ).toBe('2026-12-16T12:00:00.000Z');
  });

  it('no se pasa de fin de mes al sumar a un dia 31', () => {
    expect(
      addMonths(new Date('2026-01-31T12:00:00.000Z'), 1).toISOString(),
    ).toBe('2026-02-28T12:00:00.000Z');
  });

  it('cruza el anio', () => {
    expect(
      addMonths(new Date('2026-12-15T00:00:00.000Z'), 2).toISOString(),
    ).toBe('2027-02-15T00:00:00.000Z');
  });
});
