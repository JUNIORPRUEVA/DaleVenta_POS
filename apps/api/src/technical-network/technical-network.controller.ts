import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Patch,
  Post,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import type { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { TechnicalNetworkService } from './technical-network.service';

type AuthRequest = Request & { user?: { id?: string; role?: Role } };

@Controller('technical-network')
export class TechnicalNetworkController {
  constructor(private readonly service: TechnicalNetworkService) {}

  @Get('public-form')
  @Header('Content-Type', 'text/html; charset=utf-8')
  publicForm() {
    return this.service.publicFormHtml();
  }

  @Post('public/applications')
  submitPublicApplication(@Body() dto: Record<string, unknown>) {
    return this.service.submitApplication(dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Get('summary')
  summary() {
    return this.service.summary();
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Get('applications')
  applications() {
    return this.service.listApplications();
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Get('technicians')
  technicians() {
    return this.service.listTechnicians();
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Patch('applications/:id/status')
  updateApplicationStatus(
    @Req() req: AuthRequest,
    @Param('id') id: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.updateApplicationStatus(this.userId(req), id, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('applications/:id/approve')
  approve(@Req() req: AuthRequest, @Param('id') id: string) {
    return this.service.approveApplication(this.userId(req), id);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('technicians')
  createTechnician(@Req() req: AuthRequest, @Body() dto: Record<string, unknown>) {
    return this.service.createTechnician(this.userId(req), dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Patch('technicians/:id')
  updateTechnician(
    @Param('id') id: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.updateTechnician(id, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('technicians/:id/jobs')
  addJob(
    @Req() req: AuthRequest,
    @Param('id') technicianId: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.addJob(this.userId(req), technicianId, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('technicians/:id/evaluations')
  addEvaluation(
    @Req() req: AuthRequest,
    @Param('id') technicianId: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.addEvaluation(this.userId(req), technicianId, dto);
  }

  private userId(req: AuthRequest) {
    const id = req.user?.id;
    if (!id) throw new UnauthorizedException('Usuario no autenticado');
    return id;
  }
}
