import { Injectable, Logger } from '@nestjs/common';
import { GuardianProcessingState, GuardianSeverity, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { resolveGuardianConfig } from './guardian.config';
import { buildFingerprint } from './guardian.fingerprint';
import { GuardianIngestResultItem, GuardianIngestEventDto } from './dto/guardian-ingest.dto';
import { redactContext, redactText } from './guardian.redaction';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianAlertService } from './guardian.alert.service';

const IMPACT_BY_MODULE: Record<string, string> = {
  cash: 'Posible impacto en caja o turnos',
  sales: 'Posible impacto en el registro de ventas',
  inventory: 'Posible impacto en inventario o stock',
  sync: 'Posible retraso de sincronización entre dispositivos',
  license: 'Posible impacto en el uso de licencia',
  updater: 'Posible impacto en la actualización del sistema',
  fiscal: 'Posible impacto en comprobantes fiscales',
  printing: 'Posible impacto en impresión de comprobantes',
  auth: 'Posible impacto en el acceso de usuarios',
  reporting: 'Posible impacto en reportes',
  network: 'Posible impacto por conectividad',
  backend: 'Posible impacto en el servicio en la nube',
  flutter: 'Posible impacto en la aplicación',
  unknown: 'Impacto pendiente de determinar',
};

export type GuardianIngestOutcome = {
  ok: boolean;
  accepted: number;
  duplicates: number;
  rejected: number;
  results: GuardianIngestResultItem[];
};

/**
 * Ingesta de incidentes.
 *
 * Reglas duras:
 * - `companyId` llega resuelto por el servidor (sesión JWT); nunca del body.
 * - Se persiste antes de confirmar; un fallo de persistencia no devuelve "aceptado".
 * - No se ejecuta IA ni se envían mensajes dentro de la petición HTTP.
 * - Un evento inválido no invalida el resto del lote.
 */
@Injectable()
export class GuardianIngestService {
  private readonly logger = new Logger(GuardianIngestService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly quota: GuardianQuotaService,
    private readonly alerts?: GuardianAlertService,
  ) {}

