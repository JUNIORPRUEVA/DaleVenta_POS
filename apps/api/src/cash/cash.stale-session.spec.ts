import { ConflictException, ForbiddenException, Logger } from "@nestjs/common";
import { CashService } from "./cash.service";
import { currentBusinessDay } from "../common/utils/business-time.util";

/**
 * Blindaje multiusuario de caja (defectos D1, D1 bis, D3, D4, D6).
 *
 * Invariantes probadas:
 *  - Un turno vencido se puede CONSULTAR y CERRAR (antes el 409 dejaba al
 *    usuario sin salida) pero no operar (`canOperate: false`).
 *  - Sólo la ambigüedad real (dos turnos abiertos del mismo usuario) mantiene
 *    el 409 histórico `CASH_SESSION_REQUIRES_REVIEW`.
 *  - Abrir turno con un turno de otro día NO lo reutiliza en silencio.
 *  - Un movimiento no puede imputarse a un turno de otro día comercial.
 *  - El cierre administrativo exige ADMIN, motivo y monto; es atómico y deja
 *    auditoría; nunca cierra turnos ajenos sin conciliación declarada.
 *  - La caja diaria compartida deja de ser "el último cierre gana".
 */

const COMPANY = "11111111-1111-4111-8111-111111111111";
const OTHER_COMPANY = "99999999-9999-4999-8999-999999999999";
const ADMIN = { id: "user-admin", role: "ADMIN", companyId: COMPANY };
const CASHIER = { id: "user-cajero", role: "CAJERO", companyId: COMPANY };

const DAY = 86_400_000;

const STALE_SESSION = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const FRESH_SESSION = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const OTHER_SESSION = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const DAILY = "33333333-3333-4333-8333-333333333333";

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
  openedAt: Date;
  terminalId?: string | null;
  terminalNameSnapshot?: string | null;
  terminalCodeSnapshot?: string | null;
};

function staleDates() {
  const openedAt = new Date(Date.now() - 3 * DAY);
  return { openedAt, businessDate: currentBusinessDay(openedAt) };
}

function makeSession(overrides: Partial<Session> & { id: string }): Session {
  return {
    companyId: COMPANY,
    openedByUserId: CASHIER.id,
    cashboxDailyId: DAILY,
    status: "OPEN",
    closedAt: null,
    note: null,
    businessDate: currentBusinessDay(),
    userName: "Cajero",
    initialAmount: 0,
    openedAt: new Date(),
    terminalId: null,
    terminalNameSnapshot: "Caja",
    terminalCodeSnapshot: "T1",
    ...overrides,
  };
}

