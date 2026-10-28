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
import { Request } from 'express';
import { resolveGuardianConfig } from './guardian.config';
import { GuardianIngestBatchDto } from './dto/guardian-ingest.dto';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianMachineGuard } from './guardian.machine.guard';
import { GuardianMachineIdentity, GuardianMachineService } from './guardian.machine.service';

type MachineRequest = Request & {
  guardianMachine?: GuardianMachineIdentity;
  requestId?: string;
};

/**
 * Ingesta de telemetría servidor a servidor (DaleVentas POS → Guardian).
 *
 * Diferencias deliberadas con `GuardianIngestController` (que exige JWT de
 * usuario):
 * - Autenticación por credencial de máquina (`GuardianMachineGuard`).
 * - La empresa se toma de la credencial. El DTO no admite `companyId`, así que
 *   un cliente no puede declarar incidentes de otra empresa ni por error ni a
 *   propósito (`forbidNonWhitelisted` lo rechaza con 400).
 * - No ejecuta IA ni envía WhatsApp: solo persiste y planifica la alerta, igual
 *   que la ruta autenticada por usuario.
 */
@UseGuards(GuardianMachineGuard)
@Controller('guardian/machine')
export class GuardianMachineController {
  constructor(
    private readonly ingest: GuardianIngestService,
    private readonly machine: GuardianMachineService,
  ) {}

  @Post('incidents')
  @HttpCode(202)
  async ingestBatch(@Req() req: MachineRequest, @Body() dto: GuardianIngestBatchDto) {
    const config = resolveGuardianConfig();
    if (!config.ingestEnabled) {
      throw new ServiceUnavailableException({
        code: 'GUARDIAN_INGEST_DISABLED',
        message: 'Guardian no está habilitado para recibir incidentes',
      });
    }

    const identity = req.guardianMachine;
    if (!identity) {
      // No debería ocurrir con el guard activo; se protege igualmente.
      throw new ServiceUnavailableException({ code: 'MACHINE_IDENTITY_REQUIRED' });
    }

    const events = dto?.events ?? [];
    if (!events.length) {
      throw new BadRequestException({ code: 'EVENTS_REQUIRED', message: 'events es requerido' });
    }

    const outcome = await this.ingest.ingestBatch({
      companyId: identity.companyId,
      userId: null,
      events,
      requestId: req.requestId ?? null,
    });

    void this.machine.recordUsage({
      identity,
      ip: req.ip ?? null,
      requestId: req.requestId ?? null,
      acceptedEvents: outcome.accepted,
      totalEvents: events.length,
    });

    return outcome;
  }
}
