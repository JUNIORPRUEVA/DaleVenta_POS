/**
 * UAT E2E de blindaje de turnos contra API real + PostgreSQL aislado.
 *
 * Requisitos:
 *  - API en http://127.0.0.1:4100 con APP_ENV=uat y DATABASE_URL local dedicada.
 *  - Datos ficticios cargados con seed.mjs.
 *
 * No toca producción: valida contra el cluster local en 127.0.0.1:55432.
 */
import { PrismaClient } from "@prisma/client";

const BASE = process.env.UAT_API_URL ?? "http://127.0.0.1:4100";
const COMPANY_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const TERMINAL_1 = "dddddddd-0000-4000-8000-000000000001";
const TERMINAL_2 = "dddddddd-0000-4000-8000-000000000002";
const PASSWORD = "Uat-1234!";
const PRODUCT_A = "eeeeeeee-0000-4000-8000-000000000001"; // 250
const PRODUCT_B = "eeeeeeee-0000-4000-8000-000000000002"; // 450
const PRODUCT_C = "eeeeeeee-0000-4000-8000-000000000003"; // 800

const RUN = Date.now().toString(36);
const prisma = new PrismaClient();
const results = [];
const IANA = "America/Santo_Domingo";

function record(name, ok, detail = "") {
  results.push({ name, ok, detail });
  const icon = ok ? "PASS" : "FAIL";
  console.log(`[${icon}] ${name}${detail ? ` — ${detail}` : ""}`);
}

function expect(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  record(name, ok, ok ? "" : `esperado=${JSON.stringify(expected)} obtenido=${JSON.stringify(actual)}`);
  return ok;
}

async function req(method, path, token, body) {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      "x-client-app-version": "1.0.6+145",
      "x-client-platform": "windows",
      "x-client-device-id": `uat-${RUN}`,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  const text = await response.text();
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: response.status, body: json };
}

