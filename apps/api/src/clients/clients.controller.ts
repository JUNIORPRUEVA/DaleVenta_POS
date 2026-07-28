import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UnauthorizedException, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { ClientsService } from './clients.service';
import { CreateClientDto } from './dto/create-client.dto';
import { ClientTimelineQueryDto } from './dto/client-timeline-query.dto';
import { ClientsQueryDto } from './dto/clients-query.dto';
import { UpdateClientLocationDto } from './dto/update-client-location.dto';
import { UpdateClientDto } from './dto/update-client.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('clients')
export class ClientsController {
  constructor(private readonly clients: ClientsService) {}

  private userOrThrow(req: Request) {
    const user =
      req.user as { id?: string; role?: Role; companyId?: string | null } | undefined;
    if (!user?.id || !user.role) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return { id: user.id, role: user.role, companyId: user.companyId ?? null };
  }

  @Post()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  create(@Req() req: Request, @Body() dto: CreateClientDto) {
    return this.clients.create(this.userOrThrow(req), dto);
  }

  @Get()
  findAll(@Req() req: Request, @Query() query: ClientsQueryDto) {
    return this.clients.findAll(this.userOrThrow(req), query);
  }

  @Get(':id/profile')
  profile(@Req() req: Request, @Param('id') id: string) {
    return this.clients.getProfile(this.userOrThrow(req), id);
  }

  @Get(':id/timeline')
  timeline(@Req() req: Request, @Param('id') id: string, @Query() query: ClientTimelineQueryDto) {
    return this.clients.getTimeline(this.userOrThrow(req), id, query);
  }

  @Get(':id')
  findOne(@Req() req: Request, @Param('id') id: string) {
    return this.clients.findOne(this.userOrThrow(req), id);
  }

  @Patch(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateClientDto) {
    return this.clients.update(this.userOrThrow(req), id, dto);
  }

  @Patch(':id/location')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  updateLocation(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateClientLocationDto) {
    return this.clients.updateLocation(this.userOrThrow(req), id, dto);
  }

  @Delete('debug/purge')
  @Roles(Role.ADMIN)
  purgeAllForDebug(@Req() req: Request) {
    return this.clients.purgeAllForDebug(this.userOrThrow(req));
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  remove(@Req() req: Request, @Param('id') id: string) {
    return this.clients.remove(this.userOrThrow(req), id);
  }
}
