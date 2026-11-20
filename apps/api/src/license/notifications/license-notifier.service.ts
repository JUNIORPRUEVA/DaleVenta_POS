import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { LicenseNotificationKind, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { WhatsAppCloudChannel } from '../../guardian/guardian.alert.channels';
import { LicenseEvidenceStorage } from '../orders/license-evidence.storage';
import { MetaCloudClient } from './meta-cloud.client';
import {
  buildAdminEvidenceDetailedParams,
  buildAdminEvidenceParams,
  buildReminderParams,
  LICENSE_TEMPLATES,
} from './license.templates';

type JobPayload = {
  orderId?: string | null;
  evidenceId?: string | null;
  reference?: string | null;
  planCode?: string | null;
  planName?: string | null;
  amount?: number | null;
  companyName?: string | null;
  periodEnd?: string | null;
  /** Cuerpo detallado (10 datos) para la plantilla de soporte. */
  detailed?: boolean;
  operationType?: string | null;
  readAmount?: number | null;
  bankReference?: string | null;
  occurredAt?: string | null;
  analysisResult?: string | null;
  licenseState?: string | null;
};

const MAX_ATTEMPTS = 5;
const BATCH_SIZE = 10;

/**
 * Bandeja de salida de avisos. El aviso **nunca** bloquea ni deshace una
 * licencia: si WhatsApp falla, el cliente sigue trabajando y el trabajo queda
 * con su error para reintentar.
 */
@Injectable()
export class LicenseNotifierService implements OnModuleInit {
  private readonly logger = new Logger(LicenseNotifierService.name);
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly meta: MetaCloudClient,
    private readonly storage: LicenseEvidenceStorage,
    private readonly config: ConfigService,
  ) {}

  onModuleInit() {
    if (!this.meta.isConfigured()) {
      this.logger.warn(
        'WhatsApp Cloud API sin configurar (LICENSE_WA_TOKEN / LICENSE_WA_PHONE_NUMBER_ID): los avisos quedaran SKIPPED.',
      );
    }
  }

  async enqueue(input: {
    companyId: string;
    kind: LicenseNotificationKind;
    payload: JobPayload;
    scheduledAt?: Date;
  }) {
    return this.prisma.licenseNotificationJob.create({
      data: {
        companyId: input.companyId,
        kind: input.kind,
        payload: input.payload as Prisma.InputJsonValue,
        scheduledAt: input.scheduledAt ?? new Date(),
      },
      select: { id: true },
    });
  }

  @Cron(CronExpression.EVERY_MINUTE)
  async processPending() {
    if (this.running) return;
    this.running = true;
    try {
      const jobs = await this.prisma.licenseNotificationJob.findMany({
        where: { status: 'PENDING', scheduledAt: { lte: new Date() } },
        orderBy: { scheduledAt: 'asc' },
        take: BATCH_SIZE,
      });
      for (const job of jobs) {
        // Reclamo atomico: si otra instancia lo tomo, el contador ya cambio.
        const claimed = await this.prisma.licenseNotificationJob.updateMany({
          where: { id: job.id, status: 'PENDING' },
          data: { attempts: { increment: 1 } },
        });
        if (claimed.count !== 1) continue;
        await this.processJob(job.id, job.companyId, job.kind, job.payload);
      }
    } catch (error) {
      this.logger.warn(`Cola de avisos: ${describe(error)}`);
    } finally {
      this.running = false;
    }
  }

  private async processJob(
    jobId: string,
    companyId: string,
    kind: LicenseNotificationKind,
    rawPayload: Prisma.JsonValue,
  ) {
    const payload = (rawPayload ?? {}) as JobPayload;
    const attempts = await this.currentAttempts(jobId);
    try {
      if (!this.meta.isConfigured()) {
        await this.finish(jobId, 'SKIPPED', 'whatsapp-not-configured');
        return;
      }
      const recipient = this.meta.adminRecipient();
      if (!recipient) {
        await this.finish(jobId, 'SKIPPED', 'missing-recipient');
        return;
      }
      // La plantilla aprobada en Meta puede cambiarse por entorno sin tocar
      // codigo: es lo unico que ata el mensaje a la cuenta de WhatsApp.
      const template =
        (kind === 'ADMIN_EVIDENCE'
          ? this.readEnv('LICENSE_WA_TEMPLATE_ADMIN_EVIDENCE')
          : null) ??
        (kind === 'REMINDER_5D'
          ? this.readEnv('LICENSE_WA_TEMPLATE_REMINDER_5D')
          : null) ??
        (kind === 'REMINDER_1D'
          ? this.readEnv('LICENSE_WA_TEMPLATE_REMINDER_1D')
          : null) ??
        LICENSE_TEMPLATES[kind];
      const params = this.buildParams(kind, payload);
      if (!params) {
        await this.finish(jobId, 'SKIPPED', 'missing-payload');
        return;
      }

      let headerMediaId: string | null = null;
      if (kind === 'ADMIN_EVIDENCE' && payload.evidenceId && !this.meta.isDryRun()) {
        headerMediaId = await this.uploadEvidence(companyId, payload.evidenceId);
      }
      if (this.meta.isDryRun()) {
        // Prueba controlada: el mensaje se prepara y se registra, pero **no**
        // se llama a Meta. Sin esto, cambiar al canal de Guardian enviaria de
        // verdad al numero de soporte.
        this.logger.log(
          `[DRY-RUN] WhatsApp ${template} -> ${recipient} · media=${headerMediaId ? 'si' : 'no'} · params=${params.length}`,
        );
        await this.finish(jobId, 'SENT', null);
        return;
      }

      // Se envía por el **mismo canal de WhatsApp de APPYRA Guardian** (misma
      // cuenta, mismo número emisor y mismo token). No hay otra integración.
      const channel = new WhatsAppCloudChannel({
        token: this.meta.readConfig().token,
        phoneNumberId: this.meta.readConfig().phoneNumberId,
        apiVersion: this.meta.readConfig().version,
        templateName: template,
        templateLanguage: this.meta.readConfig().language,
      });
      const sent = await channel.send({
        to: recipient,
        text: `Comprobante ${payload.reference ?? ''}`.trim(),
        dedupeKey: jobId,
        allowOutsideBusinessHours: true,
        templateName: template,
        templateLanguage: this.meta.readConfig().language,
        templateParams: params,
        headerImageId: headerMediaId ?? undefined,
      });
      if (sent.ok) {
        await this.finish(jobId, 'SENT', null);
        return;
      }
      const result = {
        ok: false as const,
        error: sent.error ?? `guardian-${sent.classification ?? 'error'}`,
      };
      if (result.ok) {
        await this.finish(jobId, 'SENT', null);
        return;
      }
      if (
        result.error === 'whatsapp-not-configured' ||
        result.error === 'missing-recipient'
      ) {
        await this.finish(jobId, 'SKIPPED', result.error);
        return;
      }
      const status = attempts >= MAX_ATTEMPTS ? 'SKIPPED' : 'PENDING';
      await this.finish(jobId, status, result.error, attempts >= MAX_ATTEMPTS);
    } catch (error) {
      const status = attempts >= MAX_ATTEMPTS ? 'SKIPPED' : 'PENDING';
      await this.finish(jobId, status, describe(error), attempts >= MAX_ATTEMPTS);
    }
  }

  private buildParams(kind: LicenseNotificationKind, payload: JobPayload) {
    if (kind === 'ADMIN_EVIDENCE') {
      if (payload.detailed) {
        return buildAdminEvidenceDetailedParams({
          companyName: payload.companyName ?? null,
          planName: payload.planName ?? payload.planCode ?? null,
          operationType: payload.operationType ?? 'renovacion',
          expectedAmount: Number(payload.amount ?? 0),
          readAmount:
            payload.readAmount == null ? null : Number(payload.readAmount),
          internalReference: payload.reference ?? '',
          bankReference: payload.bankReference ?? null,
          occurredAt: payload.occurredAt ?? null,
          analysisResult: payload.analysisResult ?? 'sin analisis',
          licenseState: payload.licenseState ?? 'pendiente de revision',
        });
      }
      return buildAdminEvidenceParams({
        companyName: payload.companyName ?? null,
        planName: payload.planName ?? payload.planCode ?? null,
        amount: Number(payload.amount ?? 0),
        reference: payload.reference ?? '',
        receivedAt: new Date(),
      });
    }
    return buildReminderParams({
      companyName: payload.companyName ?? null,
      planName: payload.planName ?? payload.planCode ?? null,
      periodEnd: payload.periodEnd ? new Date(payload.periodEnd) : new Date(),
      reference: payload.reference ?? null,
    });
  }

  private readEnv(key: string) {
    const value = this.config.get<string>(key)?.trim();
    return value && value.length > 0 ? value : null;
  }

  private async uploadEvidence(companyId: string, evidenceId: string) {
    const evidence = await this.prisma.licensePaymentEvidence.findFirst({
      where: { id: evidenceId, companyId },
      select: { storageKey: true, mime: true, originalName: true },
    });
    if (!evidence) return null;
    try {
      const buffer = await this.storage.read(evidence.storageKey, companyId);
      const uploaded = await this.meta.uploadMedia({
        buffer,
        mime: evidence.mime,
        fileName: evidence.originalName,
      });
      return uploaded.ok ? uploaded.mediaId : null;
    } catch {
      return null;
    }
  }

  private async currentAttempts(jobId: string) {
    const job = await this.prisma.licenseNotificationJob.findUnique({
      where: { id: jobId },
      select: { attempts: true },
    });
    return job?.attempts ?? 0;
  }

  private async finish(
    jobId: string,
    status: 'PENDING' | 'SENT' | 'FAILED' | 'SKIPPED',
    lastError: string | null,
    forceFailed = false,
  ) {
    await this.prisma.licenseNotificationJob.update({
      where: { id: jobId },
      data: {
        status: forceFailed ? 'FAILED' : status,
        lastError: lastError ? lastError.slice(0, 500) : null,
        sentAt: status === 'SENT' ? new Date() : undefined,
      },
      select: { id: true },
    });
  }
}

function describe(error: unknown) {
  if (error instanceof Error) return error.message.slice(0, 300);
  return 'unknown-error';
}
