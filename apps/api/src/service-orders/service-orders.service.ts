import { randomUUID } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  Prisma,
  Role,
  ServiceOrderStatus as PrismaServiceOrderStatus,
  ServiceOrderType as PrismaServiceOrderType,
  type Client,
} from '@prisma/client';
import { RedisService } from '../common/redis/redis.service';
import { PayrollService } from '../payroll/payroll.service';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import { ServiceOrderNotificationsListener } from '../notifications/service-order-notifications.listener';
import { CloneServiceOrderDto } from './dto/clone-service-order.dto';
import { CreateEvidenceDto } from './dto/create-evidence.dto';
import { CreateReportDto } from './dto/create-report.dto';
import { CreateServiceOrderDto } from './dto/create-service-order.dto';
import { ListServiceOrdersQueryDto } from './dto/list-service-orders-query.dto';
import { ListServiceOrderCommissionsQueryDto } from './dto/list-service-order-commissions-query.dto';
import { UpdateServiceOrderDto } from './dto/update-service-order.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import {
  ApiServiceEvidenceType,
  ApiServiceOrderCategory,
  ApiServiceOrderStatus,
  ApiServiceOrderType,
  ApiServiceReportType,
  SERVICE_EVIDENCE_TYPE_FROM_DB,
  SERVICE_EVIDENCE_TYPE_TO_DB,
  SERVICE_ORDER_ALLOWED_STATUS_TRANSITIONS,
  SERVICE_ORDER_CATEGORY_FROM_DB,
  SERVICE_ORDER_CATEGORY_TO_DB,
  SERVICE_REPORT_TYPE_FROM_DB,
  SERVICE_REPORT_TYPE_TO_DB,
  SERVICE_ORDER_STATUS_FROM_DB,
  SERVICE_ORDER_STATUS_TO_DB,
  SERVICE_ORDER_TYPE_FROM_DB,
  SERVICE_ORDER_TYPE_TO_DB,
} from './service-orders.constants';

type AuthUser = { id: string; role: Role };

type ServiceOrderWithRelations = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    statusHistory: {
      orderBy: { changedAt: 'desc' };
      include: {
        changedBy: {
          select: {
            id: true;
            nombreCompleto: true;
            role: true;
          };
        };
      };
    };
    evidences: { orderBy: { createdAt: 'asc' } };
    reports: { orderBy: { createdAt: 'asc' } };
  };
}>;

type ServiceOrderWithClient = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    statusHistory: {
      orderBy: { changedAt: 'desc' };
      include: {
        changedBy: {
          select: {
            id: true;
            nombreCompleto: true;
            role: true;
          };
        };
      };
    };
  };
}>;

type ServiceOrderRecord = Prisma.ServiceOrderGetPayload<object>;

type ServiceSalesOrderWithRelations = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    assignedTo: {
      select: {
        id: true;
        nombreCompleto: true;
        email: true;
      };
    };
    createdBy: {
      select: {
        id: true;
        nombreCompleto: true;
        role: true;
      };
    };
    quotation: {
      include: {
        items: {
          orderBy: {
            createdAt: 'asc';
          };
        };
      };
    };
  };
}>;

type ServiceCommissionOrder = Prisma.ServiceOrderGetPayload<{
  include: {
    client: {
      select: {
        id: true;
        nombre: true;
      };
    };
    quotation: {
      select: {
        id: true;
        total: true;
        totalProfit: true;
      };
    };
    assignedTo: {
      select: {
        id: true;
        nombreCompleto: true;
      };
    };
    createdBy: {
      select: {
        id: true;
        nombreCompleto: true;
        role: true;
      };
    };
  };
}>;

type CommissionPeriodKey = 'current' | 'previous';

type CommissionPeriodRange = {
  key: CommissionPeriodKey;
  kind: 'bridged' | 'mid_month';
  from: Date;
  to: Date;
};

@Injectable()
export class ServiceOrdersService {
  private readonly logger = new Logger(ServiceOrdersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly payroll: PayrollService,
    private readonly orderNotifications: ServiceOrderNotificationsListener,
  ) {}

