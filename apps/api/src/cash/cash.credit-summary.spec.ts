import { Prisma } from "@prisma/client";
import { CashService } from "./cash.service";

/**
 * Hardening de crédito — CAJA (FASE 15).
 *
 * Contrato verificado:
 *   `Sale.paymentCashAmount/paymentTransferAmount` son ACUMULADOS (pago inicial
 *   + abonos). Por eso el resumen del turno compone el efectivo así:
 *
 *     salesCashTotal          = efectivo recibido AL CREAR las ventas del turno
 *                               (= acumulado - ledger lifetime de esa venta)
 *     creditPaymentsCashTotal = abonos en efectivo cobrados EN ESTE TURNO
 *                               (`SaleCreditPayment.cashSessionId` del turno)
 *     expectedCash            = apertura + salesCashTotal
 *                               + creditPaymentsCashTotal - devoluciones
 *                               + entradas manuales - salidas manuales
 *
 * REGLA: un mismo peso nunca puede aparecer dos veces en caja.
 */
describe("CashService · crédito y abonos (hardening)", () => {
  const companyId = "11111111-1111-1111-1111-111111111111";

  function decimal(value: number) {
    return new Prisma.Decimal(value);
  }

  function sale(over: Record<string, unknown> = {}) {
    return {
      id: "sale-1",
      totalSold: decimal(1000),
      totalProfit: decimal(300),
      paymentMethod: "credit",
      paymentCashAmount: decimal(0),
      paymentTransferAmount: decimal(0),
      creditAmount: decimal(1000),
      creditBalance: decimal(1000),
      isDeleted: false,
      kind: "invoice",
      items: [],
      ...over,
    };
  }

  function creditPayment(over: Record<string, unknown> = {}) {
    return {
      cashAmount: decimal(0),
      transferAmount: decimal(0),
      amount: decimal(0),
      ...over,
    };
  }

  function harness(options: {
    sales?: Array<Record<string, unknown>>;
    sessionCreditPayments?: Array<Record<string, unknown>>;
    ledger?: Array<{ saleId: string; cash: number; transfer: number }>;
    movements?: Array<Record<string, unknown>>;
    initialAmount?: number;
  }) {
    const groupBy = jest.fn().mockResolvedValue(
      (options.ledger ?? []).map((row) => ({
        saleId: row.saleId,
        _sum: {
          cashAmount: decimal(row.cash),
          transferAmount: decimal(row.transfer),
          amount: decimal(row.cash + row.transfer),
        },
      })),
    );
    const prisma = {
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: "shift-1",
          initialAmount: decimal(options.initialAmount ?? 0),
        }),
      },
      sale: { findMany: jest.fn().mockResolvedValue(options.sales ?? []) },
      cashMovement: {
        findMany: jest.fn().mockResolvedValue(options.movements ?? []),
      },
      saleCreditPayment: {
        findMany: jest
          .fn()
          .mockResolvedValue(options.sessionCreditPayments ?? []),
        groupBy,
      },
    };
    const service = new CashService(
      prisma as never,
      { emitCompany: jest.fn() } as never,
    );
    return { service, prisma, groupBy };
  }

  it("CASO A: venta a crédito sin pago inicial + abono en efectivo del mismo turno cuenta UNA vez", async () => {
    const { service } = harness({
      sales: [sale({ paymentCashAmount: decimal(300) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      sessionCreditPayments: [
        creditPayment({ cashAmount: decimal(300), amount: decimal(300) }),
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    // El efectivo del alta es 0 (todo quedó a crédito); el abono entra por su
    // propio carril. Antes se reportaban 600 (300 + 300).
    expect(summary.salesCashTotal).toBeCloseTo(0, 2);
    expect(summary.creditPaymentsCashTotal).toBeCloseTo(300, 2);
    expect(summary.expectedCash).toBeCloseTo(300, 2);
    expect(summary.creditPaymentCash).toBeCloseTo(300, 2);
    expect(summary.creditAbonos).toBeCloseTo(300, 2);
    expect(summary.creditInitialCash).toBeCloseTo(0, 2);
  });

  it("CASO B: pago inicial en efectivo + abono del mismo turno no se suman dos veces", async () => {
    const { service } = harness({
      sales: [sale({ paymentCashAmount: decimal(500) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      sessionCreditPayments: [
        creditPayment({ cashAmount: decimal(300), amount: decimal(300) }),
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    expect(summary.salesCashTotal).toBeCloseTo(200, 2);
    expect(summary.creditPaymentsCashTotal).toBeCloseTo(300, 2);
    expect(summary.creditInitialCash).toBeCloseTo(200, 2);
    // Efectivo realmente recibido: 200 + 300 = 500. Nunca 800 ni 1,000.
    expect(summary.expectedCash).toBeCloseTo(500, 2);
  });

  it("CASO C: venta de un turno anterior + abono en el turno actual", async () => {
    const { service } = harness({
      sales: [],
      sessionCreditPayments: [
        creditPayment({ cashAmount: decimal(300), amount: decimal(300) }),
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    expect(summary.salesCashTotal).toBeCloseTo(0, 2);
    expect(summary.creditPaymentsCashTotal).toBeCloseTo(300, 2);
    expect(summary.expectedCash).toBeCloseTo(300, 2);
    expect(summary.totalTickets).toBe(0);
  });

  it("CASO D: abono por transferencia no aumenta el efectivo físico", async () => {
    const { service } = harness({
      sales: [
        sale({
          paymentTransferAmount: decimal(300),
          creditAmount: decimal(1000),
        }),
      ],
      ledger: [{ saleId: "sale-1", cash: 0, transfer: 300 }],
      sessionCreditPayments: [
        creditPayment({ transferAmount: decimal(300), amount: decimal(300) }),
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    expect(summary.salesTransferTotal).toBeCloseTo(0, 2);
    expect(summary.creditPaymentTransfer).toBeCloseTo(300, 2);
    expect(summary.creditPaymentsCashTotal).toBeCloseTo(0, 2);
    expect(summary.expectedCash).toBeCloseTo(0, 2);
  });

  it("CASO E: pago mixto (efectivo + transferencia) al crear la venta", async () => {
    const { service, groupBy } = harness({
      sales: [
        sale({
          paymentMethod: "mixed",
          paymentCashAmount: decimal(200),
          paymentTransferAmount: decimal(300),
          creditAmount: decimal(0),
          creditBalance: decimal(0),
        }),
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    expect(summary.salesCashTotal).toBeCloseTo(200, 2);
    expect(summary.salesTransferTotal).toBeCloseTo(300, 2);
    expect(summary.creditPaymentsCashTotal).toBeCloseTo(0, 2);
    expect(summary.expectedCash).toBeCloseTo(200, 2);
    // Sin ventas a crédito no se consulta el ledger (0 queries extra).
    expect(groupBy).not.toHaveBeenCalled();
  });

  it("CASO F: mantiene la política vigente de anulación documentada (FASE 19)", async () => {
    const { service } = harness({
      sales: [
        sale({
          isDeleted: true,
          paymentCashAmount: decimal(500),
        }),
      ],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    // Comportamiento vigente y NO modificado por este hardening: la venta
    // anulada revierte su efectivo ACUMULADO (inicial + abonos) en el turno de
    // la anulación, y no cuenta como ticket.
    expect(summary.refundsCash).toBeCloseTo(500, 2);
    expect(summary.totalTickets).toBe(0);
    expect(summary.expectedCash).toBeCloseTo(-500, 2);
  });

  it("CASO G: efectivo esperado exacto con fondo, entradas y salidas manuales", async () => {
    const { service } = harness({
      initialAmount: 1000,
      sales: [
        sale({ id: "sale-credit", paymentCashAmount: decimal(300) }),
        sale({
          id: "sale-cash",
          paymentMethod: "cash",
          paymentCashAmount: decimal(250),
          creditAmount: decimal(0),
          creditBalance: decimal(0),
        }),
      ],
      ledger: [{ saleId: "sale-credit", cash: 300, transfer: 0 }],
      sessionCreditPayments: [
        creditPayment({ cashAmount: decimal(300), amount: decimal(300) }),
      ],
      movements: [
        { type: "IN", amount: decimal(500), movementType: "expense", affectsProfit: true },
        { type: "OUT", amount: decimal(200), movementType: "expense", affectsProfit: true },
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    expect(summary.salesCashTotal).toBeCloseTo(250, 2);
    expect(summary.creditPaymentsCashTotal).toBeCloseTo(300, 2);
    expect(summary.cashInManual).toBeCloseTo(500, 2);
    expect(summary.cashOutManual).toBeCloseTo(200, 2);
    expect(summary.expectedCash).toBeCloseTo(1850, 2);
  });

  it("CASO H: expone abonos y efectivo del alta por carriles separados", async () => {
    const { service } = harness({
      initialAmount: 100,
      sales: [sale({ paymentCashAmount: decimal(400) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      sessionCreditPayments: [
        creditPayment({ cashAmount: decimal(150), amount: decimal(150) }),
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    // Alta 100 (400 acumulado - 300 de abonos previos) + abono del turno 150.
    expect(summary.salesCashTotal).toBeCloseTo(100, 2);
    expect(summary.creditPaymentsCashTotal).toBeCloseTo(150, 2);
    expect(summary.salesCashTotal + summary.creditPaymentsCashTotal).toBeCloseTo(
      250,
      2,
    );
    expect(summary.expectedCash).toBeCloseTo(
      summary.openingAmount +
        summary.salesCashTotal +
        summary.creditPaymentsCashTotal -
        summary.refundsCash +
        summary.cashInManual -
        summary.cashOutManual,
      2,
    );
    expect(summary.paymentBreakdownViolations).toBe(0);
  });

  it("aislamiento multiempresa: todas las lecturas van filtradas por companyId", async () => {
    const { service, prisma, groupBy } = harness({
      sales: [sale({ paymentCashAmount: decimal(300) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      sessionCreditPayments: [
        creditPayment({ cashAmount: decimal(300), amount: decimal(300) }),
      ],
    });

    await service.buildSummaryForSession("shift-1", companyId);

    expect(prisma.sale.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId }),
      }),
    );
    expect(prisma.cashMovement.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId }),
      }),
    );
    expect(prisma.saleCreditPayment.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId, cashSessionId: "shift-1" }),
      }),
    );
    expect(groupBy).toHaveBeenCalledTimes(1);
    expect(groupBy.mock.calls[0][0].where).toEqual(
      expect.objectContaining({ companyId }),
    );
  });

  it("una sola query batched para el ledger (sin N+1 por venta)", async () => {
    const { service, groupBy } = harness({
      sales: [
        sale({ id: "sale-1", paymentCashAmount: decimal(300) }),
        sale({ id: "sale-2", paymentCashAmount: decimal(100) }),
        sale({ id: "sale-3", paymentCashAmount: decimal(0) }),
      ],
      ledger: [
        { saleId: "sale-1", cash: 300, transfer: 0 },
        { saleId: "sale-2", cash: 100, transfer: 0 },
      ],
    });

    const summary = await service.buildSummaryForSession("shift-1", companyId);

    expect(groupBy).toHaveBeenCalledTimes(1);
    expect(groupBy.mock.calls[0][0].where.saleId.in).toHaveLength(3);
    expect(summary.salesCashTotal).toBeCloseTo(0, 2);
    expect(summary.expectedCash).toBeCloseTo(0, 2);
  });
});
