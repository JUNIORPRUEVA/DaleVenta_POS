import {
  BadRequestException,
  Body,
  Controller,
  HttpCode,
  Post,
  Req,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Request } from 'express';
import { resolveGuardianConfig } from './guardian.config';
import { GuardianEnrollmentDto } from './dto/guardian-enrollment.dto';
import { GuardianEnrollmentService } from './guardian.enrollment.service';

/**
 * Enrolamiento de instalaciones (público, autenticado por código de un solo uso).
 *
 * - No usa JWT: una instalación recién abierta no tiene sesión de usuario.
 * - No acepta `companyId`: la empresa sale del código.
 * - Fail-closed: si la ingesta está deshabilitada, el enrolamiento tampoco existe.
 * - La respuesta incluye la credencial **una sola vez**; no se puede recuperar
 *   después (solo se almacena su hash).
 */
@Controller('guardian/installations')
export class GuardianEnrollmentController {
  constructor(private readonly enrollment: GuardianEnrollmentService) {}

  @Post('enroll')
  @HttpCode(201)
  async enroll(@Req() req: Request, @Body() dto: GuardianEnrollmentDto) {
    const config = resolveGuardianConfig();
    if (!config.ingestEnabled) {
      throw new ServiceUnavailableException({
        code: 'GUARDIAN_INGEST_DISABLED',
        message: 'Guardian no está habilitado para recibir instalaciones',
      });
    }

    const outcome = await this.enrollment.enroll({
      code: dto.code,
      installId: dto.installId,
      platform: dto.platform ?? null,
      appVersion: dto.appVersion ?? null,
      ip: req.ip ?? null,
    });

    if (!outcome.ok) {
      throw new BadRequestException({ code: outcome.code, message: outcome.message });
    }

    return {
      installId: outcome.installId,
      credential: outcome.credential,
      expiresAt: outcome.expiresAt,
      ingestPath: '/guardian/machine/incidents',
    };
  }
}