  async create(user: AuthUser, dto: CreateServiceOrderDto) {
    const payload = await this.buildCreatePayload(user, dto);

    try {
      const created = await this.prisma.$transaction(async (tx) => {
        const createdOrder = await tx.serviceOrder.create({
          data: payload,
          include: {
            client: true,
            statusHistory: {
              orderBy: { changedAt: 'desc' },
              include: {
                changedBy: {
                  select: {
                    id: true,
                    nombreCompleto: true,
                    role: true,
                  },
                },
              },
            },
          },
        });

        const actorName = await this.resolveStatusActorName(tx, createdOrder.lastStatusChangedByUserId);

        await tx.serviceOrderStatusHistory.create({
          data: {
            serviceOrderId: createdOrder.id,
            previousStatus: null,
            nextStatus: createdOrder.status,
            changedAt: createdOrder.lastStatusChangedAt,
            changedByUserId: createdOrder.lastStatusChangedByUserId,
            changedByUserName: actorName,
            note: 'Estado inicial',
          },
        });

        return tx.serviceOrder.findUniqueOrThrow({
          where: { id: createdOrder.id },
          include: {
            client: true,
            statusHistory: {
              orderBy: { changedAt: 'desc' },
              include: {
                changedBy: {
                  select: {
                    id: true,
                    nombreCompleto: true,
                    role: true,
                  },
                },
              },
            },
          },
        });
      });
      const mapped = this.mapOrder(created);
      await this.invalidateCachesForOrder(created.id);
      this.emitOrderEvent('service.created', created.id, mapped);
      await this.runNotificationHook(`service.created:${created.id}`, () =>
        this.orderNotifications.handleOrderCreated(created.id),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async list(user: AuthUser, query: ListServiceOrdersQueryDto = {}) {
    const normalizedStatuses = this.parseRequestedStatuses(query.statuses);
    const cacheKey = this.buildListCacheKey(user, {
      statuses: normalizedStatuses ?? undefined,
      from: query.from,
      to: query.to,
    });
    const cached = await this.redis.get<{ items: unknown[] }>(cacheKey);
    if (Array.isArray(cached?.items)) {
      return cached;
    }

    const where = this.buildListWhere(query, normalizedStatuses);
    const items = await this.prisma.serviceOrder.findMany({
      where,
      include: {
        client: true,
        statusHistory: {
          orderBy: { changedAt: 'desc' },
          include: {
            changedBy: {
              select: {
                id: true,
                nombreCompleto: true,
                role: true,
              },
            },
          },
        },
      },
      orderBy: [{ lastStatusChangedAt: 'desc' }, { createdAt: 'desc' }],
    });
    const response = { items: items.map((item) => this.mapOrder(item)) };
    await this.redis.set(cacheKey, response, 30);
    return response;
  }

  async findOne(user: AuthUser, id: string) {
    const cacheKey = this.buildDetailCacheKey(user, id);
    const cached = await this.redis.get<Record<string, unknown>>(cacheKey);
    if (cached) {
      return cached;
    }

    const item = await this.findOrderWithRelationsOrThrow(user, id);
    const response = this.mapOrder(item);
    await this.redis.set(cacheKey, response, 30);
    return response;
  }

  async salesSummary(user: AuthUser, from?: string, to?: string) {
    const where: Prisma.ServiceOrderWhereInput = {
      createdById: user.id,
      status: PrismaServiceOrderStatus.FINALIZADO,
      serviceType: {
        in: [
          PrismaServiceOrderType.INSTALACION,
          PrismaServiceOrderType.MANTENIMIENTO,
        ],
      },
      ...this.buildFinalizedAtRange(from, to),
    };

    const orders = await this.prisma.serviceOrder.findMany({
      where,
      orderBy: { finalizedAt: 'desc' },
      include: {
        client: true,
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
            email: true,
          },
        },
        createdBy: {
          select: {
            id: true,
            nombreCompleto: true,
            role: true,
          },
        },
        quotation: {
          include: {
            items: {
              orderBy: { createdAt: 'asc' },
            },
          },
        },
      },
    });

    const items: Array<Record<string, unknown>> = [];
    const skipped: Array<Record<string, unknown>> = [];
    const totals = {
      totalOrders: orders.length,
      eligibleOrders: 0,
      skippedOrders: 0,
      totalQuoted: 0,
      totalCost: 0,
      totalProfit: 0,
      totalOperationalExpense: 0,
      totalProfitAfterExpense: 0,
      totalSellerCommission: 0,
      totalTechnicianCommission: 0,
    };

    for (const order of orders) {
      const evaluated = this.evaluateServiceSalesOrder(order);
      if ('reason' in evaluated) {
        skipped.push(evaluated);
        continue;
      }

      items.push(evaluated);
      totals.eligibleOrders += 1;
      totals.totalQuoted += this.toNumber(evaluated.totalQuoted);
      totals.totalCost += this.toNumber(evaluated.totalCost);
      totals.totalProfit += this.toNumber(evaluated.totalProfit);
      totals.totalOperationalExpense += this.toNumber(evaluated.operationalExpenseAmount);
      totals.totalProfitAfterExpense += this.toNumber(evaluated.profitAfterExpense);
      totals.totalSellerCommission += this.toNumber(evaluated.sellerCommissionAmount);
      totals.totalTechnicianCommission += this.toNumber(evaluated.technicianCommissionAmount);
    }

    totals.skippedOrders = skipped.length;

    return {
      from: from?.trim() || null,
      to: to?.trim() || null,
      items,
      skipped,
      ...totals,
    };
  }

  async listCommissions(
    user: AuthUser,
    query: ListServiceOrderCommissionsQueryDto,
  ) {
    const periodKey: CommissionPeriodKey = query.period === 'previous' ? 'previous' : 'current';
    const page = Math.max(1, query.page ?? 1);
    const pageSize = Math.min(100, Math.max(1, query.pageSize ?? 25));
    const period = this.resolveCommissionPeriod(periodKey, new Date());
    const where = this.buildCommissionWhere(user, period);

    const [totalItems, summaryOrders, orders] = await this.prisma.$transaction([
      this.prisma.serviceOrder.count({ where }),
      this.prisma.serviceOrder.findMany({
        where,
        orderBy: [{ finalizedAt: 'desc' }, { createdAt: 'desc' }],
        include: {
          client: {
            select: {
              id: true,
              nombre: true,
            },
          },
          quotation: {
            select: {
              id: true,
              total: true,
              totalProfit: true,
            },
          },
          assignedTo: {
            select: {
              id: true,
              nombreCompleto: true,
            },
          },
          createdBy: {
            select: {
              id: true,
              nombreCompleto: true,
              role: true,
            },
          },
        },
      }),
      this.prisma.serviceOrder.findMany({
        where,
        orderBy: [{ finalizedAt: 'desc' }, { createdAt: 'desc' }],
        skip: (page - 1) * pageSize,
        take: pageSize,
        include: {
          client: {
            select: {
              id: true,
              nombre: true,
            },
          },
          quotation: {
            select: {
              id: true,
              total: true,
              totalProfit: true,
            },
          },
          assignedTo: {
            select: {
              id: true,
              nombreCompleto: true,
            },
          },
          createdBy: {
            select: {
              id: true,
              nombreCompleto: true,
              role: true,
            },
          },
        },
      }),
    ]);

    const summary = this.buildCommissionSummary(summaryOrders, user.role);
    const items = orders.map((order) => this.mapCommissionOrder(order, user.role));
    const totalPages = totalItems == 0 ? 1 : Math.ceil(totalItems / pageSize);

    return {
      period: period.key,
      range: {
        from: this.toDateOnly(period.from),
        to: this.toDateOnly(period.to),
        label: this.buildCommissionRangeLabel(period),
      },
      summary,
      pagination: {
        page,
        pageSize,
        totalItems,
        totalPages,
        hasMore: page < totalPages,
      },
      items,
    };
  }

  async adminCommissionSummaryByUser(
    from?: string,
    to?: string,
    userId?: string,
  ) {
    const where = this.buildAdminCommissionWhere(from, to);
    const orders = await this.prisma.serviceOrder.findMany({
      where,
      orderBy: [{ finalizedAt: 'desc' }, { createdAt: 'desc' }],
      include: {
        client: {
          select: {
            id: true,
            nombre: true,
          },
        },
        quotation: {
          select: {
            id: true,
            total: true,
            totalProfit: true,
          },
        },
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
        createdBy: {
          select: {
            id: true,
            nombreCompleto: true,
            email: true,
            role: true,
          },
        },
      },
    });

    const grouped = new Map<
      string,
      {
        userId: string;
        userName: string;
        userEmail: string;
        totalServices: number;
        installationCount: number;
        maintenanceCount: number;
        totalSold: number;
        totalPoints: number;
      }
    >();

    for (const order of orders) {
      const commission = this.computeCommissionAmounts(order);
      const recipientUserId = commission.recipientUserId?.trim() || order.createdById;
      if (userId?.trim() && recipientUserId !== userId.trim()) {
        continue;
      }

      const existing = grouped.get(recipientUserId) ?? {
        userId: recipientUserId,
        userName: '',
        userEmail: '',
        totalServices: 0,
        installationCount: 0,
        maintenanceCount: 0,
        totalSold: 0,
        totalPoints: 0,
      };

      const recipientUser =
        order.assignedToId != null && order.assignedToId === recipientUserId
          ? order.assignedTo
          : order.createdBy;

      existing.userName = recipientUser?.nombreCompleto?.trim() || existing.userName || 'Usuario';
      existing.totalServices += 1;
      existing.totalSold += commission.totalAmount;
      existing.totalPoints += commission.totalCommissionAmount;
      if (order.serviceType === PrismaServiceOrderType.INSTALACION) {
        existing.installationCount += 1;
      }
      if (order.serviceType === PrismaServiceOrderType.MANTENIMIENTO) {
        existing.maintenanceCount += 1;
      }

      grouped.set(recipientUserId, existing);
    }

    const items = Array.from(grouped.values()).sort((left, right) => {
      const pointsOrder = right.totalPoints - left.totalPoints;
      if (pointsOrder != 0) return pointsOrder;
      return right.totalServices - left.totalServices;
    });

    const totals = items.reduce(
      (acc, row) => {
        acc.totalServices += row.totalServices;
        acc.totalSold += row.totalSold;
        acc.totalPoints += row.totalPoints;
        acc.totalInstallations += row.installationCount;
        acc.totalMaintenances += row.maintenanceCount;
        return acc;
      },
      {
        totalServices: 0,
        totalSold: 0,
        totalPoints: 0,
        totalInstallations: 0,
        totalMaintenances: 0,
      },
    );

    return { items, totals };
  }

  async adminListCommissionsByUser(
    userId?: string,
    from?: string,
    to?: string,
  ) {
    const where = this.buildAdminCommissionWhere(from, to);
    const orders = await this.prisma.serviceOrder.findMany({
      where,
      orderBy: [{ finalizedAt: 'desc' }, { createdAt: 'desc' }],
      include: {
        client: {
          select: {
            id: true,
            nombre: true,
          },
        },
        quotation: {
          select: {
            id: true,
            total: true,
            totalProfit: true,
          },
        },
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
        createdBy: {
          select: {
            id: true,
            nombreCompleto: true,
            role: true,
          },
        },
      },
    });

    const targetUserId = userId?.trim();
    return orders
      .map((order) => this.mapCommissionOrder(order, Role.ADMIN))
      .filter((order) => {
        if (!targetUserId) return true;
        return order.commissionRecipientUserId === targetUserId;
      });
  }

  async update(user: AuthUser, id: string, dto: UpdateServiceOrderDto) {
    const current = await this.findOrderOrThrow(user, id);
    if (user.role === Role.TECNICO) {
      return this.updateAsTechnician(user, current, dto);
    }

    this.assertCanFullyEditOrder(user, current);

    const clientId = this.cleanOptionalText(dto.clientId, dto.client_id) ?? current.clientId;
    const quotationId = this.cleanOptionalText(dto.quotationId, dto.quotation_id) ?? current.quotationId;
    const category = this.cleanOptionalText(dto.category) as ApiServiceOrderCategory | null;
    const serviceType = this.cleanOptionalText(dto.serviceType, dto.service_type) as ApiServiceOrderType | null;
    const technicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note);
    const extraRequirements = this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements);
    const scheduledFor = this.hasScheduledForInput(dto)
      ? this.parseScheduledDateAlias(dto, 'scheduled_for')
      : current.scheduledFor;
    const assignedToId = this.hasAssignedToInput(dto)
      ? await this.resolveAssignedToId(dto.assignedToId, dto.assigned_to)
      : current.assignedToId;

