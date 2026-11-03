import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import { E32SandboxService, type E32TrialAuthorization } from "../sandbox/e32-sandbox.service";
import { E32_SANDBOX_URL, E32_SYNTHETIC_ADDRESS, type E32TrialManifest, type E32TrialFacts } from "../sandbox/e32-sandbox.policy";
import type { E32TrialWire, E32WireRequest } from "../sandbox/e32-sandbox.wire";

const uat=process.env.ECF_POSTGRES_UAT==="true"?describe:describe.skip;
uat("E32 first trial PostgreSQL with MOCK_ONLY wire, no real emission",()=>{
  let prisma:PrismaService,service:E32SandboxService;const actor=randomUUID();
  const facts:E32TrialFacts={worktree:true,database:true,schema:true,company:true,secretProtected:true,secretRefConfigured:true,transport:true,
    environment:"sandbox",baseUrl:E32_SANDBOX_URL,allSwitchesOff:true,noPreviousTrial:true,noNumberCollision:true,actorAuthorized:true};
  beforeAll(async()=>{
    if(!isEcfLocalTarget()||process.env.ALANUBE_ENABLE_REAL_CALLS!=="false")throw Error("E32_UAT_REFUSED");
    prisma=new PrismaService();await prisma.$connect();service=new E32SandboxService(prisma);
  });
  afterAll(async()=>{await prisma?.$disconnect();});
  async function fixture(primary=false){
    const companyId=randomUUID();await prisma.company.create({data:{id:companyId,name:"Synthetic MOCK_ONLY first E32 trial",slug:`ecf-e32-trial-${companyId}`}});
    const user={id:actor,companyId,role:"ADMIN"};
    const manifest:E32TrialManifest={version:1,mode:"MOCK_ONLY",clientRequestId:randomUUID(),issueDate:new Date().toISOString().slice(0,10),
      sender:{legalName:"SYNTHETIC MOCK COMPANY",taxId:"101000001",address:"Synthetic test address"},metadata:{alanubeCompanyId:"01FVJ1528AQRBC7D6K2TGVE5S5",encf:"E320000000001",paymentType:1,incomeType:1},
      companyAuthorizationRef:"mock://not-real-provider-authorization",numbering:{from:"E320000000001",to:"E320000000099",validUntil:new Date().toISOString().slice(0,10),authorizationRef:"mock://not-a-real-range"}};
    if(primary){manifest.companyTarget="TOKEN_PRIMARY";delete manifest.metadata.alanubeCompanyId;}
    const trial=await service.prepare(user,manifest,facts);
    const grant:E32TrialAuthorization={manifestFingerprint:trial.manifestFingerprint,actorId:actor,expiresAt:new Date(Date.now()+60000).toISOString(),maxPosts:1,maxQueries:1,approvalReference:"mock://not-real-consent"};
    return {user,manifest,trial,grant};
  }
  function wire(manifest:E32TrialManifest,options:{http?:number;timeout?:boolean;wrongId?:boolean;get404?:boolean;wrongCompany?:boolean;fixedId?:string;omitCompany?:boolean;bodyChange?:Record<string,unknown>}={}){
    const calls:E32WireRequest[]=[];const id=options.fixedId??("0"+randomUUID().replace(/-/g,"").slice(0,25).toUpperCase());
    const port:E32TrialWire={mode:"MOCK_ONLY",async execute(input){calls.push(input);
      if(options.timeout)return {ok:false,errorCode:"TIMEOUT",safeMessage:"synthetic timeout",requestId:input.requestId};
      return {ok:true,response:{statusCode:input.method==="POST"?(options.http??201):(options.get404?404:200),headers:{},requestId:input.requestId,
        body:options.get404&&input.method==="GET"?{}:{id:options.wrongId?"unknown":id,status:"FINISHED",legalStatus:"ACCEPTED",sequenceConsumed:true,...(options.omitCompany?{}:{companyIdentification:options.wrongCompany?"101000002":manifest.sender.taxId}),documentNumber:manifest.metadata.encf,...options.bodyChange}}};
    }};return {port,calls};
  }
  it("preparation is stable and divergent metadata conflicts",async()=>{
    const f=await fixture();expect((await service.prepare(f.user,f.manifest,facts)).id).toBe(f.trial.id);
    await expect(service.prepare(f.user,{...f.manifest,metadata:{...f.manifest.metadata,encf:"E320000000002"}},facts)).rejects.toThrow("E32_TRIAL_DIVERGENT_MANIFEST");
  });
  it("rejects synthetic-address selection on another tenant even with forged ready facts",async()=>{
    const f=await fixture();
    f.manifest.mode="SANDBOX";f.manifest.companyTarget="TOKEN_PRIMARY";delete f.manifest.metadata.alanubeCompanyId;
    f.manifest.sender={legalName:"FULLTECH",taxId:"132109122",address:E32_SYNTHETIC_ADDRESS};
    f.manifest.syntheticAddressTest={purpose:"SYNTHETIC_SANDBOX_ONLY",tenantCompanyId:f.user.companyId,authorizationRef:"synthetic-only",providerVerified:false};
    await expect(service.prepare(f.user,f.manifest,{...facts,syntheticAddressAllowed:true})).rejects.toThrow("E32_SYNTHETIC_ADDRESS_SCOPE_REFUSED");
    expect(await prisma.ecfSandboxE32Trial.count({where:{companyId:f.user.companyId,slot:"FIRST_E32_SANDBOX"}})).toBe(0);
  });
  it("one mock POST plus official company-scoped GET, never fiscal acceptance",async()=>{
    const f=await fixture(),w=wire(f.manifest);expect(await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port)).toMatchObject({canRetryPost:false,remoteIdObserved:true});
    expect(w.calls.map(x=>x.method)).toEqual(["POST","GET"]);expect(w.calls[1].path).toContain(`/idCompany/${f.manifest.metadata.alanubeCompanyId}`);
    expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}})).toMatchObject({status:"HUMAN_REVIEW_REQUIRED",fiscalSnapshot:null});
    expect(await prisma.ecfEvidenceReceipt.findMany({where:{companyId:f.user.companyId,documentId:f.trial.documentId}})).toEqual([expect.objectContaining({trustLevel:"SYNTHETIC"})]);
  });
  it("simultaneous operators have only one POST winner",async()=>{
    const f=await fixture(),w=wire(f.manifest);const results=await Promise.allSettled(Array.from({length:4},()=>service.runOnce(f.user,f.trial.id,f.grant,facts,w.port)));
    expect(results.filter(x=>x.status==="fulfilled")).toHaveLength(1);expect(w.calls.filter(x=>x.method==="POST")).toHaveLength(1);
  });
  it("primary company without response RNC uses GET by id and requires fiscal review",async()=>{
    const f=await fixture(true),w=wire(f.manifest,{omitCompany:true});
    const result=await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    expect(result).toMatchObject({remoteIdObserved:true,canRetryPost:false,queryObservation:{consistent:true,canUpdateFiscalStatus:false}});
    expect(w.calls).toHaveLength(2);expect(w.calls[1].path).toMatch(/^\/invoices\/[0-7][0-9A-HJKMNP-TV-Z]{25}$/);
    expect(w.calls[0].body).not.toHaveProperty("company");
    expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}})).toMatchObject({status:"HUMAN_REVIEW_REQUIRED",fiscalSnapshot:null});
  });
  it("timeout consumes latch and restart cannot issue again",async()=>{
    const f=await fixture(),w=wire(f.manifest,{timeout:true});await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    await expect(new E32SandboxService(prisma).runOnce(f.user,f.trial.id,f.grant,facts,w.port)).rejects.toThrow();
    expect(w.calls).toHaveLength(1);expect(await prisma.ecfSandboxE32Trial.findFirst({where:{companyId:f.user.companyId,id:f.trial.id}})).toMatchObject({state:"UNKNOWN_RESULT"});
  });
  it.each([200,400,401,422,500])("HTTP %s never accepts or retries and does not query without correlated 201",async(http)=>{
    const f=await fixture(),w=wire(f.manifest,{http});await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    expect(w.calls).toHaveLength(1);expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}})).toMatchObject({status:"UNKNOWN_RESULT"});
  });
  it("unknown remote id or wrong company does not bind/query",async()=>{
    for(const options of [{wrongId:true},{wrongCompany:true}]){const f=await fixture(),w=wire(f.manifest,options);await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);expect(w.calls).toHaveLength(1);
      expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}})).toMatchObject({externalProviderId:null});}
  });
  it("GET 404 preserves unknown and records quarantine observation",async()=>{
    const f=await fixture(),w=wire(f.manifest,{get404:true});await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    expect(await prisma.ecfSandboxE32TrialEvent.findMany({where:{companyId:f.user.companyId,trialId:f.trial.id,kind:"GET_OBSERVATION"}})).toEqual([expect.objectContaining({httpStatus:404,safeCode:"E32_QUERY_REQUIRES_REVIEW"})]);
  });
  it("another tenant or nonadmin cannot use a trial",async()=>{
    const f=await fixture(),other=await fixture(),w=wire(f.manifest);
    await expect(service.runOnce(other.user,f.trial.id,f.grant,facts,w.port)).rejects.toThrow("E32_TRIAL_NOT_FOUND");
    await expect(service.runOnce({...f.user,role:"CAJERO"},f.trial.id,f.grant,facts,w.port)).rejects.toThrow("E32_TRIAL_ADMIN_REQUIRED");expect(w.calls).toHaveLength(0);
  });
  it("tampered/expired consent or incomplete readiness cannot call the wire",async()=>{
    const f=await fixture(),w=wire(f.manifest);
    await expect(service.runOnce(f.user,f.trial.id,{...f.grant,manifestFingerprint:"a".repeat(64)},facts,w.port)).rejects.toThrow();
    await expect(service.runOnce(f.user,f.trial.id,{...f.grant,expiresAt:"2000-01-01"},facts,w.port)).rejects.toThrow();
    await expect(service.runOnce(f.user,f.trial.id,f.grant,{...facts,company:false},w.port)).rejects.toThrow();expect(w.calls).toHaveLength(0);
  });
  it("mock operation cannot be sent with a real-mode wire",async()=>{
    const f=await fixture(),w=wire(f.manifest);await expect(service.runOnce(f.user,f.trial.id,f.grant,facts,{...w.port,mode:"SANDBOX"})).rejects.toThrow();expect(w.calls).toHaveLength(0);
  });
  it("claim and history cannot be reset, altered or deleted",async()=>{
    const f=await fixture(),w=wire(f.manifest,{timeout:true});await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    await expect(prisma.ecfSandboxE32Trial.updateMany({where:{companyId:f.user.companyId,id:f.trial.id},data:{state:"PREPARED"}})).rejects.toThrow();
    await expect(prisma.ecfSandboxE32Trial.updateMany({where:{companyId:f.user.companyId,id:f.trial.id},data:{payloadFingerprint:"a".repeat(64)}})).rejects.toThrow();
    await expect(prisma.ecfSandboxE32Trial.deleteMany({where:{companyId:f.user.companyId,id:f.trial.id}})).rejects.toThrow();
    await expect(prisma.ecfSandboxE32TrialEvent.deleteMany({where:{companyId:f.user.companyId,trialId:f.trial.id}})).rejects.toThrow();
  });
  it("global slot collisions roll back test rows while preserving any historical trial",async()=>{
    const a=await fixture(),b=await fixture();
    await expect(prisma.$transaction(async tx=>{
      for(const f of [a,b]) {
        const document=await tx.ecfElectronicDocument.create({data:{companyId:f.user.companyId,documentType:"E32",payloadFingerprint:f.trial.payloadFingerprint,idempotencyKey:`test:${randomUUID()}`}});
        await tx.ecfSandboxE32Trial.create({data:{companyId:f.user.companyId,documentId:document.id,slot:"FIRST_E32_SANDBOX",mode:"SANDBOX",
          manifest:f.trial.manifest!,manifestFingerprint:f.trial.manifestFingerprint,payload:f.trial.payload!,payloadFingerprint:f.trial.payloadFingerprint}});
      }
    })).rejects.toMatchObject({code:"P2002",meta:{target:["slot"]}});
    for (const f of [a,b])
      expect(await prisma.ecfSandboxE32Trial.count({where:{companyId:f.user.companyId,slot:"FIRST_E32_SANDBOX"}})).toBe(0);
  });
  it("recovers a crash after claim without restoring permission to POST",async()=>{
    const f=await fixture(),w=wire(f.manifest);
    await prisma.ecfSandboxE32Trial.updateMany({where:{companyId:f.user.companyId,id:f.trial.id},data:{state:"CLAIMED"}});
    await prisma.ecfElectronicDocument.updateMany({where:{companyId:f.user.companyId,id:f.trial.documentId},data:{status:"SEND_IN_PROGRESS"}});
    await new E32SandboxService(prisma).recoverClaimed(f.user,f.trial.id);
    await service.recoverClaimed(f.user,f.trial.id);
    await expect(service.runOnce(f.user,f.trial.id,f.grant,facts,w.port)).rejects.toThrow();expect(w.calls).toHaveLength(0);
    expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}})).toMatchObject({status:"UNKNOWN_RESULT",safeErrorCode:"PROCESS_RESTART"});
  });
  it("database rejects a trial/document cross-tenant reference",async()=>{
    const f=await fixture(),other=randomUUID();await prisma.company.create({data:{id:other,name:"Synthetic FK fixture",slug:`ecf-e32-trial-${other}`}});
    await expect(prisma.ecfSandboxE32Trial.create({data:{companyId:other,documentId:f.trial.documentId,mode:"MOCK_ONLY",slot:`MOCK_ONLY:${other}`,
      manifest:f.trial.manifest!,manifestFingerprint:f.trial.manifestFingerprint,payload:f.trial.payload!,payloadFingerprint:f.trial.payloadFingerprint}})).rejects.toMatchObject({code:"P2003"});
  });
  it("does not bind a response id already associated with another local document",async()=>{
    const f=await fixture(),id="0"+randomUUID().replace(/-/g,"").slice(0,25).toUpperCase(),w=wire(f.manifest,{fixedId:id});
    await prisma.ecfElectronicDocument.create({data:{companyId:f.user.companyId,documentType:"E32",idempotencyKey:`test:${randomUUID()}`,
      payloadFingerprint:"a".repeat(64),externalProviderId:id,externalDocumentNumber:"E320000000002"}});
    expect(await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port)).toMatchObject({remoteIdObserved:true,remoteIdBound:false,canRetryPost:false});
    expect(w.calls).toHaveLength(1);expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}})).toMatchObject({externalProviderId:null,status:"UNKNOWN_RESULT"});
  });
  it("REGISTERED plus ACCEPTED persists an explicit provider observation, not UNKNOWN or DGII acceptance",async()=>{
    const f=await fixture(),w=wire(f.manifest,{bodyChange:{status:"REGISTERED"}});
    const result=await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    expect(result).toMatchObject({remoteIdBound:true,sequenceConsumed:true,assessment:{providerOutcome:"ACCEPTED",canUpdateFiscalStatus:false}});
    expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}}))
      .toMatchObject({status:"HUMAN_REVIEW_REQUIRED",safeErrorCode:"E32_OBSERVED_ACCEPTED",fiscalSnapshot:null});
    expect(await prisma.ecfElectronicDocumentStatusLog.findFirst({where:{companyId:f.user.companyId,documentId:f.trial.documentId,reasonCode:"E32_OBSERVED_ACCEPTED"}}))
      .toMatchObject({metadata:expect.objectContaining({providerOutcome:"ACCEPTED",sequenceConsumed:true})});
    await expect(service.runOnce(f.user,f.trial.id,f.grant,facts,w.port)).rejects.toThrow();
    expect(w.calls.filter(x=>x.method==="POST")).toHaveLength(1);
  });
  it.each([
    {sequenceConsumed:false}, {sequenceConsumed:undefined}, {documentNumber:"E320000000002"}, {stampDate:null},
  ])("invalid, incomplete or contradictory response stays unknown with diagnostic evidence %j",async bodyChange=>{
    const f=await fixture(),w=wire(f.manifest,{bodyChange});
    const result=await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    expect(result).toMatchObject({remoteIdBound:false,assessment:{providerOutcome:"UNKNOWN"}});
    expect(result.assessment.reasons.length).toBeGreaterThan(0);
    expect(w.calls).toHaveLength(1);
    expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}})).toMatchObject({status:"UNKNOWN_RESULT",externalProviderId:null});
    await expect(service.runOnce(f.user,f.trial.id,f.grant,facts,w.port)).rejects.toThrow();
  });
  it("records an explicit provider rejection for human review, never as fiscal acceptance or a released sequence",async()=>{
    const f=await fixture(),w=wire(f.manifest,{bodyChange:{legalStatus:"REJECTED"}});
    const result=await service.runOnce(f.user,f.trial.id,f.grant,facts,w.port);
    expect(result).toMatchObject({canRetryPost:false,remoteIdBound:true,sequenceConsumed:true,
      assessment:{providerOutcome:"REJECTED",canUpdateFiscalStatus:false,safeCode:"E32_OBSERVED_REJECTED"}});
    expect(await prisma.ecfElectronicDocument.findFirst({where:{companyId:f.user.companyId,id:f.trial.documentId}}))
      .toMatchObject({status:"HUMAN_REVIEW_REQUIRED",safeErrorCode:"E32_OBSERVED_REJECTED",fiscalSnapshot:null});
    await expect(service.runOnce(f.user,f.trial.id,f.grant,facts,w.port)).rejects.toThrow();
    expect(w.calls.filter(x=>x.method==="POST")).toHaveLength(1);
  });
});
