import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Headers,
  HttpCode,
  NotFoundException,
  Post,
  Req,
  ServiceUnavailableException,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { RolesGuard } from '../auth/roles.guard';
import { GuardianAutoEnrollmentService } from './guardian.auto-enrollment.service';
import { GuardianEnrollmentGrantDto } from './dto/guardian-enrollment-grant.dto';
import { resolveGuardianConfig } from './guardian.config';

type GuardianSessionUser = { id?: string; role?: Role; companyId?: string | null };

/**
 * Auto-enrolamiento autenticado.
 *
 * Diferencia clave con `POST /guardian/installations/enroll`: aquí **sí** hay
 * sesión de usuario, así que la empresa se resuelve desde el JWT y nunca desde
 * el cuerpo de la petición. Lo que se emite es una autorización de vida corta
 * (código de un solo uso); la credencial de instalación se obtiene después en el
 * endpoint de canje, que sigue siendo el único que emite claves.
 */
@Controller('guardian/installations')
export class GuardianAutoEnrollmentController {
  constructor(private readonly autoEnrollment: GuardianAutoEnrollmentService) {}

  @Post('enrollment-grant')
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @HttpCode(201)
  async grant(
    @Req() req: Request,
    @Body() dto: GuardianEnrollmentGrantDto,
    @Headers('x-guardian-platform-token') platformHeader?: string,
  ) {
    const config = resolveGuardianConfig();
    if (!config.ingestEnabled) {
      throw new ServiceUnavailableException({
        code: 'GUARDIAN_INGEST_DISABLED',
        message: 'Guardian no está habilitado para recibir instalaciones',
      });
    }

    // El token de plataforma NUNCA se acepta aquí: esta ruta existe para que una
    // instalación se enrolé con la identidad de su propia empresa. Permitir el
    // token de plataforma abriría la puerta a enrolar instalaciones ajenas.
    if (String(platformHeader ?? '').trim()) {
      throw new ForbiddenException({
        code: 'PLATFORM_TOKEN_NOT_ALLOWED',
        message: 'Este endpoint solo admite la sesión de la empresa',
      });
    }

    const user = req.user as GuardianSessionUser | undefined;
    const companyId = String(user?.companyId ?? '').trim();
    if (!user?.id) {
      throw new UnauthorizedException({
        code: 'SESSION_REQUIRED',
        message: 'La sesión no es válida',
      });
    }
    if (!companyId) {
      throw new BadRequestException({
        code: 'COMPANY_REQUIRED',
        message: 'La sesión no tiene una empresa activa',
      });
    }

    const outcome = await this.autoEnrollment.requestGrant({
      companyId,
      actorUserId: user.id,
      actorRole: user.role ? String(user.role) : null,
      installId: dto.installId,
      platform: dto.platform ?? null,
      appVersion: dto.appVersion ?? null,
      ip: req.ip ?? null,
    });

    if (!outcome.ok) {
      switch (outcome.code) {
        case 'COMPANY_NOT_FOUND':
          throw new NotFoundException({ code: outcome.code, message: outcome.message });
        case 'COMPANY_NOT_ALLOWED':
        case 'COMPANY_NOT_ELIGIBLE':
        case 'COMPANY_GUARDIAN_DISABLED':
        case 'AUTO_ENROLLMENT_DISABLED':
          throw new ForbiddenException({ code: outcome.code, message: outcome.message });
        case 'ENROLLMENT_RATE_LIMITED':
          throw new BadRequestException({ code: outcome.code, message: outcome.message });
        default:
          throw new BadRequestException({ code: outcome.code, message: outcome.message });
      }
    }

    return {
      code: outcome.code,
      expiresAt: outcome.expiresAt,
      enrollPath: '/guardian/installations/enroll',
    };
  }
}
