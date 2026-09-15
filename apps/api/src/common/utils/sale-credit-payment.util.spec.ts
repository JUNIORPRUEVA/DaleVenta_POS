import { Prisma } from "@prisma/client";
import {
  creditPaymentTotalsBySaleId,
  deriveSalePaymentBreakdown,
  sumCreditPaymentAmounts,
  toMoneyDecimal,
} from "./sale-credit-payment.util";

/**
 * Hardening de crédito — INVARIANTES de dinero (FASE 4 / 14).
 *
 * Invariante protegida (una sola fuente de verdad):
 *   Sale.paymentCashAmount     = initialCash     + Σ ledger.cashAmount
 *   Sale.paymentTransferAmount = initialTransfer + Σ ledger.transferAmount
 *
 * El ledger NUNCA se suma sobre el acumulado para reconstruir un total: hacerlo
 * cuenta el mismo peso dos veces (caja y reembolsos).
 */
describe("sale-credit-payment.util · invariantes de dinero", () => {
  const companyId = "11111111-1111-1111-1111-111111111111";

  function dec(value: number | string) {
    return new Prisma.Decimal(value);
  }

  it("deriva el pago inicial restando el ledger del acumulado", () => {
    const breakdown = deriveSalePaymentBreakdown({
      cumulativeCash: dec(500),
      cumulativeTransfer: dec(150),
      creditPaymentsCash: dec(300),
      creditPaymentsTransfer: dec(150),
    });

    expect(breakdown.initialCash.toString()).toBe("200");
    expect(breakdown.initialTransfer.toString()).toBe("0");
    expect(breakdown.invariantViolation).toBe(false);
    // El acumulado se devuelve tal cual lo entrega la base de datos.
    expect(breakdown.cumulativeCash.toString()).toBe("500");
    expect(breakdown.cumulativeTransfer.toString()).toBe("150");
  });

  it("mantiene la invariante initial + ledger = cumulative", () => {
    const breakdown = deriveSalePaymentBreakdown({
      cumulativeCash: dec("1234.56"),
      cumulativeTransfer: dec("78.90"),
      creditPaymentsCash: dec("1000.06"),
      creditPaymentsTransfer: dec("78.90"),
    });

    expect(
      breakdown.initialCash.plus(breakdown.creditPaymentsCash).toString(),
    ).toBe(breakdown.cumulativeCash.toString());
    expect(
      breakdown.initialTransfer
        .plus(breakdown.creditPaymentsTransfer)
        .toString(),
    ).toBe(breakdown.cumulativeTransfer.toString());
    expect(breakdown.invariantViolation).toBe(false);
  });

  it("expone la violación de invariante sin recortar a cero", () => {
    const breakdown = deriveSalePaymentBreakdown({
      cumulativeCash: dec(100),
      cumulativeTransfer: dec(0),
      creditPaymentsCash: dec(300),
      creditPaymentsTransfer: dec(0),
    });

    // Nunca se maquilla con max(0): el valor negativo es la señal.
    expect(breakdown.initialCash.toString()).toBe("-200");
    expect(breakdown.invariantViolation).toBe(true);
  });

  it("tolera el redondeo monetario de 2 decimales sin marcar falsos positivos", () => {
    const breakdown = deriveSalePaymentBreakdown({
      cumulativeCash: dec("0.01"),
      cumulativeTransfer: dec(0),
      creditPaymentsCash: dec("0.01"),
      creditPaymentsTransfer: dec(0),
    });

    expect(breakdown.initialCash.toString()).toBe("0");
    expect(breakdown.invariantViolation).toBe(false);
  });

  it("suma el ledger por canal y cae a cash + transfer cuando `amount` falta", () => {
    const totals = sumCreditPaymentAmounts([
      { cashAmount: dec(100), transferAmount: dec(0) },
      { cashAmount: dec(0), transferAmount: dec(50) },
      { cashAmount: dec(25), transferAmount: dec(25), amount: dec(50) },
    ]);

    expect(totals.cash.toString()).toBe("125");
    expect(totals.transfer.toString()).toBe("75");
    expect(totals.amount.toString()).toBe("200");
  });

  it("normaliza valores nulos y de tipo number/string", () => {
    expect(toMoneyDecimal(null).toString()).toBe("0");
    expect(toMoneyDecimal(undefined).toString()).toBe("0");
    expect(toMoneyDecimal(10.5).toString()).toBe("10.5");
    expect(toMoneyDecimal("10.50").toString()).toBe("10.5");
    expect(toMoneyDecimal(dec("3.33")).toString()).toBe("3.33");
  });

  it("una sola query batched por venta (sin N+1) y filtrada por companyId", async () => {
    const groupBy = jest.fn().mockResolvedValue([
      {
        saleId: "sale-1",
        _sum: {
          cashAmount: dec(300),
          transferAmount: dec(0),
          amount: dec(300),
        },
      },
      {
        saleId: "sale-2",
        _sum: {
          cashAmount: dec(0),
          transferAmount: dec(150),
          amount: dec(150),
        },
      },
    ]);

    const totals = await creditPaymentTotalsBySaleId(
      { saleCreditPayment: { groupBy } } as never,
      {
        companyId,
        saleIds: ["sale-1", "sale-2", "sale-1", ""],
      },
    );

    expect(groupBy).toHaveBeenCalledTimes(1);
    expect(groupBy.mock.calls[0][0].where).toEqual({
      companyId,
      saleId: { in: ["sale-1", "sale-2"] },
    });
    expect(totals.get("sale-1")?.cash.toString()).toBe("300");
    expect(totals.get("sale-2")?.transfer.toString()).toBe("150");
  });

  it("sin ids no consulta la base de datos", async () => {
    const groupBy = jest.fn();

    const totals = await creditPaymentTotalsBySaleId(
      { saleCreditPayment: { groupBy } } as never,
      { companyId, saleIds: [] },
    );

    expect(groupBy).not.toHaveBeenCalled();
    expect(totals.size).toBe(0);
  });
});