  async ingestBatch(params: {
    companyId: string;
    userId?: string | null;
    events: GuardianIngestEventDto[];
    requestId?: string | null;
  }): Promise<GuardianIngestOutcome> {
    const config = resolveGuardianConfig();
    const events = params.events.slice(0, config.maxBatchEvents);

    const deviceIds = events
      .map((event) => String(event.deviceId ?? '').trim())
      .filter((value) => value.length > 0);

    const decision = await this.quota.evaluate({
      companyId: params.companyId,
      deviceIds,
      requestedEvents: events.length,
    });

    if (!decision.allowed) {
      return {
        ok: false,
        accepted: 0,
        duplicates: 0,
        rejected: events.length,
        results: events.map((event) => ({
          eventId: event.eventId,
          status: 'rejected' as const,
          reason: decision.reason,
          severity: event.severity,
        })),
      };
    }

    const results: GuardianIngestResultItem[] = [];

    for (const event of events) {
      try {
        const result = await this.persistOne({
          companyId: params.companyId,
          userId: params.userId ?? null,
          event,
          requestId: params.requestId ?? null,
          maxStackChars: config.maxStackChars,
        });
        results.push(result);

        // Alerta administrativa: se encola aquí (escritura barata) pero NO se
        // envía en esta petición. El worker de alertas la procesa en segundos.
        if (result.status === 'accepted' && result.incidentId && this.alerts) {
          await this.alerts.planForIncident(result.incidentId).catch((error) => {
            this.logger.warn(
              `No se pudo planificar la alerta del incidente ${result.incidentId}: ${
                error instanceof Error ? error.message : String(error)
              }`,
            );
          });
        }
      } catch (error) {
        this.logger.error(
          `Guardian ingest fallo compania=${params.companyId} eventId=${event.eventId}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
        results.push({
          eventId: event.eventId,
          status: 'rejected',
          reason: 'PERSIST_FAILED',
          severity: event.severity,
        });
      }
    }

    return {
      ok: results.some((item) => item.status === 'accepted'),
      accepted: results.filter((item) => item.status === 'accepted').length,
      duplicates: results.filter((item) => item.status === 'duplicate').length,
      rejected: results.filter((item) => item.status === 'rejected').length,
      results,
    };
  }

  private async persistOne(params: {
    companyId: string;
    userId: string | null;
    event: GuardianIngestEventDto;
    requestId: string | null;
    maxStackChars: number;
  }): Promise<GuardianIngestResultItem> {
    const { event, companyId } = params;

    const occurredAt = new Date(event.occurredAt);
    if (Number.isNaN(occurredAt.getTime())) {
      return { eventId: event.eventId, status: 'rejected', reason: 'INVALID_OCCURRED_AT' };
    }

    const stack = event.stack ? redactText(event.stack, params.maxStackChars) : null;
    const message = event.message ? redactText(event.message, 1_000) : null;
    const context = redactContext(event.context ?? {});
    const payload = {
      message,
      context,
    } as Prisma.InputJsonValue;

    const fingerprint = buildFingerprint({
      module: event.module,
      operation: event.operation,
      exceptionType: event.exceptionType ?? null,
      stack,
      appVersion: event.appVersion ?? null,
    });

    const severity = event.severity as GuardianSeverity;

    try {
      const created = await this.prisma.$transaction(async (tx) => {
        const group = await tx.guardianIncidentGroup.upsert({
          where: { fingerprint },
          create: {
            fingerprint,
            module: event.module,
            operation: event.operation,
            exceptionType: event.exceptionType ?? null,
            severity,
            firstSeenAt: occurredAt,
            lastSeenAt: occurredAt,
            incidentCount: 1,
            companyCount: 1,
            companies: [companyId] as Prisma.InputJsonValue,
          },
          update: {
            lastSeenAt: occurredAt,
            incidentCount: { increment: 1 },
          },
        });

        const incident = await tx.guardianIncident.create({
          data: {
            eventId: event.eventId,
            companyId,
            groupId: group.id,
            fingerprint,
            module: event.module,
            operation: event.operation,
            platform: event.platform ?? null,
            appVersion: event.appVersion ?? null,
            deviceId: event.deviceId ?? null,
            userId: params.userId,
            severity,
            exceptionType: event.exceptionType ?? null,
            processingState: GuardianProcessingState.PENDING,
            correlationId: event.correlationId ?? params.requestId,
            stack,
            occurredAt,
            offlineMinutes: event.offlineMinutes ?? null,
            schemaVersion: event.schemaVersion ?? 1,
            payload,
            impactSummary: (IMPACT_BY_MODULE[event.module] ?? IMPACT_BY_MODULE.unknown).slice(0, 400),
          },
        });

        const evidences: Prisma.GuardianEvidenceCreateManyInput[] = [];
        if (stack) {
          evidences.push({
            incidentId: incident.id,
            kind: 'stack',
            label: 'Stack sanitizado',
            sizeBytes: Buffer.byteLength(stack, 'utf8'),
            content: { stack } as Prisma.InputJsonValue,
            redacted: true,
          });
        }
        if (message) {
          evidences.push({
            incidentId: incident.id,
            kind: 'message',
            label: 'Mensaje de error',
            sizeBytes: Buffer.byteLength(message, 'utf8'),
            content: { message } as Prisma.InputJsonValue,
            redacted: true,
          });
        }
        if (Object.keys(context as Record<string, unknown>).length > 0) {
          evidences.push({
            incidentId: incident.id,
            kind: 'context',
            label: 'Contexto sanitizado',
            sizeBytes: Buffer.byteLength(JSON.stringify(context), 'utf8'),
            content: context as Prisma.InputJsonValue,
            redacted: true,
          });
        }
        for (const [index, raw] of (event.evidences ?? []).slice(0, 3).entries()) {
          const sanitized = redactContext(raw) as Record<string, unknown>;
          evidences.push({
            incidentId: incident.id,
            kind: 'client',
            label: String(sanitized.label ?? `Evidencia ${index + 1}`).slice(0, 120),
            sizeBytes: Buffer.byteLength(JSON.stringify(sanitized), 'utf8'),
            content: sanitized as Prisma.InputJsonValue,
            redacted: true,
          });
        }
        if (evidences.length) {
          await tx.guardianEvidence.createMany({ data: evidences });
        }

        await tx.guardianIncidentEvent.create({
          data: {
            incidentId: incident.id,
            fromStatus: null,
            toStatus: 'OPEN',
            actor: 'system:ingest',
            note: `Registrado desde ${event.platform ?? 'plataforma desconocida'}`,
          },
        });

        return incident;
      });

      return {
        eventId: event.eventId,
        status: 'accepted',
        incidentId: created.id,
        severity: event.severity,
      };
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const existing = await this.prisma.guardianIncident.findFirst({
          where: { companyId, eventId: event.eventId },
          select: { id: true },
        });
        return {
          eventId: event.eventId,
          status: 'duplicate',
          incidentId: existing?.id,
          severity: event.severity,
        };
      }
      throw error;
    }
  }

  /**
   * Recalcula contadores agregados de un grupo (empresas afectadas).
   * Se usa desde el panel y el worker de diagnóstico; nunca en la ruta de ingesta.
   */
  async refreshGroupStats(fingerprint: string) {
    const companies = await this.prisma.guardianIncident.findMany({
      where: { fingerprint },
      select: { companyId: true },
      distinct: ['companyId'],
      take: 500,
    });
    const companyIds = companies.map((row) => row.companyId);
    await this.prisma.guardianIncidentGroup.update({
      where: { fingerprint },
      data: {
        companyCount: companyIds.length,
        companies: companyIds as unknown as Prisma.InputJsonValue,
      },
    });
    return { fingerprint, companyCount: companyIds.length };
  }
}
