/**
 * Fase 8 · Conciliación de intentos de cobro — prueba de INTEGRACIÓN REAL.
 *
 * No usa mocks: API en ejecución contra PostgreSQL 17 UAT (`daleventa_uat_local`)
 * con JWT real. Comprueba contrato, aislamiento por empresa, idempotencia y la
 * clasificación de una venta anulada.
 *
 * Solo apunta a 127.0.0.1:4100 y a la base UAT.
 */
import { PrismaClient } from "@prisma/client";

const BASE = process.env.UAT_API_URL ?? "http://127.0.0.1:4100";
const PASSWORD = "Uat-1234!";
const COMPANY_A = "aaaaaaaa-0000-4000-8000-000000000001";
const COMPANY_B = "aaaaaaaa-0000-4000-8000-000000000002";
const TERMINAL_A = "dddddddd-0000-4000-8000-000000000001";
const PRODUCT_A = "eeeeeeee-0000-4000-8000-000000000001";
const PRODUCT_B = "eeeeeeee-0000-4000-8000-0000000000b1";
const RUN = Date.now().toString(36);

const prisma = new PrismaClient();

const results = [];
const record = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`[${ok ? "PASS" : "FAIL"}] ${name}${detail ? ` — ${detail}` : ""}`);
};

async function req(method, path, token, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  return { status: res.status, data };
}

async function login(email) {
  const r = await req("POST", "/auth/login", null, { email, password: PASSWORD });
  if (r.status >= 300) throw new Error(`login ${email}: ${r.status}`);
  return r.data?.accessToken ?? r.data?.access_token ?? r.data?.token;
}

const recon = (id, token, expected) =>
  req(
    "GET",
    `/sales/attempts/${encodeURIComponent(id)}/reconciliation${
      expected === undefined ? "" : `?expectedTotalSold=${expected}`
    }`,
    token,
  );

const salePayload = (requestId, productId, price) => ({
  clientRequestId: requestId,
  paymentMethod: "cash",
  paymentCashAmount: price,
  cashReceived: price,
  changeAmount: 0,
  expectedTotalSold: price,
  items: [{ productId, qty: 1, priceSoldUnit: price, costUnitSnapshot: price / 2 }],
});

