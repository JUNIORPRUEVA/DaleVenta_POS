const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const {PrismaClient} = require('@prisma/client');
const db = new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing'}}});
async function main() {
  const before = JSON.parse(await fs.readFile('.uat/courier/financial-before.json','utf8'));
  const after = {
    sales:await db.sale.findMany({orderBy:{id:'asc'},select:{id:true,totalSold:true,userId:true,cashSessionId:true,clientRequestId:true}}),
    movements:await db.cashMovement.findMany({orderBy:{id:'asc'},select:{id:true,amount:true,occurredAt:true,operationId:true,sessionId:true}}),
  };
  assert.deepEqual(JSON.parse(JSON.stringify(after)),before);
  const cases = await db.recoveryReviewCase.findMany({where:{operationId:{startsWith:'native-courier-'}}});
  assert.ok(cases.length >= 1);
  for (const row of cases) {
    row.events = await db.recoveryReviewEvent.findMany({where:{companyId:row.companyId,caseId:row.id}});
    assert.equal(row.status,'RESOLVED_NOT_PERFORMED');
    assert.equal(row.expectedAmount.toNumber(),7);
    assert.equal(row.events.filter(e=>e.kind==='SUBMITTED').length,1);
    assert.equal(row.events.filter(e=>e.kind==='NOT_PERFORMED').length,1);
  }
  const evidence={result:'PASS',financialRecordsUnchanged:true,sales:after.sales.length,
    movements:after.movements.length,cases:cases.map(row=>({id:row.id,status:row.status,events:row.events.length}))};
  await fs.writeFile('.uat/courier/financial-check.json',JSON.stringify(evidence,null,2));
  console.log(JSON.stringify(evidence));
}
main().catch(error=>{console.error(error.name+': '+error.message);process.exitCode=1;}).finally(()=>db.$disconnect());
