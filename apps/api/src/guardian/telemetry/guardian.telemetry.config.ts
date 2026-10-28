import { guardianSecretValue } from '../guardian.secret';

/**
 * Configuración del puente de telemetría DaleVentas POS → APPYRA Guardian.
 *
 * Todo es **fail-closed**: sin `GUARDIAN_TELEMETRY_ENABLED=true`, sin URL válida
 * y sin credencial de máquina, el puente no existe y el POS se comporta
 * exactamente igual que antes de esta integración.
 *
 * Nada de esto activa IA ni alertas: Guardian decide qué hacer con el incidente.
 */
export type GuardianTelemetryConfig = {
  enabled: boolean;
  /** Endpoint completo de ingesta por credencial de máquina. */
  url: string | null;
  apiKeyPresent: boolean;
  installId: string;
  platform: string;
  appVersion: string | null;
  timeoutMs: number;
  queueCapacity: number;
  batchSize: number;
  dedupeWindowMs: number;
  maxPerMinute: number;
  sampleRate: number;
  maxAttempts: number;
  flushIntervalMs: number;
  /** Problemas detectados; si hay alguno, `enabled` es siempre `false`. */
  problems: string[];
};

/**
 * Valor de relleno (nunca un dato de cliente) para instalaciones que no
 * declaran `GUARDIAN_TELEMETRY_INSTALL_ID`. Agrupa los eventos de esa
 * instalación sin inventar identidad.
 */
export const GUARDIAN_TELEMETRY_DEFAULT_INSTALL = 'pos-default';

function readBool(raw: string | undefined, fallback = false): boolean {
  const value = String(raw ?? '').trim().toLowerCase();
  if (!value) return fallback;
  return value === '1' || value === 'true' || value === 'yes' || value === 'on';
}

function readNumber(raw: string | undefined, fallback: number, min: number, max: number): number {
  const parsed = Number.parseFloat(String(raw ?? '').trim());
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function readInt(raw: string | undefined, fallback: number, min: number, max: number): number {
  return Math.round(readNumber(raw, fallback, min, max));
}

export function normalizeInstallId(raw: string | undefined): string {
  const clean = String(raw ?? '')
    .trim()
    .replace(/[^A-Za-z0-9._-]/g, '-')
    .replace(/-{2,}/g, '-')
    .replace(/^[-.]+|[-.]+$/g, '')
    .slice(0, 40);
  return clean || GUARDIAN_TELEMETRY_DEFAULT_INSTALL;
}

/** Acepta solo http(s) absoluta; rechaza cualquier otro esquema o valor raro. */
export function isValidTelemetryUrl(raw: string): boolean {
  try {
    const parsed = new URL(raw);
    return (parsed.protocol === 'http:' || parsed.protocol === 'https:') && Boolean(parsed.hostname);
  } catch {
    return false;
  }
}

export function resolveGuardianTelemetryConfig(
  env: NodeJS.ProcessEnv = process.env,
): GuardianTelemetryConfig {
  const requested = readBool(env.GUARDIAN_TELEMETRY_ENABLED, false);
  const rawUrl = String(env.GUARDIAN_TELEMETRY_URL ?? '').trim();
  const key = guardianSecretValue(env, 'GUARDIAN_TELEMETRY_KEY');
  const problems: string[] = [];

  if (requested && !rawUrl) problems.push('GUARDIAN_TELEMETRY_URL no está definida');
  if (requested && rawUrl && !isValidTelemetryUrl(rawUrl)) {
    problems.push('GUARDIAN_TELEMETRY_URL no es una URL http(s) válida');
  }
  if (requested && !key) {
    problems.push('GUARDIAN_TELEMETRY_KEY no está disponible (ni su variante _FILE)');
  }

  return {
    enabled: requested && problems.length === 0,
    url: rawUrl && isValidTelemetryUrl(rawUrl) ? rawUrl : null,
    apiKeyPresent: Boolean(key),
    installId: normalizeInstallId(env.GUARDIAN_TELEMETRY_INSTALL_ID),
    platform: String(env.GUARDIAN_TELEMETRY_PLATFORM ?? 'backend')
      .trim()
      .slice(0, 24) || 'backend',
    appVersion: String(env.GUARDIAN_TELEMETRY_APP_VERSION ?? env.APP_VERSION ?? '').trim().slice(0, 40) || null,
    timeoutMs: readInt(env.GUARDIAN_TELEMETRY_TIMEOUT_MS, 3_000, 200, 10_000),
    queueCapacity: readInt(env.GUARDIAN_TELEMETRY_QUEUE_CAPACITY, 100, 1, 1_000),
    batchSize: readInt(env.GUARDIAN_TELEMETRY_BATCH_SIZE, 5, 1, 20),
    dedupeWindowMs: readInt(env.GUARDIAN_TELEMETRY_DEDUPE_WINDOW_MS, 60_000, 0, 3_600_000),
    maxPerMinute: readInt(env.GUARDIAN_TELEMETRY_MAX_PER_MINUTE, 30, 0, 600),
    sampleRate: readNumber(env.GUARDIAN_TELEMETRY_SAMPLE_RATE, 1, 0, 1),
    maxAttempts: readInt(env.GUARDIAN_TELEMETRY_MAX_ATTEMPTS, 2, 1, 3),
    flushIntervalMs: readInt(env.GUARDIAN_TELEMETRY_FLUSH_INTERVAL_MS, 2_000, 200, 60_000),
    problems,
  };
}

/** Resumen imprimible (sin credencial) para el arranque del servicio. */
export function describeGuardianTelemetryConfig(config: GuardianTelemetryConfig): string {
  return JSON.stringify({
    enabled: config.enabled,
    url: config.url,
    apiKeyPresent: config.apiKeyPresent,
    installId: config.installId,
    platform: config.platform,
    appVersion: config.appVersion,
    timeoutMs: config.timeoutMs,
    queueCapacity: config.queueCapacity,
    batchSize: config.batchSize,
    dedupeWindowMs: config.dedupeWindowMs,
    maxPerMinute: config.maxPerMinute,
    sampleRate: config.sampleRate,
    maxAttempts: config.maxAttempts,
    problems: config.problems,
  });
}
