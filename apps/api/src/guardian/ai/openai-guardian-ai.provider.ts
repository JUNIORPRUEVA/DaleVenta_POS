import { GuardianDiagnosisVerdict } from '@prisma/client';
import {
  GuardianAiProvider,
  GuardianAiRequest,
  GuardianAiResult,
  GuardianEvidenceRef,
} from './guardian-ai.provider';

const SYSTEM_PROMPT = [
  'Eres un ingeniero de confiabilidad que diagnostica incidentes de un POS.',
  'REGLA 1: solo puedes concluir con la evidencia incluida en el contexto.',
  'REGLA 2: si la evidencia no alcanza, responde "INSUFFICIENT". Nunca inventes causas.',
  'REGLA 3: no propones ni ejecutas cambios; solo describes y sugieres pasos de investigación.',
  'Responde EXCLUSIVAMENTE un JSON con las claves:',
  'verdict (CONFIRMED|PROBABLE|INSUFFICIENT), confidence (0..1), summary, impact,',
  'causeCategory, explanation, nextSteps (string[]), evidenceRefs ({type,ref,note}[]).',
].join('\n');

/**
 * Proveedor OpenAI-compatible mediante `fetch`.
 *
 * No se añade SDK: se usa `fetch` nativo para no introducir dependencias.
 * Si no hay credenciales, `isConfigured()` es false y el worker usa el mock.
 */
export class OpenAiGuardianAiProvider implements GuardianAiProvider {
  readonly name = 'openai';

  constructor(
    private readonly options: {
      apiKey: string;
      baseUrl?: string;
      model?: string;
      timeoutMs?: number;
      maxTokens?: number;
    },
  ) {}

  isConfigured(): boolean {
    return this.options.apiKey.trim().length > 0;
  }

  async analyze(request: GuardianAiRequest): Promise<GuardianAiResult> {
    const startedAt = Date.now();
    const baseUrl = (this.options.baseUrl ?? 'https://api.openai.com/v1').replace(/\/+$/, '');
    const model = this.options.model ?? 'gpt-4o-mini';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 20_000);

    try {
      const response = await fetch(`${baseUrl}/chat/completions`, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.options.apiKey}`,
        },
        body: JSON.stringify({
          model,
          temperature: 0,
          max_tokens: this.options.maxTokens ?? 900,
          response_format: { type: 'json_object' },
          messages: [
            { role: 'system', content: SYSTEM_PROMPT },
            { role: 'user', content: JSON.stringify(request) },
          ],
        }),
      });

      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        const error: any = new Error(`IA HTTP ${response.status}: ${detail.slice(0, 200)}`);
        error.status = response.status;
        throw error;
      }

      const body: any = await response.json();
      const raw = String(body?.choices?.[0]?.message?.content ?? '{}');
      const parsed = JSON.parse(raw);

      const verdict = this.normalizeVerdict(parsed?.verdict);
      const evidenceRefs: GuardianEvidenceRef[] = Array.isArray(parsed?.evidenceRefs)
        ? parsed.evidenceRefs
            .filter((item: any) => item && typeof item.ref === 'string')
            .slice(0, 20)
            .map((item: any) => ({
              type: ['incident', 'similar_incident', 'sql', 'code', 'log', 'version', 'company'].includes(item.type)
                ? item.type
                : 'incident',
              ref: String(item.ref).slice(0, 300),
              note: item.note ? String(item.note).slice(0, 300) : undefined,
            }))
        : [];

      return {
        verdict,
        confidence: Math.min(1, Math.max(0, Number(parsed?.confidence ?? 0))),
        summary: String(parsed?.summary ?? '').slice(0, 600),
        impact: parsed?.impact ? String(parsed.impact).slice(0, 600) : null,
        causeCategory: parsed?.causeCategory ? String(parsed.causeCategory).slice(0, 60) : null,
        explanation: String(parsed?.explanation ?? '').slice(0, 4_000),
        nextSteps: Array.isArray(parsed?.nextSteps)
          ? parsed.nextSteps.slice(0, 8).map((step: unknown) => String(step).slice(0, 200))
          : [],
        evidenceRefs,
        toolCalls: [],
        model,
        tokensUsed: Number(body?.usage?.total_tokens ?? 0),
        durationMs: Date.now() - startedAt,
      };
    } finally {
      clearTimeout(timeout);
    }
  }

  private normalizeVerdict(raw: unknown): GuardianDiagnosisVerdict {
    const value = String(raw ?? '').trim().toUpperCase();
    if (value === 'CONFIRMED') return GuardianDiagnosisVerdict.CONFIRMED;
    if (value === 'PROBABLE') return GuardianDiagnosisVerdict.PROBABLE;
    return GuardianDiagnosisVerdict.INSUFFICIENT;
  }
}