(async () => {
  const cajeroA = await login("cajero1.uat@fullpos.local");
  const adminA = await login("admin.uat@fullpos.local");

  const opened = await req("POST", "/cash/sessions/open", cajeroA, {
    openingAmount: 500,
    terminalId: TERMINAL_A,
  });
  if (opened.status >= 300) {
    // puede haber un turno abierto de una corrida anterior: se reutiliza
    console.log(`(turno no abierto: ${opened.status}, se continúa)`);
  }

  const reqA = `p8-ok-${RUN}`;
  const created = await req("POST", "/sales", cajeroA, salePayload(reqA, PRODUCT_A, 250));
  record("venta de prueba creada", created.status === 201, `status=${created.status}`);
  const saleId = created.data?.id;

  const confirmed = await recon(reqA, cajeroA, "250.00");
  record(
    "CONFIRMED sobre la venta registrada",
    confirmed.status === 200 &&
      confirmed.data?.status === "CONFIRMED" &&
      confirmed.data?.guidance === "ALREADY_REGISTERED",
    `status=${confirmed.status} body=${confirmed.data?.status}/${confirmed.data?.guidance}`,
  );
  record(
    "nunca autoriza repetir el cobro",
    confirmed.data?.retryAllowed === false &&
      confirmed.data?.assertsPaymentReceived === false,
    `retryAllowed=${confirmed.data?.retryAllowed} assertsPaymentReceived=${confirmed.data?.assertsPaymentReceived}`,
  );
  record(
    "vincula el intento con la venta real",
    confirmed.data?.sale?.id === saleId,
    `saleId=${confirmed.data?.sale?.id}`,
  );
  record(
    "el importe coincide con lo esperado",
    confirmed.data?.matchesExpected === true,
    `esperado=${confirmed.data?.expectedTotalSold} registrado=${confirmed.data?.recordedTotalSold}`,
  );

  const random = `no-existe-${RUN}`;
  const notFound = await recon(random, cajeroA);
  record(
    "NOT_FOUND para un identificador sin registro",
    notFound.data?.status === "NOT_FOUND" &&
      notFound.data?.sale === null &&
      notFound.data?.retryAllowed === false,
    `status=${notFound.data?.status}`,
  );

  const replay = await req("POST", "/sales", cajeroA, salePayload(reqA, PRODUCT_A, 250));
  const rows = await prisma.sale.count({
    where: { companyId: COMPANY_A, clientRequestId: reqA },
  });
  record(
    "reenviar el mismo clientRequestId no duplica",
    replay.status < 300 && replay.data?.id === saleId && rows === 1,
    `replay=${replay.status} filas=${rows}`,
  );

  const userB = await prisma.user.findFirst({
    where: { companyId: COMPANY_B },
    select: { id: true },
  });
  if (!userB) {
    record("venta de empresa B para probar aislamiento", false, "no hay usuario en la empresa B");
  } else {
    await prisma.sale.create({
      data: {
        companyId: COMPANY_B,
        userId: userB.id,
        saleDate: new Date(),
        paymentMethod: "cash",
        totalSold: 99,
        totalCost: 0,
        totalProfit: 0,
        commissionAmount: 0,
        paymentCashAmount: 99,
        status: "PAID",
        kind: "invoice",
        clientRequestId: `p8-b-${RUN}`,
      },
    });
    const crossTenant = await recon(`p8-b-${RUN}`, cajeroA);
    record(
      "no se puede consultar un intento de otra empresa",
      crossTenant.data?.status === "NOT_FOUND" && crossTenant.data?.sale === null,
      `status=${crossTenant.data?.status}`,
    );
  }

  const cancelled = await req("DELETE", `/sales/${saleId}`, adminA);
  const afterCancel = await recon(reqA, cajeroA);
  record(
    "anular después de registrar NO se reporta como rechazo",
    cancelled.status < 300 &&
      afterCancel.data?.status === "CONFIRMED" &&
      afterCancel.data?.voided === true &&
      afterCancel.data?.guidance === "REGISTERED_THEN_VOIDED",
    `cancel=${cancelled.status} recon=${afterCancel.data?.status}/${afterCancel.data?.guidance} voided=${afterCancel.data?.voided}`,
  );

  const anon = await req(
    "GET",
    `/sales/attempts/${encodeURIComponent(reqA)}/reconciliation`,
    null,
  );
  record("sin token responde 401", anon.status === 401, `status=${anon.status}`);

  // Límite de consultas: un sondeo masivo debe cortarse con 429 y no escribir
  // nada. El intento sigue intacto después del corte.
  let sawTooMany = false;
  let attemptsUsed = 0;
  for (let i = 0; i < 80 && !sawTooMany; i += 1) {
    attemptsUsed += 1;
    const burst = await recon(random, cajeroA);
    if (burst.status === 429) sawTooMany = true;
  }
  record(
    "el sondeo masivo se corta con 429",
    sawTooMany,
    `peticiones hasta el corte=${attemptsUsed}`,
  );
  const afterLimit = await recon(reqA, adminA);
  record(
    "otro usuario de la empresa sigue pudiendo verificar",
    afterLimit.status === 200 && afterLimit.data?.status === "CONFIRMED",
    `status=${afterLimit.status} recon=${afterLimit.data?.status}`,
  );

  await prisma.$disconnect();
  const failed = results.filter((r) => !r.ok);
  console.log("\n===== RESUMEN FASE 8 · CONCILIACIÓN (PostgreSQL real) =====");
  console.log(`Total: ${results.length} · OK: ${results.length - failed.length} · FALLOS: ${failed.length}`);
  for (const f of failed) console.log(`  - ${f.name} :: ${f.detail}`);
  process.exit(failed.length === 0 ? 0 : 1);
})().catch(async (e) => {
  console.error("FALLO " + (e?.message ?? e));
  await prisma.$disconnect();
  process.exit(1);
});
