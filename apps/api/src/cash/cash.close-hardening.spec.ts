import { ConflictException, Logger, NotFoundException } from "@nestjs/common";
import { CashService } from "./cash.service";

/**
 * Blindaje del cierre de turno (incidente Asadero Pacheco).
 *
 * Invariantes probadas:
 *  - El cierre identifica SIEMPRE la sesión a cerrar (`sessionId`). El backend
 *    NUNCA sustituye ese id por "el turno abierto actual".
 *  - Un replay offline de un cierre viejo NO puede cerrar un turno posterior.
 *  - Doble cierre / respuesta perdida son seguros (idempotentes).
 *  - `cashbox_daily` sólo se actualiza cuando la transición OPEN→CLOSED de la
 *    sesión correcta ocurrió realmente.
 *  - Aislamiento multiempresa estricto.
 *  - Los clientes legacy (sin `sessionId`) reciben un rechazo controlado salvo
 *    que se habilite explícitamente el modo de compatibilidad.
 */

const COMPANY = "11111111-1111-4111-8111-111111111111";
const OTHER_COMPANY = "99999999-9999-4999-8999-999999999999";
const USER = { id: "user-a", role: "ADMIN", companyId: COMPANY };

const SESSION_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const SESSION_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const CASHBOX_A = "33333333-3333-4333-8333-333333333333";
const CASHBOX_B = "44444444-4444-4444-8444-444444444444";

type Session = {
  id: string;
  companyId: string;
  openedByUserId: string;
  cashboxDailyId: string | null;
  status: string;
  closedAt: Date | null;
  note: string | null;
  businessDate: string | null;
  userName: string | null;
  initialAmount: number;
  closingAmount?: number | null;
  expectedAmount?: number | null;
  difference?: number | null;
};

function makeSession(overrides: Partial<Session> & { id: string }): Session {
  return {
    companyId: COMPANY,
    openedByUserId: USER.id,
    cashboxDailyId: CASHBOX_A,
    status: "OPEN",
    closedAt: null,
    note: null,
    businessDate: "2026-10-03",
    userName: "Cajero",
    initialAmount: 0,
    ...overrides,
  };
}

/** Mini base de datos en memoria con la semántica de `where` que usa el servicio. */
function makeDb(initial: Session[]) {
  const sessions: Session[] = initial.map((session) => ({ ...session }));
  const cashboxUpdates: Array<Record<string, unknown>> = [];
  const movements: Array<Record<string, any>> = [];

  function matches(where: Record<string, any>): Session[] {
    return sessions.filter((session) => {
      const idFilter = where.id;
      if (idFilter !== undefined) {
        if (typeof idFilter === "string") {
          if (session.id !== idFilter) return false;
        } else if (idFilter && typeof idFilter === "object") {
          if ("not" in idFilter && session.id === idFilter.not) return false;
          if (idFilter.in && !idFilter.in.includes(session.id)) return false;
        }
      }
      if (where.companyId !== undefined && session.companyId !== where.companyId) {
        return false;
      }
      if (
        where.openedByUserId !== undefined &&
        session.openedByUserId !== where.openedByUserId
      ) {
        return false;
      }
      if (where.status !== undefined && session.status !== where.status) {
        return false;
      }
      if ("closedAt" in where && where.closedAt === null && session.closedAt != null) {
        return false;
      }
      if (
        where.cashboxDailyId !== undefined &&
        session.cashboxDailyId !== where.cashboxDailyId
      ) {
        return false;
      }
      return true;
    });
  }

  const tx = {
    cashSession: {
      findFirst: jest.fn(async ({ where }: { where: Record<string, any> }) =>
        matches(where)[0] ?? null,
      ),
      findUnique: jest.fn(async ({ where }: { where: { id: string } }) =>
        sessions.find((session) => session.id === where.id) ?? null,
      ),
      updateMany: jest.fn(
        async ({ where, data }: { where: Record<string, any>; data: Record<string, any> }) => {
          const rows = matches(where);
          for (const row of rows) Object.assign(row, data);
          return { count: rows.length };
        },
      ),
      create: jest.fn(async ({ data }: { data: Record<string, any> }) => {
        const created = makeSession({ id: data.id ?? "generated", ...data } as never);
        sessions.push(created);
        return created;
      }),
    },
    cashboxDaily: {
      findFirst: jest.fn(async () => null),
      create: jest.fn(async ({ data }: { data: Record<string, any> }) => ({
        id: "cashbox-new",
        ...data,
      })),
      update: jest.fn(async (args: Record<string, unknown>) => {
        cashboxUpdates.push(args);
        return {};
      }),
    },
  };

  const prisma: any = {
    ...tx,
    user: {
      findUnique: jest.fn(async () => ({
        nombreCompleto: "Cajero",
        email: "c@x.com",
        blocked: false,
      })),
    },
    sale: { findMany: jest.fn(async () => []) },
    cashMovement: {
      findMany: jest.fn(async () => []),
      findFirst: jest.fn(async ({ where }: { where: Record<string, any> }) =>
        movements.find(
          (movement) =>
            movement.companyId === where.companyId &&
            movement.operationId === where.operationId,
        ) ?? null,
      ),
      create: jest.fn(async ({ data }: { data: Record<string, any> }) => {
        const created = { id: `movement-${movements.length + 1}`, ...data };
        movements.push(created);
        return created;
      }),
    },
    saleCreditPayment: { findMany: jest.fn(async () => []) },
    $transaction: jest.fn(async (callback: (t: unknown) => unknown) =>
      callback(tx),
    ),
  };

  return { prisma, sessions, tx, cashboxUpdates, movements };
}

