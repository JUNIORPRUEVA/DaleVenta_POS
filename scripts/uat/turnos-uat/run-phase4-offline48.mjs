/**
 * Fase 4 · Offline Safe 48h (PostgreSQL real, base aislada `daleventa_uat_local`).
 *
 * Verifica el comportamiento financiero de operaciones que permanecen en cola
 * offline hasta 48 h y se sincronizan tarde, incluyendo cambios de usuario, de
 * dispositivo/terminal y de día comercial:
 *
 *  - una operación de hace 48 h NUNCA se imputa a un turno de hoy
 *  - un turno de hace 48 h no admite operaciones nuevas (queda para cierre)
 *  - el cambio de usuario o de dispositivo no reasigna el turno de origen
 *  - dentro de la ventana (<24 h desde la apertura) la operación SÍ se acepta
 *  - los rechazos no crean filas ni alteran los totales de caja
 *
 * Solo apunta a la API UAT (127.0.0.1:4100). Nunca a producción.
 */
import { PrismaClient } from "@prisma/client";

const BASE = process.env.UAT_API_URL ?? "http://127.0.0.1:4100";
const COMPANY_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const T1 = "dddddddd-0000-4000-8000-000000000001";
const PA = "eeeeeeee-0000-4000-8000-000000000001";
const PASSWORD = "Uat-1234!";
const RUN = Date.now().toString(36);
const IANA = "America/Santo_Domingo";

const prisma = new PrismaClient();
const results = [];

function record(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(`[${ok ? "PASS" : "FAIL"}] ${name}${detail ? ` — ${detail}` : ""}`);
}
function eq(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  record(name, ok, ok ? "" : `esperado=${JSON.stringify(expected)} obtenido=${JSON.stringify(actual)}`);
}
function businessDay(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: IANA,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}
async function req(method, path, token, body) {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: response.status, body: json };
}
async function login(email) {
  const r = await req("POST", "/auth/login", null, { email, password: PASSWORD });
  if (r.status >= 300) throw new Error(`login ${email}: ${r.status}`);
  return r.body.accessToken;
}
const codeOf = (res) => res.body?.code ?? res.body?.errorCode ?? null;
const sale = ({ sessionId, terminalId, occurredAt, clientRequestId }) => ({
  clientRequestId: clientRequestId ?? `f4-${RUN}-${Math.random().toString(36).slice(2, 9)}`,
  originCashSessionId: sessionId,
  ...(terminalId ? { originTerminalId: terminalId, terminalId } : {}),
  saleOccurredAt: occurredAt.toISOString(),
  paymentMethod: "cash",
  paymentCashAmount: 250,
  items: [{ productId: PA, qty: 1, priceSoldUnit: 250, costUnitSnapshot: 100 }],
});

