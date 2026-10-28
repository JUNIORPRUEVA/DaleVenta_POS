import { GuardianAiError, GuardianAiRequest } from './guardian-ai.provider';
import {
  OpenAiGuardianAiProvider,
  describeAiContent,
  parseGuardianJson,
  validateDiagnosisPayload,
} from './openai-guardian-ai.provider';

/**
 * FASE 5A — Corrección del parseo de respuestas del proveedor de IA.
 *
 * Todas las pruebas usan `fetch` simulado: NO se realiza ninguna petición real
 * a DeepSeek/OpenAI ni a ningún otro proveedor.
 *
 * Motivo: el 2026-10-28 el diagnóstico real de DeepSeek respondió HTTP 2xx pero
 * el contenido no se pudo parsear (`AI_INVALID_RESPONSE`), sin distinguir si era
 * truncamiento por `max_tokens`, texto libre o un esquema incompleto.
 */

function request(): GuardianAiRequest {
  return {
    incident: {
      id: 'inc-p5a',
      module: 'flutter',
      operation: 'Zone',
      severity: 'SEV2',
      exceptionType: 'SyntheticGuardianProbeException',
      platform: 'windows',
      appVersion: '1.0.6+140',
      occurredAt: '2026-10-28T19:04:33.825Z',
      message: 'SyntheticGuardianProbeException(guardian-uat-selftest)',
      stack: null,
      impactSummary: null,
    },
    similarIncidents: [],
    company: null,
    businessFacts: {},
    codeMatches: [],
    versionTimeline: [],
  };
}

const VALID_DIAGNOSIS = {
  verdict: 'PROBABLE',
  confidence: 0.55,
  summary: 'Excepción no controlada en la zona raíz del cliente.',
  impact: 'La operación en curso se interrumpe y el usuario debe reintentar.',
  causeCategory: 'Error no controlado en runtime',
  explanation: 'Se lanzó una excepción asíncrona sin manejador en la zona raíz.',
  nextSteps: ['Revisar el log local del agente', 'Reproducir con la sonda UAT'],
  evidenceRefs: [{ type: 'incident', ref: 'inc-p5a', note: 'mensaje del incidente' }],
};

type Choice = { content: string; finishReason?: string | null };

function answer(choice: Choice, usage?: { total_tokens: number }) {
  return {
    id: 'chatcmpl-p5a',
    model: 'deepseek-flash',
    choices: [
      {
        index: 0,
        message: { role: 'assistant', content: choice.content },
        finish_reason: choice.finishReason === undefined ? 'stop' : choice.finishReason,
      },
    ],
    ...(usage ? { usage } : {}),
  };
}

function httpResponse(payload: unknown, init: { status?: number; headers?: Record<string, string> } = {}) {
  return {
    ok: (init.status ?? 200) < 400,
    status: init.status ?? 200,
    headers: { get: (name: string) => init.headers?.[name.toLowerCase()] ?? null },
    text: async () => JSON.stringify(payload),
    json: async () => payload,
  } as unknown as Response;
}

function nonJsonResponse(status = 200) {
  return {
    ok: status < 400,
    status,
    headers: { get: () => null },
    text: async () => '<html>gateway</html>',
    json: async () => {
      throw new SyntaxError('Unexpected token <');
    },
  } as unknown as Response;
}

