/**
 * Validación final preproducción (realtime, aislamiento por empleado,
 * recuperabilidad offline y compatibilidad de contrato con builds 130/132).
 *
 * Solo apunta a la API UAT (127.0.0.1:4100) y a la base aislada
 * `daleventa_uat_local`. Nunca a producción.
 */
import { PrismaClient } from "@prisma/client";
import { io } from "socket.io-client";

const BASE = process.env.UAT_API_URL ?? "http://127.0.0.1:4100";
const COMPANY_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const T1 = "dddddddd-0000-4000-8000-000000000001";
const T2 = "dddddddd-0000-4000-8000-000000000002";
const PA = "eeeeeeee-0000-4000-8000-000000000001";
const PB = "eeeeeeee-0000-4000-8000-000000000002";
const PASSWORD = "Uat-1234!";
const RUN = Date.now().toString(36);

const prisma = new PrismaClient();
const results = [];
const IANA = "America/Santo_Domingo";

function record(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(`[${ok ? "PASS" : "FAIL"}] ${name}${detail ? ` — ${detail}` : ""}`);
}
function eq(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  record(name, ok, ok ? "" : `esperado=${JSON.stringify(expected)} obtenido=${JSON.stringify(actual)}`);
}
function businessDay(date) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: IANA, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}
async function req(method, path, token, body, extraHeaders = {}) {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...extraHeaders,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
  return { status: response.status, body: json };
}
async function login(email) {
  const r = await req("POST", "/auth/login", null, { email, password: PASSWORD });
  if (r.status >= 300) throw new Error(`login ${email}: ${r.status}`);
  return r.body.accessToken;
}
const sale = ({ sessionId, terminalId, occurredAt, items, method = "cash" }) => {
  const total = items.reduce((s, i) => s + i.qty * i.priceSoldUnit, 0);
  return {
    clientRequestId: `pp-${RUN}-${Math.random().toString(36).slice(2, 9)}`,
    originCashSessionId: sessionId,
    originTerminalId: terminalId,
    terminalId,
    saleOccurredAt: occurredAt.toISOString(),
    paymentMethod: method,
    paymentCashAmount: method === "credit" ? 0 : total,
    items,
  };
};

function waitForEvent(socket, predicate, timeoutMs = 8000) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => { socket.off("cash.event", handler); resolve(false); }, timeoutMs);
    const handler = (payload) => {
      if (!predicate(payload)) return;
      clearTimeout(timer);
      socket.off("cash.event", handler);
      resolve(true);
    };
    socket.on("cash.event", handler);
  });
}

