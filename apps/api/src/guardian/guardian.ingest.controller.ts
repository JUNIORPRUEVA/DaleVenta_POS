import {
  BadRequestException,
  Body,
  Controller,
  HttpCode,
  Post,
  Req,
  ServiceUnavailableException,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { resolveGuardianConfig } from './guardian.config';
import { GuardianIngestBatchDto } from './dto/guardian-ingest.dto';
import { GuardianIngestService } from './guardian.ingest.service';

type GuardianRequestUser = { id: string; role: Role; companyId?: string | null };

/**
 * Recepción de incidentes del cliente (POS).
 *
 * - La empresa se toma SIEMPRE de `req.user.companyId` (sesión JWT verificada).
 * - No se ejecuta IA ni se envía WhatsApp en esta petición: solo se persiste.
 */
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('guardian')
export class GuardianIngestController {
  constructor(private readonly ingest: GuardianIngestService) {}

  @Post('incidents')
  @HttpCode(202)
  @Roles(Role.ADMIN, Role.CAJERO, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  async ingestBatch(@Req() req: Request, @Body() dto: GuardianIngestBatchDto) {
    const config = resolveGuardianConfig();
    if (!config.ingestEnabled) {
      throw new ServiceUnavailableException({
        code: 'GUARDIAN_INGEST_DISABLED',
        message: 'Guardian no está habilitado para recibir incidentes',
      });
    }

    const user = req.user as GuardianRequestUser | undefined;
    const companyId = (user?.companyId ?? '').trim();
    if (!companyId) {
      throw new BadRequestException({
        code: 'COMPANY_REQUIRED',
        message: 'La sesión no tiene una empresa activa',
      });
    }

    const events = dto?.events ?? [];
    if (!events.length) {
      throw new BadRequestException({ code: 'EVENTS_REQUIRED', message: 'events es requerido' });
    }

    const requestId = (req as Request & { requestId?: string }).requestId ?? null;

    return this.ingest.ingestBatch({
      companyId,
      userId: user?.id ?? null,
      events,
      requestId,
    });
  }
}
