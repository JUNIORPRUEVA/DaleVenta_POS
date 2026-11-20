const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const {PrismaClient}=require('@prisma/client');
const database=new URL(process.env.DATABASE_URL||'');
assert.equal(database.hostname,'127.0.0.1');assert.equal(database.port,'56560');
assert.equal(database.pathname,'/fullpos_recovery_closing');
const input=path.resolve(process.env.RECOVERY_JOURNAL_EVIDENCE_PATH||'');
assert.ok(input.replaceAll('\\','/').includes('/.uat/'));assert.ok(input.endsWith('.json'));
const prisma=new PrismaClient();
async function main(){
  const evidence=JSON.parse(await fs.readFile(input,'utf8'));
  assert.ok(['windows','android'].includes(evidence.platform));
  const {companyId,userId,sessionId}=evidence;
  assert.ok(companyId&&userId&&sessionId);
  const movements=await prisma.cashMovement.findMany({where:{companyId},select:{id:true,operationId:true,userId:true,sessionId:true,amount:true,occurredAt:true}});
  const sessions=await prisma.cashSession.findMany({where:{companyId},select:{id:true,openedByUserId:true,status:true,closingAmount:true,expectedAmount:true,difference:true}});
  const cases=await prisma.recoveryReviewCase.findMany({where:{companyId},select:{id:true,status:true,registeredEntityId:true}});
  assert.equal(await prisma.sale.count({where:{companyId}}),0);
  assert.equal(movements.length,1);assert.equal(sessions.length,1);assert.equal(cases.length,1);
  const request=evidence.dispatched.find(row=>row.path==='/cash/movements');assert.ok(request);
  assert.equal(movements[0].operationId,request.operationId);assert.equal(movements[0].userId,userId);
  assert.equal(movements[0].sessionId,sessionId);assert.equal(Number(movements[0].amount),7);
  assert.equal(movements[0].occurredAt.toISOString(),new Date(request.occurredAt).toISOString());
  assert.equal(sessions[0].id,sessionId);assert.equal(sessions[0].openedByUserId,userId);
  assert.equal(sessions[0].status,'CLOSED');assert.equal(Number(sessions[0].closingAmount),7);
  assert.equal(Number(sessions[0].expectedAmount),7);assert.equal(Number(sessions[0].difference),0);
  assert.equal(cases[0].id,evidence.reviewId);assert.equal(cases[0].status,'RESOLVED_REGISTERED');
  assert.equal(cases[0].registeredEntityId,sessionId);
  const result={result:'PASS',platform:evidence.platform,run:evidence.run,companyId,
    sessions,movements,cases,duplicates:0,retainedLocalCloseReview:evidence.retainedCloseReview};
  if(process.env.RECOVERY_SQLITE_PATH){
    const sqlitePath=path.resolve(process.env.RECOVERY_SQLITE_PATH);
    assert.ok(sqlitePath.replaceAll('\\','/').includes('/.uat/'));
    const {DatabaseSync}=require('node:sqlite');
    const local=new DatabaseSync(sqlitePath,{readOnly:true});
    try{
      const rows=local.prepare('SELECT id, status, permanent, payload FROM pending_actions WHERE company_id=? AND user_id=?').all(companyId,userId);
      assert.equal(rows.length,1);assert.equal(rows[0].id,evidence.retainedCloseReview);
      assert.equal(rows[0].status,'review_resolved');assert.equal(rows[0].permanent,1);
      const payload=JSON.parse(rows[0].payload);
      assert.equal(payload.sessionId,sessionId);assert.equal(payload.closingAmount,7);
      assert.equal(payload.recoveryReviewId,evidence.reviewId);
      assert.equal(payload.recoveryReviewStatus,'RESOLVED_REGISTERED');
      result.sqliteRetainedReview={id:rows[0].id,status:rows[0].status,permanent:true,reviewId:payload.recoveryReviewId};
    }finally{local.close();}
  }
  await fs.writeFile(input.replace(/\.json$/,'-postgresql.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify({result:'PASS',platform:evidence.platform,sessions:1,movements:1,closingAmount:7,difference:0,duplicates:0,retainedReview:1}));
}
main().catch(error=>{console.error(`Cash journal verification failed: ${error.name}: ${error.message}`);process.exitCode=1;}).finally(()=>prisma.$disconnect());
