import {
  daysUntil,
  NEXT_DUE_WINDOW_DAYS,
  renewalStateFor,
  shouldSendReminder,
} from './license-renewal.policy';

const DAY = 86_400_000;
const NOW = new Date('2026-11-17T12:00:00.000Z');

function inDays(days: number) {
  return new Date(NOW.getTime() + days * DAY);
}

describe('renewalStateFor', () => {
  it('marca la cuota como proxima exactamente en la ventana de 10 dias', () => {
    expect(NEXT_DUE_WINDOW_DAYS).toBe(10);
    expect(
      renewalStateFor({ now: NOW, periodEnd: inDays(10), paymentInReview: false }),
    ).toBe('UPCOMING');
  });

  it('con 11 dias todavia esta al dia', () => {
    expect(
      renewalStateFor({ now: NOW, periodEnd: inDays(11), paymentInReview: false }),
    ).toBe('CURRENT');
  });

  it('el ultimo dia de servicio sigue siendo cuota proxima, no vencida', () => {
    expect(
      renewalStateFor({ now: NOW, periodEnd: inDays(1), paymentInReview: false }),
    ).toBe('UPCOMING');
  });

  it('cuando la fecha ya paso esta vencida', () => {
    expect(
      renewalStateFor({ now: NOW, periodEnd: inDays(-1), paymentInReview: false }),
    ).toBe('OVERDUE');
    expect(
      renewalStateFor({ now: NOW, periodEnd: NOW, paymentInReview: false }),
    ).toBe('OVERDUE');
  });

  it('el comprobante en revision manda sobre vencida y proxima', () => {
    // Cliente que pago a tiempo: no puede aparecer como moroso.
    expect(
      renewalStateFor({ now: NOW, periodEnd: inDays(-2), paymentInReview: true }),
    ).toBe('IN_REVIEW');
    expect(
      renewalStateFor({ now: NOW, periodEnd: inDays(3), paymentInReview: true }),
    ).toBe('IN_REVIEW');
  });

  it('sin vencimiento no inventa una cuota', () => {
    expect(
      renewalStateFor({ now: NOW, periodEnd: null, paymentInReview: false }),
    ).toBe('CURRENT');
  });
});

describe('shouldSendReminder', () => {
  it('conserva los avisos de 5 y 1 dia', () => {
    expect(
      shouldSendReminder({ state: 'UPCOMING', daysLeft: 5 }),
    ).toEqual({ send: true, kind: 'REMINDER_5D' });
    expect(
      shouldSendReminder({ state: 'UPCOMING', daysLeft: 1 }),
    ).toEqual({ send: true, kind: 'REMINDER_1D' });
    expect(shouldSendReminder({ state: 'UPCOMING', daysLeft: 3 })).toEqual({
      send: false,
      kind: null,
    });
  });

  it('no reclama el pago si ya lo envio (en verificacion)', () => {
    expect(shouldSendReminder({ state: 'IN_REVIEW', daysLeft: 5 })).toEqual({
      send: false,
      kind: null,
    });
    expect(shouldSendReminder({ state: 'IN_REVIEW', daysLeft: 1 })).toEqual({
      send: false,
      kind: null,
    });
  });

  it('no manda recordatorio de vencimiento a una cuota ya vencida', () => {
    expect(shouldSendReminder({ state: 'OVERDUE', daysLeft: 0 })).toEqual({
      send: false,
      kind: null,
    });
  });
});

describe('daysUntil', () => {
  it('redondea hacia arriba: el mismo dia del vencimiento es el ultimo dia', () => {
    expect(daysUntil(NOW, NOW)).toBe(0);
    expect(daysUntil(inDays(1), NOW)).toBe(1);
    expect(daysUntil(new Date(NOW.getTime() + 3 * 60 * 60 * 1000), NOW)).toBe(1);
    expect(daysUntil(new Date(NOW.getTime() + 10 * DAY - 1000), NOW)).toBe(10);
  });
});
