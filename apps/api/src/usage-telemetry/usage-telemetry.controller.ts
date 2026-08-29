import { Controller, ForbiddenException, Headers, Post } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { UsageTelemetryService } from './usage-telemetry.service';

@Controller('internal/usage-telemetry')
export class UsageTelemetryController {
  constructor(
    private readonly telemetry: UsageTelemetryService,
    private readonly config: ConfigService,
  ) {}

  @Post('flush')
  async flush(@Headers('x-license-admin-secret') secret?: string | string[]) {
    this.assertInternalSecret(secret);
    return this.telemetry.flushAllCompanies('manual');
  }

  private assertInternalSecret(rawSecret?: string | string[]) {
    const configured = (this.config.get<string>('LICENSE_ADMIN_SECRET') ?? '').trim();
    if (!configured) {
      throw new ForbiddenException('LICENSE_ADMIN_SECRET no esta configurado');
    }
    const received = Array.isArray(rawSecret) ? rawSecret[0] : rawSecret;
    if ((received ?? '').trim() !== configured) {
      throw new ForbiddenException('Secreto invalido');
    }
  }
}
