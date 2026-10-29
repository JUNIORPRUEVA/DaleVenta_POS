import { Injectable, Logger } from '@nestjs/common';
import {
  GuardianAlertState,
  GuardianDiagnosisStatus,
  GuardianSeverity,
  Prisma,
} from '@prisma/client';
import { hostname } from 'node:os';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { resolveGuardianConfig } from './guardian.config';
import { guardianSecretValue } from './guardian.secret';
import {
  GUARDIAN_COMPANY_DISABLED,
  isGuardianEnabledForCompany,
} from './guardian.company.policy';
import {
  EvolutionOutboxChannel,
  GuardianAlertChannel,
  HttpWebhookChannel,
  WhatsAppCloudChannel,
  hashRecipient,
} from './guardian.alert.channels';
import {
  GuardianDeliveryStatus,
  advanceAlertDelivery,
  stateForAcceptance,
} from './guardian.alert.delivery';
import {
  GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS,
  resolveGuardianWhatsAppProfile,
} from './guardian.whatsapp.config';

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
  const values = [
    severityLabel,
    input.companyName,
    `${input.module} / ${input.operation}`,
    time,
    input.problem,
    input.diagnosis ?? 'Información pendiente de confirmar.',
    input.impact ?? 'Pendiente de determinar.',
    `INC-${input.incidentId.replace(/-/g, '').slice(0, 6).toUpperCase()}`,
  ];

  // Contrato de la plantilla: cada posición respeta el `maxChars` declarado en
  // `guardian.whatsapp.config.ts`. Sin este recorte, un nombre de empresa o un
  // módulo/operación largos superan el límite y Meta rechaza el envío con un
  // error permanente (clasificación `permanent`, sin reintento): la alerta se
  // perdería. Los valores que ya están dentro del límite no cambian.
  return values.map((value, index) => {
    const limit = GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS[index]?.maxChars;
    return typeof limit === 'number' && value.length > limit
      ? value.slice(0, limit)
      : value;
  });
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
    // Identidad del remitente oficial APPYRA. Solo variables `GUARDIAN_WA_*`:
    // nunca se hereda el número ni el token de otro producto.
    const profile = resolveGuardianWhatsAppProfile();

    const cloud = new WhatsAppCloudChannel({
      token: guardianSecretValue(process.env, 'GUARDIAN_WA_CLOUD_TOKEN'),
      phoneNumberId: profile.sender.phoneNumberId ?? '',
      apiVersion: profile.sender.apiVersion,
      templateName: profile.templates.incidentAlert.name,
      templateLanguage: profile.templates.incidentAlert.language,
      timeoutMs: Number(process.env.GUARDIAN_WA_TIMEOUT_MS ?? 12_000),
    });

    const evolution = new EvolutionOutboxChannel({
      // Fail-closed: reutilizar el outbox de mensajes comerciales exige un
      // interruptor explícito. `NOTIFICATIONS_ENABLED` no implica permiso.
      enabled: () => config.alertsEvolutionEnabled,
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
      url: String(process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL ?? '').trim(),
      secret: guardianSecretValue(process.env, 'GUARDIAN_ALERT_FALLBACK_SECRET') || undefined,
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

    const recipients = this.resolveRecipients();
    if (!recipients.length) return { created: false, skipped: 'RECIPIENT_NOT_CONFIGURED' };

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

    // Fase 7 — una empresa con Guardian desactivado no genera alertas nuevas.
    if (!(await isGuardianEnabledForCompany(this.prisma, incident.companyId))) {
      return { created: false, skipped: GUARDIAN_COMPANY_DISABLED };
    }

    const severity = incident.severity;
    if (severity === GuardianSeverity.SEV4 && String(process.env.GUARDIAN_ALERT_SEV4_ENABLED ?? 'false') !== 'true') {
      return { created: false, skipped: 'SEV4_RECORDED_ONLY', severity };
    }
    if (severity === GuardianSeverity.SEV3 && String(process.env.GUARDIAN_ALERT_SEV3_ENABLED ?? 'true') === 'false') {
      return { created: false, skipped: 'SEV3_DISABLED', severity };
    }

    const baseDedupeKey = `guardian:alert:initial:${incident.id}`;
    const existing = await this.prisma.guardianAlert.findFirst({
      where: { incidentId: incident.id, kind: 'initial' },
      orderBy: { createdAt: 'asc' },
      select: { id: true, dedupeKey: true },
    });
    if (existing) {
      return { created: false, alertId: existing.id, skipped: 'ALREADY_QUEUED', severity };
    }

    const groupWindowMs = config.alertGroupWindowMinutes * 60_000;
    const scheduledFor =
      severity === GuardianSeverity.SEV4 ? new Date(now.getTime() + groupWindowMs) : now;

    const channels = this.buildChannels();
    const primary = this.primaryChannel(channels);

    // Un destinatario por alerta: si un número administrativo falla, el otro
    // sigue recibiendo el aviso y cada uno conserva su propia auditoría.
    let firstAlertId: string | undefined;
    for (const recipient of recipients) {
      const dedupeKey =
        recipients.length === 1
          ? baseDedupeKey
          : `${baseDedupeKey}:${hashRecipient(recipient).slice(0, 12)}`;

      let alert: { id: string };
      try {
        alert = await this.prisma.guardianAlert.create({
          data: {
            incidentId: incident.id,
            channel: primary?.name ?? 'none',
            recipientHash: hashRecipient(recipient),
            recipientNumber: recipient,
            dedupeKey,
            kind: 'initial',
            state: GuardianAlertState.PENDING,
            nextAttemptAt: scheduledFor,
          },
        });
      } catch (error) {
        // Carrera entre dos workers planificando el mismo incidente: la clave
        // única de `dedupeKey` garantiza exactamente una alerta inicial.
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
          const concurrent = await this.prisma.guardianAlert.findFirst({
            where: { incidentId: incident.id, kind: 'initial' },
            orderBy: { createdAt: 'asc' },
            select: { id: true },
          });
          return {
            created: false,
            alertId: concurrent?.id,
            skipped: 'ALREADY_QUEUED',
            severity,
          };
        }
        throw error;
      }
      firstAlertId = firstAlertId ?? alert.id;
    }

    return { created: true, alertId: firstAlertId, severity, scheduledFor };
  }

  /** Destinatarios administrativos configurados (lista oficial). */
  private resolveRecipients(): string[] {
    const profile = resolveGuardianWhatsAppProfile();
    if (profile.adminRecipients.length) return profile.adminRecipients;
    const legacy = String(resolveGuardianConfig().alertsRecipient ?? '').trim();
    return legacy ? [legacy] : [];
  }

  /** Reclama alertas vencidas con compare-and-swap (seguro multi-worker). */
  async claimDue(limit = 10, now = new Date()) {
    const lockExpiry = new Date(now.getTime() - LOCK_TTL_MS);
    const waitSeconds = resolveGuardianConfig().alertDiagnosisWaitSeconds;
    const conditions: Prisma.GuardianAlertWhereInput[] = [
      { OR: [{ lockedAt: null }, { lockedAt: { lt: lockExpiry } }] },
    ];

    // Fase 4: SEV2/SEV3 esperan al diagnóstico hasta el plazo configurado.
    // SEV1 nunca se bloquea. La lista de severidades que esperan viene del módulo
    // de readiness para que la regla viva en un solo lugar.
    if (waitSeconds > 0) {
      const deadline = new Date(now.getTime() - waitSeconds * 1000);
      conditions.push({
        OR: [
          { incident: { severity: GuardianSeverity.SEV1 } },
          { incident: { diagnoses: { some: { status: GuardianDiagnosisStatus.DONE } } } },
          { incident: { receivedAt: { lte: deadline } } },
        ],
      });
    }

    const baseWhere: Prisma.GuardianAlertWhereInput = {
      state: { in: [GuardianAlertState.PENDING, GuardianAlertState.SENDING] },
      nextAttemptAt: { lte: now },
      AND: conditions,
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
    if (!config.alertsEnabled) {
      return { ok: true, enabled: false, processed: 0, sent: 0, failed: 0, deferred: 0 };
    }

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

    const deferred = await this.countAwaitingDiagnosis(now).catch(() => 0);

    return { ok: true, enabled: true, processed: alerts.length, sent, failed, deferred };
  }

  /**
   * Alertas que ya vencieron pero siguen esperando el diagnóstico.
   * Solo para observabilidad (no altera el despacho).
   */
  async countAwaitingDiagnosis(now = new Date()): Promise<number> {
    const waitSeconds = resolveGuardianConfig().alertDiagnosisWaitSeconds;
    if (waitSeconds <= 0) return 0;
    const deadline = new Date(now.getTime() - waitSeconds * 1000);
    return this.prisma.guardianAlert.count({
      where: {
        state: GuardianAlertState.PENDING,
        nextAttemptAt: { lte: now },
        incident: {
          severity: { in: [GuardianSeverity.SEV2, GuardianSeverity.SEV3] },
          receivedAt: { gt: deadline },
          NOT: { diagnoses: { some: { status: GuardianDiagnosisStatus.DONE } } },
        },
      },
    });
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
    // Ya aceptada por el proveedor: un reintento tras un reinicio no debe
    // reenviar el mensaje (evita duplicados en el cliente final).
    if (alert.providerMessageId) {
      return { ok: true as const, reason: 'ALREADY_SENT' };
    }

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

    const recipient =
      String((alert as { recipientNumber?: string | null }).recipientNumber ?? '').trim() ||
      this.resolveRecipients()[0] ||
      '';
    if (!recipient) {
      await this.recordFailure(
        alert.id,
        'sin destinatario administrativo configurado',
        'permanent',
        null,
        alert.attempts,
        channel.name,
      );
      return { ok: false as const, reason: 'NO_RECIPIENT' };
    }

    const result = await channel.send({
      to: recipient,
      text,
      dedupeKey: alert.dedupeKey,
      allowOutsideBusinessHours: true,
      templateName: resolveGuardianWhatsAppProfile().templates.incidentAlert.name,
      templateLanguage: resolveGuardianWhatsAppProfile().templates.incidentAlert.language,
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
      // El estado depende de la evidencia real: encolar en el outbox local no
      // equivale a enviar, y un 2xx sin id no equivale a aceptación del proveedor.
      const state = stateForAcceptance(result.acceptance);
      const now = new Date();
      await this.prisma.$transaction([
        this.prisma.guardianAlert.update({
          where: { id: alert.id },
          data: {
            state,
            channel: channel.name,
            attempts: { increment: 1 },
            sentAt: now,
            acceptedAt: state === GuardianAlertState.ACCEPTED ? now : null,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            providerMessageId: result.providerMessageId ?? null,
            lastProviderStatus: result.acceptance ?? 'sent',
          },
        }),
        this.prisma.guardianAlertAttempt.create({
          data: {
            alertId: alert.id,
            attempt: alert.attempts + 1,
            channel: channel.name,
            outcome: state === GuardianAlertState.QUEUED ? 'queued' : 'ok',
            httpStatus: result.httpStatus ?? null,
            detail: [
              result.providerMessageId ? `provider=${result.providerMessageId}` : null,
              `acceptance=${result.acceptance ?? 'sent'}`,
            ]
              .filter(Boolean)
              .join(' ')
              .slice(0, 600) || null,
          },
        }),
      ]);
      return { ok: true as const, channel: channel.name, state };
    }

    const attempts = alert.attempts + 1;
    await this.recordFailure(
      alert.id,
      result.error ?? 'error desconocido',
      result.classification ?? 'transient',
      result.httpStatus ?? null,
      alert.attempts,
      channel.name,
      result.retryAfterMs,
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
    retryAfterMs?: number,
  ) {
    const attempts = previousAttempts + 1;
    const dead = classification === 'permanent' || attempts >= MAX_ATTEMPTS;
    const delay = Math.max(this.backoffMs(attempts), Number(retryAfterMs) || 0);

    await this.prisma.$transaction([
      this.prisma.guardianAlert.update({
        where: { id: alertId },
        data: {
          state: dead ? GuardianAlertState.FAILED_PERMANENT : GuardianAlertState.PENDING,
          attempts,
          nextAttemptAt: new Date(Date.now() + delay),
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

  /**
   * Aplica un estado de entrega reportado por el proveedor.
   *
   * Es idempotente y monótono: los webhooks pueden llegar repetidos o
   * desordenados (`read` antes que `delivered`) y el estado nunca retrocede.
   * Un `failed` posterior a la entrega conserva la evidencia de entrega.
   */
  async markDelivery(providerMessageId: string, status: GuardianDeliveryStatus, error?: string | null) {
    const normalized = String(providerMessageId ?? '').trim();
    if (!normalized) return { updated: 0 };

    const alert = await this.prisma.guardianAlert.findFirst({
      where: { providerMessageId: normalized },
      select: { id: true, state: true },
    });
    if (!alert) return { updated: 0 };

    const now = new Date();
    const transition = advanceAlertDelivery(alert.state, status, now, { error });

    const data: Prisma.GuardianAlertUpdateInput = { lastProviderStatus: status };
    if (transition.state) data.state = transition.state;
    if (transition.deliveredAt) data.deliveredAt = transition.deliveredAt;
    if (transition.readAt) data.readAt = transition.readAt;
    if (transition.lastError !== undefined) {
      data.lastError = transition.lastError ? transition.lastError.slice(0, 600) : null;
    }

    await this.prisma.guardianAlert.update({ where: { id: alert.id }, data });
    return { updated: 1, state: String(transition.state ?? alert.state) };
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
