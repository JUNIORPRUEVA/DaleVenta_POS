import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { resolveGuardianConfig } from './guardian.config';
import { GuardianCaptureRegistry, GuardianBackendErrorInput } from './guardian.capture.registry';
import { redactText } from './guardian.redaction';
import { buildFingerprint } from './guardian.fingerprint';
import { GuardianSeverity } from '@prisma/client';
import { GuardianDurableOutbox } from './guardian.durable-outbox';
import { GuardianAlertService } from './guardian.alert.service';
import { classifyBackendFailure, sanitizeOperation } from './telemetry/guardian.telemetry.classifier';

type BackendCaptureRecord = {
  input: Pick<GuardianBackendErrorInput,'method'|'status'|'requestId'|'userId'>;
  companyId:string; message:string; stack:string|null; exceptionType:string;
  fingerprint:string; path:string; occurredAt:string; eventId:string;
  module?:string; severity?:GuardianSeverity;
};

/**
 * Captura de errores 5xx del propio backend hacia Guardian.
 *
 * Salvaguardas:
 * - Solo se activa con `GUARDIAN_BACKEND_CAPTURE_ENABLED`.
 * - Ignora rutas `/guardian/*` (evita captura recursiva).
 * - Requiere `companyId` atribuible; sin empresa no se inventa una.
 * - Cola persistente fuera de las transacciones comerciales.
 * - Deduplica por empresa + firma + ventana de 60 s después del guardado local.
 */
@Injectable()
export class GuardianBackendCaptureService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(GuardianBackendCaptureService.name);
  private readonly recent = new Map<string, number>();
  private readonly pending = new Set<string>();
  private readonly outbox = new GuardianDurableOutbox<BackendCaptureRecord>(GuardianDurableOutbox.directory('backend'));
  private timer: NodeJS.Timeout | null = null;

  constructor(private readonly prisma: PrismaService, private readonly alerts: GuardianAlertService) {}

  onModuleInit() {
    const config = resolveGuardianConfig();
    if (!config.backendCaptureEnabled) return;
    GuardianCaptureRegistry.register((input) => this.capture(input));
    this.timer = setInterval(() => void this.flush().catch(() => this.logger.error('Guardian: no se pudo leer la cola persistente')), 5000);
    this.timer.unref();
    void this.flush().catch(() => this.logger.error('Guardian: no se pudo recuperar la cola persistente'));
  }

  onModuleDestroy() {
    GuardianCaptureRegistry.register(null);
    if (this.timer) clearInterval(this.timer);
  }

  private capture(input: GuardianBackendErrorInput) {
    const config = resolveGuardianConfig();
    if (!config.backendCaptureEnabled) return;

    const rawPath = String(input.path ?? '');
    if (rawPath.startsWith('/guardian') || rawPath.startsWith('/api/guardian')) return;

    const status = Number(input.status ?? 0);
    if (status < 500) return;

    const companyId = String(input.companyId ?? '').trim();
    if (!companyId) return;
    const classification = classifyBackendFailure(input);
    if (!classification) return;
    const operation = sanitizeOperation(input.method,rawPath);
    const path = operation.slice(operation.indexOf(' ') + 1);

    const message = redactText(input.message ?? '', 600);
    const stack = input.stack ? redactText(input.stack, config.maxStackChars) : null;
    const exceptionType = String(input.exceptionType ?? 'BackendError').slice(0, 120);

    const fingerprint = buildFingerprint({
      module: classification.module,
      operation,
      exceptionType,
      stack,
    });

    const now = Date.now();
    const key = `${companyId}:${fingerprint}`;
    const last = this.recent.get(key) ?? 0;
    if (now - last < 60_000 || this.pending.has(key)) return;
    if (this.recent.size > 500) {
      for (const [key, at] of this.recent) {
        if (now - at > 600_000) this.recent.delete(key);
      }
    }

    // Store only the sanitized allowlist, never the original request/error object.
    const safeInput = { method: input.method?.slice(0,16), status, requestId: input.requestId?.slice(0,128), userId: input.userId };
    this.pending.add(key);
    void this.outbox.enqueue({ input: safeInput, companyId, message, stack, exceptionType, fingerprint, path,
      occurredAt: new Date(now).toISOString(), eventId: `be-${fingerprint.slice(0, 24)}-${Math.floor(now / 60_000)}`,
      module:classification.module,severity:classification.severity as GuardianSeverity,
    }).then(async () => { this.pending.delete(key); this.recent.set(key, now); await this.flush(); }).catch(
      (error) => {
        this.pending.delete(key);
        this.logger.warn(
          `Guardian backend capture falló: ${error instanceof Error ? error.message : String(error)}`,
        );
      },
    );
  }

  async flush() {
    await this.outbox.flush(async params => {
      // Do not treat DB unavailability as opt-out: retain and retry the event.
      const company = await this.prisma.company.findUnique({ where: { id: params.companyId }, select: { guardianEnabled: true } });
      if (!company?.guardianEnabled) return;
      const incident = await this.prisma.guardianIncident.findUnique({ where: {
        companyId_eventId: { companyId: params.companyId, eventId: params.eventId },
      }, select: { id: true } });
      const id = incident?.id ?? await this.persist(params);
      await this.alerts.planForIncident(id);
    });
  }

  private async persist(params: BackendCaptureRecord) {
      const incident = await this.prisma.guardianIncident.create({
        data: {
          eventId: params.eventId,
          companyId: params.companyId,
          fingerprint: params.fingerprint,
          module: params.module ?? 'backend',
          operation: `${String(params.input.method ?? 'UNKNOWN').toUpperCase()} ${params.path}`.slice(0, 80),
          platform: 'backend',
          severity: params.severity ?? GuardianSeverity.SEV2,
          exceptionType: params.exceptionType,
          correlationId: params.input.requestId ?? null,
          stack: params.stack,
          occurredAt: new Date(params.occurredAt),
          userId: params.input.userId ?? null,
          payload: {
            message: params.message,
            status: Number(params.input.status ?? 500),
          },
          impactSummary: 'Error interno del servicio en la nube',
          evidences: {
            create: [
              ...(params.stack
                ? [
                    {
                      kind: 'stack',
                      label: 'Stack sanitizado',
                      sizeBytes: Buffer.byteLength(params.stack, 'utf8'),
                      content: { stack: params.stack },
                      redacted: true,
                    },
                  ]
                : []),
            ],
          },
          history: {
            create: [
              {
                fromStatus: null,
                toStatus: 'OPEN',
                actor: 'system:backend-capture',
                note: 'Capturado automáticamente por el filtro global',
              },
            ],
          },
        },
      });
      return incident.id;
  }
}
