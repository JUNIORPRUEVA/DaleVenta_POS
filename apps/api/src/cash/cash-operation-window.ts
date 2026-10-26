import { currentBusinessDay } from "../common/utils/business-time.util";

/**
 * Ventana operativa de un turno de caja.
 *
 * Problema que resuelve
 * ---------------------
 * Un turno abierto podía recibir operaciones de días posteriores de forma
 * indefinida (una venta del 22/10 quedaba imputada al turno/cierre del 19/10),
 * porque la única validación era "turno abierto del mismo usuario". Eso
 * desviaba efectivo entre cierres diarios.
 *
 * Regla financiera
 * ----------------
 * Una operación sólo puede imputarse a un turno si ocurrió DENTRO de la vida
 * del turno y dentro de su día comercial o, como máximo, del día comercial
 * inmediatamente siguiente (un turno nocturno cruza exactamente una medianoche).
 *
 * Por qué no se usa la fecha de recepción
 * --------------------------------------
 * Las operaciones offline se sincronizan horas (o días) después. La validación
 * usa SIEMPRE `occurredAt` (fecha real de la operación en el dispositivo), nunca
 * `now()` del servidor, para no invalidar sincronizaciones legítimas
 * (Offline Safe 48h).
 *
 * Por qué hay un tope de duración y por qué 24h
 * ---------------------------------------------
 * `businessDate` es un día calendario (America/Santo_Domingo): un turno puede
 * abrirse 23:50 y vender 00:10 del día siguiente. Para que ese caso real siga
 * funcionando se acepta el día comercial siguiente, pero se acota la duración
 * total del turno a `CASH_SHIFT_MAX_SPAN_HOURS` (24h por defecto) porque un
 * turno de POS no puede durar legítimamente más de un día completo. Con 24h y
 * `occurredAt >= openedAt`, la fecha de la operación sólo puede ser la del
 * turno o la del día siguiente, así que ambas reglas se refuerzan:
 *
 *   - un turno de 3 días (turno "zombi") rechaza cualquier operación nueva;
 *   - un turno nocturno normal (22:00 → 03:00) sigue operando sin cambios.
 *
 * El valor es configurable por entorno y tiene un techo duro de 72h para que
 * una mala configuración no reabra el defecto.
 */
export const CASH_SHIFT_MAX_SPAN_HOURS_DEFAULT = 24;
export const CASH_SHIFT_MAX_SPAN_HOURS_CEILING = 72;
export const CASH_SHIFT_CLOCK_SKEW_MINUTES_DEFAULT = 5;
export const CASH_SHIFT_CLOCK_SKEW_MINUTES_CEILING = 30;

export type ShiftWindowCode =
  | "CASH_OPERATION_BEFORE_SHIFT"
  | "CASH_OPERATION_AFTER_CLOSE"
  | "CASH_SESSION_STALE";

export type ShiftWindowVerdict =
  | { allowed: true }
  | { allowed: false; code: ShiftWindowCode; reason: string };

export type ShiftWindowSession = {
  openedAt: Date;
  closedAt?: Date | null;
  businessDate?: string | null;
};

export function resolveShiftMaxSpanHours(
  env: NodeJS.ProcessEnv = process.env,
): number {
  const raw = `${env.CASH_SHIFT_MAX_SPAN_HOURS ?? ""}`.trim();
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return CASH_SHIFT_MAX_SPAN_HOURS_DEFAULT;
  }
  return Math.min(parsed, CASH_SHIFT_MAX_SPAN_HOURS_CEILING);
}

export function addDaysToDateOnly(dateText: string, days: number): string {  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateText.trim());
  if (!match) return dateText;
  const base = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]) + days),
  );
  if (Number.isNaN(base.getTime())) return dateText;
  return base.toISOString().slice(0, 10);
}

/** Fecha comercial (America/Santo_Domingo) de un instante dado. */
export function businessDateOf(instant: Date): string {
  return currentBusinessDay(instant);
}

/**
 * Tolerancia de desfase de reloj entre el dispositivo y el servidor.
 *
 * `saleOccurredAt` / `occurredAt` los genera el DISPOSITIVO; `openedAt` y
 * `closedAt` los genera el SERVIDOR. Un equipo con el reloj atrasado 2 minutos
 * rechazaría su primera venta legítima con `CASH_OPERATION_BEFORE_SHIFT`, y uno
 * adelantado podría chocar con el instante de cierre.
 *
 * Por qué no puede corromper nada: la tolerancia sólo se aplica a los bordes
 * de la vida del turno (no a la ventana de día comercial) y está acotada a
 * minutos, así que la operación sigue perteneciendo al MISMO turno y al MISMO
 * día comercial. Techo duro de 30 minutos para que una mala configuración no
 * reabra el defecto.
 */
