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
