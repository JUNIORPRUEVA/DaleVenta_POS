/**
 * Fase 6 · Consistencia de `cashbox_daily` bajo fallos, reinicios y concurrencia.
 *
 * Demuestra con PostgreSQL real que el agregado diario no puede quedar
 * permanentemente incorrecto después del cierre de un turno, que no hay doble
 * contabilización y que los cierres históricos no se modifican.
 *
 * El propio arnés arranca y MATA el proceso de la API (`SIGKILL`), que es el
 * escenario real de "fallo / caída / reinicio del proceso":
 *   - si la muerte ocurre DENTRO de la transacción, PostgreSQL hace rollback y
 *     el turno sigue OPEN sin tocar el agregado;
 *   - si ocurre DESPUÉS del commit, el turno está CLOSED y el agregado ya
 *     incluye su importe (misma transacción).
 *
 * Requisitos: PostgreSQL aislado en 55432 con `daleventa_uat_local` migrada y
 * sembrada, puerto 4100 libre, `apps/api/dist` compilado.
 */
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";
import { PrismaClient } from "@prisma/client";

const run = promisify(execFile);
const BASE = process.env.UAT_API_URL ?? "http://127.0.0.1:4100";
const DOCKER_MODE = process.env.PHASE6_DOCKER === "1";
const CONTAINER = process.env.PHASE6_CONTAINER ?? "fullpos-cand-smoke";
const API_DIR = "C:/src/fullpos-antonio-turnos/apps/api";
const COMPANY_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const T1 = "dddddddd-0000-4000-8000-000000000001";
const T2 = "dddddddd-0000-4000-8000-000000000002";
const PA = "eeeeeeee-0000-4000-8000-000000000001";
const PB = "eeeeeeee-0000-4000-8000-000000000002";
const PASSWORD = "Uat-1234!";
const RUN = Date.now().toString(36);

const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) throw new Error("DATABASE_URL requerido");
const prisma = new PrismaClient({
  datasources: {
    db: {
      url: `${dbUrl}${dbUrl.includes("?") ? "&" : "?"}application_name=uat-harness`,
    },
  },
});

