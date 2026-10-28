const RD_OFFSET_MS = 4 * 60 * 60 * 1000;
const BUSINESS_START_HOUR = 9;
const BUSINESS_END_HOUR = 18;

function toDominicanLocal(date: Date) {
  return new Date(date.getTime() - RD_OFFSET_MS);
}

function fromDominicanLocal(date: Date) {
  return new Date(date.getTime() + RD_OFFSET_MS);
}

function pad2(value: number) {
  return String(value).padStart(2, '0');
}

export function toDominicanDayKey(date: Date) {
  const local = toDominicanLocal(date);
  const year = local.getUTCFullYear();
  const month = pad2(local.getUTCMonth() + 1);
  const day = pad2(local.getUTCDate());
  return `${year}-${month}-${day}`;
}

export function isSameDominicanDay(left: Date, right: Date) {
  return toDominicanDayKey(left) === toDominicanDayKey(right);
}

export function isWithinNotificationBusinessHours(date: Date = new Date()) {
  const local = toDominicanLocal(date);
  const dayOfWeek = local.getUTCDay();
  if (dayOfWeek === 0) {
    return false;
  }

  const hour = local.getUTCHours();
  const minute = local.getUTCMinutes();
  const totalMinutes = hour * 60 + minute;
  return totalMinutes >= BUSINESS_START_HOUR * 60 && totalMinutes < BUSINESS_END_HOUR * 60;
}

export function getNextNotificationBusinessStart(date: Date = new Date()) {
  const local = toDominicanLocal(date);
  const candidate = new Date(
    Date.UTC(
      local.getUTCFullYear(),
      local.getUTCMonth(),
      local.getUTCDate(),
      BUSINESS_START_HOUR,
      0,
      0,
      0,
    ),
  );

  const currentMinutes = local.getUTCHours() * 60 + local.getUTCMinutes();
  const currentDay = local.getUTCDay();

  if (currentDay >= 1 && currentDay <= 6 && currentMinutes < BUSINESS_START_HOUR * 60) {
    return fromDominicanLocal(candidate);
  }

  if (currentDay >= 1 && currentDay <= 6 && currentMinutes < BUSINESS_END_HOUR * 60) {
    return new Date(date.getTime());
  }

  do {
    candidate.setUTCDate(candidate.getUTCDate() + 1);
  } while (candidate.getUTCDay() === 0);

  return fromDominicanLocal(candidate);
}

export function alignToNotificationBusinessHours(date: Date = new Date()) {
  if (isWithinNotificationBusinessHours(date)) {
    return new Date(date.getTime());
  }

  return getNextNotificationBusinessStart(date);
}

/**
 * Fecha del primer intento de envío de una notificación.
 *
 * Por defecto respeta la ventana comercial existente (comportamiento histórico).
 * Las alertas operativas críticas (por ejemplo, las que emitirá APPYRA Guardian)
 * deben pasar `allowOutsideBusinessHours: true` para no quedar retenidas hasta
 * el siguiente horario comercial. Este helper no cambia la ventana en sí: solo
 * decide si el primer intento se desplaza.
 */
export function resolveInitialAttemptAt(
  date: Date = new Date(),
  allowOutsideBusinessHours = false,
) {
  if (allowOutsideBusinessHours) {
    return new Date(date.getTime());
  }

  return alignToNotificationBusinessHours(date);
}
