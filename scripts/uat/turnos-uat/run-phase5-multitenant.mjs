/**
 * FASE 5 — Validación financiera E2E con PostgreSQL real (base UAT aislada).
 *
 * Cubre lo que no estaba en los scripts anteriores:
 *  - Tres empleados simultáneos + dos terminales (una compartida).
 *  - Aperturas y cierres CONCURRENTES.
 *  - Movimiento de efectivo entre cajeros (entrega/recibe) sin doble conteo.
 *  - Aislamiento entre DOS empresas (sin fuga de datos ni cierres cruzados).
 *  - Invariantes: closing == expected, diferencia 0, ventas por turno,
 *    cierres diarios por empresa, idempotencia de reintentos.
 */
import { PrismaClient } from "@prisma/client";

const BASE = process.env.UAT_API_URL ?? "http://127.0.0.1:4100";
const COMPANY_A = "aaaaaaaa-0000-4000-8000-000000000001";
const COMPANY_B = "aaaaaaaa-0000-4000-8000-000000000002";
const T1 = "dddddddd-0000-4000-8000-000000000001";
const T2 = "dddddddd-0000-4000-8000-000000000002";
const TB1 = "dddddddd-0000-4000-8000-0000000000b1";
const PA = "eeeeeeee-0000-4000-8000-000000000001";
const PB = "eeeeeeee-0000-4000-8000-000000000002";
const PB1 = "eeeeeeee-0000-4000-8000-0000000000b1";
const PASSWORD = "Uat-1234!";
const RUN = Date.now().toString(36);
const IANA = "America/Santo_Domingo";

const prisma = new PrismaClient();
const results = [];
function rec(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(`[${ok ? "PASS" : "FAIL"}] ${name}${detail ? ` — ${detail}` : ""}`);
}
function eq(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  rec(name, ok, ok ? "" : `esperado=${JSON.stringify(expected)} obtenido=${JSON.stringify(actual)}`);
}
function bd(date) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: IANA, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}
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
  if (r.status >= 300) throw new Error(`login ${email}: ${r.status} ${JSON.stringify(r.body)}`);
  return r.body.accessToken;
}
const money = (n) => Number(n ?? 0).toFixed(2);
function saleOf({ sessionId, terminalId, productId, price, qty = 1, cost = 0, occurredAt = new Date(), clientRequestId }) {
  return {
    clientRequestId: clientRequestId ?? `f5-${RUN}-${Math.random().toString(36).slice(2, 9)}`,
    originCashSessionId: sessionId,
    ...(terminalId ? { originTerminalId: terminalId, terminalId } : {}),
    saleOccurredAt: occurredAt.toISOString(),
    paymentMethod: "cash",
    paymentCashAmount: price * qty,
    items: [{ productId, qty, priceSoldUnit: price, costUnitSnapshot: cost }],
  };
}