export function resolveClockSkewMs(env: NodeJS.ProcessEnv = process.env): number {
  const raw = `${env.CASH_SHIFT_CLOCK_SKEW_MINUTES ?? ""}`.trim();
  const parsed = Number.parseInt(raw, 10);
  const minutes = Number.isFinite(parsed) && parsed >= 0
    ? Math.min(parsed, CASH_SHIFT_CLOCK_SKEW_MINUTES_CEILING)
    : CASH_SHIFT_CLOCK_SKEW_MINUTES_DEFAULT;
  return minutes * 60_000;
}

export function evaluateShiftOperationWindow(input: {
  occurredAt: Date;
  session: ShiftWindowSession;
  maxSpanHours?: number;
  env?: NodeJS.ProcessEnv;
}): ShiftWindowVerdict {
  const { session } = input;
  const occurredAt = input.occurredAt;

  if (!(occurredAt instanceof Date) || Number.isNaN(occurredAt.getTime())) {
    return {
      allowed: false,
      code: "CASH_SESSION_STALE",
      reason: "La operación no tiene una fecha válida.",
    };
  }

  const openedAtValid =
    session.openedAt instanceof Date &&
    !Number.isNaN(session.openedAt.getTime());

  // `openedAt` es NOT NULL en la base de datos, así que en producción siempre
  // existe. Si un llamador no lo trae (consulta parcial o mock), se degrada a
  // la comparación de día comercial y, si tampoco hay fecha, no se bloquea.
  if (!openedAtValid) {
    const fallbackDate = session.businessDate;
    if (!fallbackDate) return { allowed: true };
    const operationDate = businessDateOf(occurredAt);
    const allowed = new Set([
      fallbackDate,
      addDaysToDateOnly(fallbackDate, 1),
    ]);
    if (allowed.has(operationDate)) return { allowed: true };
    return {
      allowed: false,
      code: "CASH_SESSION_STALE",
      reason:
        "Este turno es de un día anterior y ya no puede recibir operaciones. " +
        "Ciérralo y abre un turno nuevo.",
    };
  }

  if (
    occurredAt.getTime() <
    session.openedAt.getTime() - resolveClockSkewMs(input.env ?? process.env)
  ) {
    return {
      allowed: false,
      code: "CASH_OPERATION_BEFORE_SHIFT",
      reason: "La operación es anterior a la apertura del turno.",
    };
  }

  if (
    session.closedAt &&
    occurredAt.getTime() >
      session.closedAt.getTime() + resolveClockSkewMs(input.env ?? process.env)
  ) {
    return {
      allowed: false,
      code: "CASH_OPERATION_AFTER_CLOSE",
      reason: "La operación es posterior al cierre del turno.",
    };
  }

  const maxSpanHours =
    input.maxSpanHours ?? resolveShiftMaxSpanHours(input.env ?? process.env);
  const spanHours =
    (occurredAt.getTime() - session.openedAt.getTime()) / 3_600_000;
  if (spanHours > maxSpanHours) {
    return {
      allowed: false,
      code: "CASH_SESSION_STALE",
      reason:
        "Este turno es de un día anterior y ya no puede recibir operaciones. " +
        "Ciérralo y abre un turno nuevo.",
    };
  }

  const sessionBusinessDate =
    session.businessDate ?? businessDateOf(session.openedAt);
  const operationBusinessDate = businessDateOf(occurredAt);
  const allowedDates = new Set([
    sessionBusinessDate,
    addDaysToDateOnly(sessionBusinessDate, 1),
  ]);
  if (!allowedDates.has(operationBusinessDate)) {
    return {
      allowed: false,
      code: "CASH_SESSION_STALE",
      reason:
        "Este turno es de un día anterior y ya no puede recibir operaciones. " +
        "Ciérralo y abre un turno nuevo.",
    };
  }

  return { allowed: true };
}

export function shiftWindowRejected(
  code: ShiftWindowCode,
  reason: string,
  sessionId: string,
) {
  return {
    code,
    errorCode: code,
    sessionId,
    message: reason,
  };
}
