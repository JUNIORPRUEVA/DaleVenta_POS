import { Controller, Get, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { RolesGuard } from '../auth/roles.guard';
import { ReportsService } from './reports.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('reports')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  @Get('sales-overview')
  salesOverview(@Req() req: Request, @Query() query: Record<string, string>) {
    const user = req.user as { id: string; role: Role };
    return this.reports.salesOverview(user, query);
  }
}
