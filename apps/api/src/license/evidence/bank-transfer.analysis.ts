/**
 * Lectura y validacion de comprobantes de transferencia bancaria.
 *
 * Trabaja sobre el **texto** que devuelve el motor OCR (local, sin IA de
 * pago). Aqui solo hay reglas deterministas y comprobables: si algo no se
 * puede leer, se dice; nunca se inventa un dato.
 */

export type BankCode = 'popular' | 'bhd' | 'banreservas' | null;

export type ParsedReceipt = {
  bank: BankCode;
  bankName: string | null;
  amount: number | null;
  tax: number | null;
  reference: string | null;
  /** ISO de la fecha/hora de la transferencia, si se pudo leer. */
  occurredAt: string | null;
  statusText: string | null;
  status: 'SUCCESS' | 'PENDING' | 'FAILED' | 'UNKNOWN';
  beneficiary: string | null;
  destinationAccount: string | null;
  raw: string;
};

export type BankCheck = { code: string; ok: boolean; detail?: string };

export type BankValidation = {
  passed: boolean;
  checks: BankCheck[];
  parsed: ParsedReceipt;
  validatedAt: string;
};

/** Cuenta autorizada de FULLTECH: termina en 0753. */
export const AUTHORIZED_ACCOUNT_SUFFIX = '0753';

/**
 * Desfase de Republica Dominicana respecto a UTC (sin horario de verano).
 *
 * Los comprobantes escriben la hora **local**, no UTC. Si se leyera como UTC,
 * una transferencia de las 22:30 del dia 18 quedaria como 18/11 22:30Z cuando en
 * realidad ocurrio el 19/11 02:30Z: caia antes del inicio del dia de la orden y
 * se rechazaba la activacion automatica justo en las horas de mas venta.
 */
export const RECEIPT_UTC_OFFSET_HOURS = -4;

const BANK_PROFILES: Array<{ bank: Exclude<BankCode, null>; name: string; keys: RegExp[] }> = [
  {
    bank: 'popular',
    name: 'Banco Popular Dominicano',
    keys: [/banco\s+popular/i, /\bpopular\s+dominicano\b/i],
  },
  { bank: 'bhd', name: 'BHD', keys: [/\bbhd\b/i, /banco\s+bhd/i] },
  {
    bank: 'banreservas',
    name: 'Banreservas',
    keys: [/banreservas/i, /banco\s+de\s+reservas/i],
  },
];

const SUCCESS_WORDS = /\b(exitos[ao]|exitosa|realizada|realizado|completad[ao]|aprobad[ao]|procesad[ao]|efectiv[ao])\b/i;
const PENDING_WORDS = /\b(pendiente|en\s+proceso|por\s+procesar|en\s+espera)\b/i;
const FAILED_WORDS = /\b(rechazad[ao]|fallid[ao]|anulad[ao]|cancelad[ao]|no\s+realizad[ao]|error)\b/i;

export function parseBankReceipt(
  text: string,
  utcOffsetHours: number = RECEIPT_UTC_OFFSET_HOURS,
): ParsedReceipt {
  const raw = String(text ?? '');
  // Espacios «de miles» que imprimen algunos bancos: normal, no separable,
  // fino y de cuarto de eme. Sin esto, "RD$5 000.00" se leia como 5.
  const flat = raw.replace(/[\u00a0\u2007\u2009\u200a\u202f]/g, ' ');
  const profile = BANK_PROFILES.find((candidate) =>
    candidate.keys.some((key) => key.test(flat)),
  );

  const amount = pickLabeledAmount(flat, [
    /(?:monto|importe|total|valor)\s*(?:transferido|de\s+la\s+transferencia)?\s*[:=]?\s*(?:RD\$|DOP\$?|RD|\$)?\s*([\d.,]+(?:\s[\d.,]+)*)/i,
  ]);
  const tax = pickLabeledAmount(flat, [
    /(?:impuesto|itbis|iva)\s*\(?(?:\d{1,2}%?)?\)?\s*[:=]?\s*(?:RD\$|DOP\$?|RD|\$)?\s*([\d.,]+(?:\s[\d.,]+)*)/i,
  ]);
  const reference =
    firstMatch(flat, [
      /(?:referencia|ref\.?|no\.?\s*de\s*referencia|n[uú]mero\s*de\s*(?:referencia|operaci[oó]n)|confirmaci[oó]n)\s*[:#]?\s*([A-Za-z0-9\-.]{4,32})/i,
    ]) ?? null;
  const occurredAt = parseDate(
    firstMatch(flat, [
      // ISO primero: 2026-11-17 14:35 (algunos PDF y correos del banco).
      /(?:fecha\s*y\s*hora|fecha|realizada\s+el|efectuada\s+el)\s*[:]?\s*(\d{4}-\d{1,2}-\d{1,2}(?:[T\s]\d{1,2}:\d{2}(?::\d{2})?)?)/i,
      /(?:fecha\s*y\s*hora|fecha|realizada\s+el|efectuada\s+el)\s*[:]?\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}(?:\s*[-–]?\s*\d{1,2}:\d{2}(?:\s*[ap]\.?\s*m\.?)?)?)/i,
    ]),
    utcOffsetHours,
  );
  const destinationAccount = pickAccount(flat);
  const beneficiary =
    firstMatch(flat, [
      /beneficiari[oa]\s*[:]?\s*([A-Za-z0-9ÁÉÍÓÚÜÑáéíóúüñ.,&\s]{3,60})/i,
    ])?.trim() ?? null;

  const statusText =
    firstMatch(flat, [
      /(?:estado|situaci[oó]n\s+de\s+la\s+operaci[oó]n)\s*[:]?\s*([A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s.]{3,40})/i,
    ])?.trim() ?? null;
  let status: ParsedReceipt['status'] = 'UNKNOWN';
  if (FAILED_WORDS.test(flat)) status = 'FAILED';
  else if (PENDING_WORDS.test(flat)) status = 'PENDING';
  else if (SUCCESS_WORDS.test(flat)) status = 'SUCCESS';

  return {
    bank: profile?.bank ?? null,
    bankName: profile?.name ?? null,
    amount,
    tax,
    reference,
    occurredAt,
    statusText,
    status,
    beneficiary,
    destinationAccount,
    raw,
  };
}

