import {
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { CashService } from "./cash.service";

/**
 * Pruebas del invariante multi-dispositivo del turno de caja:
 *  - UN solo turno abierto por (usuario + empresa).
 *  - Doble apertura concurrente: el reintento SERIALIZABLE devuelve el turno
 *    existente en lugar de crear un segundo.
 *  - Doble cierre / cerrar un turno ya cerrado: respuesta controlada, nunca
 *    duplica movimientos ni rompe saldo.
 * La fuente de verdad es la base de datos; la empresa sale del JWT
 * (requireTenant), nunca del payload del cliente.
 */
describe("CashService multi-device consistency", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  const existingSession = {
    id: "shift-1",
    openedByUserId: user.id,
    cashboxDailyId: null,
    openedAt: new Date("2026-08-22T10:00:00Z"),
    status: "OPEN",
    userName: "Cajero",
    businessDate: "2026-08-22",
  };

  function buildEmptyTx() {
    return {
      cashSession: {
        findFirst: jest.fn(),
        create: jest.fn(),
        updateMany: jest.fn(),
        findFirstOrThrow: jest.fn(),
      },
      cashboxDaily: {
        findFirst: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
    };
  }

  function buildHarness(
    overrides: {
      tx?: ReturnType<typeof buildEmptyTx> & {
        cashSession?: Record<string, unknown>;
        cashboxDaily?: Record<string, unknown>;
      };
      transaction?: unknown;
      prisma?: Record<string, unknown>;
    } = {},
  ) {
    const tx = overrides.tx ?? buildEmptyTx();
    const prisma = {
      user: {
        findUnique: jest
          .fn()
          .mockResolvedValue({ nombreCompleto: "Cajero", email: "c@x.com", blocked: false }),
      },
      cashSession: { findFirst: jest.fn() },
      cashboxDaily: { findFirst: jest.fn(), create: jest.fn(), update: jest.fn() },
      cashMovement: { create: jest.fn(), findMany: jest.fn().mockResolvedValue([]) },
      sale: { findMany: jest.fn().mockResolvedValue([]) },
      saleCreditPayment: { findMany: jest.fn().mockResolvedValue([]) },
      $transaction:
        overrides.transaction ??
        jest.fn((callback: (t: unknown) => unknown) => callback({ ...tx })),
      ...(overrides.prisma ?? {}),
    };
    const realtime = { emitCompany: jest.fn() };
    const service = new CashService(prisma as never, realtime as never);
    return { prisma, realtime, service };
  }

  it("abrir turno con uno ya abierto devuelve el existente y NO crea otro", async () => {
    const tx = buildEmptyTx();
    (tx.cashSession.findFirst as jest.Mock).mockResolvedValue(existingSession);
    const { service, realtime } = buildHarness({ tx });

    const result = await service.startSession(user, { openingAmount: 1000 });

    expect(result.shiftId).toBe("shift-1");
    expect(tx.cashSession.create).not.toHaveBeenCalled();
    expect(tx.cashboxDaily.create).not.toHaveBeenCalled();
    expect(realtime.emitCompany).toHaveBeenCalledWith(
      user.companyId,
      "cash.event",
      expect.objectContaining({ type: "cash.session.opened" }),
    );
  });

  it("doble apertura concurrente: conflicto P2034 se reintenta y devuelve el existente", async () => {
    let attempts = 0;
    const transaction = jest.fn((callback: (t: unknown) => unknown) => {
      attempts += 1;
      if (attempts === 1) {
        // Segundo dispositivo compite en el mismo instante: la transacción
        // SERIALIZABLE aborta (P2034) en lugar de crear un segundo turno.
        throw new Prisma.PrismaClientKnownRequestError("write conflict", {
          code: "P2034",
          clientVersion: "5.22.0",
          meta: {},
        });
      }
      const tx = buildEmptyTx();
      (tx.cashSession.findFirst as jest.Mock).mockResolvedValue(existingSession);
      return callback({ ...tx });
    });
    const { service } = buildHarness({ transaction });

    const result = await service.startSession(user, { openingAmount: 1000 });

    expect(attempts).toBe(2);
    expect(result.shiftId).toBe("shift-1");
  });

  it("abrir turno sin turno previo crea cashbox + cashSession", async () => {
    const tx = buildEmptyTx();
    (tx.cashSession.findFirst as jest.Mock).mockResolvedValue(null);
    (tx.cashboxDaily.findFirst as jest.Mock).mockResolvedValue(null);
    (tx.cashboxDaily.create as jest.Mock).mockResolvedValue({
      id: "cashbox-1",
      companyId: user.companyId,
      businessDate: "2026-08-22",
    });
    (tx.cashSession.create as jest.Mock).mockResolvedValue({
      ...existingSession,
      id: "shift-2",
    });
    const { service } = buildHarness({ tx });

    const result = await service.startSession(user, { openingAmount: 1000 });

    expect(result.shiftId).toBe("shift-2");
    expect(tx.cashboxDaily.create).toHaveBeenCalledTimes(1);
    expect(tx.cashSession.create).toHaveBeenCalledTimes(1);
  });

  it("cerrar un turno que ya no existe lanza NotFound controlado (no 500)", async () => {
    const { prisma, service } = buildHarness();
    // requireOpenSession: no hay turno abierto (ya lo cerró otro dispositivo).
    (prisma.cashSession.findFirst as jest.Mock).mockResolvedValue(null);

    await expect(
      service.closeSession(user, { closingAmount: 1000 }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it("cerrar un turno ya cerrado lanza Conflict y no duplica el cierre", async () => {
    const tx = buildEmptyTx();
    (tx.cashSession.findFirst as jest.Mock).mockResolvedValue(existingSession);
    // updateMany con count 0: el turno ya no estaba OPEN (otro dispositivo lo cerró).
    (tx.cashSession.updateMany as jest.Mock).mockResolvedValue({ count: 0 });

    const prismaExtra = {
      cashSession: { findFirst: jest.fn().mockResolvedValue(existingSession) },
    };
    const { service } = buildHarness({ tx, prisma: prismaExtra });

    await expect(
      service.closeSession(user, { closingAmount: 1000 }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("requiere empresa del JWT (tenant) para toda operación", async () => {
    const { service } = buildHarness();
    await expect(
      service.startSession({ id: "user-a", role: "ADMIN", companyId: "  " }, {
        openingAmount: 1000,
      }),
    ).rejects.toThrow(/sin empresa/i);
  });
});
