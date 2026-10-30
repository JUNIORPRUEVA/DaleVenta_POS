import { randomUUID } from "node:crypto";
import { e32Preflight, e32SyntheticAddressAllowed, E32_SYNTHETIC_ADDRESS, e32SandboxCompanyPrepared, e32ResponseIdentityMatches, firstE32Document, E32_SANDBOX_URL, type E32TrialManifest, type E32TrialFacts } from "./e32-sandbox.policy";
import { validateAlanubeE32QueryResponse } from "../alanube/alanube-schema-validator";
import { E32SandboxOneShotWire } from "./e32-sandbox.wire";
import { authenticateE32Operator } from "./e32-sandbox-operator";
import { JwtService } from "@nestjs/jwt";

const today = () => new Date().toISOString().slice(0,10);
const manifest = (): E32TrialManifest => ({ version:1, mode:"MOCK_ONLY", clientRequestId:randomUUID(), issueDate:today(),
  sender:{legalName:"SYNTHETIC SANDBOX FIXTURE",taxId:"101000001",address:"Synthetic test address"},
  metadata:{alanubeCompanyId:"01FVJ1528AQRBC7D6K2TGVE5S5",encf:"E320000000001",paymentType:1,incomeType:1},companyAuthorizationRef:"mock://not-provider-proof",
  numbering:{from:"E320000000001",to:"E320000000099",validUntil:today(),authorizationRef:"mock://not-an-authorized-range"} });
const facts = (): E32TrialFacts => ({worktree:true,database:true,schema:true,company:true,secretProtected:true,secretRefConfigured:true,transport:true,
  environment:"sandbox",baseUrl:E32_SANDBOX_URL,allSwitchesOff:true,noPreviousTrial:true,noNumberCollision:true,actorAuthorized:true});

describe("E32 operator authentication seam",()=>{
  const jwt=new JwtService({secret:"synthetic-test-only-secret"}),sub=randomUUID(),companyId=randomUUID();
  it("uses the existing validator's tenant rather than a company supplied by a file",async()=>{
    const validate=jest.fn(async()=>({id:sub,companyId,role:"ADMIN"}));
    const token=jwt.sign({sub,companyId:randomUUID(),tokenType:"access",sessionId:randomUUID()},{expiresIn:"5m"});
    expect(await authenticateE32Operator(token,sub,"synthetic-test-only-secret",validate)).toMatchObject({companyId});expect(validate).toHaveBeenCalledTimes(1);
  });
  it("rejects missing/bad/expired/refresh or mismatched actor tokens before database validation",async()=>{
    const validate=jest.fn(async()=>({id:sub,companyId,role:"ADMIN"}));
    const refresh=jwt.sign({sub,tokenType:"refresh",sessionId:randomUUID()},{expiresIn:"5m"});
    const expired=jwt.sign({sub,tokenType:"access",sessionId:randomUUID()},{expiresIn:-1});
    for(const token of [undefined,"malformed",refresh,expired])expect(await authenticateE32Operator(token,sub,"synthetic-test-only-secret",validate)).toBeNull();
    const token=jwt.sign({sub,tokenType:"access",sessionId:randomUUID()},{expiresIn:"5m"});
    expect(await authenticateE32Operator(token,randomUUID(),"synthetic-test-only-secret",validate)).toBeNull();expect(validate).not.toHaveBeenCalled();
  });
  it("preserves rejected sessions/licenses and nonadmin authorization",async()=>{
    const token=jwt.sign({sub,tokenType:"access",sessionId:randomUUID()},{expiresIn:"5m"});
    expect(await authenticateE32Operator(token,sub,"synthetic-test-only-secret",async()=>{throw Error("synthetic revoked session");})).toBeNull();
    expect(await authenticateE32Operator(token,sub,"synthetic-test-only-secret",async()=>({id:sub,companyId,role:"CAJERO"}))).toBeNull();
  });
});

