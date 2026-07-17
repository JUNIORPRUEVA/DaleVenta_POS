import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { NotificationStatus, Prisma, Role, ServiceOrderStatus, ServiceOrderType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  alignToNotificationBusinessHours,
  isSameDominicanDay,
} from './notification-business-hours.util';
import { NotificationsService } from './notifications.service';

type ServiceOrderNotificationContext = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    quotation: {
      include: {
        items: {
          orderBy: {
            createdAt: 'asc';
          };
        };
      };
    };
    createdBy: {
      select: {
        id: true;
        nombreCompleto: true;
        telefono: true;
        numeroFlota: true;
        blocked: true;
      };
    };
    assignedTo: {
      select: {
        id: true;
        nombreCompleto: true;
        telefono: true;
        numeroFlota: true;
        blocked: true;
      };
    };
    reports: {
      orderBy: {
        createdAt: 'asc';
      };
    };
    evidences: {
      orderBy: {
        createdAt: 'asc';
      };
    };
  };
}>;

type InternalRecipient = {
  userId: string;
  name: string;
  numbers: string[];
};

type InProgressReminderRecipient = {
  userId: string;
  name: string;
  number: string;
};

type ServiceOrderNotificationEventType =
  | 'SERVICE_ORDER_CREATED_TECH_NOTIFY'
  | 'SERVICE_ORDER_IN_PROGRESS_CUSTOMER_SERVICE'
  | 'SERVICE_ORDER_IN_PROGRESS_CREATOR'
  | 'SERVICE_ORDER_PAUSED_CREATOR'
  | 'SERVICE_ORDER_FINISHED_CREATOR'
  | 'SERVICE_ORDER_FINISHED_CUSTOMER_SERVICE'
  | 'SERVICE_ORDER_FINISHED_ADMIN';

type StatusChangeMeta = {
  actorUserId?: string | null;
  note?: string | null;
};

@Injectable()
export class ServiceOrderNotificationsListener {
  private readonly logger = new Logger(ServiceOrderNotificationsListener.name);
  private static readonly DEFAULT_TECH_NOTIFY_MINUTES_BEFORE = 30;
  private static readonly PENDING_TECHNICIAN_REMINDER_INTERVAL_MINUTES = 60;
  private static readonly IN_PROGRESS_REMINDER_INTERVAL_MINUTES = 120;
  private static readonly MAX_TECHNICIAN_REMINDERS_PER_RECIPIENT = 2;
  private static readonly CREATED_TECH_EVENT: ServiceOrderNotificationEventType =
    'SERVICE_ORDER_CREATED_TECH_NOTIFY';
  private static readonly IN_PROGRESS_CUSTOMER_SERVICE_EVENT: ServiceOrderNotificationEventType =
    'SERVICE_ORDER_IN_PROGRESS_CUSTOMER_SERVICE';
  private static readonly IN_PROGRESS_CREATOR_EVENT: ServiceOrderNotificationEventType =
    'SERVICE_ORDER_IN_PROGRESS_CREATOR';
  private static readonly PAUSED_CREATOR_EVENT: ServiceOrderNotificationEventType =
    'SERVICE_ORDER_PAUSED_CREATOR';
  private static readonly FINISHED_CREATOR_EVENT: ServiceOrderNotificationEventType =
    'SERVICE_ORDER_FINISHED_CREATOR';
  private static readonly FINISHED_CUSTOMER_SERVICE_EVENT: ServiceOrderNotificationEventType =
    'SERVICE_ORDER_FINISHED_CUSTOMER_SERVICE';
  private static readonly FINISHED_ADMIN_EVENT: ServiceOrderNotificationEventType =
    'SERVICE_ORDER_FINISHED_ADMIN';
  private static readonly IN_PROGRESS_REMINDER_KINDS = [
    'service_order_in_progress_started',
    'service_order_in_progress_reminder',
  ] as const;
  private static readonly TECHNICIAN_REMINDER_KINDS = [
    'SERVICE_ORDER_CREATED_TECH_NOTIFY',
    'service_order_thirty_minutes_before',
    'service_order_twenty_minutes_before',
    'service_order_fifteen_minutes_pending',
    'service_order_hourly_pending',
  ] as const;
  private static readonly IN_PROGRESS_REMINDER_MESSAGE =
    'Recuerda: tienes una orden en proceso. Finalizala en la app al terminar.';

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  async handleOrderCreated(orderId: string) {
    await this.scheduleThirtyMinuteReminder(orderId);
  }

  async handleOrderUpdated(orderId: string) {
    await this.scheduleThirtyMinuteReminder(orderId);
  }

  async handleOrderDeleted(orderId: string) {
    await this.cancelPendingReminderJobs(orderId, 'Orden eliminada');
    await this.cancelPendingTechnicianReminderJobs(orderId, 'Orden eliminada');
  }

  async handleOrderConfirmed(orderId: string, technicianId: string) {
    const order = await this.loadContext(orderId);
    const technician = order.assignedTo;
    if (!technician || technician.id !== technicianId) {
      throw new NotFoundException('Técnico confirmado no encontrado en la orden');
    }

    await this.cancelPendingReminderJobs(order.id, 'Orden confirmada por tecnico');
    await this.cancelPendingTechnicianReminderJobs(order.id, 'Orden confirmada por tecnico');
    await this.cancelPendingTechnicianReminderOutbox(order.id, 'Orden confirmada por tecnico');

    const recipients = this.collectCreatorRecipients(order);
    if (!recipients.length) {
      this.logger.warn(`No creator recipients found for confirmation order=${order.id}`);
      return;
    }

    const message = [
      '*Técnico confirmado*',
      `Técnico: ${technician.nombreCompleto}`,
      `Cliente: ${order.client.nombre}`,
      `Teléfono cliente: ${order.client.telefono}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Detalle: ${this.orderDetails(order)}`,
      'El técnico confirmó en la app y puede continuar con el servicio.',
    ].join('\n');

    for (const recipient of recipients) {
      await this.enqueueOrderWhatsAppRawText(order, {
        toNumber: recipient,
        messageText: message,
        dedupeKey: `service-order:confirm:${order.id}:${technician.id}:${recipient}`,
        payload: {
          kind: 'service_order_confirmation',
          orderId: order.id,
          technicianId: technician.id,
          creatorId: order.createdBy.id,
        },
      });
    }
  }

