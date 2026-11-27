import { CrmGuardianAiProvider } from './crm-guardian-ai.provider';
import { resolveGuardianAiRuntime } from './guardian.ai.runtime';
describe('shared CRM Guardian AI',()=>{
  const env={...process.env};const originalFetch=global.fetch;
  const request:any={incident:{id:'one',module:'sales',operation:'POST /sales',severity:'SEV2'},similarIncidents:[],company:null,businessFacts:{},codeMatches:[],versionTimeline:[]};
  beforeEach(()=>{process.env.GUARDIAN_AI_PROVIDER='crm';process.env.GUARDIAN_CRM_BASE_URL='https://crm.test';process.env.GUARDIAN_CRM_BRIDGE_TOKEN='synthetic-service-token';});
  afterEach(()=>{process.env={...env};global.fetch=originalFetch;});
  it('reports the shared provider honestly and does not require a separate vendor key',()=>{
    delete process.env.GUARDIAN_AI_API_KEY;
    expect(resolveGuardianAiRuntime().adapter).toBe('crm');
    expect(new CrmGuardianAiProvider().isConfigured()).toBe(true);
  });
  it('uses the authenticated CRM contract and validates the diagnosis',async()=>{
    global.fetch=jest.fn(async()=>({ok:true,json:async()=>({json:{verdict:'INSUFFICIENT',confidence:0.1,summary:'Evidence insufficient',explanation:'No proof'},model:'shared',usage:{total:10}})})) as any;
    const result=await new CrmGuardianAiProvider().analyze(request);
    expect(result.model).toBe('crm:shared');expect(result.verdict).toBe('INSUFFICIENT');
    expect(global.fetch).toHaveBeenCalledWith('https://crm.test/api/internal/guardian/diagnose',expect.objectContaining({redirect:'error',headers:expect.objectContaining({'x-guardian-crm-token':'synthetic-service-token'})}));
  });
  it('never converts a malformed or unavailable response into a diagnosis',async()=>{
    global.fetch=jest.fn(async()=>({ok:true,json:async()=>({json:{summary:'Bad'}})})) as any;
    await expect(new CrmGuardianAiProvider().analyze(request)).rejects.toMatchObject({code:'AI_SCHEMA_INVALID'});
    global.fetch=jest.fn(async()=>({ok:false,status:503})) as any;
    await expect(new CrmGuardianAiProvider().analyze(request)).rejects.toMatchObject({code:'AI_PROVIDER_ERROR',retryable:true});
  });
  it('rejects remote plaintext endpoints',()=>{
    process.env.GUARDIAN_CRM_BASE_URL='http://remote.test';
    expect(new CrmGuardianAiProvider().isConfigured()).toBe(false);
    expect(resolveGuardianAiRuntime().errors).toContain('AI_BASE_URL_INVALID');
  });
});
