import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { ReportsService } from "./reports.service";

/**
 * CONTRATO CANÓNICO DE REPORTES (congelado).
 *
 * Reportes > Ventas es DESEMPEÑO NETO DE VENTAS (state-aware), no flujo de caja:
 *   - Cada venta del período (por `saleDate`) aporta su CONTRIBUCIÓN REMANENTE:
 *     snapshot histórico menos la parte devuelta (proporcional a la cantidad
 *     devuelta), sin importar cuándo ocurrió la devolución.
 *   - Una venta totalmente devuelta aporta 0 (NUNCA -monto).
 *   - Los documentos `kind=refund` no aportan jamás al desempeño.
 *   - Ventas canceladas/eliminadas aportan 0.
 *   - ventas netas   = bruto del período - devoluciones
 *   - utilidad bruta = ventas netas - costo neto (snapshot histórico)
 *   - utilidad neta  = utilidad bruta - gastos que afectan utilidad
 *   - tickets: ACTIVE 1, PARTIALLY_RETURNED 1, FULLY_RETURNED/CANCELLED 0.
 * Ver docs/PRODUCT_SPEC.md.
 */
describe("ReportsService", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  function serviceWith(prisma: Record<string, unknown>) {
    return new ReportsService(prisma as never);
  }

  function decimal(value: number) {
    return new Prisma.Decimal(value);
  }

  function item(over: Record<string, unknown> = {}) {
    return {
      id: "item-1",
      productId: "p1",
      productSource: "LOCAL",
      sourceProductId: null,
      productNameSnapshot: "Producto 1",
      inventoryTrackedSnapshot: true,
      qty: decimal(1),
      priceSoldUnit: decimal(100),
      grossAmount: decimal(100),
      lineDiscountAmount: decimal(0),
      costUnitSnapshot: decimal(60),
      subtotalSold: decimal(100),
      subtotalCost: decimal(60),
      profit: decimal(40),
      taxableBase: decimal(100),
      taxRate: decimal(0),
      taxAmount: decimal(0),
      exemptAmount: decimal(0),
      unitCodeSnapshot: "UNIT",
      unitNameSnapshot: "Unidad",
      unitSymbolSnapshot: "u",
      unitPrecisionSnapshot: 0,
      product: null,
      ...over,
    };
  }

  function sale(over: Record<string, unknown> = {}) {
    return {
      id: "sale-1",
      companyId: user.companyId,
      userId: user.id,
      customerId: null,
      customer: null,
      kind: "invoice",
      isDeleted: false,
      deletedAt: null,
      saleDate: new Date("2026-08-10T12:00:00.000Z"),
      paymentMethod: "cash",
      totalSold: decimal(100),
      totalCost: decimal(60),
      totalProfit: decimal(40),
      discountAmount: decimal(0),
      commissionAmount: decimal(4),
      paymentCashAmount: decimal(100),
      paymentTransferAmount: decimal(0),
      items: [item()],
      ...over,
    };
  }

  function cashMovement(over: Record<string, unknown> = {}) {
    return {
      id: "cash-1",
      companyId: user.companyId,
      userId: user.id,
      type: "OUT",
      movementType: "expense",
      amount: decimal(100),
      affectsProfit: true,
      createdAt: new Date("2026-08-10T13:00:00.000Z"),
      ...over,
    };
  }

  /**
   * Prisma de prueba con la semántica real del backend:
   *   - `returnedQty` describe la cantidad devuelta por línea ORIGINAL, tal como
   *     la sumaría un documento `kind=refund` (con cualquier fecha).
   *   - `sales` describe ventas del tenant; el mock aplica los filtros de
   *     companyId, kind, isDeleted, userId y rango exclusivo.
   */
  function harness(
    options: {
      sales?: Array<Record<string, unknown>>;
      returnedQty?: Record<string, number>;
      movements?: Array<Record<string, unknown>>;
      creditPayments?: Array<Record<string, unknown>>;
      creditLedger?: Array<{ saleId: string; cash: number; transfer: number }>;
      products?: Array<Record<string, unknown>>;
      company?: Record<string, unknown> | null;
    } = {},
  ) {
    const saleFindMany = jest.fn((args: { where: Record<string, any> }) => {
      const where = args?.where ?? {};
      const gte = where.saleDate?.gte as Date | undefined;
      const lt = where.saleDate?.lt as Date | undefined;
      return Promise.resolve(
        (options.sales ?? []).filter(
          (row) =>
            row.companyId === where.companyId &&
            row.kind === where.kind &&
            row.isDeleted === where.isDeleted &&
            (!where.userId || row.userId === where.userId) &&
            (!gte || (row.saleDate as Date) >= gte) &&
            (!lt || (row.saleDate as Date) < lt),
        ),
      );
    });

    const saleItemGroupBy = jest.fn(
      (args: { where: { refundedSaleItemId: { in: string[] } } }) => {
        const ids = args?.where?.refundedSaleItemId?.in ?? [];
        return Promise.resolve(
          ids
            .filter((id) => (options.returnedQty?.[id] ?? 0) > 0)
            .map((id) => ({
              refundedSaleItemId: id,
              _sum: { qty: decimal(options.returnedQty?.[id] ?? 0) },
            })),
        );
      },
    );

    const productFindMany = jest.fn().mockResolvedValue(options.products ?? []);
    const cashFindMany = jest.fn().mockResolvedValue(options.movements ?? []);
    const creditFindMany = jest
      .fn()
      .mockResolvedValue(options.creditPayments ?? []);
    const creditGroupBy = jest.fn().mockResolvedValue(
      (options.creditLedger ?? []).map((row) => ({
        saleId: row.saleId,
        _sum: {
          cashAmount: decimal(row.cash),
          transferAmount: decimal(row.transfer),
          amount: decimal(row.cash + row.transfer),
        },
      })),
    );

    const prisma = {
      sale: { findMany: saleFindMany },
      saleItem: { groupBy: saleItemGroupBy },
      product: { findMany: productFindMany },
      cashMovement: { findMany: cashFindMany },
      saleCreditPayment: { findMany: creditFindMany, groupBy: creditGroupBy },
      company: {
        findUnique: jest.fn().mockResolvedValue(options.company ?? null),
      },
    };

    return {
      service: serviceWith(prisma),
      prisma,
      saleFindMany,
      saleItemGroupBy,
      productFindMany,
      cashFindMany,
      creditFindMany,
      creditGroupBy,
    };
  }

  const august = { from: "2026-08-01", to: "2026-08-22" };

  it("TEST 1 · venta normal: ventas, costo, bruta, neta y 1 ticket", async () => {
    const invoice = sale({
      id: "sale-normal",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({ sales: [invoice] });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.grossSales).toBeCloseTo(3000, 2);
    expect(result.kpis.returnedSales).toBeCloseTo(0, 2);
    expect(result.kpis.netSales).toBeCloseTo(3000, 2);
    expect(result.kpis.totalCost).toBeCloseTo(2000, 2);
    expect(result.kpis.grossProfit).toBeCloseTo(1000, 2);
    expect(result.kpis.totalExpenses).toBeCloseTo(0, 2);
    expect(result.kpis.netProfit).toBeCloseTo(1000, 2);
    expect(result.kpis.totalSales).toBe(1);
  });

  it("TEST 2 · devolución total: contribución exactamente 0 y 0 tickets", async () => {
    const invoice = sale({
      id: "sale-full-refund",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          id: "item-full",
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      returnedQty: { "item-full": 1 },
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.grossSales).toBeCloseTo(3000, 2);
    expect(result.kpis.returnedSales).toBeCloseTo(3000, 2);
    expect(result.kpis.netSales).toBe(0);
    expect(result.kpis.totalCost).toBe(0);
    expect(result.kpis.grossProfit).toBe(0);
    expect(result.kpis.netProfit).toBe(0);
    expect(result.kpis.totalSales).toBe(0);
    expect(result.kpis.avgTicket).toBe(0);
    expect(result.kpis.totalReturns).toBe(1);
    // El gráfico y las categorías tampoco pueden contradecir al KPI.
    expect(
      result.salesSeries.reduce((sum, row) => sum + row.value, 0),
    ).toBeCloseTo(0, 6);
    expect(
      result.profitSeries.reduce((sum, row) => sum + row.value, 0),
    ).toBeCloseTo(0, 6);
    expect(result.categoryProfits).toEqual([]);
  });

  it("TEST 3 · devolución parcial 50%: remanente con costo snapshot histórico", async () => {
    const invoice = sale({
      id: "sale-partial",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          id: "item-partial",
          qty: decimal(2),
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      returnedQty: { "item-partial": 1 },
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBeCloseTo(1500, 2);
    expect(result.kpis.totalCost).toBeCloseTo(1000, 2);
    expect(result.kpis.grossProfit).toBeCloseTo(500, 2);
    expect(result.kpis.returnedSales).toBeCloseTo(1500, 2);
    expect(result.kpis.totalSales).toBe(1);
    expect(result.categoryProfits).toEqual([
      expect.objectContaining({
        totalSales: 1500,
        totalCost: 1000,
        totalProfit: 500,
      }),
    ]);
  });

  it("TEST 4 · gastos que afectan utilidad: neta = bruta - gastos", async () => {
    const invoice = sale({
      id: "sale-expense",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      movements: [cashMovement({ id: "expense-1", amount: decimal(300) })],
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBeCloseTo(3000, 2);
    expect(result.kpis.grossProfit).toBeCloseTo(1000, 2);
    expect(result.kpis.totalExpenses).toBeCloseTo(300, 2);
    expect(result.kpis.netProfit).toBeCloseTo(700, 2);
    expect(result.kpis.netProfit).toBeCloseTo(
      result.kpis.grossProfit - result.kpis.totalExpenses,
      6,
    );
  });

  it("TEST 5 · devolución total + gasto real: neta negativa SOLO por el gasto", async () => {
    const invoice = sale({
      id: "sale-full-refund-expense",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          id: "item-full-expense",
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      returnedQty: { "item-full-expense": 1 },
      movements: [cashMovement({ amount: decimal(300) })],
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBe(0);
    expect(result.kpis.grossProfit).toBe(0);
    expect(result.kpis.totalExpenses).toBeCloseTo(300, 2);
    expect(result.kpis.netProfit).toBeCloseTo(-300, 2);
  });

  it("BUG REAL · la devolución de una venta de otro período NO produce ventas negativas", async () => {
    // Venta del 10/08 devuelta por completo (documento de devolución fechado en
    // septiembre). El reporte de septiembre NO puede mostrar -3000: la venta no
    // pertenece a ese período y el documento de devolución no es una venta.
    const invoice = sale({
      id: "sale-prior-period",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          id: "item-prior",
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      returnedQty: { "item-prior": 1 },
    });

    const september = await service.salesOverview(user as never, {
      from: "2026-09-01",
      to: "2026-09-30",
    });
    expect(september.kpis.netSales).toBe(0);
    expect(september.kpis.returnedSales).toBe(0);
    expect(september.kpis.netProfit).toBe(0);
    expect(september.kpis.totalSales).toBe(0);

    // Y su propio período es STATE-AWARE: aporta 0 aunque la devolución haya
    // ocurrido después.
    const augustReport = await service.salesOverview(user as never, august);
    expect(augustReport.kpis.netSales).toBe(0);
    expect(augustReport.kpis.grossProfit).toBe(0);
    expect(augustReport.kpis.totalSales).toBe(0);
  });

  it("TEST 13 · venta cancelada/eliminada: 0 ventas, 0 utilidad, 0 tickets", async () => {
    const cancelled = sale({
      id: "sale-cancelled",
      isDeleted: true,
      deletedAt: new Date("2026-08-11T13:00:00.000Z"),
      totalSold: decimal(600),
      totalCost: decimal(360),
      totalProfit: decimal(240),
      items: [
        item({
          subtotalSold: decimal(600),
          subtotalCost: decimal(360),
          profit: decimal(240),
        }),
      ],
    });
    const { service, saleFindMany } = harness({ sales: [cancelled] });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBe(0);
    expect(result.kpis.grossProfit).toBe(0);
    expect(result.kpis.totalSales).toBe(0);
    // La consulta de desempeño excluye canceladas por estado (isDeleted).
    expect(saleFindMany.mock.calls[0][0].where).toMatchObject({
      isDeleted: false,
      kind: "invoice",
      companyId: user.companyId,
    });
  });

  it("TEST 6-7 · crédito: la venta se devenga al emitirse y el abono no vuelve a sumar", async () => {
    const credit = sale({
      id: "sale-credit",
      paymentMethod: "credit",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      paymentCashAmount: decimal(0),
      paymentTransferAmount: decimal(0),
      items: [
        item({
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({ sales: [credit], creditLedger: [] });

    const report = await service.salesOverview(user as never, august);
    expect(report.kpis.netSales).toBeCloseTo(3000, 2);
    expect(report.kpis.grossProfit).toBeCloseTo(1000, 2);
    expect(report.kpis.cashIncome).toBeCloseTo(0, 2);
    expect(report.kpis.totalSales).toBe(1);

    // El abono del período es cobranza: no vuelve a sumar venta, utilidad ni
    // ticket.
    const withPayment = harness({
      sales: [credit],
      creditPayments: [
        {
          saleId: "sale-credit",
          cashAmount: decimal(3000),
          transferAmount: decimal(0),
          amount: decimal(3000),
          sale: { items: [item({ subtotalSold: decimal(3000) })] },
        },
      ],
      creditLedger: [{ saleId: "sale-credit", cash: 3000, transfer: 0 }],
    });
    const after = await withPayment.service.salesOverview(user as never, august);
    expect(after.kpis.netSales).toBeCloseTo(3000, 2);
    expect(after.kpis.grossProfit).toBeCloseTo(1000, 2);
    expect(after.kpis.totalSales).toBe(1);
  });

  it("TEST 8-9 · devolución de venta a crédito: 0 ventas, 0 utilidad, sin venta negativa", async () => {
    const credit = sale({
      id: "sale-credit-refund",
      paymentMethod: "credit",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      paymentCashAmount: decimal(0),
      paymentTransferAmount: decimal(0),
      creditAmount: decimal(3000),
      creditPaidAmount: decimal(0),
      creditBalance: decimal(3000),
      items: [
        item({
          id: "item-credit",
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({
      sales: [credit],
      returnedQty: { "item-credit": 1 },
    });

    const report = await service.salesOverview(user as never, august);

    expect(report.kpis.netSales).toBe(0);
    expect(report.kpis.grossProfit).toBe(0);
    expect(report.kpis.netProfit).toBe(0);
    expect(report.kpis.totalSales).toBe(0);
    expect(report.kpis.cashIncome).toBeCloseTo(0, 2);
  });

  it("TEST 14 · venta rápida (sin productId ni categoría) no rompe el reporte", async () => {
    const quick = sale({
      id: "sale-quick",
      totalSold: decimal(150),
      items: [
        item({
          id: "quick-1",
          productId: null,
          productSource: null,
          product: null,
          inventoryTrackedSnapshot: false,
          productNameSnapshot: "Servicio externo",
          subtotalSold: decimal(150),
          subtotalCost: decimal(50),
          profit: decimal(100),
        }),
      ],
    });
    const { service } = harness({ sales: [quick] });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBeCloseTo(150, 2);
    expect(result.kpis.grossProfit).toBeCloseTo(100, 2);
    expect(result.categoryProfits).toEqual([
      expect.objectContaining({ category: "Sin categoria", totalSales: 150 }),
    ]);
    expect(result.topProducts[0]).toEqual(
      expect.objectContaining({ productName: "Servicio externo" }),
    );
  });

  it("TEST 15 · exento + gravado: el ingreso neto suma base y exento", async () => {
    const invoice = sale({
      id: "sale-tax",
      items: [
        item({
          id: "taxable",
          subtotalSold: decimal(1000),
          subtotalCost: decimal(600),
          profit: decimal(400),
          taxableBase: decimal(1000),
          taxAmount: decimal(180),
        }),
        item({
          id: "exempt",
          subtotalSold: decimal(500),
          subtotalCost: decimal(200),
          profit: decimal(300),
          taxableBase: decimal(0),
          taxAmount: decimal(0),
          exemptAmount: decimal(500),
        }),
      ],
    });
    const { service } = harness({ sales: [invoice] });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBeCloseTo(1500, 2);
    expect(result.kpis.taxableBase).toBeCloseTo(1000, 2);
    expect(result.kpis.exemptAmount).toBeCloseTo(500, 2);
    expect(result.kpis.taxAmount).toBeCloseTo(180, 2);
    expect(result.kpis.grossProfit).toBeCloseTo(700, 2);
  });

  it("TEST 16 · descuentos: el descuento general se prorratea por la parte remanente", async () => {
    // Venta de 2 unidades con descuento general de 200 en el documento.
    // Se devuelve 1 unidad => el descuento aporta 100, no 200.
    const invoice = sale({
      id: "sale-discount",
      discountAmount: decimal(200),
      totalSold: decimal(1000),
      items: [
        item({
          id: "disc-1",
          qty: decimal(2),
          priceSoldUnit: decimal(500),
          subtotalSold: decimal(1000),
          subtotalCost: decimal(600),
          profit: decimal(400),
          lineDiscountAmount: decimal(0),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      returnedQty: { "disc-1": 1 },
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBeCloseTo(500, 2);
    expect(result.kpis.discountAmount).toBeCloseTo(100, 2);
  });

  it("TEST 17 · reconciliación: categorías == KPIs y neta == bruta - gastos", async () => {
    const accessories = sale({
      id: "s-a",
      customerId: "c1",
      customer: { id: "c1", nombre: "Cliente 1" },
      items: [
        item({
          id: "ia",
          productId: "pa",
          product: { categoria: "Accesorios" },
          subtotalSold: decimal(1000),
          subtotalCost: decimal(600),
          profit: decimal(400),
        }),
      ],
    });
    const repairs = sale({
      id: "s-b",
      items: [
        item({
          id: "ib",
          productId: "pb",
          product: { categoria: "Repuestos" },
          qty: decimal(2),
          subtotalSold: decimal(2000),
          subtotalCost: decimal(1500),
          profit: decimal(500),
        }),
      ],
    });
    const { service } = harness({
      sales: [accessories, repairs],
      returnedQty: { ib: 1 },
      movements: [cashMovement({ amount: decimal(100) })],
    });

    const result = await service.salesOverview(user as never, august);

    const categorySales = result.categoryProfits.reduce(
      (sum, row) => sum + row.totalSales,
      0,
    );
    const categoryProfit = result.categoryProfits.reduce(
      (sum, row) => sum + row.totalProfit,
      0,
    );
    const seriesSales = result.salesSeries.reduce(
      (sum, row) => sum + row.value,
      0,
    );

    expect(categorySales).toBeCloseTo(result.kpis.netSales, 2);
    expect(categoryProfit).toBeCloseTo(result.kpis.grossProfit, 2);
    expect(seriesSales).toBeCloseTo(result.kpis.netSales, 2);
    expect(result.kpis.grossProfit).toBeCloseTo(
      result.kpis.netSales - result.kpis.totalCost,
      2,
    );
    expect(result.kpis.netProfit).toBeCloseTo(
      result.kpis.grossProfit - result.kpis.totalExpenses,
      6,
    );
    // Repuestos: 2000 bruto, 1000 remanente (1 de 2 unidades devuelta).
    expect(result.categoryProfits).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ category: "Repuestos", totalSales: 1000 }),
        expect.objectContaining({ category: "Accesorios", totalSales: 1000 }),
      ]),
    );
  });

  it("TEST 18 · summaryOnly devuelve los MISMOS KPIs que el reporte completo", async () => {
    const invoice = sale({
      id: "sale-summary",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          id: "item-summary",
          qty: decimal(2),
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      returnedQty: { "item-summary": 1 },
    });

    const full = await service.salesOverview(user as never, august);
    const light = await service.salesOverview(user as never, {
      ...august,
      summaryOnly: "true",
    });

    expect(light.kpis.netSales).toBeCloseTo(full.kpis.netSales, 2);
    expect(light.kpis.grossProfit).toBeCloseTo(full.kpis.grossProfit, 2);
    expect(light.kpis.totalSales).toBe(full.kpis.totalSales);
    expect(light.kpis.grossSales).toBeCloseTo(full.kpis.grossSales, 2);
    expect(light.kpis.returnedSales).toBeCloseTo(full.kpis.returnedSales, 2);
  });

  it("no calcula ticket promedio sobre ventas excluidas por el filtro de categoría", async () => {
    const saleInCategory = sale({
      id: "s-a",
      totalSold: decimal(100),
      items: [
        item({
          id: "ia",
          productId: "pa",
          subtotalSold: decimal(100),
          subtotalCost: decimal(60),
          profit: decimal(40),
          product: { categoria: "Accesorios" },
        }),
      ],
    });
    const otherCategory = sale({
      id: "s-b",
      totalSold: decimal(200),
      items: [
        item({
          id: "ib",
          productId: "pb",
          subtotalSold: decimal(200),
          subtotalCost: decimal(100),
          profit: decimal(100),
          product: { categoria: "Repuestos" },
        }),
      ],
    });
    const { service } = harness({ sales: [saleInCategory, otherCategory] });

    const result = await service.salesOverview(user as never, {
      ...august,
      category: "Accesorios",
    });

    expect(result.kpis.totalSales).toBe(1);
    // 100 / 1 (solo tickets visibles de la categoría), no 100 / 2.
    expect(result.kpis.avgTicket).toBeCloseTo(100);
    expect(result.categoryProfits).toEqual([
      expect.objectContaining({ category: "Accesorios" }),
    ]);
  });

  it("una categoría totalmente devuelta no aparece en el desglose", async () => {
    const invoice = sale({
      id: "s-cat",
      items: [
        item({
          id: "i-cat",
          productId: "p-cat",
          product: { categoria: "Celulares" },
          subtotalSold: decimal(6000),
          subtotalCost: decimal(3500),
          profit: decimal(2500),
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      returnedQty: { "i-cat": 1 },
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.categoryProfits).toEqual([]);
    // Nunca: resumen -3000 con categoría +6000.
    expect(result.kpis.netSales).toBe(0);
  });

  it("usa rango exclusivo (gte/lt) sin ventana 23:59:59.999", async () => {
    const { service, saleFindMany } = harness();

    await service.salesOverview(user as never, august);

    const saleWhere = saleFindMany.mock.calls[0][0].where;
    expect(saleWhere.saleDate.gte).toEqual(
      new Date(Date.UTC(2026, 7, 1, 4, 0, 0, 0)),
    );
    expect(saleWhere.saleDate.lt).toEqual(
      new Date(Date.UTC(2026, 7, 23, 4, 0, 0, 0)),
    );
    expect(saleWhere.saleDate.lte).toBeUndefined();
  });

  it("rechaza un rango de fechas inválido", async () => {
    const { service } = harness();
    await expect(
      service.salesOverview(user as never, {
        from: "2026-08-22",
        to: "2026-08-01",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("aísla TODAS las consultas por companyId (multiempresa)", async () => {
    const invoice = sale({
      paymentMethod: "credit",
      items: [item({ id: "iso-item" })],
    });
    const {
      service,
      saleFindMany,
      saleItemGroupBy,
      productFindMany,
      cashFindMany,
      creditFindMany,
      creditGroupBy,
    } = harness({
      sales: [invoice],
      returnedQty: { "iso-item": 1 },
      creditLedger: [{ saleId: "sale-1", cash: 0, transfer: 0 }],
    });

    await service.salesOverview(user as never, august);

    for (const call of saleFindMany.mock.calls) {
      expect(call[0].where.companyId).toBe(user.companyId);
    }
    expect(saleItemGroupBy).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          sale: expect.objectContaining({ companyId: user.companyId }),
        }),
      }),
    );
    expect(productFindMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId: user.companyId }),
      }),
    );
    expect(cashFindMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId: user.companyId }),
      }),
    );
    expect(creditFindMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId: user.companyId }),
      }),
    );
    for (const call of creditGroupBy.mock.calls) {
      expect(call[0].where.companyId).toBe(user.companyId);
    }
  });

  it("TEST 12 · Empresa A y Empresa B no se contaminan", async () => {
    const userA = { ...user, companyId: "company-a" };
    const userB = { ...user, companyId: "company-b" };
    const saleA = sale({
      companyId: "company-a",
      id: "sale-a",
      totalSold: decimal(3000),
      totalCost: decimal(2000),
      totalProfit: decimal(1000),
      items: [
        item({
          id: "item-a",
          subtotalSold: decimal(3000),
          subtotalCost: decimal(2000),
          profit: decimal(1000),
        }),
      ],
    });
    const saleB = sale({
      companyId: "company-b",
      id: "sale-b",
      totalSold: decimal(500),
      totalCost: decimal(100),
      totalProfit: decimal(400),
      items: [
        item({
          id: "item-b",
          subtotalSold: decimal(500),
          subtotalCost: decimal(100),
          profit: decimal(400),
        }),
      ],
    });
    const { service } = harness({
      sales: [saleA, saleB],
      returnedQty: { "item-a": 1 },
    });

    const resultA = await service.salesOverview(userA as never, august);
    const resultB = await service.salesOverview(userB as never, august);

    expect(resultA.kpis.netSales).toBe(0);
    expect(resultA.kpis.grossSales).toBeCloseTo(3000, 2);
    expect(resultB.kpis.netSales).toBeCloseTo(500, 2);
    expect(resultB.kpis.grossProfit).toBeCloseTo(400, 2);
  });

  it("el filtro por vendedor (SELLER) se aplica a las ventas del período", async () => {
    const seller = {
      id: "user-seller",
      role: "VENDEDOR",
      companyId: user.companyId,
    };
    const own = sale({ id: "own", userId: "user-seller" });
    const other = sale({ id: "other", userId: "user-other" });
    const { service, saleFindMany } = harness({ sales: [own, other] });

    const result = await service.salesOverview(seller as never, august);

    expect(result.kpis.totalSales).toBe(1);
    expect(saleFindMany.mock.calls[0][0].where.userId).toBe("user-seller");
  });

  it("no suma documentos refund como ventas negativas", async () => {
    const { service, saleFindMany } = harness();

    await service.salesOverview(user as never, august);

    // Sólo se consulta desempeño: ventas emitidas (invoice, no borradas) y las
    // cantidades devueltas de sus líneas. Ningún documento refund se suma.
    for (const call of saleFindMany.mock.calls) {
      expect(call[0].where.kind).toBe("invoice");
    }
  });

  it("no descuenta de utilidad los movimientos OUT con affectsProfit=false", async () => {
    const { service } = harness({
      sales: [sale()],
      movements: [cashMovement({ amount: decimal(25), affectsProfit: false })],
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.grossProfit).toBeCloseTo(40);
    expect(result.kpis.totalExpenses).toBeCloseTo(0);
    expect(result.kpis.netProfit).toBeCloseTo(40);
  });

  it("reporta cantidades por unidad cuando hay UoM mixtas", async () => {
    const invoice = sale({
      items: [
        item({
          id: "unit-1",
          productId: "p-unit",
          productNameSnapshot: "Tornillo",
          qty: decimal(2),
          unitCodeSnapshot: "UNIT",
          unitNameSnapshot: "Unidad",
          unitSymbolSnapshot: "u",
          unitPrecisionSnapshot: 0,
          product: { categoria: "Mixto" },
        }),
        item({
          id: "yard-1",
          productId: "p-yard",
          productNameSnapshot: "Tela",
          qty: new Prisma.Decimal("1.500000"),
          unitCodeSnapshot: "YARD",
          unitNameSnapshot: "Yarda",
          unitSymbolSnapshot: "yd",
          unitPrecisionSnapshot: 3,
          product: { categoria: "Mixto" },
        }),
        item({
          id: "pound-1",
          productId: "p-pound",
          productNameSnapshot: "Cable",
          qty: new Prisma.Decimal("2.375000"),
          unitCodeSnapshot: "POUND",
          unitNameSnapshot: "Libra",
          unitSymbolSnapshot: "lb",
          unitPrecisionSnapshot: 3,
          product: { categoria: "Mixto" },
        }),
      ],
    });
    const { service } = harness({
      sales: [invoice],
      // Se devuelve media yarda: la cantidad vendida baja en esa unidad.
      returnedQty: { "yard-1": 0.5 },
    });

    const result = await service.salesOverview(user as never, august);

    expect(result.topProducts).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          productName: "Tela",
          unitCode: "YARD",
          totalQtyLabel: "1 yd",
        }),
        expect.objectContaining({
          productName: "Cable",
          unitCode: "POUND",
          totalQtyLabel: "2.375 lb",
        }),
      ]),
    );
    expect(result.categoryProfits[0]).toEqual(
      expect.objectContaining({
        category: "Mixto",
        totalQtyLabel: "2 u + 1 yd + 2.375 lb",
        quantityBuckets: expect.arrayContaining([
          expect.objectContaining({ unitCode: "UNIT", quantity: 2 }),
          expect.objectContaining({ unitCode: "YARD", quantity: 1 }),
          expect.objectContaining({ unitCode: "POUND", quantity: 2.375 }),
        ]),
      }),
    );
  });

  it("expone advertencia auditable cuando hay líneas sin costo", async () => {
    const invoice = sale({
      items: [
        item({
          id: "zero-cost",
          costUnitSnapshot: decimal(0),
          subtotalCost: decimal(0),
        }),
      ],
    });
    const { service } = harness({ sales: [invoice] });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.zeroCostItems).toBe(1);
    expect(result.audit.warnings).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: "items_without_cost" }),
      ]),
    );
  });

  it("venta sin líneas no rompe el reporte (null safety)", async () => {
    const { service } = harness({ sales: [sale({ id: "empty", items: [] })] });

    const result = await service.salesOverview(user as never, august);

    expect(result.kpis.netSales).toBe(0);
    expect(result.kpis.totalSales).toBe(0);
    expect(Number.isNaN(result.kpis.netSales)).toBe(false);
    expect(result.audit.saleRows).toBe(0);
  });
});
