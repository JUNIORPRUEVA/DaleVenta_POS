/**
 * Decimal-safe arithmetic for the legacy migration.
 *
 * Money is handled as integer CENTS (bigint) and quantities as integer MICRO units
 * (bigint, 6 decimals) so that no rounding drift can appear while converting SQLite
 * REAL values into the target Decimal(12,2) / Decimal(18,6) columns.
 *
 * Half-up rounding is used everywhere (the convention the cloud uses for money).
 */

export const CENTS_PER_UNIT = 100n;
export const MICRO_PER_UNIT = 1_000_000n;

export function centsFromNumber(value: number): bigint {
  if (!Number.isFinite(value)) {
    throw new Error(`Valor monetario no finito: ${String(value)}`);
  }
  return BigInt(Math.round(value * 100));
}

export function microFromNumber(value: number): bigint {
  if (!Number.isFinite(value)) {
    throw new Error(`Cantidad no finita: ${String(value)}`);
  }
  return BigInt(Math.round(value * 1_000_000));
}

/** Divide rounding half away from zero. */
function divRoundHalfUp(numerator: bigint, denominator: bigint): bigint {
  if (denominator <= 0n) throw new Error('Denominador inválido');
  const negative = numerator < 0n;
  const abs = negative ? -numerator : numerator;
  const quotient = (abs + denominator / 2n) / denominator;
  return negative ? -quotient : quotient;
}

/** quantity(MICRO) x unit price(CENTS) -> total CENTS, half-up. */
export function multiplyMicroByCents(qtyMicro: bigint, unitCents: bigint): bigint {
  return divRoundHalfUp(qtyMicro * unitCents, MICRO_PER_UNIT);
}

/** Micro units (6 decimals) -> cents (2 decimals), half-up. */
export function centsFromMicro(micro: bigint): bigint {
  return divRoundHalfUp(micro, 10_000n);
}

export function sumBigInt(values: readonly bigint[]): bigint {
  return values.reduce((acc, value) => acc + value, 0n);
}

function formatScaled(value: bigint, scale: bigint): string {
  const negative = value < 0n;
  const abs = negative ? -value : value;
  const integerPart = abs / scale;
  const fractionPart = abs % scale;
  const fractionDigits = scale.toString().length - 1;
  const fraction = fractionPart.toString().padStart(fractionDigits, '0');
  return `${negative ? '-' : ''}${integerPart.toString()}.${fraction}`;
}

/** 1557n -> "15.57"; 109553500n -> "1095535.00" */
export function formatCents(value: bigint): string {
  return formatScaled(value, CENTS_PER_UNIT);
}

/** 294000000n -> "294.000000" */
export function formatMicro(value: bigint): string {
  return formatScaled(value, MICRO_PER_UNIT);
}

export function parseCents(value: string): bigint {
  const text = value.trim();
  if (!/^-?\d+(\.\d+)?$/.test(text)) {
    throw new Error(`Importe inválido: ${value}`);
  }
  const negative = text.startsWith('-');
  const digits = negative ? text.slice(1) : text;
  const [integerPart, fractionPart = ''] = digits.split('.');
  const fraction = (fractionPart + '00').slice(0, 2);
  const cents = BigInt(integerPart) * CENTS_PER_UNIT + BigInt(fraction);
  return negative ? -cents : cents;
}

/** Milliseconds since epoch -> ISO-8601 UTC string. */
export function isoFromEpochMs(ms: number | null | undefined): string | null {
  if (ms === null || ms === undefined || !Number.isFinite(ms)) return null;
  return new Date(ms).toISOString();
}
