import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { GuardianCaptureRegistry, GuardianBackendErrorInput } from '../guardian.capture.registry';
import { buildFingerprint } from '../guardian.fingerprint';
import { redactContext, redactText } from '../guardian.redaction';
import { guardianSecretValue } from '../guardian.secret';
import {
  GuardianTelemetryConfig,
  describeGuardianTelemetryConfig,
  resolveGuardianTelemetryConfig,
} from './guardian.telemetry.config';
import {
  GuardianTelemetryClassification,
  classifyBackendFailure,
  sanitizeOperation,
} from './guardian.telemetry.classifier';

export type GuardianTelemetryEvent = {
  eventId: string;
  severity: string;
  module: string;
  operation: string;
  exceptionType?: string;
  platform: string;
  appVersion?: string;
  correlationId?: string;
  stack?: string;
  message?: string;
  occurredAt: string;
  schemaVersion: number;
  context: Record<string, unknown>;
};

export type GuardianTelemetryStats = {
  received: number;
  queued: number;
  sent: number;
  accepted: number;
  duplicatesRemote: number;
  rejectedRemote: number;
  droppedBusinessRule: number;
  droppedDuplicate: number;
  droppedSample: number;
  droppedRateLimit: number;
  droppedQueueFull: number;
  droppedAfterAttempts: number;
  failedAttempts: number;
  lastError: string | null;
  lastSuccessAt: string | null;
};

/**
 * Puente de telemetría DaleVentas POS → APPYRA Guardian.
 *
 * Contrato (no negociable):
 * - **No bloquea**: `offer()` solo encola en memoria y retorna; el envío ocurre
 *   en un temporizador con `unref()`.
 * - **No lanza**: cualquier fallo interno se captura y se cuenta. Un error de
 *   telemetría jamás puede convertirse en un error de negocio.
 * - **No toca transacciones**: no participa en ninguna transacción de Prisma ni
 *   se invoca desde dentro de una; solo desde el filtro global de excepciones y
 *   desde tareas de fondo, siempre después de responder o de fallar.
 * - **Acotado**: cola con capacidad fija (descarta el más antiguo), lote máximo,
 *   timeout absoluto por petición, reintentos limitados y caudal por minuto.
 * - **Fail-open**: si Guardian no responde, se descarta y se sigue operando.
 */
