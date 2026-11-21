// Read-only financial invariants around the native recovery UI acceptance.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {DatabaseSync} = require('node:sqlite');
const {PrismaClient} = require('@prisma/client');
const target = new URL(process.env.DATABASE_URL || '');
assert.equal(target.hostname, '127.0.0.1');
assert.equal(target.port, '56560');
assert.equal(target.pathname, '/fullpos_recovery_closing');
const root = path.resolve(__dirname, '../..');
const evidence = path.join(root, '.uat/recovery-ui-native');
const profile = path.join(root, '.uat/windows-native-20261120');
const prisma = new PrismaClient();
async function main() {
  const source = JSON.parse(await fs.readFile(path.join(profile, 'evidence/windows-persistence.json'), 'utf8'));
  const {companyId, userId} = source;
  assert.ok(companyId && userId);
  const financial = {
    sales: await prisma.sale.findMany({where:{companyId},orderBy:{id:'asc'},select:{id:true,clientRequestId:true,totalSold:true,cashSessionId:true}}),
    movements: await prisma.cashMovement.findMany({where:{companyId},orderBy:{id:'asc'},select:{id:true,operationId:true,sessionId:true,amount:true,occurredAt:true}}),
    sessions: await prisma.cashSession.findMany({where:{companyId},orderBy:{id:'asc'},select:{id:true,status:true,closingAmount:true,expectedAmount:true,difference:true}}),
  };
  const reviews = await prisma.recoveryReviewCase.findMany({where:{companyId,sourceUserId:userId},select:{id:true,sourceActionId:true,status:true,expectedAmount:true}});
  const db = new DatabaseSync(path.join(profile, 'databases/fulltech_offline.uat.db'), {readOnly:true});
  let actions;
  try {
    actions = db.prepare('SELECT id, type, status, payload FROM pending_actions WHERE company_id=? AND user_id=? ORDER BY id').all(companyId,userId).map(row => {
      const payload=JSON.parse(row.payload);
      const {recoveryReviewId,recoveryReviewStatus,...originalPayload}=payload;
      return {id:row.id,type:row.type,status:row.status,originalPayload,recoveryReviewId,recoveryReviewStatus};
    });
  } finally { db.close(); }
  const result = JSON.parse(JSON.stringify({companyId,userId,financial,reviews,actions}));
  await fs.mkdir(evidence,{recursive:true});
  if (process.argv[2] === 'before') {
    await fs.writeFile(path.join(evidence,'before.json'),JSON.stringify(result,null,2));
  } else {
    const before=JSON.parse(await fs.readFile(path.join(evidence,'before.json'),'utf8'));
    assert.deepEqual(result.financial,before.financial,'Recovery UI must not create or alter financial records.');
    assert.deepEqual(result.actions.map(({id,type,originalPayload})=>({id,type,originalPayload})),
      before.actions.map(({id,type,originalPayload})=>({id,type,originalPayload})), 'Original incidents and payloads must remain intact.');
    assert.ok(result.reviews.length >= before.reviews.length);
    assert.ok(result.reviews.some(review=>result.actions.some(action=>action.id===review.sourceActionId&&action.recoveryReviewId===review.id)));
    for (const review of result.reviews.filter(row=>!before.reviews.some(previous=>previous.id===row.id))) {
      assert.ok(['OPEN','REVIEWING'].includes(review.status), 'An unconfirmed operation must remain under review.');
    }
    await fs.writeFile(path.join(evidence,'after.json'),JSON.stringify({...result,result:'PASS'},null,2));
  }
  console.log(JSON.stringify({phase:process.argv[2],sales:financial.sales.length,movements:financial.movements.length,retainedIncidents:actions.length,reviews:reviews.length,result:'PASS'}));
}
main().catch(error=>{console.error(`${error.name}: ${error.message}`);process.exitCode=1;}).finally(()=>prisma.$disconnect());