function makeDb(initial: Session[]) {
  const sessions: Session[] = initial.map((session) => ({ ...session }));
  const cashboxUpdates: Array<Record<string, any>> = [];
  const movements: Array<Record<string, any>> = [];
  const telemetryEvents: Array<Record<string, any>> = [];
  const cashboxes: Array<Record<string, any>> = [
    {
      id: DAILY,
      companyId: COMPANY,
      businessDate: currentBusinessDay(),
      status: "OPEN",
      initialAmount: 0,
      currentAmount: 0,
      closedAt: null,
      closedByUserId: null,
    },
  ];

  function matches(where: Record<string, any>, session: Session): boolean {
    if (where.id !== undefined) {
      const idFilter = where.id;
      if (typeof idFilter === "string") {
        if (session.id !== idFilter) return false;
      } else if (idFilter && typeof idFilter === "object") {
        if ("not" in idFilter && session.id === idFilter.not) return false;
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
    if ("closedAt" in where) {
      if (where.closedAt === null && session.closedAt != null) return false;
      if (where.closedAt && typeof where.closedAt === "object") return true;
    }
    if (
      where.cashboxDailyId !== undefined &&
      session.cashboxDailyId !== where.cashboxDailyId
    ) {
      return false;
    }
    if (where.businessDate !== undefined) {
      const filter = where.businessDate;
      if (typeof filter === "string" && session.businessDate !== filter) {
        return false;
      }
      if (
        filter &&
        typeof filter === "object" &&
        "not" in filter &&
        session.businessDate === filter.not
      ) {
        return false;
      }
    }
    return true;
  }

  const select = (where: Record<string, any>) =>
    sessions.filter((session) => matches(where, session));

  const cashSession = {
    findFirst: jest.fn(async ({ where }: { where: Record<string, any> }) => {
      const rows = select(where).sort(
        (a, b) => b.openedAt.getTime() - a.openedAt.getTime(),
      );
      return rows[0] ?? null;
    }),
    findMany: jest.fn(async ({ where }: { where: Record<string, any> }) =>
      select(where).sort((a, b) => a.openedAt.getTime() - b.openedAt.getTime()),
    ),
    findUnique: jest.fn(async ({ where }: { where: { id: string } }) =>
      sessions.find((session) => session.id === where.id) ?? null,
    ),
    updateMany: jest.fn(
      async ({
        where,
        data,
      }: {
        where: Record<string, any>;
        data: Record<string, any>;
      }) => {
        const rows = select(where);
        for (const row of rows) Object.assign(row, data);
        return { count: rows.length };
      },
    ),
    create: jest.fn(async ({ data }: { data: Record<string, any> }) => {
      const created = makeSession({ id: data.id ?? "generated", ...data });
      sessions.push(created);
      return created;
    }),
    count: jest.fn(async ({ where }: { where: Record<string, any> }) =>
      select(where).length,
    ),
    aggregate: jest.fn(async ({ where }: { where: Record<string, any> }) => {
      const rows = select(where);
      return {
        _count: { _all: rows.length },
        _sum: {
          closingAmount: rows.reduce(
            (sum, row) => sum + Number(row.closingAmount ?? 0),
            0,
          ),
          initialAmount: rows.reduce(
            (sum, row) => sum + Number(row.initialAmount ?? 0),
            0,
          ),
        },
      };
    }),
  };

  const cashboxDaily = {
    findFirst: jest.fn(
      async ({ where }: { where: Record<string, any> }) =>
        cashboxes.find(
          (row) =>
            row.companyId === where.companyId &&
            (where.businessDate === undefined ||
              row.businessDate === where.businessDate),
        ) ?? null,
    ),
    create: jest.fn(async ({ data }: { data: Record<string, any> }) => {
      const created = { id: "cashbox-new", ...data };
      cashboxes.push(created);
      return created;
    }),
    update: jest.fn(async (args: Record<string, any>) => {
      cashboxUpdates.push(args);
      const target = cashboxes.find((row) => row.id === args.where.id);
      if (target) Object.assign(target, args.data);
      return target ?? {};
    }),
  };

  const tx = { cashSession, cashboxDaily, $queryRaw: jest.fn(async () => []) };

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
      findFirst: jest.fn(
        async ({ where }: { where: Record<string, any> }) =>
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
    $queryRaw: jest.fn(async () => []),
    $transaction: jest.fn(async (callback: (t: unknown) => unknown) =>
      callback(tx),
    ),
  };

  const telemetry = {
    enqueueBusinessEvent: jest.fn(async (_tx: unknown, event: unknown) => {
      telemetryEvents.push(event as Record<string, any>);
    }),
  };

  return {
    prisma,
    tx,
    telemetry,
    sessions,
    cashboxes,
    cashboxUpdates,
    movements,
    telemetryEvents,
  };
}

function buildService(db: ReturnType<typeof makeDb>) {
  const realtime = { emitCompany: jest.fn() };
  const service = new CashService(
    db.prisma as never,
    realtime as never,
    undefined,
    db.telemetry as never,
  );
  return { service, realtime };
}

let warnSpy: jest.SpyInstance;

beforeEach(() => {
  warnSpy = jest.spyOn(Logger.prototype, "warn").mockImplementation(() => {});
  jest.spyOn(Logger.prototype, "log").mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
  delete process.env.FINANCIAL_LEGACY_COMPAT;
  delete process.env.CASH_CLOSE_LEGACY_COMPAT;
  delete process.env.CASH_SHIFT_MAX_SPAN_HOURS;
});

describe("gateState · turno vencido consultable (D3)", () => {
  it("devuelve 200 con el turno vencido marcado y sin permitir operar", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    const state = await service.gateState(CASHIER as never);

    expect(state.activeSession?.shiftId).toBe(STALE_SESSION);
    expect(state.canOperate).toBe(false);
    expect(state.staleBusinessDate).toBe(true);
    expect(state.requiresClosure).toBe(true);
    expect(warnSpy).toHaveBeenCalled();
  });

  it("mantiene el 409 sólo cuando el usuario tiene dos turnos abiertos", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
      makeSession({ id: FRESH_SESSION }),
    ]);
    const { service } = buildService(db);

    await expect(service.gateState(CASHIER as never)).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CASH_SESSION_REQUIRES_REVIEW",
        reason: "MULTIPLE_OPEN_SESSIONS",
      }),
    });
  });

  it("expone totales derivados de la caja diaria compartida (D4)", async () => {
    const db = makeDb([
      makeSession({ id: FRESH_SESSION, initialAmount: 100 }),
      makeSession({
        id: OTHER_SESSION,
        openedByUserId: "otro",
        initialAmount: 50,
        status: "CLOSED",
        closedAt: new Date(),
        closingAmount: 320,
      }),
    ]);
    const { service } = buildService(db);

    const state = await service.gateState(CASHIER as never);

    expect(state.cashboxTotals).toMatchObject({
      cashboxDailyId: DAILY,
      sessions: 2,
      openSessions: 1,
      openedTotal: 150,
      closedTotal: 320,
    });
  });
});