describe('Fase 5A — parseGuardianJson', () => {
  it('acepta JSON puro', () => {
    const result = parseGuardianJson('{"a":1}');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toEqual({ a: 1 });
  });

  it('acepta JSON dentro de vallas markdown', () => {
    const result = parseGuardianJson('```json\n{"a":1}\n```');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value).toEqual({ a: 1 });
      expect(result.fenced).toBe(true);
    }
  });

  it('acepta JSON con texto alrededor', () => {
    const result = parseGuardianJson('resultado: {"a":1} fin');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toEqual({ a: 1 });
  });

  it('detecta contenido vacío', () => {
    expect(parseGuardianJson('   ')).toMatchObject({ ok: false, reason: 'EMPTY' });
  });

  it('detecta JSON truncado (estructura abierta)', () => {
    expect(parseGuardianJson('{"verdict":"PROBABLE","summary":"cor')).toMatchObject({
      ok: false,
      reason: 'TRUNCATED',
    });
  });

  it('detecta JSON truncado dentro de valla de código', () => {
    expect(parseGuardianJson('```json\n{"verdict":"PROBABLE","nextSteps":["a"')).toMatchObject({
      ok: false,
      reason: 'TRUNCATED',
    });
  });

  it('distingue texto libre (NO_JSON) de truncamiento', () => {
    expect(parseGuardianJson('No puedo determinar la causa con esta información.')).toMatchObject({
      ok: false,
      reason: 'NO_JSON',
    });
  });

  it('rechaza JSON malformado pero cerrado sin confundirlo con truncamiento', () => {
    expect(parseGuardianJson('{"verdict": "PROBABLE",}')).toMatchObject({
      ok: false,
      reason: 'NO_JSON',
    });
  });

  it('no se deja engañar por llaves dentro de cadenas', () => {
    const fenced = '```json\n{"summary":"texto con } y { dentro"}\n```';
    const result = parseGuardianJson(fenced);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toEqual({ summary: 'texto con } y { dentro' });
  });
});

describe('Fase 5A — validateDiagnosisPayload', () => {
  it('acepta el diagnóstico completo', () => {
    expect(validateDiagnosisPayload(VALID_DIAGNOSIS)).toEqual({ ok: true });
  });

  it('exige los campos obligatorios', () => {
    expect(validateDiagnosisPayload({ verdict: 'PROBABLE' })).toMatchObject({
      ok: false,
      missing: ['confidence', 'summary', 'explanation'],
    });
  });

  it('trata summary vacío como ausente/inválido y nunca lo inventa', () => {
    expect(validateDiagnosisPayload({ ...VALID_DIAGNOSIS, summary: '   ' })).toMatchObject({
      ok: false,
      invalid: ['summary'],
    });
  });

  it('rechaza tipos incorrectos', () => {
    expect(
      validateDiagnosisPayload({ ...VALID_DIAGNOSIS, verdict: 7, nextSteps: 'revisar' }),
    ).toMatchObject({ ok: false, invalid: ['verdict', 'nextSteps'] });
  });

  it('rechaza una raíz que no es objeto', () => {
    expect(validateDiagnosisPayload([VALID_DIAGNOSIS])).toMatchObject({
      ok: false,
      invalid: ['root'],
    });
  });
});

describe('Fase 5A — describeAiContent (metadatos seguros)', () => {
  it('resume la respuesta sin exponer contenido crudo', () => {
    const canary = 'SECRETO-DE-CLIENTE-123456';
    const diagnostic = describeAiContent(`{"summary":"${canary}"}`, 'stop', 1600);

    expect(diagnostic.contentLength).toBeGreaterThan(0);
    expect(diagnostic.contentSha256).toHaveLength(16);
    expect(JSON.stringify(diagnostic)).not.toContain(canary);
    expect(diagnostic.maxTokens).toBe(1600);
    expect(diagnostic.jsonBalanced).toBe(true);
  });

  it('marca contenido truncado como no balanceado', () => {
    expect(describeAiContent('{"a":', 'length', 1600)).toMatchObject({
      finishReason: 'length',
      jsonBalanced: false,
      startsWithJson: true,
    });
  });
});