    await this.assertClientExists(clientId);
    await this.assertQuotationMatchesClient(quotationId, clientId);
    if (current.status !== PrismaServiceOrderStatus.FINALIZADO && clientId !== current.clientId) {
      await this.assertClientHasNoOpenOrder(clientId, current.id);
    }

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id },
        include: { client: true },
        data: {
          clientId,
          quotationId,
          category: category
            ? SERVICE_ORDER_CATEGORY_TO_DB[category]
            : current.category,
          serviceType: serviceType
            ? SERVICE_ORDER_TYPE_TO_DB[serviceType]
            : current.serviceType,
          scheduledFor,
          technicalNote: this.hasTextInput(dto, 'technicalNote', 'technical_note')
            ? technicalNote
            : current.technicalNote,
          extraRequirements: this.hasTextInput(dto, 'extraRequirements', 'extra_requirements')
            ? extraRequirements
            : current.extraRequirements,
          assignedToId,
        },
      });
      const mapped = this.mapOrder(updated);
      await this.invalidateCachesForOrder(updated.id);
      this.emitOrderEvent('service.updated', updated.id, mapped);
      await this.runNotificationHook(`service.updated:${updated.id}`, () =>
        this.orderNotifications.handleOrderUpdated(updated.id),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async updateStatus(user: AuthUser, id: string, dto: UpdateStatusDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanModifyOrder(user, item);

    const previousStatus = this.toApiStatus(item.status);
    const nextStatus = dto.status as ApiServiceOrderStatus;
    const nextScheduledFor = this.parseScheduledDateAlias(dto, 'scheduled_at');
    if (nextStatus === 'pospuesta') {
      this.assertCanPostponeOrder(user, item);
      this.assertScheduledDateInFuture(nextScheduledFor, 'scheduled_at');
    } else {
      this.assertCanChangeOrderStatus(user, item, nextStatus);
    }
    if (!this.canFinalizePendingDirectly(user, previousStatus, nextStatus)) {
      this.assertValidStatusTransition(previousStatus, nextStatus);
    }
    let resolvedAssignedToId = item.assignedToId;
    if (nextStatus === 'en_proceso' && user.role === Role.TECNICO) {
      if (item.assignedToId && item.assignedToId !== user.id) {
        throw new BadRequestException('Esta orden ya tiene un técnico asignado.');
      }
      resolvedAssignedToId = item.assignedToId ?? user.id;
    }
    if (nextStatus === 'finalizado' && user.role === Role.TECNICO) {
      resolvedAssignedToId = item.assignedToId ?? user.id;
    }
    const now = new Date();
    const statusNote = this.cleanOptionalText(dto.note);

    try {
      const updated = await this.prisma.$transaction(async (tx) => {
        const actorName = await this.resolveStatusActorName(tx, user.id);
        const changedOrder = await tx.serviceOrder.update({
          where: { id },
          include: {
            client: true,
            statusHistory: {
              orderBy: { changedAt: 'desc' },
              include: {
                changedBy: {
                  select: {
                    id: true,
                    nombreCompleto: true,
                    role: true,
                  },
                },
              },
            },
          },
          data: {
            status: SERVICE_ORDER_STATUS_TO_DB[nextStatus],
            scheduledFor: nextStatus === 'pospuesta' ? nextScheduledFor : item.scheduledFor,
            assignedToId: resolvedAssignedToId,
            finalizedAt: nextStatus === 'finalizado' ? now : item.finalizedAt,
            lastStatusChangedAt: now,
            lastStatusChangedByUserId: user.id,
          },
        });

        await tx.serviceOrderStatusHistory.create({
          data: {
            serviceOrderId: changedOrder.id,
            previousStatus: item.status,
            nextStatus: changedOrder.status,
            changedAt: now,
            changedByUserId: user.id,
            changedByUserName: actorName,
            note: statusNote,
          },
        });

        return tx.serviceOrder.findUniqueOrThrow({
          where: { id: changedOrder.id },
          include: {
            client: true,
            statusHistory: {
              orderBy: { changedAt: 'desc' },
              include: {
                changedBy: {
                  select: {
                    id: true,
                    nombreCompleto: true,
                    role: true,
                  },
                },
              },
            },
          },
        });
      });
      if (nextStatus === 'finalizado') {
        await this.queueServiceCommissionForPayroll(updated.id, user.id);
      }
      const mapped = this.mapOrder(updated);
      await this.invalidateCachesForOrder(updated.id);
      this.emitOrderEvent('service.status_changed', updated.id, mapped);
      await this.runNotificationHook(`service.status_changed:${updated.id}:${previousStatus}->${nextStatus}`, () =>
        this.orderNotifications.handleStatusChanged(updated.id, previousStatus, nextStatus, {
          actorUserId: user.id,
          note: statusNote,
        }),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async restoreDuePostponedOrders() {
    const now = new Date();
    const dueOrders = await this.prisma.serviceOrder.findMany({
      where: {
        status: PrismaServiceOrderStatus.POSPUESTA,
        scheduledFor: {
          not: null,
          lte: now,
        },
      },
      select: { id: true },
      orderBy: [{ scheduledFor: 'asc' }, { createdAt: 'asc' }],
    });

    if (!dueOrders.length) {
      return { processed: 0 };
    }

    let processed = 0;
    for (const dueOrder of dueOrders) {
      try {
        const now = new Date();
        const updated = await this.prisma.$transaction(async (tx) => {
          const current = await tx.serviceOrder.findUnique({
            where: { id: dueOrder.id },
            select: {
              id: true,
              status: true,
              createdById: true,
            },
          });

          if (!current) {
            throw new NotFoundException('Orden de servicio no encontrada');
          }

          const actorName = await this.resolveStatusActorName(tx, current.createdById);

          const changedOrder = await tx.serviceOrder.update({
            where: { id: dueOrder.id },
            include: {
              client: true,
              statusHistory: {
                orderBy: { changedAt: 'desc' },
                include: {
                  changedBy: {
                    select: {
                      id: true,
                      nombreCompleto: true,
                      role: true,
                    },
                  },
                },
              },
            },
            data: {
              status: PrismaServiceOrderStatus.PENDIENTE,
              lastStatusChangedAt: now,
              lastStatusChangedByUserId: current.createdById,
            },
          });

          await tx.serviceOrderStatusHistory.create({
            data: {
              serviceOrderId: changedOrder.id,
              previousStatus: current.status,
              nextStatus: PrismaServiceOrderStatus.PENDIENTE,
              changedAt: now,
              changedByUserId: current.createdById,
              changedByUserName: actorName,
              note: 'Restaurada automáticamente por vencimiento de fecha pospuesta',
            },
          });

          return tx.serviceOrder.findUniqueOrThrow({
            where: { id: changedOrder.id },
            include: {
              client: true,
              statusHistory: {
                orderBy: { changedAt: 'desc' },
                include: {
                  changedBy: {
                    select: {
                      id: true,
                      nombreCompleto: true,
                      role: true,
                    },
                  },
                },
              },
            },
          });
        });
        const mapped = this.mapOrder(updated);
        await this.invalidateCachesForOrder(updated.id);
        this.emitOrderEvent('service.status_changed', updated.id, mapped);
        await this.runNotificationHook(`service.status_changed:${updated.id}:pospuesta->pendiente`, () =>
          this.orderNotifications.handleStatusChanged(updated.id, 'pospuesta', 'pendiente'),
        );
        processed += 1;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        this.logger.error(`Failed to restore postponed service order ${dueOrder.id}: ${message}`);
      }
    }

    return { processed };
  }

  async addEvidence(user: AuthUser, id: string, dto: CreateEvidenceDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanModifyOrder(user, item);
    this.assertCanAddEvidenceType(user, dto.type as ApiServiceEvidenceType);

    const content = this.cleanRequiredText(dto.content, 'content');

    try {
      const created = await this.prisma.serviceEvidence.create({
        data: {
          serviceOrderId: item.id,
          type: SERVICE_EVIDENCE_TYPE_TO_DB[dto.type as ApiServiceEvidenceType],
          content,
          createdById: user.id,
        },
      });
      await this.invalidateCachesForOrder(item.id);
      const snapshot = await this.findOrderWithRelationsOrThrow(user, item.id);
      this.emitOrderEvent('service.updated', item.id, this.mapOrder(snapshot));
      return this.mapEvidence(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async addReport(user: AuthUser, id: string, dto: CreateReportDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanModifyOrder(user, item);
    this.assertTechnicalOutputAccess(user);

    const type = dto.type as ApiServiceReportType;
    const report = this.cleanRequiredText(dto.report, 'report');

    try {
      const created = await this.prisma.serviceReport.create({
        data: {
          serviceOrderId: item.id,
          type: SERVICE_REPORT_TYPE_TO_DB[type],
          report,
          createdById: user.id,
        },
      });
      await this.invalidateCachesForOrder(item.id);
      const snapshot = await this.findOrderWithRelationsOrThrow(user, item.id);
      this.emitOrderEvent('service.updated', item.id, this.mapOrder(snapshot));
      return this.mapReport(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async clone(user: AuthUser, id: string, dto: CloneServiceOrderDto) {
    const original = await this.findOrderOrThrow(user, id);

    const serviceType = this.requireAliasValue(dto.serviceType, dto.service_type, 'service_type');
    const clientId = this.cleanOptionalText(dto.clientId, dto.client_id) ?? original.clientId;
    const quotationId = this.cleanOptionalText(dto.quotationId, dto.quotation_id) ?? original.quotationId;
    const assignedToId = await this.resolveAssignedToId(dto.assignedToId, dto.assigned_to);
    const technicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note) ?? original.technicalNote;
    const extraRequirements =
      this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements) ?? original.extraRequirements;

    await this.assertClientExists(clientId);
    await this.assertQuotationMatchesClient(quotationId, clientId);
    await this.assertClientHasNoOpenOrder(clientId);

    try {
      const cloned = await this.prisma.$transaction(async (tx) => {
        const created = await tx.serviceOrder.create({
          include: {
            client: true,
            statusHistory: {
              orderBy: { changedAt: 'desc' },
              include: {
                changedBy: {
                  select: {
                    id: true,
                    nombreCompleto: true,
                    role: true,
                  },
                },
              },
            },
          },
          data: {
            clientId,
            quotationId,
            category: original.category,
            serviceType: SERVICE_ORDER_TYPE_TO_DB[serviceType as ApiServiceOrderType],
            status: SERVICE_ORDER_STATUS_TO_DB.pendiente,
            technicalNote,
            extraRequirements,
            parentOrderId: original.id,
            createdById: user.id,
            assignedToId,
            lastStatusChangedAt: new Date(),
            lastStatusChangedByUserId: user.id,
          },
        });

        const actorName = await this.resolveStatusActorName(tx, created.lastStatusChangedByUserId);

        await tx.serviceOrderStatusHistory.create({
          data: {
            serviceOrderId: created.id,
            previousStatus: null,
            nextStatus: created.status,
            changedAt: created.lastStatusChangedAt,
            changedByUserId: created.lastStatusChangedByUserId,
            changedByUserName: actorName,
            note: 'Estado inicial',
          },
        });

        return tx.serviceOrder.findUniqueOrThrow({
          where: { id: created.id },
          include: {
            client: true,
            statusHistory: {
              orderBy: { changedAt: 'desc' },
              include: {
                changedBy: {
                  select: {
                    id: true,
                    nombreCompleto: true,
                    role: true,
                  },
                },
              },
            },
          },
        });
      });
      const mapped = this.mapOrder(cloned);
      await this.invalidateCachesForOrder(cloned.id);
      this.emitOrderEvent('service.created', cloned.id, mapped);
      await this.runNotificationHook(`service.created:${cloned.id}`, () =>
        this.orderNotifications.handleOrderCreated(cloned.id),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async remove(user: AuthUser, id: string) {
    this.assertAdminDelete(user);
    await this.findOrderOrThrow(user, id);

    try {
      await this.prisma.serviceOrder.delete({ where: { id } });
      await this.invalidateCachesForOrder(id);
      this.emitOrderEvent('service.deleted', id);
      return { ok: true };
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async purgeAllForDebug(user: AuthUser) {
    this.assertAdminDelete(user);

    const deleted = await this.prisma.serviceOrder.deleteMany();
    await this.redis.delByPattern('service-orders:list:*');
    await this.redis.delByPattern('service-orders:detail:*');

    return {
      ok: true,
      deletedServiceOrders: deleted.count,
    };
  }

  private async updateAsTechnician(
    user: AuthUser,
    current: ServiceOrderRecord,
    dto: UpdateServiceOrderDto,
  ) {
    this.assertCanModifyOrder(user, current);
    this.assertTecnicoUpdateDoesNotChangeProtectedFields(current, dto);

    const data = this.buildTecnicoUpdateData(dto, current);
    if (!data) {
      return this.mapOrder(current);
    }

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id: current.id },
        include: { client: true },
        data,
      });
      const mapped = this.mapOrder(updated);
      await this.invalidateCachesForOrder(updated.id);
      this.emitOrderEvent('service.updated', updated.id, mapped);
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  private buildListCacheKey(
    user: AuthUser,
    options?: {
      statuses?: ApiServiceOrderStatus[];
      from?: string;
      to?: string;
    },
  ) {
    const statuses = options?.statuses?.slice().sort().join(',') || 'default';
    const from = options?.from?.trim() || 'none';
    const to = options?.to?.trim() || 'none';
    return `service-orders:list:${user.role}:${user.id}:statuses=${statuses}:from=${from}:to=${to}`;
  }

  private parseRequestedStatuses(statuses?: string[]) {
    if (!Array.isArray(statuses) || statuses.length === 0) {
      return null;
    }

    return statuses
      .map((status) => this.cleanOptionalText(status))
      .filter((status): status is ApiServiceOrderStatus => {
        if (!status) return false;
        return Object.prototype.hasOwnProperty.call(SERVICE_ORDER_STATUS_TO_DB, status);
      });
  }

  private buildListWhere(
    query: ListServiceOrdersQueryDto,
    normalizedStatuses: ApiServiceOrderStatus[] | null,
  ): Prisma.ServiceOrderWhereInput {
    const requestedStatuses =
      normalizedStatuses && normalizedStatuses.length > 0
        ? normalizedStatuses
        : (['pendiente', 'en_proceso', 'en_pausa'] as ApiServiceOrderStatus[]);

    const from = this.parseOptionalDate(query.from, undefined, 'from');
    const to = this.parseOptionalDate(query.to, undefined, 'to');

    const where: Prisma.ServiceOrderWhereInput = {
      status: {
        in: requestedStatuses.map((status) => SERVICE_ORDER_STATUS_TO_DB[status]),
      },
    };

    if (from || to) {
      where.lastStatusChangedAt = {
        ...(from ? { gte: from } : {}),
        ...(to ? { lte: to } : {}),
      };
    }

    return where;
  }

  private buildCommissionWhere(
    user: AuthUser,
    period: CommissionPeriodRange,
  ): Prisma.ServiceOrderWhereInput {
    return {
      status: PrismaServiceOrderStatus.FINALIZADO,
      serviceType: {
        in: [
          PrismaServiceOrderType.INSTALACION,
          PrismaServiceOrderType.MANTENIMIENTO,
        ],
      },
      finalizedAt: {
        gte: period.from,
        lte: period.to,
      },
      ...this.buildCommissionVisibilityWhere(user),
    };
  }

  private buildAdminCommissionWhere(
    from?: string,
    to?: string,
  ): Prisma.ServiceOrderWhereInput {
    const range = this.resolveAdminCommissionDateRange(from, to);

    return {
      status: PrismaServiceOrderStatus.FINALIZADO,
      serviceType: {
        in: [
          PrismaServiceOrderType.INSTALACION,
          PrismaServiceOrderType.MANTENIMIENTO,
        ],
      },
      finalizedAt: {
        gte: range.from,
        lte: range.to,
      },
    };
  }

  private resolveAdminCommissionDateRange(from?: string, to?: string) {
    if (from?.trim() && to?.trim()) {
      const parsedFrom = new Date(from);
      const parsedTo = new Date(to);

      if (Number.isNaN(parsedFrom.getTime()) || Number.isNaN(parsedTo.getTime())) {
        throw new BadRequestException('El rango de fechas para comisiones es inválido');
      }

      const rangeFrom = new Date(
        parsedFrom.getUTCFullYear(),
        parsedFrom.getUTCMonth(),
        parsedFrom.getUTCDate(),
        0,
        0,
        0,
        0,
      );
      const rangeTo = new Date(
        parsedTo.getUTCFullYear(),
        parsedTo.getUTCMonth(),
        parsedTo.getUTCDate(),
        23,
        59,
        59,
        999,
      );

      if (rangeTo < rangeFrom) {
        throw new BadRequestException('La fecha final no puede ser menor que la inicial');
      }

      return { from: rangeFrom, to: rangeTo };
    }

    const current = this.resolveCommissionPeriod('current', new Date());
    return { from: current.from, to: current.to };
  }

  private buildCommissionVisibilityWhere(
    user: AuthUser,
  ): Prisma.ServiceOrderWhereInput {
    switch (user.role) {
      case Role.ADMIN:
        return {};
      case Role.TECNICO:
        return {
          OR: [
            {
              assignedToId: user.id,
              createdBy: {
                is: {
                  role: Role.TECNICO,
                },
              },
            },
            {
              createdById: user.id,
              OR: [
                {
                  createdBy: {
                    is: {
                      role: {
                        not: Role.TECNICO,
                      },
                    },
                  },
                },
                {
                  assignedToId: null,
                },
              ],
            },
          ],
        };
      default:
        return { createdById: user.id };
    }
  }

  private buildCommissionSummary(
    orders: ServiceCommissionOrder[],
    role: Role,
  ) {
    let totalSold = 0;
    let sellerCommissionTotal = 0;
    let technicianCommissionTotal = 0;

    for (const order of orders) {
      const commission = this.computeCommissionAmounts(order);
      totalSold += commission.totalAmount;
      sellerCommissionTotal += commission.sellerCommissionAmount;
      technicianCommissionTotal += commission.technicianCommissionAmount;
    }

    const totalServices = orders.length;
    const visibleCommissionTotal = this.resolveVisibleCommissionTotal(
      role,
      sellerCommissionTotal,
      technicianCommissionTotal,
    );

    return {
      totalServices,
      totalSold,
      averageSold: totalServices == 0 ? 0 : totalSold / totalServices,
      sellerCommissionTotal,
      technicianCommissionTotal,
      visibleCommissionTotal,
      totalCommission: sellerCommissionTotal + technicianCommissionTotal,
    };
  }

  private mapCommissionOrder(
    order: ServiceCommissionOrder,
    role: Role,
  ) {
    const commission = this.computeCommissionAmounts(order);
    return {
      id: order.id,
      clientId: order.clientId,
      clientName: order.client.nombre,
      quotationId: order.quotationId,
      createdById: order.createdById,
      createdByName: order.createdBy.nombreCompleto,
      technicianId: order.assignedToId,
      technicianName: order.assignedTo?.nombreCompleto ?? null,
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[order.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[order.status],
      finalizedAt: order.finalizedAt,
      totalAmount: commission.totalAmount,
      sellerCommissionAmount: commission.sellerCommissionAmount,
      technicianCommissionAmount: commission.technicianCommissionAmount,
      commissionRecipientUserId: commission.recipientUserId,
      commissionRecipientSource: commission.recipientSource,
      visibleCommissionAmount: this.resolveVisibleCommissionTotal(
        role,
        commission.sellerCommissionAmount,
        commission.technicianCommissionAmount,
      ),
      totalCommissionAmount: commission.totalCommissionAmount,
    };
  }

  private computeCommissionAmounts(order: ServiceCommissionOrder) {
    const totalAmount = this.toNumber(order.quotation?.total);
    const totalProfit = this.toNumber(order.quotation?.totalProfit);
    const { recipientSource, recipientUserId } = this.resolveCommissionRecipient({
      createdById: order.createdById,
      assignedToId: order.assignedToId,
      createdByRole: order.createdBy.role,
    });
    const operationalExpenseRate = 0.2;
    const operationalExpenseAmount = totalProfit > 0 ? totalProfit * operationalExpenseRate : 0;
    const profitAfterExpense = Math.max(0, totalProfit - operationalExpenseAmount);
    const totalCommissionAmount = profitAfterExpense;
    const sellerCommissionAmount = recipientSource === 'creator' ? totalCommissionAmount : 0;
    const technicianCommissionAmount = recipientSource === 'assigned_technician'
      ? totalCommissionAmount
      : 0;

    return {
      totalAmount,
      totalProfit,
      profitAfterExpense,
      operationalExpenseRate,
      operationalExpenseAmount,
      recipientUserId,
      recipientSource,
      sellerCommissionAmount,
      technicianCommissionAmount,
      totalCommissionAmount,
    };
  }

  private resolveCommissionRecipient(params: {
    createdById: string;
    assignedToId: string | null;
    createdByRole: Role;
  }) {
    const assignedToId = params.assignedToId?.trim() ?? '';

    if (params.createdByRole === Role.TECNICO && assignedToId.length > 0) {
      return {
        recipientUserId: assignedToId,
        recipientSource: 'assigned_technician' as const,
      };
    }

    return {
      recipientUserId: params.createdById,
      recipientSource: 'creator' as const,
    };
  }

  private resolveVisibleCommissionTotal(
    role: Role,
    sellerCommissionAmount: number,
    technicianCommissionAmount: number,
  ) {
    switch (role) {
      case Role.ADMIN:
        return sellerCommissionAmount + technicianCommissionAmount;
      case Role.TECNICO:
        return technicianCommissionAmount;
      default:
        return sellerCommissionAmount;
    }
  }

  private resolveCommissionPeriod(
    key: CommissionPeriodKey,
    now: Date,
  ): CommissionPeriodRange {
    const current = this.buildCurrentCommissionPeriod(now);
    if (key == 'current') {
      return current;
    }
    return this.buildPreviousCommissionPeriod(current);
  }

  private buildCurrentCommissionPeriod(now: Date): CommissionPeriodRange {
    const year = now.getFullYear();
    const month = now.getMonth();
    const day = now.getDate();

    if (day >= 15 && day <= 29) {
      const monthLastDay = this.lastDayOfMonth(year, month);
      return {
        key: 'current',
        kind: 'mid_month',
        from: new Date(year, month, 15, 0, 0, 0, 0),
        to: new Date(
          year,
          month,
          Math.min(29, monthLastDay),
          23,
          59,
          59,
          999,
        ),
      };
    }

    if (day >= 30) {
      return {
        key: 'current',
        kind: 'bridged',
        from: new Date(year, month, 30, 0, 0, 0, 0),
        to: new Date(year, month + 1, 14, 23, 59, 59, 999),
      };
    }

    const previousMonth = this.shiftMonth(year, month, -1);
    const previousMonthLastDay = this.lastDayOfMonth(
      previousMonth.year,
      previousMonth.month,
    );
    const previousMonthStartDay = Math.min(30, previousMonthLastDay);

    return {
      key: 'current',
      kind: 'bridged',
      from: new Date(
        previousMonth.year,
        previousMonth.month,
        previousMonthStartDay,
        0,
        0,
        0,
        0,
      ),
      to: new Date(year, month, 14, 23, 59, 59, 999),
    };
  }

  private buildPreviousCommissionPeriod(
    current: CommissionPeriodRange,
  ): CommissionPeriodRange {
    if (current.kind === 'mid_month') {
      const end = current.from;
      const previousMonth = this.shiftMonth(end.getFullYear(), end.getMonth(), -1);
      const previousMonthLastDay = this.lastDayOfMonth(
        previousMonth.year,
        previousMonth.month,
      );
      const previousMonthStartDay = Math.min(30, previousMonthLastDay);
      return {
        key: 'previous',
        kind: 'bridged',
        from: new Date(
          previousMonth.year,
          previousMonth.month,
          previousMonthStartDay,
          0,
          0,
          0,
          0,
        ),
        to: new Date(end.getFullYear(), end.getMonth(), 14, 23, 59, 59, 999),
      };
    }

    const start = current.from;
    const monthLastDay = this.lastDayOfMonth(
      start.getFullYear(),
      start.getMonth(),
    );
    return {
      key: 'previous',
      kind: 'mid_month',
      from: new Date(start.getFullYear(), start.getMonth(), 15, 0, 0, 0, 0),
      to: new Date(
        start.getFullYear(),
        start.getMonth(),
        Math.min(29, monthLastDay),
        23,
        59,
        59,
        999,
      ),
    };
  }

  private buildCommissionRangeLabel(period: CommissionPeriodRange) {
    const from = period.from;
    const to = period.to;
    const fromMonth = from.toLocaleDateString('es-DO', { month: 'short' });
    const toMonth = to.toLocaleDateString('es-DO', { month: 'short' });
    return `${from.getDate()} ${fromMonth} - ${to.getDate()} ${toMonth}`;
  }

  private toDateOnly(value: Date) {
    const year = value.getFullYear();
    const month = `${value.getMonth() + 1}`.padStart(2, '0');
    const day = `${value.getDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private shiftMonth(year: number, month: number, delta: number) {
    const shifted = new Date(year, month + delta, 1, 0, 0, 0, 0);
    return {
      year: shifted.getFullYear(),
      month: shifted.getMonth(),
    };
  }

  private lastDayOfMonth(year: number, month: number) {
    return new Date(year, month + 1, 0, 0, 0, 0, 0).getDate();
  }

  private buildDetailCacheKey(user: AuthUser, id: string) {
    return `service-orders:detail:${user.role}:${user.id}:${id}`;
  }

  private async invalidateCachesForOrder(id: string) {
    await this.redis.delByPattern('service-orders:list:*');
    await this.redis.delByPattern(`service-orders:detail:*:*:${id}`);
  }

  private emitOrderEvent(type: string, serviceId: string, service?: unknown) {
    this.realtime.emitOps('service.event', {
      eventId: randomUUID(),
      type,
      serviceId,
      ...(service == null ? {} : { service }),
      occurredAt: new Date().toISOString(),
    });
  }

  private async buildCreatePayload(
    user: AuthUser,
    dto: CreateServiceOrderDto,
  ): Promise<Prisma.ServiceOrderUncheckedCreateInput> {
    const clientId = this.requireAliasValue(dto.clientId, dto.client_id, 'client_id');
    const quotationId = this.cleanOptionalText(dto.quotationId, dto.quotation_id);
    const category = this.requireDirectValue(dto.category, 'category') as ApiServiceOrderCategory;
    const serviceType = this.requireAliasValue(dto.serviceType, dto.service_type, 'service_type') as ApiServiceOrderType;
    const scheduledFor = this.parseScheduledDateAlias(dto, 'scheduled_for');
    const technicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note);
    const extraRequirements = this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements);
    const assignedToId = await this.resolveAssignedToId(dto.assignedToId, dto.assigned_to);

    await this.assertClientExists(clientId);
    await this.assertQuotationMatchesClient(quotationId, clientId);
    await this.assertClientHasNoOpenOrder(clientId);

    return {
      clientId,
      quotationId,
      category: SERVICE_ORDER_CATEGORY_TO_DB[category],
      serviceType: SERVICE_ORDER_TYPE_TO_DB[serviceType],
      status: SERVICE_ORDER_STATUS_TO_DB.pendiente,
      scheduledFor,
      technicalNote,
      extraRequirements,
      createdById: user.id,
      lastStatusChangedAt: new Date(),
      lastStatusChangedByUserId: user.id,
      assignedToId,
    };
  }

  private evaluateServiceSalesOrder(order: ServiceSalesOrderWithRelations) {
    const quotation = order.quotation;
    if (!quotation) {
      return this.buildSkippedServiceSalesOrder(order, 'La orden no tiene cotización vinculada');
    }
    const quotationItems = quotation.items ?? [];
    if (!quotationItems.length) {
      return this.buildSkippedServiceSalesOrder(order, 'La cotización no tiene líneas registradas');
    }

    let missingCostItemsCount = 0;

    for (const item of quotationItems) {
      if (item.costUnitSnapshot == null || item.subtotalCost == null || item.profit == null) {
        missingCostItemsCount += 1;
      }
    }

    if (missingCostItemsCount > 0) {
      return this.buildSkippedServiceSalesOrder(
        order,
        missingCostItemsCount === quotationItems.length
          ? 'La cotización depende de artículos sin costo trazable desde catálogo'
          : 'La cotización contiene líneas sin costo trazable desde catálogo',
        missingCostItemsCount,
      );
    }

    if (quotation.totalCost == null || quotation.totalProfit == null) {
      return this.buildSkippedServiceSalesOrder(
        order,
        'La cotización no tiene utilidad histórica persistida',
        missingCostItemsCount,
      );
    }

    const totalQuoted = this.toNumber(quotation.total);
    const totalCost = this.toNumber(quotation.totalCost);
    const totalProfit = this.toNumber(quotation.totalProfit);
    const { recipientUserId, recipientSource } = this.resolveCommissionRecipient({
      createdById: order.createdById,
      assignedToId: order.assignedToId,
      createdByRole: order.createdBy.role,
    });
    const operationalExpenseRate = 0.2;
    const operationalExpenseAmount = totalProfit > 0 ? totalProfit * operationalExpenseRate : 0;
    const profitAfterExpense = Math.max(0, totalProfit - operationalExpenseAmount);
    const totalCommissionAmount = profitAfterExpense;
    const sellerCommissionAmount = recipientSource === 'creator' ? totalCommissionAmount : 0;
    const technicianCommissionAmount = recipientSource === 'assigned_technician'
      ? totalCommissionAmount
      : 0;

    return {
      orderId: order.id,
      quotationId: order.quotationId,
      customerId: order.clientId,
      customerName: order.client.nombre,
      category: SERVICE_ORDER_CATEGORY_FROM_DB[order.category],
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[order.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[order.status],
      finalizedAt: order.finalizedAt,
      createdById: order.createdById,
      technicianId: order.assignedToId,
      technicianName: order.assignedTo?.nombreCompleto ?? null,
      technicianEmail: order.assignedTo?.email ?? null,
      itemsCount: quotationItems.length,
      totalQuoted,
      totalCost,
      totalProfit,
      operationalExpenseRate,
      operationalExpenseAmount,
      profitAfterExpense,
      commissionRecipientUserId: recipientUserId,
      commissionRecipientSource: recipientSource,
      sellerCommissionRate: recipientSource === 'creator' ? 0.8 : 0,
      sellerCommissionAmount,
      technicianCommissionRate: recipientSource === 'assigned_technician' ? 0.8 : 0,
      technicianCommissionAmount,
      totalCommissionAmount,
    };
  }

  private buildSkippedServiceSalesOrder(
    order: ServiceSalesOrderWithRelations,
    reason: string,
    missingCostItemsCount = 0,
  ) {
    return {
      orderId: order.id,
      quotationId: order.quotationId,
      customerId: order.clientId,
      customerName: order.client.nombre,
      category: SERVICE_ORDER_CATEGORY_FROM_DB[order.category],
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[order.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[order.status],
      finalizedAt: order.finalizedAt,
      createdById: order.createdById,
      technicianId: order.assignedToId,
      technicianName: order.assignedTo?.nombreCompleto ?? null,
      reason,
      itemsCount: order.quotation?.items.length ?? 0,
      missingCostItemsCount,
      totalQuoted: this.toNumber(order.quotation?.total),
    };
  }

  private async queueServiceCommissionForPayroll(
    serviceOrderId: string,
    finalizedByUserId?: string,
  ) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: serviceOrderId },
      include: {
        client: true,
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
            email: true,
          },
        },
        createdBy: {
          select: {
            id: true,
            nombreCompleto: true,
            role: true,
          },
        },
        quotation: {
          include: {
            items: {
              orderBy: { createdAt: 'asc' },
            },
          },
        },
      },
    });

    if (!order) {
      return;
    }

    if (
      order.serviceType !== PrismaServiceOrderType.INSTALACION &&
      order.serviceType !== PrismaServiceOrderType.MANTENIMIENTO
    ) {
      return;
    }

    if (!order.finalizedAt) {
      return;
    }

    const evaluated = this.evaluateServiceSalesOrder(order);
    if ('reason' in evaluated) {
      return;
    }

    const recipientUserId = evaluated.commissionRecipientUserId?.trim();
    if (!recipientUserId) {
      return;
    }

    const ownerId = await this.payroll.resolveCompanyOwnerId(order.createdById);
    const concept = [
      evaluated.commissionRecipientSource === 'assigned_technician'
        ? 'Comisión de servicio para técnico instalador'
        : 'Comisión de servicio para creador de la orden',
      order.client.nombre.trim(),
      `OS ${order.id.slice(0, 8).toUpperCase()}`,
    ].join(' · ');

    await this.payroll.queueServiceCommissionRequest({
      ownerId,
      serviceOrderId: order.id,
      quotationId: order.quotationId,
      recipientUserId,
      technicianUserId: order.assignedToId ?? recipientUserId,
      createdByUserId: order.createdById,
      serviceType: order.serviceType,
      finalizedAt: order.finalizedAt,
      profitAfterExpense: this.toNumber(evaluated.profitAfterExpense),
      commissionRate:
        evaluated.commissionRecipientSource === 'assigned_technician'
          ? this.toNumber(evaluated.technicianCommissionRate)
          : this.toNumber(evaluated.sellerCommissionRate),
      commissionAmount: this.toNumber(evaluated.totalCommissionAmount),
      concept,
    });
  }

  private async findOrderOrThrow(
    user: AuthUser,
    id: string,
  ): Promise<ServiceOrderRecord> {
    const item = await this.prisma.serviceOrder.findUnique({
      where: { id },
    });

    if (!item) {
      throw new NotFoundException('Orden de servicio no encontrada');
    }

    return item;
  }

  private async findOrderWithRelationsOrThrow(
    user: AuthUser,
    id: string,
  ): Promise<ServiceOrderWithRelations> {
    const item = await this.prisma.serviceOrder.findUnique({
      where: { id },
      include: {
        client: true,
        statusHistory: {
          orderBy: { changedAt: 'desc' },
          include: {
            changedBy: {
              select: {
                id: true,
                nombreCompleto: true,
                role: true,
              },
            },
          },
        },
        evidences: { orderBy: { createdAt: 'asc' } },
        reports: { orderBy: { createdAt: 'asc' } },
      },
    });

    if (!item) {
      throw new NotFoundException('Orden de servicio no encontrada');
    }

    return item;
  }

  private assertCanOperate(
    user: AuthUser,
    item: {
      createdById: string;
      assignedToId: string | null;
    },
  ) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return;
    if (user.role === Role.VENDEDOR && item.createdById === user.id) return;
    if (user.role === Role.TECNICO) return;
    throw new ForbiddenException('No puedes operar esta orden de servicio');
  }

  private assertAdmin(user: AuthUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException('Solo administradores pueden modificar o eliminar órdenes');
    }
  }

  private hasAssignedToInput(dto: UpdateServiceOrderDto) {
    return Object.prototype.hasOwnProperty.call(dto, 'assignedToId') ||
      Object.prototype.hasOwnProperty.call(dto, 'assigned_to');
  }

  private hasScheduledForInput(dto: UpdateServiceOrderDto) {
    return Object.prototype.hasOwnProperty.call(dto, 'scheduledFor') ||
      Object.prototype.hasOwnProperty.call(dto, 'scheduled_for') ||
      Object.prototype.hasOwnProperty.call(dto, 'scheduledAt') ||
      Object.prototype.hasOwnProperty.call(dto, 'scheduled_at');
  }

  private assertCanFullyEditOrder(
    user: AuthUser,
    item: { createdById: string },
  ) {
    if (user.role === Role.ADMIN || item.createdById === user.id) {
      return;
    }
    throw new ForbiddenException('Not authorized to modify this order');
  }

  private assertAdminEdit(user: AuthUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException('Not authorized to modify this order');
    }
  }

  private assertAdminDelete(user: AuthUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException('Only admin can delete orders');
    }
  }

  private assertCanModifyOrder(user: AuthUser, item: { createdById: string; assignedToId: string | null }) {
    if (user.role === Role.ADMIN) {
      return;
    }
    if (user.role === Role.TECNICO) {
      return;
    }
    if (item.createdById === user.id) {
      return;
    }
    throw new ForbiddenException('Not authorized to modify this order');
  }

  private assertCanChangeOrderStatus(
    user: AuthUser,
    item: { createdById: string },
    nextStatus: ApiServiceOrderStatus,
  ) {
    if (nextStatus === 'pospuesta') {
      this.assertCanPostponeOrder(user, item);
      return;
    }

    if (user.role === Role.ADMIN || user.role === Role.TECNICO) {
      return;
    }
    if (nextStatus === 'cancelado') {
      return;
    }
    throw new ForbiddenException(
      'Solo administradores y técnicos pueden marcar una orden en proceso o finalizada. Para otros roles solo se permite cancelarla.',
    );
  }

  private assertCanPostponeOrder(
    user: AuthUser,
    item: { createdById: string },
  ) {
    if (user.role === Role.ADMIN || item.createdById === user.id) {
      return;
    }

    throw new ForbiddenException('Solo un administrador o el creador de la orden puede marcarla como pospuesta');
  }

  private assertTechnicalOutputAccess(user: AuthUser) {
    if (user.role === Role.ADMIN || user.role === Role.TECNICO) {
      return;
    }
    throw new ForbiddenException('Not authorized to modify this order');
  }

  private hasTextInput(dto: UpdateServiceOrderDto, ...keys: Array<keyof UpdateServiceOrderDto>) {
    return keys.some((key) => Object.prototype.hasOwnProperty.call(dto, key));
  }

  private buildTecnicoUpdateData(
    dto: UpdateServiceOrderDto,
    current: ServiceOrderRecord,
  ): Prisma.ServiceOrderUncheckedUpdateInput | null {
    const data: Prisma.ServiceOrderUncheckedUpdateInput = {};

    if (this.hasTextInput(dto, 'technicalNote', 'technical_note')) {
      const nextTechnicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note);
      if (nextTechnicalNote !== current.technicalNote) {
        data.technicalNote = nextTechnicalNote;
      }
    }

    if (this.hasTextInput(dto, 'extraRequirements', 'extra_requirements')) {
      const nextExtraRequirements = this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements);
      if (nextExtraRequirements !== current.extraRequirements) {
        data.extraRequirements = nextExtraRequirements;
      }
    }

    return Object.keys(data).length > 0 ? data : null;
  }

  private assertTecnicoUpdateDoesNotChangeProtectedFields(
    current: ServiceOrderRecord,
    dto: UpdateServiceOrderDto,
  ) {
    const nextClientId = this.cleanOptionalText(dto.clientId, dto.client_id);
    if ((dto.clientId !== undefined || dto.client_id !== undefined) && nextClientId !== current.clientId) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextQuotationId = this.cleanOptionalText(dto.quotationId, dto.quotation_id);
    if (
      (dto.quotationId !== undefined || dto.quotation_id !== undefined) &&
      nextQuotationId !== current.quotationId
    ) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextCategory = this.cleanOptionalText(dto.category);
    if (dto.category !== undefined && nextCategory !== SERVICE_ORDER_CATEGORY_FROM_DB[current.category]) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextServiceType = this.cleanOptionalText(dto.serviceType, dto.service_type);
    if (
      (dto.serviceType !== undefined || dto.service_type !== undefined) &&
      nextServiceType !== SERVICE_ORDER_TYPE_FROM_DB[current.serviceType]
    ) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextAssignedToId = this.cleanOptionalText(dto.assignedToId, dto.assigned_to);
    if (
      (dto.assignedToId !== undefined || dto.assigned_to !== undefined) &&
      nextAssignedToId !== current.assignedToId
    ) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    if (
      dto.scheduledFor !== undefined ||
      dto.scheduled_for !== undefined ||
      dto.scheduledAt !== undefined ||
      dto.scheduled_at !== undefined
    ) {
      const nextScheduledFor = this.parseScheduledDateAlias(dto, 'scheduled_for');
      const currentIso = current.scheduledFor?.toISOString() ?? null;
      const nextIso = nextScheduledFor?.toISOString() ?? null;
      if (currentIso !== nextIso) {
        throw new ForbiddenException('Not authorized to modify this order');
      }
    }
  }

  private assertCanAddEvidenceType(user: AuthUser, type: ApiServiceEvidenceType) {
    if (type.startsWith('referencia_')) {
      return;
    }

    this.assertTechnicalOutputAccess(user);
  }

  private assertCanManageTechnicalOutputs(user: AuthUser) {
    if (user.role === Role.ADMIN || user.role === Role.TECNICO) {
      return;
    }

    throw new ForbiddenException('Solo admin y técnico pueden registrar evidencia técnica o reportes');
  }

  private async assertClientExists(clientId: string) {
    const client = await this.prisma.client.findUnique({
      where: { id: clientId },
      select: { id: true },
    });
    if (!client) throw new NotFoundException('Cliente no encontrado');
  }

  private async assertQuotationMatchesClient(quotationId: string | null | undefined, clientId: string) {
    if (!quotationId?.trim()) {
      return;
    }
    const quotation = await this.prisma.cotizacion.findUnique({
      where: { id: quotationId },
      select: { id: true, customerId: true },
    });
    if (!quotation) throw new NotFoundException('Cotización no encontrada');
    if (quotation.customerId && quotation.customerId !== clientId) {
      throw new BadRequestException('La cotización indicada no pertenece al cliente seleccionado');
    }
  }

  private async assertClientHasNoOpenOrder(clientId: string, excludeOrderId?: string) {
    const existingOrder = await this.prisma.serviceOrder.findFirst({
      where: {
        clientId,
        status: {
          not: PrismaServiceOrderStatus.FINALIZADO,
        },
        ...(excludeOrderId ? { id: { not: excludeOrderId } } : {}),
      },
      select: {
        id: true,
        status: true,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    if (!existingOrder) {
      return;
    }

    const status = SERVICE_ORDER_STATUS_FROM_DB[existingOrder.status];
    throw new ConflictException(
      `El cliente ya tiene una orden sin finalizar en estado ${status}. Debes finalizarla antes de crear otra.`,
    );
  }

  private async resolveAssignedToId(value?: string | null, alias?: string | null) {
    const assignedToId = this.cleanOptionalText(value, alias);
    if (!assignedToId) return null;

    const technician = await this.prisma.user.findUnique({
      where: { id: assignedToId },
      select: { id: true, role: true },
    });

    if (!technician) throw new NotFoundException('Usuario asignado no encontrado');
    if (technician.role !== Role.TECNICO) {
      throw new BadRequestException('assigned_to debe pertenecer a un técnico');
    }

    return technician.id;
  }

  private assertValidStatusTransition(
    current: ApiServiceOrderStatus,
    next: ApiServiceOrderStatus,
  ) {
    if (current === next) {
      throw new BadRequestException('La orden ya tiene ese estado');
    }

    const allowed = SERVICE_ORDER_ALLOWED_STATUS_TRANSITIONS[current];
    if (!allowed.includes(next)) {
      throw new BadRequestException(
        `Transición inválida de estado: ${current} -> ${next}`,
      );
    }
  }

  private canFinalizePendingDirectly(
    user: AuthUser,
    current: ApiServiceOrderStatus,
    next: ApiServiceOrderStatus,
  ) {
    return (
      current === 'pendiente' &&
      next === 'finalizado' &&
      (user.role === Role.ADMIN || user.role === Role.TECNICO)
    );
  }

  private requireAliasValue(primary: string | undefined, alias: string | undefined, fieldName: string) {
    const value = this.cleanOptionalText(primary, alias);
    if (!value) {
      throw new BadRequestException(`El campo ${fieldName} es requerido`);
    }
    return value;
  }

  private requireDirectValue(value: string | undefined, fieldName: string) {
    const normalized = this.cleanOptionalText(value);
    if (!normalized) {
      throw new BadRequestException(`El campo ${fieldName} es requerido`);
    }
    return normalized;
  }

  private cleanRequiredText(value: string | undefined, fieldName: string) {
    const normalized = this.cleanOptionalText(value);
    if (!normalized) {
      throw new BadRequestException(`El campo ${fieldName} es requerido`);
    }
    return normalized;
  }

  private cleanOptionalText(...values: Array<string | null | undefined>) {
    for (const value of values) {
      const normalized = value?.trim();
      if (normalized) return normalized;
    }
    return null;
  }

  private parseOptionalDate(
    primary?: string | null,
    alias?: string | null,
    fieldName = 'date',
  ): Date | null {
    for (const value of [primary, alias]) {
      if (value == null) continue;
      const trimmed = value.trim();
      if (!trimmed) continue;
      const parsed = new Date(trimmed);
      if (Number.isNaN(parsed.getTime())) {
        throw new BadRequestException(`El campo ${fieldName} debe ser una fecha válida`);
      }
      return parsed;
    }

    return null;
  }

  private parseScheduledDateAlias(
    dto: CreateServiceOrderDto | UpdateServiceOrderDto | UpdateStatusDto,
    fieldName = 'scheduled_at',
  ) {
    return this.parseOptionalDate(
      dto.scheduledAt,
      dto.scheduled_at ?? dto.scheduledFor ?? dto.scheduled_for,
      fieldName,
    );
  }

  private assertScheduledDateInFuture(value: Date | null, fieldName: string) {
    if (!value) {
      throw new BadRequestException(`El campo ${fieldName} es obligatorio cuando el estado es pospuesta`);
    }

    if (value.getTime() <= Date.now()) {
      throw new BadRequestException(`El campo ${fieldName} debe ser una fecha futura`);
    }
  }

  private async runNotificationHook(label: string, action: () => Promise<void>) {
    try {
      await action();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(`Notification hook failed ${label}: ${message}`);
    }
  }

  private toApiStatus(status: ServiceOrderRecord['status']) {
    return SERVICE_ORDER_STATUS_FROM_DB[status];
  }

  private async resolveStatusActorName(
    tx: Prisma.TransactionClient,
    userId: string | null | undefined,
  ) {
    const normalizedUserId = userId?.trim();
    if (!normalizedUserId) {
      return null;
    }

    const user = await tx.user.findUnique({
      where: { id: normalizedUserId },
      select: {
        nombreCompleto: true,
      },
    });

    return this.cleanOptionalText(user?.nombreCompleto);
  }

  private toNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number {
    if (value == null) return 0;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }

  private buildFinalizedAtRange(from?: string, to?: string): { finalizedAt?: Prisma.DateTimeFilter } {
    if (!from && !to) return {};

    const finalizedAt: Prisma.DateTimeFilter = {};

    if (from) {
      const start = new Date(`${from}T00:00:00.000Z`);
      if (!Number.isNaN(start.getTime())) {
        finalizedAt.gte = start;
      }
    }

    if (to) {
      const end = new Date(`${to}T23:59:59.999Z`);
      if (!Number.isNaN(end.getTime())) {
        finalizedAt.lte = end;
      }
    }

    return Object.keys(finalizedAt).length ? { finalizedAt } : {};
  }

  private toNullableNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number | null {
    if (value == null) return null;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  private mapClient(client: Client) {
    const latitude = this.toNullableNumber(client.latitude);
    const longitude = this.toNullableNumber(client.longitude);
    const locationUrl = client.locationUrl ?? null;

    return {
      ...client,
      latitude,
      longitude,
      locationUrl,
      location_url: locationUrl,
    };
  }

  private mapOrder(item: ServiceOrderWithRelations | ServiceOrderWithClient | ServiceOrderRecord) {
    const base = {
      id: item.id,
      clientId: item.clientId,
      quotationId: item.quotationId,
      category: SERVICE_ORDER_CATEGORY_FROM_DB[item.category],
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[item.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[item.status],
      scheduledFor: item.scheduledFor,
      finalizedAt: item.finalizedAt,
      technicianConfirmedAt: item.technicianConfirmedAt,
      technicianConfirmedById: item.technicianConfirmedById,
      technicalNote: item.technicalNote,
      extraRequirements: item.extraRequirements,
      parentOrderId: item.parentOrderId,
      createdById: item.createdById,
      assignedToId: item.assignedToId,
      lastStatusChangedAt: item.lastStatusChangedAt,
      lastStatusChangedByUserId: item.lastStatusChangedByUserId,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      ...('client' in item ? { client: this.mapClient(item.client) } : {}),
      ...('statusHistory' in item
        ? {
            statusHistory: item.statusHistory.map((entry) => this.mapStatusHistory(entry)),
          }
        : {}),
    };

    if ('evidences' in item || 'reports' in item) {
      const order = item as ServiceOrderWithRelations;
      return {
        ...base,
        evidences: order.evidences.map((evidence) => this.mapEvidence(evidence)),
        reports: order.reports.map((report) => this.mapReport(report)),
      };
    }

    return base;
  }

  private mapStatusHistory(
    entry: Prisma.ServiceOrderStatusHistoryGetPayload<{
      include: {
        changedBy: {
          select: {
            id: true;
            nombreCompleto: true;
            role: true;
          };
        };
      };
    }>,
  ) {
    return {
      id: entry.id,
      serviceOrderId: entry.serviceOrderId,
      previousStatus: entry.previousStatus
        ? SERVICE_ORDER_STATUS_FROM_DB[entry.previousStatus]
        : null,
      nextStatus: SERVICE_ORDER_STATUS_FROM_DB[entry.nextStatus],
      changedAt: entry.changedAt,
      createdAt: entry.createdAt,
      changedByUserId: entry.changedByUserId,
      changedByUserName:
        this.cleanOptionalText(entry.changedByUserName) ??
        this.cleanOptionalText(entry.changedBy?.nombreCompleto),
      note: entry.note,
      changedBy: entry.changedBy
        ? {
            id: entry.changedBy.id,
            nombreCompleto: entry.changedBy.nombreCompleto,
            role: entry.changedBy.role,
          }
        : null,
    };
  }

  private mapEvidence(item: Prisma.ServiceEvidenceGetPayload<object>) {
    const typeKey = String(item.type ?? '').trim().toUpperCase();
    return {
      id: item.id,
      serviceOrderId: item.serviceOrderId,
      type: SERVICE_EVIDENCE_TYPE_FROM_DB[typeKey] ?? 'referencia_texto',
      content: item.content,
      createdById: item.createdById,
      createdAt: item.createdAt,
    };
  }

  private mapReport(item: Prisma.ServiceReportGetPayload<object>) {
    const typeKey = String(item.type ?? '').trim().toUpperCase();
    return {
      id: item.id,
      serviceOrderId: item.serviceOrderId,
      type: SERVICE_REPORT_TYPE_FROM_DB[typeKey] ?? 'otros',
      report: item.report,
      createdById: item.createdById,
      createdAt: item.createdAt,
    };
  }

  private rethrowWriteError(error: unknown): never {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2025') {
        throw new NotFoundException('El recurso solicitado no existe');
      }
      if (error.code === 'P2003') {
        throw new BadRequestException('La operación viola una relación requerida');
      }
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown };
      if (value.code === 'P2025') {
        throw new NotFoundException('El recurso solicitado no existe');
      }
      if (value.code === 'P2003') {
        throw new BadRequestException('La operación viola una relación requerida');
      }
    }

    throw error;
  }
}