describe("E32 offline preflight, synthetic facts only", () => {
  it("requires explicit synthetic address selection scoped to the authenticated tenant and isolated Sandbox",()=>{
    const m=manifest(),tenant={id:randomUUID(),slug:"fullpos-alanube-uat-access",name:"SYNTHETIC Fullpos Alanube UAT Access"};
    m.mode="SANDBOX";m.companyTarget="TOKEN_PRIMARY";delete m.metadata.alanubeCompanyId;
    m.sender={legalName:"FULLTECH",taxId:"132109122",address:E32_SYNTHETIC_ADDRESS};
    const runtime={APP_ENV:"uat",UAT_LOCAL_ONLY:"true",ALANUBE_ENV:"sandbox",DATABASE_URL:"postgresql://127.0.0.1:56550/fullpos_alanube_uat"};
    expect(e32SyntheticAddressAllowed(m,tenant,runtime)).toBe(false);
    expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
    m.syntheticAddressTest={purpose:"SYNTHETIC_SANDBOX_ONLY",tenantCompanyId:tenant.id,authorizationRef:"synthetic-test-selection",providerVerified:false};
    expect(e32SyntheticAddressAllowed(m,tenant,runtime)).toBe(true);
    expect(e32Preflight(m,{...facts(),syntheticAddressAllowed:true}).result).toBe("READY_FOR_AUTHORIZATION");
    for(const change of [{APP_ENV:"production"},{UAT_LOCAL_ONLY:"false"},{ALANUBE_ENV:"production"},{DATABASE_URL:"postgresql://remote.invalid:56550/fullpos_alanube_uat"},{DATABASE_URL:"postgresql://127.0.0.1:56550/fullpos_alanube_uat?host=remote"}])
      expect(e32SyntheticAddressAllowed(m,tenant,{...runtime,...change})).toBe(false);
    for(const change of [{id:randomUUID()},{slug:"real-company"},{name:"Real company"}])expect(e32SyntheticAddressAllowed(m,{...tenant,...change},runtime)).toBe(false);
    expect(e32Preflight(m,{...facts(),syntheticAddressAllowed:false}).result).toBe("BLOCKED");
    m.syntheticAddressTest.authorizationRef="";expect(e32SyntheticAddressAllowed(m,tenant,runtime)).toBe(false);
  });
  it("distinguishes disabled Sandbox preparation from certification and blocks onboarding or issuer conflicts",()=>{
    const m=manifest();m.companyTarget="TOKEN_PRIMARY";delete m.metadata.alanubeCompanyId;
    const config={environment:"SANDBOX",enabled:false,productionEnabled:false,certificationStatus:"NOT_STARTED",alanubeCompanyId:null,allowedTypes:["E32"]};
    expect(e32SandboxCompanyPrepared(config,m)).toBe(true);
    expect(config.certificationStatus).toBe("NOT_STARTED");
    for(const change of [{environment:"PRODUCTION"},{enabled:true},{productionEnabled:true},{certificationStatus:"BLOCKED"},{allowedTypes:["E34"]},{alanubeCompanyId:"01FVJ1528AQRBC7D6K2TGVE5S5"}])
      expect(e32SandboxCompanyPrepared({...config,...change},m)).toBe(false);
    expect(e32SandboxCompanyPrepared(null,m)).toBe(false);
  });
  it.each(["", "  ", "address", " ADDRESS "])("never treats placeholder address %s as ready",address=>{
    const m=manifest();m.sender.address=address;expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
  });
  it("requires explicit primary selection without fabricating a provider company id", () => {
    const m=manifest();delete m.metadata.alanubeCompanyId;
    expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
    m.companyTarget="TOKEN_PRIMARY";
    const report=e32Preflight(m,facts());
    expect(report.result).toBe("READY_FOR_AUTHORIZATION");expect(report.payload).not.toHaveProperty("company");
    m.metadata.alanubeCompanyId="01FVJ1528AQRBC7D6K2TGVE5S5";
    expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
  });
  it("correlates official responses without an undocumented required RNC and rejects contradictions", () => {
    const m=manifest(),body={documentNumber:m.metadata.encf};
    expect(e32ResponseIdentityMatches(body,m)).toBe(true);
    expect(e32ResponseIdentityMatches({...body,companyIdentification:"101000002"},m)).toBe(false);
    expect(e32ResponseIdentityMatches({...body,companyIdentification:null},m)).toBe(false);
    expect(e32ResponseIdentityMatches({documentNumber:"E320000000002"},m)).toBe(false);
  });
  it("can be locally ready without E34 rules and never grants authorization", () => {
    expect(e32Preflight(manifest(),facts())).toMatchObject({result:"READY_FOR_AUTHORIZATION",authorizationGranted:false,authenticatedRequests:0});
  });
  it("builds exact DOP 168.00, ITBIS 18.00 and exempt 50.00", () => {
    const m=manifest(), report=e32Preflight(m,facts());
    expect(report.payload?.totals).toMatchObject({totalAmount:168,itbisTotal:18,exemptAmount:50,totalTaxedAmount:100});
    expect(firstE32Document(m.sender,m.issueDate).type).toBe("E32");
  });
  it.each(["worktree","database","schema","company","secretProtected","secretRefConfigured","transport","allSwitchesOff","noPreviousTrial","noNumberCollision","actorAuthorized"] as const)("blocks critical local failure %s", key => {
    expect(e32Preflight(manifest(),{...facts(),[key]:false}).result).toBe("BLOCKED");
  });
  it("does not invent absent manifest/numbering/company", () => { expect(e32Preflight(null,facts()).result).toBe("BLOCKED"); });
  it("rejects wrong environment or URL", () => {
    expect(e32Preflight(manifest(),{...facts(),environment:"production"}).result).toBe("BLOCKED");
    expect(e32Preflight(manifest(),{...facts(),baseUrl:"https://api.alanube.co/dom/v1"}).result).toBe("BLOCKED");
  });
  it("rejects number outside the operator-attested range", () => {
    const m=manifest();m.metadata.encf="E320000000100";expect(e32Preflight(m,facts()).checks.NUMBERING_AUTHORIZATION).toBe(false);
  });
  it("rejects invalid/expired numbering and missing authorization", () => {
    const m=manifest();m.numbering.validUntil="2000-01-01";expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
    m.numbering.validUntil=today();m.numbering.authorizationRef="";expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
  });
  it("rejects a stale issue date and invalid RNC", () => {
    const m=manifest();m.issueDate="2000-01-01";expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
    m.issueDate=today();m.sender.taxId="invalid";expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
  });
  it("rejects unrecognized fields rather than persisting a token supplied in JSON", () => {
    const m={...manifest(),token:"synthetic-marker-not-a-secret"};expect(e32Preflight(m,facts()).result).toBe("BLOCKED");
  });
  it("GET validation uses the official GET schema, not the POST 201 schema", () => {
    expect(validateAlanubeE32QueryResponse(200,{id:"01FVJ1528AQRBC7D6K2TGVE5S5",status:"FINISHED",legalStatus:"ACCEPTED"}).ok).toBe(true);
    expect(validateAlanubeE32QueryResponse(200,{status:"INVENTED"}).ok).toBe(false);
    expect(validateAlanubeE32QueryResponse(201,{}).ok).toBe(false);
  });
});