describe('Fase 5A — OpenAiGuardianAiProvider (adaptador deepseek)', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  function provider(maxTokens?: number) {
    return new OpenAiGuardianAiProvider({
      apiKey: 'clave-uat-deepseek',
      adapter: 'deepseek',
      ...(maxTokens ? { maxTokens } : {}),
    });
  }

  it('acepta un JSON válido de DeepSeek y conserva tokens y modelo', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(answer({ content: JSON.stringify(VALID_DIAGNOSIS) }, { total_tokens: 321 })),
    ) as unknown as typeof fetch;

    const result = await provider().analyze(request());

    expect(result.verdict).toBe('PROBABLE');
    expect(result.model).toBe('deepseek-flash');
    expect(result.tokensUsed).toBe(321);
    expect(result.summary).toContain('Excepción no controlada');
  });

  it('acepta JSON en vallas markdown', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(answer({ content: '```json\n' + JSON.stringify(VALID_DIAGNOSIS) + '\n```' })),
    ) as unknown as typeof fetch;

    await expect(provider().analyze(request())).resolves.toMatchObject({ verdict: 'PROBABLE' });
  });

  it('clasifica truncamiento cuando finish_reason=length', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(
        answer({ content: '{"verdict":"PROBABLE","summary":"corte', finishReason: 'length' }, { total_tokens: 700 }),
      ),
    ) as unknown as typeof fetch;

    const error = (await provider(1600).analyze(request()).catch((caught) => caught)) as GuardianAiError;

    expect(error).toBeInstanceOf(GuardianAiError);
    expect(error.code).toBe('AI_OUTPUT_TRUNCATED');
    expect(error.retryable).toBe(false);
    expect(error.diagnostic).toMatchObject({ finishReason: 'length', maxTokens: 1600 });
    expect(error.diagnosticSummary).toContain('finish=length');
    expect(error.diagnosticSummary).toContain('balanced=no');
  });

  it('clasifica truncamiento por estructura abierta aunque finish_reason sea stop', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(answer({ content: '{"verdict":"PROBABLE","nextSteps":["a","b"' })),
    ) as unknown as typeof fetch;

    await expect(provider().analyze(request())).rejects.toMatchObject({
      code: 'AI_OUTPUT_TRUNCATED',
      retryable: false,
    });
  });

  it('una salida vacía es AI_INVALID_RESPONSE y no se reintenta', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(answer({ content: '', finishReason: null })),
    ) as unknown as typeof fetch;

    const error = (await provider().analyze(request()).catch((caught) => caught)) as GuardianAiError;
    expect(error.code).toBe('AI_INVALID_RESPONSE');
    expect(error.retryable).toBe(false);
  });

  it('texto libre es AI_INVALID_RESPONSE (no truncamiento)', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(answer({ content: 'No puedo determinar la causa.' })),
    ) as unknown as typeof fetch;

    await expect(provider().analyze(request())).rejects.toMatchObject({
      code: 'AI_INVALID_RESPONSE',
      retryable: false,
    });
  });

  it('un esquema incompleto es AI_SCHEMA_INVALID e indica los campos ausentes', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(answer({ content: JSON.stringify({ verdict: 'PROBABLE', confidence: 0.4 }) })),
    ) as unknown as typeof fetch;

    const error = (await provider().analyze(request()).catch((caught) => caught)) as GuardianAiError;
    expect(error.code).toBe('AI_SCHEMA_INVALID');
    expect(error.retryable).toBe(false);
    expect(error.message).toContain('summary');
    expect(error.message).toContain('explanation');
    expect(error.diagnostic?.missingFields).toEqual(['summary', 'explanation']);
  });

  it('no inventa campos: un summary vacío no se rellena con texto propio', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse(
        answer({ content: JSON.stringify({ ...VALID_DIAGNOSIS, summary: '' }) }),
      ),
    ) as unknown as typeof fetch;

    await expect(provider().analyze(request())).rejects.toMatchObject({
      code: 'AI_SCHEMA_INVALID',
      retryable: false,
    });
  });

  it('los metadatos del error nunca contienen el contenido del modelo', async () => {
    const canary = 'dato-sensible-del-cliente-9f8e7d';
    global.fetch = jest.fn(async () =>
      httpResponse(answer({ content: JSON.stringify({ verdict: 'PROBABLE', summary: canary }) })),
    ) as unknown as typeof fetch;

    const error = (await provider().analyze(request()).catch((caught) => caught)) as GuardianAiError;

    expect(error.code).toBe('AI_SCHEMA_INVALID');
    expect(error.message).not.toContain(canary);
    expect(error.diagnosticSummary).not.toContain(canary);
    expect(JSON.stringify(error.diagnostic ?? {})).not.toContain(canary);
    expect(error.diagnosticSummary).toMatch(/sha=[0-9a-f]{16}/);
  });

  it('un 500 es AI_PROVIDER_ERROR transitorio (reintentable)', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse({ error: { message: 'internal' } }, { status: 500 }),
    ) as unknown as typeof fetch;

    await expect(provider().analyze(request())).rejects.toMatchObject({
      code: 'AI_PROVIDER_ERROR',
      httpStatus: 500,
      retryable: true,
    });
  });

  it('un 401 no filtra la credencial ni se reintenta a ciegas', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse({ error: { message: 'Authentication Fails' } }, { status: 401 }),
    ) as unknown as typeof fetch;

    const error = (await provider().analyze(request()).catch((caught) => caught)) as GuardianAiError;
    expect(error.code).toBe('AI_PROVIDER_ERROR');
    expect(error.message).not.toContain('clave-uat-deepseek');
    expect(error.message).toContain('401');
  });

  it('un 429 es AI_RATE_LIMITED con Retry-After', async () => {
    global.fetch = jest.fn(async () =>
      httpResponse({ error: { message: 'rate limit' } }, { status: 429, headers: { 'retry-after': '45' } }),
    ) as unknown as typeof fetch;

    await expect(provider().analyze(request())).rejects.toMatchObject({
      code: 'AI_RATE_LIMITED',
      retryAfterMs: 45_000,
      retryable: true,
    });
  });

  it('un timeout es AI_TIMEOUT transitorio', async () => {
    global.fetch = jest.fn(async () => {
      const error = new Error('The operation was aborted');
      error.name = 'AbortError';
      throw error;
    }) as unknown as typeof fetch;

    await expect(
      new OpenAiGuardianAiProvider({
        apiKey: 'clave-uat',
        adapter: 'deepseek',
        timeoutMs: 25,
      }).analyze(request()),
    ).rejects.toMatchObject({ code: 'AI_TIMEOUT', retryable: true });
  });

  it('un 2xx con cuerpo no JSON es AI_INVALID_RESPONSE (no se reintenta)', async () => {
    global.fetch = jest.fn(async () => nonJsonResponse(200)) as unknown as typeof fetch;

    await expect(provider().analyze(request())).rejects.toMatchObject({
      code: 'AI_INVALID_RESPONSE',
      retryable: false,
    });
  });

  it('sin credenciales no hace ninguna petición de red', async () => {
    const fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
    const withoutKey = new OpenAiGuardianAiProvider({ apiKey: '', adapter: 'deepseek' });

    await expect(withoutKey.analyze(request())).rejects.toMatchObject({
      code: 'AI_NOT_CONFIGURED',
      retryable: false,
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('envía el tope de tokens por defecto de Fase 5A (1600)', async () => {
    let body: any;
    global.fetch = jest.fn(async (_target: any, init: any) => {
      body = JSON.parse(init.body);
      return httpResponse(answer({ content: JSON.stringify(VALID_DIAGNOSIS) }));
    }) as unknown as typeof fetch;

    await provider().analyze(request());

    expect(body.max_tokens).toBe(1600);
    expect(body.response_format).toEqual({ type: 'json_object' });
    expect(body.reasoning_effort).toBe('none');
  });

  it('una sola llamada al proveedor por análisis (sin reintentos internos)', async () => {
    const fetchMock = jest.fn(async () =>
      httpResponse(answer({ content: '{"verdict":"PROBABLE"', finishReason: 'length' })),
    );
    global.fetch = fetchMock as unknown as typeof fetch;

    await provider().analyze(request()).catch(() => undefined);

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
