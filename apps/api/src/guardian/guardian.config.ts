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
  /**
   * Espera máxima (segundos) a que el diagnóstico IA termine antes de enviar la
   * alerta en SEV2/SEV3. `0` desactiva la espera (envío inmediato). SEV1 nunca
   * espera. Por defecto 90 s.
   */
  alertDiagnosisWaitSeconds: number;
  diagnosisMaxAttempts: number;
  /**
   * Umbral de saldo (en la moneda que informe el proveedor) por debajo del cual
   * se considera saldo bajo y se avisa al administrador. No es una cuota: no
   * bloquea llamadas, solo decide cuándo avisar.
   */
  aiBalanceLowThreshold: number;
  /** Cada cuántos minutos se consulta el saldo del proveedor (worker). */
  aiBalanceCheckMinutes: number;
  /** Ventana anti-ruido entre avisos del mismo estado de saldo. */
  aiBalanceAlertCooldownMinutes: number;
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

function readFloat(raw: string | undefined, fallback: number, min: number, max: number): number {
  const parsed = Number.parseFloat(String(raw ?? '').trim().replace(',', '.'));
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
    alertDiagnosisWaitSeconds: readInt(env.GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS, 90, 0, 900),
    diagnosisMaxAttempts: readInt(env.GUARDIAN_DIAGNOSIS_MAX_ATTEMPTS, 4, 1, 10),
    aiBalanceLowThreshold: readFloat(env.GUARDIAN_AI_BALANCE_LOW_THRESHOLD, 5, 0, 1_000_000),
    aiBalanceCheckMinutes: readInt(env.GUARDIAN_AI_BALANCE_CHECK_MINUTES, 30, 5, 1_440),
    aiBalanceAlertCooldownMinutes: readInt(
      env.GUARDIAN_AI_BALANCE_ALERT_COOLDOWN_MINUTES,
      360,
      15,
      10_080,
    ),
    aiMaxConcurrency: readInt(env.GUARDIAN_AI_MAX_CONCURRENCY, 2, 1, 10),
    alertsEvolutionEnabled: readBool(env.GUARDIAN_ALERTS_EVOLUTION_ENABLED, false),
    platformToken: String(env.GUARDIAN_PLATFORM_TOKEN ?? '').trim(),
  };
}
