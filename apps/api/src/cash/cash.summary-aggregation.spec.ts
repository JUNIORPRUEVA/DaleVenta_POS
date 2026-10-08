import { Prisma } from "@prisma/client";
import { CashService } from "./cash.service";

describe("CashService aggregated summary equivalence", () => {
  const companyId = "11111111-1111-1111-1111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";

  function dec(value: number | string) {
    return new Prisma.Decimal(value);
  }

  const sales = [
    {
      id: "sale-cash",
      totalSold: dec(500),
      totalProfit: dec(180),
      paymentMethod: "cash",
      paymentCashAmount: dec(500),
      paymentTransferAmount: dec(0),
      creditAmount: dec(0),
      creditBalance: dec(0),
      isDeleted: false,
      kind: "invoice",
      items: [
        {
          subtotalSold: dec(300),
          profit: dec(100),
          productNameSnapshot: "Cafe",
          product: { categoria: "Bebidas" },
        },
        {
          subtotalSold: dec(200),
          profit: dec(80),
          productNameSnapshot: "Sandwich",
          product: { categoria: "Comida" },
        },
      ],
    },
    {
      id: "sale-credit",
      totalSold: dec(1000),
      totalProfit: dec(300),
      paymentMethod: "credit",
      paymentCashAmount: dec(350),
      paymentTransferAmount: dec(200),
      creditAmount: dec(1000),
      creditBalance: dec(450),
      isDeleted: false,
      kind: "invoice",
      items: [
        {
          subtotalSold: dec(1000),
          profit: dec(300),
          productNameSnapshot: "Servicio",
          product: null,
        },
      ],
    },
    {
      id: "sale-refund",
      totalSold: dec(-120),
      totalProfit: dec(-40),
      paymentMethod: "refund",
      paymentCashAmount: dec(-120),
      paymentTransferAmount: dec(0),
      creditAmount: dec(0),
      creditBalance: dec(0),
      isDeleted: false,
      kind: "refund",
      items: [],
    },
  ];

  const sessionPayments = [
    {
      saleId: "sale-credit",
      amount: dec(150),
      cashAmount: dec(100),
      transferAmount: dec(50),
    },
  ];
  const lifetimeLedger = [
    {
      saleId: "sale-credit",
      _sum: {
        amount: dec(250),
        cashAmount: dec(200),
        transferAmount: dec(50),
      },
    },
  ];
  const movements = [
    { type: "IN", amount: dec(40), movementType: "expense", affectsProfit: true },
    { type: "OUT", amount: dec(25), movementType: "expense", affectsProfit: true },
    { type: "OUT", amount: dec(10), movementType: "owner_draw", affectsProfit: false },
  ];

  function legacyService() {
    const prisma = {
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: sessionId,
          initialAmount: dec(100),
        }),
      },
      sale: { findMany: jest.fn().mockResolvedValue(sales) },
      cashMovement: { findMany: jest.fn().mockResolvedValue(movements) },
      saleCreditPayment: {
        findMany: jest.fn().mockResolvedValue(sessionPayments),
        groupBy: jest.fn().mockResolvedValue(lifetimeLedger),
      },
    };
    return new CashService(prisma as never, { emitCompany: jest.fn() } as never);
  }

  function aggregatedService() {
    const prisma = {
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: sessionId,
          initialAmount: dec(100),
        }),
      },
      sale: {
        groupBy: jest.fn().mockResolvedValue([
          {
            isDeleted: false,
            kind: "invoice",
            paymentMethod: "cash",
            _count: { id: 1 },
            _sum: {
              totalSold: dec(500),
              paymentCashAmount: dec(500),
              paymentTransferAmount: dec(0),
              creditBalance: dec(0),
            },
          },
          {
            isDeleted: false,
            kind: "invoice",
            paymentMethod: "credit",
            _count: { id: 1 },
            _sum: {
              totalSold: dec(1000),
              paymentCashAmount: dec(350),
              paymentTransferAmount: dec(200),
              creditBalance: dec(450),
            },
          },
          {
            isDeleted: false,
            kind: "refund",
            paymentMethod: "refund",
            _count: { id: 1 },
            _sum: {
              totalSold: dec(-120),
              paymentCashAmount: dec(-120),
              paymentTransferAmount: dec(0),
              creditBalance: dec(0),
            },
          },
        ]),
      },
      cashMovement: {
        groupBy: jest.fn().mockResolvedValue([
          {
            type: "IN",
            movementType: "expense",
            affectsProfit: true,
            _sum: { amount: dec(40) },
          },
          {
            type: "OUT",
            movementType: "expense",
            affectsProfit: true,
            _sum: { amount: dec(25) },
          },
          {
            type: "OUT",
            movementType: "owner_draw",
            affectsProfit: false,
            _sum: { amount: dec(10) },
          },
        ]),
      },
      saleCreditPayment: {
        aggregate: jest
          .fn()
          .mockResolvedValueOnce({
            _sum: { cashAmount: dec(200), transferAmount: dec(50) },
          })
          .mockResolvedValueOnce({
            _sum: {
              amount: dec(150),
              cashAmount: dec(100),
              transferAmount: dec(50),
            },
          }),
      },
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([
          {
            category: "Sin categoria",
            totalSold: dec(1000),
            totalProfit: dec(300),
            items: 1,
          },
          {
            category: "Bebidas",
            totalSold: dec(300),
            totalProfit: dec(100),
            items: 1,
          },
          {
            category: "Comida",
            totalSold: dec(200),
            totalProfit: dec(80),
            items: 1,
          },
        ])
        .mockResolvedValueOnce([{ count: 0 }]),
    };
    return {
      service: new CashService(
        prisma as never,
        { emitCompany: jest.fn() } as never,
      ),
      prisma,
    };
  }

  it("matches the legacy reference field by field without loading sales/items", async () => {
    const expected = await legacyService().buildSummaryForSession(
      sessionId,
      companyId,
    );
    const { service, prisma } = aggregatedService();
    const actual = await service.buildSummaryForSession(sessionId, companyId);

    expect(actual).toEqual(expected);
    expect(prisma.sale.groupBy).toHaveBeenCalledTimes(1);
    expect(prisma.saleCreditPayment.aggregate).toHaveBeenCalledTimes(2);
    expect(prisma.cashMovement.groupBy).toHaveBeenCalledTimes(1);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
  });
});
