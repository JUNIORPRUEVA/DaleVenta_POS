import {
  addDaysToDateOnly,
  businessDateOf,
  CASH_SHIFT_MAX_SPAN_HOURS_CEILING,
  evaluateShiftOperationWindow,
  resolveShiftMaxSpanHours,
} from "./cash-operation-window";

/**
 * Ventana operativa del turno (defectos D1 bis / D2).
 *
 * Invariantes probadas:
 *  - Ninguna venta/movimiento puede imputarse a un turno de un día comercial
 *    anterior (el caso Antonio: ventas del 22/10 dentro del turno del 19/10).
 *  - Los turnos nocturnos que cruzan medianoche siguen operando (caso real:
 *    apertura 23:50, venta 00:10).
 *  - La validación usa la fecha de la OPERACIÓN, nunca la de recepción, así que
 *    una sincronización offline tardía no invalida operaciones legítimas.
 *  - Varios empleados con turnos simultáneos son independientes entre sí.
 */

const HOUR = 3_600_000;
const DAY = 24 * HOUR;

function at(iso: string) {
  return new Date(iso);
}

describe("evaluateShiftOperationWindow", () => {
  it("permite una venta del mismo día comercial", () => {
    const session = {
      openedAt: at("2026-10-19T13:00:00.000Z"),
      closedAt: null,
      businessDate: "2026-10-19",
    };
    const verdict = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-19T20:30:00.000Z"),
      session,
    });
    expect(verdict.allowed).toBe(true);
  });

  it("rechaza como STALE la venta de 3 días después (caso Antonio 19/10 → 22/10)", () => {
    const session = {
      openedAt: at("2026-10-19T23:26:04.382Z"),
      closedAt: null,
      businessDate: "2026-10-19",
    };
    const verdict = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-22T11:56:15.222Z"),
      session,
    });
    expect(verdict.allowed).toBe(false);
    if (verdict.allowed) throw new Error("unreachable");
    expect(verdict.code).toBe("CASH_SESSION_STALE");
    expect(verdict.reason).toContain("día anterior");
  });

  it("permite el turno nocturno que cruza medianoche (23:50 → 00:10)", () => {
    // 2026-10-20T02:00Z = 22:00 AST del 19/10 → businessDate 2026-10-19
    const session = {
      openedAt: at("2026-10-20T01:50:00.000Z"),
      closedAt: null,
      businessDate: "2026-10-19",
    };
    // 2026-10-20T04:10Z = 00:10 AST del 20/10 → día comercial siguiente
    const verdict = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-20T04:10:00.000Z"),
      session,
    });
    expect(businessDateOf(session.openedAt)).toBe("2026-10-19");
    expect(businessDateOf(at("2026-10-20T04:10:00.000Z"))).toBe("2026-10-20");
    expect(verdict.allowed).toBe(true);
  });

  it("rechaza el segundo cambio de fecha comercial del mismo turno", () => {
    const session = {
      openedAt: at("2026-10-20T01:50:00.000Z"),
      closedAt: null,
      businessDate: "2026-10-19",
    };
    const verdict = evaluateShiftOperationWindow({
      // 22:00 AST del 20/10 → dos días comerciales después del turno
      occurredAt: at("2026-10-21T02:00:00.000Z"),
      session,
    });
    expect(verdict.allowed).toBe(false);
    if (verdict.allowed) throw new Error("unreachable");
    expect(verdict.code).toBe("CASH_SESSION_STALE");
  });

  it("rechaza una operación anterior a la apertura del turno", () => {
    const session = {
      openedAt: at("2026-10-19T18:00:00.000Z"),
      closedAt: null,
      businessDate: "2026-10-19",
    };
    const verdict = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-19T17:50:00.000Z"),
      session,
    });
    expect(verdict.allowed).toBe(false);
    if (verdict.allowed) throw new Error("unreachable");
    expect(verdict.code).toBe("CASH_OPERATION_BEFORE_SHIFT");
  });

  it("tolera desfase de reloj del dispositivo en el borde de apertura (≤5 min)", () => {
    const session = {
      openedAt: at("2026-10-19T18:00:00.000Z"),
      closedAt: null,
      businessDate: "2026-10-19",
    };
    // Reloj del equipo 3 minutos atrasado respecto al servidor.
    const skewed = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-19T17:57:00.000Z"),
      session,
    });
    expect(skewed.allowed).toBe(true);
    // 10 minutos antes: fuera de tolerancia, se rechaza.
    const tooEarly = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-19T17:50:00.000Z"),
      session,
    });
    expect(tooEarly.allowed).toBe(false);
  });

  it("rechaza una operación posterior al cierre del turno", () => {
    const session = {
      openedAt: at("2026-10-19T13:00:00.000Z"),
      closedAt: at("2026-10-19T21:00:00.000Z"),
      businessDate: "2026-10-19",
    };
    const verdict = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-19T21:10:00.000Z"),
      session,
    });
    expect(verdict.allowed).toBe(false);
    if (verdict.allowed) throw new Error("unreachable");
    expect(verdict.code).toBe("CASH_OPERATION_AFTER_CLOSE");
  });

  it("acepta una operación offline ocurrida antes del cierre aunque se reciba después", () => {
    const session = {
      openedAt: at("2026-10-19T13:00:00.000Z"),
      closedAt: at("2026-10-19T21:00:00.000Z"),
      businessDate: "2026-10-19",
    };
    // La operación ocurrió a las 20:59; se sincroniza 2 días después: no importa
    // la fecha de recepción, sólo la de la operación.
    const verdict = evaluateShiftOperationWindow({
      occurredAt: at("2026-10-19T20:59:00.000Z"),
      session,
    });
    expect(verdict.allowed).toBe(true);
  });

  it("acota la duración del turno: 23h59m permitido, 24h01m rechazado", () => {
    const openedAt = at("2026-10-19T13:00:00.000Z");
    const session = { openedAt, closedAt: null, businessDate: "2026-10-19" };
    expect(
      evaluateShiftOperationWindow({
        occurredAt: new Date(openedAt.getTime() + DAY - 60_000),
        session,
      }).allowed,
    ).toBe(true);
    const late = evaluateShiftOperationWindow({
      occurredAt: new Date(openedAt.getTime() + DAY + 60_000),
      session,
    });
    expect(late.allowed).toBe(false);
  });

  it("la ventana es configurable con techo duro de 72h", () => {
    expect(resolveShiftMaxSpanHours({} as NodeJS.ProcessEnv)).toBe(24);
    expect(
      resolveShiftMaxSpanHours({ CASH_SHIFT_MAX_SPAN_HOURS: "12" } as never),
    ).toBe(12);
    expect(
      resolveShiftMaxSpanHours({ CASH_SHIFT_MAX_SPAN_HOURS: "999" } as never),
    ).toBe(CASH_SHIFT_MAX_SPAN_HOURS_CEILING);
    expect(
      resolveShiftMaxSpanHours({ CASH_SHIFT_MAX_SPAN_HOURS: "abc" } as never),
    ).toBe(24);
  });

  it("suma días correctamente al cruzar fin de mes y de año", () => {
    expect(addDaysToDateOnly("2026-10-31", 1)).toBe("2026-11-01");
    expect(addDaysToDateOnly("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDaysToDateOnly("2026-02-28", 1)).toBe("2026-03-01");
  });
});

