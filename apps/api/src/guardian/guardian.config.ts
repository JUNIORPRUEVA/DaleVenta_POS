/**
 * APPYRA Guardian AI — configuración por entorno.
 *
 * Todos los interruptores son "fail-closed": si no se configura nada, Guardian
 * está desactivado. Nunca se activa por defecto en un entorno de clientes.
 */
export type GuardianConfig = {
  enabled: boolean;
  ingestEnabled: boolean;
  backendCaptureEnabled: boolean;
  diagnosisEnabled: boolean;
  alertsEnabled: boolean;
  maxBatchEvents: number;
  maxPayloadBytes: number;
  maxStackChars: number;
  alertsRecipient: string;
  alertsFallbackEmail: string;
  alertGroupWindowMinutes: number;
  diagnosisMaxAttempts: number;
  /** Presupuesto diario de tokens de IA por empresa (0 = sin límite). */
  aiTokensPerCompanyDay: number;
  /** Máximo de llamadas simultáneas al proveedor de IA. */
  aiMaxConcurrency: number;
  /** Interruptor explícito del canal Evolution reutilizando el outbox. */
  alertsEvolutionEnabled: boolean;
  platformToken: string;
};

function readBool(raw: string | undefined, fallback = false): boolean {
  const value = String(raw ?? '').trim().toLowerCase();
  if (!value) return fallback;
  return value === '1' || value === 'true' || value === 'yes' || value === 'on';
}

function readInt(raw: string | undefined, fallback: number, min: number, max: number): number {
  const parsed = Number.parseInt(String(raw ?? '').trim(), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

export function resolveGuardianConfig(env: NodeJS.ProcessEnv = process.env): GuardianConfig {
  const enabled = readBool(env.GUARDIAN_ENABLED, false);

  return {
    enabled,
    ingestEnabled: readBool(env.GUARDIAN_INGEST_ENABLED, enabled),
    backendCaptureEnabled: readBool(env.GUARDIAN_BACKEND_CAPTURE_ENABLED, false),
    diagnosisEnabled: readBool(env.GUARDIAN_DIAGNOSIS_ENABLED, false),
    alertsEnabled: readBool(env.GUARDIAN_ALERTS_ENABLED, false),
    maxBatchEvents: readInt(env.GUARDIAN_MAX_BATCH_EVENTS, 20, 1, 50),
    maxPayloadBytes: readInt(env.GUARDIAN_MAX_PAYLOAD_BYTES, 65_536, 1_024, 262_144),
    maxStackChars: readInt(env.GUARDIAN_MAX_STACK_CHARS, 20_000, 500, 60_000),
    alertsRecipient: String(env.GUARDIAN_ALERT_RECIPIENT ?? '').trim(),
    alertsFallbackEmail: String(env.GUARDIAN_ALERT_FALLBACK_EMAIL ?? '').trim(),
    alertGroupWindowMinutes: readInt(env.GUARDIAN_ALERT_GROUP_WINDOW_MINUTES, 30, 1, 720),
    diagnosisMaxAttempts: readInt(env.GUARDIAN_DIAGNOSIS_MAX_ATTEMPTS, 4, 1, 10),
    aiTokensPerCompanyDay: readInt(env.GUARDIAN_AI_TOKENS_PER_COMPANY_DAY, 200_000, 0, 100_000_000),
    aiMaxConcurrency: readInt(env.GUARDIAN_AI_MAX_CONCURRENCY, 2, 1, 10),
    alertsEvolutionEnabled: readBool(env.GUARDIAN_ALERTS_EVOLUTION_ENABLED, false),
    platformToken: String(env.GUARDIAN_PLATFORM_TOKEN ?? '').trim(),
  };
}

/**
 * Descripción del adaptador de IA realmente efectivo.
 *
 * Motivo: existe `GUARDIAN_AI_PROVIDER`, pero la fábrica del módulo decide
 * únicamente por `GUARDIAN_AI_API_KEY` y usa siempre el adaptador
 * OpenAI-compatible. Sin esta descripción, definir
 * `GUARDIAN_AI_PROVIDER=deepseek` daba la falsa impresión de activar un
 * proveedor distinto. Aquí se declara explícitamente que la variable es
 * informativa y se emiten las advertencias necesarias.
 */
export type GuardianAiRuntime = {
  /** Adaptador que se instancia de verdad. */
  adapter: 'openai-compatible' | 'mock';
  apiKeyPresent: boolean;
  /** Host configurado; nunca la URL completa con credenciales. */
  baseUrlHost: string | null;
  model: string;
  /** Valor declarado de `GUARDIAN_AI_PROVIDER`, si existe. */
  providerVariable: string | null;
  /** `false` siempre: la variable no cambia el adaptador. */
  providerVariableHonored: false;
  warnings: string[];
};

export function describeGuardianAiRuntime(
  env: NodeJS.ProcessEnv = process.env,
): GuardianAiRuntime {
  const apiKey = String(env.GUARDIAN_AI_API_KEY ?? '').trim();
  const rawBaseUrl = String(env.GUARDIAN_AI_BASE_URL ?? '').trim();
  const providerVariable = String(env.GUARDIAN_AI_PROVIDER ?? '').trim() || null;
  const model = String(env.GUARDIAN_AI_MODEL ?? '').trim();
  const warnings: string[] = [];

  let baseUrlHost: string | null = null;
  if (rawBaseUrl) {
    try {
      baseUrlHost = new URL(rawBaseUrl).host;
    } catch {
      baseUrlHost = null;
      warnings.push('GUARDIAN_AI_BASE_URL no es una URL válida: se usará el valor por defecto del adaptador');
    }
  }

  if (providerVariable && providerVariable.toLowerCase() !== 'openai') {
    warnings.push(
      `GUARDIAN_AI_PROVIDER=${providerVariable} no se usa: el adaptador efectivo es OpenAI-compatible ` +
        `y se selecciona solo por presencia de GUARDIAN_AI_API_KEY` +
        (baseUrlHost ? ` (host ${baseUrlHost})` : ''),
    );
  }

  if (!apiKey) {
    warnings.push('sin GUARDIAN_AI_API_KEY: se usará el proveedor mock y no se hará ninguna llamada externa');
  } else if (!rawBaseUrl) {
    warnings.push('sin GUARDIAN_AI_BASE_URL: el adaptador usará https://api.openai.com/v1 por defecto');
  }

  if (apiKey && !model) {
    warnings.push('sin GUARDIAN_AI_MODEL: el adaptador usará el modelo por defecto (gpt-4o-mini)');
  }

  return {
    adapter: apiKey ? 'openai-compatible' : 'mock',
    apiKeyPresent: apiKey.length > 0,
    baseUrlHost,
    model,
    providerVariable,
    providerVariableHonored: false,
    warnings,
  };
}