@Injectable()
export class GuardianTelemetryBridgeService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(GuardianTelemetryBridgeService.name);
  private config: GuardianTelemetryConfig;
  private readonly queue: GuardianTelemetryEvent[] = [];
  private readonly recent = new Map<string, number>();
  private timer: NodeJS.Timeout | null = null;
  private flushing = false;
  private rateWindow: { startedAt: number; count: number } = { startedAt: 0, count: 0 };
  private readonly stats: GuardianTelemetryStats = {
    received: 0,
    queued: 0,
    sent: 0,
    accepted: 0,
    duplicatesRemote: 0,
    rejectedRemote: 0,
    droppedBusinessRule: 0,
    droppedDuplicate: 0,
    droppedSample: 0,
    droppedRateLimit: 0,
    droppedQueueFull: 0,
    droppedAfterAttempts: 0,
    failedAttempts: 0,
    lastError: null,
    lastSuccessAt: null,
  };

  constructor() {
    this.config = resolveGuardianTelemetryConfig();
  }

  onModuleInit() {
    this.config = resolveGuardianTelemetryConfig();
    if (!this.config.enabled) {
      if (this.config.problems.length) {
        this.logger.warn(
          `Telemetría Guardian deshabilitada: ${this.config.problems.join('; ')}`,
        );
      }
      return;
    }

    this.logger.log(`Telemetría Guardian activa ${describeGuardianTelemetryConfig(this.config)}`);
    GuardianCaptureRegistry.registerBridge((input) => this.offer(input));

    this.timer = setInterval(() => {
      void this.flush();
    }, this.config.flushIntervalMs);
    this.timer.unref?.();
  }

  onModuleDestroy() {
    GuardianCaptureRegistry.registerBridge(null);
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    // Intento final best-effort; nunca bloquea el apagado más que el timeout.
    void this.flush();
  }

  /** Diagnóstico para pruebas y para el panel (sin credenciales). */
  snapshot(): { config: GuardianTelemetryConfig; stats: GuardianTelemetryStats; queued: number } {
    return { config: this.config, stats: { ...this.stats }, queued: this.queue.length };
  }

  /**
   * Punto de entrada único. Se invoca desde el registro del filtro global de
   * excepciones y desde tareas de fondo. Nunca propaga excepciones.
   */
  offer(input: GuardianBackendErrorInput): void {
    try {
      if (!this.config.enabled) return;
      this.stats.received += 1;

      const classification = classifyBackendFailure({
        method: input.method,
        path: input.path,
        status: input.status,
        exceptionType: input.exceptionType,
        message: input.message,
        stack: input.stack,
        prismaCode: input.prismaCode ?? null,
        prismaKind: input.prismaKind ?? null,
      });

      if (!classification) {
        this.stats.droppedBusinessRule += 1;
        return;
      }

      const message = redactText(input.message ?? '', 600);
      const stack = input.stack ? redactText(input.stack, 20_000) : null;
      const exceptionType = String(input.exceptionType ?? 'BackendError').slice(0, 120);
      const operation = sanitizeOperation(input.method, input.path);

      const fingerprint = buildFingerprint({
        module: classification.module,
        operation,
        exceptionType,
        stack,
        appVersion: this.config.appVersion,
      });

      if (!this.acceptByDedupe(fingerprint)) return;
      if (!this.acceptByRateLimit()) return;
      if (!this.acceptBySample(fingerprint)) return;

      const event = this.buildEvent({
        input,
        classification,
        fingerprint,
        message,
        stack,
        exceptionType,
        operation,
      });

      this.enqueue(event);
    } catch (error) {
      // Silencio operativo: la telemetría no puede romper el POS.
      this.stats.lastError = error instanceof Error ? error.message : String(error);
    }
  }

  private acceptByDedupe(fingerprint: string): boolean {
    if (this.config.dedupeWindowMs <= 0) return true;
    const now = Date.now();
    const last = this.recent.get(fingerprint) ?? 0;
    if (now - last < this.config.dedupeWindowMs) {
      this.stats.droppedDuplicate += 1;
      return false;
    }
    this.recent.set(fingerprint, now);
    if (this.recent.size > 500) {
      for (const [key, at] of this.recent) {
        if (now - at > this.config.dedupeWindowMs * 5) this.recent.delete(key);
      }
    }
    return true;
  }

  private acceptByRateLimit(): boolean {
    if (this.config.maxPerMinute <= 0) return true;
    const now = Date.now();
    if (now - this.rateWindow.startedAt >= 60_000) {
      this.rateWindow = { startedAt: now, count: 0 };
    }
    if (this.rateWindow.count >= this.config.maxPerMinute) {
      this.stats.droppedRateLimit += 1;
      return false;
    }
    this.rateWindow.count += 1;
    return true;
  }

  /**
   * Muestreo determinista por firma: la misma firma se muestrea siempre igual,
   * así no se pierden patrones completos ni se duplican parciales.
   */
  private acceptBySample(fingerprint: string): boolean {
    const rate = this.config.sampleRate;
    if (rate >= 1) return true;
    if (rate <= 0) {
      this.stats.droppedSample += 1;
      return false;
    }
    const bucket = parseInt(createHash('sha256').update(fingerprint).digest('hex').slice(0, 8), 16);
    const accepted = bucket / 0xffffffff < rate;
    if (!accepted) this.stats.droppedSample += 1;
    return accepted;
  }

  private buildEvent(params: {
    input: GuardianBackendErrorInput;
    classification: GuardianTelemetryClassification;
    fingerprint: string;
    message: string;
    stack: string | null;
    exceptionType: string;
    operation: string;
  }): GuardianTelemetryEvent {
    const now = new Date();
    const bucket = Math.floor(now.getTime() / 60_000);
    const eventId = `pos.${this.config.installId}.${params.fingerprint.slice(0, 16)}.${bucket}`.slice(0, 120);

    const context = redactContext({
      source: 'backend',
      method: String(params.input.method ?? 'UNKNOWN').toUpperCase().slice(0, 10),
      route: params.operation,
      httpStatus: Number(params.input.status ?? 500),
      retryable: params.classification.retryable,
      installId: this.config.installId,
      requestId: params.input.requestId ?? undefined,
      ...(params.input.context ?? {}),
    }) as Record<string, unknown>;

    return {
      eventId,
      severity: params.classification.severity,
      module: params.classification.module,
      operation: params.operation,
      exceptionType: params.exceptionType,
      platform: this.config.platform,
      ...(this.config.appVersion ? { appVersion: this.config.appVersion } : {}),
      ...(params.input.requestId ? { correlationId: String(params.input.requestId).slice(0, 128) } : {}),
      ...(params.stack ? { stack: params.stack } : {}),
      ...(params.message ? { message: params.message } : {}),
      occurredAt: now.toISOString(),
      schemaVersion: 1,
      context,
    };
  }

  private enqueue(event: GuardianTelemetryEvent): void {
    if (this.queue.length >= this.config.queueCapacity) {
      this.queue.shift();
      this.stats.droppedQueueFull += 1;
    }
    this.queue.push(event);
    this.stats.queued += 1;
  }

  /** Envía un lote. Nunca lanza; los fallos se cuentan y se descartan. */
  async flush(): Promise<void> {
    if (!this.config.enabled || this.flushing || this.queue.length === 0) return;
    this.flushing = true;
    try {
      while (this.queue.length > 0) {
        const batch = this.queue.splice(0, this.config.batchSize);
        await this.postBatch(batch);
      }
    } catch (error) {
      this.stats.lastError = error instanceof Error ? error.message : String(error);
    } finally {
      this.flushing = false;
    }
  }

  private async postBatch(batch: GuardianTelemetryEvent[]): Promise<void> {
    const url = this.config.url;
    const key = guardianSecretValue(process.env, 'GUARDIAN_TELEMETRY_KEY');
    if (!url || !key) return;

    for (let attempt = 1; attempt <= this.config.maxAttempts; attempt += 1) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), this.config.timeoutMs);
      try {
        const response = await fetch(url, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-guardian-key': key,
            'x-guardian-ts': String(Math.floor(Date.now() / 1000)),
            'user-agent': `daleventa-pos-telemetry/${this.config.appVersion ?? 'dev'}`,
          },
          body: JSON.stringify({ events: batch }),
          signal: controller.signal,
        });

        this.stats.sent += 1;

        if (response.ok) {
          const payload = (await response.json().catch(() => null)) as
            | { accepted?: number; duplicates?: number; rejected?: number }
            | null;
          this.stats.accepted += Number(payload?.accepted ?? 0);
          this.stats.duplicatesRemote += Number(payload?.duplicates ?? 0);
          this.stats.rejectedRemote += Number(payload?.rejected ?? 0);
          this.stats.lastSuccessAt = new Date().toISOString();
          return;
        }

        // 4xx (salvo 408/429) = problema nuestro: reintentar no ayuda.
        const retryable = response.status >= 500 || response.status === 408 || response.status === 429;
        this.stats.lastError = `HTTP ${response.status}`;
        if (!retryable) {
          this.stats.rejectedRemote += batch.length;
          return;
        }
      } catch (error) {
        this.stats.failedAttempts += 1;
        this.stats.lastError =
          error instanceof Error
            ? error.name === 'AbortError'
              ? `timeout tras ${this.config.timeoutMs}ms`
              : error.message
            : String(error);
      } finally {
        clearTimeout(timeout);
      }

      if (attempt < this.config.maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, 150 * attempt));
      }
    }

    this.stats.droppedAfterAttempts += batch.length;
  }
}

/** Identificador de correlación local para tareas de fondo (nunca PII). */
export function newGuardianJobCorrelationId(): string {
  return `job-${randomUUID()}`;
}