describe("multiusuario: tres empleados y dos terminales simultáneos", () => {
  // Un día comercial, tres turnos abiertos a la vez (dos en el mismo terminal,
  // uno en otro). Cada operación se valida contra SU turno.
  const terminals = { t1: "terminal-1", t2: "terminal-2" };
  const shifts = [
    {
      employee: "A",
      terminal: terminals.t1,
      openedAt: at("2026-10-19T12:00:00.000Z"),
      businessDate: "2026-10-19",
    },
    {
      employee: "B",
      terminal: terminals.t1,
      openedAt: at("2026-10-19T12:30:00.000Z"),
      businessDate: "2026-10-19",
    },
    {
      employee: "C",
      terminal: terminals.t2,
      openedAt: at("2026-10-19T13:00:00.000Z"),
      businessDate: "2026-10-19",
    },
  ];

  it("cada empleado opera en su propio turno sin interferencias", () => {
    for (const shift of shifts) {
      const verdict = evaluateShiftOperationWindow({
        occurredAt: at("2026-10-19T18:00:00.000Z"),
        session: { ...shift, closedAt: null },
      });
      expect(verdict.allowed).toBe(true);
    }
  });

  it("un turno vencido de un empleado no invalida los turnos vigentes de los demás", () => {
    const stale = {
      employee: "A",
      openedAt: at("2026-10-16T12:00:00.000Z"),
      businessDate: "2026-10-16",
      closedAt: null,
    };
    const current = {
      employee: "B",
      openedAt: at("2026-10-19T12:30:00.000Z"),
      businessDate: "2026-10-19",
      closedAt: null,
    };
    expect(
      evaluateShiftOperationWindow({
        occurredAt: at("2026-10-19T18:00:00.000Z"),
        session: stale,
      }).allowed,
    ).toBe(false);
    expect(
      evaluateShiftOperationWindow({
        occurredAt: at("2026-10-19T18:00:00.000Z"),
        session: current,
      }).allowed,
    ).toBe(true);
  });
});
