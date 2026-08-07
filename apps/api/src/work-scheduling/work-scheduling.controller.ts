import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { Role } from '@prisma/client';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { WorkSchedulingService } from './work-scheduling.service';
import { UpdateEmployeeConfigDto } from './dto/update-employee-config.dto';
import { UpsertScheduleProfileDto } from './dto/upsert-schedule-profile.dto';
import { UpsertCoverageRulesDto } from './dto/upsert-coverage-rules.dto';
import { GenerateWeekDto } from './dto/generate-week.dto';
import { ManualMoveDayOffDto, ManualSwapDayOffDto } from './dto/manual-change.dto';
import { AuditQueryDto } from './dto/audit-query.dto';
import { ReportsQueryDto } from './dto/reports-query.dto';
import { CreateWorkExceptionDto, UpdateWorkExceptionDto } from './dto/exceptions.dto';

type JwtUser = {
  id: string;
  role: Role;
  nombreCompleto?: string;
  companyId?: string | null;
};

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('work-scheduling')
export class WorkSchedulingController {
  constructor(private readonly scheduling: WorkSchedulingService) {}

  @Get('employees')
  @Roles(Role.ADMIN)
  listEmployees(@Req() req: Request) {
    return this.scheduling.listEmployees(req.user as JwtUser);
  }

  @Patch('employees/:id')
  @Roles(Role.ADMIN)
  updateEmployeeConfig(@Req() req: Request, @Param('id') userId: string, @Body() dto: UpdateEmployeeConfigDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.updateEmployeeConfig(
      userId,
      {
        enabled: dto.enabled,
        schedule_profile_id: dto.schedule_profile_id,
        preferred_day_off_weekday: dto.preferred_day_off_weekday,
        fixed_day_off_weekday: dto.fixed_day_off_weekday,
        disallowed_day_off_weekdays: dto.disallowed_day_off_weekdays,
        unavailable_weekdays: dto.unavailable_weekdays,
        notes: dto.notes,
      },
      actor,
    );
  }

  @Get('profiles')
  @Roles(Role.ADMIN)
  listProfiles(@Req() req: Request) {
    return this.scheduling.listProfiles(req.user as JwtUser);
  }

  @Post('profiles/upsert')
  @Roles(Role.ADMIN)
  upsertProfile(@Req() req: Request, @Body() dto: UpsertScheduleProfileDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.upsertProfile(
      {
        id: dto.id,
        name: dto.name,
        is_default: dto.is_default,
        days: dto.days.map((d) => ({
          weekday: d.weekday,
          is_working: d.is_working,
          kind: d.kind,
          start_minute: d.start_minute,
          end_minute: d.end_minute,
        })),
      },
      actor,
    );
  }

  @Get('coverage-rules')
  @Roles(Role.ADMIN)
  listCoverageRules(@Req() req: Request) {
    return this.scheduling.listCoverageRules(req.user as JwtUser);
  }

  @Post('coverage-rules/upsert')
  @Roles(Role.ADMIN)
  upsertCoverageRules(@Req() req: Request, @Body() dto: UpsertCoverageRulesDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.upsertCoverageRules(
      {
        rules: (dto.rules ?? []).map((r) => ({ role: r.role, weekday: r.weekday, min_required: r.min_required })),
      },
      actor,
    );
  }

  @Get('exceptions')
  @Roles(Role.ADMIN)
  listExceptions(@Req() req: Request, @Query('week_start_date') weekStartDate?: string) {
    return this.scheduling.listExceptions(req.user as JwtUser, weekStartDate ? new Date(weekStartDate) : undefined);
  }

  @Post('exceptions')
  @Roles(Role.ADMIN)
  createException(@Req() req: Request, @Body() dto: CreateWorkExceptionDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.createException(
      {
        user_id: dto.user_id,
        type: dto.type,
        date_from: dto.date_from,
        date_to: dto.date_to,
        note: dto.note,
      },
      actor,
    );
  }

  @Patch('exceptions/:id')
  @Roles(Role.ADMIN)
  updateException(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateWorkExceptionDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.updateException(
      id,
      {
        type: dto.type,
        date_from: dto.date_from,
        date_to: dto.date_to,
        note: dto.note,
      },
      actor,
    );
  }

  @Post('exceptions/:id/delete')
  @Roles(Role.ADMIN)
  deleteException(@Req() req: Request, @Param('id') id: string) {
    const actor = req.user as JwtUser;
    return this.scheduling.deleteException(id, actor);
  }

  @Post('weeks/generate')
  @Roles(Role.ADMIN)
  generateWeek(@Req() req: Request, @Body() dto: GenerateWeekDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.generateWeek(
      {
        week_start_date: dto.week_start_date,
        mode: dto.mode,
        note: dto.note,
      },
      actor,
    );
  }

  @Get('weeks/:weekStartDate')
  getWeek(@Req() req: Request, @Param('weekStartDate') weekStartDate: string) {
    const user = req.user as JwtUser;
    return this.scheduling.getWeek(weekStartDate, user).then((week) => {
      if (!week) return null;
      if (user.role === Role.ADMIN) return week;
      // Non-admin: only return their own assignments.
      return {
        ...week,
        days: (week.days ?? []).filter((d: any) => d.user_id === user.id),
      };
    });
  }

  @Post('manual/move-day-off')
  @Roles(Role.ADMIN)
  manualMoveDayOff(@Req() req: Request, @Body() dto: ManualMoveDayOffDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.manualMoveDayOff(
      {
        week_start_date: dto.week_start_date,
        user_id: dto.user_id,
        from_date: dto.from_date,
        to_date: dto.to_date,
        reason: dto.reason,
      },
      actor,
    );
  }

  @Post('manual/swap-day-off')
  @Roles(Role.ADMIN)
  manualSwapDayOff(@Req() req: Request, @Body() dto: ManualSwapDayOffDto) {
    const actor = req.user as JwtUser;
    return this.scheduling.manualSwapDayOff(
      {
        week_start_date: dto.week_start_date,
        user_a_id: dto.user_a_id,
        user_a_day_off_date: dto.user_a_day_off_date,
        user_b_id: dto.user_b_id,
        user_b_day_off_date: dto.user_b_day_off_date,
        reason: dto.reason,
      },
      actor,
    );
  }

  @Get('audit')
  @Roles(Role.ADMIN)
  listAudit(@Req() req: Request, @Query() query: AuditQueryDto) {
    return this.scheduling.listAudit({
      target_user_id: query.target_user_id,
      from: query.from,
      to: query.to,
    }, req.user as JwtUser);
  }

  @Get('reports/most-changes')
  @Roles(Role.ADMIN)
  mostChanges(@Req() req: Request, @Query() query: ReportsQueryDto) {
    return this.scheduling.reportMostChanges({ from: query.from, to: query.to }, req.user as JwtUser);
  }

  @Get('reports/low-coverage')
  @Roles(Role.ADMIN)
  lowCoverage(@Req() req: Request, @Query() query: ReportsQueryDto) {
    return this.scheduling.reportLowCoverage({ from: query.from, to: query.to }, req.user as JwtUser);
  }
}
