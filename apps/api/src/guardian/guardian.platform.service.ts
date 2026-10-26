import { Injectable } from '@nestjs/common';
import {
  GuardianIncidentStatus,
  GuardianSeverity,
  Prisma,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { GuardianIncidentsService } from './guardian.incidents.service';

export type PlatformIncidentFilters = {
  companyId?: string;
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

/**
 * Consultas de plataforma para el panel Appyra.
 *
 * Diferencias con el panel de empresa:
 * - Puede abarcar todas las empresas (solo con el token de plataforma).
 * - Devuelve el nombre de empresa para contexto operativo.
 * - Registra cada acción en `guardian_access_logs` con rol PLATFORM.
 */
@Injectable()
export class GuardianPlatformService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly incidents: GuardianIncidentsService,
  ) {}

  async companies() {
    const companies = await this.prisma.company.findMany({
      where: { status: { not: 'ARCHIVED' } },
      select: { id: true, name: true, status: true, licenseStatus: true },
      orderBy: { name: 'asc' },
      take: 1_000,
    });

    const grouped = await this.prisma.guardianIncident.groupBy({
      by: ['companyId', 'severity'],
      where: { status: { in: ['OPEN', 'ACKNOWLEDGED', 'INVESTIGATING'] } },
      _count: { _all: true },
    });

    const byCompany = new Map<string, { open: number; critical: number }>();
    for (const row of grouped) {
      const current = byCompany.get(row.companyId) ?? { open: 0, critical: 0 };
      current.open += row._count._all;
      if (row.severity === GuardianSeverity.SEV1 || row.severity === GuardianSeverity.SEV2) {
        current.critical += row._count._all;
      }
      byCompany.set(row.companyId, current);
    }

    return companies.map((company) => {
      const counters = byCompany.get(company.id);
      return {
        id: company.id,
        name: company.name,
        status: String(company.status),
        licenseStatus: String(company.licenseStatus),
        openIncidents: counters?.open ?? 0,
        criticalIncidents: counters?.critical ?? 0,
        monitored: Boolean(counters),
      };
    });
  }

  async summary() {
    const [total, bySeverity, byStatus, byModule, pendingDiagnosis, lastIncident, openAlerts] =
      await Promise.all([
        this.prisma.guardianIncident.count(),
        this.prisma.guardianIncident.groupBy({
          by: ['severity'],
          where: { status: { in: ['OPEN', 'ACKNOWLEDGED', 'INVESTIGATING'] } },
          _count: { _all: true },
        }),
        this.prisma.guardianIncident.groupBy({
          by: ['status'],
          _count: { _all: true },
        }),
        this.prisma.guardianIncident.groupBy({
          by: ['module'],
          where: { occurredAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) } },
          _count: { _all: true },
        }),
        this.prisma.guardianIncident.count({
          where: { processingState: { in: ['PENDING', 'DIAGNOSING'] } },
        }),
        this.prisma.guardianIncident.findFirst({
          orderBy: { receivedAt: 'desc' },
          select: { receivedAt: true },
        }),
        this.prisma.guardianAlert.count({ where: { state: { in: ['PENDING', 'SENDING'] } } }),
      ]);

    return {
      totalIncidents: total,
      pendingDiagnosis,
      pendingAlerts: openAlerts,
      lastIncidentAt: lastIncident?.receivedAt ?? null,
      bySeverity: Object.fromEntries(bySeverity.map((row) => [row.severity, row._count._all])),
      byStatus: Object.fromEntries(byStatus.map((row) => [row.status, row._count._all])),
      byModule: Object.fromEntries(byModule.map((row) => [row.module, row._count._all])),
    };
  }

  async list(filters: PlatformIncidentFilters) {
    const limit = Math.min(100, Math.max(1, filters.limit ?? 50));
    const where: Prisma.GuardianIncidentWhereInput = {
      ...(filters.companyId ? { companyId: filters.companyId } : {}),
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
        companyId: true,
        module: true,
        operation: true,
        platform: true,
        appVersion: true,
        deviceId: true,
        severity: true,
        status: true,
        processingState: true,
        exceptionType: true,
        occurredAt: true,
        receivedAt: true,
        offlineMinutes: true,
        impactSummary: true,
        acknowledgedAt: true,
        resolvedAt: true,
        company: { select: { name: true } },
        diagnoses: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { verdict: true, confidence: true, summary: true },
        },
        alerts: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { state: true, channel: true, sentAt: true, deliveredAt: true },
        },
      },
    });

    const hasMore = rows.length > limit;
    const items = (hasMore ? rows.slice(0, limit) : rows).map((row) => ({
      ...row,
      companyName: row.company?.name ?? null,
      latestDiagnosis: row.diagnoses[0] ?? null,
      latestAlert: row.alerts[0] ?? null,
      company: undefined,
      diagnoses: undefined,
      alerts: undefined,
    }));

    return { items, nextCursor: hasMore ? items[items.length - 1]?.id ?? null : null, limit };
  }

  async detail(incidentId: string) {
    const incident = await this.prisma.guardianIncident.findUnique({
      where: { id: incidentId },
      include: {
        company: { select: { id: true, name: true, status: true, licenseStatus: true } },
        evidences: { orderBy: { createdAt: 'asc' } },
        diagnoses: { orderBy: { createdAt: 'desc' }, take: 5 },
        history: { orderBy: { createdAt: 'asc' }, take: 50 },
        alerts: {
          orderBy: { createdAt: 'desc' },
          take: 10,
          include: { attemptsLog: { orderBy: { createdAt: 'desc' }, take: 10 } },
        },
        group: true,
      },
    });

    return incident;
  }

  async act(params: {
    incidentId: string;
    action: 'ack' | 'investigate' | 'resolve' | 'close' | 'reopen';
    note?: string | null;
    actor: string;
  }) {
    const incident = await this.prisma.guardianIncident.findUnique({
      where: { id: params.incidentId },
      select: { companyId: true, status: true },
    });
    if (!incident) return null;

    const scoped = {
      companyId: incident.companyId,
      incidentId: params.incidentId,
      userId: null,
      note: params.note ?? null,
      // El historial debe reflejar el origen real de la accion, no el generico
      // de administrador: asi el expediente es fiel sin registrar dos entradas.
      actor: `platform:${params.action}`,
    };

    let updated;
    if (params.action === 'ack') updated = await this.incidents.acknowledge(scoped);
    else if (params.action === 'investigate') updated = await this.incidents.investigate(scoped);
    else if (params.action === 'resolve') updated = await this.incidents.resolve(scoped);
    else if (params.action === 'close') updated = await this.incidents.close(scoped);
    else {
      updated = await this.prisma.guardianIncident.update({
        where: { id: params.incidentId },
        data: { status: GuardianIncidentStatus.OPEN, resolvedAt: null },
      });
      await this.prisma.guardianIncidentEvent.create({
        data: {
          incidentId: params.incidentId,
          fromStatus: incident.status,
          toStatus: 'OPEN',
          actor: 'platform:reopen',
          note: (params.note ?? '').slice(0, 600) || null,
        },
      });
    }

    await this.prisma.guardianAccessLog.create({
      data: {
        action: `platform.${params.action}`,
        actorRole: 'PLATFORM',
        companyId: incident.companyId,
        incidentId: params.incidentId,
      },
    });

    return updated;
  }

  async health() {
    const [pendingAlerts, failedAlerts, pendingDiagnosis, lastIncident] = await Promise.all([
      this.prisma.guardianAlert.count({ where: { state: { in: ['PENDING', 'SENDING'] } } }),
      this.prisma.guardianAlert.count({ where: { state: 'FAILED_PERMANENT' } }),
      this.prisma.guardianIncident.count({
        where: { processingState: { in: ['PENDING', 'DIAGNOSING'] } },
      }),
      this.prisma.guardianIncident.findFirst({
        orderBy: { receivedAt: 'desc' },
        select: { receivedAt: true },
      }),
    ]);

    const now = Date.now();
    return {
      guardianEnabled: String(process.env.GUARDIAN_ENABLED ?? '').toLowerCase() === 'true',
      whatsappCloudConfigured: Boolean(
        (process.env.GUARDIAN_WA_CLOUD_TOKEN ?? process.env.META_WHATSAPP_TOKEN ?? '').trim() &&
          (process.env.GUARDIAN_WA_PHONE_NUMBER_ID ?? process.env.META_PHONE_NUMBER_ID ?? '').trim(),
      ),
      whatsappTemplateConfigured: Boolean((process.env.GUARDIAN_WA_TEMPLATE_NAME ?? '').trim()),
      fallbackConfigured: Boolean(
        (process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL ?? '').trim(),
      ),
      aiProvider: (process.env.GUARDIAN_AI_API_KEY ?? process.env.OPENAI_API_KEY ?? '').trim()
        ? 'openai'
        : 'mock',
      pendingAlerts,
      failedAlerts,
      pendingDiagnosis,
      lastIncidentAt: lastIncident?.receivedAt ?? null,
      lastIncidentAgeSeconds: lastIncident
        ? Math.floor((now - lastIncident.receivedAt.getTime()) / 1000)
        : null,
    };
  }
}