function buildService(db: ReturnType<typeof makeDb>) {
  const realtime = { emitCompany: jest.fn() };
  const service = new CashService(db.prisma as never, realtime as never);
  return { service, realtime };
}

let warnSpy: jest.SpyInstance;

beforeEach(() => {
  warnSpy = jest.spyOn(Logger.prototype, "warn").mockImplementation(() => {});
  jest.spyOn(Logger.prototype, "log").mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
  delete process.env.CASH_CLOSE_LEGACY_MODE;
});

describe("CashService.closeSession — identidad obligatoria del turno", () => {
  it("TEST 1 · cierre normal identificado: cierra EXACTAMENTE la sesión pedida", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, initialAmount: 5000 }),
    ]);
    const { service } = buildService(db);

    const result = await service.closeSession(USER, {
      sessionId: SESSION_A,
      closingAmount: 5000,
    });

    expect(result.session.id).toBe(SESSION_A);
    expect(result.difference).toBe(0);
    expect(db.sessions[0].status).toBe("CLOSED");
    expect(db.sessions[0].closingAmount).toBeDefined();
    // updateMany se condiciona por identidad + empresa + usuario + OPEN.
    expect(db.tx.cashSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: SESSION_A,
          companyId: COMPANY,
          openedByUserId: USER.id,
          status: "OPEN",
          closedAt: null,
        }),
      }),
    );
    // cashbox_daily se cierra porque ya no quedan turnos abiertos en esa caja.
    expect(db.cashboxUpdates).toHaveLength(1);
    expect(db.cashboxUpdates[0]).toEqual(
      expect.objectContaining({ where: { id: CASHBOX_A } }),
    );
  });

  it("TEST 2 · diferencia legítima (faltante) se permite", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, initialAmount: 5000 }),
    ]);
    const { service } = buildService(db);

    const result = await service.closeSession(USER, {
      sessionId: SESSION_A,
      closingAmount: 4900,
    });

    expect(result.difference).toBe(-100);
    expect(db.sessions[0].status).toBe("CLOSED");
  });

  it("TEST 3 · doble cierre: la segunda llamada no produce segundo efecto", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, initialAmount: 5000 }),
    ]);
    const { service } = buildService(db);

    await service.closeSession(USER, {
      sessionId: SESSION_A,
      closingAmount: 5000,
    });
    db.tx.cashSession.updateMany.mockClear();
    db.cashboxUpdates.length = 0;

    await expect(
      service.closeSession(USER, { sessionId: SESSION_A, closingAmount: 5000 }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(db.tx.cashSession.updateMany).not.toHaveBeenCalled();
    expect(db.cashboxUpdates).toHaveLength(0);
  });

  it("TEST 4 · respuesta perdida (replay del mismo cierre) es seguro", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, initialAmount: 5000 }),
    ]);
    const { service } = buildService(db);

    await service.closeSession(USER, {
      sessionId: SESSION_A,
      closingAmount: 5000,
    });
    // El cliente no recibió la respuesta y reintenta el MISMO cierre.
    await expect(
      service.closeSession(USER, { sessionId: SESSION_A, closingAmount: 5000 }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(db.sessions[0].status).toBe("CLOSED");
    expect(db.cashboxUpdates).toHaveLength(1);
  });

  it("TEST 5 · reproducción Asadero: el replay viejo NO cierra el turno nuevo", async () => {
    // Turno A: 71 tickets, expected 33,735.60. Turno B (posterior): expected 3,731.80.
    const db = makeDb([
      makeSession({
        id: SESSION_A,
        initialAmount: 33735.6,
        status: "CLOSED",
        closedAt: new Date("2026-10-03T20:00:00Z"),
        closingAmount: 33735.6,
      }),
      makeSession({
        id: SESSION_B,
        cashboxDailyId: CASHBOX_B,
        initialAmount: 3731.8,
      }),
    ]);
    const { service } = buildService(db);

    const error = await service
      .closeSession(USER, { sessionId: SESSION_A, closingAmount: 33735.6 })
      .catch((e) => e);

    expect(error).toBeInstanceOf(ConflictException);
    // El turno B permanece intacto.
    const turnoB = db.sessions.find((s) => s.id === SESSION_B)!;
    expect(turnoB.status).toBe("OPEN");
    expect(turnoB.closingAmount).toBeUndefined();
    expect(turnoB.difference).toBeUndefined();
    expect(turnoB.initialAmount).toBe(3731.8);
    // Ninguna escritura sobre cashbox_daily ni sobre cash_sessions.
    expect(db.tx.cashSession.updateMany).not.toHaveBeenCalled();
    expect(db.cashboxUpdates).toHaveLength(0);
    // Se registra la firma exacta del incidente.
    const logged = warnSpy.mock.calls.map((call) => String(call[0])).join("\n");
    expect(logged).toContain("CLOSE_REPLAY_REJECTED_SESSION_MISMATCH");
    expect(logged).toContain(SESSION_B);
  });

  it("TEST 6 · el turno original sigue abierto: el replay lo cierra correctamente", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, initialAmount: 5000 }),
    ]);
    const { service } = buildService(db);

    const result = await service.closeSession(USER, {
      sessionId: SESSION_A,
      closingAmount: 5000,
    });

    expect(result.session.id).toBe(SESSION_A);
    expect(db.sessions[0].status).toBe("CLOSED");
  });

  it("TEST 7 · turno inexistente: no toca nada", async () => {
    const db = makeDb([makeSession({ id: SESSION_B, initialAmount: 100 })]);
    const { service } = buildService(db);

    await expect(
      service.closeSession(USER, {
        sessionId: SESSION_A,
        closingAmount: 100,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(db.tx.cashSession.updateMany).not.toHaveBeenCalled();
    expect(db.sessions[0].status).toBe("OPEN");
  });

  it("TEST 8 · turno de otra empresa: rechazo estricto multiempresa", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, companyId: OTHER_COMPANY, initialAmount: 5000 }),
    ]);
    const { service } = buildService(db);

    await expect(
      service.closeSession(USER, {
        sessionId: SESSION_A,
        closingAmount: 5000,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(db.sessions[0].status).toBe("OPEN");
    expect(db.cashboxUpdates).toHaveLength(0);
  });

  it("TEST 9 · cierre simultáneo: exactamente una transición OPEN→CLOSED", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, initialAmount: 5000 }),
    ]);
    const { service } = buildService(db);

    // Primera solicitud gana la transición; la segunda encuentra la sesión ya
    // cerrada y NO puede volver a cerrarla (ni tocar cashbox).
    const first = await service.closeSession(USER, {
      sessionId: SESSION_A,
      closingAmount: 5000,
    });
    const second = await service
      .closeSession(USER, { sessionId: SESSION_A, closingAmount: 9999 })
      .catch((e) => e);

    expect(first.session.id).toBe(SESSION_A);
    expect(second).toBeInstanceOf(ConflictException);
    // El monto de la segunda solicitud NUNCA se aplicó.
    expect(Number(db.sessions[0].closingAmount)).toBe(5000);
    expect(db.cashboxUpdates).toHaveLength(1);
  });

  it("TEST 10 · carrera real en updateMany: count 0 => Conflict y sin tocar cashbox", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_A, initialAmount: 5000 }),
    ]);
    // Otro request ganó la transición justo después de la lectura inicial.
    db.tx.cashSession.updateMany.mockResolvedValueOnce({ count: 0 });
    const { service } = buildService(db);

    await expect(
      service.closeSession(USER, { sessionId: SESSION_A, closingAmount: 5000 }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(db.cashboxUpdates).toHaveLength(0);
  });

  it("TEST 13 · sessionId malformado se rechaza como 404 sin error de Prisma", async () => {
    const db = makeDb([makeSession({ id: SESSION_A, initialAmount: 5000 })]);
    const { service } = buildService(db);

    await expect(
      service.closeSession(USER, {
        sessionId: "local_shift_1234567",
        closingAmount: 100,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(db.tx.cashSession.updateMany).not.toHaveBeenCalled();
  });
});

describe("CashService.closeSession — compatibilidad legacy controlada", () => {
  it("TEST 11a · sin sessionId: rechazo controlado 409 (replay no puede cerrar otro turno)", async () => {
    const db = makeDb([
      makeSession({ id: SESSION_B, initialAmount: 3731.8 }),
    ]);
    const { service } = buildService(db);

    const error = await service
      .closeSession(USER, { closingAmount: 33735.6 })
      .catch((e) => e);

    expect(error).toBeInstanceOf(ConflictException);
    expect((error as ConflictException).getResponse()).toEqual(
      expect.objectContaining({ code: "CASH_CLOSE_SESSION_ID_REQUIRED" }),
    );
    // El turno abierto actual (B) queda intacto: no se cerró "el que estuviera".
    expect(db.sessions[0].status).toBe("OPEN");
    expect(db.tx.cashSession.updateMany).not.toHaveBeenCalled();
    expect(db.cashboxUpdates).toHaveLength(0);
  });

  it("TEST 11b · modo compatibilidad explícito cierra el turno abierto actual (documentado inseguro)", async () => {
    process.env.CASH_CLOSE_LEGACY_MODE = "current_open";
    const db = makeDb([
      makeSession({ id: SESSION_B, initialAmount: 3731.8 }),
    ]);
    const { service } = buildService(db);

    const result = await service.closeSession(USER, { closingAmount: 3731.8 });

    expect(result.session.id).toBe(SESSION_B);
    expect(db.sessions[0].status).toBe("CLOSED");
  });
});

describe("CashService.addMovement — el movimiento pertenece a su turno", () => {
  it("TEST 12 · movimiento con sessionId de un turno ya cerrado no contamina el turno actual", async () => {
    const db = makeDb([
      makeSession({
        id: SESSION_A,
        status: "CLOSED",
        closedAt: new Date("2026-10-03T20:00:00Z"),
      }),
      makeSession({
        id: SESSION_B,
        cashboxDailyId: CASHBOX_B,
        initialAmount: 100,
      }),
    ]);
    const { service } = buildService(db);

    await expect(
      service.addMovement(USER, {
        type: "OUT",
        amount: 50,
        reason: "Gasto viejo",
        sessionId: SESSION_A,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(db.prisma.cashMovement.create).not.toHaveBeenCalled();
    expect(db.sessions.find((s) => s.id === SESSION_B)!.status).toBe("OPEN");
  });

  it("TEST 13 · movimiento repetido con operationId aplica exactamente una vez", async () => {
    const db = makeDb([makeSession({ id: SESSION_A, initialAmount: 500 })]);
    const { service } = buildService(db);

    const first = await service.addMovement(USER, {
      operationId: "cash.movement:duplicate-1",
      type: "IN",
      amount: 25,
      reason: "Entrada",
      sessionId: SESSION_A,
    });
    const second = await service.addMovement(USER, {
      operationId: "cash.movement:duplicate-1",
      type: "IN",
      amount: 25,
      reason: "Entrada",
      sessionId: SESSION_A,
    });

    expect(second).toBe(first);
    expect(db.prisma.cashMovement.create).toHaveBeenCalledTimes(1);
    expect(db.movements).toHaveLength(1);
  });

  it("TEST 14 · movimiento legacy sin sessionId se rechaza sin tocar el turno abierto", async () => {
    const db = makeDb([makeSession({ id: SESSION_B, initialAmount: 100 })]);
    const { service } = buildService(db);

    await expect(
      service.addMovement(USER, {
        operationId: "cash.movement:legacy",
        type: "OUT",
        amount: 10,
        reason: "Legacy",
      }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(db.prisma.cashMovement.create).not.toHaveBeenCalled();
    expect(db.sessions.find((s) => s.id === SESSION_B)!.status).toBe("OPEN");
  });
});