export type BankValidationInput = {
  parsed: ParsedReceipt;
  order: { amount: number; createdAt: Date };
  /**
   * Referencia bancaria ya usada. Se comprueba en **todas** las empresas: la
   * cuenta bancaria es una sola, asi que dos negocios del mismo dueno no pueden
   * aprovechar el mismo comprobante.
   */
  referenceAlreadyUsed?: boolean;
  /** Dias de antiguedad maxima del comprobante (1 = hoy o ayer). */
  maxReceiptAgeDays?: number;
  /**
   * Dias de maniobra hacia adelante. Por defecto **0**: un comprobante con fecha
   * futura no activa. Solo se sube en entornos de prueba.
   */
  daysForward?: number;
  /** Minutos de tolerancia por relojes desfasados (por defecto 30). */
  forwardToleranceMinutes?: number;
  now?: Date;
  /**
   * Ultimos 4 digitos de la cuenta de cobro. `undefined` usa la cuenta por
   * defecto del producto; `null` significa configuracion invalida y **falla**
   * (no se omite la comprobacion).
   */
  authorizedAccountSuffix?: string | null;
  /** Desfase de la hora local del comprobante respecto a UTC. */
  utcOffsetHours?: number;
};

export function validateBankTransfer(input: BankValidationInput): BankValidation {
  const now = input.now ?? new Date();
  const parsed = input.parsed;
  const checks: BankCheck[] = [];
  // El sufijo sale de la configuracion. Si no viene, se usa la cuenta conocida;
  // si viene mal (vacio o con menos de 4 digitos) **no se omite** la regla: se
  // marca como fallo y el comprobante se queda para revision humana.
  const configuredSuffix =
    input.authorizedAccountSuffix === undefined
      ? AUTHORIZED_ACCOUNT_SUFFIX
      : digits(input.authorizedAccountSuffix);
  const suffixOk = /^\d{4}$/.test(configuredSuffix);

  checks.push({ code: 'RECEIPT_TEXT', ok: parsed.raw.trim().length >= 20 });
  checks.push({
    code: 'BANK_ACCOUNT_CONFIGURED',
    ok: suffixOk,
    detail: suffixOk
      ? `termina en ${configuredSuffix}`
      : 'cuenta destino no configurada (se esperan 4 digitos)',
  });
  checks.push({
    code: 'BANK_IDENTIFIED',
    ok: parsed.bank != null,
    detail: parsed.bankName ?? 'banco no reconocido',
  });
  checks.push({
    code: 'OPERATION_SUCCESSFUL',
    ok: parsed.status === 'SUCCESS',
    detail: parsed.statusText ?? parsed.status,
  });
  checks.push({
    code: 'BANK_REFERENCE',
    ok: !!parsed.reference && /[A-Za-z0-9]/.test(parsed.reference),
    detail: parsed.reference ?? 'sin referencia',
  });
  checks.push({
    code: 'REFERENCE_NOT_REUSED',
    ok: input.referenceAlreadyUsed !== true,
  });
  checks.push({
    code: 'AMOUNT_EXACT',
    ok:
      parsed.amount != null &&
      round2(parsed.amount) === round2(input.order.amount),
    detail: `${parsed.amount ?? 'n/d'} vs ${input.order.amount}`,
  });
  // El impuesto nunca puede ser el monto transferido.
  checks.push({
    code: 'TAX_NOT_AMOUNT',
    ok:
      parsed.tax == null ||
      parsed.amount == null ||
      round2(parsed.tax) !== round2(parsed.amount),
    detail: parsed.tax == null ? 'sin impuesto visible' : String(parsed.tax),
  });
  checks.push({
    code: 'DESTINATION_ACCOUNT',
    ok:
      suffixOk &&
      !!parsed.destinationAccount &&
      digits(parsed.destinationAccount).endsWith(configuredSuffix),
    detail: parsed.destinationAccount ?? 'sin cuenta destino',
  });

  const daysForward = input.daysForward ?? 0;
  const forwardToleranceMs = (input.forwardToleranceMinutes ?? 30) * 60_000;
  const maxAgeDays = input.maxReceiptAgeDays ?? 1;
  const offsetHours = input.utcOffsetHours ?? RECEIPT_UTC_OFFSET_HOURS;
  const occurredMs = parsed.occurredAt ? Date.parse(parsed.occurredAt) : NaN;
  // Regla normal: la transferencia es de **hoy o ayer** (en el calendario del
  // cliente, no en UTC). Un comprobante mas antiguo no activa solo: se queda
  // para revision humana.
  const oldestAllowed =
    startOfLocalDayUtc(now, offsetHours) - maxAgeDays * 86_400_000;
  checks.push({
    code: 'RECEIPT_RECENT',
    ok: Number.isFinite(occurredMs) && occurredMs >= oldestAllowed,
    detail:
      parsed.occurredAt ??
      `fecha no leida (se admite desde ${new Date(oldestAllowed).toISOString().slice(0, 10)})`,
  });
  // Y no puede venir del futuro: solo se tolera el desfase de relojes (30 min).
  const latestAllowed = now.getTime() + forwardToleranceMs;
  checks.push({
    code: 'RECEIPT_NOT_FUTURE',
    ok: Number.isFinite(occurredMs) && occurredMs <= latestAllowed,
    detail:
      parsed.occurredAt ??
      `fecha no leida (no puede ser posterior a ${new Date(latestAllowed).toISOString()})`,
  });
  // Y no puede ser anterior al dia en que se creo la orden ni futura.
  const orderDayStart = startOfLocalDayUtc(input.order.createdAt, offsetHours);
  const windowOk =
    Number.isFinite(occurredMs) &&
    occurredMs >= orderDayStart &&
    occurredMs <= latestAllowed + daysForward * 86_400_000;
  checks.push({
    code: 'DATE_COMPATIBLE_WITH_ORDER',
    ok: windowOk,
    detail: parsed.occurredAt ?? 'fecha no leida',
  });

  return {
    passed: checks.every((check) => check.ok),
    checks,
    parsed,
    validatedAt: now.toISOString(),
  };
}

