param([switch]$DisposablePhase12)

. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment

if (-not $DisposablePhase12) {
  throw 'This smoke closes cash shifts. Run with -DisposablePhase12 against the isolated phase12 clone; the manual UAT is protected.'
}
$UatExpectedDbName = 'daleventa_offline_safe_48h_phase12_uat'
$env:PORT = '46552'
$cloneUrl = [UriBuilder]$env:DATABASE_URL
$cloneUrl.Path = $UatExpectedDbName
$env:DATABASE_URL = $cloneUrl.Uri.AbsoluteUri
$env:UAT_DB_NAME = $UatExpectedDbName
$env:UAT_EXPECTED_DB_NAME = $UatExpectedDbName
$cloneIdentity = docker exec $UatPostgresContainer psql -U $UatExpectedDbUser -d $UatExpectedDbName -t -A -c 'select current_database();'
if ($LASTEXITCODE -ne 0 -or "$cloneIdentity".Trim() -ne $UatExpectedDbName) {
  throw 'Disposable phase12 database identity could not be verified.'
}
$env:FULLPOS_PHASE12_SMOKE = 'true'
Write-UatBanner

$ErrorActionPreference = 'Stop'

$healthUrl = "http://127.0.0.1:$env:PORT/health"
try {
  $health = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 $healthUrl
  if ($health.StatusCode -lt 200 -or $health.StatusCode -ge 300) {
    throw "Unexpected health status $($health.StatusCode)"
  }
} catch {
  throw "UAT API is not reachable at $healthUrl. Start scripts/uat/run-backend.ps1 first. $($_.Exception.Message)"
}

$nodeScript = @'
const fs = require('fs');
const { randomUUID } = require('crypto');

function readEnvFile(path) {
  const env = {};
  for (const raw of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const index = line.indexOf('=');
    env[line.slice(0, index).trim()] = line.slice(index + 1).trim().replace(/^"|"$/g, '');
  }
  return env;
}

const env = readEnvFile('apps/api/.env.offline-safe-48h.uat.local');
if (process.env.FULLPOS_PHASE12_SMOKE !== 'true' || process.env.PORT !== '46552') throw new Error('Disposable phase12 smoke required.');
const base = 'http://127.0.0.1:46552';
const email = env.UAT_ADMIN_EMAIL || 'uat.admin@daleventa.local';
const password = env.UAT_ADMIN_PASSWORD;
if (!password) throw new Error('Missing UAT_ADMIN_PASSWORD in local UAT env.');

