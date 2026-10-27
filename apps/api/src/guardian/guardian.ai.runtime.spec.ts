import { describeGuardianAiRuntime } from './guardian.config';

/**
 * El adaptador de IA se selecciona SOLO por `GUARDIAN_AI_API_KEY`.
 * `GUARDIAN_AI_PROVIDER` es informativo: estas pruebas fijan ese
 * comportamiento para que nadie crea que activa un proveedor distinto.
 */
describe('describeGuardianAiRuntime', () => {
  it('sin API key usa el mock y lo advierte', () => {
    const runtime = describeGuardianAiRuntime({});
    expect(runtime.adapter).toBe('mock');
    expect(runtime.apiKeyPresent).toBe(false);
    expect(runtime.warnings.join(' | ')).toContain('proveedor mock');
  });

  it('con key y base DeepSeek usa el adaptador OpenAI-compatible y avisa que la variable provider no se usa', () => {
    const runtime = describeGuardianAiRuntime({
      GUARDIAN_AI_API_KEY: 'clave-de-prueba',
      GUARDIAN_AI_BASE_URL: 'https://api.deepseek.com',
      GUARDIAN_AI_MODEL: 'modelo-de-prueba',
      GUARDIAN_AI_PROVIDER: 'deepseek',
    });

    expect(runtime.adapter).toBe('openai-compatible');
    expect(runtime.baseUrlHost).toBe('api.deepseek.com');
    expect(runtime.providerVariable).toBe('deepseek');
    expect(runtime.providerVariableHonored).toBe(false);
    expect(runtime.warnings.join(' | ')).toContain('GUARDIAN_AI_PROVIDER=deepseek no se usa');
  });

  it('no advierte cuando provider es openai (coincide con el adaptador real)', () => {
    const runtime = describeGuardianAiRuntime({
      GUARDIAN_AI_API_KEY: 'clave-de-prueba',
      GUARDIAN_AI_BASE_URL: 'https://api.deepseek.com',
      GUARDIAN_AI_MODEL: 'modelo-de-prueba',
      GUARDIAN_AI_PROVIDER: 'openai',
    });
    expect(runtime.warnings.some((w) => w.includes('GUARDIAN_AI_PROVIDER'))).toBe(false);
  });

  it('detecta una base URL inválida sin exponerla', () => {
    const runtime = describeGuardianAiRuntime({
      GUARDIAN_AI_API_KEY: 'clave-de-prueba',
      GUARDIAN_AI_BASE_URL: 'no-es-una-url',
    });
    expect(runtime.baseUrlHost).toBeNull();
    expect(runtime.warnings.join(' | ')).toContain('no es una URL válida');
  });

  it('avisa cuando no hay base ni modelo configurados', () => {
    const runtime = describeGuardianAiRuntime({ GUARDIAN_AI_API_KEY: 'clave-de-prueba' });
    const text = runtime.warnings.join(' | ');
    expect(text).toContain('api.openai.com');
    expect(text).toContain('gpt-4o-mini');
  });

  it('nunca devuelve la API key ni la URL completa', () => {
    const runtime = describeGuardianAiRuntime({
      GUARDIAN_AI_API_KEY: 'clave-de-prueba',
      GUARDIAN_AI_BASE_URL: 'https://api.deepseek.com/v1',
    });
    expect(JSON.stringify(runtime)).not.toContain('clave-de-prueba');
    expect(JSON.stringify(runtime)).not.toContain('https://');
  });
});
