/* Isolated synthetic acceptance. No deletion, production or financial repair. */
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {OfflineCashPermitService}=require('../../apps/api/dist/auth/offline-cash-permit.service');
const database='postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing';
const prisma=new PrismaClient({datasources:{db:{url:database}}});
const api='http://127.0.0.1:4005';
const dir=path.resolve(__dirname,'../../.uat/recovery-closing-20261120');
const run=Date.now().toString();
const device=`closing-lab-${run}`;
const evidence={api,database:'fullpos_recovery_closing',run,scenarios:[]};
async function req(route,token,body,method=body?'POST':'GET'){
  const res=await fetch(api+route,{method,headers:{'content-type':'application/json','x-client-device-id':device,
    ...(token?{authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
  return {status:res.status,data:await res.json()};
}
async function business(label){
  const password=crypto.randomBytes(24).toString('base64url')+'Aa1!';
  const r=await req('/auth/register-business',null,{firstName:'Synthetic',lastName:label,email:`closing-${label}-${run}@example.test`,
    phone:'8095550202',password,confirmPassword:password,commercialName:`Recovery Closing ${label} ${run}`,country:'DO',currency:'DOP'});
  assert.equal(r.status,201);
  const b={user:r.data.user,token:r.data.accessToken};
  assert.equal((await req('/onboarding/skip-all',b.token,{})).status,201);
  return b;
}
async function snapshot(b){
  const where={companyId:b.user.companyId};
  return {sales:await prisma.sale.count({where}),movements:await prisma.cashMovement.findMany({where,select:{id:true,operationId:true,amount:true,occurredAt:true}}),
    sessions:await prisma.cashSession.findMany({where,select:{id:true,openedAt:true,createdAt:true,status:true}}),
    cases:await prisma.recoveryReviewCase.findMany({where,select:{id:true,status:true,version:true,registeredEntityId:true}}),
    reviewEvents:await prisma.recoveryReviewEvent.count({where})};
}
async function main(){
  const a=await business('A'),b=await business('B');
  evidence.before={a:await snapshot(a),b:await snapshot(b)};
  const grant=await req('/auth/offline-emergency/authorize',a.token,{});
  assert.equal(grant.status,201);
  assert.ok(grant.data.cashOpenPermit?.startsWith('fpcash1.'));
  assert.ok(grant.data.allowedOperations.includes('cash.open'));
  // Time-travel fixture uses the real issuer and a dedicated local test key.
  // It represents an authorization issued 15 minutes earlier, without sleeping.
  const {key}=JSON.parse(await fs.readFile(path.join(dir,'local-auth-key.json'),'utf8'));
  const issuer=new OfflineCashPermitService({get:name=>name==='JWT_SECRET'?key:undefined});
  const claims=JSON.parse(Buffer.from(grant.data.cashOpenPermit.split('.')[1],'base64url').toString('utf8'));
  const openedAt=new Date(Date.now()-10*60_000).toISOString();
  const validFrom=new Date(Date.now()-15*60_000);
  const receipt=issuer.issue({...claims,validFrom:validFrom.toISOString(),
    validUntil:new Date(validFrom.getTime()+48*3600_000).toISOString()});
  const session=crypto.randomUUID();
  const opening={clientSessionId:session,openingAmount:0,openedAt,offlineOpenPermit:receipt,deviceFingerprint:device};
  for(const [name,token,body] of [
    ['tampered-signature',a.token,{...opening,offlineOpenPermit:receipt+'x'}],
    ['foreign-tenant',b.token,opening],
    ['foreign-device',a.token,{...opening,deviceFingerprint:'another-device'}],
    ['future-opening',a.token,{...opening,openedAt:'2099-01-01T00:00:00Z'}],
  ]){
    const r=await req('/cash/sessions/open',token,body);assert.equal(r.status,400,name);
    evidence.scenarios.push({name,http:r.status});
  }
  assert.equal((await snapshot(a)).sessions.length,0);
  const opened=await req('/cash/sessions/open',a.token,opening);assert.equal(opened.status,201);
  assert.equal(opened.data.shiftId,session);
  const stored=await prisma.cashSession.findFirstOrThrow({where:{companyId:a.user.companyId,id:session}});
  assert.equal(stored.openedAt.toISOString(),openedAt);
  assert.ok(stored.offlineOpeningEvidenceHash);
  const movementId=`delayed-movement-${run}`;
  const occurredAt=new Date(Date.parse(openedAt)+60_000).toISOString();
  const body={sessionId:session,type:'IN',amount:7,operationId:movementId,occurredAt,reason:'Synthetic delayed offline opening'};
  assert.equal((await req('/cash/movements',a.token,body)).status,201);
  assert.equal((await req('/cash/movements',a.token,body)).status,201);
  assert.equal(await prisma.cashMovement.count({where:{companyId:a.user.companyId,operationId:movementId}}),1);
  assert.equal((await prisma.cashMovement.findFirstOrThrow({where:{companyId:a.user.companyId,operationId:movementId}})).occurredAt.toISOString(),occurredAt);
  evidence.scenarios.push({name:'ten-minute-delayed-opening-original-movement-idempotency',openedAt,occurredAt,movements:1});
  const reviewBody={sourceActionId:`cash.movement:${movementId}`,actionType:'cash.movement',operationId:movementId,
    originalSessionId:session,expectedAmount:7,payloadSummary:body};
  const submitted=await req('/recovery/reviews',a.token,reviewBody);assert.equal(submitted.status,201);
  const caseId=submitted.data.id;
  assert.equal((await req('/recovery/reviews',a.token,reviewBody)).data.id,caseId);
  assert.equal((await req(`/recovery/reviews/${caseId}`,b.token)).status,404);
  const altered=await req('/recovery/reviews',a.token,{...reviewBody,expectedAmount:8,payloadSummary:{...body,amount:8}});
  assert.equal(altered.status,409);
  const no=await req(`/recovery/reviews/${caseId}/decision`,a.token,{decision:'NOT_PERFORMED',expectedVersion:1,note:'Synthetic review existing record'});
  assert.equal(no.status,409);
  const confirmed=await req(`/recovery/reviews/${caseId}/verify`,a.token,{});
  assert.equal(confirmed.data.status,'RESOLVED_REGISTERED');assert.equal(confirmed.data.financiallyConfirmed,true);
  assert.ok(confirmed.data.registeredEntityId);
  const missingId=`not-performed-${run}`;
  const missing=await req('/recovery/reviews',a.token,{...reviewBody,sourceActionId:missingId,operationId:missingId,payloadSummary:{...body,operationId:missingId}});
  assert.equal(missing.status,201);
  const unknown=await req(`/recovery/reviews/${missing.data.id}/verify`,a.token,{});
  assert.equal(unknown.data.verification,'NOT_FOUND');assert.equal(unknown.data.status,'OPEN');
  const decision=await req(`/recovery/reviews/${missing.data.id}/decision`,a.token,{decision:'NOT_PERFORMED',expectedVersion:1,note:'Synthetic evidence: no cash exchanged'});
  assert.equal(decision.data.status,'RESOLVED_NOT_PERFORMED');assert.equal(decision.data.financiallyConfirmed,false);
  evidence.scenarios.push({name:'review-idempotent-tenant-isolated-confirmed-or-human-audited',cases:2});
  evidence.after={a:await snapshot(a),b:await snapshot(b)};
  assert.equal(evidence.after.a.sales,0);assert.equal(evidence.after.a.movements.length,1);
  assert.equal(evidence.after.a.cases.length,2);assert.equal(evidence.after.a.reviewEvents,4);
  assert.deepEqual(evidence.after.b,evidence.before.b);
  // A closed daily cashbox is a synthetic fixture, never reopened by recovery.
  const c=await business('ClosedDaily');
  const cg=await req('/auth/offline-emergency/authorize',c.token,{});
  assert.equal(cg.status,201);
  const cc=JSON.parse(Buffer.from(cg.data.cashOpenPermit.split('.')[1],'base64url').toString('utf8'));
  const cPermit=issuer.issue({...cc,validFrom:validFrom.toISOString(),validUntil:new Date(validFrom.getTime()+48*3600_000).toISOString()});
  const businessDate=new Date(Date.parse(openedAt)-4*3600_000).toISOString().slice(0,10);
  const closedBox=await prisma.cashboxDaily.create({data:{companyId:c.user.companyId,businessDate,
    openedByUserId:c.user.id,initialAmount:0,currentAmount:0,status:'CLOSED',closedAt:new Date(),closedByUserId:c.user.id}});
  const deniedClosed=await req('/cash/sessions/open',c.token,{...opening,clientSessionId:crypto.randomUUID(),offlineOpenPermit:cPermit});
  assert.equal(deniedClosed.status,409);assert.equal(deniedClosed.data.code,'CASH_OFFLINE_CASHBOX_CLOSED');
  const retainedBox=await prisma.cashboxDaily.findFirstOrThrow({where:{companyId:c.user.companyId,id:closedBox.id}});
  assert.equal(retainedBox.status,'CLOSED');assert.equal(retainedBox.closedAt.getTime(),closedBox.closedAt.getTime());
  assert.equal((await snapshot(c)).sessions.length,0);
  evidence.scenarios.push({name:'offline-recovery-cannot-reopen-closed-daily-cashbox',http:409,sessions:0});

  // Revocation applies to the historical authorization even with a different,
  // currently valid session for the same owner.
  const d=await business('RevokedPermit');
  const dg=await req('/auth/offline-emergency/authorize',d.token,{});
  assert.equal(dg.status,201);
  const dc=JSON.parse(Buffer.from(dg.data.cashOpenPermit.split('.')[1],'base64url').toString('utf8'));
  const revokedAt=new Date(Date.now()-2*60_000);
  const revokedId=crypto.randomUUID();
  // Independent synthetic authorization history; the request JWT is unmodified.
  await prisma.authSession.create({data:{id:revokedId,companyId:d.user.companyId,userId:d.user.id,
    tokenFamily:crypto.randomUUID(),
    refreshTokenHash:crypto.randomBytes(32).toString('hex'),expiresAt:new Date(Date.now()+3600_000),
    revokedAt}});
  const oldPermit=issuer.issue({...dc,sessionId:revokedId,validFrom:validFrom.toISOString(),
    validUntil:new Date(validFrom.getTime()+48*3600_000).toISOString()});
  const deniedRevoked=await req('/cash/sessions/open',d.token,{...opening,clientSessionId:crypto.randomUUID(),
    openedAt:new Date(Date.now()-60_000).toISOString(),offlineOpenPermit:oldPermit});
  assert.equal(deniedRevoked.status,403);assert.equal(deniedRevoked.data.code,'CASH_OFFLINE_OPEN_AUTHORIZATION_REVOKED');
  assert.equal((await snapshot(d)).sessions.length,0);
  evidence.scenarios.push({name:'revoked-historical-permit-denied-with-current-valid-jwt',http:403,sessions:0});
  const e=await business('CloseNotPerformed');
  const eo=await req('/cash/sessions/open',e.token,{openingAmount:0});
  assert.equal(eo.status,201);
  const eBefore=await snapshot(e);
  const eReview=await req('/recovery/reviews',e.token,{sourceActionId:`not-sent-close-${run}`,
    actionType:'cash.close',operationId:eo.data.shiftId,originalSessionId:eo.data.shiftId,
    expectedAmount:0,payloadSummary:{sessionId:eo.data.shiftId,closingAmount:0}});
  assert.equal(eReview.status,201);
  const eCheck=await req(`/recovery/reviews/${eReview.data.id}/verify`,e.token,{});
  assert.equal(eCheck.data.verification,'NOT_FOUND');
  const eDecision=await req(`/recovery/reviews/${eReview.data.id}/decision`,e.token,{decision:'NOT_PERFORMED',
    expectedVersion:1,note:'Synthetic evidence: this close was never submitted'});
  assert.equal(eDecision.data.status,'RESOLVED_NOT_PERFORMED');assert.equal(eDecision.data.financiallyConfirmed,false);
  const eAfter=await snapshot(e);
  assert.equal(eAfter.sessions[0].status,'OPEN');assert.equal(eAfter.movements.length,0);assert.equal(eAfter.sales,0);
  evidence.closeNotPerformed={before:eBefore,after:eAfter};
  evidence.scenarios.push({name:'administrative-rejected-close-resolution-keeps-the-original-session-open',caseId:eReview.data.id});
  await fs.writeFile(path.join(dir,`api-closing-${run}.json`),JSON.stringify(evidence,null,2));
  console.log(`PASS: ${evidence.scenarios.length} local closing scenarios; 1 movement, 2 retained cases, 4 audit events; foreign tenant unchanged.`);
}
main().catch(error=>{console.error(error instanceof assert.AssertionError?error.message:'Local acceptance failed; inspect guarded laboratory logs.');process.exitCode=1;}).finally(()=>prisma.$disconnect());