  async handleStatusChanged(
    orderId: string,
    previousStatus: string,
    nextStatus: string,
    meta: StatusChangeMeta = {},
  ) {
    await this.cancelPendingInProgressReminderOutbox(orderId, `Estado actualizado a ${nextStatus}`);

    if (
      nextStatus === 'en_proceso' ||
      nextStatus === 'finalizado' ||
      nextStatus === 'cancelado' ||
      nextStatus === 'pospuesta'
    ) {
      await this.cancelPendingReminderJobs(orderId, `Estado actualizado a ${nextStatus}`);
      await this.cancelPendingTechnicianReminderJobs(orderId, `Estado actualizado a ${nextStatus}`);
      await this.cancelPendingTechnicianReminderOutbox(orderId, `Estado actualizado a ${nextStatus}`);
    }

    if (previousStatus === 'pospuesta' && nextStatus === 'pendiente') {
      await this.notifyPostponedOrderReady(orderId);
      return;
    }

    if (nextStatus === 'en_proceso') {
      await this.notifyServiceStarted(orderId);
      return;
    }

    if (nextStatus === 'en_pausa') {
      await this.notifyServicePaused(orderId, meta);
      return;
    }

    if (nextStatus === 'finalizado') {
      await this.notifyServiceFinalized(orderId);
      return;
    }

    this.logger.debug(`No notification flow for service-order status change ${previousStatus} -> ${nextStatus} order=${orderId}`);
  }

  async processDueInProgressReminders(_limit = 25) {
    this.logger.debug('In-progress technician reminders are disabled.');
    return 0;
  }

  async dispatchThirtyMinuteReminder(jobId: string) {
    const job = await this.prisma.serviceOrderNotificationJob.findUnique({
      where: { id: jobId },
    });

    if (!job) {
      throw new NotFoundException('Job de notificación no encontrado');
    }

    const order = await this.loadContext(job.orderId);
    if (!order.scheduledFor) {
      await this.markJobCancelled(job.id, 'La orden no tiene fecha programada');
      return;
    }

    if (
      order.status === ServiceOrderStatus.CANCELADO ||
      order.status === ServiceOrderStatus.FINALIZADO ||
      order.status === ServiceOrderStatus.POSPUESTA
    ) {
      await this.markJobCancelled(job.id, `La orden ya no es notificable (${order.status})`);
      return;
    }

    if (order.technicianConfirmedById) {
      await this.markJobCancelled(job.id, 'La orden ya fue confirmada por un tecnico');
      return;
    }

    const payloadScheduledFor = this.extractScheduledFor(job.payload);
    if (payloadScheduledFor && payloadScheduledFor !== order.scheduledFor.toISOString()) {
      await this.markJobCancelled(job.id, 'La fecha programada cambió y el job quedó obsoleto');
      return;
    }

    const payloadAssignedToId = this.extractAssignedToUserId(job.payload);
    const currentAssignedToId = (order.assignedToId ?? '').trim() || null;
    if (payloadAssignedToId !== currentAssignedToId) {
      await this.markJobCancelled(job.id, 'El técnico asignado cambió y el job quedó obsoleto');
      return;
    }

    const recipients = await this.resolveTechnicianRecipients(order);
    if (!recipients.length) {
      this.logger.warn(`No technician recipients found for created-order notification order=${order.id}`);
      return;
    }

    const message = this.buildCreatedOrderMessage(order);

    for (const recipient of recipients) {
      for (const number of recipient.numbers) {
        await this.enqueueTechnicianCreatedNotification(order, {
          recipientUserId: recipient.userId,
          recipientName: recipient.name,
          toNumber: number,
          messageText: message,
        });
      }
    }
  }