describe("startSession · no reutilización silenciosa de turno vencido (D1)", () => {
  it("rechaza abrir turno con CASH_CLOSE_PREVIOUS_REQUIRED y no crea otro", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    await expect(
      service.startSession(CASHIER as never, { openingAmount: 100 } as never),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CASH_CLOSE_PREVIOUS_REQUIRED",
        sessionId: STALE_SESSION,
      }),
    });
    expect(db.prisma.cashSession.create).not.toHaveBeenCalled();
  });

  it("abre un turno nuevo con normalidad cuando no hay turno previo", async () => {
    const db = makeDb([]);
    const { service } = buildService(db);

    const opened = await service.startSession(CASHIER as never, {
      openingAmount: 100,
    } as never);

    expect(opened.shiftId).toBeTruthy();
    expect(db.prisma.cashSession.create).toHaveBeenCalledTimes(1);
  });
});

describe("addMovement · ventana operativa (D1 bis / D2)", () => {
  it("rechaza el movimiento imputado a un turno de otro día comercial", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    await expect(
      service.addMovement(
        CASHIER as never,
        {
          sessionId: STALE_SESSION,
          operationId: "op-stale",
          type: "OUT",
          amount: 10,
          reason: "gasto",
        } as never,
        {} as never,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "CASH_SESSION_STALE" }),
    });
    expect(db.prisma.cashMovement.create).not.toHaveBeenCalled();
  });

  it("acepta el movimiento offline legítimo usando la fecha de la operación", async () => {
    const openedAt = new Date(Date.now() - 60_000);
    const db = makeDb([makeSession({ id: FRESH_SESSION, openedAt })]);
    const { service } = buildService(db);

    const movement = await service.addMovement(
      CASHIER as never,
      {
        sessionId: FRESH_SESSION,
        operationId: "op-offline-ok",
        type: "IN",
        amount: 25,
        occurredAt: new Date(openedAt.getTime() + 1_000).toISOString(),
      } as never,
      {} as never,
    );

    expect(movement.sessionId).toBe(FRESH_SESSION);
    expect(db.prisma.cashMovement.create).toHaveBeenCalledTimes(1);
  });
});

