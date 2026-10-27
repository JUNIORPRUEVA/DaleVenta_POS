/**
 * APPYRA Guardian AI — resolución del proveedor de IA realmente efectivo.
 *
 * Motivo de este módulo: `GUARDIAN_AI_PROVIDER` existía en la documentación
 * pero la fábrica del módulo decidía solo por presencia de `GUARDIAN_AI_API_KEY`
 * y siempre instanciaba el adaptador OpenAI-compatible. Configurar
 * `GUARDIAN_AI_PROVIDER=deepseek` daba la falsa impresión de cambiar de
 * proveedor.
 *
 * Aquí la variable SÍ se honra de forma explícita, con tres adaptadores:
 * - `deepseek`: API OpenAI-compatible de DeepSeek (por defecto
 *   `https://api.deepseek.com/v1`, modelo `deepseek-flash`).
 * - `openai`: API OpenAI (por defecto `https://api.openai.com/v1`,
 *   modelo `gpt-4o-mini`).
 * - `mock`: proveedor determinista local, sin llamadas externas.
 *
 * Reglas duras (fail-closed):
 * - La credencial es SIEMPRE `GUARDIAN_AI_API_KEY`. Nunca se reutiliza
 *   `OPENAI_API_KEY` ni la clave de otro producto: mezclaría facturación.
 * - Si el proveedor declarado y el host de `GUARDIAN_AI_BASE_URL` no
 *   corresponden, se degrada a `mock` en lugar de enviar la clave a un host
 *   equivocado.
 * - Un modelo no reconocido para el proveedor declarado degrada a `mock`.
 * - Cualquier degradación queda registrada en `errors` con un código estable
 *   para que el panel pueda mostrarla sin exponer secretos.
 *
 * Modelos admitidos de DeepSeek: verificados en la documentación oficial
 * (`https://api-docs.deepseek.com/api/create-chat-completion` y
 * `https://api-docs.deepseek.com/api/list-models`, consultada el 2026-10-26):
 * `deepseek-flash` y `deepseek-v4-pro`.
 */

export type GuardianAiAdapterKind = 'mock' | 'openai' | 'deepseek';

export type GuardianAiRuntimeErrorCode =
  | 'AI_PROVIDER_UNKNOWN'
  | 'AI_API_KEY_MISSING'
  | 'AI_BASE_URL_INVALID'
  | 'AI_BASE_URL_MISMATCH'
  | 'AI_MODEL_UNSUPPORTED';

export type GuardianAiRuntime = {
  /** Adaptador que se instancia de verdad. */
  adapter: GuardianAiAdapterKind;
  /** Valor normalizado de `GUARDIAN_AI_PROVIDER` (o `null` si no se definió). */
  providerVariable: string | null;
  apiKeyPresent: boolean;
  /** Base URL efectiva; `null` cuando el adaptador es `mock`. */
  baseUrl: string | null;
  /** Host efectivo, sin credenciales ni ruta: seguro para logs. */
  baseUrlHost: string | null;
  /** Modelo efectivo. */
  model: string;
  modelSupported: boolean;
  timeoutMs: number;
  maxTokens: number;
  maxConcurrent: number;
  /** Códigos de error de configuración (degradaciones a mock). */
  errors: GuardianAiRuntimeErrorCode[];
  /** Advertencias legibles, sin secretos. */
  warnings: string[];
};

export const GUARDIAN_AI_DEFAULT_TIMEOUT_MS = 20_000;
export const GUARDIAN_AI_DEFAULT_MAX_TOKENS = 900;
export const GUARDIAN_AI_DEFAULT_MAX_CONCURRENCY = 2;

export const GUARDIAN_DEEPSEEK_DEFAULT_BASE_URL = 'https://api.deepseek.com/v1';
export const GUARDIAN_DEEPSEEK_DEFAULT_MODEL = 'deepseek-flash';
export const GUARDIAN_DEEPSEEK_BASE_URL_HOSTS = ['api.deepseek.com'];
export const GUARDIAN_DEEPSEEK_MODELS = ['deepseek-flash', 'deepseek-v4-pro'] as const;

export const GUARDIAN_OPENAI_DEFAULT_BASE_URL = 'https://api.openai.com/v1';
export const GUARDIAN_OPENAI_DEFAULT_MODEL = 'gpt-4o-mini';
export const GUARDIAN_OPENAI_BASE_URL_HOSTS = ['api.openai.com'];

