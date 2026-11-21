/* Synthetic acceptance only. No seed, cleanup, production connection or deletion. */
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { PrismaClient } = require('@prisma/client');
const db = new URL(process.env.DATABASE_URL || '');
assert.equal(db.hostname, '127.0.0.1');
assert.equal(db.port, '56560');
assert.ok(['/fullpos_recovery_stabilization','/fullpos_recovery_closing'].includes(db.pathname));
const api = process.env.RECOVERY_ACCEPTANCE_API || 'http://127.0.0.1:4004';
const apiUrl = new URL(api);
assert.equal(apiUrl.hostname,'127.0.0.1');
assert.ok(['4004','4005'].includes(apiUrl.port));
const prisma = new PrismaClient();
const run = Date.now().toString();
const evidence = { run, api, database:db.pathname.slice(1), scenarios:[] };
async function request(route, token, body, method = body ? 'POST' : 'GET') {
  const response = await fetch(`${api}${route}`, { method,
    headers:{'content-type':'application/json', ...(token ? {authorization:`Bearer ${token}`} : {})},
    ...(body ? {body:JSON.stringify(body)} : {}),
  });
  return {status:response.status, data:await response.json(), retryAfter:response.headers.get('retry-after')};
}
async function business(label) {
  const password = crypto.randomBytes(24).toString('base64url')+'aA1!';
  const registered = await request('/auth/register-business', null, {
    firstName:'Recovery',lastName:label,email:`api-recovery-${label}-${run}@example.test`,
    phone:'8095550202',password,confirmPassword:password,commercialName:`Recovery ${label} ${run}`,country:'DO',currency:'DOP',
  });
  assert.equal(registered.status,201);
  const {user,accessToken:token}=registered.data;
  assert.ok(user.companyId && user.id && token);
  const opening=await request('/cash/sessions/open',token,{openingAmount:0});
  assert.equal(opening.status,201);
  return {user,token,shift:opening.data.shiftId};
}
async function snapshot(companyId) {
  return {
    sales:await prisma.sale.count({where:{companyId}}),
    movements:await prisma.cashMovement.count({where:{companyId}}),
    obligations:await prisma.saleReconciliationObligation.count({where:{companyId}}),
    sessions:await prisma.cashSession.findMany({where:{companyId},select:{id:true,status:true,openedAt:true,closedAt:true,businessDate:true}}),
  };
}
function businessDay(at) { return new Date(at.getTime()-4*3600000).toISOString().slice(0,10); }
async function main() {
  const a=await business('A'), b=await business('B');
  const beforeA=await snapshot(a.user.companyId), beforeB=await snapshot(b.user.companyId);
  const base={sessionId:a.shift,type:'IN',amount:11,reason:'Synthetic API acceptance'};
  for (const [name,occurredAt] of [['invalid','bad-date'],['ambiguous','2026-11-20T12:00:00'],['future','2099-01-01T00:00:00Z']]) {
    const result=await request('/cash/movements',a.token,{...base,operationId:`api-${name}-${run}`,occurredAt});
    assert.equal(result.status,400,name);
    assert.equal((await snapshot(a.user.companyId)).movements,beforeA.movements);
    evidence.scenarios.push({name:`reject-${name}-date`,http:result.status,persistedMovements:0});
  }
  const openedAt=new Date(Date.now()-26*3600000);
  assert.equal((await prisma.cashSession.updateMany({where:{id:a.shift,companyId:a.user.companyId,openedByUserId:a.user.id},
    data:{openedAt,businessDate:businessDay(openedAt)}})).count,1);
  const stale=await request('/cash/movements',a.token,{...base,operationId:`api-stale-${run}`,occurredAt:new Date().toISOString()});
  assert.equal(stale.status,409);
  assert.equal(stale.data.code,'CASH_SESSION_STALE');
  const staleGate=await request('/cash/state',a.token);
  assert.equal(staleGate.data.canOperate,false);
  assert.equal(staleGate.data.requiresClosure,true);
  assert.equal((await snapshot(a.user.companyId)).movements,0);
  evidence.scenarios.push({name:'old-open-shift-26h',http:409,code:stale.data.code,canOperate:false,requiresClosure:true});
  const foreign=await request('/cash/movements',b.token,{...base,operationId:`api-foreign-${run}`,occurredAt:new Date().toISOString()});
  assert.ok([404,409].includes(foreign.status));
  assert.equal((await snapshot(b.user.companyId)).movements,beforeB.movements);
  const foreignLookup=await request(`/sales/attempts/api-stale-${run}/reconciliation?expectedTotalSold=11`,b.token);
  assert.equal(foreignLookup.data.status,'NOT_FOUND');
  evidence.scenarios.push({name:'multiple-companies-foreign-shift-is-rejected',http:foreign.status,
    foreignLookup:'NOT_FOUND',companyBMovementDelta:0});

  // Historical nocturnal fixture, created through the API, with only its own
  // synthetic session dates adjusted. Neither rule nor server clock is changed.
  const night=await business('Night');
  const yesterday=new Date(Date.now()-24*3600000).toISOString().slice(0,10);
  const nightOpen=new Date(`${yesterday}T02:30:00Z`);
  const occurrence=new Date(nightOpen.getTime()+2*3600000);
  await prisma.cashSession.updateMany({where:{id:night.shift,companyId:night.user.companyId,openedByUserId:night.user.id},
    data:{openedAt:nightOpen,businessDate:businessDay(nightOpen)}});
  const body={sessionId:night.shift,operationId:`api-night-${run}`,type:'IN',amount:11,occurredAt:occurrence.toISOString()};
  const nightResult=await request('/cash/movements',night.token,body);
  assert.equal(nightResult.status,201);
  const persisted=await prisma.cashMovement.findFirstOrThrow({where:{companyId:night.user.companyId,operationId:body.operationId}});
  assert.equal(persisted.occurredAt.toISOString(),body.occurredAt);
  const replay=await request('/cash/movements',night.token,body);
  assert.equal(replay.data.id,nightResult.data.id);
  assert.equal(await prisma.cashMovement.count({where:{companyId:night.user.companyId,operationId:body.operationId}}),1);
  evidence.scenarios.push({name:'night-shift-delayed-original-time',openedAt:nightOpen,occurredAt:occurrence,
    reception:persisted.createdAt,serverId:persisted.id,count:1});

  const cross=await request('/cash/movements',b.token,{...body,operationId:`api-cross-${run}`});
  assert.ok([404,409].includes(cross.status));
  assert.equal((await snapshot(b.user.companyId)).movements,beforeB.movements);
  const unknown=await request(`/sales/attempts/api-night-${run}/reconciliation?expectedTotalSold=11`,b.token);
  assert.equal(unknown.data.status,'NOT_FOUND');
  evidence.scenarios.push({name:'two-real-tenants-no-cross-write-or-disclosure',writeHttp:cross.status,lookupStatus:unknown.data.status});

  const unauthenticated=await request('/cash/state','invalid-test-token');
  assert.equal(unauthenticated.status,401);
  // Create a normal employee through the real admin endpoint. Roles and JWT
  // verification stay enabled; this user cannot administer other shifts.
  const staffPassword=crypto.randomBytes(24).toString('base64url')+'aA1!';
  const staffEmail=`api-staff-${run}@example.test`;
  const staff=await request('/users',b.token,{email:staffEmail,password:staffPassword,nombreCompleto:'Recovery cashier',edad:30,role:'CAJERO'});
  assert.equal(staff.status,201);
  const staffLogin=await request('/auth/login',null,{identifier:staffEmail,password:staffPassword});
  assert.equal(staffLogin.status,201);
  const forbidden=await request('/cash/sessions/stale',staffLogin.data.accessToken);
  assert.equal(forbidden.status,403);
  evidence.scenarios.push({name:'real-authentication-and-permissions',unauthenticated:401,cashierAdminEndpoint:403});

  let limited;
  for(let i=0;i<62;i++) {
    limited=await request(`/sales/attempts/rate-${run}/reconciliation?expectedTotalSold=1`,b.token);
    if(limited.status===429) break;
  }
  assert.equal(limited.status,429);
  assert.ok(Number(limited.retryAfter)>0);
  evidence.scenarios.push({name:'real-reconciliation-rate-limit',http:429,retryAfterSeconds:Number(limited.retryAfter)});
  const closed=await request('/cash/sessions/close',a.token,{sessionId:a.shift,closingAmount:0});
  assert.equal(closed.status,201);
  assert.equal((await prisma.cashSession.findFirstOrThrow({where:{id:a.shift,companyId:a.user.companyId}})).status,'CLOSED');
  evidence.scenarios.push({name:'old-shift-can-close-without-changing-window',http:201});
  const offlineOpening=await business('OfflineOpening');
  const earlier=await request('/cash/movements',offlineOpening.token,{
    sessionId:offlineOpening.shift,operationId:`api-pre-opening-${run}`,type:'IN',amount:5,
    occurredAt:new Date(Date.now()-10*60000).toISOString(),
  });
  assert.equal(earlier.status,409);
  assert.equal(earlier.data.code,'CASH_OPERATION_BEFORE_SHIFT');
  assert.equal((await snapshot(offlineOpening.user.companyId)).movements,0);
  evidence.scenarios.push({name:'known-limit-delayed-offline-opening-needs-review',http:409,
    code:earlier.data.code,persistedMovements:0,automaticBackdatingAllowed:false});
  evidence.before={a:beforeA,b:beforeB};
  evidence.after={a:await snapshot(a.user.companyId),b:await snapshot(b.user.companyId),night:await snapshot(night.user.companyId)};
  evidence.companies={a:a.user.companyId,b:b.user.companyId,night:night.user.companyId};
  evidence.result='PASS';
  const dir=path.resolve('.uat/recovery-stabilization-20261120');
  await fs.mkdir(dir,{recursive:true});
  await fs.writeFile(path.join(dir,'api-postgresql-evidence.json'),JSON.stringify(evidence,null,2));
  console.log(JSON.stringify({result:'PASS',scenarios:evidence.scenarios.length,evidence:'api-postgresql-evidence.json'}));
}
main().catch(error=>{console.error(`Acceptance failed: ${error.name}: ${error.message}`);process.exitCode=1;})
  .finally(()=>prisma.$disconnect());