describe("cierre administrativo (D6)", () => {
  it("rechaza a un usuario que no es ADMIN", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    await expect(
      service.adminCloseSession(CASHIER as never, STALE_SESSION, {
        reason: "turno olvidado por el cajero",
        closingAmount: 0,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("cierra el turno ajeno, registra diferencia, auditoría y no reescribe historial", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({
        id: STALE_SESSION,
        openedAt,
        businessDate,
        initialAmount: 0,
      }),
    ]);
    const { service } = buildService(db);

    const result = await service.adminCloseSession(ADMIN as never, STALE_SESSION, {
      reason: "empleado no se presentó a cerrar",
      closingAmount: 0,
      note: "verificado con el dueño",
    });

    const closed = db.sessions.find((row) => row.id === STALE_SESSION)!;
    expect(closed.status).toBe("CLOSED");
    expect(closed.closedByUserId).toBe(ADMIN.id);
    expect(closed.note).toContain("[CIERRE ADMINISTRATIVO]");
    expect(closed.note).toContain("empleado no se presentó a cerrar");
    expect(result.difference).toBe(0);
    expect(db.telemetryEvents).toEqual([
      expect.objectContaining({ eventType: "CASH_SESSION_ADMIN_CLOSED" }),
    ]);
    expect(db.cashboxUpdates).toHaveLength(1);
  });

  it("no cierra la caja diaria si otro empleado sigue con turno abierto", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
      makeSession({ id: FRESH_SESSION, openedByUserId: "otro-cajero" }),
    ]);
    const { service } = buildService(db);

    await service.adminCloseSession(ADMIN as never, STALE_SESSION, {
      reason: "turno olvidado sin cerrar",
      closingAmount: 0,
    });

    // El importe se refresca siempre (para que la caja diaria sea exacta), pero
    // el estado NO se cierra mientras otro empleado siga con turno abierto.
    expect(db.cashboxUpdates).toHaveLength(1);
    expect(db.cashboxUpdates[0].data).not.toHaveProperty("status");
    expect(db.cashboxUpdates[0].data.currentAmount).toBe(0);
    expect(db.cashboxes[0].status).toBe("OPEN");
  });

  it("en carrera (updateMany count 0) no produce segundo cierre", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);
    db.prisma.cashSession.updateMany.mockResolvedValueOnce({ count: 0 });

    await expect(
      service.adminCloseSession(ADMIN as never, STALE_SESSION, {
        reason: "doble cierre administrativo",
        closingAmount: 0,
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("aísla multiempresa: un ADMIN de otra empresa no ve el turno", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    await expect(
      service.adminCloseSession(
        { id: "admin-otra", role: "ADMIN", companyId: OTHER_COMPANY } as never,
        STALE_SESSION,
        { reason: "intento entre empresas", closingAmount: 0 },
      ),
    ).rejects.toThrow();
  });
});

describe("staleSessions · visibilidad para el administrador", () => {
  it("lista sólo turnos de días anteriores", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
      makeSession({ id: FRESH_SESSION }),
    ]);
    const { service } = buildService(db);

    const result = await service.staleSessions(ADMIN as never);

    expect(result.items).toHaveLength(1);
    expect(result.items[0].shiftId).toBe(STALE_SESSION);
    expect(result.items[0].requiresClosure).toBe(true);
  });

  it("rechaza a un no administrador", async () => {
    const db = makeDb([]);
    const { service } = buildService(db);
    await expect(service.staleSessions(CASHIER as never)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });
});

