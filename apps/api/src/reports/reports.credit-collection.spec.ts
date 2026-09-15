import { Prisma } from "@prisma/client";
import { ReportsService } from "./reports.service";

/**
 * Hardening de crédito — REPORTES (FASE 17).
 *
 * Contrato verificado:
 *   - VENTAS y UTILIDAD siguen DEVENGADAS por `saleDate` (no se toca).
 *   - EFECTIVO/TRANSFERENCIA representan dinero COBRADO EN EL PERÍODO:
 *       A) pago inicial de las ventas con `saleDate` en el período
 *       B) abonos (`SaleCreditPayment`) con `paidAt` real en el período
 *   Un abono del 10/09 no puede aparecer en el reporte del 01/09 ni volver a
 *   sumar venta/utilidad.
 */
describe("ReportsService · cobro de crédito por fecha real (hardening)", () => {
  const companyId = "11111111-1111-1111-1111-111111111111";
  const admin = { id: "user-admin", role: "ADMIN", companyId };
  const seller = { id: "user-seller", role: "VENDEDOR", companyId };

  function dec(value: number) {
    return new Prisma.Decimal(value);
  }

  function item(over: Record<string, unknown> = {}) {
    return {
      id: "item-1",
      subtotalSold: dec(1000),
      subtotalCost: dec(700),
      profit: dec(300),
      lineDiscountAmount: dec(0),
      taxableBase: dec(1000),
      taxAmount: dec(0),
      exemptAmount: dec(0),
      costUnitSnapshot: dec(700),
      qty: dec(1),
      product: null,
      ...over,
    };
  }

  function creditSale(over: Record<string, unknown> = {}) {
    return {
      id: "sale-1",
      companyId,
      userId: seller.id,
      customerId: null,
      customer: null,
      kind: "invoice",
      isDeleted: false,
      deletedAt: null,
      saleDate: new Date("2026-09-01T14:00:00.000Z"),
      totalSold: dec(1000),
      totalCost: dec(700),
      totalProfit: dec(300),
      commissionAmount: dec(30),
      discountAmount: dec(0),
      paymentMethod: "credit",
      paymentCashAmount: dec(0),
      paymentTransferAmount: dec(0),
      items: [item()],
      ...over,
    };
  }

  function creditPayment(over: Record<string, unknown> = {}) {
    return {
      saleId: "sale-1",
      companyId,
      saleUserId: seller.id,
      paidAt: new Date("2026-09-10T15:00:00.000Z"),
      cashAmount: dec(300),
      transferAmount: dec(0),
      amount: dec(300),
      sale: { items: [item()] },
      ...over,
    };
  }

  function harness(options: {
    sales?: Array<Record<string, unknown>>;
    creditPayments?: Array<Record<string, unknown>>;
    ledger?: Array<{ saleId: string; cash: number; transfer: number }>;
    refunds?: Array<Record<string, unknown>>;
  }) {
    const saleFindMany = jest.fn((args: { where: Record<string, any> }) => {
      const where = args?.where ?? {};
      if (where.kind === "refund") {
        return Promise.resolve(options.refunds ?? []);
      }
      if (where.kind === "invoice" && where.isDeleted === true) {
        return Promise.resolve([]);
      }
      const gte = where.saleDate?.gte as Date | undefined;
      const lt = where.saleDate?.lt as Date | undefined;
      return Promise.resolve(
        (options.sales ?? []).filter(
          (row) =>
            (!gte || (row.saleDate as Date) >= gte) &&
            (!lt || (row.saleDate as Date) < lt),
        ),
      );
    });

    const creditFindMany = jest.fn((args: { where: Record<string, any> }) => {
      const where = args?.where ?? {};
      const gte = where.paidAt?.gte as Date | undefined;
      const lt = where.paidAt?.lt as Date | undefined;
      return Promise.resolve(
        (options.creditPayments ?? []).filter(
          (row) =>
            (!gte || (row.paidAt as Date) >= gte) &&
            (!lt || (row.paidAt as Date) < lt) &&
            row.companyId === where.companyId &&
            (!where.sale?.userId || row.saleUserId === where.sale.userId),
        ),
      );
    });

    const groupBy = jest.fn().mockResolvedValue(
      (options.ledger ?? []).map((row) => ({
        saleId: row.saleId,
        _sum: {
          cashAmount: dec(row.cash),
          transferAmount: dec(row.transfer),
          amount: dec(row.cash + row.transfer),
        },
      })),
    );

    const prisma = {
      sale: { findMany: saleFindMany },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      cashMovement: { findMany: jest.fn().mockResolvedValue([]) },
      saleCreditPayment: { findMany: creditFindMany, groupBy },
    };
    return {
      service: new ReportsService(prisma as never),
      saleFindMany,
      creditFindMany,
      groupBy,
    };
  }

  it("CASO 1-4: el pago inicial va a la fecha de la venta y el abono a su fecha real", async () => {
    const { service } = harness({
      sales: [creditSale({ paymentCashAmount: dec(500) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      creditPayments: [creditPayment({ cashAmount: dec(300) })],
    });

    // Día de la venta: devengado 1,000; efectivo cobrado 200 (alta).
    const day1 = await service.salesOverview(admin as never, {
      from: "2026-09-01",
      to: "2026-09-01",
    });
    expect(day1.kpis.grossSales).toBeCloseTo(1000, 2);
    expect(day1.kpis.netProfit).toBeCloseTo(300, 2);
    expect(day1.kpis.cashIncome).toBeCloseTo(200, 2);
    expect(day1.kpis.creditPaymentsCash).toBeCloseTo(0, 2);

    // Día del abono: NO vuelve a sumar venta, utilidad ni ticket.
    const day10 = await service.salesOverview(admin as never, {
      from: "2026-09-10",
      to: "2026-09-10",
    });
    expect(day10.kpis.grossSales).toBeCloseTo(0, 2);
    expect(day10.kpis.netSales).toBeCloseTo(0, 2);
    expect(day10.kpis.netProfit).toBeCloseTo(0, 2);
    expect(day10.kpis.totalSales).toBe(0);
    expect(day10.kpis.cashIncome).toBeCloseTo(300, 2);
    expect(day10.kpis.creditPaymentsCash).toBeCloseTo(300, 2);
    expect(day10.kpis.creditPaymentsCount).toBe(1);

    // El lifetime cuadra con el acumulado de la venta (200 + 300 = 500).
    expect(
      day1.kpis.cashIncome + day10.kpis.cashIncome,
    ).toBeCloseTo(500, 2);
  });

  it("CASO 3: re-consultar el período de la venta NO retro-atribuye el abono posterior", async () => {
    const { service } = harness({
      sales: [creditSale({ paymentCashAmount: dec(500) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      creditPayments: [creditPayment({ cashAmount: dec(300) })],
    });

    // Primera lectura del 01/09 (antes del abono) y segunda lectura (después):
    // ambas deben dar el mismo efectivo del alta, 200.
    const before = await service.salesOverview(admin as never, {
      from: "2026-09-01",
      to: "2026-09-01",
    });
    const after = await service.salesOverview(admin as never, {
      from: "2026-09-01",
      to: "2026-09-01",
    });

    expect(before.kpis.cashIncome).toBeCloseTo(200, 2);
    expect(after.kpis.cashIncome).toBeCloseTo(200, 2);
    expect(after.kpis.cashIncome).not.toBeCloseTo(500, 2);
  });

  it("CASO 5-6: la transferencia no entra al efectivo y el abono mixto se separa por canal", async () => {
    const { service } = harness({
      sales: [
        creditSale({
          // Alta: 200 efectivo + 300 transferencia (acumulado del alta).
          paymentCashAmount: dec(200),
          paymentTransferAmount: dec(600),
        }),
      ],
      ledger: [{ saleId: "sale-1", cash: 0, transfer: 300 }],
      creditPayments: [
        creditPayment({
          cashAmount: dec(0),
          transferAmount: dec(300),
          amount: dec(300),
        }),
      ],
    });

    const day1 = await service.salesOverview(admin as never, {
      from: "2026-09-01",
      to: "2026-09-01",
    });
    expect(day1.kpis.cashIncome).toBeCloseTo(200, 2);
    expect(
      day1.paymentMethods.find((row) => row.method === "Transferencia")?.amount,
    ).toBeCloseTo(300, 2);

    const day10 = await service.salesOverview(admin as never, {
      from: "2026-09-10",
      to: "2026-09-10",
    });
    expect(day10.kpis.cashIncome).toBeCloseTo(0, 2);
    expect(day10.kpis.creditPaymentsTransfer).toBeCloseTo(300, 2);
    expect(
      day10.paymentMethods.find((row) => row.method === "Transferencia")
        ?.amount,
    ).toBeCloseTo(300, 2);
  });

  it("CASO 7: invariante rota se expone (sin recortar) y queda auditable", async () => {
    const { service } = harness({
      sales: [creditSale({ paymentCashAmount: dec(100) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      creditPayments: [creditPayment({ cashAmount: dec(300) })],
    });

    const day1 = await service.salesOverview(admin as never, {
      from: "2026-09-01",
      to: "2026-09-01",
    });
    const day10 = await service.salesOverview(admin as never, {
      from: "2026-09-10",
      to: "2026-09-10",
    });

    // El pago inicial derivado es negativo (100 - 300) y NO se recorta a 0.
    expect(day1.kpis.cashIncome).toBeCloseTo(-200, 2);
    expect(day10.kpis.cashIncome).toBeCloseTo(300, 2);
    // El lifetime sigue cuadrando con el acumulado persistido (100).
    expect(day1.kpis.cashIncome + day10.kpis.cashIncome).toBeCloseTo(100, 2);
    expect(day1.audit.paymentBreakdownViolations).toBe(1);
    expect(day1.audit.warnings).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: "payment_breakdown_invariant_violation",
        }),
      ]),
    );
  });

  it("CASO 8: una devolución afecta el devengado pero no inyecta efectivo (contrato vigente)", async () => {
    const { service } = harness({
      sales: [],
      refunds: [
        creditSale({
          id: "refund-1",
          kind: "refund",
          refundedSaleId: "sale-1",
          paymentMethod: "refund",
          paymentCashAmount: dec(-200),
          totalSold: dec(-200),
          totalCost: dec(-140),
          totalProfit: dec(-60),
          items: [
            item({
              subtotalSold: dec(-200),
              subtotalCost: dec(-140),
              profit: dec(-60),
            }),
          ],
        }),
      ],
      ledger: [],
      creditPayments: [],
    });

    const report = await service.salesOverview(admin as never, {
      from: "2026-09-01",
      to: "2026-09-01",
    });

    // La devolución resta del devengado…
    expect(report.kpis.returnedSales).toBeCloseTo(200, 2);
    expect(report.kpis.totalReturns).toBe(1);
    // …pero el carril de caja del reporte sigue siendo solo dinero COBRADO.
    expect(report.kpis.cashIncome).toBeCloseTo(0, 2);
    expect(report.audit.creditPaymentRows).toBe(0);
  });

  it("CASO 9-10: tenant isolation y semántica SELLER del filtro por usuario", async () => {
    const { service, creditFindMany, groupBy, saleFindMany } = harness({
      sales: [creditSale({ paymentCashAmount: dec(500) })],
      ledger: [{ saleId: "sale-1", cash: 300, transfer: 0 }],
      creditPayments: [
        creditPayment({ cashAmount: dec(300) }),
        creditPayment({
          cashAmount: dec(900),
          saleUserId: "otro-vendedor",
          saleId: "sale-2",
        }),
      ],
    });

    const report = await service.salesOverview(seller as never, {
      from: "2026-09-01",
      to: "2026-09-30",
    });

    // Solo el dinero del vendedor autenticado: 200 del alta + 300 del abono.
    // El abono de 900 de otro vendedor queda fuera (sin fuga entre vendedores).
    expect(report.kpis.cashIncome).toBeCloseTo(500, 2);
    expect(report.kpis.creditPaymentsCash).toBeCloseTo(300, 2);

    // Todas las consultas quedan acotadas al tenant.
    for (const call of saleFindMany.mock.calls) {
      expect(call[0].where.companyId).toBe(companyId);
    }
    for (const call of creditFindMany.mock.calls) {
      expect(call[0].where.companyId).toBe(companyId);
      // Semántica MANTENIDA (SELLER): el dinero se atribuye al vendedor dueño
      // de la venta, no al usuario que cobró el abono.
      expect(call[0].where.sale).toEqual({ userId: seller.id });
    }
    for (const call of groupBy.mock.calls) {
      expect(call[0].where.companyId).toBe(companyId);
    }
  });

  it("sin N+1: una sola lectura batched del ledger y una sola del ledger del período", async () => {
    const { service, creditFindMany, groupBy } = harness({
      sales: [
        creditSale({ id: "sale-1", paymentCashAmount: dec(300) }),
        creditSale({ id: "sale-2", paymentCashAmount: dec(200) }),
      ],
      ledger: [
        { saleId: "sale-1", cash: 300, transfer: 0 },
        { saleId: "sale-2", cash: 200, transfer: 0 },
      ],
      creditPayments: [creditPayment({ saleId: "sale-1", cashAmount: dec(100) })],
    });

    const report = await service.salesOverview(admin as never, {
      from: "2026-09-01",
      to: "2026-09-30",
    });

    expect(groupBy).toHaveBeenCalledTimes(1);
    expect(groupBy.mock.calls[0][0].where.saleId.in).toEqual(
      expect.arrayContaining(["sale-1", "sale-2"]),
    );
    expect(creditFindMany).toHaveBeenCalledTimes(1);
    expect(report.audit.creditPaymentRows).toBe(1);
    expect(report.kpis.creditPaymentsCash).toBeCloseTo(100, 2);
  });
});
