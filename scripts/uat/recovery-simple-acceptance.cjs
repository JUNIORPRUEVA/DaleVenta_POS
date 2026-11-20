// Only local API/PostgreSQL, synthetic administrative evidence, no financial POST.
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const jwt=require('jsonwebtoken');
const {PrismaClient}=require('@prisma/client');
const root=path.resolve(__dirname,'../..');
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing'}}});
const api='http://127.0.0.1:4005';
const evidence={api,scenarios:[]};
async function request(route,token,body){
  const response=await fetch(api+route,{method:body?'POST':'GET',headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
  return {status:response.status,data:await response.json()};
}
async function financial(companyId){
  return JSON.parse(JSON.stringify({
    sales:await db.sale.findMany({where:{companyId},orderBy:{id:'asc'},select:{id:true,clientRequestId:true,userId:true,totalSold:true,cashSessionId:true,paymentMethod:true}}),
    movements:await db.cashMovement.findMany({where:{companyId},orderBy:{id:'asc'},select:{id:true,operationId:true,amount:true,occurredAt:true,sessionId:true}}),
    sessions:await db.cashSession.findMany({where:{companyId},orderBy:{id:'asc'},select:{id:true,status:true,closingAmount:true,expectedAmount:true,difference:true}}),
  }));
}
async function main(){
  assert.equal((await request('/health')).status,200);
  const profile=JSON.parse(await fs.readFile(path.join(root,'.uat/simple-financial-before.json'),'utf8'));
  const user=await db.user.findUniqueOrThrow({where:{id:profile.userId}});
  assert.equal(user.role,'ADMIN');
  const session=await db.authSession.findFirstOrThrow({where:{userId:user.id,companyId:profile.companyId,revokedAt:null,expiresAt:{gt:new Date()}}});
  const {key}=JSON.parse(await fs.readFile(process.env.FULLPOS_LOCAL_RECOVERY_KEY_FILE,'utf8'));
  const token=jwt.sign({sub:user.id,companyId:profile.companyId,sessionId:session.id,tokenType:'access'},key,{expiresIn:'10m'});
  const before=await financial(profile.companyId);
  const suffix=crypto.randomUUID();
  const body={totalDeclared:7,paymentMethod:'cash',declaredAtUtc:new Date().toISOString(),note:'Synthetic recovery UI declaration acceptance'};
  const created=await request(`/sales/attempts/ui-no-sale-${suffix}/declaration`,token,body);
  assert.equal(created.status,201);const row=created.data.obligation;assert.ok(row.id);
  const route=`/sales/reconciliation-obligations/${row.id}/resolve`;
  const decision={expectedVersion:row.version,note:'Synthetic evidence: declaration was incorrect'};
  assert.equal((await request(route,null,{...decision,decision:'DISMISS'})).status,401);
  assert.equal((await request(route,token,{...decision,decision:'CHECK'})).status,409);
  assert.equal((await request(route,token,{...decision,expectedVersion:999,decision:'DISMISS'})).status,409);
  assert.equal((await db.saleReconciliationObligation.findUniqueOrThrow({where:{id:row.id}})).status,'PENDING');
  const dismissed=await request(route,token,{...decision,decision:'DISMISS'});assert.equal(dismissed.status,201);
  assert.equal(dismissed.data.status,'DISMISSED');
  const events=await db.saleReconciliationDeclarationEvent.count({where:{companyId:profile.companyId,obligationId:row.id}});
  assert.equal((await request(route,token,{...decision,decision:'DISMISS'})).status,201);
  assert.equal(await db.saleReconciliationDeclarationEvent.count({where:{companyId:profile.companyId,obligationId:row.id}}),events);
  evidence.scenarios.push('401 denied','missing sale retained','stale version retained','dismissal audited','repeat dismissal idempotent');
  // Existing synthetic native sale: no new sale/movement is posted.
  const sale=before.sales.find(item=>item.clientRequestId&&item.paymentMethod==='cash');assert.ok(sale);
  const declaration=await request(`/sales/attempts/${sale.clientRequestId}/declaration`,token,{
    ...body,totalDeclared:Number(sale.totalSold),attemptPayload:{originCashSessionId:sale.cashSessionId},
  });assert.equal(declaration.status,201);
  const linked=declaration.data.obligation;
  const linkedRoute=`/sales/reconciliation-obligations/${linked.id}/resolve`;
  assert.equal((await request(linkedRoute,token,{...decision,expectedVersion:linked.version,decision:'DISMISS'})).status,409);
  const checked=await request(linkedRoute,token,{...decision,expectedVersion:linked.version,decision:'CHECK'});
  assert.equal(checked.status,201);assert.equal(checked.data.status,'RECONCILED');
  evidence.scenarios.push('registered sale cannot be dismissed','exact existing sale reconciles');
  const foreign=await db.company.findFirst({where:{id:{not:profile.companyId},status:'ACTIVE'},select:{id:true}});
  if(foreign){
    const foreignSession=await db.authSession.findFirst({where:{companyId:foreign.id,revokedAt:null,expiresAt:{gt:new Date()}},include:{user:true}});
    if(foreignSession){
      const otherToken=jwt.sign({sub:foreignSession.userId,companyId:foreign.id,sessionId:foreignSession.id,tokenType:'access'},key,{expiresIn:'10m'});
      assert.ok([403,404].includes((await request(route,otherToken,{...decision,decision:'CHECK'})).status));
      evidence.scenarios.push('foreign company denied');
    }
  }
  const after=await financial(profile.companyId);assert.deepEqual(after,before);
  evidence.financial={sales:after.sales.length,movements:after.movements.length,unchanged:true};
  evidence.result='PASS';
  const dir=path.join(root,'.uat/recovery-simple');await fs.mkdir(dir,{recursive:true});
  await fs.writeFile(path.join(dir,`api-acceptance-${Date.now()}.json`),JSON.stringify(evidence,null,2));
  console.log(JSON.stringify(evidence));
}
main().catch(error=>{console.error(`${error.name}: ${error.message}`);process.exitCode=1;}).finally(()=>db.$disconnect());
