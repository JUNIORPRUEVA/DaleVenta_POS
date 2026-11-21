// Independent read-only SQL verification of the Windows app's HTTP upload.
const assert = require('node:assert/strict'), fs = require('node:fs/promises'), path = require('node:path');
const { PrismaClient } = require('@prisma/client');
const directory = path.resolve(__dirname, '../../.uat/plans-payment');
const db = new PrismaClient({ datasources: { db: { url: 'postgresql://postgres@127.0.0.1:56562/fullpos_plans_payment_20261121' } } });
async function main() {
  try {
    const result = JSON.parse(await fs.readFile(path.join(directory, 'native-result.json'), 'utf8'));
    assert.equal(result.result, 'PASS');
    const order = await db.licensePaymentOrder.findFirstOrThrow({ where: { id: result.orderId, companyId: result.companyId }, include: { evidences: true } });
    const company = await db.company.findUniqueOrThrow({ where: { id: result.companyId } });
    assert.equal(order.months, 3);
    assert.equal(order.status, 'EVIDENCE_RECEIVED');
    assert.equal(order.evidences.length, 1);
    assert.equal(order.evidences[0].id, result.evidenceId);
    assert.equal(order.evidences[0].companyId, result.companyId);
    assert.equal(order.activationState, 'NONE');
    assert.equal(company.licenseStatus, 'TRIAL');
    const evidence = { result: 'PASS', runId: result.runId, orderId: order.id, months: 3, receipts: 1, status: order.status, activationState: order.activationState, companyLicenseStatus: company.licenseStatus };
    await fs.writeFile(path.join(directory, 'native-sql-result.json'), JSON.stringify(evidence, null, 2));
    console.log('PASS: independent SQL, one receipt, three months, no unverified activation.');
  } finally { await db.$disconnect(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
