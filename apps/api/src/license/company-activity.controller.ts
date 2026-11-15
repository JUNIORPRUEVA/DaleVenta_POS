import { Body, Controller, Get, Headers, Param, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { CompanyActivityService } from './company-activity.service';
import { LicenseService } from './license.service';

@Controller('activity')
export class CompanyActivityController {
  constructor(private readonly activity:CompanyActivityService,private readonly licenses:LicenseService){}
  @UseGuards(AuthGuard('jwt'))
  @Post('pulse')
  pulse(@Req() req:Request,@Body() value:Record<string,unknown>){
    return this.activity.pulse(req.user as unknown as {companyId:string;sessionId:string},value);
  }
  @Get('admin/companies/:companyId')
  async report(@Param('companyId') id:string,@Headers('x-license-admin-secret') secret?:string){
    await this.licenses.assertAdminSecret(secret);
    return this.activity.report(id);
  }
}
