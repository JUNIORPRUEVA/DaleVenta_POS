import http from "node:http";
import * as jwt from "jsonwebtoken";
import { io as createClient, type Socket } from "socket.io-client";
import { CashService } from "../cash/cash.service";
import { CatalogRealtimeRelayService } from "./catalog-realtime-relay.service";

/**
 * Prueba multi-cliente realtime de caja con Socket.IO REAL en memoria:
 *  - DOS sockets del MISMO usuario/empresa (Windows + Android) reciben el
 *    evento `cash.event` al abrir/cerrar turno (no se sobrescriben entre sí).
 *  - Un socket de OTRA empresa NO recibe el evento (room correcto).
 *  - Un fallo al abrir NO emite un evento falso.
 * Demuestra el lado servidor de la cadena realtime: DB commit → emit → room.
 */
const JWT_SECRET = "realtime-test-secret";
const COMPANY_A = "11111111-1111-1111-1111-111111111111";
const COMPANY_B = "22222222-2222-4222-8222-222222222222";
const USER = { id: "user-a", role: "ADMIN", companyId: COMPANY_A };

function tokenFor(companyId: string) {
  return jwt.sign(
    { sub: USER.id, role: "ADMIN", companyId, tokenType: "access" },
    JWT_SECRET,
  );
}

function waitFor(
  cond: () => boolean,
  timeout = 4000,
  interval = 25,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      if (cond()) return resolve();
      if (Date.now() - start > timeout) {
        return reject(new Error("timeout waiting for condition"));
      }
      setTimeout(tick, interval);
    };
    tick();
  });
}

