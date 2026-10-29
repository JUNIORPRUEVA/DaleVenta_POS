import {
  BadRequestException,
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { GuardianIncidentStatus, GuardianSeverity } from '@prisma/client';
import { GuardianPlatformGuard } from './guardian.platform.guard';
import { GuardianPlatformService } from './guardian.platform.service';

/**
 * API del panel Appyra (plataforma).
 *
 * Autenticación exclusiva por `x-guardian-platform-token`. Los endpoints de
 * lectura agregan datos de todas las empresas; las acciones administrativas
 * quedan auditadas en `guardian_access_logs` con rol PLATFORM.
 */
@UseGuards(GuardianPlatformGuard)
@Controller('guardian/platform')
export class GuardianPlatformController {
  constructor(private readonly platform: GuardianPlatformService) {}

  @Get('health')
  health() {
    return this.platform.health();
  }

  @Get('summary')
  summary() {
    return this.platform.summary();
  }

  @Get('companies')
  async companies() {
    return { companies: await this.platform.companies() };
  }

  /**
   * Fase 7 — activación de Guardian por empresa.
   *
   * Solo accesible con el token de plataforma (GuardianPlatformGuard): ni un
   * usuario de empresa ni una credencial de máquina pueden activarlo. El
   * historial existente nunca se borra al desactivar.
   */
  @Post('companies/:companyId/guardian')
  async setCompanyGuardian(
    @Param('companyId') companyId: string,
    @Body() body: { enabled?: boolean },
  ) {
    if (typeof body?.enabled !== 'boolean') {
      throw new BadRequestException('`enabled` debe ser booleano');
    }
    const company = await this.platform.setCompanyGuardianEnabled(companyId, body.enabled);
    if (!company) throw new NotFoundException('Empresa no encontrada');
    return { company };
  }

  /**
   * Fase 10 — revocación de una credencial de instalación.
   *
   * Sólo con el token de plataforma. Tras revocarla, la instalación ya no puede
   * ingerir telemetría; los incidentes y diagnósticos históricos se conservan.
   */
  @Post('credentials/:credentialId/revoke')
  async revokeCredential(@Param('credentialId') credentialId: string) {
    const credential = await this.platform.revokeMachineCredential(credentialId);
    if (!credential) throw new NotFoundException('Credencial no encontrada');
    return { credential };
  }

  @Get('workers')
  workers() {
    return this.platform.workers();
  }

  @Get('incidents')
  async list(
    @Query('companyId') companyId?: string,
    @Query('status') status?: string,
    @Query('severity') severity?: string,
    @Query('module') module?: string,
    @Query('platform') platform?: string,
    @Query('appVersion') appVersion?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.platform.list({
      companyId: companyId?.trim() || undefined,
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
  }

  @Get('incidents/:id')
  async detail(@Param('id') id: string) {
    const incident = await this.platform.detail(id);
    if (!incident) throw new NotFoundException('Incidente no encontrado');
    return incident;
  }

  @Post('incidents/:id/ack')
  act(@Param('id') id: string, @Body() body: { note?: string }) {
    return this.run(id, 'ack', body?.note);
  }

  @Post('incidents/:id/investigate')
  actInvestigate(@Param('id') id: string, @Body() body: { note?: string }) {
    return this.run(id, 'investigate', body?.note);
  }

  @Post('incidents/:id/resolve')
  actResolve(@Param('id') id: string, @Body() body: { note?: string }) {
    return this.run(id, 'resolve', body?.note);
  }

  @Post('incidents/:id/close')
  actClose(@Param('id') id: string, @Body() body: { note?: string }) {
    return this.run(id, 'close', body?.note);
  }

  @Post('incidents/:id/reopen')
  actReopen(@Param('id') id: string, @Body() body: { note?: string }) {
    return this.run(id, 'reopen', body?.note);
  }

  private async run(
    id: string,
    action: 'ack' | 'investigate' | 'resolve' | 'close' | 'reopen',
    note?: string,
  ) {
    const updated = await this.platform.act({ incidentId: id, action, note, actor: 'platform' });
    if (!updated) throw new NotFoundException('Incidente no encontrado');
    return updated;
  }

  private parseEnum<T extends Record<string, string>>(
    enumObject: T,
    raw: string | undefined,
  ): T[keyof T] | undefined {
    const value = String(raw ?? '').trim().toUpperCase();
    if (!value) return undefined;
    if (!(Object.values(enumObject) as string[]).includes(value)) {
      throw new BadRequestException({ code: 'INVALID_FILTER', message: `Valor no permitido: ${value}` });
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