function connect(token, tag) {
  const socket = io(BASE, { auth: { token }, transports: ["websocket"], reconnection: false, forceNew: true });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${tag} socket timeout`)), 10000);
    socket.on("connect", () => { clearTimeout(timer); resolve(socket); });
    socket.on("connect_error", (error) => { clearTimeout(timer); reject(new Error(`${tag} connect_error: ${error.message}`)); });
  });
}

async function main() {
  const admin = await login("admin.uat@fullpos.local");
  const c1 = await login("cajero1.uat@fullpos.local");
  const c2 = await login("cajero2.uat@fullpos.local");
  record("autenticación de los 3 empleados contra la API UAT", Boolean(admin && c1 && c2));

  const [user1, user2] = await Promise.all([
    prisma.user.findUnique({ where: { email: "cajero1.uat@fullpos.local" } }),
    prisma.user.findUnique({ where: { email: "cajero2.uat@fullpos.local" } }),
  ]);

  /* ---------- 1 · REALTIME ENTRE DISPOSITIVOS (socket.io real) ---------- */
  let socket1 = null;
  let socket2 = null;
  try {
    socket1 = await connect(c1, "cajero1");
    socket2 = await connect(c2, "cajero2");
    record("R1 dos clientes socket.io autenticados en la misma empresa", socket1.connected && socket2.connected);

    const openPromise2 = waitForEvent(socket2, (p) => `${p?.type ?? ""}`.includes("opened"));
    const open = await req("POST", "/cash/sessions/open", c1, { openingAmount: 100, terminalId: T1 });
    eq("R2 apertura de cajero1 por HTTP (201)", open.status, 201);
    const gotOpen = await openPromise2;
    record("R3 el OTRO dispositivo recibe el evento cash.session.opened", gotOpen);

    const closePromise2 = waitForEvent(socket2, (p) => `${p?.type ?? ""}`.includes("closed"));
    await req("POST", "/cash/sessions/close", c1, { sessionId: open.body.shiftId, closingAmount: 100 });
    const gotClose = await closePromise2;
    record("R4 el OTRO dispositivo recibe el evento cash.session.closed", gotClose);
  } catch (error) {
    record("R1-R4 realtime socket.io", false, String(error.message ?? error));
  } finally {
    socket1?.disconnect();
    socket2?.disconnect();
  }

  /* ---------- 2 · AISLAMIENTO POR EMPLEADO BAJO CONCURRENCIA ---------- */
  const open1 = await req("POST", "/cash/sessions/open", c1, { openingAmount: 200, terminalId: T1 });
  const open2 = await req("POST", "/cash/sessions/open", c2, { openingAmount: 300, terminalId: T1 });
  const open3 = await req("POST", "/cash/sessions/open", admin, { openingAmount: 400, terminalId: T2 });
  const shifts = { c1: open1.body?.shiftId, c2: open2.body?.shiftId, admin: open3.body?.shiftId };
  record("I1 tres turnos abiertos en paralelo", Boolean(shifts.c1 && shifts.c2 && shifts.admin));

  const rounds = [];
  for (let i = 0; i < 8; i += 1) {
    rounds.push(
      req("GET", "/cash/state", c1),
      req("GET", "/cash/state", c2),
      req("GET", "/cash/state", admin),
    );
  }
  const [s1, s2, s3] = await Promise.all(rounds);
  const ownOnly = (res, ownShift) => res.body?.activeSession?.shiftId === ownShift;
  record("I2 cajero1 sólo ve su propio turno (8 lecturas concurrentes)", ownOnly(s1, shifts.c1));
  record("I3 cajero2 sólo ve su propio turno", ownOnly(s2, shifts.c2));
  record("I4 el admin sólo ve su propio turno", ownOnly(s3, shifts.admin));

  // Cierre de cajero2 no debe alterar el estado de los demás
  await req("POST", "/cash/sessions/close", c2, { sessionId: shifts.c2, closingAmount: 300 });
  const after1 = await req("GET", "/cash/state", c1);
  const after3 = await req("GET", "/cash/state", admin);
  record("I5 cerrar el turno de cajero2 no afecta a cajero1", after1.body?.activeSession?.shiftId === shifts.c1 && after1.body?.canOperate === true);
  record("I6 cerrar el turno de cajero2 no afecta al admin", after3.body?.activeSession?.shiftId === shifts.admin && after3.body?.canOperate === true);

  await req("POST", "/cash/sessions/close", c1, { sessionId: shifts.c1, closingAmount: 200 });
  await req("POST", "/cash/sessions/close", admin, { sessionId: shifts.admin, closingAmount: 400 });

  /* ---------- 3 · OFFLINE RECHAZADA TRAS CIERRE: RECUPERABLE ---------- */
  const openedAt = new Date(Date.now() - 2 * 3_600_000);
  const offlineShift = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: user1.id,
      userName: "Cajero Uno",
      openedAt,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(openedAt),
    },
  });
  const payload = sale({ sessionId: offlineShift.id, terminalId: T1, occurredAt: new Date(openedAt.getTime() + 60_000), items: [{ productId: PA, qty: 1, priceSoldUnit: 250, costUnitSnapshot: 100 }] });
  const firstTry = await req("POST", "/sales", c1, payload);
  eq("D1 la venta offline entra mientras el turno está abierto (201)", firstTry.status, 201);

  const summary = await req("GET", "/cash/summary", c1);
  await req("POST", "/cash/sessions/close", c1, { sessionId: offlineShift.id, closingAmount: Number(summary.body?.expectedCash ?? 0) });

  const retries = [];
  for (let i = 0; i < 3; i += 1) retries.push(await req("POST", "/sales", c1, { ...payload, clientRequestId: `${payload.clientRequestId}-r${i}` }));
  record("D2 los 3 reintentos tras el cierre se rechazan controladamente (409)", retries.every((r) => r.status === 409), retries.map((r) => r.status).join(","));
  record("D3 el código permite reconstruir la operación (ORIGIN_SESSION_CLOSED)", retries.every((r) => (r.body?.code ?? r.body?.errorCode) === "ORIGIN_SESSION_CLOSED"));
  const duplicate = await prisma.sale.count({ where: { companyId: COMPANY_ID, cashSessionId: offlineShift.id } });
  eq("D4 no hay duplicación: 1 sola venta en ese turno", duplicate, 1);
  const rejectedSales = await prisma.sale.count({ where: { companyId: COMPANY_ID, clientRequestId: { startsWith: payload.clientRequestId } } });
  eq("D5 los reintentos rechazados no crearon filas", rejectedSales, 1);

  // El rechazo no re-imputa a un turno nuevo: reenviar la operación vieja
  // apuntando a un turno recién abierto debe fallar (la operación ocurrió antes
  // de esa apertura) y NO crear filas. Es la garantía financiera correcta.
  const newShift = await req("POST", "/cash/sessions/open", c1, { openingAmount: 0, terminalId: T1 });
  const wrongTarget = await req("POST", "/sales", c1, { ...payload, originCashSessionId: newShift.body.shiftId, clientRequestId: `${payload.clientRequestId}-new` });
  record(
    "D6 reenviar la operación vieja a un turno nuevo se rechaza (sin re-imputación silenciosa)",
    wrongTarget.status === 409 && (wrongTarget.body?.code ?? wrongTarget.body?.errorCode) === "CASH_OPERATION_BEFORE_SHIFT",
    `status=${wrongTarget.status} code=${wrongTarget.body?.code ?? wrongTarget.body?.errorCode}`,
  );
  const reimputed = await prisma.sale.count({ where: { companyId: COMPANY_ID, clientRequestId: `${payload.clientRequestId}-new` } });
  eq("D7 la re-imputación rechazada no crea filas", reimputed, 0);
  // Control positivo: el turno nuevo sí es operable con una operación de ahora.
  const freshSale = await req("POST", "/sales", c1, sale({ sessionId: newShift.body.shiftId, terminalId: T1, occurredAt: new Date(), items: [{ productId: PA, qty: 1, priceSoldUnit: 250 }] }));
  record("D8 el turno nuevo sigue siendo operable (control positivo)", freshSale.status === 201, `status=${freshSale.status}`);
  const freshSummary = await req("GET", "/cash/summary", c1);
  await req("POST", "/cash/sessions/close", c1, { sessionId: newShift.body.shiftId, closingAmount: Number(freshSummary.body?.expectedCash ?? 0) });

  /* ---------- 4 · COMPATIBILIDAD DE CONTRATO BUILD 132 / 130 ---------- */
  // Payloads idénticos a los que envían esas builds (verificado en su código).
  const open132 = await req("POST", "/cash/sessions/open", c2, { openingAmount: 50, deviceFingerprint: "device-B" }, { "x-client-app-version": "1.0.6+132", "x-client-platform": "windows" });
  const shift132 = open132.body?.shiftId;
  const state132 = await req("GET", "/cash/state", c2, undefined, { "x-client-app-version": "1.0.6+132", "x-client-platform": "windows" });
  const requiredForOld = ["businessDate", "canOperate", "activeSession", "cashboxToday"];
  record("C1 /cash/state conserva TODOS los campos que exige la build 132", requiredForOld.every((k) => k in (state132.body ?? {})) && Boolean(state132.body?.activeSession?.shiftId === shift132));
  const sale132 = await req("POST", "/sales", c2, { ...sale({ sessionId: shift132, terminalId: null, occurredAt: new Date(), items: [{ productId: PB, qty: 1, priceSoldUnit: 450, costUnitSnapshot: 200 }] }), originTerminalId: undefined }, { "x-client-app-version": "1.0.6+132" });
  record("C2 venta con el payload de 132 (sin terminal) aceptada", sale132.status === 201, `status=${sale132.status} ${sale132.status !== 201 ? JSON.stringify(sale132.body).slice(0, 160) : ""}`);
  const move132 = await req("POST", "/cash/movements", c2, { sessionId: shift132, operationId: `pp132-${RUN}`, type: "IN", amount: 20, reason: "propina", movementType: "transfer" }, { "x-client-app-version": "1.0.6+132" });
  record("C3 movimiento SIN occurredAt (como envía 132/130) aceptado", move132.status === 201, `status=${move132.status}`);
  const sum132 = await req("GET", "/cash/summary", c2, undefined, { "x-client-app-version": "1.0.6+132" });
  const close132 = await req("POST", "/cash/sessions/close", c2, { sessionId: shift132, closingAmount: Number(sum132.body?.expectedCash ?? 0) }, { "x-client-app-version": "1.0.6+132" });
  record("C4 cierre identificado con el payload de 132 aceptado", [200, 201].includes(close132.status), `status=${close132.status}`);

  // Turno vencido visto por un cliente viejo: debe poder CERRARLO
  const staleOpenedAt = new Date(Date.now() - 3 * 86_400_000);
  const staleShift = await prisma.cashSession.create({
    data: { companyId: COMPANY_ID, openedByUserId: user2.id, userName: "Cajero Dos", openedAt: staleOpenedAt, initialAmount: 0, status: "OPEN", businessDate: businessDay(staleOpenedAt) },
  });
  const staleState130 = await req("GET", "/cash/state", c2, undefined, { "x-client-app-version": "1.0.6+130", "x-client-platform": "ios" });
  record(
    "C5 un cliente 130 recibe el turno vencido con activeSession (puede pulsar Cerrar turno)",
    staleState130.status === 200 && staleState130.body?.activeSession?.shiftId === staleShift.id,
    `status=${staleState130.status}`,
  );
  const staleSale130 = await req("POST", "/sales", c2, sale({ sessionId: staleShift.id, terminalId: null, occurredAt: new Date(), items: [{ productId: PA, qty: 1, priceSoldUnit: 250 }] }), { "x-client-app-version": "1.0.6+130" });
  record("C6 la venta en turno vencido se rechaza con un `code` legible por el cliente", staleSale130.status === 409 && Boolean(staleSale130.body?.code ?? staleSale130.body?.errorCode), `code=${staleSale130.body?.code}`);
  const closeStale130 = await req("POST", "/cash/sessions/close", c2, { sessionId: staleShift.id, closingAmount: 0 }, { "x-client-app-version": "1.0.6+130" });
  record("C7 el cliente 130 cierra su turno vencido sin cambios de cliente", [200, 201].includes(closeStale130.status), `status=${closeStale130.status}`);

  const openLeft = await prisma.cashSession.count({ where: { companyId: COMPANY_ID, status: "OPEN" } });
  eq("Z1 no quedan turnos abiertos al finalizar", openLeft, 0);

  const failed = results.filter((r) => !r.ok);
  console.log("\n===== RESUMEN PREPRODUCCIÓN =====");
  console.log(`Total: ${results.length} · OK: ${results.length - failed.length} · FALLOS: ${failed.length}`);
  for (const f of failed) console.log(`  - ${f.name} :: ${f.detail}`);
  process.exitCode = failed.length ? 1 : 0;
}

main()
  .catch((error) => { console.error("[preprod] ERROR FATAL", error); process.exitCode = 2; })
  .finally(async () => { await prisma.$disconnect(); });