describe("performCloseSession · caja diaria aditiva (D4)", () => {
  it("cierra la caja diaria con la SUMA de los cierres del día, no con el último", async () => {
    const openedAt = new Date(Date.now() - 60_000);
    const db = makeDb([
      makeSession({ id: FRESH_SESSION, openedAt }),
      makeSession({
        id: OTHER_SESSION,
        openedByUserId: "otro",
        openedAt,
        status: "CLOSED",
        closedAt: new Date(),
        closingAmount: 500,
      }),
    ]);
    const { service } = buildService(db);

    await service.closeSession(CASHIER as never, {
      sessionId: FRESH_SESSION,
      closingAmount: 250,
    } as never);

    expect(db.cashboxUpdates.length).toBeGreaterThanOrEqual(1);
    expect(
      db.cashboxUpdates.every(
        (update) => update.data.currentAmount === 750,
      ),
    ).toBe(true);
  });

  /**
   * Regresión del defecto detectado en UAT con PostgreSQL real: si varios
   * empleados cierran casi a la vez, cada transacción veía a los demás todavía
   * OPEN, nadie finalizaba la caja diaria y el importe se quedaba en el inicial.
   * Ahora la finalización se repite tras el commit con la fila bloqueada
   * (`SELECT ... FOR UPDATE`) y el total se deriva de los cierres reales.
   */
  it("finaliza la caja diaria tras el commit con la fila bloqueada (cierres simultáneos)", async () => {
    const openedAt = new Date(Date.now() - 60_000);
    const db = makeDb([
      makeSession({ id: FRESH_SESSION, openedAt }),
      makeSession({
        id: OTHER_SESSION,
        openedByUserId: "otro",
        openedAt,
        status: "CLOSED",
        closedAt: new Date(),
        closingAmount: 500,
      }),
    ]);
    const { service } = buildService(db);

    await service.closeSession(CASHIER as never, {
      sessionId: FRESH_SESSION,
      closingAmount: 250,
    } as never);

    // El bloqueo de fila serializa a los que cierran a la vez.
    expect(db.tx.$queryRaw).toHaveBeenCalled();
    const lastUpdate = db.cashboxUpdates[db.cashboxUpdates.length - 1];
    expect(lastUpdate.data.currentAmount).toBe(750);
    expect(lastUpdate.data.status).toBe("CLOSED");
  });
});

/**
 * Regresión del bloqueo detectado en producción con la build 145:
 * `GET /cash/summary` y `GET /cash/movements` aplicaban la ventana operativa y
 * devolvían 409 en un turno vencido. El cliente consulta ambos ANTES de enviar
 * el cierre, así que el usuario no podía cerrar su turno desde la app.
 *
 * Invariante: la ventana operativa limita OPERACIONES FINANCIERAS nuevas, no
 * las lecturas del propio turno ni los datos de autorización/pertenencia.
 */
describe("lecturas de caja · turno vencido consultable (hotfix cierre)", () => {
  it("summary() devuelve el resumen de un turno vencido sin lanzar", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    const summary = await service.summary(CASHIER as never);

    expect(summary).toBeTruthy();
    expect(summary.sessionId).toBe(STALE_SESSION);
  });

  it("movements() devuelve los movimientos de un turno vencido sin lanzar", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    await expect(service.movements(CASHIER as never)).resolves.toEqual([]);
    expect(db.prisma.cashMovement.findMany).toHaveBeenCalled();
  });

  it("el cierre de un turno vencido sigue permitido tras consultar sus lecturas", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);

    await service.summary(CASHIER as never);
    await service.movements(CASHIER as never);
    const result = await service.closeSession(CASHIER as never, {
      sessionId: STALE_SESSION,
      closingAmount: 0,
    } as never);

    expect(result.session.status).toBe("CLOSED");
    expect(db.sessions.find((row) => row.id === STALE_SESSION)?.status).toBe(
      "CLOSED",
    );
  });

  it("una operación financiera nueva en el turno vencido SIGUE rechazada (409)", async () => {
    const { openedAt, businessDate } = staleDates();
    const db = makeDb([
      makeSession({ id: STALE_SESSION, openedAt, businessDate }),
    ]);
    const { service } = buildService(db);
    // Cliente antiguo (sin sessionId) sobre un turno vencido: debe rechazarse
    // por ventana operativa, no aceptarse en silencio.
    process.env.FINANCIAL_LEGACY_COMPAT = "true";

    await expect(
      service.addMovement(CASHIER as never, {
        type: "IN",
        amount: 10,
        reason: "prueba de bloqueo financiero",
      } as never),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "CASH_SESSION_STALE" }),
    });
    expect(db.movements).toHaveLength(0);
  });
});
