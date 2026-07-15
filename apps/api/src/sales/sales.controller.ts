import { Body, Controller, Delete, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { SalesService } from './sales.service';
import { CreateSaleDto } from './dto/create-sale.dto';
import { SalesRangeQueryDto } from './dto/sales-range-query.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('sales')
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Get()
  listMine(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as { id: string; role: string };
    return this.sales.listMine(user.id, query.from, query.to, query.customerId, query.includeDeleted === 'true');
  }

  @Get('invoices')
  listInvoices(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as { id: string; role: Role };
    return this.sales.listInvoices(user, query.from, query.to, query.customerId, query.includeDeleted === 'true');
  }

  @Get('summary')
  summaryMine(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as { id: string; role: string };
    return this.sales.summaryMine(user.id, query.from, query.to, query.customerId);
  }

  @Post()
  create(@Req() req: Request, @Body() dto: CreateSaleDto) {
    const user = req.user as { id: string; role: string };
    return this.sales.create(user.id, dto);
  }

  @Delete('debug/purge')
  @Roles(Role.ADMIN)
  purgeAllForDebug(@Req() req: Request) {
    const user = req.user as { id: string; role: string };
    return this.sales.purgeAllForDebug(user);
  }

  @Delete(':id')
  remove(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: string };
    return this.sales.remove(user.id, id);
  }

  @Post(':id/return')
  returnSale(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.sales.returnSale(user, id);
  }
}