const PROVIDER_ALIASES: Record<string, GuardianAiAdapterKind> = {
  deepseek: 'deepseek',
  openai: 'openai',
  'openai-compatible': 'openai',
  mock: 'mock',
  none: 'mock',
};

function read(env: NodeJS.ProcessEnv, name: string): string {
  return String(env[name] ?? '').trim();
}

function readPositiveInt(raw: string, fallback: number, min: number, max: number): number {
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function parseHost(raw: string): string | null {
  try {
    return new URL(raw).host.toLowerCase();
  } catch {
    return null;
  }
}

function hostMatches(host: string, allowed: readonly string[]): boolean {
  return allowed.some((entry) => host === entry || host.endsWith(`.${entry}`));
}

/**
 * Resuelve el adaptador efectivo a partir del entorno.
 *
 * No lanza excepciones: devuelve siempre un runtime utilizable. Cuando algo no
 * es válido, el adaptador es `mock` y el motivo aparece en `errors`.
 */
export function resolveGuardianAiRuntime(
  env: NodeJS.ProcessEnv = process.env,
): GuardianAiRuntime {
  const apiKey = read(env, 'GUARDIAN_AI_API_KEY');
  const rawProvider = read(env, 'GUARDIAN_AI_PROVIDER');
  const providerVariable = rawProvider || null;
  const rawBaseUrl = read(env, 'GUARDIAN_AI_BASE_URL');
  const rawModel = read(env, 'GUARDIAN_AI_MODEL');

  const timeoutMs = readPositiveInt(read(env, 'GUARDIAN_AI_TIMEOUT_MS'), GUARDIAN_AI_DEFAULT_TIMEOUT_MS, 1_000, 120_000);
  const maxTokens = readPositiveInt(read(env, 'GUARDIAN_AI_MAX_TOKENS'), GUARDIAN_AI_DEFAULT_MAX_TOKENS, 64, 8_192);
  const maxConcurrent = readPositiveInt(
    read(env, 'GUARDIAN_AI_MAX_CONCURRENCY'),
    GUARDIAN_AI_DEFAULT_MAX_CONCURRENCY,
    1,
    10,
  );

  const errors: GuardianAiRuntimeErrorCode[] = [];
  const warnings: string[] = [];

  // 1. Proveedor declarado.
  const requested: GuardianAiAdapterKind | null =
    providerVariable === null ? null : (PROVIDER_ALIASES[providerVariable.toLowerCase()] ?? null);

  if (providerVariable !== null && requested === null) {
    errors.push('AI_PROVIDER_UNKNOWN');
    warnings.push(
      `GUARDIAN_AI_PROVIDER="${providerVariable}" no es un proveedor conocido ` +
        '(valores admitidos: deepseek, openai, mock). Se usa el proveedor mock.',
    );
  }

  // Sin credencial: cualquier proveedor real se degrada a mock.
  if (!apiKey) {
    if (requested && requested !== 'mock') {
      errors.push('AI_API_KEY_MISSING');
      warnings.push(
        `GUARDIAN_AI_PROVIDER=${requested} sin GUARDIAN_AI_API_KEY: se usa el proveedor mock y no se ` +
          'hará ninguna llamada externa.',
      );
    } else {
      warnings.push('sin GUARDIAN_AI_API_KEY: se usa el proveedor mock (sin llamadas externas).');
    }
    return {
      adapter: 'mock',
      providerVariable,
      apiKeyPresent: false,
      baseUrl: null,
      baseUrlHost: null,
      model: 'mock',
      modelSupported: true,
      timeoutMs,
      maxTokens,
      maxConcurrent,
      errors,
      warnings,
    };
  }

  // 2. Proveedor efectivo: declarado, o inferido por host de la base URL.
  const declaredHost = rawBaseUrl ? parseHost(rawBaseUrl) : null;
  let adapter: GuardianAiAdapterKind;
  if (requested && requested !== 'mock') {
    adapter = requested;
  } else if (declaredHost && hostMatches(declaredHost, GUARDIAN_DEEPSEEK_BASE_URL_HOSTS)) {
    adapter = 'deepseek';
  } else {
    adapter = 'openai';
  }

  if (requested === 'mock' && apiKey) {
    warnings.push(
      'GUARDIAN_AI_PROVIDER=mock con GUARDIAN_AI_API_KEY definida: se respeta el proveedor mock y no se ' +
        'hará ninguna llamada externa.',
    );
    return {
      adapter: 'mock',
      providerVariable,
      apiKeyPresent: true,
      baseUrl: null,
      baseUrlHost: null,
      model: 'mock',
      modelSupported: true,
      timeoutMs,
      maxTokens,
      maxConcurrent,
      errors,
      warnings,
    };
  }

  const defaultBaseUrl =
    adapter === 'deepseek' ? GUARDIAN_DEEPSEEK_DEFAULT_BASE_URL : GUARDIAN_OPENAI_DEFAULT_BASE_URL;
  const defaultModel =
    adapter === 'deepseek' ? GUARDIAN_DEEPSEEK_DEFAULT_MODEL : GUARDIAN_OPENAI_DEFAULT_MODEL;

  // 3. Base URL: se valida formato y coherencia con el proveedor.
  let baseUrl = defaultBaseUrl;
  if (rawBaseUrl) {
    const host = parseHost(rawBaseUrl);
    if (!host) {
      errors.push('AI_BASE_URL_INVALID');
      warnings.push('GUARDIAN_AI_BASE_URL no es una URL válida: se usa el valor por defecto del proveedor.');
    } else {
      const allowed =
        adapter === 'deepseek' ? GUARDIAN_DEEPSEEK_BASE_URL_HOSTS : GUARDIAN_OPENAI_BASE_URL_HOSTS;
      if (!hostMatches(host, allowed)) {
        errors.push('AI_BASE_URL_MISMATCH');
        warnings.push(
          `GUARDIAN_AI_BASE_URL apunta a "${host}", que no corresponde al proveedor ${adapter}: ` +
            'no se envía la credencial a un host distinto y se usa el proveedor mock.',
        );
      } else {
        baseUrl = rawBaseUrl.replace(/\/+$/, '');
      }
    }
  }

  // 4. Modelo: se exige uno admitido por el proveedor declarado.
  const model = rawModel || defaultModel;
  const supportedModels =
    adapter === 'deepseek' ? GUARDIAN_DEEPSEEK_MODELS : adapter === 'openai' ? null : [];
  let modelSupported = true;
  if (adapter === 'deepseek') {
    modelSupported = (GUARDIAN_DEEPSEEK_MODELS as readonly string[]).includes(model);
    if (!modelSupported) {
      errors.push('AI_MODEL_UNSUPPORTED');
      warnings.push(
        `GUARDIAN_AI_MODEL="${model}" no está entre los modelos admitidos de DeepSeek ` +
          `(${GUARDIAN_DEEPSEEK_MODELS.join(', ')}). Se usa el proveedor mock.`,
      );
    }
  } else if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{1,80}$/.test(model)) {
    modelSupported = false;
    errors.push('AI_MODEL_UNSUPPORTED');
    warnings.push(`GUARDIAN_AI_MODEL="${model}" no tiene un formato de identificador válido: se usa el mock.`);
  }

  const blocked = errors.some(
    (code) =>
      code === 'AI_BASE_URL_INVALID' ||
      code === 'AI_BASE_URL_MISMATCH' ||
      code === 'AI_MODEL_UNSUPPORTED' ||
      code === 'AI_PROVIDER_UNKNOWN',
  );

  if (blocked) {
    return {
      adapter: 'mock',
      providerVariable,
      apiKeyPresent: true,
      baseUrl: null,
      baseUrlHost: null,
      model: 'mock',
      modelSupported: false,
      timeoutMs,
      maxTokens,
      maxConcurrent,
      errors,
      warnings,
    };
  }

  return {
    adapter,
    providerVariable,
    apiKeyPresent: true,
    baseUrl,
    baseUrlHost: parseHost(baseUrl),
    model,
    modelSupported,
    timeoutMs,
    maxTokens,
    maxConcurrent,
    errors,
    warnings,
  };
}

/** Resumen apto para logs y para el panel: nunca contiene la credencial. */
export function describeGuardianAiRuntime(runtime: GuardianAiRuntime): string {
  return (
    `adaptador=${runtime.adapter} host=${runtime.baseUrlHost ?? 'local'} modelo=${runtime.model} ` +
    `tokens_max=${runtime.maxTokens} timeout_ms=${runtime.timeoutMs} errores=${runtime.errors.join('|') || 'ninguno'}`
  );
}
