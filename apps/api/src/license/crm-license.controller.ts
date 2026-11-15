import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { CrmLicenseService } from './crm-license.service';
import { LicenseService } from './license.service';

/** Separate from legacy admin and client routes; only the existing private bridge authenticates here. */
@Controller('license/integrations/crm')
export class CrmLicenseController {
  constructor(private readonly licenses: LicenseService, private readonly crm: CrmLicenseService) {}
  @Get('capabilities')
  async capabilities(@Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return { licenseRead: true, licenseWrite: this.crm.enabled(), bankTransfers: false };
  }
  @Get('companies')
  async list(@Query() query: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.list(query);
  }
  @Post(':companyId/commands')
  async command(@Param('companyId') id: string, @Body() body: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.command(id, body);
  }
  @Get('companies/:companyId')
  async detail(@Param('companyId') id: string, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.detail(id);
  }
}