async function main() {
  const [adminA, c1, c2, cB] = await Promise.all([
    login("admin.uat@fullpos.local"),
    login("cajero1.uat@fullpos.local"),
    login("cajero2.uat@fullpos.local"),
    login("cajero.uat.b@fullpos.local"),
  ]);
  rec("autenticación: 3 empleados de empresa A + 1 de empresa B", Boolean(adminA && c1 && c2 && cB));

  /* ---------- Aperturas CONCURRENTES (3 usuarios A + 1 usuario B) ---------- */
  const [oA, oB, oC, oD] = await Promise.all([
    req("POST", "/cash/sessions/open", c1, { openingAmount: 100, terminalId: T1 }),
    req("POST", "/cash/sessions/open", c2, { openingAmount: 100, terminalId: T1 }),
    req("POST", "/cash/sessions/open", adminA, { openingAmount: 100, terminalId: T2 }),
    req("POST", "/cash/sessions/open", cB, { openingAmount: 100, terminalId: TB1 }),
  ]);
  rec("O1 cuatro aperturas concurrentes exitosas", [oA, oB, oC, oD].every((r) => r.status === 201), [oA.status, oB.status, oC.status, oD.status].join(","));
  const sA = oA.body?.shiftId, sB = oB.body?.shiftId, sC = oC.body?.shiftId, sD = oD.body?.shiftId;
  if (![sA, sB, sC, sD].every(Boolean)) {
    console.error(`[fase5] ABORTO: faltan turnos (${[sA, sB, sC, sD].join(", ")}) — se detiene aquí para no encadenar cascadas.`);
    await prisma.$disconnect();
    process.exit(1);
  }
  eq("O2 dos cajeros comparten terminal T1 y obtienen turnos distintos", sA !== sB, true);

  /* ---------- Aislamiento entre empresas ---------- */
  const stateB = await req("GET", "/cash/state", cB);
  eq("X1 la empresa B sólo ve su propio turno", stateB.body?.activeSession?.shiftId, sD);
  const adminB_onA = await req("POST", `/cash/sessions/${sA}/admin-close`, cB, { reason: "intento entre empresas", closingAmount: 0 });
  rec("X2 B no puede cerrar un turno de A", [403, 404].includes(adminB_onA.status), `status=${adminB_onA.status}`);
  const closedAsB = await req("GET", "/cash/sessions/closed?page=1&limit=50", cB);
  const leaks = (closedAsB.body?.items ?? []).filter((item) => item.sessionId === sA || item.id === sA).length;
  eq("X3 el historial de B no contiene turnos de A", leaks, 0);

  /* ---------- Ventas y movimiento de efectivo entre cajeros ---------- */
  const saleA = await req("POST", "/sales", c1, saleOf({ sessionId: sA, terminalId: T1, productId: PA, price: 250, cost: 100 }));
  const saleB = await req("POST", "/sales", c2, saleOf({ sessionId: sB, terminalId: T1, productId: PB, price: 450, cost: 200 }));
  const saleC = await req("POST", "/sales", adminA, saleOf({ sessionId: sC, terminalId: T2, productId: PA, price: 800, cost: 300 }));
  const saleD = await req("POST", "/sales", cB, saleOf({ sessionId: sD, terminalId: TB1, productId: PB1, price: 100, cost: 50 }));
  rec("V1 una venta por empleado (4)", [saleA, saleB, saleC, saleD].every((r) => r.status === 201), [saleA.status, saleB.status, saleC.status, saleD.status].join(","));
  eq("V2 la venta de B no cae en un turno de A", saleD.body?.cashSessionId, sD);

  // Entrega de efectivo cajero1 -> cajero2 (mismo efectivo, dos registros causales)
  const out = await req("POST", "/cash/movements", c1, { sessionId: sA, operationId: `f5-out-${RUN}`, type: "OUT", amount: 100, reason: "Entrega de fondo a cajero2", movementType: "transfer" });
  const inc = await req("POST", "/cash/movements", c2, { sessionId: sB, operationId: `f5-in-${RUN}`, type: "IN", amount: 100, reason: "Recibido de cajero1", movementType: "transfer" });
  rec("V3 entrega y recepción registradas en sus turnos", out.status === 201 && inc.status === 201, `${out.status}/${inc.status}`);
  eq("V4 ambas conservan su turno de origen", [out.body?.sessionId, inc.body?.sessionId], [sA, sB]);

  /* ---------- Resúmenes e invariantes ---------- */
  const [sumA, sumB, sumC, sumD] = await Promise.all([
    req("GET", "/cash/summary", c1),
    req("GET", "/cash/summary", c2),
    req("GET", "/cash/summary", adminA),
    req("GET", "/cash/summary", cB),
  ]);
  // A: 100 + 250 - 100 = 250 ; B: 100 + 450 + 100 = 650 ; C: 100 + 800 = 900 ; D: 100 + 100 = 200
  eq("S1 esperado cajero1 (entrega 100 descontada)", money(sumA.body?.expectedCash), "250.00");
  eq("S2 esperado cajero2 (recibe 100 sumado)", money(sumB.body?.expectedCash), "650.00");
  eq("S3 esperado admin", money(sumC.body?.expectedCash), "900.00");
  eq("S4 esperado empresa B", money(sumD.body?.expectedCash), "200.00");
  const totalA = Number(sumA.body?.expectedCash) + Number(sumB.body?.expectedCash) + Number(sumC.body?.expectedCash);
  eq("S5 el efectivo entregado no se cuenta dos veces (total A = 1800)", money(totalA), "1800.00");

  /* ---------- Cierres CONCURRENTES ---------- */
  const closed = await Promise.all([
    req("POST", "/cash/sessions/close", c1, { sessionId: sA, closingAmount: Number(sumA.body?.expectedCash), note: "fase5 A" }),
    req("POST", "/cash/sessions/close", c2, { sessionId: sB, closingAmount: Number(sumB.body?.expectedCash), note: "fase5 B" }),
    req("POST", "/cash/sessions/close", adminA, { sessionId: sC, closingAmount: Number(sumC.body?.expectedCash), note: "fase5 C" }),
    req("POST", "/cash/sessions/close", cB, { sessionId: sD, closingAmount: Number(sumD.body?.expectedCash), note: "fase5 D" }),
  ]);
  rec("C1 cuatro cierres concurrentes exitosos", closed.every((r) => [200, 201].includes(r.status)), closed.map((r) => r.status).join(","));
  const diffs = closed.map((r) => Number(r.body?.difference ?? 0));
  rec("C2 todas las diferencias son 0", diffs.every((d) => d === 0), diffs.join(","));

  const rows = await prisma.cashSession.findMany({
    where: { id: { in: [sA, sB, sC, sD].filter(Boolean) } },
    select: { id: true, status: true, closingAmount: true, expectedAmount: true, difference: true, businessDate: true, companyId: true },
  });
  rec("C3 los cuatro turnos quedaron CLOSED", rows.every((r) => r.status === "CLOSED"));
  rec("C4 closing == expected en todos", rows.every((r) => money(r.closingAmount) === money(r.expectedAmount)));
  rec("C5 diferencia 0 registrada", rows.every((r) => money(r.difference) === "0.00"));
  eq("C6 los turnos de A y de B están en empresas distintas", rows.filter((r) => r.companyId === COMPANY_A).length, 3);

  /* ---------- Caja diaria por empresa (sin mezclar) ---------- */
  const dailyA = await prisma.cashboxDaily.findFirst({ where: { companyId: COMPANY_A, businessDate: bd(new Date()) } });
  const dailyB = await prisma.cashboxDaily.findFirst({ where: { companyId: COMPANY_B, businessDate: bd(new Date()) } });
  rec("D1 cada empresa tiene su propia caja diaria", Boolean(dailyA && dailyB && dailyA.id !== dailyB.id));
  const sumClosedA = rows.filter((r) => r.companyId === COMPANY_A).reduce((s, r) => s + Number(r.closingAmount), 0);
  eq("D2 la caja diaria de A suma sus 3 cierres", money(dailyA?.currentAmount), money(sumClosedA));
  eq("D3 la caja diaria de B sólo suma el cierre de B", money(dailyB?.currentAmount), "200.00");

  /* ---------- Ventas asociadas + idempotencia ---------- */
  const salesBySession = await prisma.sale.groupBy({ by: ["cashSessionId"], where: { companyId: COMPANY_A, cashSessionId: { in: [sA, sB, sC].filter(Boolean) } }, _count: { _all: true } });
  rec("I1 cada turno de A tiene exactamente su venta", salesBySession.every((g) => g._count._all === 1), JSON.stringify(salesBySession.map((g) => g._count._all)));

  const replayBody = saleOf({ sessionId: null, terminalId: T1, productId: PA, price: 250, clientRequestId: `f5-idem-${RUN}` });
  const openForRetry = await req("POST", "/cash/sessions/open", c1, { openingAmount: 0, terminalId: T1 });
  const retrySession = openForRetry.body?.shiftId;
  const first = await req("POST", "/sales", c1, { ...replayBody, originCashSessionId: retrySession });
  const replay = await req("POST", "/sales", c1, { ...replayBody, originCashSessionId: retrySession });
  rec("I2 primer envío aceptado", first.status === 201, `status=${first.status}`);
  eq("I3 reintento idéntico devuelve la MISMA venta", replay.body?.id, first.body?.id);
  eq("I4 sólo existe una fila para ese clientRequestId", await prisma.sale.count({ where: { clientRequestId: `f5-idem-${RUN}` } }), 1);

  // Sincronización offline tardía (ocurrida hace 2h en un turno abierto hace 3h)
  const lateOpenedAt = new Date(Date.now() - 3 * 3_600_000);
  const user1 = await prisma.user.findUnique({ where: { email: "cajero1.uat@fullpos.local" } });
  const lateShift = await prisma.cashSession.create({
    data: { companyId: COMPANY_A, openedByUserId: user1.id, userName: "Cajero Uno", openedAt: lateOpenedAt, initialAmount: 0, status: "OPEN", businessDate: bd(lateOpenedAt) },
  });
  const lateSale = await req("POST", "/sales", c1, saleOf({ sessionId: lateShift.id, terminalId: T1, productId: PA, price: 250, occurredAt: new Date(Date.now() - 2 * 3_600_000) }));
  rec("L1 sincronización offline tardía aceptada en su turno original", lateSale.status === 201, `status=${lateSale.status}`);
  eq("L2 conserva el turno original", lateSale.body?.cashSessionId, lateShift.id);

  /* ---------- Limpieza controlada (solo base UAT) ---------- */
  const s1 = await req("GET", "/cash/summary", c1);
  await req("POST", "/cash/sessions/close", c1, { sessionId: retrySession, closingAmount: Number(s1.body?.expectedCash) });
  const s2 = await req("GET", "/cash/summary", c1);
  await req("POST", "/cash/sessions/close", c1, { sessionId: lateShift.id, closingAmount: Number(s2.body?.expectedCash) });
  eq("Z1 no quedan turnos abiertos", await prisma.cashSession.count({ where: { status: "OPEN" } }), 0);

  const failed = results.filter((r) => !r.ok);
  console.log("\n===== RESUMEN FASE 5 =====");
  console.log(`Total: ${results.length} · OK: ${results.length - failed.length} · FALLOS: ${failed.length}`);
  for (const f of failed) console.log(`  - ${f.name} :: ${f.detail}`);
  process.exitCode = failed.length ? 1 : 0;
}

main()
  .catch((e) => { console.error("[fase5] ERROR FATAL", e); process.exitCode = 2; })
  .finally(async () => { await prisma.$disconnect(); });
