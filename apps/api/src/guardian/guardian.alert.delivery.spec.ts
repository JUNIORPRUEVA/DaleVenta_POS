import { GuardianAlertState } from '@prisma/client';
import { advanceAlertDelivery, mapMetaStatus } from './guardian.alert.delivery';

describe('mapMetaStatus', () => {
  it('mapea los estados reales de WhatsApp Cloud API', () => {
    expect(mapMetaStatus('sent')).toBe('sent');
    expect(mapMetaStatus('delivered')).toBe('delivered');
    expect(mapMetaStatus('read')).toBe('read');
    expect(mapMetaStatus('failed')).toBe('failed');
  });

  it('devuelve unknown para valores no relacionados con entrega', () => {
    expect(mapMetaStatus('deleted')).toBe('unknown');
    expect(mapMetaStatus(undefined)).toBe('unknown');
    expect(mapMetaStatus('')).toBe('unknown');
  });
});

describe('advanceAlertDelivery', () => {
  const now = new Date('2026-10-26T12:00:00.000Z');

  it('un envío aceptado pasa de SENDING a SENT', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.SENDING, 'sent', now);
    expect(transition.state).toBe(GuardianAlertState.SENT);
  });

  it('delivered fija deliveredAt', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.SENT, 'delivered', now);
    expect(transition.state).toBe(GuardianAlertState.DELIVERED);
    expect(transition.deliveredAt).toEqual(now);
  });

  it('read antes de delivered registra lectura y entrega', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.SENT, 'read', now);
    expect(transition.state).toBe(GuardianAlertState.READ);
    expect(transition.readAt).toEqual(now);
    expect(transition.deliveredAt).toEqual(now);
  });

  it('nunca retrocede cuando un webhook llega desordenado', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.READ, 'delivered', now);
    expect(transition.state).toBeNull();
    expect(transition.deliveredAt).toBeUndefined();
  });

  it('failed antes de entregar deja la alerta en FAILED_PERMANENT', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.SENT, 'failed', now, {
      error: '131026 destinatario inválido',
    });
    expect(transition.state).toBe(GuardianAlertState.FAILED_PERMANENT);
    expect(transition.lastError).toContain('131026');
  });

  it('failed posterior a la entrega conserva la evidencia y anota el error', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.DELIVERED, 'failed', now);
    expect(transition.state).toBeNull();
    expect(transition.lastError).toBeTruthy();
  });

  it('una alerta terminal no revive con estados tardíos', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.DEAD, 'read', now);
    expect(transition.state).toBeNull();
    expect(transition.readAt).toBeUndefined();
  });

  it('sent no degrada una alerta ya entregada', () => {
    const transition = advanceAlertDelivery(GuardianAlertState.DELIVERED, 'sent', now);
    expect(transition.state).toBeNull();
  });
});
