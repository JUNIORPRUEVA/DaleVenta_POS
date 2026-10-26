import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export type GuardianQuotaPolicy = {
  enabled: boolean;
  incidentsPerHour: number;
  incidentsPerDay: number;
  deviceIncidentsPerDay: number;
};

export const DEFAULT_GUARDIAN_QUOTA: GuardianQuotaPolicy = {
  enabled: true,
  incidentsPerHour: 60,
  incidentsPerDay: 500,
  deviceIncidentsPerDay: 200,
};

export type GuardianQuotaDecision =
  | { allowed: true; policy: GuardianQuotaPolicy }
  | { allowed: false; policy: GuardianQuotaPolicy; reason: string; retryAfterSeconds: number };

/**
 * Cuotas por empresa y por dispositivo.
 *
 * Se calculan con `count` sobre `guardian_incidents` (índices por empresa), no con
 * contadores en memoria: si el proceso reinicia o hay varias réplicas, la cuota
 * sigue siendo correcta.
 */
@Injectable()
export class GuardianQuotaService {
  constructor(private readonly prisma: PrismaService) {}

  async getPolicy(companyId: string): Promise<GuardianQuotaPolicy> {
    const row = await this.prisma.guardianCompanyQuota.findUnique({ where: { companyId } });
    if (!row) return { ...DEFAULT_GUARDIAN_QUOTA };
    return {
      enabled: row.enabled,
      incidentsPerHour: row.incidentsPerHour,
      incidentsPerDay: row.incidentsPerDay,
      deviceIncidentsPerDay: row.incidentsPerDay,
    };
  }

  async evaluate(params: {
    companyId: string;
    deviceIds: string[];
    requestedEvents: number;
    now?: Date;
  }): Promise<GuardianQuotaDecision> {
    const policy = await this.getPolicy(params.companyId);
    const now = params.now ?? new Date();

    if (!policy.enabled) {
      return {
        allowed: false,
        policy,
        reason: 'GUARDIAN_DISABLED_FOR_COMPANY',
        retryAfterSeconds: 3600,
      };
    }

    const hourStart = new Date(now.getTime() - 60 * 60 * 1000);
    const dayStart = new Date(now.getTime() - 24 * 60 * 60 * 1000);

    const [lastHour, lastDay] = await Promise.all([
      this.prisma.guardianIncident.count({
        where: { companyId: params.companyId, receivedAt: { gte: hourStart } },
      }),
      this.prisma.guardianIncident.count({
        where: { companyId: params.companyId, receivedAt: { gte: dayStart } },
      }),
    ]);

    if (lastHour + params.requestedEvents > policy.incidentsPerHour) {
      return { allowed: false, policy, reason: 'HOURLY_QUOTA_EXCEEDED', retryAfterSeconds: 600 };
    }
    if (lastDay + params.requestedEvents > policy.incidentsPerDay) {
      return { allowed: false, policy, reason: 'DAILY_QUOTA_EXCEEDED', retryAfterSeconds: 3600 };
    }

    for (const deviceId of params.deviceIds.slice(0, 5)) {
      const clean = deviceId.trim();
      if (!clean) continue;
      const deviceCount = await this.prisma.guardianIncident.count({
        where: { companyId: params.companyId, deviceId: clean, receivedAt: { gte: dayStart } },
      });
      if (deviceCount + params.requestedEvents > policy.deviceIncidentsPerDay) {
        return {
          allowed: false,
          policy,
          reason: 'DEVICE_QUOTA_EXCEEDED',
          retryAfterSeconds: 3600,
        };
      }
    }

    return { allowed: true, policy };
  }
}