describe("E32 single-use wire (fetch always mocked)", () => {
  const saved = {...process.env}; let fetchMock: jest.SpyInstance;
  const request = {method:"POST" as const,path:"/invoices",body:e32Preflight(manifest(),facts()).payload,requestId:"synthetic"};
  beforeEach(() => {
    Object.assign(process.env,{APP_ENV:"uat",UAT_LOCAL_ONLY:"true",DATABASE_URL:"postgresql://127.0.0.1:56550/fullpos_alanube_uat",ALANUBE_ENV:"sandbox",ALANUBE_BASE_URL:E32_SANDBOX_URL,ALANUBE_ENABLE_REAL_CALLS:"true",ECF_EMISSION_ENABLED:"true",ECF_ALANUBE_AUTH_TESTS_ENABLED:"false"});
    fetchMock=jest.spyOn(globalThis,"fetch").mockResolvedValue(new Response('{"id":"01FVJ1528AQRBC7D6K2TGVE5S5"}',{status:201}));
  });
  afterEach(() => {fetchMock.mockRestore();process.env={...saved};jest.useRealTimers();});
  it("does not resolve secrets or call fetch while disabled", async () => {
    process.env.ALANUBE_ENABLE_REAL_CALLS="false";const resolver=jest.fn(async()=>"synthetic-token");
    expect((await new E32SandboxOneShotWire(resolver).execute(request)).ok).toBe(false);expect(resolver).not.toHaveBeenCalled();expect(fetchMock).not.toHaveBeenCalled();
  });
  it("serializes one E32 POST with Bearer and prohibits a second", async () => {
    const wire=new E32SandboxOneShotWire(async()=>"synthetic-token");
    expect((await wire.execute(request)).ok).toBe(true);expect((await wire.execute(request)).ok).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1);expect(fetchMock.mock.calls[0][0]).toBe(E32_SANDBOX_URL+"/invoices");
    expect(fetchMock.mock.calls[0][1]).toMatchObject({redirect:"manual",body:JSON.stringify(request.body),headers:{authorization:"Bearer synthetic-token"}});
  });
  it.each(["", "/idCompany/01FVJ1528AQRBC7D6K2TGVE5S5"])("allows one official GET in target mode %s",async suffix=>{
    const wire=new E32SandboxOneShotWire(async()=>"synthetic-token");
    const get={method:"GET" as const,path:`/invoices/01FVJ1528AQRBC7D6K2TGVE5S5${suffix}`,requestId:"synthetic"};
    expect((await wire.execute(get)).ok).toBe(true);expect((await wire.execute(get)).ok).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
  it("rejects E31 and arbitrary URLs", async () => {
    const wire=new E32SandboxOneShotWire(async()=>"synthetic-token");
    expect((await wire.execute({...request,path:"/fiscal-invoices"})).ok).toBe(false);expect(fetchMock).not.toHaveBeenCalled();
  });
  it("validates the E32 body again before resolving any secret",async()=>{
    const resolver=jest.fn(async()=>"synthetic-token");
    expect((await new E32SandboxOneShotWire(resolver).execute({...request,body:{test:true}})).ok).toBe(false);
    expect(resolver).not.toHaveBeenCalled();expect(fetchMock).not.toHaveBeenCalled();
  });
  it("blocks production database before network", async () => {
    process.env.DATABASE_URL="postgresql://remote.invalid:5432/production";
    expect((await new E32SandboxOneShotWire(async()=>"synthetic-token").execute(request)).ok).toBe(false);expect(fetchMock).not.toHaveBeenCalled();
  });
  it("blocks redirects without retry", async () => {
    fetchMock.mockResolvedValue(new Response(null,{status:302}));
    expect(await new E32SandboxOneShotWire(async()=>"synthetic-token").execute(request)).toMatchObject({ok:false,errorCode:"REDIRECT_BLOCKED"});expect(fetchMock).toHaveBeenCalledTimes(1);
  });
  it("bounds responses before parse", async () => {
    fetchMock.mockResolvedValue(new Response("x".repeat(65537),{status:201}));
    expect((await new E32SandboxOneShotWire(async()=>"synthetic-token").execute(request)).ok).toBe(false);expect(fetchMock).toHaveBeenCalledTimes(1);
  });
  it("aborts timeout and never retries", async () => {
    jest.useFakeTimers();fetchMock.mockImplementation((_url,options)=>new Promise((_resolve,reject)=>options.signal.addEventListener("abort",()=>reject(Error("synthetic timeout")))));
    const result=new E32SandboxOneShotWire(async()=>"synthetic-token").execute(request);
    await jest.advanceTimersByTimeAsync(10001);expect(await result).toMatchObject({ok:false,errorCode:"TIMEOUT"});expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