  async scheduleThirtyMinuteReminder(orderId: string) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      select: {
        id: true,
        status: true,
        scheduledFor: true,
        technicianConfirmedById: true,
        assignedToId: true,
      },
    });

    if (!order) {
      return;
    }

    await this.cancelPendingReminderJobs(order.id, 'Reprogramando notificación programada');
    await this.cancelPendingTechnicianReminderJobs(order.id, 'Deshabilitando recordatorios antiguos duplicados');
    await this.cancelPendingTechnicianReminderOutbox(
      order.id,
      'Deshabilitando recordatorios antiguos duplicados',
    );

    const notifyMinutesBefore = this.resolveTechNotifyMinutesBefore();

    if (
      order.status === ServiceOrderStatus.CANCELADO ||
      order.status === ServiceOrderStatus.FINALIZADO ||
      order.status === ServiceOrderStatus.POSPUESTA ||
      order.technicianConfirmedById
    ) {
      return;
    }

    if (!order.scheduledFor) {
      await this.notifyCreatedOrderNow(order.id);
      return;
    }

    const runAt = new Date(order.scheduledFor.getTime() - notifyMinutesBefore * 60_000);
    if (runAt.getTime() <= Date.now()) {
      await this.notifyCreatedOrderNow(order.id);
      return;
    }

    const nextRunAt = alignToNotificationBusinessHours(
      runAt,
    );
    const dedupeKey = `service-order:job:created-tech:${order.id}:${order.scheduledFor.toISOString()}:${(order.assignedToId ?? 'all').toString()}`;

    await this.prisma.serviceOrderNotificationJob.create({
      data: {
        orderId: order.id,
        kind: 'THIRTY_MINUTES_BEFORE',
        status: 'PENDING',
        dedupeKey,
        runAt: nextRunAt,
        payload: {
          scheduledFor: order.scheduledFor.toISOString(),
          assignedToId: order.assignedToId,
          notifyMinutesBefore,
        },
      },
    }).catch(async (error: unknown) => {
      const code = typeof error === 'object' && error && 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
      if (code === 'P2002') {
        await this.prisma.serviceOrderNotificationJob.update({
          where: { dedupeKey },
          data: {
            status: 'PENDING',
            runAt: nextRunAt,
            payload: {
              scheduledFor: order.scheduledFor?.toISOString() ?? null,
              assignedToId: order.assignedToId,
              notifyMinutesBefore,
            },
            attempts: 0,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            completedAt: null,
          },
        });
        return;
      }
      throw error;
    });
  }

  async dispatchPendingTechnicianReminder(jobId: string) {
    const job = await this.prisma.serviceOrderNotificationJob.findUnique({
      where: { id: jobId },
    });

    if (!job) {
      throw new NotFoundException('Job de notificación no encontrado');
    }

    const order = await this.loadContext(job.orderId);

    if (order.status !== ServiceOrderStatus.PENDIENTE) {
      await this.markJobCancelled(job.id, `La orden ya cambió de estado (${order.status})`);
      return;
    }

    if (order.technicianConfirmedById) {
      await this.markJobCancelled(job.id, 'La orden ya fue confirmada por un tecnico');
      return;
    }

    if (!this.shouldNotifyTechniciansForPending(order)) {
      await this.cancelPendingTechnicianReminderJobs(
        order.id,
        'La orden solo debe notificar seguimiento el mismo dia agendado',
      );
      return;
    }

    const technicians = await this.getRoleRecipients(Role.TECNICO, { fleetOnly: true, fallbackToPhone: true });
    if (!technicians.length) {
      this.logger.warn(`No technician recipients found for hourly pending reminder order=${order.id}`);
      return;
    }

    const message = [
      '*¡Nuevo servicio disponible!*',
      `Cliente: ${order.client.nombre}`,
      `Teléfono cliente: ${order.client.telefono}`,
      `Ubicación: ${this.mapsLink(order)}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Detalle: ${this.orderDetails(order)}`,
      order.scheduledFor ? `Programado para: ${order.scheduledFor.toLocaleString('es-DO')}` : 'Sin hora programada',
      'Abre la app y toma la orden para iniciar el servicio.',
    ].join('\n');

    let enqueuedCount = 0;
    for (const technician of technicians) {
      for (const number of technician.numbers) {
        const nextReminderSequence = await this.getNextTechnicianReminderSequence(order.id, number);
        if (!nextReminderSequence) {
          this.logger.warn(`Technician reminder limit reached order=${order.id} recipient=${number}`);
          continue;
        }

        await this.enqueueOrderWhatsAppRawText(order, {
          toNumber: number,
          messageText: this.buildTechnicianReminderMessage(message, nextReminderSequence),
          dedupeKey: `service-order:1h-pending:${order.id}:${job.runAt.toISOString()}:${technician.userId}:${number}`,
          payload: {
            kind: 'service_order_hourly_pending',
            jobId: job.id,
            orderId: order.id,
            scheduledFor: order.scheduledFor?.toISOString(),
            recipientUserId: technician.userId,
          },
        });
        enqueuedCount += 1;
      }
    }

    if (!enqueuedCount) {
      await this.cancelPendingTechnicianReminderJobs(
        order.id,
        'Se alcanzó el maximo de 2 recordatorios por orden y destinatario',
      );
      return;
    }

    const nextRunAt = await this.computeNextPendingTechnicianReminderRunAt(order.id);

    if (!this.shouldNotifyTechniciansForPending(order, nextRunAt)) {
      return;
    }

    const nextDedupeKey = `service-order:job:1h-pending:${order.id}:run-${nextRunAt.toISOString()}`;

    await this.prisma.serviceOrderNotificationJob.create({
      data: {
        orderId: order.id,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: 'PENDING',
        dedupeKey: nextDedupeKey,
        runAt: nextRunAt,
        payload: {
          createdFrom: job.id,
        },
      },
    }).catch(async (error: unknown) => {
      const code = typeof error === 'object' && error && 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
      if (code === 'P2002') {
        // Duplo detectado, actualizar con nueva fecha
        await this.prisma.serviceOrderNotificationJob.update({
          where: { dedupeKey: nextDedupeKey },
          data: {
            status: 'PENDING',
            runAt: nextRunAt,
            attempts: 0,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            completedAt: null,
          },
        });
        return;
      }
      this.logger.error(`Error creando siguiente job horario para orden ${order.id}:`, error);
    });
  }

  async syncPendingTechnicianReminders(orderId: string) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      select: {
        id: true,
        status: true,
        scheduledFor: true,
        technicianConfirmedById: true,
      },
    });

    if (!order) {
      return;
    }

    await this.cancelPendingTechnicianReminderJobs(order.id, 'Reprogramando seguimiento tecnico');

    if (!this.shouldNotifyTechniciansForPending(order)) {
      return;
    }

    const runAt = await this.computeNextPendingTechnicianReminderRunAt(order.id);
    const dedupeKey = `service-order:job:1h-pending:${order.id}:initial`;

    await this.prisma.serviceOrderNotificationJob.create({
      data: {
        orderId: order.id,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: 'PENDING',
        dedupeKey,
        runAt,
        payload: {
          isInitial: true,
        },
      },
    }).catch(async (error: unknown) => {
      const code = typeof error === 'object' && error && 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
      if (code === 'P2002') {
        await this.prisma.serviceOrderNotificationJob.update({
          where: { dedupeKey },
          data: {
            status: 'PENDING',
            runAt,
            attempts: 0,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            completedAt: null,
          },
        });
        return;
      }
      throw error;
    });
  }

  private async notifyServiceStarted(orderId: string) {
    const order = await this.loadContext(orderId);
    const creatorRecipients = this.collectCreatorRecipients(order);
    const customerServiceRecipients = await this.getRoleRecipients(Role.ASISTENTE, {
      fleetOnly: false,
      fallbackToPhone: true,
    });

    const scheduleLabel = order.scheduledFor
      ? order.scheduledFor.toLocaleString('es-DO')
      : 'Sin fecha programada';
    const quotationTotal = this.formatQuotationTotal(order);
    const technicianName = order.assignedTo?.nombreCompleto?.trim() || 'Sin técnico asignado';

    const customerServiceMessage = [
      '*FULLTECH - Orden de servicio*',
      'Estado: EN PROCESO',
      `Cliente: ${order.client.nombre}`,
      `Teléfono cliente: ${(order.client.telefono ?? '').trim() || 'No disponible'}`,
      `Dirección: ${this.mapsLink(order)}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Técnico: ${technicianName}`,
      `Fecha/Hora: ${scheduleLabel}`,
      quotationTotal ? `Monto/Cotización: ${quotationTotal}` : null,
      'Próximo paso: preparar factura y documentación correspondiente.',
    ]
      .filter(Boolean)
      .join('\n');

    const creatorMessage = [
      '*FULLTECH - Orden de servicio*',
      'Estado: EN PROCESO',
      `Cliente: ${order.client.nombre}`,
      `Técnico: ${technicianName}`,
      `Fecha/Hora: ${scheduleLabel}`,
      'Estado actual: EN PROCESO',
      'Próximo paso: seguimiento operativo de la orden.',
    ].join('\n');

    for (const assistant of customerServiceRecipients) {
      for (const number of assistant.numbers) {
        await this.enqueueCompanyEventNotification(order, {
          eventType: ServiceOrderNotificationsListener.IN_PROGRESS_CUSTOMER_SERVICE_EVENT,
          recipientUserId: assistant.userId,
          toNumber: number,
          messageText: customerServiceMessage,
        });
      }
    }

    for (const recipient of creatorRecipients) {
      await this.enqueueCompanyEventNotification(order, {
        eventType: ServiceOrderNotificationsListener.IN_PROGRESS_CREATOR_EVENT,
        recipientUserId: order.createdBy.id,
        toNumber: recipient,
        messageText: creatorMessage,
      });
    }

    if (!customerServiceRecipients.length) {
      this.logger.warn(`No servicio-al-cliente recipients found for in-progress order=${order.id}`);
    }
    if (!creatorRecipients.length) {
      this.logger.warn(`No creator recipients found for in-progress order=${order.id}`);
    }
  }

  private async notifyInProgressActor(orderId: string, actorUserId?: string | null) {
    if (!actorUserId) {
      this.logger.warn(`No actor user id found for in-progress reminder order=${orderId}`);
      return;
    }

    const recipient = await this.resolveInProgressReminderRecipient(actorUserId);
    if (!recipient) {
      return;
    }

    await this.enqueueInProgressReminder(
      orderId,
      recipient,
      'service_order_in_progress_started',
      new Date(),
    );
  }

  private async notifyServiceFinalized(orderId: string) {
    const order = await this.loadContext(orderId);
    const creatorRecipients = this.collectCreatorRecipients(order);
    const customerServiceRecipients = await this.getRoleRecipients(Role.ASISTENTE, {
      fleetOnly: false,
      fallbackToPhone: true,
    });
    const adminRecipients = await this.getRoleRecipients(Role.ADMIN, {
      fleetOnly: false,
      fallbackToPhone: true,
    });

    const scheduleLabel = order.scheduledFor
      ? order.scheduledFor.toLocaleString('es-DO')
      : 'Sin fecha programada';
    const technicianName = order.assignedTo?.nombreCompleto?.trim() || 'Sin técnico asignado';
    const evidenceSummary = this.buildEvidenceSummary(order);

    const message = [
      '*FULLTECH - Orden de servicio*',
      'Estado: FINALIZADA',
      `Cliente: ${order.client.nombre}`,
      `Técnico: ${technicianName}`,
      `Servicio realizado: ${this.formatServiceLabel(order)}`,
      `Fecha/Hora: ${scheduleLabel}`,
      `Evidencias: ${evidenceSummary}`,
      `Referencia de orden: ${order.id}`,
      'Próximo paso: documentación lista para enviar cotización/factura.',
    ].join('\n');

    for (const recipient of creatorRecipients) {
      await this.enqueueCompanyEventNotification(order, {
        eventType: ServiceOrderNotificationsListener.FINISHED_CREATOR_EVENT,
        recipientUserId: order.createdBy.id,
        toNumber: recipient,
        messageText: message,
      });
    }

    for (const assistant of customerServiceRecipients) {
      for (const number of assistant.numbers) {
        await this.enqueueCompanyEventNotification(order, {
          eventType: ServiceOrderNotificationsListener.FINISHED_CUSTOMER_SERVICE_EVENT,
          recipientUserId: assistant.userId,
          toNumber: number,
          messageText: message,
        });
      }
    }

    for (const admin of adminRecipients) {
      for (const number of admin.numbers) {
        await this.enqueueCompanyEventNotification(order, {
          eventType: ServiceOrderNotificationsListener.FINISHED_ADMIN_EVENT,
          recipientUserId: admin.userId,
          toNumber: number,
          messageText: message,
        });
      }
    }
  }

  private async notifyServicePaused(orderId: string, meta: StatusChangeMeta) {
    const order = await this.loadContext(orderId);
    const creatorRecipients = this.collectCreatorRecipients(order);
    if (!creatorRecipients.length) {
      this.logger.warn(`No creator recipients found for paused order=${order.id}`);
      return;
    }

    const actorName = await this.resolveActorDisplayName(meta.actorUserId);
    const note = (meta.note ?? '').trim();
    const scheduleLabel = order.scheduledFor
      ? order.scheduledFor.toLocaleString('es-DO')
      : 'Sin fecha programada';

    const message = [
      '*FULLTECH - Orden de servicio*',
      'Estado: EN PAUSA',
      `Cliente: ${order.client.nombre}`,
      `Técnico que pausó: ${actorName}`,
      note ? `Motivo de pausa: ${note}` : null,
      `Fecha/Hora: ${scheduleLabel}`,
      'Estado actual: EN PAUSA',
      'Indicación: dar seguimiento y coordinar la reanudación del servicio.',
    ]
      .filter(Boolean)
      .join('\n');

    for (const recipient of creatorRecipients) {
      await this.enqueueCompanyEventNotification(order, {
        eventType: ServiceOrderNotificationsListener.PAUSED_CREATOR_EVENT,
        recipientUserId: order.createdBy.id,
        toNumber: recipient,
        messageText: message,
      });
    }
  }

  private async notifyPostponedOrderReady(orderId: string) {
    const order = await this.loadContext(orderId);
    const recipients = this.collectCreatorRecipients(order);
    if (!recipients.length) {
      this.logger.warn(`No creator recipients found for postponed reset order=${order.id}`);
      return;
    }

    const scheduleLabel = order.scheduledFor
      ? order.scheduledFor.toLocaleString('es-DO')
      : 'Hoy';
    const message = [
      'Tienes una orden programada para hoy. Por favor contacta al cliente para el servicio.',
      `Cliente: ${order.client.nombre}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Fecha: ${scheduleLabel}`,
    ].join('\n');

    for (const recipient of recipients) {
      await this.enqueueOrderWhatsAppRawText(order, {
        toNumber: recipient,
        messageText: message,
        dedupeKey: `service-order:postponed-ready:${order.id}:${recipient}:${order.scheduledFor?.toISOString() ?? 'no-date'}`,
        payload: {
          kind: 'service_order_postponed_ready',
          orderId: order.id,
          recipient,
        },
      });
    }
  }

  private async loadContext(orderId: string): Promise<ServiceOrderNotificationContext> {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      include: {
        client: true,
        quotation: {
          include: {
            items: {
              orderBy: {
                createdAt: 'asc',
              },
            },
          },
        },
        createdBy: {
          select: {
            id: true,
            nombreCompleto: true,
            telefono: true,
            numeroFlota: true,
            blocked: true,
          },
        },
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
            telefono: true,
            numeroFlota: true,
            blocked: true,
          },
        },
        reports: {
          orderBy: {
            createdAt: 'asc',
          },
        },
        evidences: {
          orderBy: {
            createdAt: 'asc',
          },
        },
      },
    });

    if (!order) {
      throw new NotFoundException('Orden de servicio no encontrada');
    }

    return order;
  }

  private requiresAssistantInvoiceFlow(serviceType: ServiceOrderType) {
    return serviceType === ServiceOrderType.INSTALACION || serviceType === ServiceOrderType.MANTENIMIENTO;
  }

  private orderDetails(order: ServiceOrderNotificationContext) {
    return [order.technicalNote?.trim(), order.extraRequirements?.trim()]
      .filter((item): item is string => !!item)
      .join(' | ') || 'Sin detalles adicionales';
  }

  private customerComments(order: ServiceOrderNotificationContext) {
    return order.reports
      .filter((report) => report.type === 'REQUERIMIENTO_CLIENTE' || report.type === 'OTROS')
      .map((report) => report.report.trim())
      .filter((report) => report.length > 0)
      .join(' | ');
  }

  private formatServiceLabel(order: ServiceOrderNotificationContext) {
    return `${order.serviceType.toLowerCase()} / ${order.category.toLowerCase()}`;
  }

  private mapsLink(order: ServiceOrderNotificationContext) {
    if (order.client.locationUrl?.trim()) {
      return order.client.locationUrl.trim();
    }

    const lat = this.toNullableNumber(order.client.latitude);
    const lng = this.toNullableNumber(order.client.longitude);
    if (lat == null || lng == null) {
      return 'Ubicación no registrada';
    }

    return `https://maps.google.com/?q=${lat},${lng}`;
  }

  private resolveTechNotifyMinutesBefore() {
    const raw = (process.env.SERVICE_ORDER_TECH_NOTIFY_MINUTES_BEFORE ?? '').trim();
    const parsed = Number(raw);
    if (Number.isFinite(parsed) && parsed > 0) {
      return Math.floor(parsed);
    }
    return ServiceOrderNotificationsListener.DEFAULT_TECH_NOTIFY_MINUTES_BEFORE;
  }

  private formatQuotationTotal(order: ServiceOrderNotificationContext) {
    if (!order.quotation?.total) {
      return null;
    }

    const value = this.toNullableNumber(order.quotation.total);
    if (value == null) {
      return null;
    }

    return new Intl.NumberFormat('es-DO', {
      style: 'currency',
      currency: 'DOP',
      maximumFractionDigits: 2,
    }).format(value);
  }

  private buildEvidenceSummary(order: ServiceOrderNotificationContext) {
    const reportsCount = order.reports.length;
    const imagesCount = order.evidences.filter((item) => item.type.includes('IMAGEN')).length;
    const videosCount = order.evidences.filter((item) => item.type.includes('VIDEO')).length;
    return `reportes/texto=${reportsCount}, imágenes=${imagesCount}, videos=${videosCount}`;
  }

  private async resolveActorDisplayName(actorUserId?: string | null) {
    const actorId = (actorUserId ?? '').trim();
    if (!actorId) {
      return 'No identificado';
    }

    const actor = await this.prisma.user.findUnique({
      where: { id: actorId },
      select: { nombreCompleto: true },
    });
    const actorName = (actor?.nombreCompleto ?? '').trim();
    return actorName || actorId;
  }

  private buildEventDedupeKey(params: {
    orderId: string;
    eventType: ServiceOrderNotificationEventType;
    recipientUserId?: string | null;
    toNumber: string;
  }) {
    const normalized = this.notifications.normalizeWhatsAppNumber(params.toNumber);
    const recipientRef = (params.recipientUserId ?? '').trim() || normalized || 'no-recipient';
    return `service-order:event:${params.eventType}:${params.orderId}:${recipientRef}`;
  }

  private buildCreatedOrderMessage(order: ServiceOrderNotificationContext) {
    const scheduledLabel = order.scheduledFor
      ? order.scheduledFor.toLocaleString('es-DO')
      : 'Sin fecha programada';
    const creatorName = order.createdBy.nombreCompleto.trim() || 'Sin creador';
    const reference = [order.extraRequirements?.trim(), order.technicalNote?.trim()]
      .filter((item): item is string => !!item)
      .join(' | ');

    return [
      '*FULLTECH - Orden de servicio*',
      'Nueva orden de servicio',
      `Cliente: ${order.client.nombre}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Fecha/Hora programada: ${scheduledLabel}`,
      `Dirección/Ubicación: ${this.mapsLink(order)}`,
      `Creada por: ${creatorName}`,
      reference ? `Observación/Referencia: ${reference}` : null,
      'Acción requerida: revisa la orden en la app de Operaciones.',
    ]
      .filter(Boolean)
      .join('\n');
  }

  private async resolveTechnicianRecipients(order: ServiceOrderNotificationContext) {
    const assignedId = (order.assignedToId ?? '').trim();
    if (assignedId) {
      const assigned = await this.getRoleRecipients(Role.TECNICO, {
        fleetOnly: true,
        fallbackToPhone: true,
      });
      const filtered = assigned.filter((item) => item.userId === assignedId);
      if (!filtered.length) {
        this.logger.warn(`Assigned technician has no valid phone order=${order.id} assignedTo=${assignedId}`);
      }
      return filtered;
    }

    return this.getRoleRecipients(Role.TECNICO, {
      fleetOnly: true,
      fallbackToPhone: true,
    });
  }

  private async enqueueTechnicianCreatedNotification(
    order: ServiceOrderNotificationContext,
    params: {
      recipientUserId: string;
      recipientName: string;
      toNumber: string;
      messageText: string;
    },
  ) {
    const eventType = ServiceOrderNotificationsListener.CREATED_TECH_EVENT;
    const dedupeKey = this.buildEventDedupeKey({
      orderId: order.id,
      eventType,
      recipientUserId: params.recipientUserId,
      toNumber: params.toNumber,
    });

    await this.notifications.enqueueWhatsAppRawText({
      toNumber: params.toNumber,
      messageText: params.messageText,
      dedupeKey,
      senderUserId: params.recipientUserId,
      payload: {
        kind: eventType,
        eventType,
        orderId: order.id,
        recipientUserId: params.recipientUserId,
        recipientName: params.recipientName,
        requirePersonalInstance: false,
      },
    });
  }

  private async enqueueCompanyEventNotification(
    order: ServiceOrderNotificationContext,
    params: {
      eventType: ServiceOrderNotificationEventType;
      recipientUserId?: string | null;
      toNumber: string;
      messageText: string;
      payload?: Record<string, unknown>;
    },
  ) {
    const dedupeKey = this.buildEventDedupeKey({
      orderId: order.id,
      eventType: params.eventType,
      recipientUserId: params.recipientUserId,
      toNumber: params.toNumber,
    });

    await this.enqueueOrderWhatsAppRawText(order, {
      toNumber: params.toNumber,
      messageText: params.messageText,
      dedupeKey,
      payload: {
        kind: params.eventType,
        eventType: params.eventType,
        orderId: order.id,
        recipientUserId: params.recipientUserId ?? null,
        ...(params.payload ?? {}),
      },
    });
  }

  private async notifyCreatedOrderNow(orderId: string) {
    const order = await this.loadContext(orderId);
    if (
      order.status === ServiceOrderStatus.CANCELADO ||
      order.status === ServiceOrderStatus.FINALIZADO ||
      order.status === ServiceOrderStatus.POSPUESTA ||
      order.technicianConfirmedById
    ) {
      return;
    }

    const recipients = await this.resolveTechnicianRecipients(order);
    if (!recipients.length) {
      this.logger.warn(`No technician recipients found for immediate created-order notification order=${order.id}`);
      return;
    }

    const message = this.buildCreatedOrderMessage(order);
    for (const recipient of recipients) {
      for (const number of recipient.numbers) {
        await this.enqueueTechnicianCreatedNotification(order, {
          recipientUserId: recipient.userId,
          recipientName: recipient.name,
          toNumber: number,
          messageText: message,
        });
      }
    }
  }

  private toNullableNumber(value: Prisma.Decimal | number | string | null | undefined) {
    if (value == null) return null;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  private collectCreatorRecipients(order: ServiceOrderNotificationContext) {
    const values = [order.createdBy.numeroFlota, order.createdBy.telefono]
      .map((item) => (item ?? '').trim())
      .filter((item) => item.length > 0);
    return [...new Set(values)];
  }

  private async enqueueOrderWhatsAppRawText(
    order: ServiceOrderNotificationContext,
    params: Parameters<NotificationsService['enqueueWhatsAppRawText']>[0],
  ) {
    // Use the company instance (no senderUserId) so all order notifications
    // are sent from the company's WhatsApp, not from the individual creator.
    const { senderUserId: _ignored, ...rest } = params as typeof params & { senderUserId?: unknown };
    void _ignored;
    await this.notifications.enqueueWhatsAppRawText({ ...rest });
  }

  private async enqueueOrderWhatsAppDocument(
    order: ServiceOrderNotificationContext,
    params: Parameters<NotificationsService['enqueueWhatsAppDocument']>[0],
  ) {
    // Use the company instance — same rationale as enqueueOrderWhatsAppRawText.
    const { senderUserId: _ignored, ...rest } = params as typeof params & { senderUserId?: unknown };
    void _ignored;
    await this.notifications.enqueueWhatsAppDocument({ ...rest });
  }

  private async resolveOrderSenderUserId(orderId: string) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      select: {
        createdBy: {
          select: { id: true },
        },
      },
    });
    return order?.createdBy?.id ?? null;
  }

  private async resolveInProgressReminderRecipient(actorUserId: string) {
    const actor = await this.prisma.user.findUnique({
      where: { id: actorUserId },
      select: {
        id: true,
        nombreCompleto: true,
        numeroFlota: true,
        blocked: true,
      },
    });

    if (!actor) {
      this.logger.warn(`Actor user not found for in-progress reminder user=${actorUserId}`);
      return null;
    }

    if (actor.blocked) {
      this.logger.warn(`Blocked actor user skipped for in-progress reminder user=${actorUserId}`);
      return null;
    }

    const number = (actor.numeroFlota ?? '').trim();
    if (!number) {
      this.logger.warn(`Actor user has no fleet number for in-progress reminder user=${actorUserId}`);
      return null;
    }

    return {
      userId: actor.id,
      name: actor.nombreCompleto,
      number,
    } satisfies InProgressReminderRecipient;
  }

  private async enqueueInProgressReminder(
    orderId: string,
    recipient: InProgressReminderRecipient,
    kind: (typeof ServiceOrderNotificationsListener.IN_PROGRESS_REMINDER_KINDS)[number],
    sequenceAt: Date,
  ) {
    // No senderUserId → uses company WhatsApp instance.
    await this.notifications.enqueueWhatsAppRawText({
      toNumber: recipient.number,
      messageText: ServiceOrderNotificationsListener.IN_PROGRESS_REMINDER_MESSAGE,
      dedupeKey: `service-order:in-progress:${kind}:${orderId}:${recipient.userId}:${sequenceAt.toISOString()}`,
      payload: {
        kind,
        orderId,
        actorUserId: recipient.userId,
      },
    });
  }

  private extractActorUserId(payload: Prisma.JsonValue | null) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return null;
    }

    const raw = (payload as Record<string, unknown>).actorUserId;
    return typeof raw === 'string' && raw.trim().length > 0 ? raw.trim() : null;
  }

  private extractScheduledFor(payload: Prisma.JsonValue | null) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return null;
    }
    const raw = (payload as Record<string, unknown>).scheduledFor;
    return typeof raw === 'string' && raw.trim().length > 0 ? raw.trim() : null;
  }

  private extractAssignedToUserId(payload: Prisma.JsonValue | null) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return null;
    }
    const raw = (payload as Record<string, unknown>).assignedToId;
    return typeof raw === 'string' && raw.trim().length > 0 ? raw.trim() : null;
  }

  private async cancelPendingReminderJobs(orderId: string, reason: string) {
    await this.prisma.serviceOrderNotificationJob.updateMany({
      where: {
        orderId,
        kind: 'THIRTY_MINUTES_BEFORE',
        status: { in: ['PENDING', 'PROCESSING'] },
      },
      data: {
        status: 'CANCELLED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async cancelPendingTechnicianReminderJobs(orderId: string, reason: string) {
    await this.prisma.serviceOrderNotificationJob.updateMany({
      where: {
        orderId,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: { in: ['PENDING', 'PROCESSING'] },
      },
      data: {
        status: 'CANCELLED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async cancelPendingTechnicianReminderOutbox(orderId: string, reason: string) {
    await this.prisma.notificationOutbox.updateMany({
      where: {
        status: { in: [NotificationStatus.PENDING, NotificationStatus.SENDING] },
        payload: {
          path: ['orderId'],
          equals: orderId,
        },
        OR: ServiceOrderNotificationsListener.TECHNICIAN_REMINDER_KINDS.map((kind) => ({
          payload: {
            path: ['kind'],
            equals: kind,
          },
        })),
      },
      data: {
        status: 'FAILED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async cancelPendingInProgressReminderOutbox(orderId: string, reason: string) {
    await this.prisma.notificationOutbox.updateMany({
      where: {
        status: { in: [NotificationStatus.PENDING, NotificationStatus.SENDING] },
        payload: {
          path: ['orderId'],
          equals: orderId,
        },
        OR: ServiceOrderNotificationsListener.IN_PROGRESS_REMINDER_KINDS.map((kind) => ({
          payload: {
            path: ['kind'],
            equals: kind,
          },
        })),
      },
      data: {
        status: 'FAILED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async findLatestInProgressReminderEvent(orderId: string) {
    return this.prisma.notificationOutbox.findFirst({
      where: {
        payload: {
          path: ['orderId'],
          equals: orderId,
        },
        OR: ServiceOrderNotificationsListener.IN_PROGRESS_REMINDER_KINDS.map((kind) => ({
          payload: {
            path: ['kind'],
            equals: kind,
          },
        })),
      },
      orderBy: [{ createdAt: 'desc' }],
      select: {
        createdAt: true,
        sentAt: true,
        payload: true,
      },
    });
  }

  private shouldNotifyTechniciansForPending(
    order: {
      status: ServiceOrderStatus;
      scheduledFor: Date | null;
      technicianConfirmedById?: string | null;
    },
    referenceDate: Date = new Date(),
  ) {
    if (order.status !== ServiceOrderStatus.PENDIENTE || order.technicianConfirmedById) {
      return false;
    }

    if (!order.scheduledFor) {
      return true;
    }

    return isSameDominicanDay(order.scheduledFor, referenceDate);
  }

  private async computeNextPendingTechnicianReminderRunAt(orderId: string, fromDate: Date = new Date()) {
    const latestReminder = await this.prisma.notificationOutbox.findFirst({
      where: {
        status: {
          in: [NotificationStatus.PENDING, NotificationStatus.SENDING, NotificationStatus.SENT],
        },
        payload: {
          path: ['orderId'],
          equals: orderId,
        },
        OR: ServiceOrderNotificationsListener.TECHNICIAN_REMINDER_KINDS.map((kind) => ({
          payload: {
            path: ['kind'],
            equals: kind,
          },
        })),
      },
      orderBy: [{ createdAt: 'desc' }],
      select: {
        createdAt: true,
        sentAt: true,
      },
    });

    const latestAt = latestReminder?.sentAt ?? latestReminder?.createdAt ?? null;
    const minRunAt = latestAt
      ? new Date(
          latestAt.getTime() +
            ServiceOrderNotificationsListener.PENDING_TECHNICIAN_REMINDER_INTERVAL_MINUTES * 60_000,
        )
      : fromDate;

    return alignToNotificationBusinessHours(
      minRunAt.getTime() > fromDate.getTime() ? minRunAt : fromDate,
    );
  }

  private async hasOpenPendingTechnicianReminderJob(orderId: string) {
    const count = await this.prisma.serviceOrderNotificationJob.count({
      where: {
        orderId,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: { in: ['PENDING', 'PROCESSING'] },
      },
    });

    return count > 0;
  }

  private async schedulePendingTechnicianFollowUp(orderId: string, scheduledFor: Date | null) {
    const runAt = await this.computeNextPendingTechnicianReminderRunAt(orderId);
    const order = {
      status: ServiceOrderStatus.PENDIENTE,
      scheduledFor,
      technicianConfirmedById: null,
    };

    if (!this.shouldNotifyTechniciansForPending(order, runAt)) {
      return;
    }

    const dedupeKey = `service-order:job:1h-pending:${orderId}:run-${runAt.toISOString()}`;

    await this.prisma.serviceOrderNotificationJob.create({
      data: {
        orderId,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: 'PENDING',
        dedupeKey,
        runAt,
        payload: {
          scheduledFor: scheduledFor?.toISOString() ?? null,
          source: 'scheduled-reminder-follow-up',
        },
      },
    }).catch(async (error: unknown) => {
      const code = typeof error === 'object' && error && 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
      if (code === 'P2002') {
        await this.prisma.serviceOrderNotificationJob.update({
          where: { dedupeKey },
          data: {
            status: 'PENDING',
            runAt,
            attempts: 0,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            completedAt: null,
          },
        });
        return;
      }
      throw error;
    });
  }

  private buildTechnicianReminderMessage(message: string, sequence: number) {
    const lines = [`*Aviso #${sequence}*`, message];
    if (sequence > 1) {
      lines.push(
        'Este aviso sigue llegando porque la orden todavia no ha sido marcada como confirmada.',
      );
    }

    return lines.join('\n');
  }

  private async countTechnicianRemindersForRecipient(orderId: string, rawNumber: string) {
    const normalized = this.notifications.normalizeWhatsAppNumber(rawNumber);
    if (!normalized) {
      return ServiceOrderNotificationsListener.MAX_TECHNICIAN_REMINDERS_PER_RECIPIENT;
    }

    return this.prisma.notificationOutbox.count({
      where: {
        status: {
          in: [NotificationStatus.PENDING, NotificationStatus.SENDING, NotificationStatus.SENT],
        },
        toNumberNormalized: normalized,
        payload: {
          path: ['orderId'],
          equals: orderId,
        },
        OR: ServiceOrderNotificationsListener.TECHNICIAN_REMINDER_KINDS.map((kind) => ({
          payload: {
            path: ['kind'],
            equals: kind,
          },
        })),
      },
    });
  }

  private async getNextTechnicianReminderSequence(orderId: string, rawNumber: string) {
    const count = await this.countTechnicianRemindersForRecipient(orderId, rawNumber);
    if (count >= ServiceOrderNotificationsListener.MAX_TECHNICIAN_REMINDERS_PER_RECIPIENT) {
      return null;
    }

    return count + 1;
  }

  private async markJobCancelled(jobId: string, reason: string) {
    await this.prisma.serviceOrderNotificationJob.update({
      where: { id: jobId },
      data: {
        status: 'CANCELLED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async getRoleRecipients(
    role: Role,
    options: { fleetOnly: boolean; fallbackToPhone: boolean },
  ): Promise<InternalRecipient[]> {
    const users = await this.prisma.user.findMany({
      where: {
        role,
        blocked: false,
      },
      select: {
        id: true,
        nombreCompleto: true,
        telefono: true,
        numeroFlota: true,
      },
      orderBy: {
        nombreCompleto: 'asc',
      },
    });

    return users
      .map((user) => {
        const numbers = new Set<string>();
        const fleet = (user.numeroFlota ?? '').trim();
        const phone = (user.telefono ?? '').trim();

        if (options.fleetOnly) {
          if (fleet) {
            numbers.add(fleet);
          } else if (options.fallbackToPhone && phone) {
            numbers.add(phone);
          }
        } else {
          if (fleet) numbers.add(fleet);
          if (phone) numbers.add(phone);
        }

        return {
          userId: user.id,
          name: user.nombreCompleto,
          numbers: [...numbers],
        };
      })
      .filter((user) => {
        if (user.numbers.length > 0) {
          return true;
        }
        this.logger.warn(
          `Skipping ${role} user without valid phone numbers userId=${user.userId}`,
        );
        return false;
      });
  }
}
