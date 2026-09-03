import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";

export interface CashTenderInput {
  /** Efectivo real entregado por el cliente (tender). Nulo/ausente = no
   *  disponible (clientes/ventas legadas que nunca almacenaron el tender). */
  cashReceived?: number | null;
  /** Devuelta enviada por el cliente (opcional). Se valida contra la derivada. */
  changeAmount?: number | null;
  /** Efectivo NETO aplicado/retenido por la venta (paymentCashAmount). */
  paymentCashAmount: Prisma.Decimal;
}

export interface CashTenderResult {
  cashReceived: Prisma.Decimal | null;
  changeAmount: Prisma.Decimal | null;
}

/**
 * Deriva y valida el tender (efectivo recibido) y la devuelta de una venta.
 *
 * Invariante protegida (nunca se redefine paymentCashAmount):
 *   DEVUELTA = round2(max(0, EFECTIVO RECIBIDO - EFECTIVO NETO))
 *   EFECTIVO RECIBIDO - DEVUELTA == paymentCashAmount (neto retenido)
 *
 * Cuando cashReceived no está disponible (ventas legadas) se conserva NULL
 * para no fabricar un tender histórico inexistente. Lanza BadRequestException
 * en combinaciones imposibles.
 */
export function deriveCashTenderChange(
  input: CashTenderInput,
): CashTenderResult {
  const { cashReceived, changeAmount, paymentCashAmount } = input;
  if (cashReceived === undefined || cashReceived === null) {
    return { cashReceived: null, changeAmount: null };
  }

  const requestedCashReceived = new Prisma.Decimal(
    cashReceived,
  ).toDecimalPlaces(2);
  if (requestedCashReceived.lt(0)) {
    throw new BadRequestException(
      "El efectivo recibido no puede ser negativo.",
    );
  }
  if (requestedCashReceived.lt(paymentCashAmount)) {
    throw new BadRequestException(
      "El efectivo recibido no puede ser menor que el efectivo neto aplicado a la venta.",
    );
  }

  const derivedChange = Prisma.Decimal.max(
    requestedCashReceived.minus(paymentCashAmount),
    new Prisma.Decimal(0),
  ).toDecimalPlaces(2);

  if (changeAmount !== undefined && changeAmount !== null) {
    const requestedChange = new Prisma.Decimal(changeAmount).toDecimalPlaces(2);
    if (requestedChange.lt(0)) {
      throw new BadRequestException("La devuelta no puede ser negativa.");
    }
    if (requestedChange.greaterThan(requestedCashReceived)) {
      throw new BadRequestException(
        "La devuelta no puede superar el efectivo recibido.",
      );
    }
    if (requestedChange.minus(derivedChange).abs().greaterThan(0.005)) {
      throw new BadRequestException(
        "La devuelta no coincide con el efectivo recibido/neto de la venta.",
      );
    }
  }

  return {
    cashReceived: requestedCashReceived,
    changeAmount: derivedChange,
  };
}
