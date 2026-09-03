import { Prisma } from "@prisma/client";
import { CashService } from "./cash.service";

/**
 * Regresión TICKET-CASH-CHANGE-02:
 * aunque la venta persista cashReceived=1000 y changeAmount=150, el resumen
 * del turno (expectedCash / salesCashTotal) debe seguir usando el efectivo
 * NETO retenido (paymentCashAmount=850), NUNCA el tender (1000).
 */
describe("CashService net-cash summary regression (TICKET-CASH-CHANGE-02)", () => {
  const companyId = "11111111-1111-1111-1111-111111111111";

  function harness(sale: Record<string, unknown>) {
    const prisma = {
      cashSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: "shift-1",
          initialAmount: new Prisma.Decimal(0),
        }),
      },
      sale: {
        findMany: jest.fn().mockResolvedValue([sale]),
      },
      cashMovement: { findMany: jest.fn().mockResolvedValue([]) },
      saleCreditPayment: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const realtime = { emitCompany: jest.fn() };
    const service = new CashService(prisma as never, realtime as never);
    return { service };
  }

  const netCashSale = {
    totalSold: new Prisma.Decimal(850),
    totalProfit: new Prisma.Decimal(425),
    paymentMethod: "cash",
    paymentCashAmount: new Prisma.Decimal(850), // NETO retenido (1000 recibido - 150 devuelta)
    paymentTransferAmount: new Prisma.Decimal(0),
    creditAmount: new Prisma.Decimal(0),
    creditBalance: new Prisma.Decimal(0),
    isDeleted: false,
    kind: "invoice",
    items: [],
  };

  it("expectedCash y salesCashTotal usan el NETO (850), no el tender (1000)", async () => {
    const { service } = harness(netCashSale);
    const summary = await service.buildSummaryForSession("shift-1", companyId);
    expect(summary.salesCashTotal).toBeCloseTo(850, 2);
    expect(summary.expectedCash).toBeCloseTo(850, 2);
    expect(summary.expectedCash).not.toBeCloseTo(1000, 2);
    expect(summary.totalTickets).toBe(1);
  });

  it("una venta por transferencia no suma efectivo", async () => {
    const { service } = harness({
      ...netCashSale,
      paymentMethod: "transfer",
      paymentCashAmount: new Prisma.Decimal(0),
      paymentTransferAmount: new Prisma.Decimal(850),
    });
    const summary = await service.buildSummaryForSession("shift-1", companyId);
    expect(summary.salesCashTotal).toBeCloseTo(0, 2);
    expect(summary.salesTransferTotal).toBeCloseTo(850, 2);
    expect(summary.expectedCash).toBeCloseTo(0, 2);
  });
});