function buildCashHarness(relay: CatalogRealtimeRelayService) {
  const tx = {
    cashSession: {
      findFirst: jest.fn(),
      create: jest.fn(),
      updateMany: jest.fn(),
    },
    cashboxDaily: {
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
  };
  const prisma = {
    user: {
      findUnique: jest
        .fn()
        .mockResolvedValue({ nombreCompleto: "Cajero", email: "c@x.com", blocked: false }),
    },
    cashSession: { findFirst: jest.fn() },
    cashboxDaily: { findFirst: jest.fn(), create: jest.fn(), update: jest.fn() },
    cashMovement: { findMany: jest.fn().mockResolvedValue([]), create: jest.fn() },
    sale: { findMany: jest.fn().mockResolvedValue([]) },
    saleCreditPayment: { findMany: jest.fn().mockResolvedValue([]) },
    $transaction: jest.fn((callback: (t: unknown) => unknown) =>
      callback({ ...tx }),
    ),
  };
  const service = new CashService(prisma as never, relay as never);
  return { prisma, tx, service };
}

describe("realtime cash multi-cliente (Socket.IO real en memoria)", () => {
  let server: http.Server;
  let relay: CatalogRealtimeRelayService;
  let baseUrl: string;
  let sockets: Socket[] = [];

  beforeAll(async () => {
    const config = {
      get: (key: string) => (key === "JWT_SECRET" ? JWT_SECRET : ""),
    } as never;
    relay = new CatalogRealtimeRelayService(config);
    server = http.createServer();
    relay.attach(server);
    await new Promise<void>((resolve) => server.listen(0, () => resolve()));
    const address = server.address() as { port: number };
    baseUrl = `http://localhost:${address.port}`;
  });

  afterAll(async () => {
    for (const s of sockets) s.disconnect();
    sockets = [];
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  function connect(companyId: string): Socket {
    const s = createClient(baseUrl, {
      transports: ["websocket"],
      auth: { token: tokenFor(companyId) },
    });
    sockets.push(s);
    return s;
  }

  function makeSession(id: string) {
    return {
      id,
      openedByUserId: USER.id,
      cashboxDailyId: "cashbox-1",
      openedAt: new Date(),
      status: "OPEN",
      userName: "Cajero",
      businessDate: "2026-08-22",
    };
  }

  it(
    "Test 1/5/6 — abrir turno emite cash.event a DOS sockets del mismo " +
      "usuario/empresa y NO a otra empresa",
    async () => {
      const win = connect(COMPANY_A); // Windows
      const and = connect(COMPANY_A); // Android
      const other = connect(COMPANY_B); // otra empresa
      const winEvents: any[] = [];
      const andEvents: any[] = [];
      const otherEvents: any[] = [];
      win.on("cash.event", (d) => winEvents.push(d));
      and.on("cash.event", (d) => andEvents.push(d));
      other.on("cash.event", (d) => otherEvents.push(d));

      await waitFor(() => win.connected && and.connected && other.connected);

      const { tx, service } = buildCashHarness(relay);
      (tx.cashSession.findFirst as jest.Mock).mockResolvedValue(null);
      (tx.cashboxDaily.findFirst as jest.Mock).mockResolvedValue(null);
      (tx.cashboxDaily.create as jest.Mock).mockResolvedValue({ id: "cashbox-1" });
      (tx.cashSession.create as jest.Mock).mockResolvedValue(makeSession("shift-1"));

      const startedAt = performance.now();
      await service.startSession(USER, { openingAmount: 1000 });

      await waitFor(() => winEvents.length >= 1 && andEvents.length >= 1);
      const latencyMs = performance.now() - startedAt;
      // FASE F — medición aproximada: confirmación backend → evento recibido
      // por el otro cliente (red local/in-memory).
      // eslint-disable-next-line no-console
      console.log(
        `[latencia] startSession confirmado → cash.event recibido en ambos = ${latencyMs.toFixed(1)}ms`,
      );
      expect(latencyMs).toBeLessThan(2000); // objetivo < 1-2s
      expect(winEvents[0].type).toBe("cash.session.opened");
      expect(winEvents[0].companyId).toBe(COMPANY_A);
      expect(andEvents[0].type).toBe("cash.session.opened");
      // Ambos sockets conviven: ninguno reemplazó la conexión del otro.
      expect(win.connected).toBe(true);
      expect(and.connected).toBe(true);
      // Empresa B NO recibe (room company:A).
      expect(otherEvents.length).toBe(0);
    },
  );

  it("Test 2 — cerrar turno emite cash.event a ambos sockets", async () => {
    const win = connect(COMPANY_A);
    const and = connect(COMPANY_A);
    const winEvents: any[] = [];
    const andEvents: any[] = [];
    win.on("cash.event", (d) => winEvents.push(d));
    and.on("cash.event", (d) => andEvents.push(d));
    await waitFor(() => win.connected && and.connected);

    const { prisma, tx, service } = buildCashHarness(relay);
    // requireOpenSession + buildSummary
    (prisma.cashSession.findFirst as jest.Mock).mockResolvedValue(
      makeSession("shift-1"),
    );
    (tx.cashSession.updateMany as jest.Mock).mockResolvedValue({ count: 1 });
    (tx.cashSession.findFirst as jest.Mock)
      .mockResolvedValueOnce({ ...makeSession("shift-1"), status: "CLOSED" }) // closed
      .mockResolvedValueOnce(null); // otherOpen
    (tx.cashboxDaily.update as jest.Mock).mockResolvedValue({ id: "cashbox-1" });

    await service.closeSession(USER, { closingAmount: 1000 });

    await waitFor(() => winEvents.length >= 1 && andEvents.length >= 1);
    expect(winEvents[0].type).toBe("cash.session.closed");
    expect(andEvents[0].type).toBe("cash.session.closed");
  });

  it("Test 3 — fallo al abrir NO emite evento falso", async () => {
    const win = connect(COMPANY_A);
    const winEvents: any[] = [];
    win.on("cash.event", (d) => winEvents.push(d));
    await waitFor(() => win.connected);

    const { prisma, service } = buildCashHarness(relay);
    // La transacción falla (p. ej. error de DB): el emit va DESPUÉS del commit.
    (prisma.$transaction as jest.Mock).mockRejectedValue(new Error("db down"));

    await expect(
      service.startSession(USER, { openingAmount: 1000 }),
    ).rejects.toThrow("db down");

    await new Promise((resolve) => setTimeout(resolve, 150));
    expect(winEvents.length).toBe(0);
  });
});
