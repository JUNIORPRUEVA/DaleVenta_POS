import { Injectable, Logger } from '@nestjs/common';
import {
  GuardianAlertState,
  GuardianSeverity,
  Prisma,
} from '@prisma/client';
import { hostname } from 'node:os';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { resolveGuardianConfig } from './guardian.config';
import {
  EvolutionOutboxChannel,
  GuardianAlertChannel,
  HttpWebhookChannel,
  WhatsAppCloudChannel,
  hashRecipient,
} from './guardian.alert.channels';

const WORKER_ID = `guardian-alerts-${hostname()}-${process.pid}`;
const LOCK_TTL_MS = 2 * 60_000;
const MAX_ATTEMPTS = 6;

export type GuardianAlertPlan = {
  created: boolean;
  alertId?: string;
  skipped?: string;
  severity?: GuardianSeverity;
  scheduledFor?: Date;
};

/**
 * Construye el mensaje administrativo. Función pura y testeable.
 * Formato acordado en la especificación de Fase 4.
 */
export function buildGuardianAlertMessage(input: {
  severity: GuardianSeverity;
  companyName: string;
  module: string;
  operation: string;
  occurredAt: Date;
  problem: string;
  diagnosis: string | null;
  impact: string | null;
  incidentId: string;
  relatedCount?: number;
}): string {
  const severityLabel =
    input.severity === GuardianSeverity.SEV1
      ? 'CRÍTICO'
      : input.severity === GuardianSeverity.SEV2
        ? 'ALTO'
        : input.severity === GuardianSeverity.SEV3
          ? 'MEDIO'
          : 'BAJO';

  const time = input.occurredAt.toLocaleString('es-DO', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
    day: '2-digit',
    month: '2-digit',
  });

  const shortId = `INC-${input.incidentId.replace(/-/g, '').slice(0, 6).toUpperCase()}`;
  const related =
    input.relatedCount && input.relatedCount > 1
      ? `Eventos similares en curso: ${input.relatedCount}`
      : null;

  return [
    `APPYRA GUARDIAN — INCIDENTE ${severityLabel}`,
    '',
    `Empresa: ${input.companyName}`,
    `Sistema: Fullpos Cloud`,
    `Módulo: ${input.module} / ${input.operation}`,
    `Hora: ${time}`,
    '',
    'Problema:',
    input.problem,
    '',
    'Diagnóstico:',
    input.diagnosis ?? 'Información pendiente de confirmar.',
    '',
    'Impacto:',
    input.impact ?? 'Pendiente de determinar.',
    '',
    ...(related ? [related, ''] : []),
    'Estado:',
    'Incidente registrado. Investigación en curso.',
    '',
    `ID: ${shortId}`,
    '',
    'No se modificó información del cliente.',
  ].join('\n');
}

export function buildGuardianAlertTemplateParams(input: {
  severity: GuardianSeverity;
  companyName: string;
  module: string;
  operation: string;
  occurredAt: Date;
  problem: string;
  diagnosis: string | null;
  impact: string | null;
  incidentId: string;
}): string[] {
  const severityLabel =
    input.severity === GuardianSeverity.SEV1
      ? 'CRÍTICO'
      : input.severity === GuardianSeverity.SEV2
        ? 'ALTO'
        : input.severity === GuardianSeverity.SEV3
          ? 'MEDIO'
          : 'BAJO';
  const time = input.occurredAt.toLocaleString('es-DO', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
    day: '2-digit',
    month: '2-digit',
  });
  return [
    severityLabel,
    input.companyName,
    `${input.module} / ${input.operation}`,
    time,
    input.problem,
    input.diagnosis ?? 'Información pendiente de confirmar.',
    input.impact ?? 'Pendiente de determinar.',
    `INC-${input.incidentId.replace(/-/g, '').slice(0, 6).toUpperCase()}`,
  ];
}

