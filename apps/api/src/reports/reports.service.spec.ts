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
    return {
      sale: { findMany },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      cashMovement: { findMany: jest.fn().mockResolvedValue([]) },
    };
  }

  it("restringe devoluciones a reversiones de períodos anteriores (sin doble descuento)", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([]) // sales activas
      .mockResolvedValueOnce([]) // returnedSales
      .mockResolvedValueOnce([]); // refundSales
    const service = serviceWith(emptyPrisma(findMany));

    const result = await service.salesOverview(user as never, {
      from: "2026-08-01",
      to: "2026-08-22",
    });

    // La consulta de devoluciones ahora exige saleDate < inicio del rango:
    // una venta creada y anulada dentro del mismo período NO se descuenta dos
    // veces y el neto no puede quedar negativo.
    const returnedWhere = findMany.mock.calls[1][0].where;
    expect(returnedWhere).toMatchObject({
      companyId: user.companyId,
      kind: "invoice",
      isDeleted: true,
    });
    expect(returnedWhere.saleDate).toEqual({
      lt: new Date(Date.UTC(2026, 7, 1, 4, 0, 0, 0)),
    });
    expect(result.kpis.netSales).toBe(0);
    expect(result.kpis.totalReturns).toBe(0);
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

  it("aísla todas las consultas por companyId (multiempresa)", async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const productFindMany = jest.fn().mockResolvedValue([]);
    const cashFindMany = jest.fn().mockResolvedValue([]);
    const service = serviceWith({
      sale: { findMany },
      product: { findMany: productFindMany },
      cashMovement: { findMany: cashFindMany },
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
    });
    expect(cashFindMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId: user.companyId }),
      }),
    );
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
});
