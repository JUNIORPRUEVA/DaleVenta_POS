import { Prisma } from '@prisma/client';

/**
 * Como leer una orden sin ambiguedad desde soporte.
 *
 * El cliente **no** tiene que escribir la referencia en el banco: la orden ya
 * existe antes de transferir y el comprobante queda colgado de su `id`. Esto
 * describe la operacion para que el agente sepa que esta pagando sin preguntar.
 */
export type OrderOperationType =
  | 'RENEWAL'
  | 'UPGRADE'
  | 'DOWNGRADE'
  | 'PURCHASE';

export type OrderOperation = {
  operationType: OrderOperationType;
  /** Plan que tenia la empresa cuando creo la orden. */
  companyPlanCode: string | null;
  /** Diferencia entre lo que vale el pedido y lo que se debe transferir. */
  creditApplied: number;
  monthlyPrice: number | null;
  subtotal: number;
};

export function describeOrderOperation(input: {
  companyPlanCode: string | null;
  companyPlanPrice: number | null;
  orderPlanCode: string;
  orderPlanPrice: number | null;
  months: number;
  amount: number;
}): OrderOperation {
  const companyCode = (input.companyPlanCode ?? '').trim().toLowerCase();
  const orderCode = input.orderPlanCode.trim().toLowerCase();
  const monthlyPrice = input.orderPlanPrice;
  const subtotal =
    monthlyPrice == null ? round2(input.amount) : round2(monthlyPrice * input.months);
  // Lo que no se transfiere es saldo a favor (tiempo no consumido al mejorar).
  const creditApplied = round2(Math.max(0, subtotal - input.amount));

  let operationType: OrderOperationType;
  if (!companyCode) {
    operationType = 'PURCHASE';
  } else if (companyCode === orderCode) {
    operationType = 'RENEWAL';
  } else if (
    input.companyPlanPrice != null &&
    monthlyPrice != null &&
    monthlyPrice > input.companyPlanPrice
  ) {
    operationType = 'UPGRADE';
  } else if (
    input.companyPlanPrice != null &&
    monthlyPrice != null &&
    monthlyPrice < input.companyPlanPrice
  ) {
    operationType = 'DOWNGRADE';
  } else {
    // Mismo precio, otro plan: es un cambio, se trata como mejora a efectos
    // de soporte (no hay saldo ni cargo distinto).
    operationType = 'UPGRADE';
  }
  return {
    operationType,
    companyPlanCode: companyCode || null,
    creditApplied,
    monthlyPrice,
    subtotal,
  };
}

/**
 * Datos que el agente puede leer del comprobante. Son **sugerencias**: no
 * cambian el estado de la orden ni activan nada. La aprobacion exige comprobar
 * que el dinero llego de verdad.
 */
export type EvidenceInsights = {
  receivedOn: string | null;
  amount: number | null;
  bank: string | null;
  bankReference: string | null;
  confidence: number | null;
  notes: string | null;
  source: string;
};

const MAX_TEXT = 120;
const MAX_REFERENCE = 64;
const MAX_NOTES = 500;
const MAX_AMOUNT = 10_000_000;

export function normalizeEvidenceInsights(
  raw: Record<string, unknown>,
): EvidenceInsights {
  const allowed = [
    'receivedOn',
    'amount',
    'bank',
    'bankReference',
    'confidence',
    'notes',
    'source',
  ];
  for (const key of Object.keys(raw)) {
    if (!allowed.includes(key)) {
      throw new InvalidInsightsError(`unsupported_field:${key}`);
    }
  }

  const receivedOn = optionalString(raw.receivedOn, 40);
  if (receivedOn != null) {
    const parsed = new Date(receivedOn);
    if (Number.isNaN(parsed.getTime())) {
      throw new InvalidInsightsError('invalid_received_on');
    }
    const skew = Math.abs(Date.now() - parsed.getTime());
    if (skew > 400 * 86_400_000) {
      throw new InvalidInsightsError('received_on_out_of_range');
    }
  }

  let amount: number | null = null;
  if (raw.amount !== undefined && raw.amount !== null && raw.amount !== '') {
    const value =
      typeof raw.amount === 'string'
        ? Number(raw.amount.replace(/[^0-9.\-]/g, ''))
        : Number(raw.amount);
    if (!Number.isFinite(value) || value <= 0 || value > MAX_AMOUNT) {
      throw new InvalidInsightsError('invalid_amount');
    }
    amount = round2(value);
  }

  let confidence: number | null = null;
  if (raw.confidence !== undefined && raw.confidence !== null && raw.confidence !== '') {
    const value = Number(raw.confidence);
    if (!Number.isFinite(value) || value < 0 || value > 1) {
      throw new InvalidInsightsError('invalid_confidence');
    }
    confidence = Number(value.toFixed(3));
  }

  return {
    receivedOn,
    amount,
    bank: optionalString(raw.bank, MAX_TEXT),
    bankReference: optionalString(raw.bankReference, MAX_REFERENCE),
    confidence,
    notes: optionalString(raw.notes, MAX_NOTES),
    source: optionalString(raw.source, 32) ?? 'appyra-crm',
  };
}

export class InvalidInsightsError extends Error {}

function optionalString(value: unknown, max: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw new InvalidInsightsError('invalid_text');
  const trimmed = value.trim();
  if (!trimmed) return null;
  // Sin caracteres de control: esto acaba en el panel de soporte.
  if (/[\u0000-\u001f\u007f]/.test(trimmed)) {
    throw new InvalidInsightsError('invalid_text');
  }
  if (trimmed.length > max) throw new InvalidInsightsError('text_too_long');
  return trimmed;
}

function round2(value: number) {
  return Math.round(value * 100) / 100;
}

export type OrderWithEvidences = Prisma.LicensePaymentOrderGetPayload<{
  include: { evidences: true };
}>;

/**
 * Describe cada orden de una tanda. Una sola consulta de precios para todas:
 * el panel de soporte no hace N+1 por cada comprobante.
 */
export async function describeOrders(
  db: {
    licensePlan: {
      findMany: (args: {
        where: { code: { in: string[] } };
        select: { code: true; monthlyPrice: true };
      }) => Promise<Array<{ code: string; monthlyPrice: Prisma.Decimal }>>;
    };
  },
  rows: Array<{
    id: string;
    planCode: string;
    months: number;
    amount: Prisma.Decimal;
    company?: { planCode: string | null } | null;
  }>,
): Promise<Map<string, OrderOperation>> {
  const codes = Array.from(
    new Set(
      rows
        .flatMap((row) => [
          row.planCode.trim().toLowerCase(),
          (row.company?.planCode ?? '').trim().toLowerCase(),
        ])
        .filter((code) => code.length > 0),
    ),
  );
  const plans = codes.length
    ? await db.licensePlan.findMany({
        where: { code: { in: codes } },
        select: { code: true, monthlyPrice: true },
      })
    : [];
  const prices = new Map(
    plans.map((plan) => [plan.code.trim().toLowerCase(), plan.monthlyPrice.toNumber()]),
  );

  const result = new Map<string, OrderOperation>();
  for (const row of rows) {
    const companyCode = (row.company?.planCode ?? '').trim().toLowerCase();
    const orderCode = row.planCode.trim().toLowerCase();
    result.set(
      row.id,
      describeOrderOperation({
        companyPlanCode: companyCode || null,
        companyPlanPrice: prices.get(companyCode) ?? null,
        orderPlanCode: orderCode,
        orderPlanPrice: prices.get(orderCode) ?? null,
        months: row.months,
        amount: row.amount.toNumber(),
      }),
    );
  }
  return result;
}
