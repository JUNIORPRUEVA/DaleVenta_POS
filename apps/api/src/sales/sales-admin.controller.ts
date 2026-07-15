import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { SalesRangeQueryDto } from './dto/sales-range-query.dto';
import { SalesService } from './sales.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/sales')
export class SalesAdminController {
  constructor(private readonly sales: SalesService) {}

  @Get()
  listByUser(@Query() query: SalesRangeQueryDto) {
    return this.sales.listByUser(query.userId ?? '', query.from, query.to, query.customerId, query.includeDeleted === 'true');
  }

  @Get('summary')
  summaryByUser(@Query() query: SalesRangeQueryDto) {
    return this.sales.summaryByUser(query.from, query.to, query.userId);
  }
}
