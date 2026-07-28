import { Controller, Get, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { TenantUser } from '../auth/tenant-context';
import { Request } from 'express';
import { SalesRangeQueryDto } from './dto/sales-range-query.dto';
import { SalesService } from './sales.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/sales')
export class SalesAdminController {
  constructor(private readonly sales: SalesService) {}

  @Get()
  listByUser(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    return this.sales.listByUser(req.user as TenantUser, query.userId ?? '', query.from, query.to, query.customerId, query.includeDeleted === 'true');
  }

  @Get('summary')
  summaryByUser(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    return this.sales.summaryByUser(req.user as TenantUser, query.from, query.to, query.userId);
  }
}
