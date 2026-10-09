import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Permissions, Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import {
  CloneServiceOrderDto,
  CreateServiceEvidenceDto,
  CreateServiceOrderDto,
  CreateServiceReportDto,
  UpdateServiceOrderDto,
  UpdateServiceOrderStatusDto,
} from './dto/service-order.dto';
import {
  ServiceOrdersQueryDto,
  ServiceOrdersSyncQueryDto,
} from './dto/service-orders-query.dto';
import { ServiceOrdersService } from './service-orders.service';

type RequestUser = {
  id: string;
  role: Role;
  companyId?: string | null;
};

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('service-orders')
export class ServiceOrdersController {
  constructor(private readonly serviceOrders: ServiceOrdersService) {}

  @Get()
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  list(@Req() req: Request, @Query() query: ServiceOrdersQueryDto) {
    return this.serviceOrders.list(req.user as RequestUser, query);
  }

  @Get('sync')
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  sync(@Req() req: Request, @Query() query: ServiceOrdersSyncQueryDto) {
    return this.serviceOrders.sync(req.user as RequestUser, query);
  }

  @Post()
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  create(@Req() req: Request, @Body() dto: CreateServiceOrderDto) {
    return this.serviceOrders.create(req.user as RequestUser, dto);
  }

  @Delete('debug/purge')
  @Roles(Role.ADMIN)
  purgeAllForDebug(@Req() req: Request) {
    return this.serviceOrders.purgeAllForDebug(req.user as RequestUser);
  }

  @Get(':id')
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  getOne(@Req() req: Request, @Param('id') id: string) {
    return this.serviceOrders.getOne(req.user as RequestUser, id);
  }

  @Patch(':id')
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  update(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: UpdateServiceOrderDto,
  ) {
    return this.serviceOrders.update(req.user as RequestUser, id, dto);
  }

  @Delete(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  remove(@Req() req: Request, @Param('id') id: string) {
    return this.serviceOrders.delete(req.user as RequestUser, id);
  }

  @Post(':id/clone')
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  clone(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CloneServiceOrderDto,
  ) {
    return this.serviceOrders.clone(req.user as RequestUser, id, dto);
  }

  @Patch(':id/status')
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  updateStatus(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: UpdateServiceOrderStatusDto,
  ) {
    return this.serviceOrders.updateStatus(
      req.user as RequestUser,
      id,
      dto.status,
      dto.scheduledAt ?? dto.scheduled_at,
    );
  }

  @Post(':id/evidences')
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  addEvidence(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateServiceEvidenceDto,
  ) {
    return this.serviceOrders.addEvidence(req.user as RequestUser, id, dto);
  }

  @Post(':id/report')
  @Permissions('viewQuotes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  addReport(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateServiceReportDto,
  ) {
    return this.serviceOrders.addReport(req.user as RequestUser, id, dto);
  }
}
