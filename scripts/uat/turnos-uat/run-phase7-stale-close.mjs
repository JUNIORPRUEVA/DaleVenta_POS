/**
 * Fase 7 · Cierre de turno vencido desde el contrato de la build 145 (hotfix).
 *
 * Reproduce el flujo EXACTO que ejecuta la app Windows 145 al cerrar caja:
 *   GET /cash/state -> GET /cash/summary -> GET /cash/movements -> POST /cash/sessions/close
 * y verifica que después puede abrir turno y vender, sin perder el blindaje
 * financiero (las ventas nuevas sobre turnos vencidos siguen rechazadas).
 *
 * Solo apunta a la API UAT (127.0.0.1:4100) y a `daleventa_uat_local`.
 */
import { PrismaClient } from "@prisma/client";

const BASE = process.env.UAT_API_URL ?? "http://127.0.0.1:4100";
const COMPANY_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const T1 = "dddddddd-0000-4000-8000-000000000001";
const PA = "eeeeeeee-0000-4000-8000-000000000001";
const PASSWORD = "Uat-1234!";
const RUN = Date.now().toString(36);
const IANA = "America/Santo_Domingo";

const prisma = new PrismaClient({
  datasources: {
    db: {
      url: `${process.env.DATABASE_URL}${process.env.DATABASE_URL.includes("?") ? "&" : "?"}application_name=uat-harness`,
    },
  },
});
const results = [];
const record = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`[${ok ? "PASS" : "FAIL"}] ${name}${detail ? ` — ${detail}` : ""}`);
};
const eq = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  record(name, ok, ok ? "" : `esperado=${JSON.stringify(expected)} obtenido=${JSON.stringify(actual)}`);
};
const money = (v) => Number(v?.toString?.() ?? v ?? 0).toFixed(2);
const businessDay = (d) =>
  new Intl.DateTimeFormat("en-CA", { timeZone: IANA, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);

async function req(method, path, token, body) {
  const r = await fetch(`${BASE}${path}`, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
  return { status: r.status, body: json };
}
async function login(email) {
  const r = await req("POST", "/auth/login", null, { email, password: PASSWORD });
  if (r.status >= 300) throw new Error(`login ${email}: ${r.status}`);
  return r.body.accessToken;
}
const codeOf = (r) => r.body?.code ?? r.body?.errorCode ?? null;

async function main() {
  const token = await login("cajero1.uat@fullpos.local");
  const user = await prisma.user.findUnique({ where: { email: "cajero1.uat@fullpos.local" } });
  record("autenticación del cajero titular", Boolean(token && user));

  /* ---------- Turno vencido con ventas reales dentro de su ventana ---------- */
  const openedAt = new Date(Date.now() - 4 * 86_400_000);
  const stale = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: user.id,
      userName: "Cajero Uno",
      openedAt,
      initialAmount: 100,
      status: "OPEN",
      businessDate: businessDay(openedAt),
    },
  });
  const saleInWindow = await req("POST", "/sales", token, {
    clientRequestId: `p7-in-${RUN}`,
    originCashSessionId: stale.id,
    originTerminalId: T1,
    terminalId: T1,
    saleOccurredAt: new Date(openedAt.getTime() + 60 * 60_000).toISOString(),
    paymentMethod: "cash",
    paymentCashAmount: 250,
    items: [{ productId: PA, qty: 1, priceSoldUnit: 250, costUnitSnapshot: 100 }],
  });
  record("A0 venta histórica dentro de la ventana aceptada en el turno vencido", saleInWindow.status === 201, `status=${saleInWindow.status}`);

  /* ---------- FLUJO EXACTO DE LA APP 145 ---------- */
  const state = await req("GET", "/cash/state", token);
  record(
    "A1 GET /cash/state expone el turno vencido como activo",
    state.status === 200 && state.body?.activeSession?.shiftId === stale.id,
    `status=${state.status} active=${state.body?.activeSession?.shiftId ?? "null"} stale=${state.body?.staleBusinessDate}`,
  );
  eq("A2 el estado marca staleBusinessDate/canOperate", [state.body?.staleBusinessDate, state.body?.canOperate], [true, false]);

  const summary = await req("GET", "/cash/summary", token);
  record("A3 GET /cash/summary responde 200 en turno vencido (antes 409)", summary.status === 200, `status=${summary.status} code=${codeOf(summary)}`);
  eq("A4 el resumen corresponde al turno vencido", summary.body?.sessionId, stale.id);
  eq("A5 el resumen incluye la venta histórica + fondo", money(summary.body?.expectedCash), "350.00");

  const movements = await req("GET", "/cash/movements", token);
  record("A6 GET /cash/movements responde 200 en turno vencido (antes 409)", movements.status === 200, `status=${movements.status} code=${codeOf(movements)}`);

  const closed = await req("POST", "/cash/sessions/close", token, {
    sessionId: stale.id,
    closingAmount: 350,
    note: "cierre de prueba con conteo declarado",
  });
  record("A7 POST /cash/sessions/close acepta el contrato de la build 145", [200, 201].includes(closed.status), `status=${closed.status} code=${codeOf(closed)}`);
  const closedRow = await prisma.cashSession.findUnique({ where: { id: stale.id } });
  eq("A8 el turno quedó CLOSED con el importe declarado y su esperado", [closedRow?.status, money(closedRow?.closingAmount), money(closedRow?.expectedAmount)], ["CLOSED", "350.00", "350.00"]);
  eq("A9 la diferencia registrada es 0 (conteo = esperado)", money(closedRow?.difference), "0.00");

  const stateAfter = await req("GET", "/cash/state", token);
  record("A10 tras cerrar, /cash/state ya no muestra turno activo", stateAfter.status === 200 && stateAfter.body?.activeSession === null, `status=${stateAfter.status}`);

  /* ---------- Reapertura y venta normal ---------- */
  const opened = await req("POST", "/cash/sessions/open", token, { openingAmount: 200, terminalId: T1 });
  record("A11 apertura del turno del día", opened.status === 201, `status=${opened.status}`);
  const newShift = opened.body?.shiftId;

  const freshSale = await req("POST", "/sales", token, {
    clientRequestId: `p7-new-${RUN}`,
    originCashSessionId: newShift,
    originTerminalId: T1,
    terminalId: T1,
    saleOccurredAt: new Date().toISOString(),
    paymentMethod: "cash",
    paymentCashAmount: 180,
    items: [{ productId: PA, qty: 1, priceSoldUnit: 180, costUnitSnapshot: 70 }],
  });
  record("A12 venta normal en el turno nuevo aceptada", freshSale.status === 201, `status=${freshSale.status}`);
  eq("A13 la venta se imputa al turno nuevo", freshSale.body?.cashSessionId, newShift);

  const sumNew = await req("GET", "/cash/summary", token);
  eq("A14 resumen del turno nuevo = fondo + venta", money(sumNew.body?.expectedCash), "380.00");
  const closeNew = await req("POST", "/cash/sessions/close", token, { sessionId: newShift, closingAmount: 380 });
  record("A15 cierre del turno nuevo", [200, 201].includes(closeNew.status), `status=${closeNew.status}`);

  /* ---------- Caja diaria e integridad ---------- */
  const box = await prisma.cashboxDaily.findFirst({
    where: { companyId: COMPANY_ID, businessDate: businessDay(new Date()) },
  });
  if (box) {
    const agg = await prisma.cashSession.aggregate({
      where: { cashboxDailyId: box.id, status: "CLOSED", closedAt: { not: null } },
      _sum: { closingAmount: true },
    });
    eq(
      "A16 caja diaria del día = suma de sus cierres",
      Number((Number(box.currentAmount) - Number(agg._sum.closingAmount ?? 0)).toFixed(2)),
      0,
    );
  } else {
    record("A16 caja diaria del día = suma de sus cierres", false, "sin caja diaria para hoy");
  }

  const staleBox = await prisma.cashboxDaily.findFirst({
    where: { companyId: COMPANY_ID, businessDate: businessDay(openedAt) },
  });
  if (staleBox) {
    const aggStale = await prisma.cashSession.aggregate({
      where: { cashboxDailyId: staleBox.id, status: "CLOSED", closedAt: { not: null } },
      _sum: { closingAmount: true },
    });
    eq(
      "A17 caja diaria del turno vencido recalculada con su cierre",
      Number((Number(staleBox.currentAmount) - Number(aggStale._sum.closingAmount ?? 0)).toFixed(2)),
      0,
    );
  }

  /* ---------- El blindaje financiero sigue intacto ---------- */
  const openedAt2 = new Date(Date.now() - 5 * 86_400_000);
  const stale2 = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: user.id,
      userName: "Cajero Uno",
      openedAt: openedAt2,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(openedAt2),
    },
  });
  const blocked = await req("POST", "/sales", token, {
    clientRequestId: `p7-block-${RUN}`,
    originCashSessionId: stale2.id,
    originTerminalId: T1,
    terminalId: T1,
    saleOccurredAt: new Date().toISOString(),
    paymentMethod: "cash",
    paymentCashAmount: 100,
    items: [{ productId: PA, qty: 1, priceSoldUnit: 100, costUnitSnapshot: 40 }],
  });
  record(
    "B1 venta NUEVA sobre un turno vencido sigue rechazada",
    blocked.status === 409 && codeOf(blocked) === "CASH_SESSION_STALE",
    `status=${blocked.status} code=${codeOf(blocked)}`,
  );
  eq(
    "B2 el rechazo no creó filas",
    await prisma.sale.count({ where: { companyId: COMPANY_ID, clientRequestId: `p7-block-${RUN}` } }),
    0,
  );

  const staleSummary = await req("GET", "/cash/summary", token);
  record("B3 el turno vencido restante sigue siendo consultable", staleSummary.status === 200, `status=${staleSummary.status}`);
  const adminClose2 = await req("POST", `/cash/sessions/${stale2.id}/admin-close`, await login("admin.uat@fullpos.local"), {
    reason: "limpieza al final del escenario de prueba",
    closingAmount: 0,
  });
  record("B4 cierre administrativo disponible como respaldo", [200, 201].includes(adminClose2.status), `status=${adminClose2.status}`);

  const openLeft = await prisma.cashSession.count({ where: { companyId: COMPANY_ID, status: "OPEN" } });
  eq("Z1 no quedan turnos abiertos", openLeft, 0);

  const failed = results.filter((r) => !r.ok);
  console.log("\n===== RESUMEN FASE 7 · CIERRE DE TURNO VENCIDO =====");
  console.log(`Total: ${results.length} · OK: ${results.length - failed.length} · FALLOS: ${failed.length}`);
  for (const f of failed) console.log(`  - ${f.name} :: ${f.detail}`);
  process.exitCode = failed.length ? 1 : 0;
}

main()
  .catch((error) => {
    console.error("[fase7] ERROR FATAL", error);
    process.exitCode = 2;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
