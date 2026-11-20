const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { PrismaClient } = require('@prisma/client');
const target = new URL(process.env.DATABASE_URL || '');
assert.equal(target.hostname,'127.0.0.1');
assert.equal(target.port,'56560');
assert.ok(['/fullpos_recovery_stabilization','/fullpos_recovery_closing'].includes(target.pathname));
const prisma = new PrismaClient();
async function main() {
  const dir=path.resolve(process.env.RECOVERY_NATIVE_EVIDENCE_DIR || '.uat/recovery-stabilization-20261120');
  assert.ok(dir.replaceAll('\\','/').includes('/.uat/'));
  const sourceFile=process.env.RECOVERY_NATIVE_EVIDENCE_FILE || 'windows-persistence.json';
  assert.equal(path.basename(sourceFile),sourceFile);
  const source=JSON.parse(await fs.readFile(path.join(dir,sourceFile),'utf8'));
  assert.ok(['windows','android'].includes(source.platform));
  const {companyId,run}=source;
  const sales=await prisma.sale.findMany({where:{companyId},select:{id:true,clientRequestId:true,totalSold:true,saleDate:true,cashSessionId:true}});
  const movements=await prisma.cashMovement.findMany({where:{companyId},select:{id:true,operationId:true,amount:true,sessionId:true,occurredAt:true,createdAt:true}});
  const sessions=await prisma.cashSession.findMany({where:{companyId},select:{id:true,status:true,closingAmount:true,expectedAmount:true,difference:true}});
  assert.equal(sales.length,2);
  assert.equal(new Set(sales.map(row=>row.clientRequestId)).size,2);
  for(const sale of sales) {
    assert.equal(Number(sale.totalSold),50);
    assert.equal(sale.cashSessionId,source.originalShift);
  }
  assert.equal(movements.length,3);
  assert.equal(new Set(movements.map(row=>row.operationId)).size,3);
  assert.ok(movements.every(row=>Number(row.amount)===7 && row.occurredAt && row.occurredAt<=row.createdAt));
  assert.ok(!movements.some(row=>row.operationId===`windows-old-shift-${run}`));
  const closed=sessions.find(row=>row.id===source.originalShift);
  assert.equal(closed.status,'CLOSED');
  assert.equal(Number(closed.closingAmount),114);
  assert.equal(Number(closed.expectedAmount),114);
  assert.equal(Number(closed.difference),0);
  assert.equal(sessions.find(row=>row.id===source.laterShift).status,'OPEN');
  assert.equal(source.persistentIncidentsAfterRestart,46);
  const result={result:'PASS',companyId,run,sales,movements,sessions,
    duplicates:0,rejectedOldShiftWrites:0,retainedSQLiteIncidents:46};
  if (process.env.RECOVERY_SQLITE_PATH) {
    const sqlitePath=path.resolve(process.env.RECOVERY_SQLITE_PATH);
    assert.ok(sqlitePath.replaceAll('\\','/').includes('/.uat/'));
    const {DatabaseSync}=require('node:sqlite');
    const local=new DatabaseSync(sqlitePath,{readOnly:true});
    try {
      const incidents=local.prepare('SELECT status, permanent, count(*) AS total FROM pending_actions WHERE company_id=? AND user_id=? GROUP BY status, permanent').all(companyId,source.userId);
      assert.equal(incidents.reduce((sum,row)=>sum+row.total,0),46);
      assert.ok(incidents.every(row=>row.permanent===1));
      result.sqliteIncidents=incidents;
      result.sqliteSales=local.prepare('SELECT client_request_id, server_id, status FROM offline_sales WHERE company_id=? AND user_id=?').all(companyId,source.userId);
      assert.equal(result.sqliteSales.length,2);
      assert.ok(result.sqliteSales.every(row=>row.status==='synced'&&sales.some(sale=>sale.id===row.server_id&&sale.clientRequestId===row.client_request_id)));
    } finally { local.close(); }
  }
  await fs.writeFile(path.join(dir,`${source.platform}-${run}-postgresql-crosscheck.json`),JSON.stringify(result,null,2));
  console.log(JSON.stringify({result:'PASS',sales:2,movements:3,duplicates:0,retainedSQLiteIncidents:46}));
}
main().catch(error=>{console.error(`Persistence verification failed: ${error.name}: ${error.message}`);process.exitCode=1;})
  .finally(()=>prisma.$disconnect());