@Injectable()
export class GuardianAlertService {
  private readonly logger = new Logger(GuardianAlertService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  /** Canales disponibles en este entorno (en orden de preferencia). */
  buildChannels(): GuardianAlertChannel[] {
    const config = resolveGuardianConfig();
    const firstNonEmpty = (...values: Array<string | undefined>) =>
      values.map((value) => String(value ?? '').trim()).find((value) => value.length > 0) ?? '';

    const cloud = new WhatsAppCloudChannel({
      // Se reutilizan los nombres de configuración Meta ya usados en el
      // ecosistema FULLTECH; los `GUARDIAN_*` tienen prioridad.
      token: firstNonEmpty(
        process.env.GUARDIAN_WA_CLOUD_TOKEN,
        process.env.META_WHATSAPP_TOKEN,
        process.env.META_ACCESS_TOKEN,
      ),
      phoneNumberId: firstNonEmpty(
        process.env.GUARDIAN_WA_PHONE_NUMBER_ID,
        process.env.META_PHONE_NUMBER_ID,
      ),
      apiVersion: firstNonEmpty(process.env.GUARDIAN_WA_API_VERSION, process.env.META_GRAPH_VERSION) || undefined,
      templateName: firstNonEmpty(process.env.GUARDIAN_WA_TEMPLATE_NAME) || undefined,
      templateLanguage: firstNonEmpty(process.env.GUARDIAN_WA_TEMPLATE_LANG) || 'es',
      timeoutMs: Number(process.env.GUARDIAN_WA_TIMEOUT_MS ?? 12_000),
    });

    const evolution = new EvolutionOutboxChannel({
      enabled: () => {
        const flag = String(process.env.NOTIFICATIONS_ENABLED ?? '').trim().toLowerCase();
        return flag !== '0' && flag !== 'false';
      },
      enqueue: async (input) => {
        const row = await this.notifications.enqueueWhatsAppRawText({
          toNumber: input.toNumber,
          messageText: input.messageText,
          dedupeKey: input.dedupeKey,
          allowOutsideBusinessHours: input.allowOutsideBusinessHours,
          payload: { kind: 'guardian_alert' },
        });
        return { id: row.id };
      },
    });

    const webhook = new HttpWebhookChannel({
      url: String(process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL ?? config.alertsFallbackEmail ?? ''),
      secret: process.env.GUARDIAN_ALERT_FALLBACK_SECRET,
      timeoutMs: Number(process.env.GUARDIAN_WEBHOOK_TIMEOUT_MS ?? 12_000),
    });

    return [cloud, evolution, webhook];
  }

  private primaryChannel(channels: GuardianAlertChannel[]): GuardianAlertChannel | null {
    return channels.find((channel) => channel.name !== 'http_webhook' && channel.isConfigured()) ?? null;
  }

  private fallbackChannel(channels: GuardianAlertChannel[]): GuardianAlertChannel | null {
    return channels.find((channel) => channel.name === 'http_webhook' && channel.isConfigured()) ?? null;
  }

  /**
   * Crea (idempotentemente) la alerta de un incidente.
   *
   * Política 24/7: SEV1 y SEV2 se envían a cualquier hora, incluso madrugada,
   * domingo o feriado. Los horarios comerciales de mensajes a clientes no se tocan.
   */
  async planForIncident(incidentId: string, now = new Date()): Promise<GuardianAlertPlan> {
    const config = resolveGuardianConfig();
    if (!config.alertsEnabled) return { created: false, skipped: 'ALERTS_DISABLED' };

    const recipient = config.alertsRecipient;
    if (!recipient) return { created: false, skipped: 'RECIPIENT_NOT_CONFIGURED' };

    const incident = await this.prisma.guardianIncident.findUnique({
      where: { id: incidentId },
      select: {
        id: true,
        companyId: true,
        module: true,
        operation: true,
        severity: true,
        occurredAt: true,
        impactSummary: true,
        fingerprint: true,
        payload: true,
      },
    });
    if (!incident) return { created: false, skipped: 'INCIDENT_NOT_FOUND' };

    const severity = incident.severity;
    if (severity === GuardianSeverity.SEV4 && String(process.env.GUARDIAN_ALERT_SEV4_ENABLED ?? 'false') !== 'true') {
      return { created: false, skipped: 'SEV4_RECORDED_ONLY', severity };
    }
    if (severity === GuardianSeverity.SEV3 && String(process.env.GUARDIAN_ALERT_SEV3_ENABLED ?? 'true') === 'false') {
      return { created: false, skipped: 'SEV3_DISABLED', severity };
    }

    const dedupeKey = `guardian:alert:initial:${incident.id}`;
    const existing = await this.prisma.guardianAlert.findUnique({ where: { dedupeKey } });
    if (existing) {
      return { created: false, alertId: existing.id, skipped: 'ALREADY_QUEUED', severity };
    }

    const groupWindowMs = config.alertGroupWindowMinutes * 60_000;
    const scheduledFor =
      severity === GuardianSeverity.SEV4 ? new Date(now.getTime() + groupWindowMs) : now;

    const channels = this.buildChannels();
    const primary = this.primaryChannel(channels);

    const alert = await this.prisma.guardianAlert.create({
      data: {
        incidentId: incident.id,
        channel: primary?.name ?? 'none',
        recipientHash: hashRecipient(recipient),
        dedupeKey,
        kind: 'initial',
        state: GuardianAlertState.PENDING,
        nextAttemptAt: scheduledFor,
      },
    });

    return { created: true, alertId: alert.id, severity, scheduledFor };
  }

  /** Reclama alertas vencidas con compare-and-swap (seguro multi-worker). */
  async claimDue(limit = 10, now = new Date()) {
    const lockExpiry = new Date(now.getTime() - LOCK_TTL_MS);
    const baseWhere: Prisma.GuardianAlertWhereInput = {
      state: { in: [GuardianAlertState.PENDING, GuardianAlertState.SENDING] },
      nextAttemptAt: { lte: now },
      OR: [{ lockedAt: null }, { lockedAt: { lt: lockExpiry } }],
    };

    const candidates = await this.prisma.guardianAlert.findMany({
      where: baseWhere,
      select: { id: true },
      orderBy: [{ nextAttemptAt: 'asc' }, { createdAt: 'asc' }],
      take: limit,
    });

    const claimed: string[] = [];
    for (const candidate of candidates) {
      const result = await this.prisma.guardianAlert.updateMany({
        where: { id: candidate.id, ...baseWhere },
        data: { state: GuardianAlertState.SENDING, lockedAt: now, lockedBy: WORKER_ID },
      });
      if (result.count === 1) claimed.push(candidate.id);
    }

    if (!claimed.length) return [];
    return this.prisma.guardianAlert.findMany({ where: { id: { in: claimed } } });
  }

  async processDue(limit = 10, now = new Date()) {
    const config = resolveGuardianConfig();
    if (!config.alertsEnabled) return { ok: true, enabled: false, processed: 0, sent: 0, failed: 0 };

    const alerts = await this.claimDue(limit, now);
    const channels = this.buildChannels();
    let sent = 0;
    let failed = 0;

    for (const alert of alerts) {
      const outcome = await this.attempt(alert.id, channels).catch((error) => {
        this.logger.error(
          `Alerta falló alert=${alert.id}: ${error instanceof Error ? error.message : String(error)}`,
        );
        return { ok: false as const };
      });
      if (outcome.ok) sent += 1;
      else failed += 1;
    }

    return { ok: true, enabled: true, processed: alerts.length, sent, failed };
  }

  private backoffMs(attempts: number) {
    if (attempts <= 1) return 60_000;
    if (attempts === 2) return 5 * 60_000;
    if (attempts === 3) return 15 * 60_000;
    if (attempts === 4) return 60 * 60_000;
    return 3 * 60 * 60_000;
  }

  async attempt(alertId: string, channels?: GuardianAlertChannel[]) {
    const alert = await this.prisma.guardianAlert.findUnique({ where: { id: alertId } });
    if (!alert) return { ok: false as const, reason: 'NOT_FOUND' };

    const incident = await this.prisma.guardianIncident.findUnique({
      where: { id: alert.incidentId },
      select: {
        id: true,
        module: true,
        operation: true,
        severity: true,
        occurredAt: true,
        impactSummary: true,
        fingerprint: true,
        company: { select: { name: true } },
        diagnoses: {
          where: { status: 'DONE' },
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { summary: true, impact: true, verdict: true },
        },
      },
    });
    if (!incident) return { ok: false as const, reason: 'INCIDENT_NOT_FOUND' };

    const available = channels ?? this.buildChannels();
    const primary = this.primaryChannel(available);
    const fallback = this.fallbackChannel(available);
    const channel =
      alert.attempts >= 2 && fallback ? fallback : primary ?? fallback ?? null;

    if (!channel) {
      await this.recordFailure(alert.id, 'no hay canal configurado', 'permanent', null, alert.attempts, alert.channel);
      return { ok: false as const, reason: 'NO_CHANNEL' };
    }

    const relatedCount = await this.prisma.guardianIncident.count({
      where: {
        fingerprint: incident.fingerprint,
        occurredAt: { gte: new Date(Date.now() - 60 * 60 * 1000) },
      },
    });

    const diagnosis = incident.diagnoses[0];
    const text = buildGuardianAlertMessage({
      severity: incident.severity,
      companyName: incident.company.name,
      module: incident.module,
      operation: incident.operation,
      occurredAt: incident.occurredAt,
      problem: this.problemText(incident.module, incident.operation),
      diagnosis: diagnosis?.summary ?? null,
      impact: diagnosis?.impact ?? incident.impactSummary,
      incidentId: incident.id,
      relatedCount,
    });

    const recipient = resolveGuardianConfig().alertsRecipient;
    const result = await channel.send({
      to: recipient,
      text,
      dedupeKey: alert.dedupeKey,
      allowOutsideBusinessHours: true,
      templateName: process.env.GUARDIAN_WA_TEMPLATE_NAME,
      templateParams: buildGuardianAlertTemplateParams({
        severity: incident.severity,
        companyName: incident.company.name,
        module: incident.module,
        operation: incident.operation,
        occurredAt: incident.occurredAt,
        problem: this.problemText(incident.module, incident.operation),
        diagnosis: diagnosis?.summary ?? null,
        impact: diagnosis?.impact ?? incident.impactSummary,
        incidentId: incident.id,
      }),
    });

    if (result.ok) {
      await this.prisma.$transaction([
        this.prisma.guardianAlert.update({
          where: { id: alert.id },
          data: {
            state: GuardianAlertState.SENT,
            channel: channel.name,
            attempts: { increment: 1 },
            sentAt: new Date(),
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            providerMessageId: result.providerMessageId ?? null,
          },
        }),
        this.prisma.guardianAlertAttempt.create({
          data: {
            alertId: alert.id,
            attempt: alert.attempts + 1,
            channel: channel.name,
            outcome: 'ok',
            httpStatus: result.httpStatus ?? null,
            detail: result.providerMessageId ? `provider=${result.providerMessageId}` : null,
          },
        }),
      ]);
      return { ok: true as const, channel: channel.name };
    }

    const attempts = alert.attempts + 1;
    await this.recordFailure(
      alert.id,
      result.error ?? 'error desconocido',
      result.classification ?? 'transient',
      result.httpStatus ?? null,
      alert.attempts,
      channel.name,
    );

    if (result.classification === 'permanent' && fallback && channel.name !== fallback.name) {
      await this.escalate(incident.id, alert.dedupeKey, 'fallo permanente del canal principal');
    }

    return { ok: false as const, attempts, classification: result.classification };
  }

  private async recordFailure(
    alertId: string,
    error: string,
    classification: 'transient' | 'permanent',
    httpStatus: number | null,
    previousAttempts: number,
    channel: string,
  ) {
    const attempts = previousAttempts + 1;
    const dead = classification === 'permanent' || attempts >= MAX_ATTEMPTS;

    await this.prisma.$transaction([
      this.prisma.guardianAlert.update({
        where: { id: alertId },
        data: {
          state: dead ? GuardianAlertState.FAILED_PERMANENT : GuardianAlertState.PENDING,
          attempts,
          nextAttemptAt: new Date(Date.now() + this.backoffMs(attempts)),
          lockedAt: null,
          lockedBy: null,
          lastError: error.slice(0, 600),
          channel,
        },
      }),
      this.prisma.guardianAlertAttempt.create({
        data: {
          alertId,
          attempt: attempts,
          channel,
          outcome: classification,
          httpStatus,
          detail: error.slice(0, 600),
        },
      }),
    ]);
  }

  private async escalate(incidentId: string, dedupeKey: string, reason: string) {
    const escalationKey = `${dedupeKey}:escalation`;
    const existing = await this.prisma.guardianAlert.findUnique({ where: { dedupeKey: escalationKey } });
    if (existing) return existing;

    return this.prisma.guardianAlert.create({
      data: {
        incidentId,
        channel: 'http_webhook',
        recipientHash: hashRecipient(resolveGuardianConfig().alertsFallbackEmail),
        dedupeKey: escalationKey,
        kind: 'escalation',
        state: GuardianAlertState.PENDING,
        nextAttemptAt: new Date(),
        lastError: reason.slice(0, 600),
      },
    });
  }

  /** Marca la alerta como entregada/leída a partir del id del proveedor. */
  async markDelivery(providerMessageId: string, status: 'delivered' | 'read' | 'failed') {
    const normalized = String(providerMessageId ?? '').trim();
    if (!normalized) return { updated: 0 };

    const alert = await this.prisma.guardianAlert.findFirst({
      where: { providerMessageId: normalized },
      select: { id: true, state: true },
    });
    if (!alert) return { updated: 0 };

    if (status === 'failed') {
      await this.prisma.guardianAlert.update({
        where: { id: alert.id },
        data: { state: GuardianAlertState.FAILED_PERMANENT, lastError: 'proveedor reportó fallo' },
      });
      return { updated: 1, state: 'FAILED_PERMANENT' };
    }

    await this.prisma.guardianAlert.update({
      where: { id: alert.id },
      data: {
        state: GuardianAlertState.DELIVERED,
        deliveredAt: new Date(),
      },
    });
    return { updated: 1, state: 'DELIVERED' };
  }

  private problemText(module: string, operation: string): string {
    const base: Record<string, string> = {
      cash: 'Se detectó una posible inconsistencia en operaciones asociadas a turnos.',
      sales: 'Se detectó un problema al registrar ventas.',
      sync: 'Se detectó un fallo de sincronización entre el punto de venta y la nube.',
      inventory: 'Se detectó un problema en el inventario.',
      license: 'Se detectó un problema con la licencia del sistema.',
      updater: 'Se detectó un problema en la actualización del sistema.',
      fiscal: 'Se detectó un problema en comprobantes fiscales.',
      printing: 'Se detectó un problema al imprimir comprobantes.',
      auth: 'Se detectó un problema de acceso de usuarios.',
      backend: 'Se detectó un error interno en el servicio en la nube.',
    };
    return base[module] ?? `Se detectó un fallo en ${module} (${operation}).`;
  }
}
