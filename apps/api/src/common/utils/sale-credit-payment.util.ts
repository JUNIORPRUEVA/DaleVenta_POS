import { Prisma } from "@prisma/client";
import type { PrismaService } from "../../prisma/prisma.service";

/**
 * Contrato de dinero de una venta a crédito (single source of truth).
 *
 * SEMÁNTICA CONGELADA (no cambiar sin migración/versionado):
 *
 * - `Sale.paymentCashAmount` / `Sale.paymentTransferAmount`
 *   = EFECTIVO / TRANSFERENCIA ACUMULADO (lifetime) retenido por la venta.
 *   Incluye el pago recibido AL CREAR (`create()`) más todos los abonos
 *   posteriores registrados por `addCreditPayment()`. Documentado en
 *   `docs/PRODUCT_SPEC.md` como "NET cash retained by the sale": caja, cierre
 *   de turno, reportes de caja y elegibilidad de gaveta lo consumen así.
 *
 * - `SaleCreditPayment` = LEDGER de eventos de abono con fecha real (`paidAt`),
 *   sesión de caja (`cashSessionId`), cobrador (`userId`) y monto por canal.
 *   Sirve para timeline/auditoría/atribución por fecha y turno. NUNCA debe
 *   volver a sumarse sobre `Sale.payment*` para reconstruir un total, porque
 *   ese total ya está acumulado en la venta: hacerlo cuenta el mismo peso dos
 *   veces (BUG histórico de caja y de reembolsos).
 *
 * CONSECUENCIA DE LECTURA:
 *   initialCash     = Sale.paymentCashAmount     - SUM(ledger.cashAmount)
 *   initialTransfer = Sale.paymentTransferAmount - SUM(ledger.transferAmount)
 *   cash de un turno/fecha = initial (atribuido al alta de la venta)
 *                          + ledger (atribuido a `paidAt` / `cashSessionId`)
 */

type MoneyLike = Prisma.Decimal | number | string | null | undefined;

/** Tolerancia de redondeo monetario (2 decimales). */
export const MONEY_EPSILON = new Prisma.Decimal("0.005");

export function toMoneyDecimal(value: MoneyLike): Prisma.Decimal {
  if (value == null) return new Prisma.Decimal(0);
  return new Prisma.Decimal(value as Prisma.Decimal.Value);
}

export interface CreditPaymentAmounts {
  cashAmount: MoneyLike;
  transferAmount: MoneyLike;
  amount?: MoneyLike;
}

export interface CreditPaymentLedgerTotals {
  cash: Prisma.Decimal;
  transfer: Prisma.Decimal;
  amount: Prisma.Decimal;
}

export function emptyCreditPaymentTotals(): CreditPaymentLedgerTotals {
  return {
    cash: new Prisma.Decimal(0),
    transfer: new Prisma.Decimal(0),
    amount: new Prisma.Decimal(0),
  };
}

/**
 * Suma el ledger de abonos de UNA venta. `amount` cae a cash + transfer cuando
 * el evento no lo trae (compatibilidad con filas legadas).
 */
export function sumCreditPaymentAmounts(
  payments: readonly CreditPaymentAmounts[],
): CreditPaymentLedgerTotals {
  return payments.reduce<CreditPaymentLedgerTotals>((acc, payment) => {
    const cash = toMoneyDecimal(payment.cashAmount);
    const transfer = toMoneyDecimal(payment.transferAmount);
    return {
      cash: acc.cash.plus(cash),
      transfer: acc.transfer.plus(transfer),
      amount: acc.amount.plus(
        payment.amount == null ? cash.plus(transfer) : toMoneyDecimal(payment.amount),
      ),
    };
  }, emptyCreditPaymentTotals());
}

export interface SalePaymentBreakdown {
  /** Efectivo neto recibido AL CREAR la venta (atribuible a su fecha/turno). */
  initialCash: Prisma.Decimal;
  /** Transferencia neta recibida AL CREAR la venta. */
  initialTransfer: Prisma.Decimal;
  /** Abonos en efectivo del ledger (atribuibles a su `paidAt`/sesión). */
  creditPaymentsCash: Prisma.Decimal;
  /** Abonos por transferencia del ledger. */
  creditPaymentsTransfer: Prisma.Decimal;
  /** Acumulado persistido en la venta (tomado tal cual de la BD). */
  cumulativeCash: Prisma.Decimal;
  cumulativeTransfer: Prisma.Decimal;
  /**
   * DATA INVARIANT VIOLATION: el ledger supera el acumulado de la venta.
   * Se expone (nunca se corrige con `max(0)`) para que sea detectable y
   * auditable. Un valor negativo en `initial*` es señal de datos corruptos.
   */
  invariantViolation: boolean;
}

/**
 * Deriva el desglose de dinero de una venta: pago inicial (creación) vs ledger
 * de abonos, a partir del acumulado persistido. NO recorta a cero: si el ledger
 * excede el acumulado, la diferencia negativa y `invariantViolation` quedan
 * visibles.
 */
export function deriveSalePaymentBreakdown(input: {
  cumulativeCash: MoneyLike;
  cumulativeTransfer: MoneyLike;
  creditPaymentsCash?: MoneyLike;
  creditPaymentsTransfer?: MoneyLike;
}): SalePaymentBreakdown {
  const cumulativeCash = toMoneyDecimal(input.cumulativeCash).toDecimalPlaces(2);
  const cumulativeTransfer = toMoneyDecimal(
    input.cumulativeTransfer,
  ).toDecimalPlaces(2);
  const creditPaymentsCash = toMoneyDecimal(
    input.creditPaymentsCash,
  ).toDecimalPlaces(2);
  const creditPaymentsTransfer = toMoneyDecimal(
    input.creditPaymentsTransfer,
  ).toDecimalPlaces(2);

  return {
    initialCash: cumulativeCash.minus(creditPaymentsCash).toDecimalPlaces(2),
    initialTransfer: cumulativeTransfer
      .minus(creditPaymentsTransfer)
      .toDecimalPlaces(2),
    creditPaymentsCash,
    creditPaymentsTransfer,
    cumulativeCash,
    cumulativeTransfer,
    invariantViolation:
      creditPaymentsCash.minus(cumulativeCash).gt(MONEY_EPSILON) ||
      creditPaymentsTransfer.minus(cumulativeTransfer).gt(MONEY_EPSILON),
  };
}

/**
 * Ledger por venta en UNA query batched (sin N+1): `saleId IN (...)`.
 * Multi-tenant estricto: siempre filtra por `companyId` del usuario autenticado
 * además de los ids recibidos.
 */
export async function creditPaymentTotalsBySaleId(
  prisma: Pick<PrismaService, "saleCreditPayment">,
  params: { companyId: string; saleIds: readonly string[] },
): Promise<Map<string, CreditPaymentLedgerTotals>> {
  const totals = new Map<string, CreditPaymentLedgerTotals>();
  const saleIds = Array.from(new Set(params.saleIds.filter(Boolean)));
  if (saleIds.length === 0) return totals;

  const rows = await prisma.saleCreditPayment.groupBy({
    by: ["saleId"],
    where: { companyId: params.companyId, saleId: { in: saleIds } },
    _sum: { cashAmount: true, transferAmount: true, amount: true },
  });

  for (const row of rows) {
    totals.set(row.saleId, {
      cash: toMoneyDecimal(row._sum.cashAmount).toDecimalPlaces(2),
      transfer: toMoneyDecimal(row._sum.transferAmount).toDecimalPlaces(2),
      amount: toMoneyDecimal(row._sum.amount).toDecimalPlaces(2),
    });
  }
  return totals;
}
