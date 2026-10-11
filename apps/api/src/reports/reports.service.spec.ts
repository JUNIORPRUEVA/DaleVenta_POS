import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { ReportsService } from "./reports.service";

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
      productNameSnapshot: "Producto 1",
      qty: decimal(1),
      priceSoldUnit: decimal(100),
      costUnitSnapshot: decimal(60),
      subtotalSold: decimal(100),
      subtotalCost: decimal(60),
      profit: decimal(40),
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
      totalSold: decimal(100),
      totalCost: decimal(60),
      totalProfit: decimal(40),
      commissionAmount: decimal(4),
      paymentCashAmount: decimal(100),
      paymentTransferAmount: decimal(0),
      items: [item()],
      ...over,
    };
  }

  function emptyPrisma(findMany: jest.Mock) {
    // Queries beyond the ones a test queues explicitly (e.g. the cancelled
    // sales of the period) resolve to an empty list, so each test only has to
    // describe the rows it cares about.
    findMany.mockResolvedValue([]);
    return {
      sale: { findMany },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      cashMovement: { findMany: jest.fn().mockResolvedValue([]) },
      saleCreditPayment: {
        findMany: jest.fn().mockResolvedValue([]),
        groupBy: jest.fn().mockResolvedValue([]),
      },
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

  it("restringe devoluciones a reversiones de períodos anteriores (sin doble descuento)", async () => {
    const cancelledSamePeriod = sale({
      id: "sale-cancelled-same-period",
      isDeleted: true,
      deletedAt: new Date("2026-08-10T13:00:00.000Z"),
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([cancelledSamePeriod]) // sales emitted in range
      .mockResolvedValueOnce([cancelledSamePeriod]) // cancelled in range
      .mockResolvedValueOnce([]); // refundSales
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    // Movimiento del período: la venta emitida entra al bruto y su cancelación
    // entra como reversa. El neto queda 0 sin clamps ni signos visuales.
    const saleWhere = findMany.mock.calls[0][0].where;
    expect(saleWhere).toMatchObject({
      companyId: user.companyId,
      kind: "invoice",
    });
    expect(saleWhere.isDeleted).toBeUndefined();
    const returnedWhere = findMany.mock.calls[1][0].where;
    expect(returnedWhere).toMatchObject({
      companyId: user.companyId,
      kind: "invoice",
      isDeleted: true,
    });
    expect(returnedWhere.saleDate).toBeUndefined();
    expect(result.kpis.netSales).toBe(0);
    expect(result.kpis.totalReturns).toBe(1);
  });

  it("netea venta + devolución completa del mismo período a cero", async () => {
    const invoice = sale({
      id: "sale-full-refund",
      totalSold: decimal(100),
      totalCost: decimal(40),
      totalProfit: decimal(60),
      items: [
        item({
          subtotalSold: decimal(100),
          subtotalCost: decimal(40),
          profit: decimal(60),
        }),
      ],
    });
    const refund = sale({
      id: "refund-full",
      kind: "refund",
      refundedSaleId: "sale-full-refund",
      totalSold: decimal(-100),
      totalCost: decimal(-40),
      totalProfit: decimal(-60),
      items: [
        item({
          subtotalSold: decimal(-100),
          subtotalCost: decimal(-40),
          profit: decimal(-60),
        }),
      ],
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([invoice])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([refund]);
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.grossSales).toBeCloseTo(100);
    expect(result.kpis.returnedSales).toBeCloseTo(100);
    expect(result.kpis.netSales).toBeCloseTo(0);
    expect(result.kpis.totalCost).toBeCloseTo(40);
    expect(result.kpis.totalProfit).toBeCloseTo(60);
    expect(result.kpis.netProfit).toBeCloseTo(0);
  });

  it("netea venta + devolución parcial del mismo período al remanente", async () => {
    const invoice = sale({
      id: "sale-partial-refund",
      totalSold: decimal(100),
      totalCost: decimal(40),
      totalProfit: decimal(60),
      items: [
        item({
          subtotalSold: decimal(100),
          subtotalCost: decimal(40),
          profit: decimal(60),
        }),
      ],
    });
    const refund = sale({
      id: "refund-partial",
      kind: "refund",
      refundedSaleId: "sale-partial-refund",
      totalSold: decimal(-40),
      totalCost: decimal(-16),
      totalProfit: decimal(-24),
      items: [
        item({
          subtotalSold: decimal(-40),
          subtotalCost: decimal(-16),
          profit: decimal(-24),
        }),
      ],
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([invoice])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([refund]);
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.netSales).toBeCloseTo(60);
    expect(result.kpis.netProfit).toBeCloseTo(36);
  });

  it("netea venta + devolución parcial + cancelación en el mismo período a cero", async () => {
    const invoice = sale({
      id: "sale-partial-cancel",
      isDeleted: true,
      deletedAt: new Date("2026-08-10T13:00:00.000Z"),
      totalSold: decimal(100),
      totalCost: decimal(40),
      totalProfit: decimal(60),
      items: [
        item({
          subtotalSold: decimal(100),
          subtotalCost: decimal(40),
          profit: decimal(60),
        }),
      ],
    });
    const refund = sale({
      id: "refund-partial-cancel",
      kind: "refund",
      refundedSaleId: "sale-partial-cancel",
      totalSold: decimal(-40),
      totalCost: decimal(-16),
      totalProfit: decimal(-24),
      items: [
        item({
          subtotalSold: decimal(-40),
          subtotalCost: decimal(-16),
          profit: decimal(-24),
        }),
      ],
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([invoice])
      .mockResolvedValueOnce([invoice])
      .mockResolvedValueOnce([refund])
      // La venta cancelada del período alimenta `cancelledInRangeIds`: sin ella
      // el refund volvería a descontarse (100 cancelada + 40 devuelta = 140).
      .mockResolvedValueOnce([invoice]);
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.grossSales).toBeCloseTo(100);
    expect(result.kpis.returnedSales).toBeCloseTo(100);
    expect(result.kpis.netSales).toBeCloseTo(0);
    expect(result.kpis.netProfit).toBeCloseTo(0);
    expect(result.audit.refundDocumentRows).toBe(1);
    expect(result.kpis.totalReturns).toBe(1);
  });

  it("mantiene refund de período actual contra venta de período anterior como movimiento negativo", async () => {
    const refund = sale({
      id: "refund-prior-sale",
      kind: "refund",
      refundedSaleId: "sale-prior-period",
      totalSold: decimal(-100),
      totalCost: decimal(-40),
      totalProfit: decimal(-60),
      items: [
        item({
          subtotalSold: decimal(-100),
          subtotalCost: decimal(-40),
          profit: decimal(-60),
        }),
      ],
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([refund]);
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-09-01",
      to: "2026-09-30",
    });

    expect(result.kpis.grossSales).toBeCloseTo(0);
    expect(result.kpis.returnedSales).toBeCloseTo(100);
    expect(result.kpis.netSales).toBeCloseTo(-100);
    expect(result.kpis.netProfit).toBeCloseTo(-60);
  });

  it("resta documentos de devolución (kind=refund) del neto", async () => {
    const invoice = sale();
    const refund = sale({
      id: "refund-1",
      kind: "refund",
      totalSold: decimal(-20),
      totalCost: decimal(-12),
      totalProfit: decimal(-8),
      commissionAmount: decimal(0),
      items: [
        item({
          subtotalSold: decimal(-20),
          subtotalCost: decimal(-12),
          profit: decimal(-8),
        }),
      ],
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([invoice]) // sales
      .mockResolvedValueOnce([]) // returnedSales
      .mockResolvedValueOnce([refund]); // refundSales
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.grossSales).toBeCloseTo(100);
    expect(result.kpis.returnedSales).toBeCloseTo(20);
    expect(result.kpis.netSales).toBeCloseTo(80);
    expect(result.kpis.totalReturns).toBe(1);
  });

  it("expone utilidad bruta, gastos y utilidad neta sin recalcular costos históricos", async () => {
    const invoice = sale({
      totalSold: decimal(2100),
      totalCost: decimal(872),
      totalProfit: decimal(1228),
      items: [
        item({
          subtotalSold: decimal(2100),
          subtotalCost: decimal(872),
          profit: decimal(1228),
        }),
      ],
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([invoice])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith({
      ...emptyPrisma(findMany),
      cashMovement: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            cashMovement({ id: "expense-1", amount: decimal(700) }),
          ]),
      },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.totalProfit).toBeCloseTo(1228);
    expect(result.kpis.totalExpenses).toBeCloseTo(700);
    expect(result.kpis.netProfit).toBeCloseTo(528);
  });

  it("agrega movimientos de caja en base de datos sin materializar cada fila", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([sale()])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const cashGroupBy = jest.fn().mockResolvedValue([
      {
        type: "IN",
        movementType: "income",
        affectsProfit: true,
        _sum: { amount: decimal(125) },
        _count: { _all: 5 },
      },
      {
        type: "OUT",
        movementType: "expense",
        affectsProfit: true,
        _sum: { amount: decimal(70) },
        _count: { _all: 2 },
      },
      {
        type: "OUT",
        movementType: "expense",
        affectsProfit: false,
        _sum: { amount: decimal(30) },
        _count: { _all: 1 },
      },
    ]);
    const cashFindMany = jest.fn();
    const service = serviceWith({
      ...emptyPrisma(findMany),
      cashMovement: {
        groupBy: cashGroupBy,
        findMany: cashFindMany,
      },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(cashGroupBy).toHaveBeenCalledWith(
      expect.objectContaining({
        by: ["type", "movementType", "affectsProfit"],
        _sum: { amount: true },
        _count: { _all: true },
      }),
    );
    expect(cashFindMany).not.toHaveBeenCalled();
    expect(result.kpis.cashIncome).toBeCloseTo(225);
    expect(result.kpis.cashExpense).toBeCloseTo(100);
    expect(result.kpis.totalExpenses).toBeCloseTo(70);
    expect(result.audit.cashMovementRows).toBe(8);
  });

  it("agrega inventario/categorias en base de datos sin materializar productos", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([sale()])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const productFindMany = jest.fn();
    const queryRaw = jest
      .fn()
      .mockResolvedValueOnce([
        {
          category: "Bebidas",
          unitCode: "UNIT",
          unitName: "Unidad",
          unitSymbol: "u",
          unitPrecision: 0,
          products: 2,
          units: decimal(5),
          costValue: decimal(175),
          saleValue: decimal(300),
          outOfStock: 1,
          lowStock: 1,
          productsWithoutCost: 0,
        },
      ])
      .mockResolvedValueOnce([{ category: "Bebidas" }])
      .mockResolvedValueOnce([
        {
          cash: decimal(0),
          transfer: decimal(0),
          cashOperations: 0,
          transferOperations: 0,
          rowCount: 0,
        },
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith({
      ...emptyPrisma(findMany),
      $queryRaw: queryRaw,
      product: { findMany: productFindMany },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(queryRaw).toHaveBeenCalledTimes(7);
    expect(productFindMany).not.toHaveBeenCalled();
    expect(result.categories).toEqual(["Bebidas"]);
    expect(result.inventory).toEqual(
      expect.objectContaining({
        products: 2,
        units: 5,
        costValue: 175,
        saleValue: 300,
        outOfStock: 1,
        lowStock: 1,
        productsWithoutCost: 0,
      }),
    );
    expect(result.inventory.unitsByUnit).toEqual([
      expect.objectContaining({ unitCode: "UNIT", quantity: 5 }),
    ]);
  });

  it("castea filtros raw uuid de empresa y vendedor para reportes agregados", async () => {
    const capturedSql: string[] = [];
    const queryRaw = jest.fn((query: { strings?: readonly string[] }) => {
      const sql = query.strings?.join("") ?? "";
      capturedSql.push(sql);
      if (sql.includes("invoice_sales AS")) {
        return Promise.resolve([
          {
            totalSales: 0,
            saleItemRows: 0,
            totalSold: decimal(0),
            totalCost: decimal(0),
            totalProfit: decimal(0),
            totalCommission: decimal(0),
            taxableBase: decimal(0),
            taxAmount: decimal(0),
            exemptAmount: decimal(0),
            discountAmount: decimal(0),
            initialCash: decimal(0),
            initialTransfer: decimal(0),
            initialCashOperations: 0,
            initialTransferOperations: 0,
            paymentBreakdownViolations: 0,
            zeroCostItems: 0,
            zeroCostSoldAmount: decimal(0),
            returnCount: 0,
            returnedAmount: decimal(0),
            returnedCost: decimal(0),
            returnedProfit: decimal(0),
            refundDocumentRows: 0,
          },
        ]);
      }
      if (sql.includes("FROM \"sale_credit_payments\" cp")) {
        return Promise.resolve([
          {
            cash: decimal(0),
            transfer: decimal(0),
            cashOperations: 0,
            transferOperations: 0,
            rowCount: 0,
          },
        ]);
      }
      return Promise.resolve([]);
    });
    const service = serviceWith({
      ...emptyPrisma(jest.fn()),
      $queryRaw: queryRaw,
      cashMovement: {
        groupBy: jest.fn().mockResolvedValue([]),
        findMany: jest.fn(),
      },
    });

    await service.salesOverview(
      {
        ...user,
        id: "22222222-2222-2222-2222-222222222222",
        role: "VENDEDOR",
      } as never,
      {
        from: "2026-08-01",
        to: "2026-08-22",
      },
    );

    const sellerFilters = capturedSql.filter((sql) =>
      sql.includes('s."userId"'),
    );
    expect(sellerFilters.length).toBeGreaterThan(0);
    expect(sellerFilters).toEqual(
      expect.arrayContaining([
        expect.stringContaining('s."userId" = CAST('),
      ]),
    );
    for (const sql of sellerFilters) {
      expect(sql).toContain(" AS uuid)");
    }
    const companyFilters = capturedSql.filter((sql) =>
      sql.includes('"company_id"'),
    );
    expect(companyFilters.length).toBeGreaterThan(0);
    for (const sql of companyFilters) {
      expect(sql).toContain('"company_id" = CAST(');
      expect(sql).toContain(" AS uuid)");
    }
  });

  it("agrega abonos de credito del periodo en base de datos sin materializarlos", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([sale()])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const creditFindMany = jest.fn();
    const queryRaw = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          cash: decimal(75),
          transfer: decimal(25),
          cashOperations: 2,
          transferOperations: 1,
          rowCount: 3,
        },
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith({
      ...emptyPrisma(findMany),
      $queryRaw: queryRaw,
      saleCreditPayment: {
        findMany: creditFindMany,
        groupBy: jest.fn().mockResolvedValue([]),
      },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(creditFindMany).not.toHaveBeenCalled();
    expect(result.kpis.creditPaymentsCash).toBeCloseTo(75);
    expect(result.kpis.creditPaymentsTransfer).toBeCloseTo(25);
    expect(result.kpis.creditPaymentsCount).toBe(3);
    expect(result.audit.creditPaymentRows).toBe(3);
    expect(
      result.paymentMethods.find((row) => row.method === "Efectivo"),
    ).toEqual(expect.objectContaining({ amount: 175, count: 3 }));
    expect(
      result.paymentMethods.find((row) => row.method === "Transferencia"),
    ).toEqual(expect.objectContaining({ amount: 25, count: 1 }));
  });

  it("agrega series, top clients, top products y categorias en base de datos cuando no hay filtro de categoria", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([
        sale({
          id: "sale-1",
          customerId: "client-1",
          customer: { id: "client-1", nombre: "Cliente legacy" },
        }),
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const queryRaw = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          cash: decimal(0),
          transfer: decimal(0),
          cashOperations: 0,
          transferOperations: 0,
          rowCount: 0,
        },
      ])
      .mockResolvedValueOnce([
        {
          clientName: "Cliente DB",
          totalSpent: decimal(450),
          purchaseCount: 3,
        },
      ])
      .mockResolvedValueOnce([
        {
          productName: "Producto DB",
          totalSales: decimal(300),
          totalQty: decimal(2),
          unitCode: "UNIT",
          unitName: "Unidad",
          unitSymbol: "u",
          unitPrecision: 0,
          totalProfit: decimal(120),
        },
      ])
      .mockResolvedValueOnce([
        {
          label: "2026-08-10",
          sales: decimal(450),
          profit: decimal(180),
        },
      ])
      .mockResolvedValueOnce([
        {
          category: "Bebidas",
          totalSales: decimal(450),
          totalCost: decimal(270),
          totalProfit: decimal(180),
          totalQty: decimal(2),
          salesCount: 3,
          unitCode: "UNIT",
          unitName: "Unidad",
          unitSymbol: "u",
          unitPrecision: 0,
          unitQuantity: decimal(2),
        },
      ]);
    const service = serviceWith({
      ...emptyPrisma(findMany),
      $queryRaw: queryRaw,
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(queryRaw).toHaveBeenCalledTimes(7);
    expect(result.topClients).toEqual([
      { clientName: "Cliente DB", totalSpent: 450, purchaseCount: 3 },
    ]);
    expect(result.topProducts).toEqual([
      {
        productName: "Producto DB",
        totalSales: 300,
        totalQty: 2,
        unitCode: "UNIT",
        unitName: "Unidad",
        unitSymbol: "u",
        unitPrecision: 0,
        totalQtyLabel: "2 u",
        totalProfit: 120,
      },
    ]);
    expect(result.salesSeries).toEqual([
      { label: "2026-08-10", value: 450 },
    ]);
    expect(result.profitSeries).toEqual([
      { label: "2026-08-10", value: 180 },
    ]);
    expect(result.categoryProfits).toEqual([
      {
        category: "Bebidas",
        totalSales: 450,
        totalCost: 270,
        totalProfit: 180,
        totalQty: 2,
        quantityBuckets: [
          {
            unitCode: "UNIT",
            unitName: "Unidad",
            unitSymbol: "u",
            unitPrecision: 0,
            quantity: 2,
            label: "2 u",
          },
        ],
        totalQtyLabel: "2 u",
        salesCount: 3,
      },
    ]);
  });

  it("usa ruta agregada completa sin materializar ventas/items cuando no hay filtro de categoria", async () => {
    const saleFindMany = jest.fn();
    const productFindMany = jest.fn();
    const queryRaw = (query: { strings?: readonly string[] }) => {
      const sql = query.strings?.join(" ") ?? "";
      if (sql.includes("invoice_sales AS")) {
        return Promise.resolve([
          {
            totalSales: 3,
            saleItemRows: 4,
            totalSold: decimal(650),
            totalCost: decimal(390),
            totalProfit: decimal(260),
            totalCommission: decimal(26),
            taxableBase: decimal(250),
            taxAmount: decimal(45),
            exemptAmount: decimal(380),
            discountAmount: decimal(25),
            initialCash: decimal(350),
            initialTransfer: decimal(125),
            initialCashOperations: 2,
            initialTransferOperations: 1,
            paymentBreakdownViolations: 1,
            zeroCostItems: 0,
            zeroCostSoldAmount: decimal(0),
            returnCount: 1,
            returnedAmount: decimal(40),
            returnedCost: decimal(16),
            returnedProfit: decimal(24),
            refundDocumentRows: 1,
          },
        ]);
      }
      if (sql.includes("FROM \"Product\"") && sql.includes("GROUP BY")) {
        return Promise.resolve([
          {
            category: "Bebidas",
            unitCode: "UNIT",
            unitName: "Unidad",
            unitSymbol: "u",
            unitPrecision: 0,
            products: 2,
            units: decimal(5),
            costValue: decimal(175),
            saleValue: decimal(300),
            outOfStock: 1,
            lowStock: 1,
            productsWithoutCost: 0,
          },
        ]);
      }
      if (sql.includes("SELECT DISTINCT")) {
        return Promise.resolve([{ category: "Bebidas" }]);
      }
      if (sql.includes("FROM \"sale_credit_payments\" cp")) {
        return Promise.resolve([
          {
            cash: decimal(75),
            transfer: decimal(25),
            cashOperations: 2,
            transferOperations: 1,
            rowCount: 3,
          },
        ]);
      }
      if (sql.includes("per_sale") && sql.includes("\"clientName\"")) {
        return Promise.resolve([
          { clientName: "Cliente DB", totalSpent: decimal(450), purchaseCount: 3 },
        ]);
      }
      if (sql.includes("FROM \"SaleItem\" si") && sql.includes("\"productName\"")) {
        return Promise.resolve([
          {
            productName: "Producto DB",
            totalSales: decimal(300),
            totalQty: decimal(2),
            unitCode: "UNIT",
            unitName: "Unidad",
            unitSymbol: "u",
            unitPrecision: 0,
            totalProfit: decimal(120),
          },
        ]);
      }
      if (sql.includes("to_char")) {
        return Promise.resolve([
          { label: "2026-08-10", sales: decimal(650), profit: decimal(260) },
        ]);
      }
      if (sql.includes("item_rows AS")) {
        return Promise.resolve([
          {
            category: "Bebidas",
            totalSales: decimal(650),
            totalCost: decimal(390),
            totalProfit: decimal(260),
            totalQty: decimal(4),
            salesCount: 3,
            unitCode: "UNIT",
            unitName: "Unidad",
            unitSymbol: "u",
            unitPrecision: 0,
            unitQuantity: decimal(4),
          },
        ]);
      }
      return Promise.resolve([]);
    };
    const service = serviceWith({
      sale: { findMany: saleFindMany },
      product: { findMany: productFindMany },
      company: { findUnique: jest.fn().mockResolvedValue({ inventoryEnabled: true }) },
      cashMovement: {
        groupBy: jest.fn().mockResolvedValue([]),
        findMany: jest.fn(),
      },
      saleCreditPayment: {
        findMany: jest.fn(),
        groupBy: jest.fn(),
      },
      $queryRaw: queryRaw,
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(saleFindMany).not.toHaveBeenCalled();
    expect(productFindMany).not.toHaveBeenCalled();
    expect(result.kpis.totalSales).toBe(3);
    expect(result.kpis.grossSales).toBeCloseTo(650);
    expect(result.kpis.returnedSales).toBeCloseTo(40);
    expect(result.kpis.netSales).toBeCloseTo(610);
    expect(result.kpis.creditPaymentsCash).toBeCloseTo(75);
    expect(result.kpis.creditPaymentsTransfer).toBeCloseTo(25);
    expect(result.audit).toEqual(
      expect.objectContaining({
        source: "database",
        saleRows: 3,
        saleItemRows: 4,
        returnedRows: 1,
        refundDocumentRows: 1,
        creditPaymentRows: 3,
        paymentBreakdownViolations: 1,
        categoryFiltered: false,
      }),
    );
  });

  it("no descuenta de utilidad los movimientos OUT con affectsProfit=false", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([sale()])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith({
      ...emptyPrisma(findMany),
      cashMovement: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            cashMovement({ amount: decimal(25), affectsProfit: false }),
          ]),
      },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.totalProfit).toBeCloseTo(40);
    expect(result.kpis.totalExpenses).toBeCloseTo(0);
    expect(result.kpis.netProfit).toBeCloseTo(40);
  });

  it("reduce la utilidad bruta por refunds antes de descontar gastos una sola vez", async () => {
    const refund = sale({
      id: "refund-profit",
      kind: "refund",
      totalSold: decimal(-20),
      totalCost: decimal(-12),
      totalProfit: decimal(-8),
      items: [
        item({
          subtotalSold: decimal(-20),
          subtotalCost: decimal(-12),
          profit: decimal(-8),
        }),
      ],
    });
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([sale()])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([refund]);
    const service = serviceWith({
      ...emptyPrisma(findMany),
      cashMovement: {
        findMany: jest
          .fn()
          .mockResolvedValue([cashMovement({ amount: decimal(10) })]),
      },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.totalProfit).toBeCloseTo(40);
    expect(result.kpis.totalExpenses).toBeCloseTo(10);
    expect(result.kpis.netProfit).toBeCloseTo(22);
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
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([saleInCategory, otherCategory])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
      category: "Accesorios",
    });

    expect(result.kpis.totalSales).toBe(1);
    // 100 / 1 (solo órdenes visibles de la categoría), no 100 / 2.
    expect(result.kpis.avgTicket).toBeCloseTo(100);
  });

  it("usa rango exclusivo (gte/lt) sin ventana 23:59:59.999", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith(emptyPrisma(findMany));

    await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    const saleWhere = findMany.mock.calls[0][0].where;
    expect(saleWhere.saleDate.gte).toEqual(
      new Date(Date.UTC(2026, 7, 1, 4, 0, 0, 0)),
    );
    expect(saleWhere.saleDate.lt).toEqual(
      new Date(Date.UTC(2026, 7, 23, 4, 0, 0, 0)),
    );
    expect(saleWhere.saleDate.lte).toBeUndefined();
  });

  it("rechaza un rango de fechas inválido", async () => {
    const service = serviceWith(emptyPrisma(jest.fn()));
    await expect(
      service.salesOverview(user as never, {
        from: "2026-08-22",
        to: "2026-08-01",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("no descuenta dos veces una venta devuelta y luego cancelada", async () => {
    // Venta de período anterior (600) devuelta 200 y cancelada en el período.
    // Reversión correcta del período: 600 (no 600 + 200 = 800).
    const cancelled = sale({
      id: "sale-cancelled",
      totalSold: decimal(600),
      items: [
        item({
          subtotalSold: decimal(600),
          subtotalCost: decimal(360),
          profit: decimal(240),
        }),
      ],
    });
    const refund = sale({
      id: "refund-1",
      kind: "refund",
      refundedSaleId: "sale-cancelled",
      totalSold: decimal(-200),
      items: [
        item({
          id: "refund-item-1",
          subtotalSold: decimal(-200),
          subtotalCost: decimal(-120),
          profit: decimal(-80),
        }),
      ],
    });
    const findMany = jest.fn((args: { where: Record<string, unknown> }) => {
      const where = args.where;
      if (where.kind === "refund") return Promise.resolve([refund]);
      if (where.kind === "invoice" && where.isDeleted === true) {
        return Promise.resolve([cancelled]);
      }
      return Promise.resolve([]);
    });
    const service = serviceWith({
      sale: { findMany },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      cashMovement: { findMany: jest.fn().mockResolvedValue([]) },
      saleCreditPayment: {
        findMany: jest.fn().mockResolvedValue([]),
        groupBy: jest.fn().mockResolvedValue([]),
      },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.returnedSales).toBe(600);
    expect(result.kpis.netSales).toBe(-600);
  });

  it("aísla todas las consultas por companyId (multiempresa)", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValue([]);
    const productFindMany = jest.fn().mockResolvedValue([]);
    const cashFindMany = jest.fn().mockResolvedValue([]);
    const creditFindMany = jest.fn().mockResolvedValue([]);
    const creditGroupBy = jest.fn().mockResolvedValue([]);
    const service = serviceWith({
      sale: { findMany },
      product: { findMany: productFindMany },
      cashMovement: { findMany: cashFindMany },
      saleCreditPayment: {
        findMany: creditFindMany,
        groupBy: creditGroupBy,
      },
    });

    await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    for (const call of findMany.mock.calls) {
      expect(call[0].where.companyId).toBe(user.companyId);
    }
    expect(productFindMany).toHaveBeenCalledWith({
      where: expect.objectContaining({ companyId: user.companyId }),
      select: expect.anything(),
      take: expect.any(Number),
    });
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

  it("mantiene KPIs aislados cuando una empresa tiene gastos y otra no", async () => {
    const userA = { ...user, companyId: "company-a" };
    const userB = { ...user, companyId: "company-b" };
    const findMany = jest.fn((args: { where: Record<string, unknown> }) => {
      const where = args.where;
      // La consulta real de facturas del período NO filtra por `isDeleted`
      // (la reversión de canceladas se resta aparte). Un mock que exige
      // `isDeleted === false` quedaba desactualizado y devolvía 0 ventas.
      if (where.kind === "invoice" && where.isDeleted === undefined) {
        return Promise.resolve([
          sale({
            companyId: where.companyId,
            totalProfit: decimal(1000),
            items: [item({ profit: decimal(1000) })],
          }),
        ]);
      }
      return Promise.resolve([]);
    });
    const cashFindMany = jest.fn((args: { where: { companyId: string } }) =>
      Promise.resolve(
        args.where.companyId === "company-a"
          ? [cashMovement({ companyId: "company-a", amount: decimal(700) })]
          : [],
      ),
    );
    const service = serviceWith({
      sale: { findMany },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      cashMovement: { findMany: cashFindMany },
      saleCreditPayment: {
        findMany: jest.fn().mockResolvedValue([]),
        groupBy: jest.fn().mockResolvedValue([]),
      },
    });

    const resultA = await service.salesOverview(userA as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });
    const resultB = await service.salesOverview(userB as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(resultA.kpis.totalExpenses).toBeCloseTo(700);
    expect(resultA.kpis.netProfit).toBeCloseTo(300);
    expect(resultB.kpis.totalExpenses).toBeCloseTo(0);
    expect(resultB.kpis.netProfit).toBeCloseTo(1000);
  });

  it("devoluciones nulas (sin items) no rompen el reporte (null safety)", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        sale({ id: "r-null", kind: "refund", items: [] }),
      ]);
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.netSales).toBe(0);
    expect(result.kpis.totalReturns).toBe(1);
    expect(Number.isNaN(result.kpis.netSales)).toBe(false);
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
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([invoice])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.topProducts).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          productName: "Tela",
          unitCode: "YARD",
          totalQtyLabel: "1.5 yd",
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
        totalQtyLabel: "2 u + 1.5 yd + 2.375 lb",
        quantityBuckets: expect.arrayContaining([
          expect.objectContaining({ unitCode: "UNIT", quantity: 2 }),
          expect.objectContaining({ unitCode: "YARD", quantity: 1.5 }),
          expect.objectContaining({ unitCode: "POUND", quantity: 2.375 }),
        ]),
      }),
    );
  });

  it("caracteriza ventas mixtas, credito, impuestos, descuentos, categorias, tops e inventario", async () => {
    const saleCash = sale({
      id: "sale-cash",
      customerId: "client-1",
      customer: { id: "client-1", nombre: "Cliente Uno" },
      saleDate: new Date("2026-08-10T12:00:00.000Z"),
      totalSold: decimal(200),
      totalCost: decimal(120),
      totalProfit: decimal(80),
      commissionAmount: decimal(8),
      discountAmount: decimal(25),
      paymentMethod: "cash",
      paymentCashAmount: decimal(200),
      paymentTransferAmount: decimal(0),
      items: [
        item({
          id: "cash-a",
          productId: "prod-a",
          productNameSnapshot: "Cafe",
          qty: decimal(2),
          subtotalSold: decimal(120),
          subtotalCost: decimal(70),
          profit: decimal(50),
          taxableBase: decimal(100),
          taxAmount: decimal(18),
          exemptAmount: decimal(0),
          lineDiscountAmount: decimal(10),
          product: { categoria: "Bebidas" },
        }),
        item({
          id: "cash-b",
          productId: "prod-b",
          productNameSnapshot: "Pan",
          qty: decimal(1),
          subtotalSold: decimal(80),
          subtotalCost: decimal(50),
          profit: decimal(30),
          taxableBase: decimal(0),
          taxAmount: decimal(0),
          exemptAmount: decimal(80),
          lineDiscountAmount: decimal(5),
          product: { categoria: "Panaderia" },
        }),
      ],
    });
    const saleCard = sale({
      id: "sale-card",
      customerId: "client-2",
      customer: { id: "client-2", nombre: "Cliente Dos" },
      saleDate: new Date("2026-08-11T12:00:00.000Z"),
      totalSold: decimal(150),
      totalCost: decimal(90),
      totalProfit: decimal(60),
      commissionAmount: decimal(6),
      paymentMethod: "card",
      paymentCashAmount: decimal(0),
      paymentTransferAmount: decimal(150),
      items: [
        item({
          id: "card-a",
          productId: "prod-c",
          productNameSnapshot: "Bizcocho",
          qty: decimal(1),
          subtotalSold: decimal(150),
          subtotalCost: decimal(90),
          profit: decimal(60),
          taxableBase: decimal(150),
          taxAmount: decimal(27),
          exemptAmount: decimal(0),
          product: { categoria: "Panaderia" },
        }),
      ],
    });
    const saleCredit = sale({
      id: "sale-credit",
      customerId: "client-1",
      customer: { id: "client-1", nombre: "Cliente Uno" },
      saleDate: new Date("2026-08-12T12:00:00.000Z"),
      totalSold: decimal(300),
      totalCost: decimal(180),
      totalProfit: decimal(120),
      commissionAmount: decimal(12),
      paymentMethod: "credit",
      paymentCashAmount: decimal(200),
      paymentTransferAmount: decimal(0),
      items: [
        item({
          id: "credit-a",
          productId: "prod-d",
          productNameSnapshot: "Producto sin categoria",
          qty: decimal(3),
          subtotalSold: decimal(300),
          subtotalCost: decimal(180),
          profit: decimal(120),
          taxableBase: decimal(0),
          taxAmount: decimal(0),
          exemptAmount: decimal(300),
          product: null,
        }),
      ],
    });
    const products = [
      {
        id: "prod-a",
        nombre: "Cafe",
        categoria: "Bebidas",
        costo: decimal(35),
        precio: decimal(60),
        stock: decimal(2),
        unitOfMeasure: {
          code: "UNIT",
          name: "Unidad",
          symbol: "u",
          precision: 0,
        },
      },
      {
        id: "prod-b",
        nombre: "Pan",
        categoria: "Panaderia",
        costo: decimal(50),
        precio: decimal(80),
        stock: decimal(0),
        unitOfMeasure: {
          code: "UNIT",
          name: "Unidad",
          symbol: "u",
          precision: 0,
        },
      },
      {
        id: "prod-d",
        nombre: "Producto sin categoria",
        categoria: "",
        costo: decimal(60),
        precio: decimal(100),
        stock: decimal(5),
        unitOfMeasure: {
          code: "UNIT",
          name: "Unidad",
          symbol: "u",
          precision: 0,
        },
      },
    ];
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([saleCash, saleCard, saleCredit])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const service = serviceWith({
      ...emptyPrisma(findMany),
      product: { findMany: jest.fn().mockResolvedValue(products) },
      saleCreditPayment: {
        findMany: jest.fn().mockResolvedValue([
          {
            saleId: "sale-credit",
            cashAmount: decimal(50),
            transferAmount: decimal(25),
            amount: decimal(75),
            sale: {
              items: [
                {
                  subtotalSold: decimal(300),
                  product: null,
                },
              ],
            },
          },
        ]),
        groupBy: jest.fn().mockResolvedValue([
          {
            saleId: "sale-credit",
            _sum: {
              cashAmount: decimal(50),
              transferAmount: decimal(25),
              amount: decimal(75),
            },
          },
        ]),
      },
    });

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    expect(result.kpis.totalSales).toBe(3);
    expect(result.kpis.grossSales).toBeCloseTo(650);
    expect(result.kpis.netSales).toBeCloseTo(650);
    expect(result.kpis.totalCost).toBeCloseTo(390);
    expect(result.kpis.totalProfit).toBeCloseTo(260);
    expect(result.kpis.netProfit).toBeCloseTo(260);
    expect(result.kpis.cashIncome).toBeCloseTo(400);
    expect(
      result.paymentMethods.find((row) => row.method === "Efectivo")?.amount,
    ).toBeCloseTo(400);
    // Caracterizacion actual: paymentTransferAmount es acumulado; si el ledger
    // trae una transferencia que no esta en el acumulado de la venta, el pago
    // inicial queda negativo y el abono del periodo lo compensa.
    expect(
      result.paymentMethods.find((row) => row.method === "Transferencia")
        ?.amount,
    ).toBeCloseTo(150);
    expect(result.kpis.creditPaymentsCash).toBeCloseTo(50);
    expect(result.kpis.creditPaymentsTransfer).toBeCloseTo(25);
    expect(result.kpis.creditPaymentsCount).toBe(1);
    expect(result.kpis.taxableBase).toBeCloseTo(250);
    expect(result.kpis.taxAmount).toBeCloseTo(45);
    expect(result.kpis.exemptAmount).toBeCloseTo(380);
    expect(result.kpis.discountAmount).toBeCloseTo(25);
    expect(result.salesSeries).toEqual([
      { label: "2026-08-10", value: 200 },
      { label: "2026-08-11", value: 150 },
      { label: "2026-08-12", value: 300 },
    ]);
    expect(result.topClients).toEqual([
      { clientName: "Cliente Uno", totalSpent: 500, purchaseCount: 2 },
      { clientName: "Cliente Dos", totalSpent: 150, purchaseCount: 1 },
    ]);
    expect(result.topProducts[0]).toEqual(
      expect.objectContaining({
        productName: "Producto sin categoria",
        totalSales: 300,
        totalQty: 3,
      }),
    );
    expect(result.categoryProfits).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          category: "Sin categoria",
          totalSales: 300,
          totalProfit: 120,
          salesCount: 1,
        }),
        expect.objectContaining({
          category: "Panaderia",
          totalSales: 230,
          totalProfit: 90,
          salesCount: 2,
        }),
        expect.objectContaining({
          category: "Bebidas",
          totalSales: 120,
          totalProfit: 50,
          salesCount: 1,
        }),
      ]),
    );
    expect(result.categories).toEqual(["Bebidas", "Panaderia", "Sin categoria"]);
    expect(result.inventory).toEqual(
      expect.objectContaining({
        products: 3,
        units: 7,
        costValue: 370,
        saleValue: 620,
        outOfStock: 1,
        lowStock: 1,
        productsWithoutCost: 0,
      }),
    );
    expect(result.audit).toEqual(
      expect.objectContaining({
        source: "database",
        saleRows: 3,
        saleItemRows: 4,
        returnedRows: 0,
        creditPaymentRows: 1,
        categoryFiltered: false,
      }),
    );
  });
});
