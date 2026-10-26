import { Injectable, Logger } from '@nestjs/common';
import { NotificationOutbox, Prisma } from '@prisma/client';
import { hostname } from 'os';
import { PrismaService } from '../prisma/prisma.service';
import { buildNotificationMessage } from './notification-templates';
import { EvolutionWhatsAppService } from './evolution-whatsapp.service';
import {
  isWithinNotificationBusinessHours,
  resolveInitialAttemptAt,
} from './notification-business-hours.util';
import { NotificationPayload } from './notification.types';

const WORKER_ID = `${hostname()}-${process.pid}`;

/**
 * Vigencia del lock de un intento de envío. Si un worker muere durante el envío,
 * la fila queda reclamable por otro worker pasado este margen.
 */
const OUTBOX_LOCK_TTL_MS = 2 * 60_000;

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly evolution: EvolutionWhatsAppService,
  ) {}

  normalizeWhatsAppNumber(raw: string) {
    return this.evolution.normalizeWhatsAppNumber(raw);
  }

  private getInitialAttemptAt(date: Date = new Date(), allowOutsideBusinessHours = false) {
    return resolveInitialAttemptAt(date, allowOutsideBusinessHours);
  }

  private pad2(n: number) {
    return String(n).padStart(2, '0');
  }

  private pad3(n: number) {
    return String(n).padStart(3, '0');
  }

  private computeFallbackOrderNumber(params: { createdAt?: Date | null; serviceId: string }) {
    const createdAt = params.createdAt instanceof Date ? params.createdAt : new Date();
    const serviceId = (params.serviceId ?? '').toString();

    const yyyy = createdAt.getFullYear();
    const MM = this.pad2(createdAt.getMonth() + 1);
    const dd = this.pad2(createdAt.getDate());
    const HH = this.pad2(createdAt.getHours());
    const mm = this.pad2(createdAt.getMinutes());
    const ss = this.pad2(createdAt.getSeconds());
    const SSS = this.pad3(createdAt.getMilliseconds());

    const hexTail = serviceId.replace(/-/g, '').slice(-6);
    const tailNum = hexTail ? parseInt(hexTail, 16) : 0;
    const stableSuffix = this.pad3(Math.abs(tailNum) % 1000);

    return `${yyyy}${MM}${dd}${HH}${mm}${ss}${SSS}${stableSuffix}`;
  }

  private extractServiceIdFromPayload(payload: unknown): string | null {
    try {
      const p: any = payload as any;
      const direct = p?.serviceId ? String(p.serviceId) : '';
      if (direct) return direct;
      const dataId = p?.data?.serviceId ? String(p.data.serviceId) : '';
      if (dataId) return dataId;
      return null;
    } catch {
      return null;
    }
  }

  private async resolveServiceOrderNumber(serviceId: string): Promise<string | null> {
    const id = (serviceId ?? '').toString().trim();
    if (!id) return null;

    try {
      const service = await this.prisma.service.findUnique({
        where: { id },
        select: { id: true, orderNumber: true, createdAt: true } as any,
      });

      if (!service) return null;
      const raw = typeof (service as any).orderNumber === 'string' ? (service as any).orderNumber.trim() : '';
      if (raw) return raw;

      const createdAt = (service as any).createdAt instanceof Date ? (service as any).createdAt : null;
      return this.computeFallbackOrderNumber({ createdAt, serviceId: id });
    } catch {
      // Best-effort: if migrations are missing, try again without selecting orderNumber.
      try {
        const service = await this.prisma.service.findUnique({
          where: { id },
          select: { id: true, createdAt: true } as any,
        });

        if (!service) return null;
        const createdAt = (service as any).createdAt instanceof Date ? (service as any).createdAt : null;
        return this.computeFallbackOrderNumber({ createdAt, serviceId: id });
      } catch {
        return null;
      }
    }
  }

  private stripServiceIdFromMessage(messageText: string, serviceId: string) {
    const id = (serviceId ?? '').toString().trim();
    if (!id) return messageText;
    return messageText
      .replace(`ID: ${id}.`, '')
      .replace(`ID: ${id}`, '')
      .replace(/\s{2,}/g, ' ')
      .trim();
  }

  private injectOrderNumberLine(messageText: string, orderNumber: string) {
    if (!orderNumber.trim()) return messageText;
    if (messageText.toLowerCase().includes('orden:')) return messageText;

    const orderLine = `Orden: ${orderNumber}`;
    if (messageText.includes('\n')) {
      const lines = messageText.split('\n');
      lines.splice(1, 0, orderLine);
      return lines.join('\n');
    }

    const base = messageText.trim();
    if (!base) return orderLine;
    const sep = base.endsWith('.') ? ' ' : '. ';
    return `${base}${sep}${orderLine}.`;
  }

  private async maybeInjectOrderNumber(messageText: string, payload?: unknown) {
    const serviceId = this.extractServiceIdFromPayload(payload);
    if (!serviceId) return messageText;

    const orderNumber = await this.resolveServiceOrderNumber(serviceId);
    if (!orderNumber) return messageText;

    const stripped = this.stripServiceIdFromMessage(messageText, serviceId);
    return this.injectOrderNumberLine(stripped, orderNumber);
  }

  private normalizeSenderUserId(raw?: string | null) {
    const value = (raw ?? '').toString().trim();
    return value || null;
  }

  private attachSenderUserId(payload: unknown, senderUserId?: string | null) {
    const normalizedSenderUserId = this.normalizeSenderUserId(senderUserId);
    if (!normalizedSenderUserId) {
      return (payload ?? null) as Prisma.InputJsonValue;
    }

    if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
      return {
        ...(payload as Record<string, unknown>),
        senderUserId: normalizedSenderUserId,
      } as Prisma.InputJsonValue;
    }

    return {
      senderUserId: normalizedSenderUserId,
      payload,
    } as Prisma.InputJsonValue;
  }

  private extractSenderUserId(payload: unknown) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return null;
    }

    const raw = (payload as Record<string, unknown>).senderUserId;
    return this.normalizeSenderUserId(typeof raw === 'string' ? raw : null);
  }

  /**
   * Crea una fila del outbox de forma idempotente.
   *
   * `dedupeKey` es único en la base: dos llamadas concurrentes con la misma clave
   * hacen que una gane el INSERT y la otra reciba P2002. En ese caso devolvemos la
   * fila ya existente en lugar de propagar el error al flujo de negocio que encola.
   */
  private async createOutboxEntry(args: {
    data: Prisma.NotificationOutboxUncheckedCreateInput;
  }): Promise<NotificationOutbox> {
    try {
      return await this.prisma.notificationOutbox.create(args);
    } catch (error) {
      const rawDedupeKey = args.data.dedupeKey;
      const dedupeKey = typeof rawDedupeKey === 'string' ? rawDedupeKey.trim() : '';
      if (
        dedupeKey &&
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const existing = await this.prisma.notificationOutbox.findUnique({ where: { dedupeKey } });
        if (existing) return existing;
      }
      throw error;
    }
  }

  private formatLocalYmdHm(d: Date) {
    const yyyy = d.getFullYear();
    const mm = this.pad2(d.getMonth() + 1);
    const dd = this.pad2(d.getDate());
    const hh = this.pad2(d.getHours());
    const min = this.pad2(d.getMinutes());
    return `${yyyy}-${mm}-${dd} ${hh}:${min}`;
  }

  private async disableLegacyReservationReminder(row: { id: string; payload: unknown }) {
    const payload = (row.payload ?? null) as any;
    const serviceId = payload?.serviceId ? String(payload.serviceId) : 'unknown';

    this.logger.warn(
      `legacy reservation_reminder disabled for outbox=${row.id} service=${serviceId}`,
    );

    await this.prisma.notificationOutbox.update({
      where: { id: row.id },
      data: {
        status: 'FAILED',
        lockedAt: null,
        lockedBy: null,
        lastError:
          'Flujo legado reservation_reminder deshabilitado: el sistema actual usa ServiceOrder/Operations y ya no debe reenviar recordatorios de reserva.',
        lastStatusCode: null,
      },
    });
  }

  async enqueueWhatsAppRawText(params: {
    toNumber: string;
    messageText: string;
    dedupeKey?: string;
    payload?: unknown;
    senderUserId?: string | null;
    /**
     * Alertas operativas críticas (APPYRA Guardian): el primer intento no se
     * desplaza a la ventana comercial y el despachador no las retiene.
     */
    allowOutsideBusinessHours?: boolean;
  }) {
    const dedupeKey = (params.dedupeKey ?? '').toString().trim();
    if (dedupeKey) {
      const existing = await this.prisma.notificationOutbox.findUnique({
        where: { dedupeKey },
      });
      if (existing) {
        return existing;
      }
    }

    const rawPhone = (params.toNumber ?? '').toString().trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);
    let messageText = (params.messageText ?? '').toString();
    messageText = await this.maybeInjectOrderNumber(messageText, params.payload);
    const allowOutsideBusinessHours = params.allowOutsideBusinessHours === true;
    const nextAttemptAt = this.getInitialAttemptAt(new Date(), allowOutsideBusinessHours);
    const payload = allowOutsideBusinessHours
      ? {
          ...((params.payload && typeof params.payload === 'object' && !Array.isArray(params.payload))
            ? params.payload as Record<string, unknown>
            : { payload: params.payload }),
          allowOutsideBusinessHours: true,
        }
      : params.payload;

    if (!normalized) {
      return this.createOutboxEntry({
        data: {
          channel: 'WHATSAPP',
          status: 'FAILED',
          templateKey: 'custom_text',
          dedupeKey: dedupeKey || null,
          messageText,
          payload: this.attachSenderUserId(payload, params.senderUserId),
          recipientUserId: null,
          toNumber: rawPhone,
          toNumberNormalized: '',
          attempts: 0,
          nextAttemptAt,
          lastError: 'Número de WhatsApp inválido',
        },
      });
    }

    if (!messageText.trim()) {
      return this.createOutboxEntry({
        data: {
          channel: 'WHATSAPP',
          status: 'FAILED',
          templateKey: 'custom_text',
          dedupeKey: dedupeKey || null,
          messageText,
          payload: this.attachSenderUserId(payload, params.senderUserId),
          recipientUserId: null,
          toNumber: rawPhone,
          toNumberNormalized: normalized,
          attempts: 0,
          nextAttemptAt,
          lastError: 'Mensaje vacío',
        },
      });
    }

    return this.createOutboxEntry({
      data: {
        channel: 'WHATSAPP',
        contentType: 'TEXT' as any,
        status: 'PENDING',
        templateKey: 'custom_text',
        dedupeKey: dedupeKey || null,
        messageText,
        payload: this.attachSenderUserId(payload, params.senderUserId),
        recipientUserId: null,
        toNumber: rawPhone,
        toNumberNormalized: normalized,
        attempts: 0,
        nextAttemptAt,
      },
    });
  }

  async enqueueWhatsAppDocument(params: {
    toNumber: string;
    messageText: string;
    fileName: string;
    bytes: Uint8Array;
    mimeType?: string;
    dedupeKey?: string;
    payload?: unknown;
    recipientUserId?: string | null;
    senderUserId?: string | null;
    scheduledFor?: Date | string | null;
    allowOutsideBusinessHours?: boolean;
  }) {
    const rawPhone = (params.toNumber ?? '').toString().trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);
    const fileName = (params.fileName ?? '').toString().trim() || 'document.pdf';
    const mimeType = (params.mimeType ?? 'application/pdf').toString().trim() || 'application/pdf';
    const bytes = params.bytes instanceof Uint8Array ? params.bytes : new Uint8Array(params.bytes);
    let messageText = (params.messageText ?? '').toString();
    messageText = await this.maybeInjectOrderNumber(messageText, params.payload);
    const scheduledFor = params.scheduledFor
      ? new Date(params.scheduledFor)
      : null;
    const nextAttemptAt = scheduledFor && !Number.isNaN(scheduledFor.getTime())
      ? scheduledFor
      : this.getInitialAttemptAt(new Date(), params.allowOutsideBusinessHours === true);
    const payload = params.allowOutsideBusinessHours
      ? {
          ...((params.payload && typeof params.payload === 'object' && !Array.isArray(params.payload))
            ? params.payload as Record<string, unknown>
            : { payload: params.payload }),
          allowOutsideBusinessHours: true,
        }
      : params.payload;

    const data = {
      channel: 'WHATSAPP' as const,
      contentType: 'DOCUMENT' as any,
      status: (!normalized || !bytes.length || !messageText.trim()) ? 'FAILED' as const : 'PENDING' as const,
      templateKey: 'custom_document',
      dedupeKey: params.dedupeKey ?? null,
      messageText,
      mediaBase64: bytes.length ? Buffer.from(bytes).toString('base64') : null,
      mediaFileName: fileName,
      mediaMimeType: mimeType,
      payload: this.attachSenderUserId(payload, params.senderUserId),
      recipientUserId: (params.recipientUserId ?? null) as any,
      toNumber: rawPhone,
      toNumberNormalized: normalized || '',
      attempts: 0,
      nextAttemptAt,
      lastError: !normalized
        ? 'Número de WhatsApp inválido'
        : !bytes.length
          ? 'El documento está vacío'
          : !messageText.trim()
            ? 'Mensaje vacío'
            : null,
    };

    if (params.dedupeKey?.trim()) {
      return this.prisma.notificationOutbox.upsert({
        where: { dedupeKey: params.dedupeKey.trim() },
        create: data,
        update: {
          ...data,
          lockedAt: null,
          lockedBy: null,
          sentAt: null,
          lastStatusCode: null,
        },
      });
    }

    return this.prisma.notificationOutbox.create({
      data,
    });
  }

  async enqueueWhatsAppToUser(params: {
    recipientUserId: string;
    payload: NotificationPayload;
    dedupeKey?: string;
    senderUserId?: string | null;
  }) {
    const user = await this.prisma.user.findUnique({
      where: { id: params.recipientUserId },
      select: { id: true, telefono: true, blocked: true },
    });

    const rawPhone = (user?.telefono ?? '').trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);

    let messageText = buildNotificationMessage(params.payload);
    messageText = await this.maybeInjectOrderNumber(messageText, params.payload);
    const nextAttemptAt = this.getInitialAttemptAt();

    if (!user || user.blocked) {
      return this.createOutboxEntry({
        data: {
          channel: 'WHATSAPP',
          contentType: 'TEXT' as any,
          status: 'FAILED',
          templateKey: params.payload.template,
          dedupeKey: params.dedupeKey ?? null,
          messageText,
          payload: this.attachSenderUserId(params.payload, params.senderUserId),
          recipientUserId: params.recipientUserId,
          toNumber: rawPhone,
          toNumberNormalized: normalized,
          attempts: 0,
          nextAttemptAt,
          lastError: 'Usuario inválido o bloqueado',
        },
      });
    }

    if (!normalized) {
      return this.createOutboxEntry({
        data: {
          channel: 'WHATSAPP',
          contentType: 'TEXT' as any,
          status: 'FAILED',
          templateKey: params.payload.template,
          dedupeKey: params.dedupeKey ?? null,
          messageText,
          payload: this.attachSenderUserId(params.payload, params.senderUserId),
          recipientUserId: params.recipientUserId,
          toNumber: rawPhone,
          toNumberNormalized: '',
          attempts: 0,
          nextAttemptAt,
          lastError: 'Usuario no tiene teléfono válido',
        },
      });
    }

    return this.createOutboxEntry({
      data: {
        channel: 'WHATSAPP',
        contentType: 'TEXT' as any,
        status: 'PENDING',
        templateKey: params.payload.template,
        dedupeKey: params.dedupeKey ?? null,
        messageText,
        payload: this.attachSenderUserId(params.payload, params.senderUserId),
        recipientUserId: params.recipientUserId,
        toNumber: rawPhone,
        toNumberNormalized: normalized,
        attempts: 0,
        nextAttemptAt,
      },
    });
  }

  private backoffMs(attempts: number) {
    // attempts is 1-based after a failure.
    if (attempts <= 1) return 60_000;
    if (attempts === 2) return 5 * 60_000;
    if (attempts === 3) return 15 * 60_000;
    if (attempts === 4) return 60 * 60_000;
    return 3 * 60 * 60_000;
  }

  /**
   * Reclama filas del outbox de forma atómica.
   *
   * Cada fila se reclama con un compare-and-swap: el `updateMany` incluye el
   * predicado de elegibilidad (estado, `nextAttemptAt` y lock libre o vencido),
   * por lo que PostgreSQL reevalúa la condición sobre la versión actualizada de
   * la fila. Si otro worker la reclamó primero, el conteo es 0 y se descarta.
   * Así dos workers o dos réplicas no pueden procesar la misma notificación.
   */
  private async claimDueRows(limit: number, now: Date) {
    const lockExpiry = new Date(now.getTime() - OUTBOX_LOCK_TTL_MS);
    const claimableWhere: Prisma.NotificationOutboxWhereInput = {
      status: { in: ['PENDING', 'SENDING'] },
      nextAttemptAt: { lte: now },
      OR: [{ lockedAt: null }, { lockedAt: { lt: lockExpiry } }],
    };

    const candidates = await this.prisma.notificationOutbox.findMany({
      where: claimableWhere,
      select: { id: true },
      orderBy: [{ nextAttemptAt: 'asc' }, { createdAt: 'asc' }],
      take: limit,
    });

    if (!candidates.length) return [];

    const claimedIds: string[] = [];
    for (const candidate of candidates) {
      const claim = await this.prisma.notificationOutbox.updateMany({
        where: { id: candidate.id, ...claimableWhere },
        data: {
          status: 'SENDING',
          lockedAt: now,
          lockedBy: WORKER_ID,
        },
      });
      if (claim.count === 1) claimedIds.push(candidate.id);
    }

    if (!claimedIds.length) return [];

    return this.prisma.notificationOutbox.findMany({
      where: { id: { in: claimedIds } },
      orderBy: [{ nextAttemptAt: 'asc' }, { createdAt: 'asc' }],
    });
  }

  async processOutboxBatch(limit = 25) {
    const now = new Date();
    const claimed = await this.claimDueRows(limit, now);

    for (const row of claimed) {
      try {
        const payload = (row.payload ?? null) as any;
        const kind = payload?.kind ? String(payload.kind) : '';
        const senderUserId = this.extractSenderUserId(payload);
        const requirePersonalInstance =
          payload && typeof payload === 'object' && !Array.isArray(payload)
            ? (payload as Record<string, unknown>).requirePersonalInstance === true
            : false;
        const allowOutsideBusinessHours =
          payload && typeof payload === 'object' && !Array.isArray(payload)
            ? (payload as Record<string, unknown>).allowOutsideBusinessHours === true
            : false;
        if (kind === 'reservation_reminder') {
          await this.disableLegacyReservationReminder(row);
          continue;
        }

        if (!allowOutsideBusinessHours && !isWithinNotificationBusinessHours()) {
          await this.prisma.notificationOutbox.update({
            where: { id: row.id },
            data: {
              status: 'PENDING',
              nextAttemptAt: this.getInitialAttemptAt(),
              lockedAt: null,
              lockedBy: null,
              lastError: null,
            },
          });
          continue;
        }

        const contentType = String((row as any).contentType ?? 'TEXT').toUpperCase();
        if (contentType === 'DOCUMENT') {
          const mediaBase64 = ((row as any).mediaBase64 ?? '').toString();
          const mediaFileName = ((row as any).mediaFileName ?? '').toString().trim() || 'document.pdf';
          if (!mediaBase64.trim()) {
            throw new Error('Documento faltante en notification_outbox');
          }

          await this.evolution.sendPdfDocument({
            toNumber: row.toNumberNormalized,
            bytes: Buffer.from(mediaBase64, 'base64'),
            fileName: mediaFileName,
            caption: row.messageText,
            senderUserId,
            requirePersonalInstance,
          });
        } else {
          await this.evolution.sendTextMessage({
            toNumber: row.toNumberNormalized,
            message: row.messageText,
            senderUserId,
            requirePersonalInstance,
          });
        }

        this.logger.log(`notification sent id=${row.id} contentType=${contentType} to=${row.toNumberNormalized}`);

        await this.prisma.notificationOutbox.update({
          where: { id: row.id },
          data: {
            status: 'SENT',
            sentAt: new Date(),
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            lastStatusCode: null,
          },
        });
      } catch (e) {
        const attempts = (row.attempts ?? 0) + 1;
        const maxAttempts = 6;
        const errMsg = (e as any)?.message ? String((e as any).message) : String(e);
        const statusCode = typeof (e as any)?.status === 'number' ? (e as any).status : null;

        this.logger.warn(`notification failed id=${row.id} attempts=${attempts} status=${statusCode ?? 'n/a'} error=${errMsg}`);

        await this.prisma.notificationOutbox.update({
          where: { id: row.id },
          data: {
            status: attempts >= maxAttempts ? 'FAILED' : 'PENDING',
            attempts,
            nextAttemptAt: new Date(Date.now() + this.backoffMs(attempts)),
            lockedAt: null,
            lockedBy: null,
            lastError: errMsg.slice(0, 1800),
            lastStatusCode: statusCode,
          },
        });
      }
    }
  }
}