/** Motivo legible para el administrador (una sola linea). */
export function describeBankFailure(validation: BankValidation) {
  const failed = validation.checks.filter((check) => !check.ok).map((check) => check.code);
  return failed.length ? failed.join(', ') : null;
}

function pickLabeledAmount(text: string, patterns: RegExp[]): number | null {
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (match?.[1]) {
      const value = toNumber(match[1]);
      if (value != null) return value;
    }
  }
  return null;
}

function pickAccount(text: string): string | null {
  const pattern =
    /(?:cuenta\s+destino|cuenta\s+de\s+destino|a\s+la\s+cuenta|cuenta\s+beneficiario|cuenta)\s*[:#]?\s*([\d\-\s]{6,30})/i;
  const match = pattern.exec(text);
  return match?.[1]?.trim() ?? null;
}

function firstMatch(text: string, patterns: RegExp[]): string | null {
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (match?.[1]) return match[1].trim();
  }
  return null;
}

/**
 * Convierte una cifra bancaria a numero sin adivinar de forma peligrosa.
 *
 * Acepta 5,000.00 | 5.000,00 | 5,000 | 5.000 | 5000 y devuelve `null` cuando
 * la cifra es ambigua (",," o ". ." o mezclas imposibles): es mejor mandar el
 * comprobante a revision que activar con una cantidad inventada.
 */
