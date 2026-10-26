import { Injectable, NotFoundException } from '@nestjs/common';
import {
  GuardianIncidentStatus,
  GuardianSeverity,
  Prisma,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export type GuardianListFilters = {
  companyId: string;
  status?: GuardianIncidentStatus;
  severity?: GuardianSeverity;
  module?: string;
  platform?: string;
  appVersion?: string;
  from?: Date;
  to?: Date;
  limit?: number;
  cursor?: string;
};

const MAX_LIMIT = 100;

@Injectable()
export class GuardianIncidentsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(filters: GuardianListFilters) {
    const limit = Math.min(MAX_LIMIT, Math.max(1, filters.limit ?? 50));
    const where: Prisma.GuardianIncidentWhereInput = {
      companyId: filters.companyId,
      ...(filters.status ? { status: filters.status } : {}),
      ...(filters.severity ? { severity: filters.severity } : {}),
      ...(filters.module ? { module: filters.module } : {}),
      ...(filters.platform ? { platform: filters.platform } : {}),
      ...(filters.appVersion ? { appVersion: filters.appVersion } : {}),
      ...(filters.from || filters.to
        ? {
            occurredAt: {
              ...(filters.from ? { gte: filters.from } : {}),
              ...(filters.to ? { lte: filters.to } : {}),
            },
          }
        : {}),
    };

    const rows = await this.prisma.guardianIncident.findMany({
      where,
      orderBy: [{ occurredAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
      ...(filters.cursor ? { cursor: { id: filters.cursor }, skip: 1 } : {}),
      select: {
        id: true,
        eventId: true,
        module: true,
        operation: true,
        platform: true,
        appVersion: true,
        severity: true,
        status: true,
        processingState: true,
        exceptionType: true,
        occurredAt: true,
        receivedAt: true,
        impactSummary: true,
        acknowledgedAt: true,
        resolvedAt: true,
        groupId: true,
        fingerprint: true,
      },
    });

    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;

    return {
      items,
      nextCursor: hasMore ? items[items.length - 1]?.id ?? null : null,
      limit,
    };
  }

  async detail(companyId: string, incidentId: string) {
    const incident = await this.prisma.guardianIncident.findFirst({
      where: { id: incidentId, companyId },
      include: {
        evidences: { orderBy: { createdAt: 'asc' } },
        diagnoses: { orderBy: { createdAt: 'desc' }, take: 5 },
        history: { orderBy: { createdAt: 'asc' }, take: 50 },
        group: true,
      },
    });

    if (!incident) throw new NotFoundException('Incidente no encontrado');

    return incident;
  }

  async summary(companyId: string) {
    const [bySeverity, byStatus, total, pendingDiagnosis, groups] = await Promise.all([
      this.prisma.guardianIncident.groupBy({
        by: ['severity'],
        where: { companyId, status: { in: ['OPEN', 'ACKNOWLEDGED', 'INVESTIGATING'] } },
        _count: { _all: true },
      }),
      this.prisma.guardianIncident.groupBy({
        by: ['status'],
        where: { companyId },
        _count: { _all: true },
      }),
      this.prisma.guardianIncident.count({ where: { companyId } }),
      this.prisma.guardianIncident.count({
        where: { companyId, processingState: { in: ['PENDING', 'DIAGNOSING'] } },
      }),
      this.prisma.guardianIncidentGroup.count({
        where: { incidents: { some: { companyId } } },
      }),
    ]);

    return {
      total,
      pendingDiagnosis,
      groups,
      bySeverity: Object.fromEntries(bySeverity.map((row) => [row.severity, row._count._all])),
      byStatus: Object.fromEntries(byStatus.map((row) => [row.status, row._count._all])),
    };
  }

  async acknowledge(params: {
    companyId: string;
    incidentId: string;
    userId: string | null;
    note?: string | null;
    actor?: string;
  }) {
    return this.transition(params, {
      toStatus: GuardianIncidentStatus.ACKNOWLEDGED,
      data: { acknowledgedAt: new Date(), acknowledgedByUserId: params.userId },
      actor: params.actor ?? 'admin:ack',
    });
  }

  async investigate(params: {
    companyId: string;
    incidentId: string;
    userId: string | null;
    note?: string | null;
    actor?: string;
  }) {
    return this.transition(params, {
      toStatus: GuardianIncidentStatus.INVESTIGATING,
      data: {
        acknowledgedAt: new Date(),
        acknowledgedByUserId: params.userId,
      },
      actor: params.actor ?? 'admin:investigate',
    });
  }

  async resolve(params: {
    companyId: string;
    incidentId: string;
    userId: string | null;
    note?: string | null;
    actor?: string;
  }) {
    return this.transition(params, {
      toStatus: GuardianIncidentStatus.RESOLVED,
      data: {
        resolvedAt: new Date(),
        resolvedByUserId: params.userId,
        resolutionNote: (params.note ?? '').toString().slice(0, 600) || null,
      },
      actor: params.actor ?? 'admin:resolve',
    });
  }

  async close(params: {
    companyId: string;
    incidentId: string;
    userId: string | null;
    note?: string | null;
    actor?: string;
  }) {
    return this.transition(params, {
      toStatus: GuardianIncidentStatus.CLOSED,
      data: { resolvedAt: new Date(), resolvedByUserId: params.userId },
      actor: params.actor ?? 'admin:close',
    });
  }

  private async transition(
    params: { companyId: string; incidentId: string; userId: string | null; note?: string | null },
    change: {
      toStatus: GuardianIncidentStatus;
      data: Prisma.GuardianIncidentUpdateInput;
      actor: string;
    },
  ) {
    const current = await this.prisma.guardianIncident.findFirst({
      where: { id: params.incidentId, companyId: params.companyId },
      select: { id: true, status: true },
    });
    if (!current) throw new NotFoundException('Incidente no encontrado');

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.guardianIncident.update({
        where: { id: current.id },
        data: { ...change.data, status: change.toStatus },
      });

      await tx.guardianIncidentEvent.create({
        data: {
          incidentId: current.id,
          fromStatus: current.status,
          toStatus: change.toStatus,
          actor: change.actor,
          actorUserId: params.userId,
          note: (params.note ?? '').toString().slice(0, 600) || null,
        },
      });

      return updated;
    });
  }
}
