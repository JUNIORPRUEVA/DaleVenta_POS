import {
  GUARDIAN_DEEPSEEK_DEFAULT_BASE_URL,
  GUARDIAN_DEEPSEEK_DEFAULT_MODEL,
  GUARDIAN_OPENAI_DEFAULT_MODEL,
  describeGuardianAiRuntime,
  resolveGuardianAiRuntime,
} from './guardian.ai.runtime';

/** Entorno mínimo: solo las variables indicadas, nunca el entorno real. */
function env(overrides: Record<string, string | undefined>): NodeJS.ProcessEnv {
  return { ...overrides } as NodeJS.ProcessEnv;
}

describe('resolveGuardianAiRuntime', () => {
  it('sin credencial usa el mock y no inventa proveedor', () => {
    const runtime = resolveGuardianAiRuntime(env({}));

    expect(runtime.adapter).toBe('mock');
    expect(runtime.apiKeyPresent).toBe(false);
    expect(runtime.baseUrl).toBeNull();
    expect(runtime.model).toBe('mock');
    expect(runtime.errors).toEqual([]);
  });

  it('selecciona DeepSeek explícitamente y aplica sus valores por defecto', () => {
    const runtime = resolveGuardianAiRuntime(
      env({ GUARDIAN_AI_PROVIDER: 'deepseek', GUARDIAN_AI_API_KEY: 'clave-uat-deepseek' }),
    );

    expect(runtime.adapter).toBe('deepseek');
    expect(runtime.baseUrl).toBe(GUARDIAN_DEEPSEEK_DEFAULT_BASE_URL);
    expect(runtime.baseUrlHost).toBe('api.deepseek.com');
    expect(runtime.model).toBe(GUARDIAN_DEEPSEEK_DEFAULT_MODEL);
    expect(runtime.modelSupported).toBe(true);
    expect(runtime.errors).toEqual([]);
  });

  it('normaliza el nombre del proveedor sin distinguir mayúsculas', () => {
    const runtime = resolveGuardianAiRuntime(
      env({ GUARDIAN_AI_PROVIDER: '  DeepSeek  ', GUARDIAN_AI_API_KEY: 'clave-uat' }),
    );

    expect(runtime.adapter).toBe('deepseek');
    expect(runtime.providerVariable).toBe('DeepSeek');
  });

  it('infiere DeepSeek por el host cuando no se declara proveedor', () => {
    const runtime = resolveGuardianAiRuntime(
      env({
        GUARDIAN_AI_API_KEY: 'clave-uat',
        GUARDIAN_AI_BASE_URL: 'https://api.deepseek.com',
      }),
    );

    expect(runtime.adapter).toBe('deepseek');
  });

  it('sin proveedor declarado ni host DeepSeek mantiene OpenAI (compatibilidad previa)', () => {
    const runtime = resolveGuardianAiRuntime(env({ GUARDIAN_AI_API_KEY: 'clave-uat' }));

    expect(runtime.adapter).toBe('openai');
    expect(runtime.model).toBe(GUARDIAN_OPENAI_DEFAULT_MODEL);
  });

  it('degrada a mock si se declara deepseek sin credencial', () => {
    const runtime = resolveGuardianAiRuntime(env({ GUARDIAN_AI_PROVIDER: 'deepseek' }));

    expect(runtime.adapter).toBe('mock');
    expect(runtime.errors).toContain('AI_API_KEY_MISSING');
    expect(runtime.warnings.join(' ')).toMatch(/GUARDIAN_AI_API_KEY/);
  });

  it('degrada a mock si el host no corresponde al proveedor (no envía la clave a otro host)', () => {
    const runtime = resolveGuardianAiRuntime(
      env({
        GUARDIAN_AI_PROVIDER: 'deepseek',
        GUARDIAN_AI_API_KEY: 'clave-uat',
        GUARDIAN_AI_BASE_URL: 'https://api.openai.com/v1',
      }),
    );

    expect(runtime.adapter).toBe('mock');
    expect(runtime.baseUrl).toBeNull();
    expect(runtime.errors).toContain('AI_BASE_URL_MISMATCH');
  });

  it('rechaza un modelo no documentado de DeepSeek', () => {
    const runtime = resolveGuardianAiRuntime(
      env({
        GUARDIAN_AI_PROVIDER: 'deepseek',
        GUARDIAN_AI_API_KEY: 'clave-uat',
        GUARDIAN_AI_MODEL: 'deepseek-inexistente',
      }),
    );

    expect(runtime.adapter).toBe('mock');
    expect(runtime.modelSupported).toBe(false);
    expect(runtime.errors).toContain('AI_MODEL_UNSUPPORTED');
  });

  it('acepta los dos modelos documentados de DeepSeek', () => {
    for (const model of ['deepseek-flash', 'deepseek-v4-pro']) {
      const runtime = resolveGuardianAiRuntime(
        env({ GUARDIAN_AI_PROVIDER: 'deepseek', GUARDIAN_AI_API_KEY: 'clave-uat', GUARDIAN_AI_MODEL: model }),
      );
      expect(runtime.adapter).toBe('deepseek');
      expect(runtime.model).toBe(model);
    }
  });

  it('degrada a mock con una base URL inválida', () => {
    const runtime = resolveGuardianAiRuntime(
      env({
        GUARDIAN_AI_PROVIDER: 'deepseek',
        GUARDIAN_AI_API_KEY: 'clave-uat',
        GUARDIAN_AI_BASE_URL: 'no-es-una-url',
      }),
    );

    expect(runtime.adapter).toBe('mock');
    expect(runtime.errors).toContain('AI_BASE_URL_INVALID');
  });

  it('rechaza un proveedor desconocido en lugar de adivinar', () => {
    const runtime = resolveGuardianAiRuntime(
      env({ GUARDIAN_AI_PROVIDER: 'anthropic', GUARDIAN_AI_API_KEY: 'clave-uat' }),
    );

    expect(runtime.adapter).toBe('mock');
    expect(runtime.errors).toContain('AI_PROVIDER_UNKNOWN');
  });

  it('respeta mock explícito aunque exista credencial', () => {
    const runtime = resolveGuardianAiRuntime(
      env({ GUARDIAN_AI_PROVIDER: 'mock', GUARDIAN_AI_API_KEY: 'clave-uat' }),
    );

    expect(runtime.adapter).toBe('mock');
    expect(runtime.apiKeyPresent).toBe(true);
  });

  it('acota timeout, tokens y concurrencia a rangos seguros', () => {
    const runtime = resolveGuardianAiRuntime(
      env({
        GUARDIAN_AI_PROVIDER: 'deepseek',
        GUARDIAN_AI_API_KEY: 'clave-uat',
        GUARDIAN_AI_TIMEOUT_MS: '999999',
        GUARDIAN_AI_MAX_TOKENS: '1',
        GUARDIAN_AI_MAX_CONCURRENCY: '0',
      }),
    );

    expect(runtime.timeoutMs).toBe(120_000);
    expect(runtime.maxTokens).toBe(64);
    expect(runtime.maxConcurrent).toBe(1);
  });

  it('no reutiliza OPENAI_API_KEY de otro producto', () => {
    const runtime = resolveGuardianAiRuntime(
      env({ GUARDIAN_AI_PROVIDER: 'deepseek', OPENAI_API_KEY: 'clave-de-otro-producto' }),
    );

    expect(runtime.apiKeyPresent).toBe(false);
    expect(runtime.adapter).toBe('mock');
  });

  it('describeGuardianAiRuntime no expone la credencial', () => {
    const runtime = resolveGuardianAiRuntime(
      env({
        GUARDIAN_AI_PROVIDER: 'deepseek',
        GUARDIAN_AI_API_KEY: 'clave-secreta-que-no-debe-aparecer',
      }),
    );
    const summary = describeGuardianAiRuntime(runtime);

    expect(summary).toContain('adaptador=deepseek');
    expect(summary).toContain('api.deepseek.com');
    expect(summary).not.toContain('clave-secreta');
  });
});
