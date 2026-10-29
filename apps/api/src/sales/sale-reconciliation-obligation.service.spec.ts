import { ForbiddenException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { TenantUser } from "../auth/tenant-context";
import { SaleReconciliationObligationService } from "./sale-reconciliation-obligation.service";

/**
 * Contrato de las obligaciones de conciliación.
 *
 * Lo que estas pruebas protegen:
 *  - Una operación tiene UNA sola obligación ACTIVA (nunca se duplica el saldo
 *    pendiente), aunque declaren varias personas o dispositivos.
 *  - Cada declaración o rectificación queda auditada con actor, importe anterior
 *    y nuevo, y nota.
 *  - Cambiar el importe exige rol administrativo.
 *  - Declarar NUNCA crea ventas, caja ni inventario.
 */
describe("SaleReconciliationObligationService", () => {
  const companyId = "11111111-1111-4111-8111-111111111111";
  const otherCompany = "22222222-2222-4222-8222-222222222222";

  const owner = { id: "owner-1", companyId, role: "ADMIN" } as unknown as TenantUser;
  const cashier = {
    id: "cashier-1",
    companyId,
    role: "CAJERO",
  } as unknown as TenantUser;

  type Row = Record<string, any>;

  function buildRow(data: Row): Row {
    const now = new Date("2026-10-29T12:00:00.000Z");
    return {
      id: "obl-1",
      status: "PENDING",
      version: 1,
      declarationCount: 1,
      createdAt: now,
      updatedAt: now,
      resolvedAt: null,
      resolvedByUserId: null,
      resolutionNote: null,
      currency: "DOP",
      paymentMethod: "cash",
      operationFingerprint: null,
      ...data,
    };
  }

  function build() {
    const state = {
      row: null as Row | null,
      events: [] as Row[],
      created: 0,
      updated: 0,
      createAttempts: 0,
      failNextCreateWithP2002: false,
    };
    const obligation = {
      findFirst: jest.fn(async ({ where }: any) => {
        if (!state.row) return null;
        if (where.id && where.id !== state.row.id) return null;
        if (where.companyId && where.companyId !== state.row.companyId) return null;
        if (where.status && where.status !== state.row.status) return null;
        if (
          where.clientRequestId &&
          where.clientRequestId !== state.row.clientRequestId
        ) {
          return null;
        }
        return state.row;
      }),
      create: jest.fn(async ({ data }: any) => {
        state.createAttempts += 1;
        if (state.failNextCreateWithP2002) {
          throw new Prisma.PrismaClientKnownRequestError("duplicado", {
            code: "P2002",
            clientVersion: "5.22.0",
          });
        }
        state.created += 1;
        state.row = buildRow({ ...data, id: "obl-created" });
        return state.row;
      }),
      update: jest.fn(async ({ data }: any) => {
        state.updated += 1;
        const row = state.row!;
        const next: Row = { ...row };
        for (const [key, value] of Object.entries(data)) {
          if (value && typeof value === "object" && "increment" in (value as any)) {
            next[key] = Number(next[key] ?? 0) + Number((value as any).increment);
          } else if (value !== undefined) {
            next[key] = value;
          }
        }
        state.row = next;
        return next;
      }),
      findMany: jest.fn(async ({ where }: any) =>
        state.row && (!where.companyId || where.companyId === state.row.companyId)
          ? [state.row]
          : [],
      ),
    };

    const events = {
      create: jest.fn(async ({ data }: any) => {
        const event = {
          id: `ev-${state.events.length + 1}`,
          createdAt: new Date("2026-10-29T12:00:00.000Z"),
          ...data,
        };
        state.events.push(event);
        return event;
      }),
      findMany: jest.fn(async ({ where }: any) =>
        state.events.filter(
          (event) =>
            event.obligationId === where.obligationId &&
            event.companyId === where.companyId,
        ),
      ),
    };

    const prisma = {
      saleReconciliationObligation: obligation,
      saleReconciliationDeclarationEvent: events,
      $transaction: jest.fn(async (callback: any) =>
        callback({
          saleReconciliationObligation: obligation,
          saleReconciliationDeclarationEvent: events,
        }),
      ),
      // Nada de esta función puede tocar ventas, caja ni inventario.
      sale: {
        create: jest.fn(() => {
          throw new Error("una declaración NO puede crear ventas");
        }),
        update: jest.fn(() => {
          throw new Error("una declaración NO puede modificar ventas");
        }),
      },
      cashMovement: {
        create: jest.fn(() => {
          throw new Error("una declaración NO puede crear movimientos de caja");
        }),
      },
    } as unknown as ConstructorParameters<
      typeof SaleReconciliationObligationService
    >[0];

    return {
      prisma: prisma as any,
      state,
      service: new SaleReconciliationObligationService(prisma),
    };
  }

  const baseDto = {
    totalDeclared: 50,
    declaredAtUtc: "2026-10-27T20:39:00.000Z",
    paymentMethod: "cash",
    note: "Cliente pagó en efectivo, no salió ticket",
    declaredByRole: "ADMIN",
  };

  it("crea UNA obligación activa y deja el evento CREATED", async () => {
    const { service, state, prisma } = build();
    const result = await service.recordDeclaration(owner, "op-1", baseDto as never);

    expect(state.created).toBe(1);
    expect(result.duplicate).toBe(false);
    expect(result.amendment).toBe("CREATED");
    expect(result.obligation.totalDeclared).toBe(50);
    expect(result.obligation.declarationCount).toBe(1);
    expect(result.obligation.version).toBe(1);
    expect(result.obligation.retryAllowed).toBe(false);
    expect(result.obligation.assertsPaymentReceived).toBe(false);

    expect(state.events).toHaveLength(1);
    expect(state.events[0].kind).toBe("CREATED");
    expect(state.events[0].actorUserId).toBe("owner-1");
    expect(prisma.sale.create).not.toHaveBeenCalled();
    expect(prisma.cashMovement.create).not.toHaveBeenCalled();
  });

  it("el reenvío idéntico no duplica ni escribe otro evento", async () => {
    const { service, state } = build();
    const first = await service.recordDeclaration(owner, "op-2", baseDto as never);
    const second = await service.recordDeclaration(owner, "op-2", baseDto as never);

    expect(state.created).toBe(1);
    expect(second.duplicate).toBe(true);
    expect(second.obligation.id).toBe(first.obligation.id);
    expect(state.events).toHaveLength(1);
  });

  it("dos encargados con la MISMA cantidad comparten la obligación (AMENDED)", async () => {
    const { service, state } = build();
    await service.recordDeclaration(owner, "op-3", baseDto as never);
    const other = await service.recordDeclaration(
      cashier,
      "op-3",
      { ...baseDto, declaredByUserId: "otro-encargado", note: "Confirmo el mismo monto" } as never,
    );

    expect(state.created).toBe(1);
    expect(state.updated).toBe(1);
    expect(other.amendment).toBe("AMENDED");
    expect(other.obligation.totalDeclared).toBe(50);
    expect(other.obligation.declarationCount).toBe(2);
    // Nunca hay dos obligaciones activas para la misma operación.
    const listing = await service.list(owner, "PENDING");
    expect(listing).toHaveLength(1);
    expect(state.events.map((e) => e.kind)).toEqual(["CREATED", "AMENDED"]);
    expect(state.events[1].actorUserId).toBe("otro-encargado");
  });

  it("un administrativo rectifica el importe y queda auditado", async () => {
    const { service, state } = build();
    await service.recordDeclaration(owner, "op-4", baseDto as never);
    const rectified = await service.recordDeclaration(
      owner,
      "op-4",
      { ...baseDto, totalDeclared: 55, note: "Arqueo: eran 55" } as never,
    );

    expect(state.created).toBe(1);
    expect(rectified.amendment).toBe("RECTIFIED");
    expect(rectified.obligation.totalDeclared).toBe(55);
    expect(rectified.obligation.version).toBe(2);
    expect(rectified.obligation.declarationCount).toBe(2);
    const event = state.events[1];
    expect(event.kind).toBe("RECTIFIED");
    expect(Number(event.previousTotal)).toBe(50);
    expect(Number(event.totalDeclared)).toBe(55);
  });

  it("un cajero NO puede cambiar el importe: 403 y rastro del rechazo", async () => {
    const { service, state } = build();
    await service.recordDeclaration(owner, "op-5", baseDto as never);

    await expect(
      service.recordDeclaration(cashier, "op-5", {
        ...baseDto,
        totalDeclared: 500,
      } as never),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(state.created).toBe(1);
    expect(state.updated).toBe(0);
    expect(state.row!.totalDeclared.toString()).toBe("50");
    expect(state.events.map((e) => e.kind)).toEqual([
      "CREATED",
      "RECTIFICATION_REJECTED",
    ]);
  });

  it("una carrera perdida (P2002) se resuelve contra la obligación que ganó", async () => {
    const { service, state } = build();
    await service.recordDeclaration(owner, "op-6", baseDto as never);
    // Simula que otra declaración simultánea ganó la creación: la actual ya
    // existe, así que el intento de crear choca con el índice único.
    state.row = null;
    let firstRead = true;
    const originalFindFirst =
      (service as any).prisma.saleReconciliationObligation.findFirst;
    (service as any).prisma.saleReconciliationObligation.findFirst = jest.fn(
      async (args: any) => {
        if (firstRead) {
          firstRead = false;
          return null; // no ve la activa (carrera)
        }
        return originalFindFirst(args);
      },
    );
    state.failNextCreateWithP2002 = true;
    state.row = buildRow({
      id: "obl-winner",
      companyId,
      clientRequestId: "op-6",
      declarationHash: "hash-del-ganador",
      totalDeclared: new Prisma.Decimal("50"),
      declaredAtUtc: new Date("2026-10-27T20:39:00.000Z"),
    });

    const result = await service.recordDeclaration(
      owner,
      "op-6",
      { ...baseDto, note: "Otra nota de la carrera" } as never,
    );

    expect(result.duplicate).toBe(false);
    expect(result.amendment).toBe("AMENDED");
    expect(result.obligation.id).toBe("obl-winner");
  });

  it("la empresa del listado es siempre la del token", async () => {
    const { service, prisma } = build();
    await service.list({ ...owner, companyId: otherCompany } as TenantUser);
    const args = prisma.saleReconciliationObligation.findMany.mock.calls[0][0];
    expect(args.where.companyId).toBe(otherCompany);
  });

  it("el historial de una obligación ajena no se expone", async () => {
    const { service } = build();
    await expect(
      service.listEvents({ ...owner, companyId: otherCompany } as TenantUser, "obl-x"),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("el historial de la propia obligación devuelve los eventos", async () => {
    const { service, state } = build();
    const created = await service.recordDeclaration(owner, "op-7", baseDto as never);
    const events = await service.listEvents(owner, created.obligation.id);
    expect(events).toHaveLength(1);
    expect(events[0].kind).toBe("CREATED");
    expect(events[0].totalDeclared).toBe(50);
    expect(state.events[0].clientRequestId).toBe("op-7");
  });

  it("rechaza una operación sin empresa (aislamiento multiempresa)", async () => {
    const { service } = build();
    await expect(
      service.recordDeclaration(
        { id: "x", role: "ADMIN" } as unknown as TenantUser,
        "op-8",
        baseDto as never,
      ),
    ).rejects.toBeTruthy();
  });
});