async function request(path, options = {}, expectedStatuses = [200, 201]) {
  const res = await fetch(`${base}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      'x-client-device-id': 'fase8-sync-integrity-device',
      'x-client-platform': 'windows',
      'x-client-app-version': 'uat-fase8',
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  let body;
  try { body = text ? JSON.parse(text) : null; } catch (_) { body = text; }
  if (!expectedStatuses.includes(res.status)) {
    throw new Error(`${options.method || 'GET'} ${path} -> ${res.status}: ${typeof body === 'string' ? body : JSON.stringify(body)}`);
  }
  return { status: res.status, body };
}

function saleIdOf(response) {
  return response.body?.id || response.body?.sale?.id;
}

(async () => {
  const runId = `fase8-${Date.now()}`;
  const login = await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  const token = login.body.accessToken || login.body.token;
  if (!token) throw new Error('Login did not return an access token.');
  const auth = { authorization: `Bearer ${token}` };
  const companyId = login.body.user?.companyId;
  if (!companyId || !/^[0-9a-f-]{36}$/i.test(companyId)) throw new Error('Missing tenant identity.');

  const offlineAuthorization = await request('/auth/offline-emergency/authorize', {
    method: 'POST',
    headers: auth,
    body: '{}',
  });

  const cashSessionClientId = randomUUID();
  const cash = await request('/cash/sessions/open', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      openingAmount: 1000,
      note: `Fase 8 sync integrity ${runId}`,
      clientSessionId: cashSessionClientId,
    }),
  });
  const originalShiftId = cash.body.shiftId || cash.body.id || cash.body.session?.id || cashSessionClientId;

  // Each run owns its stock. Repeated smoke runs must not exhaust shared seeds.
  const productLines = [];
  for (const priceSoldUnit of [100, 120, 140]) {
    const product = await request('/products', {
      method: 'POST', headers: auth,
      body: JSON.stringify({ operationId: randomUUID(), nombre: `${runId}-${priceSoldUnit}`,
        codigo: `${runId}-${priceSoldUnit}`, categoria: 'UAT sync smoke',
        precio: priceSoldUnit, costo: 40, stock: 10 }),
    });
    if (!product.body?.id) throw new Error('Smoke product identity missing.');
    productLines.push({ productId: product.body.id, qty: 1, priceSoldUnit });
  }

  const sales = [];
  for (let index = 0; index < productLines.length; index += 1) {
    const line = productLines[index];
    const clientRequestId = `${runId}-sale-${index + 1}-${randomUUID()}`;
    const total = line.qty * line.priceSoldUnit;
    const payload = {
      clientRequestId,
      originCashSessionId: originalShiftId,
      deviceFingerprint: 'fase8-sync-integrity-device',
      saleOccurredAt: new Date(Date.now() - (productLines.length - index) * 1000).toISOString(),
      paymentMethod: 'cash',
      paymentCashAmount: total,
      cashReceived: total,
      expectedTotalSold: total,
      items: [line],
    };
    const first = await request('/sales', {
      method: 'POST',
      headers: auth,
      body: JSON.stringify(payload),
    });
    const replayBeforeClose = await request('/sales', {
      method: 'POST',
      headers: auth,
      body: JSON.stringify(payload),
    });
    if (saleIdOf(first) !== saleIdOf(replayBeforeClose)) {
      throw new Error(`Idempotency mismatch before close for ${clientRequestId}`);
    }
    sales.push({ clientRequestId, saleId: saleIdOf(first), total, productId: line.productId, qty: line.qty, priceSoldUnit: line.priceSoldUnit, payload });
  }

  const insufficientStock = await request('/sales', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      clientRequestId: `${runId}-insufficient-${randomUUID()}`,
      originCashSessionId: originalShiftId,
      paymentMethod: 'cash',
      paymentCashAmount: 999999999,
      cashReceived: 999999999,
      expectedTotalSold: 999999999,
      items: [{ productId: productLines[0].productId, qty: 999999, priceSoldUnit: 1000 }],
    }),
  }, [400, 409]);

  await request('/cash/sessions/close', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      sessionId: originalShiftId,
      closingAmount: 1000 + sales.reduce((sum, sale) => sum + sale.total, 0),
      note: `Fase 8 close original ${runId}`,
    }),
  });

  const newCash = await request('/cash/sessions/open', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      openingAmount: 250,
      note: `Fase 8 new shift ${runId}`,
      clientSessionId: randomUUID(),
    }),
  });
  const newShiftId = newCash.body.shiftId || newCash.body.id || newCash.body.session?.id;
  if (!newShiftId || newShiftId === originalShiftId) {
    throw new Error('Opening a new cash shift after close did not produce a distinct shift.');
  }

  for (const sale of sales) {
    const replayAfterNewShift = await request('/sales', {
      method: 'POST',
      headers: auth,
      body: JSON.stringify(sale.payload),
    });
    if (saleIdOf(replayAfterNewShift) !== sale.saleId) {
      throw new Error(`Idempotency mismatch after new shift for ${sale.clientRequestId}`);
    }
  }

  console.log(JSON.stringify({
    status: 'PASS',
    companyId,
    runId,
    offlineAuthorization: {
      policyVersion: offlineAuthorization.body?.policyVersion,
      maxOfflineHours: offlineAuthorization.body?.maxOfflineHours,
      validUntilUtc: offlineAuthorization.body?.validUntilUtc,
    },
    originalShiftId,
    newShiftId,
    sales,
    insufficientStock: {
      status: insufficientStock.status,
      code: insufficientStock.body?.code || insufficientStock.body?.errorCode || insufficientStock.body?.message,
    },
  }, null, 2));
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
'@

$nodeResult = $nodeScript | node
if ($LASTEXITCODE -ne 0) {
  throw "Sync integrity smoke failed."
}

$result = $nodeResult | ConvertFrom-Json
$ids = @($result.sales | ForEach-Object { $_.clientRequestId })
if ($ids.Count -ne 3) {
  throw "Expected 3 sale IDs from sync integrity smoke."
}

$values = ($ids | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ','
$sql = @'
select
  count(*) as sales,
  count(distinct s.client_request_id) as distinct_client_request_ids,
  count(distinct s."cashSessionId") as distinct_cash_sessions,
  coalesce(sum(s."totalSold"), 0) as total_sold,
  count(si.id) as sale_items,
  count(im.id) as inventory_movements
from "Sale" s
left join "SaleItem" si on si."saleId" = s.id
left join inventory_movements im on im.source_id = s.id
where s.company_id = '__COMPANY_ID__' and s.client_request_id in (__CLIENT_REQUEST_IDS__);
'@
$sql = $sql.Replace('__CLIENT_REQUEST_IDS__', $values)
$sql = $sql.Replace('__COMPANY_ID__', $result.companyId)

$pg = $sql | docker exec -i $UatPostgresContainer psql -U $UatExpectedDbUser -d $UatExpectedDbName -t -A -F '|'
if ($LASTEXITCODE -ne 0) {
  throw "PostgreSQL reconciliation failed: $pg"
}
$parts = ($pg | Select-Object -Last 1).Split('|')
$expectedTotal = ($result.sales | Measure-Object -Property total -Sum).Sum.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
if ($parts[0] -ne '3' -or $parts[1] -ne '3' -or $parts[2] -ne '1' -or $parts[3] -ne $expectedTotal -or $parts[4] -ne '3' -or $parts[5] -ne '3') {
  throw "Unexpected PostgreSQL reconciliation result: $pg"
}

[ordered]@{
  status = 'PASS'
  database = $UatExpectedDbName
  apiPort = $env:PORT
  companyId = $result.companyId
  runId = $result.runId
  originalShiftId = $result.originalShiftId
  newShiftId = $result.newShiftId
  sales = $result.sales
  insufficientStock = $result.insufficientStock
  postgres = @{
    sales = [int]$parts[0]
    distinctClientRequestIds = [int]$parts[1]
    distinctCashSessions = [int]$parts[2]
    totalSold = $parts[3]
    saleItems = [int]$parts[4]
    inventoryMovements = [int]$parts[5]
  }
} | ConvertTo-Json -Depth 8
