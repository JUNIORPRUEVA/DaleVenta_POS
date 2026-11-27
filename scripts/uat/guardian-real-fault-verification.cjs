require('reflect-metadata');
const assert = require('node:assert/strict');
const { createServer } = require('node:http');
const { randomBytes, randomUUID } = require('node:crypto');
const { mkdtemp, mkdir, readdir, readFile, writeFile } = require('node:fs/promises');
const { join } = require('node:path');
const { tmpdir } = require('node:os');
const { execFileSync } = require('node:child_process');
const { Controller, Get, Module, UseGuards, UnauthorizedException, BadRequestException } = require('@nestjs/common');
const { NestFactory } = require('@nestjs/core');
const { JwtService } = require('@nestjs/jwt');
const { PrismaClient } = require('@prisma/client');
const { GlobalExceptionFilter } = require('../../apps/api/src/common/filters/global-exception.filter.ts');
const { GuardianBackendCaptureService } = require('../../apps/api/src/guardian/guardian.backend-capture.service.ts');
const { GuardianAlertService } = require('../../apps/api/src/guardian/guardian.alert.service.ts');
const { GuardianDiagnosisService } = require('../../apps/api/src/guardian/guardian.diagnosis.service.ts');
const { GuardianToolsService } = require('../../apps/api/src/guardian/guardian.tools.service.ts');
const { CrmGuardianAiProvider } = require('../../apps/api/src/guardian/ai/crm-guardian-ai.provider.ts');
const { GuardianPlatformService } = require('../../apps/api/src/guardian/guardian.platform.service.ts');
const { GuardianIncidentsService } = require('../../apps/api/src/guardian/guardian.incidents.service.ts');

const container = 'fullpos_guardian_fault_verify_20261127';
const database = 'postgresql://postgres@127.0.0.1:14671/guardian_fault_verification_test?connection_limit=2&pool_timeout=2&connect_timeout=2';
let app, prisma, receiver, tools, databaseStopped = false;
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, timeout = 15000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { try { if (await check()) return; } catch {} await wait(200); }
  throw new Error('Timed out waiting for verification evidence');
}
function docker(...args) { execFileSync('docker', args, {stdio:'pipe',timeout:20000}); }

