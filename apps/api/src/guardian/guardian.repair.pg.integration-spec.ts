import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { GuardianBackendCaptureService } from './guardian.backend-capture.service';
import { GuardianAlertService } from './guardian.alert.service';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianPlatformService } from './guardian.platform.service';
import { GuardianIncidentsService } from './guardian.incidents.service';

const url = process.env.GUARDIAN_UAT_DATABASE_URL || '';
(url ? describe : describe.skip)('Guardian repair: persisted PostgreSQL regressions',()=>{
  const original={...process.env};
  let prisma:PrismaClient,alerts:GuardianAlertService,directory:string;
  let companyA:string,companyB:string;
  beforeAll(async()=>{
    const target=new URL(url);
    if (!['127.0.0.1','localhost'].includes(target.hostname) || target.pathname !== '/guardian_repair_test') {
      throw new Error('This suite requires the isolated local guardian_repair_test database');
    }
    prisma=new PrismaClient({datasources:{db:{url}}});await prisma.$connect();
    process.env.GUARDIAN_ENABLED='true';process.env.GUARDIAN_BACKEND_CAPTURE_ENABLED='true';
    process.env.GUARDIAN_ALERTS_ENABLED='true';process.env.GUARDIAN_DIAGNOSIS_ENABLED='false';
    process.env.GUARDIAN_ALERT_RECIPIENT='18095550000';delete process.env.GUARDIAN_ALERT_RECIPIENTS;
    alerts=new GuardianAlertService(prisma as any,{enqueueWhatsAppRawText:()=>{throw new Error('External sending forbidden');}} as any);
    jest.spyOn(alerts as any,'buildChannels').mockReturnValue([{name:'isolated_test',isConfigured:()=>true,send:jest.fn(async()=>({ok:true,acceptance:'accepted',providerMessageId:`local-${randomUUID()}`}))}]);
  });
  beforeEach(async()=>{
    directory=await mkdtemp(join(tmpdir(),'guardian-pg-repair-'));process.env.GUARDIAN_OUTBOX_DIR=directory;
    companyA=(await prisma.company.create({data:{name:'Guardian repair A',slug:`guardian-repair-${randomUUID()}`,guardianEnabled:true}})).id;
    companyB=(await prisma.company.create({data:{name:'Guardian repair B',slug:`guardian-repair-${randomUUID()}`,guardianEnabled:true}})).id;
  });
  afterEach(async()=>{await rm(directory,{recursive:true,force:true});});
  afterAll(async()=>{jest.restoreAllMocks();await prisma?.$disconnect();process.env={...original};});
  const capture=async(service:GuardianBackendCaptureService,events:any[])=>{
    for(const event of events)(service as any).capture(event);
    await (service as any).outbox.writes;await service.flush();
  };
  const event=(companyId:string,path='/synthetic/one')=>({companyId,path,method:'POST',status:500,message:'Isolated error',exceptionType:'GuardianRepairRegression'});
  it('persists concurrent errors per company and sends urgent alerts without AI',async()=>{
    const before=await prisma.guardianIncident.count({where:{companyId:{in:[companyA,companyB]}}});expect(before).toBe(0);
    await capture(new GuardianBackendCaptureService(prisma as any,alerts),[event(companyA),event(companyA,'/synthetic/two'),event(companyB)]);
    const incidents=await prisma.guardianIncident.findMany({where:{companyId:{in:[companyA,companyB]}},include:{alerts:true,diagnoses:true}});
    expect(incidents).toHaveLength(3);expect(incidents.every(row=>row.alerts.length===1 && row.diagnoses.length===0)).toBe(true);
    const ids=await alerts.claimDue(100);
    for(const alert of ids) await alerts.attempt(alert.id);
    const accepted=await prisma.guardianAlert.findMany({where:{incidentId:{in:incidents.map(row=>row.id)}}});
    expect(accepted.every(row=>row.state==='ACCEPTED' && !row.deliveredAt)).toBe(true);
  });
  it('recovers an old incident without requiring a diagnosis or a recent date',async()=>{
    const incident=await prisma.guardianIncident.create({data:{eventId:randomUUID(),companyId:companyA,module:'backend',operation:'synthetic',fingerprint:'old-offline-recovery',severity:'SEV2',occurredAt:new Date(Date.now()-30*86400_000),receivedAt:new Date(Date.now()-30*86400_000)}});
    await alerts.planMissingAlerts(100);
    expect(await prisma.guardianAlert.count({where:{incidentId:incident.id}})).toBe(1);
    await alerts.planMissingAlerts(100);
    expect(await prisma.guardianAlert.count({where:{incidentId:incident.id}})).toBe(1);
  });
  it('does not ingest another company context or incidents for an opted-out company',async()=>{
    const ingest=new GuardianIngestService(prisma as any,new GuardianQuotaService(prisma as any),alerts);
    const id=randomUUID();
    const result=await ingest.ingestBatch({companyId:companyB,events:[{eventId:id,module:'sales',operation:'synthetic',severity:'SEV2',occurredAt:new Date().toISOString(),context:{_guardianCompanyId:companyA}}]});
    expect(result.results[0].reason).toBe('COMPANY_SCOPE_MISMATCH');expect(await prisma.guardianIncident.count({where:{eventId:id}})).toBe(0);
    await prisma.company.update({where:{id:companyA},data:{guardianEnabled:false}});
    await capture(new GuardianBackendCaptureService(prisma as any,alerts),[event(companyA)]);
    expect(await prisma.guardianIncident.count({where:{companyId:companyA}})).toBe(0);
  });
  it('a monitored company with zero incidents remains monitored in the actual platform projection',async()=>{
    const platform=new GuardianPlatformService(prisma as any,new GuardianIncidentsService(prisma as any));
    const row=(await platform.companies()).find(row=>row.id===companyA);
    expect(row?.monitored).toBe(true);expect(row?.openIncidents).toBe(0);
  });
});
