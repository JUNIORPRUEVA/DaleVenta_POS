import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { GuardianBackendCaptureService } from './guardian.backend-capture.service';
import { GuardianDurableOutbox } from './guardian.durable-outbox';

describe('durable backend Guardian capture', () => {
  const original = {...process.env};
  let directory: string;
  let prisma: any;
  let alerts: any;
  const event = (companyId='company-a',path='/audit/one') => ({companyId,path,method:'GET',status:500,message:'Synthetic',exceptionType:'AuditError'});
  beforeEach(async()=>{
    directory = await mkdtemp(join(tmpdir(),'guardian-capture-'));
    process.env.GUARDIAN_OUTBOX_DIR=directory;
    process.env.GUARDIAN_BACKEND_CAPTURE_ENABLED='true';
    prisma = {company:{findUnique:jest.fn(async()=>({guardianEnabled:true}))},guardianIncident:{findUnique:jest.fn(async()=>null),create:jest.fn(async()=>({id:'incident'}))}};
    alerts = {planForIncident:jest.fn(async()=>({created:true}))};
  });
  afterEach(async()=>{process.env={...original};await rm(directory,{recursive:true,force:true});});
  const capture = async(service:GuardianBackendCaptureService,...events:any[])=>{
    for(const value of events) (service as any).capture(value);
    await (service as any).outbox['writes'];
    await service.flush();
  };
  it('keeps concurrent failures and isolates company dedupe',async()=>{
    const service=new GuardianBackendCaptureService(prisma,alerts);
    await capture(service,event(),event('company-a','/audit/two'),event('company-b'));
    expect(prisma.guardianIncident.create).toHaveBeenCalledTimes(3);
    expect(alerts.planForIncident).toHaveBeenCalledTimes(3);
    expect((await readdir(join(directory,'backend'))).filter(f=>f.endsWith('.json'))).toHaveLength(0);
  });
  it('does not write incidents or send alerts for opted-out companies',async()=>{
    prisma.company.findUnique.mockResolvedValue({guardianEnabled:false});
    await capture(new GuardianBackendCaptureService(prisma,alerts),event());
    expect(prisma.guardianIncident.create).not.toHaveBeenCalled();
    expect(alerts.planForIncident).not.toHaveBeenCalled();
  });
  it('never stores query credentials or reports expected business rejections as infrastructure failures',async()=>{
    const service=new GuardianBackendCaptureService(prisma,alerts);
    await capture(service,{...event('company-a','/api/v1/sales?token=synthetic-private-query'),message:'Synthetic safe error'});
    expect(JSON.stringify(prisma.guardianIncident.create.mock.calls)).not.toContain('synthetic-private-query');
    prisma.guardianIncident.create.mockClear();
    await capture(service,{...event(),message:'Stock insuficiente para el producto',prismaCode:'P2002'});
    expect(prisma.guardianIncident.create).not.toHaveBeenCalled();
  });
  it('retains DB failures across service recreation and sends the original event exactly once',async()=>{
    prisma.company.findUnique.mockRejectedValue(new Error('DB down'));
    await capture(new GuardianBackendCaptureService(prisma,alerts),event());
    expect((await readdir(join(directory,'backend'))).filter(f=>f.endsWith('.json'))).toHaveLength(1);
    prisma.company.findUnique.mockResolvedValue({guardianEnabled:true});
    const now=Date.now(); jest.spyOn(Date,'now').mockReturnValue(now+10_000);
    try {await new GuardianBackendCaptureService(prisma,alerts).flush();}
    finally {jest.restoreAllMocks();}
    expect(prisma.guardianIncident.create).toHaveBeenCalledTimes(1);
    expect(prisma.guardianIncident.create.mock.calls[0][0].data.occurredAt.getTime()).toBeLessThanOrEqual(now);
    expect(alerts.planForIncident).toHaveBeenCalledTimes(1);
  });
  it('retries an alert planning failure without duplicating the persisted incident',async()=>{
    alerts.planForIncident.mockRejectedValueOnce(new Error('worker DB unavailable'));
    await capture(new GuardianBackendCaptureService(prisma,alerts),event());
    prisma.guardianIncident.findUnique.mockResolvedValue({id:'incident'});
    jest.spyOn(Date,'now').mockReturnValue(Date.now()+10_000);
    try {await new GuardianBackendCaptureService(prisma,alerts).flush();}
    finally {jest.restoreAllMocks();}
    expect(prisma.guardianIncident.create).toHaveBeenCalledTimes(1);
    expect(alerts.planForIncident).toHaveBeenCalledTimes(2);
  });
  it('one blocked record does not block a healthy event; Retry-After survives restart',async()=>{
    const box=new GuardianDurableOutbox<{id:number}>(join(directory,'isolated'));
    await box.enqueue({id:1});await box.enqueue({id:2});
    const deliver=jest.fn(async(value:{id:number})=>{if(value.id===1)throw Object.assign(new Error('429'),{retryAfterMs:3600_000});});
    await box.flush(deliver);
    expect(deliver).toHaveBeenCalledTimes(2);
    const next=jest.fn(async()=>{});
    await new GuardianDurableOutbox(join(directory,'isolated')).flush(next);
    expect(next).not.toHaveBeenCalled();
    expect((await readdir(join(directory,'isolated'))).filter(f=>f.endsWith('.json'))).toHaveLength(1);
  });
});
