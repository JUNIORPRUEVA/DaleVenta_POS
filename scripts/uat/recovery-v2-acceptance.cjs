#!/usr/bin/env node
/**
 * UAT de aceptación — Motor de recuperación v2 y obligaciones de conciliación.
 *
 * Habla con una API real (UAT aislado) por HTTP y comprueba el comportamiento
 * observable. No toca producción y no imprime tokens ni contraseñas.
 *
 * Contrato que vigila:
 *  - UNA sola obligación ACTIVA por operación (varios encargados o dispositivos
 *    NO duplican el importe pendiente).
 *  - Cada declaración o rectificación queda auditada (actor, importe anterior y
 *    nuevo, nota).
 *  - Cambiar el importe exige rol administrativo.
 *  - Declarar NUNCA crea ventas, pagos, caja ni inventario.
 *
 * Uso:
 *   node scripts/uat/recovery-v2-acceptance.cjs
 *   UAT_API_BASE=http://127.0.0.1:4010 node scripts/uat/recovery-v2-acceptance.cjs
 */
const { randomUUID } = require('node:crypto');

const BASE = (process.env.UAT_API_BASE || 'http://127.0.0.1:4010').replace(/\/+$/, '');
const RUN = randomUUID().slice(0, 8);

const results = [];
function record(id, title, status, evidence) {
  results.push({ id, title, status, evidence });
  const icon = status === 'PASS' ? 'PASS' : status === 'FAIL' ? 'FAIL' : 'N/E ';
  console.log(`[${icon}] ${id} · ${title}`);
  if (evidence) console.log(`        ${evidence}`);
}

