import { Body, Controller, Delete, Get, Headers, Param, Post, Query, StreamableFile } from '@nestjs/common';
import { CrmLicenseService } from './crm-license.service';
import { LicenseService } from './license.service';
import { LicenseOrdersService } from './orders/license-orders.service';
import { LicensePlanRequestService } from './renewal/license-plan-request.service';

/** Separate from legacy admin and client routes; only the existing private bridge authenticates here. */
@Controller('license/integrations/crm')
export class CrmLicenseController {
  constructor(
    private readonly licenses: LicenseService,
    private readonly crm: CrmLicenseService,
    private readonly orders: LicenseOrdersService,
    private readonly planRequests: LicensePlanRequestService,
  ) {}
  @Get('capabilities')
  async capabilities(@Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return { licenseRead: true, licenseWrite: this.crm.enabled(), bankTransfers: false, payments: true, overrides: true };
  }
  @Get('companies')
  async list(@Query() query: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.list(query);
  }
  /** Ordenes de pago (pendientes de verificar incluidas) con su comprobante. */
  @Get('orders')
  async listOrders(@Query() query: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.orders(query);
  }
  /** Solicitudes de mejora de plan hechas por empresas que ya estan en el tope. */
  @Get('plan-requests')
  async listPlanRequests(@Query() query: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.planRequests.listAdmin(query);
  }
  @Post('plan-requests/:requestId/status')
  async setPlanRequestStatus(
    @Param('requestId') requestId: string,
    @Body() body: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string,
  ) {
    await this.licenses.assertAdminSecret(secret);
    const status = String(body.status ?? '').trim().toUpperCase() as
      | 'OPEN'
      | 'CONTACTED'
      | 'CLOSED';
    return this.planRequests.setStatus({ requestId, status, actor: 'crm' });
  }
  /**
   * Guarda lo que el agente leyo del comprobante (fecha, importe, banco,
   * referencia bancaria). Es apoyo para soporte: no aprueba ni activa nada.
   */
  @Post('orders/:orderId/evidence/:evidenceId/insights')
  async saveEvidenceInsights(
    @Param('orderId') orderId: string,
    @Param('evidenceId') evidenceId: string,
    @Body() body: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string,
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.orders.saveEvidenceInsights({ orderId, evidenceId, raw: body ?? {} });
  }
  @Get('orders/:orderId/evidence/:evidenceId')
  async downloadEvidence(
    @Param('orderId') orderId: string,
    @Param('evidenceId') evidenceId: string,
    @Headers('x-license-admin-secret') secret?: string,
  ) {
    await this.licenses.assertAdminSecret(secret);
    const { evidence, buffer } = await this.orders.getAdminEvidence(orderId, evidenceId);
    return new StreamableFile(buffer, {
      type: evidence.mime,
      disposition: `inline; filename="${(evidence.originalName || 'comprobante').replace(/[^\w.\- ]+/g, '_').slice(0, 120)}"`,
    });
  }
  @Post(':companyId/commands')
  async command(@Param('companyId') id: string, @Body() body: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.command(id, body);
  }
  /** Excepcion autorizada: mas cuotas o una funcion fuera del plan. */
  @Post('companies/:companyId/overrides')
  async override(@Param('companyId') id: string, @Body() body: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.override(id, body);
  }
  @Delete('companies/:companyId/overrides')
  async clearOverride(@Param('companyId') id: string, @Body() body: Record<string, unknown>, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.clearOverride(id, body ?? {});
  }
  @Get('companies/:companyId')
  async detail(@Param('companyId') id: string, @Headers('x-license-admin-secret') secret?: string) {
    await this.licenses.assertAdminSecret(secret);
    return this.crm.detail(id);
  }
}
