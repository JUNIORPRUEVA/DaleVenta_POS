import { GuardianAiError, GuardianAiProvider, GuardianAiRequest, GuardianAiResult } from './guardian-ai.provider';
import { validateDiagnosisPayload } from './openai-guardian-ai.provider';
import { buildUntrustedEvidenceBlock } from './guardian.ai.sanitizer';
import { guardianSecretValue } from '../guardian.secret';

/** Reuses the CRM provider, encrypted account and budget; never receives the vendor's API key. */
export class CrmGuardianAiProvider implements GuardianAiProvider {
  readonly name = 'crm';
  isConfigured(): boolean {
    return Boolean(guardianSecretValue(process.env, 'GUARDIAN_CRM_BRIDGE_TOKEN') && this.endpoint());
  }
  private endpoint(): string | null {
    try {
      const url = new URL(process.env.GUARDIAN_CRM_BASE_URL || '');
      if (url.username || url.password || url.search || url.hash) return null;
      if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(url.hostname))) return null;
      return `${url.href.replace(/\/+$/, '')}/api/internal/guardian/diagnose`;
    } catch { return null; }
  }
  async status() {
    if (!this.isConfigured()) return {reachable:false,configured:false,enabled:false};
    try {
      const response = await fetch(this.endpoint()!.replace(/diagnose$/,'status'), {redirect:'error',signal:AbortSignal.timeout(2000),
        headers:{'x-guardian-crm-token':guardianSecretValue(process.env,'GUARDIAN_CRM_BRIDGE_TOKEN')}});
      if (!response.ok) return {reachable:false,configured:false,enabled:false};
      const state = await response.json();
      return {reachable:true,configured:state.configured === true,enabled:state.enabled === true};
    } catch { return {reachable:false,configured:false,enabled:false}; }
  }
  async analyze(request: GuardianAiRequest): Promise<GuardianAiResult> {
    if (!this.isConfigured()) throw new GuardianAiError('AI_NOT_CONFIGURED', 'Integración IA del CRM sin configurar');
    const started = Date.now();
    const response = await fetch(this.endpoint()!, {method:'POST',redirect:'error',signal:AbortSignal.timeout(30_000),
      headers:{'content-type':'application/json','x-guardian-crm-token':guardianSecretValue(process.env,'GUARDIAN_CRM_BRIDGE_TOKEN')},
      body:JSON.stringify({evidence:buildUntrustedEvidenceBlock(request).slice(0,12000)}),
    });
    if (!response.ok) throw new GuardianAiError(response.status === 429 ? 'AI_RATE_LIMITED' : 'AI_PROVIDER_ERROR',
      `IA compartida HTTP ${response.status}`, {httpStatus:response.status,retryable:response.status === 429 || response.status >= 500});
    const result = await response.json();
    const data = result?.json;
    if (!validateDiagnosisPayload(data).ok || !['CONFIRMED','PROBABLE','INSUFFICIENT'].includes(data?.verdict) ||
        typeof data?.confidence !== 'number' || data.confidence < 0 || data.confidence > 1) {
      throw new GuardianAiError('AI_SCHEMA_INVALID','Diagnóstico compartido no válido');
    }
    return {verdict:data.verdict,confidence:data.confidence,summary:data.summary.slice(0,600),
      explanation:data.explanation.slice(0,4000),impact:data.impact?.slice(0,600)||null,causeCategory:data.causeCategory?.slice(0,60)||null,
      nextSteps:(data.nextSteps||[]).filter((item: unknown)=>typeof item === 'string').slice(0,8).map((item:string)=>item.slice(0,500)),
      evidenceRefs:(data.evidenceRefs||[]).filter((item:any)=>item && typeof item.ref==='string' && ['incident','similar_incident','sql','code','log','version','company'].includes(item.type)).slice(0,20).map((item:any)=>({type:item.type,ref:item.ref.slice(0,300),note:typeof item.note==='string'?item.note.slice(0,300):undefined})),
      toolCalls:[],model:`crm:${String(result.model || 'shared').slice(0,100)}`,
      tokensUsed:Math.max(0,Number(result.usage?.total)||0),durationMs:Date.now()-started};
  }
}
