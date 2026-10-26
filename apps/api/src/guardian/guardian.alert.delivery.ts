import { GuardianAlertState } from '@prisma/client';

/**
 * Estados de entrega reales de WhatsApp Cloud API.
 *
 * Un HTTP 200 al enviar SOLO significa que Meta aceptó el mensaje (`sent`).
 * `delivered` y `read` llegan después por el webhook de estados. Nunca se debe
 * asumir entrega por el código HTTP de la petición.
 */
export type GuardianDeliveryStatus = 'sent' | 'delivered' | 'read' | 'failed';

/**
 * Traduce el `status` literal del webhook de Meta.
 * Devuelve `unknown` para valores que no corresponden a estados de entrega
 * (por ejemplo `deleted` en versiones nuevas): se registran sin cambiar el estado.
 */
export function mapMetaStatus(raw: unknown): GuardianDeliveryStatus | 'unknown' {
  switch (String(raw ?? '').trim().toLowerCase()) {
    case 'sent':
      return 'sent';
    case 'delivered':
      return 'delivered';
    case 'read':
      return 'read';
    case 'failed':
      return 'failed';
    default:
      return 'unknown';
  }
}

/**
 * Orden de avance del ciclo de vida. Un webhook puede llegar desordenado
 * (p. ej. `read` antes que `delivered`); el estado nunca debe retroceder.
 */
const FORWARD_RANK: Record<string, number> = {
  PENDING: 0,
  SENDING: 1,
  SENT: 2,
  DELIVERED: 3,
  READ: 4,
  FAILED_PERMANENT: -1,
  DEAD: -2,
};

export type AlertDeliveryTransition = {
  /** null cuando no hay cambio de estado (solo se actualiza el último estado del proveedor). */
  state: GuardianAlertState | null;
  deliveredAt?: Date;
  readAt?: Date;
  lastError?: string | null;
};

/**
 * Calcula el nuevo estado de una alerta a partir de un estado de entrega.
 *
 * Reglas:
 * - Monótono: SENT < DELIVERED < READ. Nunca se degrada.
 * - `failed` antes de la entrega deja la alerta en FAILED_PERMANENT.
 * - `failed` después de `delivered`/`read` NO borra la entrega: se conserva el
 *   estado y se anota el error (un fallo asíncrono posterior no invalida la
 *   evidencia de que el mensaje llegó).
 * - Una alerta terminal (FAILED_PERMANENT/DEAD) no revive con estados tardíos.
 */
export function advanceAlertDelivery(
  current: GuardianAlertState,
  status: GuardianDeliveryStatus,
  now: Date,
  context?: { error?: string | null },
): AlertDeliveryTransition {
  const rank = FORWARD_RANK[String(current)] ?? 0;
  const terminal =
    current === GuardianAlertState.FAILED_PERMANENT || current === GuardianAlertState.DEAD;

  if (status === 'failed') {
    if (rank >= FORWARD_RANK.DELIVERED) {
      return {
        state: null,
        lastError: context?.error ?? 'proveedor reportó fallo posterior a la entrega',
      };
    }
    if (terminal) {
      return { state: null, lastError: context?.error ?? 'proveedor reportó fallo' };
    }
    return {
      state: GuardianAlertState.FAILED_PERMANENT,
      lastError: context?.error ?? 'proveedor reportó fallo',
    };
  }

  if (terminal) return { state: null };

  if (status === 'sent') {
    if (rank >= FORWARD_RANK.SENT) return { state: null };
    return { state: GuardianAlertState.SENT };
  }

  if (status === 'delivered') {
    if (rank >= FORWARD_RANK.DELIVERED) return { state: null };
    return { state: GuardianAlertState.DELIVERED, deliveredAt: now };
  }

  // read
  if (rank >= FORWARD_RANK.READ) return { state: null };
  return {
    state: GuardianAlertState.READ,
    readAt: now,
    ...(rank >= FORWARD_RANK.DELIVERED ? {} : { deliveredAt: now }),
  };
}
