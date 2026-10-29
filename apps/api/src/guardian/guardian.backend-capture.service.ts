import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { resolveGuardianConfig } from './guardian.config';
import { GuardianCaptureRegistry, GuardianBackendErrorInput } from './guardian.capture.registry';
import { redactText } from './guardian.redaction';
import { buildFingerprint } from './guardian.fingerprint';
import { GuardianSeverity } from '@prisma/client';

/**
 * Captura de errores 5xx del propio backend hacia Guardian.
 *
 * Salvaguardas:
 * - Solo se activa con `GUARDIAN_BACKEND_CAPTURE_ENABLED`.
 * - Ignora rutas `/guardian/*` (evita captura recursiva).
 * - Requiere `companyId` atribuible; sin empresa no se inventa una.
 * - Fire-and-forget con guardia de reentrada: nunca retrasa ni altera la respuesta.
 * - Deduplica por firma + ventana de 60 s en memoria para no inundar la tabla.
 */
@Injectable()
export class GuardianBackendCaptureService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(GuardianBackendCaptureService.name);
  private readonly recent = new Map<string, number>();
  private inFlight = false;

  constructor(private readonly prisma: PrismaService) {}

  onModuleInit() {
    const config = resolveGuardianConfig();
    if (!config.backendCaptureEnabled) return;
    GuardianCaptureRegistry.register((input) => this.capture(input));
  }

  onModuleDestroy() {
    GuardianCaptureRegistry.register(null);
  }

  private capture(input: GuardianBackendErrorInput) {
    const config = resolveGuardianConfig();
    if (!config.backendCaptureEnabled) return;

    const path = String(input.path ?? '');
    if (path.startsWith('/guardian') || path.startsWith('/api/guardian')) return;

    const status = Number(input.status ?? 0);
    if (status < 500) return;

    const companyId = String(input.companyId ?? '').trim();
    if (!companyId) return;

    const message = redactText(input.message ?? '', 600);
    const stack = input.stack ? redactText(input.stack, config.maxStackChars) : null;
    const exceptionType = String(input.exceptionType ?? 'BackendError').slice(0, 120);

    const fingerprint = buildFingerprint({
      module: 'backend',
      operation: `${String(input.method ?? 'UNKNOWN').toUpperCase()} ${path}`.slice(0, 80),
      exceptionType,
      stack,
    });

    const now = Date.now();
    const last = this.recent.get(fingerprint) ?? 0;
    if (now - last < 60_000) return;
    this.recent.set(fingerprint, now);
    if (this.recent.size > 500) {
      for (const [key, at] of this.recent) {
        if (now - at > 600_000) this.recent.delete(key);
      }
    }

    void this.persist({ input, companyId, message, stack, exceptionType, fingerprint, path }).catch(
      (error) => {
        this.logger.warn(
          `Guardian backend capture falló: ${error instanceof Error ? error.message : String(error)}`,
        );
      },
    );
  }

  private async persist(params: {
    input: GuardianBackendErrorInput;
    companyId: string;
    message: string;
    stack: string | null;
    exceptionType: string;
    fingerprint: string;
    path: string;
  }) {
    if (this.inFlight) return;
    this.inFlight = true;

    try {
      const now = new Date();
      const eventId = `be-${params.fingerprint.slice(0, 24)}-${Math.floor(now.getTime() / 60_000)}`;

      await this.prisma.guardianIncident.create({
        data: {
          eventId,
          companyId: params.companyId,
          fingerprint: params.fingerprint,
          module: 'backend',
          operation: `${String(params.input.method ?? 'UNKNOWN').toUpperCase()} ${params.path}`.slice(0, 80),
          platform: 'backend',
          severity: GuardianSeverity.SEV2,
          exceptionType: params.exceptionType,
          correlationId: params.input.requestId ?? null,
          stack: params.stack,
          occurredAt: now,
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
    } finally {
      this.inFlight = false;
    }
  }
}
