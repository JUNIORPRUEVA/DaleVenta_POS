// Read-only verification of the synthetic browser fixture on isolated PostgreSQL.
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const {PrismaClient}=require('@prisma/client');
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing'}}});
async function main(){
  const email='signup-local-20261120-2015@example.test';
  assert.equal(await db.user.count({where:{email}}),1);
  const user=await db.user.findUniqueOrThrow({where:{email},select:{id:true,companyId:true,role:true}});
  assert.equal(user.role,'ADMIN');assert.ok(user.companyId);
  const company=await db.company.findUniqueOrThrow({where:{id:user.companyId},select:{name:true}});
  assert.equal(company.name,'Laboratorio Registro 2015');
  const tickets=await db.sessionHandoffTicket.findMany({where:{userId:user.id},select:{usedAt:true,companyId:true}});
  assert.equal(tickets.length,1);assert.ok(tickets[0].usedAt);assert.equal(tickets[0].companyId,user.companyId);
  const sales=await db.sale.count({where:{companyId:user.companyId}});
  const movements=await db.cashMovement.count({where:{companyId:user.companyId}});
  assert.equal(sales,0);assert.equal(movements,0);
  const requests=(await fs.readFile('.uat/signup/http-statuses.jsonl','utf8')).trim().split('\n').map(JSON.parse);
  const count=(path,status)=>requests.filter(r=>r.method==='POST'&&r.path===path&&r.status===status).length;
  assert.equal(count('/api/auth/register-business',201),1);
  assert.equal(count('/api/auth/handoff/ticket',201),1);
  assert.equal(count('/api/auth/handoff/exchange',200),1);
  assert.equal(count('/api/auth/handoff/exchange',401),1);
  assert.equal(requests.filter(r=>r.method==='POST'&&r.path==='/api/auth/login').length,0);
  const evidence={result:'PASS',oneAccount:true,companyMatches:true,oneTicketConsumed:true,
    registrationPosts:1,successfulExchanges:1,manualLoginPosts:0,sales,movements,
    rejectedInvalidExchanges:count('/api/auth/handoff/exchange',401)};
  await fs.writeFile('.uat/signup/database-evidence.json',JSON.stringify(evidence,null,2));
  console.log(JSON.stringify(evidence));
}
main().catch(error=>{console.error(error.name+': '+error.message);process.exitCode=1;}).finally(()=>db.$disconnect());
