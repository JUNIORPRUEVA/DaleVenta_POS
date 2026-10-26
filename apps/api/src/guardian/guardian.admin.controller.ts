import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { GuardianIncidentStatus, GuardianSeverity, Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { PrismaService } from '../prisma/prisma.service';
import { GuardianIncidentsService } from './guardian.incidents.service';
import { resolveGuardianConfig } from './guardian.config';

type GuardianRequestUser = { id: string; role: Role; companyId?: string | null };

/**
 * Panel administrativo Guardian.
 *
 * Aislamiento: cada consulta se filtra por la empresa de la sesión. El token de
 * plataforma (`GUARDIAN_PLATFORM_TOKEN`) es opcional y solo permite elegir
 * `companyId` explícito; si no está configurado, es imposible ver otra empresa.
 */
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('guardian/admin')
export class GuardianAdminController {
  constructor(
    private readonly incidents: GuardianIncidentsService,
    private readonly prisma: PrismaService,
  ) {}

  private resolveCompanyId(req: Request, platformHeader?: string, requestedCompanyId?: string) {
    const user = req.user as GuardianRequestUser | undefined;
    const config = resolveGuardianConfig();
    const platformToken = String(platformHeader ?? '').trim();

    if (config.platformToken && platformToken && platformToken === config.platformToken) {
      const requested = String(requestedCompanyId ?? '').trim();
      if (!requested) {
        throw new BadRequestException({
          code: 'COMPANY_REQUIRED',
          message: 'companyId es requerido para el acceso de plataforma',
        });
      }
      return { companyId: requested, actorUserId: user?.id ?? null, actorRole: 'PLATFORM' };
    }

    const companyId = (user?.companyId ?? '').trim();
    if (!companyId) {
      throw new BadRequestException({
        code: 'COMPANY_REQUIRED',
        message: 'La sesión no tiene una empresa activa',
      });
    }
    return { companyId, actorUserId: user?.id ?? null, actorRole: user?.role ?? null };
  }

  private async audit(params: {
    action: string;
    actorUserId: string | null;
    actorRole: string | null;
    companyId: string;
    incidentId?: string | null;
    requestId?: string | null;
    ip?: string | null;
  }) {
    try {
      await this.prisma.guardianAccessLog.create({
        data: {
          action: params.action,
          actorUserId: params.actorUserId,
          actorRole: params.actorRole,
          companyId: params.companyId,
          incidentId: params.incidentId ?? null,
          requestId: params.requestId ?? null,
          ip: params.ip ?? null,
        },
      });
    } catch {
      // La auditoría nunca debe romper la consulta del panel.
    }
  }

  @Get('summary')
  @Roles(Role.ADMIN)
  async summary(
    @Req() req: Request,
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);
    return this.incidents.summary(scope.companyId);
  }

  @Get('health')
  @Roles(Role.ADMIN)
  async health(
    @Req() req: Request,
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);
    const now = Date.now();
    const dayAgo = new Date(now - 24 * 60 * 60 * 1000);

    const incidentIds = (
      await this.prisma.guardianIncident.findMany({
        where: { companyId: scope.companyId },
        select: { id: true },
        take: 5_000,
      })
    ).map((row) => row.id);

    const [lastIncident, lastAlert, incidents24h, pendingDiagnosis, pendingAlerts, deadAlerts] =
      await Promise.all([
        this.prisma.guardianIncident.findFirst({
          where: { companyId: scope.companyId },
          orderBy: { receivedAt: 'desc' },
          select: { receivedAt: true },
        }),
        this.prisma.guardianAlert.findFirst({
          where: { incidentId: { in: incidentIds }, sentAt: { not: null } },
          orderBy: { sentAt: 'desc' },
          select: { sentAt: true },
        }),
        this.prisma.guardianIncident.count({
          where: { companyId: scope.companyId, receivedAt: { gte: dayAgo } },
        }),
        this.prisma.guardianIncident.count({
          where: { companyId: scope.companyId, processingState: { in: ['PENDING', 'DIAGNOSING'] } },
        }),
        this.prisma.guardianAlert.count({
          where: { incidentId: { in: incidentIds }, state: { in: ['PENDING', 'SENDING'] } },
        }),
        this.prisma.guardianAlert.count({
          where: { incidentId: { in: incidentIds }, state: 'FAILED_PERMANENT' },
        }),
      ]);

    const lastIncidentAgeSeconds = lastIncident
      ? Math.floor((now - lastIncident.receivedAt.getTime()) / 1000)
      : null;

    return {
      guardianEnabled: resolveGuardianConfig().enabled,
      ingestEnabled: resolveGuardianConfig().ingestEnabled,
      diagnosisEnabled: resolveGuardianConfig().diagnosisEnabled,
      alertsEnabled: resolveGuardianConfig().alertsEnabled,
      whatsappCloudConfigured: Boolean(
        String(process.env.GUARDIAN_WA_CLOUD_TOKEN ?? '').trim() &&
          String(process.env.GUARDIAN_WA_PHONE_NUMBER_ID ?? '').trim(),
      ),
      fallbackWebhookConfigured: Boolean(
        String(process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL ?? '').trim(),
      ),
      lastIncidentAt: lastIncident?.receivedAt ?? null,
      lastIncidentAgeSeconds,
      lastAlertSentAt: lastAlert?.sentAt ?? null,
      incidentsLast24h: incidents24h,
      pendingDiagnosis,
      pendingAlerts,
      failedPermanentAlerts: deadAlerts,
      // Señal de "Guardian silencioso": si no hay incidentes en 24 h no es error,
      // pero si el cliente está activo y no llega nada, el panel lo muestra.
      silentWarning: lastIncidentAgeSeconds !== null && lastIncidentAgeSeconds > 24 * 60 * 60,
    };
  }

  @Get('incidents')
  @Roles(Role.ADMIN)
  async list(
    @Req() req: Request,
    @Query('status') status?: string,
    @Query('severity') severity?: string,
    @Query('module') module?: string,
    @Query('platform') platform?: string,
    @Query('appVersion') appVersion?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);

    const result = await this.incidents.list({
      companyId: scope.companyId,
      status: this.parseEnum(GuardianIncidentStatus, status),
      severity: this.parseEnum(GuardianSeverity, severity),
      module: module?.trim() || undefined,
      platform: platform?.trim() || undefined,
      appVersion: appVersion?.trim() || undefined,
      from: this.parseDate(from),
      to: this.parseDate(to),
      limit: limit ? Number.parseInt(limit, 10) : undefined,
      cursor: cursor?.trim() || undefined,
    });

    await this.audit({
      action: 'incident.list',
      actorUserId: scope.actorUserId,
      actorRole: scope.actorRole,
      companyId: scope.companyId,
      requestId: (req as Request & { requestId?: string }).requestId ?? null,
      ip: req.ip ?? null,
    });

    return result;
  }

  @Get('incidents/:id')
  @Roles(Role.ADMIN)
  async detail(
    @Req() req: Request,
    @Param('id') id: string,
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);
    const incident = await this.incidents.detail(scope.companyId, id);

    await this.audit({
      action: 'incident.view',
      actorUserId: scope.actorUserId,
      actorRole: scope.actorRole,
      companyId: scope.companyId,
      incidentId: id,
      requestId: (req as Request & { requestId?: string }).requestId ?? null,
      ip: req.ip ?? null,
    });

    return incident;
  }

  @Post('incidents/:id/ack')
  @Roles(Role.ADMIN)
  async acknowledge(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() body: { note?: string },
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);
    const result = await this.incidents.acknowledge({
      companyId: scope.companyId,
      incidentId: id,
      userId: scope.actorUserId,
      note: body?.note ?? null,
    });
    await this.audit({
      action: 'incident.ack',
      actorUserId: scope.actorUserId,
      actorRole: scope.actorRole,
      companyId: scope.companyId,
      incidentId: id,
      ip: req.ip ?? null,
    });
    return result;
  }

  @Post('incidents/:id/investigate')
  @Roles(Role.ADMIN)
  async investigate(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() body: { note?: string },
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);
    const result = await this.incidents.investigate({
      companyId: scope.companyId,
      incidentId: id,
      userId: scope.actorUserId,
      note: body?.note ?? null,
    });
    await this.audit({
      action: 'incident.investigate',
      actorUserId: scope.actorUserId,
      actorRole: scope.actorRole,
      companyId: scope.companyId,
      incidentId: id,
      ip: req.ip ?? null,
    });
    return result;
  }

  @Post('incidents/:id/resolve')
  @Roles(Role.ADMIN)
  async resolve(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() body: { note?: string },
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);
    const result = await this.incidents.resolve({
      companyId: scope.companyId,
      incidentId: id,
      userId: scope.actorUserId,
      note: body?.note ?? null,
    });
    await this.audit({
      action: 'incident.resolve',
      actorUserId: scope.actorUserId,
      actorRole: scope.actorRole,
      companyId: scope.companyId,
      incidentId: id,
      ip: req.ip ?? null,
    });
    return result;
  }

  @Post('incidents/:id/close')
  @Roles(Role.ADMIN)
  async close(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() body: { note?: string },
    @Headers('x-guardian-platform-token') platformToken?: string,
    @Query('companyId') requestedCompanyId?: string,
  ) {
    const scope = this.resolveCompanyId(req, platformToken, requestedCompanyId);
    const result = await this.incidents.close({
      companyId: scope.companyId,
      incidentId: id,
      userId: scope.actorUserId,
      note: body?.note ?? null,
    });
    await this.audit({
      action: 'incident.close',
      actorUserId: scope.actorUserId,
      actorRole: scope.actorRole,
      companyId: scope.companyId,
      incidentId: id,
      ip: req.ip ?? null,
    });
    return result;
  }

  private parseEnum<T extends Record<string, string>>(
    enumObject: T,
    raw: string | undefined,
  ): T[keyof T] | undefined {
    const value = String(raw ?? '').trim().toUpperCase();
    if (!value) return undefined;
    const values = Object.values(enumObject) as string[];
    if (!values.includes(value)) {
      throw new BadRequestException({
        code: 'INVALID_FILTER',
        message: `Valor no permitido: ${value}`,
      });
    }
    return value as T[keyof T];
  }

  private parseDate(raw: string | undefined): Date | undefined {
    const value = String(raw ?? '').trim();
    if (!value) return undefined;
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      throw new BadRequestException({ code: 'INVALID_DATE', message: `Fecha inválida: ${value}` });
    }
    return date;
  }
}
