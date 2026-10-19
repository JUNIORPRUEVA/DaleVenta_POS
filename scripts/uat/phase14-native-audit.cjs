const assert = require('node:assert/strict');
const fs = require('node:fs');
const { Client } = require('pg');

async function main() {
  const target = new URL(process.env.DATABASE_URL);
  assert.equal(process.env.APP_ENV, 'uat');
  assert.equal(process.env.UAT_LOCAL_ONLY, 'true');
  assert.equal(target.hostname, '127.0.0.1');
  assert.equal(target.port, '56548');
  assert.equal(target.pathname, '/daleventa_offline_safe_48h_phase12_uat');
  const result = JSON.parse(fs.readFileSync('.uat/phase14-native-bank/native-B-synced.json', 'utf8'));
  assert.equal(result.status, 'PASS');
  assert.equal(result.lostConfirmations, 3);
  const a = JSON.parse(fs.readFileSync('.uat/phase14-native-bank/native-A.json', 'utf8'));
  assert.equal(a.build, '14001');
  assert.equal(result.build, '14002');
  for (const field of ['companyId', 'userId', 'shiftId', 'deviceHash', 'tokenHash', 'grantHash', 'validUntilUtc']) {
    assert.equal(result[field], a[field], field);
  }
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  try {
    assert.equal((await db.query('select current_database() as name')).rows[0].name, target.pathname.slice(1));
    const products = (await db.query('select stock from "Product" where company_id=$1 and id=$2', [result.companyId, result.productId])).rows;
    assert.equal(products.length, 1);
    assert.equal(Number(products[0].stock), 16);
    const sales = (await db.query('select id,"cashSessionId","userId","totalSold" from "Sale" where company_id=$1 and client_request_id=$2', [result.companyId, result.saleClientRequestId])).rows;
    assert.equal(sales.length, 1);
    assert.equal(sales[0].cashSessionId, result.shiftId);
    assert.equal(sales[0].userId, result.userId);
    assert.equal(Number(sales[0].totalSold), 400);
    const entries = (await db.query('select operation_id from inventory_movements where company_id=$1 and operation_id=$2', [result.companyId, result.stockOperationId])).rows;
    assert.equal(entries.length, 1);
    const moves = (await db.query('select id from inventory_movements where company_id=$1 and source_id=$2 and source_type=$3', [result.companyId, sales[0].id, 'SALE'])).rows;
    assert.equal(moves.length, 1);
    const evidence = { status: 'PASS', database: target.pathname.slice(1), companyId: result.companyId,
      productId: result.productId, originalShiftId: result.shiftId, saleId: sales[0].id,
      products: 1, stockEntries: entries.length, sales: sales.length, saleMovements: moves.length,
      stock: 16, totalSold: 400, lostConfirmations: result.lostConfirmations,
      nativeIdentityAndGrantUnchanged: true,
      scope: 'Real native probe/SQLite/plugins and isolated Inno; commercial updater orchestration not asserted' };
    fs.writeFileSync('.uat/evidence/phase14-native-postgres.json', JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence, null, 2));
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/g, '[redacted]')); process.exitCode = 1; });