async function call(method, path, { token, body, timeoutMs = 15000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${BASE}${path}`, {
      method,
      headers: {
        ...(body ? { 'content-type': 'application/json' } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = { raw: text.slice(0, 300) };
    }
    return { status: res.status, json };
  } finally {
    clearTimeout(timer);
  }
}

function describe(value) {
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  return text && text.length > 240 ? `${text.slice(0, 240)}…` : text;
}

function tokenOf(payload) {
  return (
    payload?.accessToken ??
    payload?.access_token ??
    payload?.token ??
    null
  );
}

async function registerBusiness(label) {
  const email = `uat.${RUN}.${label}@daleventa.local`;
  const password = `Uat-${randomUUID().slice(0, 18)}!`;
  const res = await call('POST', '/auth/register-business', {
    body: {
      firstName: 'UAT',
      lastName: label.toUpperCase(),
      email,
      phone: '8090000000',
      password,
      confirmPassword: password,
      commercialName: `UAT Recovery ${RUN} ${label}`,
      taxId: '00000000000',
      country: 'DO',
      city: 'Santo Domingo',
      currency: 'DOP',
    },
  });
  const login = await call('POST', '/auth/login', {
    body: { identifier: email, password },
  });
  return { email, password, res, login, token: tokenOf(login.json) ?? tokenOf(res.json) };
}

async function loginAs(email, password) {
  const res = await call('POST', '/auth/login', {
    body: { identifier: email, password },
  });
  return { status: res.status, token: tokenOf(res.json) };
}

async function main() {
  console.log(`\nUAT Recovery v2 · API ${BASE} · run ${RUN}\n`);

  // ---------------------------------------------------------------- setup
  const owner = await registerBusiness('a');
  if (owner.res.status >= 400 || !owner.token) {
    record('ENV-01', 'Alta de empresa sintética A + login (ADMIN)', 'FAIL',
      `register=${owner.res.status} login=${owner.login.status} ${describe(owner.login.json)}`);
    console.log(JSON.stringify({ results, run: RUN }, null, 2));
    process.exit(1);
  }
  record('ENV-01', 'Alta de empresa sintética A + login (ADMIN)', 'PASS', `HTTP ${owner.res.status}`);

  const other = await registerBusiness('b');
  if (!other.token) {
    record('ENV-02', 'Alta de empresa sintética B + login', 'FAIL', describe(other.login.json));
    console.log(JSON.stringify({ results, run: RUN }, null, 2));
    process.exit(1);
  }
  record('ENV-02', 'Alta de empresa sintética B + login', 'PASS', `HTTP ${other.res.status}`);

  const tokenA = owner.token;
  const tokenB = other.token;

  // Cajero de la MISMA empresa (para probar la autorización de rectificación).
  const cashierEmail = `uat.${RUN}.cajero@daleventa.local`;
  const cashierPassword = `Uat-${randomUUID().slice(0, 18)}!`;
  const createdCashier = await call('POST', '/users', {
    token: tokenA,
    body: {
      email: cashierEmail,
      password: cashierPassword,
      nombreCompleto: 'Cajero UAT',
      telefono: '8090000002',
      edad: 30,
      numeroFlota: '9001',
      role: 'CAJERO',
    },
  });
  const cashierLogin = await loginAs(cashierEmail, cashierPassword);
  record(
    'ENV-03',
    'Cajero sintético de la MISMA empresa creado y autenticado',
    createdCashier.status < 400 && Boolean(cashierLogin.token) ? 'PASS' : 'FAIL',
    `crear=${createdCashier.status} login=${cashierLogin.status} ${cashierLogin.token ? '' : describe(createdCashier.json)}`,
  );
  const tokenCashier = cashierLogin.token;

  // ------------------------------------------------- 1) declaración base
  const declaredAt = new Date('2026-10-27T20:39:00.000Z').toISOString();
  const baseBody = {
    totalDeclared: 50,
    declaredAtUtc: declaredAt,
    paymentMethod: 'cash',
    declaredByRole: 'ADMIN',
    note: 'UAT: cliente pagó en efectivo, no salió ticket',
  };
  const requestId = `uat-decl-${RUN}-1`;

  const created = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: baseBody,
  });
  const obligation = created.json?.obligation;
  record(
    'DECL-01',
    'Declaración crea UNA obligación PENDING (sin retryAllowed ni pago declarado)',
    created.status === 201 &&
      obligation?.status === 'PENDING' &&
      obligation?.totalDeclared === 50 &&
      obligation?.retryAllowed === false &&
      obligation?.assertsPaymentReceived === false &&
      obligation?.declarationCount === 1 &&
      obligation?.version === 1
      ? 'PASS'
      : 'FAIL',
    `HTTP ${created.status} id=${obligation?.id ?? '-'} count=${obligation?.declarationCount} ` +
      `version=${obligation?.version} retryAllowed=${obligation?.retryAllowed}`,
  );

  // ------------------------------------------------ 2) idempotencia exacta
  const again = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: baseBody,
  });
  record(
    'DECL-02',
    'Reenvío idéntico devuelve la MISMA obligación (duplicate:true) sin evento nuevo',
    again.status === 201 &&
      again.json?.duplicate === true &&
      again.json?.obligation?.id === obligation?.id &&
      again.json?.obligation?.declarationCount === 1
      ? 'PASS'
      : 'FAIL',
    `HTTP ${again.status} duplicate=${again.json?.duplicate} count=${again.json?.obligation?.declarationCount}`,
  );

  // --------------------------- 3) otra persona, MISMO importe → 1 obligación
  const sameAmount = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenCashier,
    body: { ...baseBody, note: 'UAT: el cajero confirma el mismo monto' },
  });
  record(
    'DEV-01',
    'Dos encargados declaran el MISMO importe: sigue habiendo UNA obligación',
    sameAmount.status === 201 &&
      sameAmount.json?.duplicate === false &&
      sameAmount.json?.amendment === 'AMENDED' &&
      sameAmount.json?.obligation?.id === obligation?.id &&
      sameAmount.json?.obligation?.totalDeclared === 50 &&
      sameAmount.json?.obligation?.declarationCount === 2
      ? 'PASS'
      : 'FAIL',
    `HTTP ${sameAmount.status} amendment=${sameAmount.json?.amendment} ` +
      `id=${sameAmount.json?.obligation?.id ?? '-'} total=${sameAmount.json?.obligation?.totalDeclared} ` +
      `count=${sameAmount.json?.obligation?.declarationCount}`,
  );

  // ------------------- 4) el cajero NO puede cambiar el importe (403)
  const cashierRectifies = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenCashier,
    body: { ...baseBody, totalDeclared: 500, note: 'UAT: intento de rectificación sin permiso' },
  });
  const afterRejected = await call('GET', '/sales/reconciliation-obligations?status=PENDING', {
    token: tokenA,
  });
  const rejectedRow = (Array.isArray(afterRejected.json) ? afterRejected.json : []).find(
    (row) => row.clientRequestId === requestId,
  );
  record(
    'DEV-02',
    'Un cajero NO puede cambiar el importe: 403 y la obligación intacta',
    cashierRectifies.status === 403 && rejectedRow?.totalDeclared === 50
      ? 'PASS'
      : 'FAIL',
    `HTTP ${cashierRectifies.status} code=${cashierRectifies.json?.code ?? '-'} ` +
      `importe_vigente=${rejectedRow?.totalDeclared}`,
  );

  // ------------------- 5) el administrativo rectifica → mismo id, version 2
  const rectified = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: { ...baseBody, totalDeclared: 55, note: 'UAT: arqueo, eran 55' },
  });
  record(
    'DEV-03',
    'Rectificación autorizada: MISMA obligación, importe 55 y version 2',
    rectified.status === 201 &&
      rectified.json?.amendment === 'RECTIFIED' &&
      rectified.json?.obligation?.id === obligation?.id &&
      rectified.json?.obligation?.totalDeclared === 55 &&
      rectified.json?.obligation?.version === 2
      ? 'PASS'
      : 'FAIL',
    `HTTP ${rectified.status} amendment=${rectified.json?.amendment} ` +
      `id=${rectified.json?.obligation?.id ?? '-'} total=${rectified.json?.obligation?.totalDeclared} ` +
      `version=${rectified.json?.obligation?.version}`,
  );

  // ------------------------------------------- 6) una sola fila por operación
  const listA = await call('GET', '/sales/reconciliation-obligations?status=PENDING', {
    token: tokenA,
  });
  const rowsA = Array.isArray(listA.json) ? listA.json : [];
  const mine = rowsA.filter((row) => row.clientRequestId === requestId);
  record(
    'LIST-01',
    'La operación tiene UNA sola obligación pendiente (no duplica el saldo)',
    listA.status === 200 && mine.length === 1 && mine[0].totalDeclared === 55
      ? 'PASS'
      : 'FAIL',
    `HTTP ${listA.status} filas_de_la_operacion=${mine.length} importe=${mine[0]?.totalDeclared}`,
  );

  // ------------------------------------------------- 7) historial auditado
  const events = await call(
    'GET',
    `/sales/reconciliation-obligations/${obligation?.id}/events`,
    { token: tokenA },
  );
  const kinds = Array.isArray(events.json) ? events.json.map((e) => e.kind) : [];
  const rectifiedEvent = Array.isArray(events.json)
    ? events.json.find((e) => e.kind === 'RECTIFIED')
    : null;
  record(
    'EVT-01',
    'Historial: cada declaración y la rectificación quedan auditadas',
    events.status === 200 &&
      kinds.join(',') === 'CREATED,AMENDED,RECTIFICATION_REJECTED,RECTIFIED' &&
      rectifiedEvent?.previousTotal === 50 &&
      rectifiedEvent?.totalDeclared === 55
      ? 'PASS'
      : 'FAIL',
    `HTTP ${events.status} eventos=[${kinds.join(', ')}] anterior=${rectifiedEvent?.previousTotal} nuevo=${rectifiedEvent?.totalDeclared}`,
  );

  // -------------------------------------------------- 8) aislamiento empresa B
  const listB = await call('GET', '/sales/reconciliation-obligations', { token: tokenB });
  const rowsB = Array.isArray(listB.json) ? listB.json : [];
  record(
    'TENANT-01',
    'La empresa B NO ve ninguna obligación de la empresa A',
    listB.status === 200 && rowsB.length === 0 ? 'PASS' : 'FAIL',
    `HTTP ${listB.status} filas visibles para B=${rowsB.length}`,
  );

  const foreignEvents = await call(
    'GET',
    `/sales/reconciliation-obligations/${obligation?.id}/events`,
    { token: tokenB },
  );
  record(
    'TENANT-02',
    'El historial de otra empresa responde 403 (no filtra datos)',
    foreignEvents.status === 403 ? 'PASS' : 'FAIL',
    `HTTP ${foreignEvents.status}`,
  );

  // ------------------------------------------------------------- 9) 401 / 400
  const noToken = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    body: baseBody,
  });
  record('AUTH-01', 'Sin token el endpoint responde 401', noToken.status === 401 ? 'PASS' : 'FAIL',
    `HTTP ${noToken.status}`);

  const badAmount = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: { ...baseBody, totalDeclared: 0 },
  });
  record('VALID-01', 'Importe 0 rechazado con 400', badAmount.status === 400 ? 'PASS' : 'FAIL',
    `HTTP ${badAmount.status}`);

  const badDate = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: { ...baseBody, declaredAtUtc: '27/10/2026 20:39' },
  });
  record('VALID-02', 'Fecha no ISO-8601 UTC rechazada con 400', badDate.status === 400 ? 'PASS' : 'FAIL',
    `HTTP ${badDate.status}`);

  const legacyFingerprint = await call(
    'POST',
    `/sales/attempts/uat-decl-${RUN}-legacyfp/declaration`,
    { token: tokenA, body: { ...baseBody, operationFingerprint: 'huella-no-hex-legacy' } },
  );
  record(
    'DECL-05',
    'Una huella de correlación no hexadecimal NO pierde la obligación',
    legacyFingerprint.status === 201 ? 'PASS' : 'FAIL',
    `HTTP ${legacyFingerprint.status} ${legacyFingerprint.status === 201 ? '' : describe(legacyFingerprint.json)}`,
  );

  // ------------- 10) 5 envíos simultáneos idénticos → 1 obligación, 5 marcas
  const burstId = `uat-decl-${RUN}-burst`;
  const burstBody = { ...baseBody, note: 'UAT: 5 envíos simultáneos' };
  const burst = await Promise.all(
    Array.from({ length: 5 }, () =>
      call('POST', `/sales/attempts/${burstId}/declaration`, { token: tokenA, body: burstBody }),
    ),
  );
  const burstCreated = burst.filter((r) => r.json?.duplicate === false).length;
  const burstDuplicate = burst.filter((r) => r.json?.duplicate === true).length;
  const burstIds = new Set(burst.map((r) => r.json?.obligation?.id).filter(Boolean));
  const burstRow = (Array.isArray((await call('GET', '/sales/reconciliation-obligations?status=PENDING', { token: tokenA })).json)
    ? (await call('GET', '/sales/reconciliation-obligations?status=PENDING', { token: tokenA })).json
    : []
  ).find((row) => row.clientRequestId === burstId);
  record(
    'CONC-01',
    '5 envíos simultáneos de la misma declaración → UNA sola obligación',
    burstCreated === 1 && burstDuplicate === 4 && burstIds.size === 1 && burstRow?.declarationCount === 1
      ? 'PASS'
      : 'FAIL',
    `creadas=${burstCreated} duplicadas=${burstDuplicate} ids=${burstIds.size} count=${burstRow?.declarationCount}`,
  );

  // ----------------------------------------- 11) verificación read-only (motor)
  const unknownId = `uat-unknown-${RUN}`;
  const reconciliation = await call(
    'GET',
    `/sales/attempts/${unknownId}/reconciliation?expectedTotalSold=50.00`,
    { token: tokenA },
  );
  record(
    'RECON-01',
    'La consulta del motor da un estado explícito para una operación inexistente',
    reconciliation.status === 200 && typeof reconciliation.json?.status === 'string'
      ? 'PASS'
      : 'FAIL',
    `HTTP ${reconciliation.status} status=${reconciliation.json?.status} guidance=${reconciliation.json?.guidance ?? '-'}`,
  );

  const reconciliation2 = await call(
    'GET',
    `/sales/attempts/${unknownId}/reconciliation?expectedTotalSold=50.00`,
    { token: tokenA },
  );
  record(
    'RECON-02',
    'Repetir la consulta no cambia nada (solo lectura idempotente)',
    reconciliation2.status === 200 && reconciliation2.json?.status === reconciliation.json?.status
      ? 'PASS'
      : 'FAIL',
    `HTTP ${reconciliation2.status} status=${reconciliation2.json?.status}`,
  );

  // --------------------------------------- 12) la declaración NO crea ventas
  const salesBefore = await call('GET', '/sales?limit=50', { token: tokenA });
  const salesList = Array.isArray(salesBefore.json)
    ? salesBefore.json
    : Array.isArray(salesBefore.json?.items)
      ? salesBefore.json.items
      : null;
  record(
    'SAFE-01',
    'Declarar dinero recibido no crea ninguna venta en la empresa A',
    salesBefore.status === 200 && Array.isArray(salesList) && salesList.length === 0 ? 'PASS' : 'FAIL',
    `HTTP ${salesBefore.status} ventas=${salesList ? salesList.length : 'forma inesperada'}`,
  );

  // ---------------------- 13) ciclo completo: venta real → verificación → cierre
  const openSession = await call('POST', '/cash/sessions/open', {
    token: tokenA,
    body: {
      openingAmount: 0,
      note: 'UAT recovery v2',
      clientSessionId: randomUUID(),
      deviceFingerprint: `uat-${RUN}`,
    },
  });
  const sessionId = openSession.json?.shiftId ?? openSession.json?.cashId ?? null;
  record(
    'CASH-01',
    'Turno de caja sintético abierto (requisito del backend para vender)',
    (openSession.status === 200 || openSession.status === 201) && Boolean(sessionId) ? 'PASS' : 'FAIL',
    `HTTP ${openSession.status} shiftId=${sessionId ?? '-'}`,
  );

  const cycleId = `uat-cycle-${RUN}`;
  const saleBody = {
    clientRequestId: cycleId,
    note: 'UAT ciclo de recuperación',
    paymentMethod: 'cash',
    paymentCashAmount: 50,
    cashReceived: 50,
    expectedTotalSold: 50,
    ...(sessionId ? { originCashSessionId: sessionId } : {}),
    items: [
      {
        qty: 1,
        priceSoldUnit: 50,
        costUnitSnapshot: 30,
        productName: 'Artículo UAT',
        productSource: 'LOCAL',
      },
    ],
  };
  const sale = await call('POST', '/sales', { token: tokenA, body: saleBody, timeoutMs: 25000 });
  const saleId = sale.json?.sale?.id ?? sale.json?.id ?? null;
  record(
    'CYCLE-01',
    'Venta sintética en efectivo registrada',
    sale.status === 201 && Boolean(saleId) ? 'PASS' : 'FAIL',
    `HTTP ${sale.status} saleId=${saleId ?? '-'} ${saleId ? '' : describe(sale.json)}`,
  );

  const verify1 = await call(
    'GET',
    `/sales/attempts/${cycleId}/reconciliation?expectedTotalSold=50.00`,
    { token: tokenA },
  );
  record(
    'CYCLE-02',
    'La consulta del motor confirma la venta real (CONFIRMED + saleId)',
    verify1.status === 200 &&
      verify1.json?.status === 'CONFIRMED' &&
      String(verify1.json?.sale?.id ?? '') === String(saleId)
      ? 'PASS'
      : 'FAIL',
    `HTTP ${verify1.status} status=${verify1.json?.status} saleId=${verify1.json?.sale?.id ?? '-'}`,
  );

  const verifyAgain = await Promise.all(
    Array.from({ length: 3 }, () =>
      call('GET', `/sales/attempts/${cycleId}/reconciliation?expectedTotalSold=50.00`, { token: tokenA }),
    ),
  );
  const readSales = await call('GET', '/sales?limit=50', { token: tokenA });
  const afterList = Array.isArray(readSales.json)
    ? readSales.json
    : Array.isArray(readSales.json?.items)
      ? readSales.json.items
      : [];
  record(
    'CYCLE-03',
    'Verificar 3 veces más NO duplica la venta (sigue habiendo 1)',
    verifyAgain.every((r) => r.json?.status === 'CONFIRMED') && afterList.length === 1 ? 'PASS' : 'FAIL',
    `confirmadas=${verifyAgain.filter((r) => r.json?.status === 'CONFIRMED').length} ventas=${afterList.length}`,
  );

  const resend = await call('POST', '/sales', { token: tokenA, body: saleBody, timeoutMs: 25000 });
  const resendId = resend.json?.sale?.id ?? resend.json?.id ?? null;
  const readSales2 = await call('GET', '/sales?limit=50', { token: tokenA });
  const finalList = Array.isArray(readSales2.json)
    ? readSales2.json
    : Array.isArray(readSales2.json?.items)
      ? readSales2.json.items
      : [];
  record(
    'CYCLE-04',
    'Reenviar la MISMA venta (mismo clientRequestId) no crea una segunda',
    (resend.status === 200 || resend.status === 201) &&
      String(resendId) === String(saleId) &&
      finalList.length === 1
      ? 'PASS'
      : 'FAIL',
    `HTTP ${resend.status} saleId=${resendId ?? '-'} ventas finales=${finalList.length}`,
  );

  const summary = {
    run: RUN,
    api: BASE,
    total: results.length,
    passed: results.filter((r) => r.status === 'PASS').length,
    failed: results.filter((r) => r.status === 'FAIL').length,
    notExecuted: results.filter((r) => r.status === 'N/E').length,
    results,
  };
  console.log('\n--- RESUMEN ---');
  console.log(JSON.stringify(summary, null, 2));
  process.exit(summary.failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error('UAT acceptance aborted:', error);
  process.exit(2);
});