(async () => {
  assert.equal(execFileSync('docker',['port',container,'5432/tcp'],{encoding:'utf8'}).trim(),'127.0.0.1:14671','Requires the dedicated loopback test container');
  const directory = await mkdtemp(join(tmpdir(),'guardian-real-fault-'));
  const marker = `guardian-real-fault-${randomUUID()}`;
  Object.assign(process.env, {
    NODE_ENV:'production', GUARDIAN_PROCESS_ROLE:'api', GUARDIAN_ENABLED:'true', GUARDIAN_INGEST_ENABLED:'true',
    GUARDIAN_BACKEND_CAPTURE_ENABLED:'true', GUARDIAN_ALERTS_ENABLED:'true', GUARDIAN_DIAGNOSIS_ENABLED:'true',
    GUARDIAN_OUTBOX_DIR:directory, GUARDIAN_ALERT_RECIPIENT:'18095550000', GUARDIAN_AI_PROVIDER:'crm',
    GUARDIAN_CRM_BRIDGE_TOKEN:'synthetic-local-service-verification',
    GUARDIAN_READER_DATABASE_URL:'postgresql://guardian_fault_reader@127.0.0.1:14671/guardian_fault_verification_test',
  });
  delete process.env.GUARDIAN_ALERT_RECIPIENTS;
  const received = [];
  let failNextNotice = true, aiCalls = 0;
  receiver = createServer(async (req,res) => {
    let body=''; for await(const part of req) body += part;
    res.setHeader('content-type','application/json');
    if (req.url.includes('/diagnose')) { aiCalls++; res.statusCode=503; res.end('{"ok":false}'); return; }
    if (failNextNotice) { failNextNotice=false; res.statusCode=503; res.end('{"ok":false}'); return; }
    received.push(JSON.parse(body)); res.end(JSON.stringify({id:`local-${marker}-${received.length}`}));
  });
  await new Promise(resolve => receiver.listen(0,'127.0.0.1',resolve));
  const receiverUrl = `http://127.0.0.1:${receiver.address().port}`;
  process.env.GUARDIAN_CRM_BASE_URL=receiverUrl;
  prisma = new PrismaClient({datasources:{db:{url:database}}}); await prisma.$connect();
  const a = await prisma.company.create({data:{name:'Verificación HTTP A',slug:`${marker}-a`,guardianEnabled:true}});
  const b = await prisma.company.create({data:{name:'Verificación HTTP B',slug:`${marker}-b`,guardianEnabled:true}});
  const scope={companyId:{in:[a.id,b.id]}};
  const alertScope={incident:scope};
  assert.equal(await prisma.guardianIncident.count({where:scope}),0);
  const alerts = new GuardianAlertService(prisma,{enqueueWhatsAppRawText:async()=>{throw new Error('External sending forbidden');}});
  alerts.buildChannels=()=>[{name:'local_verification_receiver',isConfigured:()=>true,send:async payload=>{
    const response=await fetch(`${receiverUrl}/notice`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});
    if(!response.ok)return {ok:false,httpStatus:response.status,error:'Local receptor unavailable',classification:'transient'};
    const result=await response.json();return {ok:true,httpStatus:200,providerMessageId:result.id,acceptance:'accepted'};
  }}];
  const capture = new GuardianBackendCaptureService(prisma,alerts);
  const jwt = new JwtService({secret:randomBytes(32).toString('hex')});
  class VerificationIdentityGuard {
    canActivate(context) {
      const request=context.switchToHttp().getRequest();
      try {
        const claims=jwt.verify(String(request.headers.authorization || '').replace(/^Bearer /,''));
        if(![a.id,b.id].includes(claims.companyId))throw new Error();
        request.user={companyId:claims.companyId};return true;
      } catch {throw new UnauthorizedException('Local verification requires signed identity');}
    }
  }
  class VerificationController {
    failure() { throw new Error('Controlled HTTP runtime failure'); }
    otherFailure() { throw new TypeError('Controlled independent runtime failure'); }
    async databaseDown() { return {count:await prisma.company.count()}; }
    expectedValidation() { throw new BadRequestException('Expected validation rejection'); }
    healthy() { return {ok:true}; }
  }
  Controller('verification')(VerificationController); UseGuards(VerificationIdentityGuard)(VerificationController);
  for(const [method,path] of Object.entries({failure:'failure',otherFailure:'other-failure',databaseDown:'database-down',expectedValidation:'validation',healthy:'healthy'})) {
    Get(path)(VerificationController.prototype,method,Object.getOwnPropertyDescriptor(VerificationController.prototype,method));
  }
  class VerificationModule {}
  Module({controllers:[VerificationController],providers:[{provide:VerificationIdentityGuard,useValue:new VerificationIdentityGuard()},{provide:GuardianBackendCaptureService,useValue:capture}]})(VerificationModule);
  app=await NestFactory.create(VerificationModule,{logger:false});
  app.use((req,_res,next)=>{req.requestId=`verification-${randomUUID()}`;next();});
  app.useGlobalFilters(new GlobalExceptionFilter());
  await app.listen(0,'127.0.0.1'); const api=await app.getUrl();
  const tokens={a:jwt.sign({companyId:a.id}),b:jwt.sign({companyId:b.id})};
  const request=(path,company='a')=>fetch(`${api}/verification/${path}`,{headers:{authorization:`Bearer ${tokens[company]}`}});
  const start=Date.now();
  const failures=await Promise.all([request('failure?token=synthetic-query-not-to-store'),request('other-failure'),request('failure','b')]);
  assert(failures.every(response=>response.status===500));
  await until(async()=>await prisma.guardianIncident.count({where:scope})===3);
  assert.equal((await request('failure')).status,500);
  assert.equal((await request('validation')).status,400);
  assert.equal((await fetch(`${api}/verification/failure`)).status,401);
  assert.equal((await request('healthy')).status,200);
  await wait(300);
  assert.equal(await prisma.guardianIncident.count({where:scope}),3,'Duplicate/validation/unauthorized calls must not add incidents');
  const incidents=await prisma.guardianIncident.findMany({where:scope,orderBy:{receivedAt:'asc'}});
  assert.equal(incidents.filter(row=>row.companyId===a.id).length,2);
  assert.equal(incidents.filter(row=>row.companyId===b.id).length,1);
  assert(!JSON.stringify(incidents).includes('synthetic-query-not-to-store'));
  tools = new GuardianToolsService(prisma);
  const diagnosis = new GuardianDiagnosisService(prisma,tools,new CrmGuardianAiProvider());
  await diagnosis.diagnose(incidents[0].id);
  assert.equal(aiCalls,1);
  assert.equal(await prisma.guardianDiagnosis.count({where:{incidentId:incidents[0].id,status:'DONE'}}),0);
  const firstDispatch=await alerts.processDue(10);
  assert.equal(firstDispatch.sent,2);assert.equal(firstDispatch.failed,1);
  const pending=await prisma.guardianAlert.findFirstOrThrow({where:{...alertScope,state:'PENDING'}});
  assert(pending.nextAttemptAt.getTime()>Date.now());
  const secondDispatch=await alerts.processDue(10,new Date(pending.nextAttemptAt.getTime()+1000));
  assert.equal(secondDispatch.sent,1);assert.equal(received.length,3);
  const accepted=await prisma.guardianAlert.findMany({where:alertScope});
  assert(accepted.every(row=>row.state==='ACCEPTED' && row.deliveredAt===null));
  await alerts.processDue(10,new Date(Date.now()+120000));assert.equal(received.length,3);
  await alerts.markDelivery(accepted[0].providerMessageId,'delivered');
  const platform=new GuardianPlatformService(prisma,new GuardianIncidentsService(prisma));
  const detail=await platform.detail(accepted[0].incidentId);
  assert.equal(detail.alerts[0].state,'DELIVERED');
  const detectionElapsedMs=Date.now()-start;
  // Interrupt only the disposable PostgreSQL created specifically for this verification.
  docker('stop','--time','1',container);databaseStopped=true;
  const databaseFailure=await request('database-down');assert.equal(databaseFailure.status,500);
  const healthyWhileDbDown=await request('healthy');assert.equal(healthyWhileDbDown.status,200);
  await until(async()=> (await readdir(join(directory,'backend'))).filter(file=>file.endsWith('.json')).length>0);
  const retainedDuringOutage=(await readdir(join(directory,'backend'))).filter(file=>file.endsWith('.json')).length;
  assert(retainedDuringOutage>0);
  let persistedRetryAttemptsDuringDbOutage=0;
  await until(async()=>{
    const files=(await readdir(join(directory,'backend'))).filter(file=>file.endsWith('.json'));
    const entries=await Promise.all(files.map(async file=>JSON.parse(await readFile(join(directory,'backend',file),'utf8'))));
    persistedRetryAttemptsDuringDbOutage=Math.max(0,...entries.map(entry=>entry.attempts));
    return persistedRetryAttemptsDuringDbOutage>0;
  });
  docker('start',container);databaseStopped=false;
  // Do not call capture/flush manually: the real capture service's periodic retry must recover it.
  await until(async()=>await prisma.guardianIncident.count({where:scope})===4,25000);
  const databaseIncident=await prisma.guardianIncident.findFirstOrThrow({where:{...scope,operation:{contains:'database-down'}}});
  assert.equal(databaseIncident.companyId,a.id);
  await until(async()=>await prisma.guardianAlert.count({where:{incidentId:databaseIncident.id}})===1);
  await alerts.processDue(10,new Date(Date.now()+120000));assert.equal(received.length,4);
  const evidence={verification:'Real HTTP exceptions and actual isolated PostgreSQL outage',productionTouched:false,externalMessages:0,externalAiCalls:0,
    automaticGlobalFilterCapture:true,directCaptureCalls:0,runtimeFailuresPersisted:3,companiesIsolated:2,duplicateSuppressed:true,
    expectedValidationNotAlerted:true,unauthenticatedRequestNotAttributed:true,queryRedacted:true,actualAiHttp503Observed:true,
    urgentAlertsWorkedWithoutAi:true,actualNotificationHttp503Retried:true,noDuplicateAfterRetry:true,acceptanceNotDelivery:true,
    deliveryReceiptReflectedInPlatform:true,actualDatabaseStoppedAndRestarted:true,healthyEndpointSurvivedDatabaseOutage:true,
    spoolFilesRetainedDuringOutage:retainedDuringOutage,persistedRetryAttemptsDuringDbOutage,databaseFaultRecoveredAutomatically:true,manualCaptureOrFlushCalls:0,totalIncidentsPersisted:4,totalLocalNotices:4,
    initialVerificationElapsedMs:detectionElapsedMs,evidenceDirectory:directory};
  await mkdir(join(__dirname,'../../.uat'),{recursive:true});
  await writeFile(join(__dirname,'../../.uat/guardian-real-fault-verification.json'),JSON.stringify(evidence,null,2));
  console.log(JSON.stringify(evidence,null,2));
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{
  if(databaseStopped){try{docker('start',container);}catch{}}
  await app?.close();await tools?.onModuleDestroy();await prisma?.$disconnect();
  if(receiver)await new Promise(resolve=>receiver.close(resolve));
});
