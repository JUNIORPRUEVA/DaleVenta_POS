const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');
async function main() {
  const target = new URL(process.env.DATABASE_URL);
  assert.equal(process.env.APP_ENV, 'uat');
  assert.equal(process.env.UAT_LOCAL_ONLY, 'true');
  assert.equal(target.hostname, '127.0.0.1');
  assert.equal(target.port, '56548');
  assert.equal(target.pathname, '/daleventa_offline_safe_48h_uat');
  const files = fs.readdirSync('.uat').filter(name => name.startsWith('phase11-flutter-client-'))
    .map(name => path.join('.uat', name, 'integrity-result.json')).filter(file => fs.existsSync(file));
  const isUpdate = process.env.FULLPOS_PHASE13_UPDATE_AUDIT === 'true';
  const file = isUpdate ? '.uat/phase13-update-bench/phase11-flutter-client-update/update-resume-result.json' : files.sort().at(-1);
  assert.ok(file, 'No successful Flutter UAT evidence exists.');
  const evidence = JSON.parse(fs.readFileSync(file, 'utf8'));
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  try {
    const product = (await db.query('select id, stock from "Product" where company_id=$1 and id=$2', [evidence.companyId, evidence.productId])).rows;
    assert.equal(product.length, 1);
    assert.equal(Number(product[0].stock), 16);
    const entries = (await db.query('select quantity_delta, operation_payload_hash from inventory_movements where company_id=$1 and operation_id=$2 and product_id=$3', [evidence.companyId, evidence.stockOperationId, evidence.productId])).rows;
    assert.equal(entries.length, 1);
    assert.equal(Number(entries[0].quantity_delta), 20);
    assert.ok(entries[0].operation_payload_hash);
    const sales = (await db.query('select id, "cashSessionId", "totalSold" from "Sale" where company_id=$1 and client_request_id=$2', [evidence.companyId, evidence.saleClientRequestId])).rows;
    assert.equal(sales.length, 1);
    assert.equal(sales[0].cashSessionId, evidence.shiftId);
    assert.equal(Number(sales[0].totalSold), 400);
    const lines = (await db.query('select "productId", qty from "SaleItem" where "saleId"=$1 and "saleId" in (select id from "Sale" where company_id=$2)', [sales[0].id, evidence.companyId])).rows;
    assert.equal(lines.length, 1);
    assert.equal(lines[0].productId, evidence.productId);
    assert.equal(Number(lines[0].qty), 4);
    const movements = (await db.query('select quantity_delta from inventory_movements where company_id=$1 and product_id=$2', [evidence.companyId, evidence.productId])).rows;
    assert.equal(movements.length, 2);
    assert.equal(movements.reduce((sum, m) => sum + Number(m.quantity_delta), 0), 16);
    const result = { ...evidence, postgresVerified: true, productCount: 1, entryCount: 1, saleCount: 1, saleItemCount: 1, movementCount: 2 };
    fs.writeFileSync(isUpdate ? '.uat/evidence/phase13-update-postgres-reconciliation.json' : '.uat/evidence/phase11-flutter-postgres-reconciliation.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
