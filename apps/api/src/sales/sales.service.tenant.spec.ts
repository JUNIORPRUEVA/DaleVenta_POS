import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

describe("SalesService tenant isolation", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  function serviceWith(prisma: Record<string, unknown>) {
    return new SalesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      { emitCompany: jest.fn() } as never,
      {
        getCompanyFiscalSettings: jest.fn().mockResolvedValue({
          taxEnabled: false,
          defaultTaxRate: 0,
          pricesIncludeTax: false,
          ncfEnabled: false,
        }),
        resolvePriceMode: jest.fn().mockReturnValue("NO_TAX"),
        calculatorService: { calculate: jest.fn() },
      } as never,
      {
        normalizeType: jest.fn(),
        reserveNextNcf: jest.fn(),
        markIssued: jest.fn(),
      } as never,
    );
  }

  it("rejects clientId from another company when creating a sale", async () => {
    const prisma = {
      sale: { findFirst: jest.fn() },
      client: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        customerId: "22222222-2222-4222-8222-222222222222",
        items: [
          {
            productName: "Servicio",
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 50,
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.client.findFirst).toHaveBeenCalledWith({
      where: {
        id: "22222222-2222-4222-8222-222222222222",
        companyId: user.companyId,
        isDeleted: false,
      },
      select: {
        nombre: true,
        telefono: true,
        taxId: true,
        businessName: true,
        direccion: true,
      },
    });
  });

  it("rejects productId from another company when creating a sale", async () => {
    const prisma = {
      sale: { findFirst: jest.fn() },
      product: { findMany: jest.fn().mockResolvedValue([]) },
      company: {
        findFirst: jest.fn().mockResolvedValue({ name: "Empresa A" }),
      },
      appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        items: [
          {
            productId: "22222222-2222-4222-8222-222222222222",
            qty: 1,
            priceSoldUnit: 100,
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.product.findMany).toHaveBeenCalledWith({
      where: {
        id: { in: ["22222222-2222-4222-8222-222222222222"] },
        companyId: user.companyId,
        archivedAt: null,
      },
      select: {
        id: true,
        nombre: true,
        imagen: true,
        costo: true,
        stock: true,
        itemType: true,
        trackInventory: true,
        taxTreatment: true,
        taxRate: true,
        taxPriceMode: true,
        unitOfMeasure: {
          select: {
            code: true,
            name: true,
            symbol: true,
            allowDecimals: true,
            precision: true,
          },
        },
      },
    });
  });

  it("stores LOCAL product identity for local sale lines", () => {
    const service = serviceWith({} as any);
    const product = {
      id: "11111111-1111-4111-8111-111111111111",
      nombre: "Tela local",
      imagen: null,
      costo: 10,
      stock: 20,
      taxTreatment: "INHERIT",
      taxRate: null,
      taxPriceMode: null,
      unitOfMeasure: {
        code: "YARD",
        name: "Yarda",
        symbol: "yd",
        allowDecimals: true,
        precision: 3,
      },
    };

    const normalized = (service as any).normalizeItem(
      {
        productId: product.id,
        qty: 5.5,
        priceSoldUnit: 20,
      },
      0,
      new Map([[product.id, product]]),
    );

    expect(normalized).toMatchObject({
      productId: product.id,
      productSource: "LOCAL",
      sourceProductId: product.id,
      productNameSnapshot: "Tela local",
      unitCodeSnapshot: "YARD",
    });
  });

  it("rejects FULLPOS sale lines until writable stock is proven", async () => {
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(null) },
      company: {
        findFirst: jest.fn().mockResolvedValue({ name: "Empresa A" }),
      },
      appConfig: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(
        user as never,
        {
          items: [
            {
              productName: "Tela FULLPOS",
              productSource: "FULLPOS",
              sourceProductId: "same-remote-id",
              qty: 5.5,
              priceSoldUnit: 20,
              costUnitSnapshot: 10,
            },
          ],
        } as never,
      ),
    ).rejects.toThrow("FULLPOS");
  });

  it("returns the existing sale for the same company and clientRequestId", async () => {
    const existingSale = {
      id: "33333333-3333-4333-8333-333333333333",
      companyId: user.companyId,
      clientRequestId: "sale-request-1",
      items: [],
    };
    const prisma = {
      sale: { findFirst: jest.fn().mockResolvedValue(existingSale) },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(user as never, {
        clientRequestId: "sale-request-1",
        items: [
          {
            productName: "Servicio",
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 50,
          },
        ],
      }),
    ).resolves.toBe(existingSale);

    expect(prisma.sale.findFirst).toHaveBeenCalledWith({
      where: { companyId: user.companyId, clientRequestId: "sale-request-1" },
      include: expect.any(Object),
    });
  });

  it("falls back to a compatible sale list instead of returning empty on schema mismatch", async () => {
    const fallbackSale = {
      id: "44444444-4444-4444-8444-444444444444",
      userId: user.id,
      customerId: null,
      saleDate: new Date("2026-08-20T12:00:00.000Z"),
      note: null,
      totalSold: 3300,
      totalCost: 0,
      totalProfit: 3300,
      commissionAmount: 330,
      paymentMethod: "cash",
      paymentCashAmount: 3300,
      paymentTransferAmount: 0,
      creditAmount: 0,
      creditPaidAmount: 0,
      creditBalance: 0,
      creditStatus: "none",
      kind: "invoice",
      status: "PAID",
      isDeleted: false,
      deletedAt: null,
    };
    const prisma = {
      sale: {
        findMany: jest
          .fn()
          .mockRejectedValueOnce({ code: "P2022" })
          .mockResolvedValueOnce([fallbackSale]),
      },
    };
    const service = serviceWith(prisma);

    const rows = await service.listInvoices(
      user as never,
      "2026-08-01",
      "2026-08-20",
      undefined,
      true,
    );

    expect(rows).toEqual([
      expect.objectContaining({
        ...fallbackSale,
        returnStatus: "ACTIVE",
        canReturn: true,
      }),
    ]);

    expect(prisma.sale.findMany).toHaveBeenCalledTimes(2);
    expect(prisma.sale.findMany).toHaveBeenLastCalledWith({
      where: {
        companyId: user.companyId,
        kind: "invoice",
        saleDate: {
          gte: new Date("2026-08-01T04:00:00.000Z"),
          lt: new Date("2026-08-21T04:00:00.000Z"),
        },
      },
      orderBy: { saleDate: "desc" },
      select: expect.objectContaining({
        id: true,
        totalSold: true,
        saleDate: true,
      }),
    });
  });

  it("listInvoices scopes by companyId and applies take when limit is provided", async () => {
    const prisma = {
      sale: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    await service.listInvoices(
      user as never,
      "2026-08-01",
      "2026-08-20",
      undefined,
      false,
      20,
    );

    expect(prisma.sale.findMany).toHaveBeenCalledWith({
      where: {
        companyId: user.companyId,
        kind: "invoice",
        isDeleted: false,
        saleDate: {
          gte: new Date("2026-08-01T04:00:00.000Z"),
          lt: new Date("2026-08-21T04:00:00.000Z"),
        },
      },
      orderBy: { saleDate: "desc" },
      take: 20,
      include: expect.any(Object),
    });
  });

  it("listMine scopes by companyId and applies take when limit is provided", async () => {
    const prisma = {
      sale: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    await service.listMine(
      user as never,
      "2026-08-01",
      "2026-08-20",
      undefined,
      false,
      20,
    );

    expect(prisma.sale.findMany).toHaveBeenCalledWith({
      where: {
        companyId: user.companyId,
        isDeleted: false,
        saleDate: {
          gte: new Date("2026-08-01T04:00:00.000Z"),
          lt: new Date("2026-08-21T04:00:00.000Z"),
        },
      },
      orderBy: { saleDate: "desc" },
      take: 20,
      include: expect.any(Object),
    });
  });

  it("listInvoices without limit does not add take", async () => {
    const prisma = {
      sale: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    await service.listInvoices(
      user as never,
      "2026-08-01",
      "2026-08-20",
      undefined,
      false,
    );

    expect(prisma.sale.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ take: undefined }),
    );
  });

  it("derives return summary for invoices without exposing refund documents", async () => {
    const invoice = {
      id: "invoice-1",
      companyId: user.companyId,
      userId: user.id,
      customerId: null,
      saleDate: new Date("2026-08-20T12:00:00.000Z"),
      totalSold: new Prisma.Decimal(100),
      kind: "invoice",
      isDeleted: false,
      items: [
        {
          id: "item-1",
          qty: new Prisma.Decimal(2),
        },
      ],
      refunds: [
        {
          id: "refund-1",
          kind: "refund",
          isDeleted: false,
          totalSold: new Prisma.Decimal(-50),
          items: [
            {
              refundedSaleItemId: "item-1",
              qty: new Prisma.Decimal(1),
              subtotalSold: new Prisma.Decimal(-50),
            },
          ],
        },
      ],
    };
    const prisma = {
      sale: { findMany: jest.fn().mockResolvedValue([invoice]) },
    };
    const service = serviceWith(prisma);

    const rows = await service.listInvoices(user as never);

    expect(prisma.sale.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          companyId: user.companyId,
          kind: "invoice",
          isDeleted: false,
        }),
      }),
    );
    expect(rows).toEqual([
      expect.objectContaining({
        id: "invoice-1",
        returnStatus: "PARTIALLY_RETURNED",
        canReturn: true,
      }),
    ]);
    expect(rows[0].returnedAmount.toString()).toBe("50");
    expect(rows[0].returnableAmount.toString()).toBe("50");
  });

  describe("financial summary cancellation policy", () => {
    function money(value: number | string | null) {
      return value === null ? null : new Prisma.Decimal(value);
    }

    function aggregate(
      totalSold: number | string | null,
      totalCost: number | string | null,
      totalProfit: number | string | null,
      commissionAmount: number | string | null,
    ) {
      return {
        _sum: {
          totalSold: money(totalSold),
          totalCost: money(totalCost),
          totalProfit: money(totalProfit),
          commissionAmount: money(commissionAmount),
        },
      };
    }

    function summaryRow(
      userId: string,
      totalSold: number,
      totalProfit: number,
      commissionAmount: number,
    ) {
      return {
        userId,
        totalSold: new Prisma.Decimal(totalSold),
        totalProfit: new Prisma.Decimal(totalProfit),
        commissionAmount: new Prisma.Decimal(commissionAmount),
      };
    }

    it("reverses a prior-period cancelled sale in the cancellation period", async () => {
      const aggregateMock = jest
        .fn()
        .mockResolvedValueOnce(aggregate(null, null, null, null))
        .mockResolvedValueOnce(aggregate(null, null, null, null))
        .mockResolvedValueOnce(aggregate(1000, 700, 300, 30));
      const countMock = jest.fn().mockResolvedValue(0);
      const service = serviceWith({
        sale: { aggregate: aggregateMock, count: countMock },
      });

      const summary = await service.summaryMine(
        user as never,
        "2026-09-08",
        "2026-09-08",
      );

      expect(summary).toMatchObject({
        totalSales: 0,
        totalSold: -1000,
        totalCost: -700,
        totalProfit: -300,
        totalCommission: -30,
      });
      expect(aggregateMock.mock.calls[2][0].where).toMatchObject({
        companyId: user.companyId,
        kind: "invoice",
        isDeleted: true,
        deletedAt: {
          gte: new Date("2026-09-08T04:00:00.000Z"),
          lt: new Date("2026-09-09T04:00:00.000Z"),
        },
        saleDate: { lt: new Date("2026-09-08T04:00:00.000Z") },
      });
    });

    it("keeps an active non-cancelled sale summary unchanged", async () => {
      const service = serviceWith({
        sale: {
          aggregate: jest
            .fn()
            .mockResolvedValueOnce(aggregate(1000, 700, 300, 30))
            .mockResolvedValueOnce(aggregate(null, null, null, null))
            .mockResolvedValueOnce(aggregate(null, null, null, null)),
          count: jest.fn().mockResolvedValue(1),
        },
      });

      await expect(
        service.summaryMine(user as never, "2026-09-07", "2026-09-07"),
      ).resolves.toMatchObject({
        totalSales: 1,
        totalSold: 1000,
        totalCost: 700,
        totalProfit: 300,
        totalCommission: 30,
      });
    });

    it("does not double-reverse an idempotent cancellation represented by one cancelled sale row", async () => {
      const service = serviceWith({
        sale: {
          aggregate: jest
            .fn()
            .mockResolvedValueOnce(aggregate(null, null, null, null))
            .mockResolvedValueOnce(aggregate(null, null, null, null))
            .mockResolvedValueOnce(aggregate(1000, 700, 300, 30)),
          count: jest.fn().mockResolvedValue(0),
        },
      });

      await expect(
        service.summaryMine(user as never, "2026-09-08", "2026-09-08"),
      ).resolves.toMatchObject({
        totalSold: -1000,
        totalCost: -700,
        totalProfit: -300,
      });
    });

    it("scopes active refund and cancelled summary queries by companyId", async () => {
      const aggregateMock = jest
        .fn()
        .mockResolvedValueOnce(aggregate(100, 70, 30, 3))
        .mockResolvedValueOnce(aggregate(-20, -14, -6, 0))
        .mockResolvedValueOnce(aggregate(50, 35, 15, 1.5));
      const countMock = jest.fn().mockResolvedValue(1);
      const service = serviceWith({
        sale: { aggregate: aggregateMock, count: countMock },
      });

      await service.summaryMine(user as never, "2026-09-08", "2026-09-08");

      for (const call of aggregateMock.mock.calls) {
        expect(call[0].where.companyId).toBe(user.companyId);
      }
      expect(countMock.mock.calls[0][0].where.companyId).toBe(user.companyId);
    });

    it("reconciles summaryMine and summaryByUser for the same seller and period", async () => {
      const saleApi = {
        aggregate: jest
          .fn()
          .mockResolvedValueOnce(aggregate(1000, 700, 300, 30))
          .mockResolvedValueOnce(aggregate(-200, -140, -60, 0))
          .mockResolvedValueOnce(aggregate(100, 70, 30, 3)),
        count: jest.fn().mockResolvedValue(1),
        findMany: jest
          .fn()
          .mockResolvedValueOnce([summaryRow(user.id, 1000, 300, 30)])
          .mockResolvedValueOnce([summaryRow(user.id, -200, -60, 0)])
          .mockResolvedValueOnce([summaryRow(user.id, 100, 30, 3)]),
      };
      const service = serviceWith({
        sale: saleApi,
        user: {
          findMany: jest
            .fn()
            .mockResolvedValue([
              {
                id: user.id,
                email: "user@demo.test",
                nombreCompleto: "User A",
              },
            ]),
        },
      });

      const mine = await service.summaryMine(
        user as never,
        "2026-09-08",
        "2026-09-08",
      );
      const byUser = await service.summaryByUser(
        user as never,
        "2026-09-08",
        "2026-09-08",
        user.id,
      );

      expect(byUser.totals.totalSold).toBeCloseTo(mine.totalSold);
      expect(byUser.totals.totalProfit).toBeCloseTo(mine.totalProfit);
      expect(byUser.totals.totalCommission).toBeCloseTo(mine.totalCommission);
      expect(saleApi.findMany.mock.calls[0][0].where).toMatchObject({
        companyId: user.companyId,
        userId: user.id,
        kind: "invoice",
        isDeleted: false,
      });
    });
  });

  describe("profit snapshot regressions", () => {
    const product = {
      id: "11111111-1111-4111-8111-111111111111",
      nombre: "Producto historico",
      imagen: null,
      costo: new Prisma.Decimal(100),
      stock: new Prisma.Decimal(10),
      taxTreatment: "INHERIT",
      taxRate: null,
      taxPriceMode: null,
      unitOfMeasure: {
        code: "UNIT",
        name: "Unidad",
        symbol: "u",
        allowDecimals: false,
        precision: 0,
      },
    };

    it("keeps historical profit based on the sale-time cost snapshot", () => {
      const service = serviceWith({} as any);
      const normalized = (service as any).normalizeItem(
        { productId: product.id, qty: 2, priceSoldUnit: 150 },
        0,
        new Map([[product.id, product]]),
      );
      product.costo = new Prisma.Decimal(150);

      expect(normalized.costUnitSnapshot.toString()).toBe("100");
      expect(normalized.subtotalCost.toString()).toBe("200");
      expect(normalized.profit.toString()).toBe("100");
    });

    it("keeps a sale snapshot unchanged after a later purchase updates Product.costo", () => {
      const service = serviceWith({} as any);
      const normalized = (service as any).normalizeItem(
        { productId: product.id, qty: 1, priceSoldUnit: 150 },
        0,
        new Map([[product.id, { ...product, costo: new Prisma.Decimal(100) }]]),
      );
      const productAfterPurchase = {
        ...product,
        costo: new Prisma.Decimal(140),
      };

      expect(productAfterPurchase.costo.toString()).toBe("140");
      expect(normalized.costUnitSnapshot.toString()).toBe("100");
      expect(normalized.profit.toString()).toBe("50");
    });

    it("reconciles quick/manual sale and normal sale profit for the same economics", () => {
      const service = serviceWith({} as any);
      const normal = (service as any).normalizeItem(
        { productId: product.id, qty: 2, priceSoldUnit: 150 },
        0,
        new Map([[product.id, { ...product, costo: new Prisma.Decimal(100) }]]),
      );
      const quick = (service as any).normalizeItem(
        {
          productName: "Producto historico",
          qty: 2,
          priceSoldUnit: 150,
          costUnitSnapshot: 100,
        },
        0,
        new Map(),
      );

      expect(quick.subtotalSold.toString()).toBe(
        normal.subtotalSold.toString(),
      );
      expect(quick.subtotalCost.toString()).toBe(
        normal.subtotalCost.toString(),
      );
      expect(quick.profit.toString()).toBe(normal.profit.toString());
    });
  });
});
