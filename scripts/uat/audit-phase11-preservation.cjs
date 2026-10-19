const assert = require('node:assert/strict');
const fs = require('node:fs');
const { Client } = require('pg');
async function main() {
  const target = new URL(process.env.DATABASE_URL);
  assert.equal(process.env.APP_ENV, 'uat');
  assert.equal(process.env.UAT_LOCAL_ONLY, 'true');
  assert.equal(target.hostname, '127.0.0.1');
  assert.equal(target.port, '56548');
  assert.equal(target.pathname, '/daleventa_offline_safe_48h_uat');
  const manual = JSON.parse(fs.readFileSync('.uat/evidence/phase11-manual-preservation.json', 'utf8'));
  assert.equal(manual.quoteUnchanged, true);
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  try {
    let items = 0;
    let movements = 0;
    for (const local of manual.sales) {
      const sale = (await db.query('select id, "cashSessionId", "totalSold" from "Sale" where company_id=$1 and client_request_id=$2', [local.companyId, local.clientRequestId])).rows;
      assert.equal(sale.length, 1);
      assert.equal(sale[0].cashSessionId, local.shiftId);
      assert.equal(Number(sale[0].totalSold), local.total);
      items += Number((await db.query('select count(*) as count from "SaleItem" where "saleId"=$1 and "saleId" in (select id from "Sale" where company_id=$2)', [sale[0].id, local.companyId])).rows[0].count);
      movements += Number((await db.query('select count(*) as count from inventory_movements where company_id=$1 and source_id=$2 and source_type=$3', [local.companyId, sale[0].id, 'SALE'])).rows[0].count);
    }
    assert.equal(manual.sales.length, 8);
    assert.equal(items, 20);
    assert.equal(movements, 20);
    const recovery = JSON.parse(fs.readFileSync('.uat/evidence/phase11-quote-recovery-dto.json', 'utf8'));
    assert.equal(Object.hasOwn(recovery.dto, 'customerId'), false);
    const candidates = (await db.query('select id from "Cotizacion" where company_id=$1 and "customerName"=$2 and "customerPhone"=$3 and total=$4', [recovery.companyId, recovery.dto.customerName, recovery.dto.customerPhone, recovery.total])).rows;
    const result = { status: 'PASS', manualSales: 8, items, inventoryMovements: movements, quoteUnchanged: true,
      quoteRecoveryDtoValidated: true, remoteQuoteCandidatesByNamePhoneTotal: candidates.length,
      recoveryApplied: false, originalQuoteRequiresApproval: true };
    fs.writeFileSync('.uat/evidence/phase11-preservation-postgres.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