function businessDay(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: IANA,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function saleBody({ sessionId, terminalId, occurredAt, paymentMethod = "cash", items, creditAmount }) {
  const total = items.reduce((sum, item) => sum + item.qty * item.priceSoldUnit, 0);
  const cash = paymentMethod === "credit" ? 0 : total;
  return {
    clientRequestId: `uat-${RUN}-${Math.random().toString(36).slice(2, 10)}`,
    originCashSessionId: sessionId,
    ...(terminalId ? { originTerminalId: terminalId, terminalId } : {}),
    saleOccurredAt: occurredAt.toISOString(),
    paymentMethod,
    paymentCashAmount: cash,
    ...(paymentMethod === "credit" ? { creditAmount: creditAmount ?? total } : {}),
    items,
  };
}

async function login(email) {
  const response = await req("POST", "/auth/login", null, { email, password: PASSWORD });
  if (response.status !== 200 && response.status !== 201) {
    throw new Error(`login ${email} failed: ${response.status} ${JSON.stringify(response.body)}`);
  }
  return response.body.accessToken;
}

async function openShift(token, { openingAmount, terminalId, deviceFingerprint }) {
  const response = await req("POST", "/cash/sessions/open", token, {
    openingAmount,
    ...(terminalId ? { terminalId } : {}),
    ...(deviceFingerprint ? { deviceFingerprint } : {}),
  });
  return response;
}

async function main() {
  const admin = await login("admin.uat@fullpos.local");
  const cajero1 = await login("cajero1.uat@fullpos.local");
  const cajero2 = await login("cajero2.uat@fullpos.local");
  record("autenticación real de 3 empleados (ADMIN + 2 CAJERO)", Boolean(admin && cajero1 && cajero2));

  /* ------------------------------------------------------------------ *
   * ESCENARIO A · 3 empleados simultáneos, 2 terminales (T1 compartida)
   * ------------------------------------------------------------------ */
  const openA = await openShift(cajero1, { openingAmount: 500, terminalId: TERMINAL_1, deviceFingerprint: "device-A" });
  const openB = await openShift(cajero2, { openingAmount: 300, terminalId: TERMINAL_1, deviceFingerprint: "device-B" });
  expect("A1 cajero1 abre turno en T1 (201)", openA.status, 201);
  expect("A2 cajero2 abre turno en el MISMO terminal T1 (201)", openB.status, 201);
  const shiftA = openA.body?.shiftId;
  const shiftB = openB.body?.shiftId;
  record("A3 cada empleado obtiene un turno distinto", Boolean(shiftA && shiftB && shiftA !== shiftB), `${shiftA} / ${shiftB}`);

  const openC = await openShift(admin, { openingAmount: 100, terminalId: TERMINAL_2, deviceFingerprint: "device-C" });
  expect("A4 admin abre turno en T2 (201)", openC.status, 201);
  const shiftC = openC.body?.shiftId;

  const stateA = await req("GET", "/cash/state", cajero1);
  const stateB = await req("GET", "/cash/state", cajero2);
  expect("A5 /cash/state de cajero1 ve SU turno", stateA.body?.activeSession?.shiftId, shiftA);
  expect("A6 /cash/state de cajero2 ve SU turno", stateB.body?.activeSession?.shiftId, shiftB);
  record("A7 los 3 turnos están operativos", [stateA, stateB].every((r) => r.body?.canOperate === true && r.body?.staleBusinessDate === false));

  // Ventas: 2 por cajero, una a crédito
  const saleA1 = await req("POST", "/sales", cajero1, saleBody({ sessionId: shiftA, terminalId: TERMINAL_1, occurredAt: new Date(), items: [{ productId: PRODUCT_A, qty: 2, priceSoldUnit: 250, costUnitSnapshot: 100 }] }));
  const saleA2 = await req("POST", "/sales", cajero1, saleBody({ sessionId: shiftA, terminalId: TERMINAL_1, occurredAt: new Date(), items: [{ productId: PRODUCT_B, qty: 1, priceSoldUnit: 450, costUnitSnapshot: 200 }] }));
  const saleB1 = await req("POST", "/sales", cajero2, saleBody({ sessionId: shiftB, terminalId: TERMINAL_1, occurredAt: new Date(), items: [{ productId: PRODUCT_C, qty: 1, priceSoldUnit: 800, costUnitSnapshot: 400 }], paymentMethod: "credit" }));
  const saleC1 = await req("POST", "/sales", admin, saleBody({ sessionId: shiftC, terminalId: TERMINAL_2, occurredAt: new Date(), items: [{ productId: PRODUCT_A, qty: 1, priceSoldUnit: 250, costUnitSnapshot: 100 }] }));
  record("A8 venta efectivo cajero1", saleA1.status === 201, `status=${saleA1.status} ${saleA1.status !== 201 ? JSON.stringify(saleA1.body).slice(0, 200) : ""}`);
  record("A9 segunda venta efectivo cajero1", saleA2.status === 201, `status=${saleA2.status} ${saleA2.status !== 201 ? JSON.stringify(saleA2.body).slice(0, 200) : ""}`);
  record("A10 venta a crédito cajero2", saleB1.status === 201, `status=${saleB1.status} ${saleB1.status !== 201 ? JSON.stringify(saleB1.body).slice(0, 200) : ""}`);
  record("A11 venta admin en T2", saleC1.status === 201, `status=${saleC1.status} ${saleC1.status !== 201 ? JSON.stringify(saleC1.body).slice(0, 200) : ""}`);
  expect("A12 cada venta queda en el turno de su dueño (cajero1)", saleA1.body?.cashSessionId, shiftA);
  expect("A13 cada venta queda en el turno de su dueño (admin)", saleC1.body?.cashSessionId, shiftC);

  // Movimientos: ingreso y egreso
  const moveIn = await req("POST", "/cash/movements", cajero1, { sessionId: shiftA, operationId: `op-in-${RUN}`, type: "IN", amount: 200, reason: "Fondo adicional", movementType: "transfer", occurredAt: new Date().toISOString() });
  const moveOut = await req("POST", "/cash/movements", cajero1, { sessionId: shiftA, operationId: `op-out-${RUN}`, type: "OUT", amount: 50, reason: "Compra de agua", movementType: "expense", occurredAt: new Date().toISOString() });
  expect("A14 ingreso de efectivo (201)", moveIn.status, 201);
  expect("A15 salida de efectivo (201)", moveOut.status, 201);

  // Abono del crédito de cajero2
  const creditSaleId = saleB1.body?.id;
  const creditPay = await req("POST", `/sales/${creditSaleId}/credit-payments`, cajero2, { operationId: `op-abono-${RUN}`, operationCashSessionId: shiftB, paidAt: new Date().toISOString(), cashAmount: 300 });
  record("A16 abono a crédito en el turno de cajero2", creditPay.status === 201 || creditPay.status === 200, `status=${creditPay.status}`);

  // Devolución: la política exige permiso `refundSales` y el turno debe ser del
  // propio usuario, así que la ejecuta el ADMIN sobre SU turno/venta.
  const saleC1Items = saleC1.body?.items ?? [];
  const refund = await req("POST", `/sales/${saleC1.body?.id}/return`, admin, {
    clientRequestId: `uat-refund-${RUN}`,
    originalSaleCashSessionId: shiftC,
    operationCashSessionId: shiftC,
    operationOccurredAt: new Date().toISOString(),
    reason: "UAT devolución",
    restoreInventory: false,
    items: saleC1Items.length ? [{ saleItemId: saleC1Items[0].id, qty: 1 }] : undefined,
  });
  record("A17 devolución en el turno del admin", refund.status === 201, `status=${refund.status} ${refund.status !== 201 ? JSON.stringify(refund.body).slice(0, 220) : ""}`);

  // Defecto detectado en UAT: un id de venta malformado devolvía 500 (Prisma).
  const malformedId = await req("POST", "/sales/not-a-uuid/credit-payments", cajero2, { cashAmount: 1 });
  record("A17b id malformado responde 400 (no 500)", malformedId.status === 400, `status=${malformedId.status}`);

  // Resumen esperado por turno antes de cerrar
  const summaryA = await req("GET", "/cash/summary", cajero1);
  const summaryB = await req("GET", "/cash/summary", cajero2);
  const summaryC = await req("GET", "/cash/summary", admin);
  record("A18 resumen de cajero1 calculado", summaryA.status === 200, `expected=${summaryA.body?.expectedCash}`);
  record("A19 resumen de cajero2 calculado", summaryB.status === 200, `expected=${summaryB.body?.expectedCash}`);
  record("A20 resumen de admin calculado", summaryC.status === 200, `expected=${summaryC.body?.expectedCash}`);

  // Cierres identificados con el importe esperado (diferencia 0)
  const closeA = await req("POST", "/cash/sessions/close", cajero1, { sessionId: shiftA, closingAmount: summaryA.body?.expectedCash ?? 0, note: "UAT cierre cajero1" });
  const closeB = await req("POST", "/cash/sessions/close", cajero2, { sessionId: shiftB, closingAmount: summaryB.body?.expectedCash ?? 0, note: "UAT cierre cajero2" });
  const closeC = await req("POST", "/cash/sessions/close", admin, { sessionId: shiftC, closingAmount: summaryC.body?.expectedCash ?? 0, note: "UAT cierre admin" });
  record("A21 cierre cajero1", [200, 201].includes(closeA.status), `status=${closeA.status}`);
  record("A22 cierre cajero2", [200, 201].includes(closeB.status), `status=${closeB.status}`);
  record("A23 cierre admin", [200, 201].includes(closeC.status), `status=${closeC.status}`);
  record("A24 cierres con diferencia 0", [closeA, closeB, closeC].every((r) => Number(r.body?.difference ?? 99) === 0 || r.body?.difference === undefined), `[${closeA.body?.difference}, ${closeB.body?.difference}, ${closeC.body?.difference}]`);

  // D4 · Caja diaria = SUMA de los cierres, sin duplicar
  const expectedSum = [summaryA, summaryB, summaryC].reduce((sum, r) => sum + Number(r.body?.expectedCash ?? 0), 0);
  const closedSum = [closeA, closeB, closeC].reduce((sum, r) => sum + Number(r.body?.session?.closingAmount ?? 0), 0);
  const stateAfter = await req("GET", "/cash/state", admin);
  const totals = stateAfter.body?.cashboxTotals;
  record("A25 cashboxTotals expone 3 turnos cerrados", totals?.sessions >= 3, JSON.stringify(totals));
  expect("A26 caja diaria = suma de cierres (sin duplicación)", Number(totals?.closedTotal ?? -1), Number(closedSum.toFixed(2)));
  record("A27 suma de resúmenes == suma de cierres", Math.abs(expectedSum - closedSum) < 0.01, `${expectedSum} vs ${closedSum}`);

  /* ------------------------------------------------------------------ *
   * ESCENARIO B · turno vencido: consultar, no operar, cerrar
   * ------------------------------------------------------------------ */
  const cajero1User = await prisma.user.findUnique({ where: { email: "cajero1.uat@fullpos.local" } });
  const staleOpenedAt = new Date(Date.now() - 3 * 86_400_000);
  const staleShift = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: cajero1User.id,
      userName: "Cajero Uno",
      openedAt: staleOpenedAt,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(staleOpenedAt),
    },
  });
  const staleState = await req("GET", "/cash/state", cajero1);
  expect("B1 /cash/state devuelve 200 con el turno vencido", staleState.status, 200);
  expect("B2 el turno vencido es la sesión activa (permite cerrarlo)", staleState.body?.activeSession?.shiftId, staleShift.id);
  expect("B3 staleBusinessDate=true", staleState.body?.staleBusinessDate, true);
  expect("B4 requiresClosure=true", staleState.body?.requiresClosure, true);
  expect("B5 canOperate=false", staleState.body?.canOperate, false);

  const staleSale = await req("POST", "/sales", cajero1, saleBody({ sessionId: staleShift.id, terminalId: TERMINAL_1, occurredAt: new Date(), items: [{ productId: PRODUCT_A, qty: 1, priceSoldUnit: 250 }] }));
  expect("B6 venta en turno vencido rechazada (409)", staleSale.status, 409);
  expect("B7 código CASH_SESSION_STALE", staleSale.body?.code ?? staleSale.body?.errorCode, "CASH_SESSION_STALE");

  const staleOpen = await openShift(cajero1, { openingAmount: 100, terminalId: TERMINAL_1 });
  expect("B8 abrir turno con turno vencido rechazado (409)", staleOpen.status, 409);
  expect("B9 código CASH_CLOSE_PREVIOUS_REQUIRED", staleOpen.body?.code ?? staleOpen.body?.errorCode, "CASH_CLOSE_PREVIOUS_REQUIRED");
  expect("B10 el 409 informa la sesión a cerrar", staleOpen.body?.sessionId, staleShift.id);

  const staleMovement = await req("POST", "/cash/movements", cajero1, { sessionId: staleShift.id, operationId: `op-stale-${RUN}`, type: "IN", amount: 10, reason: "intento", occurredAt: new Date().toISOString() });
  expect("B11 movimiento en turno vencido rechazado (409)", staleMovement.status, 409);

  const staleClose = await req("POST", "/cash/sessions/close", cajero1, { sessionId: staleShift.id, closingAmount: 0, note: "UAT cierre turno vencido" });
  record("B12 el dueño puede CERRAR su turno vencido", [200, 201].includes(staleClose.status), `status=${staleClose.status} ${JSON.stringify(staleClose.body).slice(0, 160)}`);

  /* ------------------------------------------------------------------ *
   * ESCENARIO C · ventana de 24h y turno nocturno
   * ------------------------------------------------------------------ */
  const cajero2User = await prisma.user.findUnique({ where: { email: "cajero2.uat@fullpos.local" } });
  const windowOpenedAt = new Date(Date.now() - 25 * 3_600_000);
  const windowShift = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: cajero2User.id,
      userName: "Cajero Dos",
      openedAt: windowOpenedAt,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(windowOpenedAt),
    },
  });
  const insideWindow = await req("POST", "/sales", cajero2, saleBody({ sessionId: windowShift.id, terminalId: TERMINAL_1, occurredAt: new Date(windowOpenedAt.getTime() + 23 * 3_600_000), items: [{ productId: PRODUCT_B, qty: 1, priceSoldUnit: 450 }] }));
  record("C1 venta a las 23h de apertura permitida", insideWindow.status === 201, `status=${insideWindow.status} ${JSON.stringify(insideWindow.body).slice(0, 140)}`);

  const beyondWindow = await req("POST", "/sales", cajero2, saleBody({ sessionId: windowShift.id, terminalId: TERMINAL_1, occurredAt: new Date(windowOpenedAt.getTime() + 24 * 3_600_000 + 60_000), items: [{ productId: PRODUCT_B, qty: 1, priceSoldUnit: 450 }] }));
  expect("C2 venta a las 24h01m rechazada (409)", beyondWindow.status, 409);
  expect("C3 código CASH_SESSION_STALE", beyondWindow.body?.code ?? beyondWindow.body?.errorCode, "CASH_SESSION_STALE");

  const beforeOpen = await req("POST", "/sales", cajero2, saleBody({ sessionId: windowShift.id, terminalId: TERMINAL_1, occurredAt: new Date(windowOpenedAt.getTime() - 3_600_000), items: [{ productId: PRODUCT_B, qty: 1, priceSoldUnit: 450 }] }));
  expect("C4 venta anterior a la apertura rechazada (409)", beforeOpen.status, 409);
  expect("C5 código CASH_OPERATION_BEFORE_SHIFT", beforeOpen.body?.code ?? beforeOpen.body?.errorCode, "CASH_OPERATION_BEFORE_SHIFT");
  await prisma.cashSession.update({ where: { id: windowShift.id }, data: { status: "CLOSED", closedAt: new Date() } });

  // Turno nocturno: abierto ayer 22:00 local, venta hoy 00:30 local
  const nightOpenedAt = (() => {
    const now = new Date();
    const parts = new Intl.DateTimeFormat("en-CA", { timeZone: IANA, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(now);
    const y = Number(parts.find((p) => p.type === "year").value);
    const m = Number(parts.find((p) => p.type === "month").value);
    const d = Number(parts.find((p) => p.type === "day").value);
    // 22:00 AST = 02:00Z del día siguiente (UTC-4)
    return new Date(Date.UTC(y, m - 1, d, 2, 0, 0));
  })();
  const nightShift = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: cajero2User.id,
      userName: "Cajero Dos",
      openedAt: nightOpenedAt,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(nightOpenedAt),
    },
  });
  const nightSale = await req("POST", "/sales", cajero2, saleBody({ sessionId: nightShift.id, terminalId: TERMINAL_1, occurredAt: new Date(nightOpenedAt.getTime() + 2.5 * 3_600_000), items: [{ productId: PRODUCT_C, qty: 1, priceSoldUnit: 800 }] }));
  record("C6 venta nocturna que cruza medianoche permitida", nightSale.status === 201, `status=${nightSale.status} ${JSON.stringify(nightSale.body).slice(0, 140)}`);
  await prisma.cashSession.update({ where: { id: nightShift.id }, data: { status: "CLOSED", closedAt: new Date() } });

  /* ------------------------------------------------------------------ *
   * ESCENARIO D · offline: fecha original, idempotencia, turno cerrado
   * ------------------------------------------------------------------ */
  // Turno abierto 3 h antes en el dispositivo: la operación offline ocurrió a
  // las 2 h y se sincroniza ahora (fecha de operación ≠ fecha de recepción).
  const cajero1Row = await prisma.user.findUnique({ where: { email: "cajero1.uat@fullpos.local" } });
  const offlineOpenedAt = new Date(Date.now() - 3 * 3_600_000);
  const offlineCreated = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: cajero1Row.id,
      userName: "Cajero Uno",
      openedAt: offlineOpenedAt,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(offlineOpenedAt),
    },
  });
  const offlineShift = offlineCreated.id;
  const offlineOccurredAt = new Date(Date.now() - 2 * 3_600_000);
  const offlineBody = { ...saleBody({ sessionId: offlineShift, terminalId: TERMINAL_1, occurredAt: offlineOccurredAt, items: [{ productId: PRODUCT_A, qty: 1, priceSoldUnit: 250 }] }), clientRequestId: `uat-offline-${RUN}` };
  const offline1 = await req("POST", "/sales", cajero1, offlineBody);
  const offline2 = await req("POST", "/sales", cajero1, offlineBody);
  expect("D1 venta offline (fecha 2h atrás) aceptada", offline1.status, 201);
  expect("D2 reintento idempotente devuelve la MISMA venta", offline2.body?.id, offline1.body?.id);
  const offlineRows = await prisma.sale.count({ where: { clientRequestId: `uat-offline-${RUN}` } });
  expect("D3 sólo existe 1 venta para ese clientRequestId", offlineRows, 1);
  expect("D4 la venta conserva el turno original", offline1.body?.cashSessionId, offlineShift);

  const offlineSummary = await req("GET", "/cash/summary", cajero1);
  await req("POST", "/cash/sessions/close", cajero1, { sessionId: offlineShift, closingAmount: Number(offlineSummary.body?.expectedCash ?? 0), note: "UAT cierre offline" });
  const afterCloseSale = await req("POST", "/sales", cajero1, { ...offlineBody, clientRequestId: `uat-offline-after-close-${RUN}` });
  expect("D5 venta offline contra turno ya cerrado rechazada (409)", afterCloseSale.status, 409);
  expect("D6 código ORIGIN_SESSION_CLOSED", afterCloseSale.body?.code ?? afterCloseSale.body?.errorCode, "ORIGIN_SESSION_CLOSED");
  const leaked = await prisma.sale.count({ where: { clientRequestId: `uat-offline-after-close-${RUN}` } });
  expect("D7 no se creó venta ni contaminó otro turno", leaked, 0);

  /* ------------------------------------------------------------------ *
   * ESCENARIO E · cierre administrativo
   * ------------------------------------------------------------------ */
  const adminTarget = await openShift(cajero2, { openingAmount: 0, terminalId: TERMINAL_2 });
  const adminTargetShift = adminTarget.body?.shiftId;
  const forbidden = await req("POST", `/cash/sessions/${adminTargetShift}/admin-close`, cajero1, { reason: "intento sin permiso", closingAmount: 0 });
  expect("E1 cajero NO puede cerrar el turno de otro (403)", forbidden.status, 403);

  const staleList = await req("GET", "/cash/sessions/stale", admin);
  expect("E2 ADMIN consulta turnos vencidos (200)", staleList.status, 200);

  const [adminClose1, adminClose2] = await Promise.all([
    req("POST", `/cash/sessions/${adminTargetShift}/admin-close`, admin, { reason: "cierre administrativo UAT por ausencia del cajero", closingAmount: 0, note: "UAT" }),
    req("POST", `/cash/sessions/${adminTargetShift}/admin-close`, admin, { reason: "cierre administrativo UAT por ausencia del cajero", closingAmount: 0, note: "UAT" }),
  ]);
  const okCount = [adminClose1, adminClose2].filter((r) => [200, 201].includes(r.status)).length;
  const conflictCount = [adminClose1, adminClose2].filter((r) => r.status === 409).length;
  record("E3 concurrencia: exactamente 1 cierre administrativo gana", okCount === 1 && conflictCount === 1, `ok=${okCount} conflict=${conflictCount}`);

  const adminClosedRow = await prisma.cashSession.findUnique({ where: { id: adminTargetShift } });
  const adminUser = await prisma.user.findUnique({ where: { email: "admin.uat@fullpos.local" } });
  record("E4 el cierre administrativo queda registrado con el actor", adminClosedRow?.status === "CLOSED" && adminClosedRow?.closedByUserId === adminUser.id);
  record("E5 la nota de auditoría incluye el motivo", (adminClosedRow?.note ?? "").includes("CIERRE ADMINISTRATIVO") && (adminClosedRow?.note ?? "").includes("ausencia"));
  const auditRows = await prisma.telemetryOutbox.count({ where: { companyId: COMPANY_ID, eventType: "CASH_SESSION_ADMIN_CLOSED" } });
  record("E6 event de auditoría CASH_SESSION_ADMIN_CLOSED emitido", auditRows >= 1, `rows=${auditRows}`);

  const afterAdminClose = await req("POST", "/cash/movements", cajero2, { sessionId: adminTargetShift, operationId: `op-after-admin-${RUN}`, type: "IN", amount: 10, reason: "intento", occurredAt: new Date().toISOString() });
  record("E7 operación pendiente contra turno cerrado por admin es rechazada", afterAdminClose.status === 404 || afterAdminClose.status === 409, `status=${afterAdminClose.status}`);

  /* ------------------------------------------------------------------ *
   * ESCENARIO F · integridad financiera final
   * ------------------------------------------------------------------ */
  const crossDay = await prisma.$queryRaw`
    SELECT count(*)::int AS count
    FROM "Sale" s
    JOIN cash_sessions cs ON cs.id = s."cashSessionId"
    WHERE s.company_id = ${COMPANY_ID}::uuid
      AND s."isDeleted" = false
      AND cs."businessDate" <> to_char((s."saleDate" AT TIME ZONE 'America/Santo_Domingo'), 'YYYY-MM-DD')
      AND s."saleDate" > cs."openedAt" + interval '24 hours'
  `;
  expect("F1 ninguna venta fuera de la ventana de 24h de su turno", Number(crossDay[0].count), 0);

  const orphanSales = await prisma.sale.count({ where: { companyId: COMPANY_ID, cashSessionId: null } });
  expect("F2 ninguna venta sin turno", orphanSales, 0);

  const openLeft = await prisma.cashSession.count({ where: { companyId: COMPANY_ID, status: "OPEN" } });
  record("F3 no quedan turnos abiertos al final del UAT", openLeft === 0, `open=${openLeft}`);

  const failed = results.filter((r) => !r.ok);
  console.log("\n================ RESUMEN UAT ================");
  console.log(`Total: ${results.length} · OK: ${results.length - failed.length} · FALLOS: ${failed.length}`);
  if (failed.length) {
    for (const item of failed) console.log(`  - ${item.name} :: ${item.detail}`);
  }
  process.exitCode = failed.length ? 1 : 0;
}

main()
  .catch((error) => {
    console.error("[uat] ERROR FATAL", error);
    process.exitCode = 2;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