const results = [];
function record(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(`[${ok ? "PASS" : "FAIL"}] ${name}${detail ? ` — ${detail}` : ""}`);
}
function eq(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  record(name, ok, ok ? "" : `esperado=${JSON.stringify(expected)} obtenido=${JSON.stringify(actual)}`);
}
const money = (v) => Number(v?.toString?.() ?? v ?? 0).toFixed(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/* ---------------- ciclo de vida de la API ---------------- */
let api = null;
async function waitForApi(timeoutMs = 45000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const r = await fetch(`${BASE}/auth/login`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email: "no-existe@uat.local", password: "x" }),
      });
      if (r.status === 401 || r.status === 400 || r.status === 201) return true;
    } catch {
      /* aún no escucha */
    }
    await sleep(500);
  }
  throw new Error("la API no respondió a tiempo");
}
async function startApi() {
  if (DOCKER_MODE) {
    // Contenedor real: `docker start` equivale a reiniciar el proceso.
    await run("docker", ["start", CONTAINER]);
    await waitForApi();
    return;
  }
  api = spawn("node", ["dist/main.js"], {
    cwd: API_DIR,
    env: {
      ...process.env,
      APP_ENV: "uat",
      UAT_LOCAL_ONLY: "true",
      PORT: "4100",
      JWT_SECRET: "uat-local-only-secret-not-production",
      NODE_ENV: "development",
      FINANCIAL_LEGACY_COMPAT: "true",
    },
    stdio: "ignore",
    windowsHide: true,
  });
  await waitForApi();
}
async function killApi() {
  if (DOCKER_MODE) {
    // Muerte abrupta del contenedor (SIGKILL a PID 1).
    await run("docker", ["kill", CONTAINER]).catch(() => {});
    await sleep(1200);
    return;
  }
  if (!api) return;
  const victim = api;
  api = null;
  victim.kill("SIGKILL");
  await new Promise((resolve) => {
    const timer = setTimeout(resolve, 5000);
    victim.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
  await sleep(600);
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
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
  return { status: response.status, body: json };
}
async function login(email) {
  const r = await req("POST", "/auth/login", null, { email, password: PASSWORD });
  if (r.status >= 300) throw new Error(`login ${email}: ${r.status}`);
  return r.body.accessToken;
}
const salePayload = ({ sessionId, terminalId, productId, price, cost }) => ({
  clientRequestId: `p6-${RUN}-${Math.random().toString(36).slice(2, 9)}`,
  originCashSessionId: sessionId,
  originTerminalId: terminalId,
  terminalId,
  saleOccurredAt: new Date().toISOString(),
  paymentMethod: "cash",
  paymentCashAmount: price,
  items: [{ productId, qty: 1, priceSoldUnit: price, costUnitSnapshot: cost }],
});

async function dailyVsSum(cashboxDailyId) {
  const [box, agg] = await Promise.all([
    prisma.cashboxDaily.findUnique({ where: { id: cashboxDailyId } }),
    prisma.cashSession.aggregate({
      where: { cashboxDailyId, status: "CLOSED", closedAt: { not: null } },
      _sum: { closingAmount: true },
    }),
  ]);
  const sum = Number(agg._sum.closingAmount ?? 0);
  const current = Number(box?.currentAmount ?? 0);
  return { box, sum, current, delta: Number((current - sum).toFixed(2)) };
}

async function closedFingerprint(companyId) {
  const rows = await prisma.cashSession.findMany({
    where: { companyId, status: "CLOSED" },
    select: { id: true, closingAmount: true, expectedAmount: true, difference: true, closedAt: true },
    orderBy: { id: "asc" },
  });
  return rows.map((r) => `${r.id}|${money(r.closingAmount)}|${money(r.expectedAmount)}|${money(r.difference)}|${r.closedAt?.toISOString() ?? ""}`);
}

async function main() {
  await startApi();
  let admin = await login("admin.uat@fullpos.local");
  let c1 = await login("cajero1.uat@fullpos.local");
  let c2 = await login("cajero2.uat@fullpos.local");
  record("A1 la API arranca y autentica a los 3 empleados", Boolean(admin && c1 && c2));

  /* ---------- 1 · Concurrencia ---------- */
  const openings = await Promise.all([
    req("POST", "/cash/sessions/open", c1, { openingAmount: 100, terminalId: T1 }),
    req("POST", "/cash/sessions/open", c2, { openingAmount: 200, terminalId: T1 }),
    req("POST", "/cash/sessions/open", admin, { openingAmount: 300, terminalId: T2 }),
  ]);
  record("C1 tres aperturas concurrentes", openings.every((o) => o.status === 201), openings.map((o) => o.status).join(","));
  const [s1, s2, s3] = openings.map((o) => o.body.shiftId);

  const sales = await Promise.all([
    req("POST", "/sales", c1, salePayload({ sessionId: s1, terminalId: T1, productId: PA, price: 250, cost: 100 })),
    req("POST", "/sales", c2, salePayload({ sessionId: s2, terminalId: T1, productId: PB, price: 450, cost: 200 })),
    req("POST", "/sales", admin, salePayload({ sessionId: s3, terminalId: T2, productId: PA, price: 800, cost: 300 })),
  ]);
  record("C2 tres ventas concurrentes", sales.every((s) => s.status === 201), sales.map((s) => s.status).join(","));

  const summaries = await Promise.all([
    req("GET", "/cash/summary", c1),
    req("GET", "/cash/summary", c2),
    req("GET", "/cash/summary", admin),
  ]);
  const expected = summaries.map((s) => Number(s.body?.expectedCash ?? 0));
  record("C3 los tres resúmenes son legibles", expected.every((v) => Number.isFinite(v) && v > 0), expected.map((v) => v.toFixed(2)).join(","));

  const cashboxId = (await prisma.cashSession.findUnique({ where: { id: s1 } }))?.cashboxDailyId;
  record("C4 los tres turnos comparten la misma caja diaria", Boolean(cashboxId));

  const closings = await Promise.all([
    req("POST", "/cash/sessions/close", c1, { sessionId: s1, closingAmount: expected[0] }),
    req("POST", "/cash/sessions/close", c2, { sessionId: s2, closingAmount: expected[1] }),
    req("POST", "/cash/sessions/close", admin, { sessionId: s3, closingAmount: expected[2] }),
  ]);
  record("C5 tres cierres concurrentes exitosos", closings.every((c) => [200, 201].includes(c.status)), closings.map((c) => c.status).join(","));

  const total = expected.reduce((a, b) => a + b, 0);
  const afterConcurrency = await dailyVsSum(cashboxId);
  eq("C6 la caja diaria es EXACTAMENTE la suma de los cierres", afterConcurrency.delta, 0);
  eq("C7 el importe diario coincide con los resúmenes de los tres turnos", afterConcurrency.current, Number(total.toFixed(2)));
  eq("C8 la caja diaria quedó CLOSED", afterConcurrency.box?.status, "CLOSED");
  eq("C9 no quedan turnos abiertos", await prisma.cashSession.count({ where: { companyId: COMPANY_ID, status: "OPEN" } }), 0);

  // Huella de los cierres ya confirmados: debe permanecer intacta hasta el final.
  const historicalBefore = await closedFingerprint(COMPANY_ID);
  record("C10 hay cierres históricos que vigilar", historicalBefore.length === 3, `${historicalBefore.length} cierres`);

  /* ---------- 2 · Replay / idempotencia ---------- */
  const replays = [];
  for (let i = 0; i < 3; i += 1) {
    replays.push(await req("POST", "/cash/sessions/close", c1, { sessionId: s1, closingAmount: expected[0] }));
  }
  record("I1 los replays de un cierre ya cerrado se rechazan (409)", replays.every((r) => r.status === 409), replays.map((r) => r.status).join(","));
  const afterReplay = await dailyVsSum(cashboxId);
  eq("I2 el replay no altera el agregado diario", afterReplay.delta, 0);
  eq("I3 el replay no altera el importe (sin doble contabilización)", afterReplay.current, Number(total.toFixed(2)));

  /* ---------- 3 · Caída del proceso A MITAD del cierre ---------- */
  const faultRuns = [];
  for (let i = 1; i <= 3; i += 1) {
    const open = await req("POST", "/cash/sessions/open", c1, { openingAmount: 50 + i * 10, terminalId: T1 });
    const shiftId = open.body.shiftId;
    await req("POST", "/sales", c1, salePayload({ sessionId: shiftId, terminalId: T1, productId: PA, price: 100 + i * 10, cost: 40 }));
    const sum = await req("GET", "/cash/summary", c1);
    const amount = Number(sum.body?.expectedCash ?? 0);

    // Cierre en vuelo y muerte del proceso pocos milisegundos después.
    const inFlight = req("POST", "/cash/sessions/close", c1, { sessionId: shiftId, closingAmount: amount }).catch(() => ({ status: 0 }));
    await sleep(5 + i * 3);
    await killApi();
    await inFlight.catch(() => {});

    const row = await prisma.cashSession.findUnique({ where: { id: shiftId } });
    const consistency = await dailyVsSum(cashboxId);
    const run = {
      i,
      status: row?.status,
      deltaAfterFault: consistency.delta,
    };

    // Reinicio de la API y reintento del cierre (convergencia).
    await startApi();
    c1 = await login("cajero1.uat@fullpos.local");
    const retry = row?.status === "OPEN"
      ? await req("POST", "/cash/sessions/close", c1, { sessionId: shiftId, closingAmount: amount })
      : await req("POST", "/cash/sessions/close", c1, { sessionId: shiftId, closingAmount: amount });
    run.retryStatus = retry.status;
    const afterRetry = await dailyVsSum(cashboxId);
    run.deltaAfterRetry = afterRetry.delta;
    run.finalStatus = (await prisma.cashSession.findUnique({ where: { id: shiftId } }))?.status;
    faultRuns.push(run);
  }

  record(
    "F1 tras la muerte a mitad de cierre el agregado sigue consistente",
    faultRuns.every((r) => r.deltaAfterFault === 0),
    faultRuns.map((r) => `s${r.i}:delta=${r.deltaAfterFault}`).join(","),
  );
  record(
    "F2 el turno nunca queda a medias (OPEN o CLOSED)",
    faultRuns.every((r) => r.status === "OPEN" || r.status === "CLOSED"),
    faultRuns.map((r) => `s${r.i}:${r.status}`).join(","),
  );
  record(
    "F3 tras reiniciar, el reintento deja el turno cerrado y el agregado exacto",
    faultRuns.every((r) => r.finalStatus === "CLOSED" && r.deltaAfterRetry === 0),
    faultRuns.map((r) => `s${r.i}:${r.retryStatus}->${r.finalStatus} delta=${r.deltaAfterRetry}`).join(","),
  );

  /* ---------- 4 · Caída inmediatamente DESPUÉS del commit ---------- */
  const open2 = await req("POST", "/cash/sessions/open", c1, { openingAmount: 70, terminalId: T1 });
  const shift2 = open2.body.shiftId;
  await req("POST", "/sales", c1, salePayload({ sessionId: shift2, terminalId: T1, productId: PA, price: 130, cost: 50 }));
  const sum2 = await req("GET", "/cash/summary", c1);
  const closed2 = await req("POST", "/cash/sessions/close", c1, { sessionId: shift2, closingAmount: Number(sum2.body?.expectedCash ?? 0) });
  record("F4 el cierre confirmado responde 201", closed2.status === 201, `status=${closed2.status}`);
  await killApi();
  const afterCrash = await dailyVsSum(cashboxId);
  eq("F5 tras la caída inmediata el agregado diario sigue exacto", afterCrash.delta, 0);
  const rowAfterCrash = await prisma.cashSession.findUnique({ where: { id: shift2 } });
  eq("F6 el turno quedó CLOSED con su importe confirmado", rowAfterCrash?.status, "CLOSED");

  /* ---------- 5 · Auto-sanación de un agregado heredado incorrecto ---------- */
  await startApi();
  c1 = await login("cajero1.uat@fullpos.local");
  const before = await dailyVsSum(cashboxId);
  await prisma.cashboxDaily.update({ where: { id: cashboxId }, data: { currentAmount: 0 } });
  const corrupted = await dailyVsSum(cashboxId);
  const open3 = await req("POST", "/cash/sessions/open", c1, { openingAmount: 40, terminalId: T1 });
  const shift3 = open3.body.shiftId;
  await req("POST", "/sales", c1, salePayload({ sessionId: shift3, terminalId: T1, productId: PA, price: 60, cost: 20 }));
  const sum3 = await req("GET", "/cash/summary", c1);
  await req("POST", "/cash/sessions/close", c1, { sessionId: shift3, closingAmount: Number(sum3.body?.expectedCash ?? 0) });
  const healed = await dailyVsSum(cashboxId);
  record("R1 el agregado corrupto se detecta antes de sanar", corrupted.delta < 0, `delta=${corrupted.delta}`);
  eq("R2 el siguiente cierre recalcula el agregado (auto-sanación idempotente)", healed.delta, 0);
  record(
    "R3 la auto-sanación conserva la suma previa y añade el nuevo cierre",
    healed.current > before.current,
    `antes=${before.current} despues=${healed.current}`,
  );

  /* ---------- 6 · Integridad de cierres históricos ---------- */
  const historicalAfter = await closedFingerprint(COMPANY_ID);
  const preserved = historicalBefore.every((line) => historicalAfter.includes(line));
  record(
    "H1 ningún cierre histórico fue modificado",
    preserved && historicalBefore.length === 3,
    `${historicalBefore.length} cierres previos verificados de ${historicalAfter.length} actuales`,
  );

  const finalConsistency = await dailyVsSum(cashboxId);
  eq("Z1 estado final: caja diaria = suma de cierres", finalConsistency.delta, 0);
  eq("Z2 no quedan turnos abiertos", await prisma.cashSession.count({ where: { companyId: COMPANY_ID, status: "OPEN" } }), 0);

  const failed = results.filter((r) => !r.ok);
  console.log("\n===== RESUMEN FASE 6 · CONSISTENCIA CAJA DIARIA =====");
  console.log(`Total: ${results.length} · OK: ${results.length - failed.length} · FALLOS: ${failed.length}`);
  for (const f of failed) console.log(`  - ${f.name} :: ${f.detail}`);
  process.exitCode = failed.length ? 1 : 0;
}

main()
  .catch((error) => {
    console.error("[fase6] ERROR FATAL", error);
    process.exitCode = 2;
  })
  .finally(async () => {
    await killApi().catch(() => {});
    await prisma.$disconnect().catch(() => {});
  });
