import { Body, Controller, Delete, Get, Headers, Param, Patch, Post, Query, Req, StreamableFile, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { Request } from 'express';
import { RolesGuard } from '../auth/roles.guard';
import { type TenantUser } from '../auth/tenant-context';
import { LicenseService } from './license.service';
import { LicensePlansService } from './plans/license-plans.service';
import { LicenseOrdersService } from './orders/license-orders.service';
import { MAX_EVIDENCE_BYTES } from './orders/license-evidence.storage';
import { LicensePlanRequestService } from './renewal/license-plan-request.service';

@Controller('license')
export class LicenseController {
  constructor(
    private readonly licenses: LicenseService,
    private readonly plans: LicensePlansService,
    private readonly orders: LicenseOrdersService,
    private readonly planRequests: LicensePlanRequestService,
  ) {}

  /**
   * Catálogo vigente de planes. Público a propósito: la landing y la pantalla
   * Planes deben mostrar los mismos precios, que salen del servidor.
   */
  @Get('plans')
  listPlans() {
    return this.plans.listPublic();
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Get()
  getMyLicense(@Req() req: Request) {
    return this.licenses.getMyLicense(req.user as TenantUser);
  }

  /**
   * Datos de la cuenta bancaria unica. Si el propietario no los configuro, la
   * respuesta dice `configured:false` y la app manda a soporte: nunca se
   * inventan numeros de cuenta.
   */
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Get('payment-instructions')
  paymentInstructions() {
    return this.orders.paymentInstructions();
  }

  /** Acceso efectivo (FULL/RESTRICTED/BLOCKED) segun la licencia. */
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Get('access')
  getAccess(@Req() req: Request) {
    const user = req.user as TenantUser & { licenseAccess?: unknown };
    return { access: user.licenseAccess ?? null };
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Post('orders')
  createOrder(@Req() req: Request, @Body() dto: Record<string, unknown>) {
    return this.orders.createOrder(req.user as TenantUser, dto);
  }

  /**
   * Ticket de soporte para ampliar plan cuando la empresa ya esta en el plan
   * mas alto. No cambia la licencia: la decide soporte desde el CRM.
   */
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Post('plan-requests')
  createPlanRequest(@Req() req: Request, @Body() dto: Record<string, unknown>) {
    return this.planRequests.create(req.user as TenantUser, dto);
  }

  /** Ticket de mejora ya abierto, para no ofrecer «solicitar» dos veces. */
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Get('plan-requests')
  getPlanRequest(@Req() req: Request) {
    return this.planRequests.myOpen(req.user as TenantUser);
  }

  /**
   * Lo que se debe transferir hoy por ese plan y esos meses. Si el cliente
   * cambia de plan, descuenta los dias que aun no ha consumido.
   */
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Get('orders/quote')
  quoteOrder(@Req() req: Request, @Query() query: Record<string, unknown>) {
    return this.orders.quote(req.user as TenantUser, query);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Get('orders')
  listOrders(@Req() req: Request) {
    return this.orders.listOrders(req.user as TenantUser);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Post('orders/:id/cancel')
  cancelOrder(@Req() req: Request, @Param('id') id: string) {
    return this.orders.cancelOrder(req.user as TenantUser, id);
  }

  /**
   * Sube el comprobante y activa la licencia al instante. El archivo se valida
   * por firma real (no por extension) y se guarda en almacenamiento privado.
   */
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Post('orders/:id/evidence')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: MAX_EVIDENCE_BYTES },
    }),
  )
  uploadEvidence(
    @Req() req: Request,
    @Param('id') id: string,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.orders.uploadEvidence(req.user as TenantUser, id, file);
  }

  /** Descarga privada del comprobante: solo para la empresa dueña. */
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Get('orders/:id/evidence/:evidenceId')
  async downloadEvidence(
    @Req() req: Request,
    @Param('id') id: string,
    @Param('evidenceId') evidenceId: string,
  ) {
    const { evidence, buffer } = await this.orders.getEvidence(
      req.user as TenantUser,
      id,
      evidenceId,
    );
    return new StreamableFile(buffer, {
      type: evidence.mime,
      disposition: `inline; filename="${safeFileName(evidence.originalName)}"`,
    });
  }

  // AQUI ESTABAN `POST /license/activate`, `POST /license/block` y
  // `PATCH /license/limits` (autoservicio del propietario). Se quitaron a
  // proposito: permitian activar la licencia o subirse el cupo y la fecha sin
  // pagar, saltandose el catalogo, la orden y el comprobante. La unica via para
  // cambiar una licencia es el flujo de planes; el equipo lo hace con
  // `POST /license/admin/:companyId/activate` y el puente del CRM, ambos con
  // `x-license-admin-secret`.

  @Get('admin/companies')
  async listCompanies(
    @Query() query: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.listAdminCompanies(query);
  }

  /**
   * Abre la **demo de 7 dias** a una empresa nueva que se creo fuera de la app
   * (CRM o alta manual). Es la unica forma de iniciar una prueba sin registro,
   * la empresa solo puede tener una y queda auditado con su actor.
   */
  @Post('admin/:companyId/trial')
  async startTrial(
    @Param('companyId') companyId: string,
    @Headers('x-license-admin-secret') secret?: string | string[],
    @Headers('x-license-admin-actor') actor?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    const actorEmail = Array.isArray(actor) ? actor[0] : actor;
    return this.licenses.ensureTrialForCompany(companyId, actorEmail);
  }

  @Get('admin/:companyId/usage')
  async getCompanyUsage(
    @Param('companyId') companyId: string,
    @Headers('x-license-admin-secret') secret?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.getAdminCompanyUsage(companyId);
  }

  @Get('admin/:companyId')
  async getCompany(
    @Param('companyId') companyId: string,
    @Headers('x-license-admin-secret') secret?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.getAdminCompany(companyId);
  }

  @Post('admin/:companyId/activate')
  async activateCompany(
    @Param('companyId') companyId: string,
    @Body() dto: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string | string[],
    @Headers('x-license-admin-actor') actor?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.activateCompany(companyId, this.withActor(dto, actor));
  }

  @Post('admin/:companyId/block')
  async blockCompany(
    @Param('companyId') companyId: string,
    @Body() dto: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string | string[],
    @Headers('x-license-admin-actor') actor?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.blockCompany(companyId, this.withActor(dto, actor));
  }

  @Patch('admin/:companyId')
  async updateCompany(
    @Param('companyId') companyId: string,
    @Body() dto: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string | string[],
    @Headers('x-license-admin-actor') actor?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.updateCompanyLicense(companyId, this.withActor(dto, actor));
  }

  @Delete('admin/:companyId')
  async deleteCompanyLicense(
    @Param('companyId') companyId: string,
    @Body() dto: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string | string[],
    @Headers('x-license-admin-actor') actor?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.deleteCompanyLicense(companyId, this.withActor(dto ?? {}, actor));
  }

  @Delete('admin/:companyId/permanent')
  async permanentlyDeleteCompanyLicense(
    @Param('companyId') companyId: string,
    @Body() dto: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string | string[],
    @Headers('x-license-admin-actor') actor?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.permanentlyDeleteCompanyLicense(companyId, this.withActor(dto ?? {}, actor));
  }

  private withActor(dto: Record<string, unknown>, actor?: string | string[]) {
    const actorEmail = Array.isArray(actor) ? actor[0] : actor;
    return { ...dto, actorEmail };
  }
}

/** El nombre original lo sube el cliente: se limpia antes de ir en cabecera. */
function safeFileName(value: string) {
  return (value || 'comprobante')
    .replace(/[^\w.\- ]+/g, '_')
    .slice(0, 120);
}
