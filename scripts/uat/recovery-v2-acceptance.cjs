#!/usr/bin/env node
/**
 * UAT de aceptación — Motor de recuperación v2 y obligaciones de conciliación.
 *
 * Habla con una API real (UAT aislado) por HTTP y comprueba el comportamiento
 * observable. No toca producción y no imprime tokens ni contraseñas.
 *
 * Uso:
 *   node scripts/uat/recovery-v2-acceptance.cjs
 *   UAT_API_BASE=http://127.0.0.1:4010 node scripts/uat/recovery-v2-acceptance.cjs
 *
 * Salida: matriz PASS/FAIL por caso + resumen JSON. Código de salida 0 solo si
 * no hay ningún FAIL.
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

async function call(method, path, { token, body, timeoutMs = 10000 } = {}) {
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
  return text && text.length > 220 ? `${text.slice(0, 220)}…` : text;
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
  const token =
    login.json?.accessToken ||
    login.json?.access_token ||
    login.json?.token ||
    res.json?.accessToken ||
    null;
  return { email, res, login, token };
}

async function main() {
  console.log(`\nUAT Recovery v2 · API ${BASE} · run ${RUN}\n`);

  // ---------------------------------------------------------------- setup
  const companyA = await registerBusiness('a');
  if (companyA.res.status >= 400 || !companyA.token) {
    record(
      'ENV-01',
      'Alta de empresa sintética A + login',
      'FAIL',
      `register=${companyA.res.status} login=${companyA.login.status} ${describe(companyA.login.json)}`,
    );
    console.log(JSON.stringify({ results, run: RUN }, null, 2));
    process.exit(1);
  }
  record('ENV-01', 'Alta de empresa sintética A + login', 'PASS', `HTTP ${companyA.res.status}`);

  const companyB = await registerBusiness('b');
  if (!companyB.token) {
    record('ENV-02', 'Alta de empresa sintética B + login', 'FAIL', describe(companyB.login.json));
    console.log(JSON.stringify({ results, run: RUN }, null, 2));
    process.exit(1);
  }
  record('ENV-02', 'Alta de empresa sintética B + login', 'PASS', `HTTP ${companyB.res.status}`);

  const tokenA = companyA.token;
  const tokenB = companyB.token;

  // ------------------------------------------------- 1) declaración base
  const requestId = `uat-decl-${RUN}-1`;
  const declaredAt = new Date('2026-10-27T20:39:00.000Z').toISOString();
  const baseBody = {
    totalDeclared: 50,
    declaredAtUtc: declaredAt,
    paymentMethod: 'cash',
    declaredByRole: 'OWNER',
    note: 'UAT: cliente pagó en efectivo, no salió ticket',
  };

  const created = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: baseBody,
  });
  const obligation = created.json?.obligation;
  const okShape =
    created.status === 201 &&
    obligation?.id &&
    obligation?.totalDeclared === 50 &&
    obligation?.retryAllowed === false &&
    obligation?.assertsPaymentReceived === false &&
    obligation?.status === 'PENDING';
  record(
    'DECL-01',
    'Declaración crea obligación PENDING (sin retryAllowed ni pago declarado)',
    okShape ? 'PASS' : 'FAIL',
    `HTTP ${created.status} id=${obligation?.id ?? '-'} status=${obligation?.status ?? '-'} ` +
      `retryAllowed=${obligation?.retryAllowed} assertsPaymentReceived=${obligation?.assertsPaymentReceived}`,
  );

  // ------------------------------------------------ 2) idempotencia exacta
  const again = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: baseBody,
  });
  const dupOk =
    again.status === 201 &&
    again.json?.duplicate === true &&
    again.json?.obligation?.id === obligation?.id;
  record(
    'DECL-02',
    'Reenvío idéntico devuelve la MISMA obligación (duplicate:true)',
    dupOk ? 'PASS' : 'FAIL',
    `HTTP ${again.status} duplicate=${again.json?.duplicate} id=${again.json?.obligation?.id ?? '-'}`,
  );

  // ------------------------------------ 3) rectificación de importe = nueva
  const corrected = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: { ...baseBody, totalDeclared: 55 },
  });
  const correctedOk =
    corrected.status === 201 &&
    corrected.json?.duplicate === false &&
    corrected.json?.obligation?.id !== obligation?.id &&
    corrected.json?.obligation?.totalDeclared === 55;
  record(
    'DECL-03',
    'Rectificación de importe crea una obligación NUEVA y auditable',
    correctedOk ? 'PASS' : 'FAIL',
    `HTTP ${corrected.status} duplicate=${corrected.json?.duplicate} nuevo id=${corrected.json?.obligation?.id ?? '-'}`,
  );

  // -------------------------------------------- 4) misma operación, otra nota
  const otherNote = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: { ...baseBody, note: 'UAT: rectifico la nota del arqueo' },
  });
  record(
    'DECL-04',
    'Misma operación con otra nota queda como registro distinto (trazable)',
    otherNote.status === 201 && otherNote.json?.duplicate === false ? 'PASS' : 'FAIL',
    `HTTP ${otherNote.status} duplicate=${otherNote.json?.duplicate} id=${otherNote.json?.obligation?.id ?? '-'}`,
  );

  // ------------------------------------------------------- 5) listado propio
  const listA = await call('GET', '/sales/reconciliation-obligations?status=PENDING', {
    token: tokenA,
  });
  const rowsA = Array.isArray(listA.json) ? listA.json : [];
  const mine = rowsA.filter((row) => row.clientRequestId === requestId);
  record(
    'LIST-01',
    'El listado devuelve las 3 obligaciones de esa operación en la empresa A',
    listA.status === 200 && mine.length === 3 ? 'PASS' : 'FAIL',
    `HTTP ${listA.status} filas=${rowsA.length} de la operación=${mine.length}`,
  );

  // -------------------------------------------------- 6) aislamiento empresa B
  const listB = await call('GET', '/sales/reconciliation-obligations', { token: tokenB });
  const rowsB = Array.isArray(listB.json) ? listB.json : [];
  record(
    'TENANT-01',
    'La empresa B NO ve ninguna obligación de la empresa A',
    listB.status === 200 && rowsB.length === 0 ? 'PASS' : 'FAIL',
    `HTTP ${listB.status} filas visibles para B=${rowsB.length}`,
  );

  // ------------------------------------------------------------- 7) 401 / 400
  const noToken = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    body: baseBody,
  });
  record(
    'AUTH-01',
    'Sin token el endpoint responde 401',
    noToken.status === 401 ? 'PASS' : 'FAIL',
    `HTTP ${noToken.status}`,
  );

  const badAmount = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: { ...baseBody, totalDeclared: 0 },
  });
  record(
    'VALID-01',
    'Importe 0 rechazado con 400 (no se puede declarar un monto inexistente)',
    badAmount.status === 400 ? 'PASS' : 'FAIL',
    `HTTP ${badAmount.status}`,
  );

  const badDate = await call('POST', `/sales/attempts/${requestId}/declaration`, {
    token: tokenA,
    body: { ...baseBody, declaredAtUtc: '27/10/2026 20:39' },
  });
  record(
    'VALID-02',
    'Fecha no ISO-8601 UTC rechazada con 400',
    badDate.status === 400 ? 'PASS' : 'FAIL',
    `HTTP ${badDate.status}`,
  );

  // ------------------------- 7.1) defecto UAT: huella no hexadecimal no bloquea
  const legacyFingerprint = await call(
    'POST',
    `/sales/attempts/uat-decl-${RUN}-legacyfp/declaration`,
    {
      token: tokenA,
      body: { ...baseBody, operationFingerprint: 'huella-no-hex-legacy' },
    },
  );
  record(
    'DECL-05',
    'Una huella de correlación en formato no hexadecimal NO pierde la obligación',
    legacyFingerprint.status === 201 && Boolean(legacyFingerprint.json?.obligation?.id)
      ? 'PASS'
      : 'FAIL',
    `HTTP ${legacyFingerprint.status} id=${legacyFingerprint.json?.obligation?.id ?? '-'} ` +
      `${legacyFingerprint.status === 201 ? '' : describe(legacyFingerprint.json)}`,
  );

  // ------------------------------------ 9) dos dispositivos de la misma empresa
  // Misma empresa, dos terminales distintas declarando la MISMA operación.
  const sharedId = `uat-decl-${RUN}-twodevices`;
  const deviceBody = {
    ...baseBody,
    note: 'UAT: dos dispositivos, misma declaración',
    declaredByRole: 'CASHIER',
  };
  const deviceA = await call('POST', `/sales/attempts/${sharedId}/declaration`, {
    token: tokenA,
    body: { ...deviceBody, declaredByUserId: 'device-a-user' },
  });
  const deviceB = await call('POST', `/sales/attempts/${sharedId}/declaration`, {
    token: tokenA,
    body: { ...deviceBody, declaredByUserId: 'device-b-user' },
  });
  const listing = await call('GET', '/sales/reconciliation-obligations', { token: tokenA });
  const sharedRows = (Array.isArray(listing.json) ? listing.json : []).filter(
    (row) => row.clientRequestId === sharedId,
  );
  record(
    'DEV-01',
    'Dos dispositivos declaran la misma operación: 2 registros auditables, no 1 silencioso',
    deviceA.status === 201 &&
      deviceB.status === 201 &&
      sharedRows.length === 2 &&
      sharedRows[0].id !== sharedRows[1].id
      ? 'PASS'
      : 'FAIL',
    `dispositivoA=${deviceA.status} dispositivoB=${deviceB.status} filas=${sharedRows.length} ` +
      `actores=${sharedRows.map((r) => r.declaredByUserId).join(',')}`,
  );

  const deviceBCorrects = await call('POST', `/sales/attempts/${sharedId}/declaration`, {
    token: tokenA,
    body: {
      ...deviceBody,
      totalDeclared: 55,
      declaredByUserId: 'device-b-user',
      note: 'UAT: rectificación autorizada desde el dispositivo B',
    },
  });
  const afterCorrection = await call('GET', '/sales/reconciliation-obligations', {
    token: tokenA,
  });
  const correctionRows = (Array.isArray(afterCorrection.json) ? afterCorrection.json : []).filter(
    (row) => row.clientRequestId === sharedId,
  );
  record(
    'DEV-02',
    'La rectificación de un dispositivo queda como registro nuevo, autorizado y auditable',
    deviceBCorrects.status === 201 &&
      deviceBCorrects.json?.duplicate === false &&
      correctionRows.length === 3
      ? 'PASS'
      : 'FAIL',
    `HTTP ${deviceBCorrects.status} duplicate=${deviceBCorrects.json?.duplicate} ` +
      `filas_totales=${correctionRows.length}`,
  );

  // ------------------------------------- 10) concurrencia de la MISMA declaración
  const burstId = `uat-decl-${RUN}-burst`;
  const burstBody = { ...baseBody, note: 'UAT: 5 envíos simultáneos' };
  const burst = await Promise.all(
    Array.from({ length: 5 }, () =>
      call('POST', `/sales/attempts/${burstId}/declaration`, { token: tokenA, body: burstBody }),
    ),
  );
  const createdCount = burst.filter((r) => r.json?.duplicate === false).length;
  const duplicateCount = burst.filter((r) => r.json?.duplicate === true).length;
  const burstIds = new Set(burst.map((r) => r.json?.obligation?.id).filter(Boolean));
  record(
    'CONC-01',
    '5 envíos simultáneos de la misma declaración producen UNA sola obligación',
    createdCount === 1 && duplicateCount === 4 && burstIds.size === 1 ? 'PASS' : 'FAIL',
    `creadas=${createdCount} duplicadas=${duplicateCount} ids distintos=${burstIds.size}`,
  );

  // ------------------------------------------- 9) verificación read-only (motor)
  const unknownId = `uat-unknown-${RUN}`;
  const reconciliation = await call(
    'GET',
    `/sales/attempts/${unknownId}/reconciliation?expectedTotalSold=50.00`,
    { token: tokenA },
  );
  const reconStatus = reconciliation.json?.status;
  record(
    'RECON-01',
    'La consulta del motor responde con un estado explícito para una operación inexistente',
    reconciliation.status === 200 && typeof reconStatus === 'string' ? 'PASS' : 'FAIL',
    `HTTP ${reconciliation.status} status=${reconStatus} guidance=${reconciliation.json?.guidance ?? '-'} ` +
      `retryAllowed=${reconciliation.json?.retryAllowed}`,
  );

  const reconUnknownAgain = await call(
    'GET',
    `/sales/attempts/${unknownId}/reconciliation?expectedTotalSold=50.00`,
    { token: tokenA },
  );
  record(
    'RECON-02',
    'Repetir la consulta no cambia nada (endpoint idempotente de solo lectura)',
    reconUnknownAgain.status === 200 &&
      reconUnknownAgain.json?.status === reconStatus
      ? 'PASS'
      : 'FAIL',
    `HTTP ${reconUnknownAgain.status} status=${reconUnknownAgain.json?.status}`,
  );

  // --------------------------------------- 10) la declaración NO crea ventas
  const salesA = await call('GET', '/sales?limit=20', { token: tokenA });
  const salesList = Array.isArray(salesA.json)
    ? salesA.json
    : Array.isArray(salesA.json?.items)
      ? salesA.json.items
      : Array.isArray(salesA.json?.data)
        ? salesA.json.data
        : null;
  record(
    'SAFE-01',
    'Declarar dinero recibido no crea ninguna venta en la empresa A',
    salesA.status === 200 && Array.isArray(salesList) && salesList.length === 0 ? 'PASS' : 'FAIL',
    `HTTP ${salesA.status} ventas=${salesList ? salesList.length : 'forma inesperada'}`,
  );

  // ---------------------- 11) ciclo completo: venta real → verificación → cierre
  const openSession = await call('POST', '/cash/sessions/open', {
    token: tokenA,
    body: {
      openingAmount: 0,
      note: 'UAT recovery v2',
      clientSessionId: randomUUID(),
      deviceFingerprint: `uat-${RUN}`,
    },
  });
  // `shiftId` es el id de `cash_sessions` que la venta espera en
  // `originCashSessionId`; `cashId` es otra entidad (el contenedor de caja).
  const sessionId =
    openSession.json?.shiftId ??
    openSession.json?.cashId ??
    openSession.json?.session?.id ??
    openSession.json?.id ??
    null;
  record(
    'CASH-01',
    'Turno de caja sintético abierto (requisito del backend para vender)',
    (openSession.status === 200 || openSession.status === 201) && Boolean(sessionId)
      ? 'PASS'
      : 'FAIL',
    `HTTP ${openSession.status} sessionId=${sessionId ?? '-'} ${sessionId ? '' : describe(openSession.json)}`,
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
    ...(sessionId ? { terminalId: undefined } : {}),
    items: [
      {
        qty: 1,
        priceSoldUnit: 50,
        // El backend exige coste para un artículo fuera de inventario.
        costUnitSnapshot: 30,
        productName: 'Artículo UAT',
        productSource: 'LOCAL',
      },
    ],
  };
  const sale = await call('POST', '/sales', { token: tokenA, body: saleBody, timeoutMs: 20000 });
  const saleId = sale.json?.sale?.id ?? sale.json?.id ?? null;
  record(
    'CYCLE-01',
    'Venta sintética en efectivo registrada (respuesta dudosa simulada después)',
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
    `HTTP ${verify1.status} status=${verify1.json?.status} saleId=${verify1.json?.sale?.id ?? '-'} ` +
      `guidance=${verify1.json?.guidance ?? '-'}`,
  );

  const verifyAgain = await Promise.all(
    Array.from({ length: 3 }, () =>
      call('GET', `/sales/attempts/${cycleId}/reconciliation?expectedTotalSold=50.00`, {
        token: tokenA,
      }),
    ),
  );
  const allConfirmed = verifyAgain.every(
    (r) => r.status === 200 && r.json?.status === 'CONFIRMED',
  );
  const afterVerify = await call('GET', '/sales?limit=50', { token: tokenA });
  const afterList = Array.isArray(afterVerify.json)
    ? afterVerify.json
    : Array.isArray(afterVerify.json?.items)
      ? afterVerify.json.items
      : [];
  record(
    'CYCLE-03',
    'Verificar 3 veces más NO duplica la venta (sigue habiendo 1)',
    allConfirmed && afterList.length === 1 ? 'PASS' : 'FAIL',
    `consultas=${verifyAgain.length} confirmadas=${verifyAgain.filter((r) => r.json?.status === 'CONFIRMED').length} ventas=${afterList.length}`,
  );

  const resend = await call('POST', '/sales', {
    token: tokenA,
    body: saleBody,
    timeoutMs: 20000,
  });
  const resendId = resend.json?.sale?.id ?? resend.json?.id ?? null;
  const afterResend = await call('GET', '/sales?limit=50', { token: tokenA });
  const finalList = Array.isArray(afterResend.json)
    ? afterResend.json
    : Array.isArray(afterResend.json?.items)
      ? afterResend.json.items
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