export function toNumber(raw: string): number | null {
  const cleaned = String(raw ?? '')
    .replace(/\s/g, '')
    .replace(/[^0-9.,]/g, '');
  if (!cleaned) return null;
  if ((cleaned.match(/,/g)?.length ?? 0) > 1 && (cleaned.match(/\./g)?.length ?? 0) > 1) {
    return null;
  }
  const lastComma = cleaned.lastIndexOf(',');
  const lastDot = cleaned.lastIndexOf('.');
  const lastSeparator = Math.max(lastComma, lastDot);
  if (lastSeparator === -1) {
    const only = Number(cleaned);
    return Number.isFinite(only) ? only : null;
  }
  const separator = cleaned[lastSeparator];
  const decimals = cleaned.length - lastSeparator - 1;
  const hasBoth = lastComma !== -1 && lastDot !== -1;
  // Un unico tipo de separador con **tres** digitos detras y algo delante es
  // separador de miles: 5.000 y 5,000 son cinco mil, no cinco. Con "0.500" la
  // parte entera es cero: es medio punto, no quinientos.
  const before = cleaned.slice(0, lastSeparator);
  const isGrouping =
    !hasBoth &&
    decimals === 3 &&
    lastSeparator > 0 &&
    before !== '0' &&
    /^\d{1,3}$/.test(before);
  let normalized: string;
  if (isGrouping) {
    normalized = cleaned.replace(/[.,]/g, '');
  } else if (hasBoth) {
    const thousands = separator === ',' ? /\./g : /,/g;
    normalized = cleaned.replace(thousands, '').replace(separator, '.');
  } else if (decimals >= 1 && decimals <= 2) {
    normalized = cleaned.replace(separator, '.');
  } else if (!hasBoth && decimals === 3 && before === '0') {
    // 0.500 y 0,500 son medio punto: parte entera cero, luego es decimal.
    normalized = cleaned.replace(separator, '.');
  } else {
    // Cuatro o mas "decimales" no existen en una moneda: cifra ambigua.
    return null;
  }
  if (!/^\d+(\.\d+)?$/.test(normalized)) return null;
  const value = Number(normalized);
  return Number.isFinite(value) ? value : null;
}

function parseDate(
  raw: string | null,
  utcOffsetHours: number = RECEIPT_UTC_OFFSET_HOURS,
): string | null {
  if (!raw) return null;
  // ISO (2026-11-17 14:35 o 2026-11-17T14:35:00).
  const iso =
    /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T\s]+(\d{1,2}):(\d{2})(?::\d{2})?)?/.exec(
      raw.trim(),
    );
  // dd/mm/aaaa y dd-mm-aaaa (con hora y a. m./p. m. opcionales).
  const short =
    /(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})(?:\s*[-–]?\s*(\d{1,2}):(\d{2})(?:\s*([ap])\.?\s*m\.?)?)?/i.exec(
      raw,
    );
  let day: number;
  let month: number;
  let year: number;
  let hour: number;
  let minute: number;
  if (iso) {
    year = Number(iso[1]);
    month = Number(iso[2]);
    day = Number(iso[3]);
    hour = iso[4] ? Number(iso[4]) : 12;
    minute = iso[5] ? Number(iso[5]) : 0;
  } else if (short) {
    day = Number(short[1]);
    month = Number(short[2]);
    year = Number(short[3]);
    if (year < 100) year += 2000;
    hour = short[4] ? Number(short[4]) : 12;
    minute = short[5] ? Number(short[5]) : 0;
    const meridiem = (short[6] ?? '').toLowerCase();
    if (meridiem === 'p' && hour < 12) hour += 12;
    if (meridiem === 'a' && hour === 12) hour = 0;
    // Si no puede ser dia/mes, se interpreta como mes/dia solo cuando el
    // primero es imposible como dia (13-31 en el segundo campo sigue siendo
    // dd/mm: el formato dominicano manda).
    if (day > 31 || month > 12) return null;
  } else {
    return null;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
    return null;
  }
  // La hora del comprobante es local: se convierte a UTC restando el desfase.
  const wallClock = Date.UTC(year, month - 1, day, hour, minute);
  const date = new Date(wallClock - utcOffsetHours * 3_600_000);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function digits(value: string | null | undefined) {
  return String(value ?? '').replace(/\D/g, '');
}

/**
 * Inicio del dia **local** (America/Santo_Domingo) de un instante UTC,
 * devuelto como instante UTC.
 */
export function startOfLocalDayUtc(
  instant: Date,
  utcOffsetHours: number = RECEIPT_UTC_OFFSET_HOURS,
): number {
  const shifted = new Date(instant.getTime() + utcOffsetHours * 3_600_000);
  const localMidnightAsUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  return localMidnightAsUtc - utcOffsetHours * 3_600_000;
}

function round2(value: number) {
  return Math.round(value * 100) / 100;
}