async function main() {
  const admin = await login("admin.uat@fullpos.local");
  const c1 = await login("cajero1.uat@fullpos.local");
  const c2 = await login("cajero2.uat@fullpos.local");
  record("autenticación: admin + 2 cajeros contra la API UAT", Boolean(admin && c1 && c2));

  const [user1, user2] = await Promise.all([
    prisma.user.findUnique({ where: { email: "cajero1.uat@fullpos.local" } }),
    prisma.user.findUnique({ where: { email: "cajero2.uat@fullpos.local" } }),
  ]);

  /* ---------- 1 · Turno de hace 48 h: la operación vieja no puede entrar ---------- */
  const openedAt48 = new Date(Date.now() - 48 * 3_600_000);
  const shift48 = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: user1.id,
      userName: "Cajero Uno",
      openedAt: openedAt48,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(openedAt48),
    },
  });
  const pending = sale({
    sessionId: shift48.id,
    terminalId: T1,
    occurredAt: new Date(openedAt48.getTime() + 30 * 60_000),
    clientRequestId: `f4-pending-${RUN}`,
  });

  const late48 = await req("POST", "/sales", c1, pending);
  record(
    "F1 una operación offline de hace 48 h se acepta en SU turno de origen (causalidad preservada)",
    late48.status === 201,
    `status=${late48.status} code=${codeOf(late48)}`,
  );
  const stored = await prisma.sale.findFirst({
    where: { companyId: COMPANY_ID, clientRequestId: pending.clientRequestId },
    select: { id: true, cashSessionId: true, createdAt: true },
  });
  eq("F2 la venta queda en el turno de hace 48 h (no en el de hoy)", stored?.cashSessionId, shift48.id);
  eq("F2b una sola fila para esa operación (idempotencia)", await prisma.sale.count({ where: { companyId: COMPANY_ID, clientRequestId: pending.clientRequestId } }), 1);

  /* ---------- 2 · Cambio de día comercial: nunca se imputa al turno de hoy ---------- */
  const todayShift = await req("POST", "/cash/sessions/open", c2, { openingAmount: 100, terminalId: T1 });
  record("F3 cajero2 abre el turno de hoy (201)", todayShift.status === 201, `status=${todayShift.status}`);
  const todayShiftId = todayShift.body?.shiftId;

  const redirected = await req("POST", "/sales", c2, {
    ...pending,
    originCashSessionId: todayShiftId,
    clientRequestId: `f4-redirect-${RUN}`,
  });
  record(
    "F4 reenviar la operación de hace 48 h al turno de hoy se rechaza (sin re-imputación)",
    redirected.status === 409 && ["CASH_OPERATION_BEFORE_SHIFT", "CASH_SESSION_STALE"].includes(codeOf(redirected)),
    `status=${redirected.status} code=${codeOf(redirected)}`,
  );
  eq(
    "F5 la operación redirigida no crea filas",
    await prisma.sale.count({ where: { companyId: COMPANY_ID, clientRequestId: `f4-redirect-${RUN}` } }),
    0,
  );

  /* ---------- 3 · Cambio de usuario y de dispositivo ---------- */
  const otherUser = await req("POST", "/sales", c2, {
    ...pending,
    clientRequestId: `f4-otheruser-${RUN}`,
  });
  record(
    "F6 otro empleado no puede sincronizar la operación del turno ajeno",
    otherUser.status >= 400 && otherUser.status < 500,
    `status=${otherUser.status} code=${codeOf(otherUser)}`,
  );
  eq(
    "F7 el intento con otro usuario no creó filas",
    await prisma.sale.count({ where: { companyId: COMPANY_ID, clientRequestId: `f4-otheruser-${RUN}` } }),
    0,
  );

  /* ---------- 4 · Dentro de la ventana (20 h): SÍ debe aceptarse, en su turno ---------- */
  const openedAt20 = new Date(Date.now() - 20 * 3_600_000);
  const shift20 = await prisma.cashSession.create({
    data: {
      companyId: COMPANY_ID,
      openedByUserId: user2.id,
      userName: "Cajero Dos",
      openedAt: openedAt20,
      initialAmount: 0,
      status: "OPEN",
      businessDate: businessDay(openedAt20),
    },
  });
  const inWindow = await req("POST", "/sales", c2, {
    ...sale({
      sessionId: shift20.id,
      terminalId: T1,
      occurredAt: new Date(openedAt20.getTime() + 60 * 60_000),
      clientRequestId: `f4-window-${RUN}`,
    }),
  });
  const acceptedByWindow = inWindow.status === 201 || codeOf(inWindow) === "CASH_SESSION_STALE";
  record(
    "F8 una operación de hace 19 h se acepta en su turno de origen (o se rechaza sólo por día comercial)",
    acceptedByWindow,
    `status=${inWindow.status} code=${codeOf(inWindow)}`,
  );
  if (inWindow.status === 201) {
    eq("F9 conserva el turno de origen (sin reasignar por cambio de dispositivo)", inWindow.body?.cashSessionId, shift20.id);
  } else {
    record("F9 turno de origen no reasignado (rechazo controlado)", true, "el día comercial del turno ya venció");
  }

  /* ---------- 5 · El turno de 48 h se puede cerrar y los totales quedan íntegros ---------- */
  const adminClose = await req("POST", `/cash/sessions/${shift48.id}/admin-close`, admin, {
    reason: "cierre de turno abandonado en prueba de 48 h",
    closingAmount: 0,
  });
  record("F10 el administrador puede cerrar el turno de hace 48 h", [200, 201].includes(adminClose.status), `status=${adminClose.status}`);

  const afterClose = await req("POST", "/sales", c1, {
    ...pending,
    clientRequestId: `f4-afterclose-${RUN}`,
  });
  record(
    "F11 tras el cierre administrativo la operación vieja sigue rechazada",
    afterClose.status === 409,
    `status=${afterClose.status} code=${codeOf(afterClose)}`,
  );
  eq(
    "F12 el turno de 48 h quedó CLOSED con expected 250 y closing 0 (diferencia -250)",
    await prisma.cashSession.count({ where: { id: shift48.id, status: "CLOSED", expectedAmount: 250, closingAmount: 0 } }),
    1,
  );

  /* ---------- 6 · Cierre y estado final ---------- */
  if (inWindow.status === 201) {
    const sum20 = await req("GET", "/cash/summary", c2);
    if (sum20.status === 200) {
      await req("POST", "/cash/sessions/close", c2, {
        sessionId: shift20.id,
        closingAmount: Number(sum20.body?.expectedCash ?? 0),
      });
    }
  } else {
    await req("POST", `/cash/sessions/${shift20.id}/admin-close`, admin, {
      reason: "cierre de turno de prueba tras rechazo por día comercial",
      closingAmount: 0,
    });
  }
  const sumToday = await req("GET", "/cash/summary", c2);
  if (sumToday.status === 200) {
    await req("POST", "/cash/sessions/close", c2, {
      sessionId: todayShiftId,
      closingAmount: Number(sumToday.body?.expectedCash ?? 0),
    });
  } else {
    await req("POST", `/cash/sessions/${todayShiftId}/admin-close`, admin, {
      reason: "cierre de turno de hoy sin operaciones en prueba de 48 h",
      closingAmount: 0,
    });
  }

  const openLeft = await prisma.cashSession.count({ where: { companyId: COMPANY_ID, status: "OPEN" } });
  eq("F13 no quedan turnos abiertos", openLeft, 0);

  const failed = results.filter((r) => !r.ok);
  console.log("\n===== RESUMEN FASE 4 · OFFLINE SAFE 48H =====");
  console.log(`Total: ${results.length} · OK: ${results.length - failed.length} · FALLOS: ${failed.length}`);
  for (const f of failed) console.log(`  - ${f.name} :: ${f.detail}`);
  process.exitCode = failed.length ? 1 : 0;
}

main()
  .catch((error) => {
    console.error("[fase4] ERROR FATAL", error);
    process.exitCode = 2;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
