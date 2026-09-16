import { BadRequestException } from "@nestjs/common";

export const BUSINESS_TIME_ZONE = "America/Santo_Domingo";

const BUSINESS_DAY_FORMATTER = new Intl.DateTimeFormat("en-CA", {
  timeZone: BUSINESS_TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

const BUSINESS_DATE_TIME_PARTS = new Intl.DateTimeFormat("en-CA", {
  timeZone: BUSINESS_TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hour12: false,
});

const ISO_WITH_ZONE_RE = /(?:Z|[+-]\d{2}:\d{2})$/i;
const DATE_ONLY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

type DateParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

export function formatBusinessDay(date: Date): string {
  const parts = partsMap(BUSINESS_DAY_FORMATTER, date);
  return `${parts.year}-${pad2(parts.month)}-${pad2(parts.day)}`;
}

export function currentBusinessDay(now = new Date()): string {
  return formatBusinessDay(now);
}

export function businessDateRange(
  from?: string,
  to?: string,
): { gte: Date; lt: Date } {
  const startText = normalizeDateOnly(from) ?? currentBusinessDay();
  const endText = normalizeDateOnly(to) ?? startText;
  const start = businessDayStartUtc(startText);
  const end = nextBusinessDayStartUtc(endText);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    throw new BadRequestException("Rango de fechas invalido");
  }
  if (start.getTime() >= end.getTime()) {
    throw new BadRequestException(
      "La fecha inicial no puede ser mayor que la final",
    );
  }
  return { gte: start, lt: end };
}

export function parseBusinessBoundary(value: string, isStart: boolean): Date {
  const trimmed = value.trim();
  if (DATE_ONLY_RE.test(trimmed)) {
    return isStart ? businessDayStartUtc(trimmed) : nextBusinessDayStartUtc(trimmed);
  }
  return parseServerInstant(trimmed);
}

export function parseServerInstant(value: string): Date {
  const trimmed = value.trim();
  if (!ISO_WITH_ZONE_RE.test(trimmed)) {
    throw new BadRequestException(
      "Timestamp ambiguo: use ISO 8601 con Z u offset explícito",
    );
  }
  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) {
    throw new BadRequestException("Timestamp invalido");
  }
  return parsed;
}

export function businessDayStartUtc(dateText: string): Date {
  return businessLocalToUtc(dateText, 0, 0, 0, 0);
}

export function nextBusinessDayStartUtc(dateText: string): Date {
  const parsed = parseDateOnly(dateText);
  if (!parsed) return new Date(Number.NaN);
  const next = new Date(Date.UTC(parsed.year, parsed.month - 1, parsed.day + 1));
  return businessLocalToUtc(formatUtcDateOnly(next), 0, 0, 0, 0);
}

export function businessLocalToUtc(
  dateText: string,
  hour: number,
  minute: number,
  second: number,
  millisecond: number,
): Date {
  const parsed = parseDateOnly(dateText);
  if (!parsed) return new Date(Number.NaN);
  const utcGuess = new Date(
    Date.UTC(parsed.year, parsed.month - 1, parsed.day, hour, minute, second, millisecond),
  );
  const offset = timeZoneOffsetMs(utcGuess);
  return new Date(utcGuess.getTime() - offset);
}

function normalizeDateOnly(value?: string): string | undefined {
  const text = value?.trim();
  if (!text) return undefined;
  return text.slice(0, 10);
}

function parseDateOnly(value: string) {
  const match = DATE_ONLY_RE.exec(value.trim());
  if (!match) return null;
  return {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
  };
}

function timeZoneOffsetMs(date: Date): number {
  const parts = partsMap(BUSINESS_DATE_TIME_PARTS, date);
  const asUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour === 24 ? 0 : parts.hour,
    parts.minute,
    parts.second,
  );
  return asUtc - date.getTime();
}

function partsMap(formatter: Intl.DateTimeFormat, date: Date): DateParts {
  const entries = Object.fromEntries(
    formatter
      .formatToParts(date)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, Number(part.value)]),
  ) as Record<string, number>;
  return {
    year: entries.year,
    month: entries.month,
    day: entries.day,
    hour: entries.hour ?? 0,
    minute: entries.minute ?? 0,
    second: entries.second ?? 0,
  };
}

function formatUtcDateOnly(date: Date): string {
  return `${date.getUTCFullYear()}-${pad2(date.getUTCMonth() + 1)}-${pad2(
    date.getUTCDate(),
  )}`;
}

function pad2(value: number): string {
  return `${value}`.padStart(2, "0");
}
