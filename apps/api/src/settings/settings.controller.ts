import { Body, Controller, Get, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { RolesGuard } from '../auth/roles.guard';
import { type TenantUser } from '../auth/tenant-context';
import { SettingsService } from './settings.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('settings')
export class SettingsController {
  constructor(private readonly settings: SettingsService) {}

  @Get()
  getSettings(@Req() req: Request) {
    return this.settings.getSettings(req.user as TenantUser);
  }

  @Patch()
  updateSettings(@Req() req: Request, @Body() dto: Record<string, unknown>) {
    return this.settings.updateSettings(req.user as TenantUser, dto);
  }

  @Post('admin-pin')
  setAdminPin(@Req() req: Request, @Body() dto: { pin?: unknown }) {
    return this.settings.setAdminPin(req.user as TenantUser, dto.pin);
  }

  @Post('admin-pin/verify')
  verifyAdminPin(
    @Req() req: Request,
    @Body() dto: { pin?: unknown; scope?: unknown; scopes?: unknown },
  ) {
    const user = req.user as TenantUser & { requestedScopes?: unknown };
    user.requestedScopes = dto.scopes ?? dto.scope;
    return this.settings.verifyAdminPin(user, dto.pin);
  }
}
