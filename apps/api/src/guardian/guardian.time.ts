/**
 * Fase 14 — Formato de fecha y hora de APPYRA Guardian.
 *
 * Reglas:
 * - Internamente todo se guarda y se transporta en UTC (PostgreSQL `timestamptz`
 *   y `Date` de JS). Aquí es el ÚNICO punto donde se convierte a la zona del
 *   negocio, para que no exista doble conversión.
 * - Zona: `America/Santo_Domingo` (UTC-04:00 todo el año, sin horario de verano).
 * - Formato dominicano: `DD/MM/YYYY, hh:mm a. m.` / `DD/MM/YYYY, hh:mm p. m.`
 *
 * El defecto anterior usaba `toLocaleString('es-DO', …)` sin `timeZone`, así que
 * formateaba en la zona del contenedor (UTC) y las alertas mostraban +4 horas.
 */
export const GUARDIAN_TIME_ZONE = 'America/Santo_Domingo';

const PARTS_FORMATTER = new Intl.DateTimeFormat('en-GB', {
  timeZone: GUARDIAN_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

/**
 * Convierte un instante UTC al formato dominicano `DD/MM/YYYY, hh:mm a. m.`.
 * Nunca devuelve `undefined`: ante una fecha inválida devuelve un guion.
 */
export function formatGuardianDateTime(value: Date | string | number): string {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '—';

  const parts = PARTS_FORMATTER.formatToParts(date);
  const pick = (type: Intl.DateTimeFormatPartTypes): string =>
    parts.find((part) => part.type === type)?.value ?? '00';

  // Algunos ICU devuelven "24" para medianoche con hour12:false.
  const rawHour = Number.parseInt(pick('hour'), 10);
  const hour24 = Number.isFinite(rawHour) ? rawHour % 24 : 0;
  const suffix = hour24 < 12 ? 'a. m.' : 'p. m.';
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;

  return `${pick('day')}/${pick('month')}/${pick('year')}, ${String(hour12).padStart(2, '0')}:${pick('minute')} ${suffix}`;
}

/** Solo la hora, en el mismo formato dominicano (sin fecha). */
export function formatGuardianTime(value: Date | string | number): string {
  const formatted = formatGuardianDateTime(value);
  if (formatted === '—') return formatted;
  const [, time] = formatted.split(', ');
  return time ?? formatted;
}
