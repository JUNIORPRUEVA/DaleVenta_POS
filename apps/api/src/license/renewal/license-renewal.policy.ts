/**
 * Politica de renovacion: **una sola** definicion de cuando una cuota pasa a
 * estar pendiente, para que la pantalla y los recordatorios no puedan decir
 * cosas distintas.
 *
 * Hay cuatro situaciones y no se mezclan:
 *
 * - `CURRENT`    al dia, sin cuota proxima todavia.
 * - `UPCOMING`   la proxima cuota ya se puede pagar (ventana de 10 dias).
 *                **No** esta vencida: el servicio sigue activo.
 * - `IN_REVIEW`  el cliente ya envio el comprobante y espera verificacion.
 *                No se le puede escribir como si no hubiera pagado.
 * - `OVERDUE`    la cuota paso su fecha sin pago: aqui si hay riesgo de corte.
 */

/** Dias antes del vencimiento en los que la cuota aparece como pendiente. */
export const NEXT_DUE_WINDOW_DAYS = 10;

/** Avisos que se conservan (5 y 1 dia antes), solo si la cuota no esta pagada. */
export const REMINDER_DAYS = [5, 1] as const;

export type RenewalState = 'CURRENT' | 'UPCOMING' | 'IN_REVIEW' | 'OVERDUE';

/** Estados de orden que significan «el cliente pago y espera verificacion». */
export const IN_REVIEW_STATUSES = ['EVIDENCE_RECEIVED', 'UNCONFIRMED'] as const;

export type RenewalStateInput = {
  now: Date;
  /** Fin del periodo pagado (vencimiento real de la licencia). */
  periodEnd: Date | null;
  /** Ya hay un comprobante esperando verificacion. */
  paymentInReview: boolean;
  windowDays?: number;
};

/**
 * Calcula el estado. El comprobante en revision manda: el cliente **si** pago,
 * asi que ni se le marca vencida ni se le manda un recordatorio de cobro.
 */
export function renewalStateFor(input: RenewalStateInput): RenewalState {
  if (input.paymentInReview) return 'IN_REVIEW';
  if (!input.periodEnd) return 'CURRENT';
  const windowDays = input.windowDays ?? NEXT_DUE_WINDOW_DAYS;
  const daysLeft = daysUntil(input.periodEnd, input.now);
  if (daysLeft <= 0) return 'OVERDUE';
  return daysLeft <= windowDays ? 'UPCOMING' : 'CURRENT';
}

/**
 * Dias que faltan. Se redondea hacia arriba para que «vence manana» sea 1 y no
 * 0, y para que el mismo dia del vencimiento cuente como ultimo dia de servicio.
 */
export function daysUntil(target: Date, now: Date): number {
  const ms = target.getTime() - now.getTime();
  return Math.ceil(ms / 86_400_000);
}

/** ¿Toca mandar el aviso de este nivel hoy, con este estado? */
export function shouldSendReminder(input: {
  state: RenewalState;
  daysLeft: number | null;
  reminderDays?: readonly number[];
}): { send: boolean; kind: 'REMINDER_5D' | 'REMINDER_1D' | null } {
  if (input.daysLeft == null) return { send: false, kind: null };
  // Vencida o en revision: no se reclama un pago que ya existe (o que ya
  // paso a reclamarse por otra via).
  if (input.state === 'IN_REVIEW' || input.state === 'OVERDUE') {
    return { send: false, kind: null };
  }
  const days = input.reminderDays ?? REMINDER_DAYS;
  if (input.daysLeft === 5 && days.includes(5)) {
    return { send: true, kind: 'REMINDER_5D' };
  }
  if (input.daysLeft === 1 && days.includes(1)) {
    return { send: true, kind: 'REMINDER_1D' };
  }
  return { send: false, kind: null };
}
