import { Body, Controller, Delete, Get, Headers, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { type TenantUser } from '../auth/tenant-context';
import { LicenseService } from './license.service';

@Controller('license')
export class LicenseController {
  constructor(private readonly licenses: LicenseService) {}

  @UseGuards(AuthGuard('jwt'))
  @Get()
  getMyLicense(@Req() req: Request) {
    return this.licenses.getMyLicense(req.user as TenantUser);
  }

  @UseGuards(AuthGuard('jwt'))
  @Post('activate')
  activateMyLicense(@Req() req: Request, @Body() dto: Record<string, unknown>) {
    return this.licenses.activateMyLicense(req.user as TenantUser, dto);
  }

  @UseGuards(AuthGuard('jwt'))
  @Post('block')
  blockMyLicense(@Req() req: Request, @Body() dto: Record<string, unknown>) {
    return this.licenses.blockMyLicense(req.user as TenantUser, dto);
  }

  @UseGuards(AuthGuard('jwt'))
  @Patch('limits')
  updateMyLimits(@Req() req: Request, @Body() dto: Record<string, unknown>) {
    return this.licenses.updateMyLimits(req.user as TenantUser, dto);
  }

  @Get('admin/companies')
  async listCompanies(
    @Query() query: Record<string, unknown>,
    @Headers('x-license-admin-secret') secret?: string | string[],
  ) {
    await this.licenses.assertAdminSecret(secret);
    return this.licenses.listAdminCompanies(query);
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

  private withActor(dto: Record<string, unknown>, actor?: string | string[]) {
    const actorEmail = Array.isArray(actor) ? actor[0] : actor;
    return { ...dto, actorEmail };
  }
}
