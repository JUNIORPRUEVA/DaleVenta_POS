import { Body, Controller, Get, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { type TenantUser } from '../auth/tenant-context';
import { SettingsService } from './settings.service';

@UseGuards(AuthGuard('jwt'))
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
  verifyAdminPin(@Req() req: Request, @Body() dto: { pin?: unknown }) {
    return this.settings.verifyAdminPin(req.user as TenantUser, dto.pin);
  }
}
