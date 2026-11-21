import { Body, Controller, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { Role } from '@prisma/client';
import { TenantUser } from '../auth/tenant-context';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { RecoveryReviewService } from './recovery-review.service';
import { RecoveryDecisionDto, SubmitRecoveryReviewDto } from './recovery-review.dto';
@UseGuards(AuthGuard('jwt'),RolesGuard)
@Controller('recovery/reviews')
export class RecoveryReviewController {
  constructor(private readonly service:RecoveryReviewService) {}
  @Roles(Role.ADMIN)
  @Get() list(@Req() req:Request,@Query('cursor') cursor?:string){return this.service.list(req.user as TenantUser,cursor);}
  @Post() submit(@Req() req:Request,@Body() body:SubmitRecoveryReviewDto){return this.service.submit(req.user as TenantUser,body);}
  @Roles(Role.ADMIN)
  @Get(':id') detail(@Req() req:Request,@Param('id') id:string){return this.service.detail(req.user as TenantUser,id);}
  @Roles(Role.ADMIN)
  @Post(':id/verify') verify(@Req() req:Request,@Param('id') id:string){return this.service.verify(req.user as TenantUser,id);}
  @Roles(Role.ADMIN)
  @Post(':id/decision') decide(@Req() req:Request,@Param('id') id:string,@Body() body:RecoveryDecisionDto){return this.service.decide(req.user as TenantUser,id,body);}
}
