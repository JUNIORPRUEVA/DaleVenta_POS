import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import {
  Prisma,
  Role,
  WorkAssignmentStatus,
  WorkScheduleAuditAction,
  WorkScheduleExceptionType,
  WorkShiftKind,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { requireTenant } from '../auth/tenant-context';

type Weekday = 0 | 1 | 2 | 3 | 4 | 5 | 6; // 0=Mon ... 6=Sun

type JwtActor = {
  id: string;
  role: Role;
  nombreCompleto?: string;
  companyId?: string | null;
};

type CoverageRuleMap = Map<string, Map<Weekday, number>>; // role -> weekday -> min

type ValidationWarning =
  | {
      type: 'COVERAGE_SHORTAGE';
      role: Role;
      weekday: Weekday;
      date: string; // yyyy-mm-dd
      min_required: number;
      working: number;
      missing: number;
    }
  | {
      type: 'IMPOSSIBLE_COVERAGE';
      role: Role;
      weekday: Weekday;
      date: string;
      employees_total: number;
      min_required: number;
      forced_off: number;
    }
  | {
      type: 'DISALLOWED_FIXED_DAY_OFF';
      user_id: string;
      weekday: Weekday;
    }
  | {
      type: 'NO_VALID_DAY_OFF_FOUND';
      user_id: string;
      role: Role;
    }
  | {
      type: 'NO_DAY_OFF_THIS_WEEK';
      user_id: string;
    };

function toIsoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

function normalizeDayLocal(d: Date) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function addDays(date: Date, days: number) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

function weekday0Mon(date: Date): Weekday {
  return ((date.getDay() + 6) % 7) as Weekday;
}

function startOfWeekMonday(date: Date) {
  const day = normalizeDayLocal(date);
  const wd = weekday0Mon(day);
  return addDays(day, -wd);
}

function clampWeekday(value: number): Weekday {
  if (value < 0) return 0;
  if (value > 6) return 6;
  return value as Weekday;
}

function uniqueWeekdays(values: number[] | null | undefined): Weekday[] {
  if (!values || values.length === 0) return [];
  const set = new Set<number>();
  for (const v of values) {
    if (Number.isInteger(v) && v >= 0 && v <= 6) set.add(v);
  }
  return Array.from(set).sort((a, b) => a - b).map((v) => v as Weekday);
}

function stringHashToInt(input: string) {
  let h = 0;
  for (let i = 0; i < input.length; i++) {
    h = (h * 31 + input.charCodeAt(i)) >>> 0;
  }
  return h;
}

@Injectable()
export class WorkSchedulingService {
  constructor(private readonly prisma: PrismaService) {}

  private async ensureDefaultProfile() {
    const existing = await this.prisma.workScheduleProfile.findFirst({
      where: { isDefault: true },
      select: { id: true },
    });
    if (existing) return existing.id;

    const profile = await this.prisma.workScheduleProfile.create({
      data: {
        name: 'Horario General',
        isDefault: true,
        days: {
          create: [
            // 0=Mon ... 5=Sat
            ...Array.from({ length: 6 }).map((_, idx) => ({
              weekday: idx,
              isWorking: true,
              kind: WorkShiftKind.NORMAL,
              startMinute: 9 * 60,
              endMinute: 18 * 60,
            })),
            // 6=Sun
            {
              weekday: 6,
              isWorking: true,
              kind: WorkShiftKind.REDUCED,
              startMinute: 9 * 60,
              endMinute: 14 * 60,
            },
          ],
        },
      },
      select: { id: true },
    });

    return profile.id;
  }

  private async ensureDefaultCoverageRules() {
    const count = await this.prisma.workCoverageRule.count();
    if (count > 0) return;

    const roles: Array<{ role: Role; defaultMin: number }> = [
      { role: Role.TECNICO, defaultMin: 2 },
      { role: Role.VENDEDOR, defaultMin: 1 },
      { role: Role.ASISTENTE, defaultMin: 1 },
      { role: Role.MARKETING, defaultMin: 0 },
      { role: Role.ADMIN, defaultMin: 0 },
    ];

    const rules: Prisma.WorkCoverageRuleCreateManyInput[] = [];
    for (const r of roles) {
      if (r.role === Role.ADMIN) continue;
      for (let weekday = 0; weekday <= 6; weekday++) {
        rules.push({ role: r.role, weekday, minRequired: r.defaultMin });
      }
    }

    await this.prisma.workCoverageRule.createMany({ data: rules, skipDuplicates: true });
  }

  private async ensureEmployeeConfigs(userIds: string[]) {
    if (userIds.length === 0) return;
    const existing = await this.prisma.workEmployeeConfig.findMany({
      where: { userId: { in: userIds } },
      select: { userId: true },
    });
    const existingSet = new Set(existing.map((x) => x.userId));
    const missing = userIds.filter((id) => !existingSet.has(id));
    if (missing.length === 0) return;

    await this.prisma.workEmployeeConfig.createMany({
      data: missing.map((userId) => ({ userId, enabled: true })),
      skipDuplicates: true,
    });
  }

  async listEmployees() {
    const users = await this.prisma.user.findMany({
      where: { role: { not: Role.ADMIN } },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        nombreCompleto: true,
        email: true,
        telefono: true,
        role: true,
        blocked: true,
      },
    });

    await this.ensureEmployeeConfigs(users.map((u) => u.id));

    const configs = await this.prisma.workEmployeeConfig.findMany({
      where: { userId: { in: users.map((u) => u.id) } },
      select: {
        userId: true,
        enabled: true,
        scheduleProfileId: true,
        preferredDayOffWeekday: true,
        fixedDayOffWeekday: true,
        disallowedDayOffWeekdays: true,
        unavailableWeekdays: true,
        notes: true,
        lastAssignedDayOffWeekday: true,
        updatedAt: true,
      },
    });

    const byUserId = new Map(configs.map((c) => [c.userId, c] as const));

    return users.map((u) => {
      const cfg = byUserId.get(u.id);
      return {
        id: u.id,
        nombre_completo: u.nombreCompleto,
        email: u.email,
        telefono: u.telefono,
        role: u.role,
        blocked: u.blocked ? 1 : 0,
        schedule: {
          enabled: cfg?.enabled ?? true,
          schedule_profile_id: cfg?.scheduleProfileId ?? null,
          preferred_day_off_weekday: cfg?.preferredDayOffWeekday ?? null,
          fixed_day_off_weekday: cfg?.fixedDayOffWeekday ?? null,
          disallowed_day_off_weekdays: cfg?.disallowedDayOffWeekdays ?? [],
          unavailable_weekdays: cfg?.unavailableWeekdays ?? [],
          notes: cfg?.notes ?? null,
          last_assigned_day_off_weekday: cfg?.lastAssignedDayOffWeekday ?? null,
          updated_at: cfg?.updatedAt?.toISOString() ?? null,
        },
      };
    });
  }

  async updateEmployeeConfig(userId: string, dto: {
    enabled?: boolean;
    schedule_profile_id?: string | null;
    preferred_day_off_weekday?: number | null;
    fixed_day_off_weekday?: number | null;
    disallowed_day_off_weekdays?: number[];
    unavailable_weekdays?: number[];
    notes?: string | null;
  }, actor?: JwtActor) {
    await this.ensureEmployeeConfigs([userId]);

    const data: Prisma.WorkEmployeeConfigUpdateInput = {};
    if (dto.enabled !== undefined) data.enabled = dto.enabled;
    if (dto.schedule_profile_id !== undefined) {
      data.scheduleProfile = dto.schedule_profile_id
        ? { connect: { id: dto.schedule_profile_id } }
        : { disconnect: true };
    }
    if (dto.preferred_day_off_weekday !== undefined) data.preferredDayOffWeekday = dto.preferred_day_off_weekday;
    if (dto.fixed_day_off_weekday !== undefined) data.fixedDayOffWeekday = dto.fixed_day_off_weekday;
    if (dto.disallowed_day_off_weekdays !== undefined) data.disallowedDayOffWeekdays = uniqueWeekdays(dto.disallowed_day_off_weekdays);
    if (dto.unavailable_weekdays !== undefined) data.unavailableWeekdays = uniqueWeekdays(dto.unavailable_weekdays);
    if (dto.notes !== undefined) data.notes = dto.notes;

    const updated = await this.prisma.workEmployeeConfig.update({
      where: { userId },
      data,
      select: {
        userId: true,
        enabled: true,
        scheduleProfileId: true,
        preferredDayOffWeekday: true,
        fixedDayOffWeekday: true,
        disallowedDayOffWeekdays: true,
        unavailableWeekdays: true,
        notes: true,
        lastAssignedDayOffWeekday: true,
        updatedAt: true,
      },
    });

    if (actor) {
      await this.createAudit({
        action: WorkScheduleAuditAction.UPDATE_EMPLOYEE_CONFIG,
        actor,
        targetUserId: userId,
        reason: 'update_employee_config',
        before: null,
        after: {
          enabled: updated.enabled,
          schedule_profile_id: updated.scheduleProfileId,
          preferred_day_off_weekday: updated.preferredDayOffWeekday,
          fixed_day_off_weekday: updated.fixedDayOffWeekday,
          disallowed_day_off_weekdays: updated.disallowedDayOffWeekdays,
          unavailable_weekdays: updated.unavailableWeekdays,
          notes: updated.notes,
        },
      });
    }

    return {
      user_id: updated.userId,
      enabled: updated.enabled,
      schedule_profile_id: updated.scheduleProfileId,
      preferred_day_off_weekday: updated.preferredDayOffWeekday,
      fixed_day_off_weekday: updated.fixedDayOffWeekday,
      disallowed_day_off_weekdays: updated.disallowedDayOffWeekdays,
      unavailable_weekdays: updated.unavailableWeekdays,
      notes: updated.notes,
      last_assigned_day_off_weekday: updated.lastAssignedDayOffWeekday,
      updated_at: updated.updatedAt.toISOString(),
    };
  }

  async listProfiles() {
    const profiles = await this.prisma.workScheduleProfile.findMany({
      orderBy: [{ isDefault: 'desc' }, { name: 'asc' }],
      include: { days: { orderBy: { weekday: 'asc' } } },
    });

    return profiles.map((p) => ({
      id: p.id,
      name: p.name,
      is_default: p.isDefault ? 1 : 0,
      days: p.days.map((d) => ({
        weekday: d.weekday,
        is_working: d.isWorking ? 1 : 0,
        kind: d.kind,
        start_minute: d.startMinute,
        end_minute: d.endMinute,
      })),
      created_at: p.createdAt.toISOString(),
      updated_at: p.updatedAt.toISOString(),
    }));
  }

  async upsertProfile(dto: {
    id?: string;
    name: string;
    is_default?: boolean;
    days: Array<{ weekday: number; is_working: boolean; kind: WorkShiftKind; start_minute: number; end_minute: number }>;
  }, actor?: JwtActor) {
    const days = dto.days ?? [];
    if (days.length !== 7) {
      throw new BadRequestException('El perfil debe incluir los 7 días (weekday 0..6)');
    }

    const normalizeDays = days.map((d) => ({
      weekday: clampWeekday(d.weekday),
      isWorking: !!d.is_working,
      kind: d.kind,
      startMinute: d.start_minute,
      endMinute: d.end_minute,
    }));

    const unique = new Set(normalizeDays.map((d) => d.weekday));
    if (unique.size !== 7) {
      throw new BadRequestException('Los days.weekday deben ser únicos (0..6)');
    }

    const isDefault = dto.is_default === true;

    const profile = await this.prisma.$transaction(async (tx) => {
      let saved:
        | (Prisma.WorkScheduleProfileGetPayload<{ include: { days: true } }>)
        | null = null;

      if (dto.id) {
        saved = await tx.workScheduleProfile.update({
          where: { id: dto.id },
          data: {
            name: dto.name.trim(),
            isDefault: isDefault ? true : undefined,
          },
          include: { days: true },
        });

        // Upsert days
        for (const d of normalizeDays) {
          await tx.workScheduleProfileDay.upsert({
            where: { profileId_weekday: { profileId: saved.id, weekday: d.weekday } },
            update: {
              isWorking: d.isWorking,
              kind: d.kind,
              startMinute: d.startMinute,
              endMinute: d.endMinute,
            },
            create: {
              profileId: saved.id,
              weekday: d.weekday,
              isWorking: d.isWorking,
              kind: d.kind,
              startMinute: d.startMinute,
              endMinute: d.endMinute,
            },
          });
        }
      } else {
        saved = await tx.workScheduleProfile.create({
          data: {
            name: dto.name.trim(),
            isDefault,
            days: {
              create: normalizeDays.map((d) => ({
                weekday: d.weekday,
                isWorking: d.isWorking,
                kind: d.kind,
                startMinute: d.startMinute,
                endMinute: d.endMinute,
              })),
            },
          },
          include: { days: true },
        });
      }

      if (isDefault) {
        await tx.workScheduleProfile.updateMany({
          where: { id: { not: saved.id }, isDefault: true },
          data: { isDefault: false },
        });
      }

      const final = await tx.workScheduleProfile.findUnique({
        where: { id: saved.id },
        include: { days: { orderBy: { weekday: 'asc' } } },
      });

      return final!;
    });

    if (actor) {
      await this.createAudit({
        action: WorkScheduleAuditAction.UPDATE_SETTINGS,
        actor,
        reason: 'upsert_profile',
        before: null,
        after: { profile_id: profile.id, is_default: profile.isDefault },
      });
    }

    return {
      id: profile.id,
      name: profile.name,
      is_default: profile.isDefault ? 1 : 0,
      days: profile.days.map((d) => ({
        weekday: d.weekday,
        is_working: d.isWorking ? 1 : 0,
        kind: d.kind,
        start_minute: d.startMinute,
        end_minute: d.endMinute,
      })),
      created_at: profile.createdAt.toISOString(),
      updated_at: profile.updatedAt.toISOString(),
    };
  }

  async listCoverageRules() {
    await this.ensureDefaultCoverageRules();
    const rules = await this.prisma.workCoverageRule.findMany({
      orderBy: [{ role: 'asc' }, { weekday: 'asc' }],
    });
    return rules.map((r) => ({
      id: r.id,
      role: r.role,
      weekday: r.weekday,
      min_required: r.minRequired,
      created_at: r.createdAt.toISOString(),
      updated_at: r.updatedAt.toISOString(),
    }));
  }

  async upsertCoverageRules(dto: { rules: Array<{ role: Role; weekday: number; min_required: number }> }, actor?: JwtActor) {
    const items = dto.rules ?? [];
    if (items.length === 0) return { ok: true };

    await this.prisma.$transaction(async (tx) => {
      for (const r of items) {
        const weekday = clampWeekday(r.weekday);
        await tx.workCoverageRule.upsert({
          where: { role_weekday: { role: r.role, weekday } },
          update: { minRequired: r.min_required },
          create: { role: r.role, weekday, minRequired: r.min_required },
        });
      }
    });

    if (actor) {
      await this.createAudit({
        action: WorkScheduleAuditAction.UPDATE_SETTINGS,
        actor,
        reason: 'upsert_coverage_rules',
        before: null,
        after: { count: items.length },
      });
    }

    return { ok: true };
  }

  async listExceptions(weekStartDate?: Date) {
    // If weekStartDate is provided, only return exceptions overlapping that week.
    let where: Prisma.WorkScheduleExceptionWhereInput = {};
    if (weekStartDate) {
      const start = normalizeDayLocal(weekStartDate);
      const end = addDays(start, 6);
      where = {
        OR: [
          { dateFrom: { lte: end }, dateTo: { gte: start } },
        ],
      };
    }

    const list = await this.prisma.workScheduleException.findMany({
      where,
      orderBy: [{ dateFrom: 'desc' }, { createdAt: 'desc' }],
    });

    return list.map((x) => ({
      id: x.id,
      user_id: x.userId,
      type: x.type,
      date_from: x.dateFrom.toISOString(),
      date_to: x.dateTo.toISOString(),
      note: x.note,
      created_by_id: x.createdById,
      created_by_name: x.createdByName,
      created_at: x.createdAt.toISOString(),
      updated_at: x.updatedAt.toISOString(),
    }));
  }

  async createException(dto: { user_id?: string; type: WorkScheduleExceptionType; date_from: string; date_to: string; note?: string }, actor?: JwtActor) {
    const dateFrom = normalizeDayLocal(new Date(dto.date_from));
    const dateTo = normalizeDayLocal(new Date(dto.date_to));
    if (dateTo < dateFrom) throw new BadRequestException('date_to no puede ser menor que date_from');

    if (dto.user_id) await this.ensureEmployeeConfigs([dto.user_id]);

    const created = await this.prisma.workScheduleException.create({
      data: {
        userId: dto.user_id ?? null,
        type: dto.type,
        dateFrom,
        dateTo,
        note: (dto.note ?? '').trim() || null,
        createdById: actor?.id ?? null,
        createdByName: actor?.nombreCompleto ?? null,
      },
    });

    if (actor) {
      await this.createAudit({
        action: WorkScheduleAuditAction.CREATE_EXCEPTION,
        actor,
        targetUserId: dto.user_id ?? null,
        reason: dto.note ?? null,
        before: null,
        after: { id: created.id, type: created.type, date_from: created.dateFrom, date_to: created.dateTo },
      });
    }

    return {
      id: created.id,
      user_id: created.userId,
      type: created.type,
      date_from: created.dateFrom.toISOString(),
      date_to: created.dateTo.toISOString(),
      note: created.note,
      created_at: created.createdAt.toISOString(),
      updated_at: created.updatedAt.toISOString(),
    };
  }

  async updateException(id: string, dto: { type?: WorkScheduleExceptionType; date_from?: string; date_to?: string; note?: string | null }, actor?: JwtActor) {
    const companyId = requireTenant(actor);
    const existing = await this.prisma.workScheduleException.findFirst({
      where: {
        id,
        OR: [
          { userId: null },
          {
            employeeConfig: {
              user: {
                OR: [
                  { companyId },
                  { companyMemberships: { some: { companyId, status: 'ACTIVE' } } },
                ],
              },
            },
          },
        ],
      },
    });
    if (!existing) throw new NotFoundException('Excepción no encontrada');

    const data: Prisma.WorkScheduleExceptionUpdateInput = {};
    if (dto.type !== undefined) data.type = dto.type;
    if (dto.date_from !== undefined) data.dateFrom = normalizeDayLocal(new Date(dto.date_from));
    if (dto.date_to !== undefined) data.dateTo = normalizeDayLocal(new Date(dto.date_to));
    if (data.dateFrom && data.dateTo && (data.dateTo as Date) < (data.dateFrom as Date)) {
      throw new BadRequestException('date_to no puede ser menor que date_from');
    }
    if (dto.note !== undefined) data.note = (dto.note ?? '').trim() || null;

    await this.prisma.workScheduleException.updateMany({ where: { id }, data });
    const updated = await this.prisma.workScheduleException.findFirst({
      where: {
        id,
        OR: [
          { userId: null },
          {
            employeeConfig: {
              user: {
                OR: [
                  { companyId },
                  { companyMemberships: { some: { companyId, status: 'ACTIVE' } } },
                ],
              },
            },
          },
        ],
      },
    });
    if (!updated) throw new NotFoundException('Excepción no encontrada');

    if (actor) {
      await this.createAudit({
        action: WorkScheduleAuditAction.UPDATE_EXCEPTION,
        actor,
        targetUserId: updated.userId,
        reason: dto.note ?? null,
        before: {
          type: existing.type,
          date_from: existing.dateFrom,
          date_to: existing.dateTo,
          note: existing.note,
        },
        after: {
          type: updated.type,
          date_from: updated.dateFrom,
          date_to: updated.dateTo,
          note: updated.note,
        },
      });
    }

    return {
      id: updated.id,
      user_id: updated.userId,
      type: updated.type,
      date_from: updated.dateFrom.toISOString(),
      date_to: updated.dateTo.toISOString(),
      note: updated.note,
      updated_at: updated.updatedAt.toISOString(),
    };
  }

  async deleteException(id: string, actor?: JwtActor) {
    const companyId = requireTenant(actor);
    const existing = await this.prisma.workScheduleException.findFirst({
      where: {
        id,
        OR: [
          { userId: null },
          {
            employeeConfig: {
              user: {
                OR: [
                  { companyId },
                  { companyMemberships: { some: { companyId, status: 'ACTIVE' } } },
                ],
              },
            },
          },
        ],
      },
    });
    if (!existing) throw new NotFoundException('Excepción no encontrada');

    await this.prisma.workScheduleException.deleteMany({ where: { id } });

    if (actor) {
      await this.createAudit({
        action: WorkScheduleAuditAction.DELETE_EXCEPTION,
        actor,
        targetUserId: existing.userId,
        reason: existing.note,
        before: { id: existing.id, type: existing.type, date_from: existing.dateFrom, date_to: existing.dateTo },
        after: null,
      });
    }

    return { ok: true };
  }

  private async loadCoverageRuleMap(): Promise<CoverageRuleMap> {
    await this.ensureDefaultCoverageRules();
    const rules = await this.prisma.workCoverageRule.findMany();
    const map: CoverageRuleMap = new Map();
    for (const r of rules) {
      if (!map.has(r.role)) map.set(r.role, new Map());
      map.get(r.role)!.set(r.weekday as Weekday, r.minRequired);
    }
    return map;
  }

  private async computeWeekEmployees() {
    const users = await this.prisma.user.findMany({
      where: { role: { not: Role.ADMIN } },
      orderBy: [{ role: 'asc' }, { createdAt: 'asc' }],
      select: { id: true, nombreCompleto: true, role: true, blocked: true },
    });

    await this.ensureEmployeeConfigs(users.map((u) => u.id));

    const configs = await this.prisma.workEmployeeConfig.findMany({
      where: { userId: { in: users.map((u) => u.id) } },
      select: {
        userId: true,
        enabled: true,
        scheduleProfileId: true,
        preferredDayOffWeekday: true,
        fixedDayOffWeekday: true,
        disallowedDayOffWeekdays: true,
        unavailableWeekdays: true,
        lastAssignedDayOffWeekday: true,
      },
    });

    const cfgByUserId = new Map(configs.map((c) => [c.userId, c] as const));

    const employees = users.map((u) => {
      const cfg = cfgByUserId.get(u.id);
      return {
        id: u.id,
        nombre: u.nombreCompleto,
        role: u.role,
        blocked: u.blocked,
        config: {
          enabled: cfg?.enabled ?? true,
          scheduleProfileId: cfg?.scheduleProfileId ?? null,
          preferredDayOffWeekday: cfg?.preferredDayOffWeekday ?? null,
          fixedDayOffWeekday: cfg?.fixedDayOffWeekday ?? null,
          disallowedDayOffWeekdays: uniqueWeekdays(cfg?.disallowedDayOffWeekdays ?? []),
          unavailableWeekdays: uniqueWeekdays(cfg?.unavailableWeekdays ?? []),
          lastAssignedDayOffWeekday: cfg?.lastAssignedDayOffWeekday ?? null,
        },
      };
    });

    return employees;
  }

  private pickDayOrder(params: {
    userId: string;
    weekStart: Date;
    preferred?: number | null;
    lastAssigned?: number | null;
  }): Weekday[] {
    const weekIndex = Math.floor(startOfWeekMonday(params.weekStart).getTime() / (7 * 24 * 60 * 60 * 1000));
    const seed = stringHashToInt(params.userId) % 7;
    const start = params.lastAssigned != null ? (params.lastAssigned + 1) % 7 : (seed + (weekIndex % 7) + 7) % 7;

    const order: Weekday[] = Array.from({ length: 7 }).map((_, i) => ((start + i) % 7) as Weekday);

    const pref = params.preferred;
    if (pref != null && pref >= 0 && pref <= 6) {
      const p = pref as Weekday;
      return [p, ...order.filter((x) => x !== p)];
    }

    return order;
  }

  private assignDayOffForRoleGroup(args: {
    role: Role;
    weekStart: Date;
    employees: Array<{
      id: string;
      config: {
        preferredDayOffWeekday: number | null;
        fixedDayOffWeekday: number | null;
        disallowedDayOffWeekdays: Weekday[];
        lastAssignedDayOffWeekday: number | null;
      };
      forcedOffWeekdays: Set<Weekday>;
    }>;
    minCoverageByWeekday: Map<Weekday, number>;
  }) {
    const warnings: ValidationWarning[] = [];

    const enabledEmployees = args.employees;

    const offSets = new Map<Weekday, Set<string>>();
    const offLimit = new Map<Weekday, number>();

    for (let wd = 0; wd <= 6; wd++) {
      const weekday = wd as Weekday;
      const minReq = args.minCoverageByWeekday.get(weekday) ?? 0;
      offLimit.set(weekday, Math.max(0, enabledEmployees.length - minReq));
      offSets.set(weekday, new Set());
    }

    // Initialize forced off.
    for (const emp of enabledEmployees) {
      for (const wd of emp.forcedOffWeekdays) {
        offSets.get(wd)!.add(emp.id);
      }
    }

    // If forced off already breaks coverage, warn (but still proceed).
    for (let wd = 0; wd <= 6; wd++) {
      const weekday = wd as Weekday;
      const minReq = args.minCoverageByWeekday.get(weekday) ?? 0;
      const forcedOff = offSets.get(weekday)!.size;
      if (forcedOff > enabledEmployees.length - minReq) {
        warnings.push({
          type: 'IMPOSSIBLE_COVERAGE',
          role: args.role,
          weekday,
          date: toIsoDate(addDays(args.weekStart, weekday)),
          employees_total: enabledEmployees.length,
          min_required: minReq,
          forced_off: forcedOff,
        });
      }
    }

    const result = new Map<string, Weekday>();

    // Deterministic ordering: fixed day-offs first, then those with more restrictions.
    const sorted = [...enabledEmployees].sort((a, b) => {
      const aFixed = a.config.fixedDayOffWeekday != null ? 1 : 0;
      const bFixed = b.config.fixedDayOffWeekday != null ? 1 : 0;
      if (aFixed !== bFixed) return bFixed - aFixed;
      const aRestr = (a.config.disallowedDayOffWeekdays?.length ?? 0) + (a.forcedOffWeekdays.size > 0 ? 1 : 0);
      const bRestr = (b.config.disallowedDayOffWeekdays?.length ?? 0) + (b.forcedOffWeekdays.size > 0 ? 1 : 0);
      if (aRestr !== bRestr) return bRestr - aRestr;
      return a.id.localeCompare(b.id);
    });

    for (const emp of sorted) {
      const disallowed = new Set(emp.config.disallowedDayOffWeekdays ?? []);

      const fixed = emp.config.fixedDayOffWeekday;
      if (fixed != null) {
        const fixedWd = clampWeekday(fixed);
        if (disallowed.has(fixedWd)) {
          warnings.push({ type: 'DISALLOWED_FIXED_DAY_OFF', user_id: emp.id, weekday: fixedWd });
        }
        result.set(emp.id, fixedWd);
        offSets.get(fixedWd)!.add(emp.id);
        continue;
      }

      // Prefer to "use" an already-forced-off weekday as the weekly day off.
      const forcedOptions = Array.from(emp.forcedOffWeekdays).filter((wd) => !disallowed.has(wd));
      if (forcedOptions.length > 0) {
        const order = this.pickDayOrder({
          userId: emp.id,
          weekStart: args.weekStart,
          preferred: emp.config.preferredDayOffWeekday,
          lastAssigned: emp.config.lastAssignedDayOffWeekday,
        });
        const picked = order.find((d) => forcedOptions.includes(d));
        const day = (picked ?? forcedOptions[0]) as Weekday;
        result.set(emp.id, day);
        // forced-off already accounted (offSets already has emp.id for that weekday)
        continue;
      }

      const order = this.pickDayOrder({
        userId: emp.id,
        weekStart: args.weekStart,
        preferred: emp.config.preferredDayOffWeekday,
        lastAssigned: emp.config.lastAssignedDayOffWeekday,
      }).filter((d) => !disallowed.has(d));

      let chosen: Weekday | null = null;
      for (const wd of order) {
        const set = offSets.get(wd)!;
        if (set.has(emp.id)) {
          chosen = wd;
          break;
        }
        const limit = offLimit.get(wd)!;
        if (set.size + 1 <= limit) {
          chosen = wd;
          break;
        }
      }

      if (chosen == null) {
        // As a last resort, choose the weekday with the smallest off load.
        let bestWd: Weekday = 0;
        let bestSize = Number.POSITIVE_INFINITY;
        for (const wd of order.length ? order : ([0, 1, 2, 3, 4, 5, 6] as Weekday[])) {
          const size = offSets.get(wd)!.size;
          if (size < bestSize) {
            bestSize = size;
            bestWd = wd;
          }
        }
        chosen = bestWd;
        warnings.push({ type: 'NO_VALID_DAY_OFF_FOUND', user_id: emp.id, role: args.role });
      }

      result.set(emp.id, chosen);
      offSets.get(chosen)!.add(emp.id);
    }

    return { dayOffByUserId: result, warnings };
  }

  private buildProfileDayMap(days: Array<{ profileId: string; weekday: number; isWorking: boolean; kind: WorkShiftKind; startMinute: number; endMinute: number }>) {
    const map = new Map<string, Map<Weekday, { isWorking: boolean; kind: WorkShiftKind; startMinute: number; endMinute: number }>>();
    for (const d of days) {
      const wd = clampWeekday(d.weekday);
      if (!map.has(d.profileId)) map.set(d.profileId, new Map());
      map.get(d.profileId)!.set(wd, {
        isWorking: d.isWorking,
        kind: d.kind,
        startMinute: d.startMinute,
        endMinute: d.endMinute,
      });
    }
    return map;
  }

  private exceptionCoversDate(exception: { dateFrom: Date; dateTo: Date }, date: Date) {
    const d = normalizeDayLocal(date);
    const from = normalizeDayLocal(exception.dateFrom);
    const to = normalizeDayLocal(exception.dateTo);
    return d >= from && d <= to;
  }

  private async computeValidationForSchedule(scheduleId: string, weekStart: Date) {
    const warnings: ValidationWarning[] = [];

    const coverage = await this.loadCoverageRuleMap();

    // Load schedule assignments
    const assignments = await this.prisma.workDayAssignment.findMany({
      where: { weekScheduleId: scheduleId },
      select: { userId: true, date: true, weekday: true, status: true },
    });

    const userIds = Array.from(new Set(assignments.map((a) => a.userId)));

    const users = await this.prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, role: true, blocked: true },
    });
    const roleByUser = new Map(users.map((u) => [u.id, u.role] as const));

    const configs = await this.prisma.workEmployeeConfig.findMany({
      where: { userId: { in: userIds } },
      select: { userId: true, enabled: true },
    });
    const enabledByUser = new Map(configs.map((c) => [c.userId, c.enabled] as const));

    const enabledUsersByRole = new Map<Role, Set<string>>();
    for (const u of users) {
      if (u.role === Role.ADMIN) continue;
      const enabled = enabledByUser.get(u.id) ?? true;
      if (u.blocked || !enabled) continue;
      if (!enabledUsersByRole.has(u.role)) enabledUsersByRole.set(u.role, new Set());
      enabledUsersByRole.get(u.role)!.add(u.id);
    }

    // Coverage per day/role
    for (let wd = 0; wd <= 6; wd++) {
      const weekday = wd as Weekday;
      const date = addDays(weekStart, weekday);
      for (const [role, userSet] of enabledUsersByRole.entries()) {
        const min = coverage.get(role)?.get(weekday) ?? 0;
        if (min <= 0) continue;

        let working = 0;
        for (const a of assignments) {
          if (a.weekday !== weekday) continue;
          if (!userSet.has(a.userId)) continue;
          if (a.status === WorkAssignmentStatus.WORK) working++;
        }

        if (working < min) {
          warnings.push({
            type: 'COVERAGE_SHORTAGE',
            role,
            weekday,
            date: toIsoDate(date),
            min_required: min,
            working,
            missing: min - working,
          });
        }
      }
    }

    // Day-off per employee
    const byUser = new Map<string, WorkAssignmentStatus[]>();
    for (const a of assignments) {
      if (!byUser.has(a.userId)) byUser.set(a.userId, []);
      byUser.get(a.userId)!.push(a.status);
    }
    for (const [userId, statuses] of byUser.entries()) {
      const hasOff = statuses.some((s) => s === WorkAssignmentStatus.DAY_OFF || s === WorkAssignmentStatus.EXCEPTION_OFF);
      if (!hasOff) warnings.push({ type: 'NO_DAY_OFF_THIS_WEEK', user_id: userId });
    }

    return warnings;
  }

  async getWeek(weekStartDateIso: string) {
    const weekStart = startOfWeekMonday(new Date(weekStartDateIso));
    const schedule = await this.prisma.workWeekSchedule.findUnique({
      where: { weekStartDate: weekStart },
      select: { id: true, weekStartDate: true, generatedAt: true, warnings: true },
    });
    if (!schedule) return null;

    const assignments = await this.prisma.workDayAssignment.findMany({
      where: { weekScheduleId: schedule.id },
      orderBy: [{ date: 'asc' }, { userId: 'asc' }],
      select: {
        id: true,
        userId: true,
        date: true,
        weekday: true,
        status: true,
        startMinute: true,
        endMinute: true,
        manualOverride: true,
        note: true,
        conflictFlags: true,
      },
    });

    const userIds = Array.from(new Set(assignments.map((a) => a.userId)));
    const users = await this.prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, nombreCompleto: true, role: true },
    });
    const userById = new Map(users.map((u) => [u.id, u] as const));

    return {
      id: schedule.id,
      week_start_date: toIsoDate(schedule.weekStartDate),
      generated_at: schedule.generatedAt.toISOString(),
      warnings: schedule.warnings ?? [],
      days: assignments.map((a) => ({
        id: a.id,
        user_id: a.userId,
        user_name: userById.get(a.userId)?.nombreCompleto ?? '',
        role: userById.get(a.userId)?.role ?? null,
        date: toIsoDate(a.date),
        weekday: a.weekday,
        status: a.status,
        start_minute: a.startMinute,
        end_minute: a.endMinute,
        manual_override: a.manualOverride ? 1 : 0,
        note: a.note,
        conflict_flags: a.conflictFlags,
      })),
    };
  }

  async generateWeek(params: { week_start_date: string; mode?: 'REPLACE' | 'KEEP_MANUAL'; note?: string }, actor: JwtActor) {
    const weekStart = startOfWeekMonday(new Date(params.week_start_date));
    const mode = params.mode ?? 'REPLACE';

    const defaultProfileId = await this.ensureDefaultProfile();
    await this.ensureDefaultCoverageRules();

    const employees = await this.computeWeekEmployees();
    const activeEmployees = employees.filter((e) => e.role !== Role.ADMIN && !e.blocked && e.config.enabled);

    const coverage = await this.loadCoverageRuleMap();

    const profileIds = new Set<string>();
    profileIds.add(defaultProfileId);
    for (const e of activeEmployees) {
      if (e.config.scheduleProfileId) profileIds.add(e.config.scheduleProfileId);
    }

    const profileDays = await this.prisma.workScheduleProfileDay.findMany({
      where: { profileId: { in: Array.from(profileIds) } },
      select: { profileId: true, weekday: true, isWorking: true, kind: true, startMinute: true, endMinute: true },
    });
    const profileDayMap = this.buildProfileDayMap(profileDays);

    // Exceptions overlapping the week.
    const weekEnd = addDays(weekStart, 6);
    const exceptions = await this.prisma.workScheduleException.findMany({
      where: {
        dateFrom: { lte: weekEnd },
        dateTo: { gte: weekStart },
        OR: [
          { userId: null },
          { userId: { in: activeEmployees.map((e) => e.id) } },
        ],
      },
      orderBy: [{ userId: 'asc' }, { dateFrom: 'asc' }],
      select: { id: true, userId: true, type: true, dateFrom: true, dateTo: true, note: true },
    });

    const globalExceptions = exceptions.filter((x) => x.userId == null);
    const userExceptionsByUserId = new Map<string, typeof exceptions>();
    for (const ex of exceptions) {
      if (!ex.userId) continue;
      if (!userExceptionsByUserId.has(ex.userId)) userExceptionsByUserId.set(ex.userId, []);
      userExceptionsByUserId.get(ex.userId)!.push(ex);
    }

    // Forced off weekdays (unavailable weekdays + exceptions + company closed in profile).
    const forcedOffByUserId = new Map<string, Set<Weekday>>();

    for (const emp of activeEmployees) {
      const set = new Set<Weekday>();
      for (const wd of emp.config.unavailableWeekdays) set.add(wd);

      const personal = userExceptionsByUserId.get(emp.id) ?? [];
      const allExceptions = [...globalExceptions, ...personal];

      for (let wd = 0; wd <= 6; wd++) {
        const weekday = wd as Weekday;
        const date = addDays(weekStart, weekday);

        // If the employee profile says the company/employee doesn't work that day, treat as forced off.
        const profileId = emp.config.scheduleProfileId ?? defaultProfileId;
        const dayTemplate = profileDayMap.get(profileId)?.get(weekday);
        if (dayTemplate && !dayTemplate.isWorking) {
          set.add(weekday);
          continue;
        }

        const covered = allExceptions.some((ex) => this.exceptionCoversDate(ex, date));
        if (covered) set.add(weekday);
      }

      forcedOffByUserId.set(emp.id, set);
    }

    // Assign weekly day-off per role group.
    const warnings: ValidationWarning[] = [];
    const dayOffByUserId = new Map<string, Weekday>();

    const byRole = new Map<Role, typeof activeEmployees>();
    for (const e of activeEmployees) {
      if (!byRole.has(e.role)) byRole.set(e.role, []);
      byRole.get(e.role)!.push(e);
    }

    for (const [role, emps] of byRole.entries()) {
      const minMap = coverage.get(role) ?? new Map();
      const { dayOffByUserId: perRole, warnings: w } = this.assignDayOffForRoleGroup({
        role,
        weekStart,
        employees: emps.map((e) => ({
          id: e.id,
          config: {
            preferredDayOffWeekday: e.config.preferredDayOffWeekday,
            fixedDayOffWeekday: e.config.fixedDayOffWeekday,
            disallowedDayOffWeekdays: e.config.disallowedDayOffWeekdays,
            lastAssignedDayOffWeekday: e.config.lastAssignedDayOffWeekday,
          },
          forcedOffWeekdays: forcedOffByUserId.get(e.id) ?? new Set(),
        })),
        minCoverageByWeekday: new Map(Array.from({ length: 7 }).map((_, idx) => [idx as Weekday, minMap.get(idx as Weekday) ?? 0])),
      });

      for (const [userId, wd] of perRole.entries()) dayOffByUserId.set(userId, wd);
      warnings.push(...w);
    }

    const actorName = actor?.nombreCompleto ?? null;

    const schedule = await this.prisma.$transaction(async (tx) => {
      const week = await tx.workWeekSchedule.upsert({
        where: { weekStartDate: weekStart },
        update: {
          generatedById: actor.id,
          generatedByName: actorName,
          generatedAt: new Date(),
          warnings: [],
        },
        create: {
          weekStartDate: weekStart,
          generatedById: actor.id,
          generatedByName: actorName,
          warnings: [],
        },
        select: { id: true },
      });

      // Remove previous assignments (respecting manual overrides if requested).
      if (mode === 'REPLACE') {
        await tx.workDayAssignment.deleteMany({ where: { weekScheduleId: week.id } });
      } else {
        await tx.workDayAssignment.deleteMany({ where: { weekScheduleId: week.id, manualOverride: false } });
      }

      const keptManual = mode === 'KEEP_MANUAL'
        ? await tx.workDayAssignment.findMany({
            where: { weekScheduleId: week.id, manualOverride: true },
            select: { userId: true, date: true },
          })
        : [];

      const keptKey = new Set(keptManual.map((k) => `${k.userId}:${toIsoDate(k.date)}`));

      const createRows: Prisma.WorkDayAssignmentCreateManyInput[] = [];

      for (const emp of activeEmployees) {
        const profileId = emp.config.scheduleProfileId ?? defaultProfileId;
        const templateByWeekday = profileDayMap.get(profileId) ?? profileDayMap.get(defaultProfileId);
        if (!templateByWeekday) {
          throw new BadRequestException('No hay profile days para generar horarios');
        }

        const dayOff = dayOffByUserId.get(emp.id) ?? 6;

        for (let wd = 0; wd <= 6; wd++) {
          const weekday = wd as Weekday;
          const date = addDays(weekStart, weekday);
          const key = `${emp.id}:${toIsoDate(date)}`;
          if (keptKey.has(key)) continue;

          const template = templateByWeekday.get(weekday);
          const forcedOff = (forcedOffByUserId.get(emp.id) ?? new Set()).has(weekday);
          const status: WorkAssignmentStatus = !template?.isWorking
            ? WorkAssignmentStatus.EXCEPTION_OFF
            : forcedOff
              ? WorkAssignmentStatus.EXCEPTION_OFF
              : (weekday === dayOff ? WorkAssignmentStatus.DAY_OFF : WorkAssignmentStatus.WORK);

          const startMinute = status === WorkAssignmentStatus.WORK ? (template?.startMinute ?? null) : null;
          const endMinute = status === WorkAssignmentStatus.WORK ? (template?.endMinute ?? null) : null;

          let note: string | null = null;
          if (!template?.isWorking) {
            note = 'Día no laborable (perfil)';
          } else if (forcedOff) {
            // attach the most relevant exception type (if any)
            const personal = userExceptionsByUserId.get(emp.id) ?? [];
            const allExceptions = [...globalExceptions, ...personal];
            const hit = allExceptions.find((ex) => this.exceptionCoversDate(ex, date));
            note = hit ? `Excepción: ${hit.type}` : 'No disponible';
          }

          createRows.push({
            weekScheduleId: week.id,
            userId: emp.id,
            date,
            weekday,
            status,
            startMinute,
            endMinute,
            manualOverride: false,
            note,
            conflictFlags: Prisma.DbNull,
          });
        }
      }

      if (createRows.length > 0) {
        await tx.workDayAssignment.createMany({ data: createRows });
      }

      // Update lastAssignedDayOffWeekday for rotation.
      for (const emp of activeEmployees) {
        const picked = dayOffByUserId.get(emp.id);
        if (picked == null) continue;
        await tx.workEmployeeConfig.update({
          where: { userId: emp.id },
          data: { lastAssignedDayOffWeekday: picked },
        });
      }

      return week;
    });

    // Validate and persist warnings.
    const validationWarnings = await this.computeValidationForSchedule(schedule.id, weekStart);
    const allWarnings = [...warnings, ...validationWarnings];

    await this.prisma.workWeekSchedule.update({
      where: { id: schedule.id },
      data: { warnings: allWarnings as any },
    });

    await this.createAudit({
      action: mode === 'REPLACE' ? WorkScheduleAuditAction.GENERATE_WEEK : WorkScheduleAuditAction.REGENERATE_WEEK,
      actor,
      weekStartDate: weekStart,
      reason: params.note ?? null,
      before: null,
      after: { warnings: allWarnings.length },
    });

    const response = await this.getWeek(toIsoDate(weekStart));
    return response;
  }

  private async assertNoCoverageShortage(scheduleId: string, weekStart: Date) {
    const warnings = await this.computeValidationForSchedule(scheduleId, weekStart);
    const shortage = warnings.find((w) => w.type === 'COVERAGE_SHORTAGE');
    if (!shortage) return;

    const w = shortage as Extract<ValidationWarning, { type: 'COVERAGE_SHORTAGE' }>;
    throw new BadRequestException(
      `Cambio no permitido: cobertura insuficiente para ${w.role} el ${w.date}. Requerido ${w.min_required}, disponible ${w.working}.`
    );
  }

  async manualMoveDayOff(dto: { week_start_date: string; user_id: string; from_date: string; to_date: string; reason?: string }, actor: JwtActor) {
    const companyId = requireTenant(actor);
    const weekStart = startOfWeekMonday(new Date(dto.week_start_date));
    const schedule = await this.prisma.workWeekSchedule.findFirst({ where: { weekStartDate: weekStart, companyId }, select: { id: true } });
    if (!schedule) throw new NotFoundException('Semana no encontrada. Primero genera la semana.');

    await this.ensureEmployeeConfigs([dto.user_id]);

    const fromDate = normalizeDayLocal(new Date(dto.from_date));
    const toDate = normalizeDayLocal(new Date(dto.to_date));

    const [fromA, toA] = await this.prisma.workDayAssignment.findMany({
      where: {
        weekScheduleId: schedule.id,
        userId: dto.user_id,
        date: { in: [fromDate, toDate] },
      },
    });

    const aFrom = [fromA, toA].find((x) => x && toIsoDate(x.date) === toIsoDate(fromDate));
    const aTo = [fromA, toA].find((x) => x && toIsoDate(x.date) === toIsoDate(toDate));

    if (!aFrom || !aTo) throw new BadRequestException('No se encontraron asignaciones para esas fechas');
    if (aFrom.status !== WorkAssignmentStatus.DAY_OFF) throw new BadRequestException('La fecha origen no es un día libre');
    if (aTo.status !== WorkAssignmentStatus.WORK) throw new BadRequestException('La fecha destino debe ser un día laborable');

    const user = await this.prisma.user.findFirst({
      where: {
        id: dto.user_id,
        OR: [
          { companyId },
          { companyMemberships: { some: { companyId, status: 'ACTIVE' } } },
        ],
      },
      select: { role: true, blocked: true },
    });
    if (!user || user.blocked) throw new BadRequestException('Empleado inválido o bloqueado');

    const defaultProfileId = await this.ensureDefaultProfile();
    const cfg = await this.prisma.workEmployeeConfig.findUnique({ where: { userId: dto.user_id }, select: { scheduleProfileId: true, enabled: true } });
    if (cfg && !cfg.enabled) throw new BadRequestException('Empleado inactivo en horarios');

    const profileId = cfg?.scheduleProfileId ?? defaultProfileId;
    const dayTemplate = await this.prisma.workScheduleProfileDay.findUnique({
      where: { profileId_weekday: { profileId, weekday: weekday0Mon(fromDate) } },
    });

    if (!dayTemplate?.isWorking) {
      throw new BadRequestException('No se puede mover el día libre a un día no laborable del perfil');
    }

    const before = {
      from: { date: aFrom.date, status: aFrom.status },
      to: { date: aTo.date, status: aTo.status },
    };

    await this.prisma.$transaction(async (tx) => {
      await tx.workDayAssignment.update({
        where: { id: aFrom.id },
        data: {
          status: WorkAssignmentStatus.WORK,
          startMinute: dayTemplate.startMinute,
          endMinute: dayTemplate.endMinute,
          manualOverride: true,
        },
      });

      await tx.workDayAssignment.update({
        where: { id: aTo.id },
        data: {
          status: WorkAssignmentStatus.DAY_OFF,
          startMinute: null,
          endMinute: null,
          manualOverride: true,
          note: null,
        },
      });

      // Strict validation: do not allow coverage shortage.
      await this.assertNoCoverageShortage(schedule.id, weekStart);

      const allWarnings = await this.computeValidationForSchedule(schedule.id, weekStart);
      await tx.workWeekSchedule.updateMany({ where: { id: schedule.id, companyId }, data: { warnings: allWarnings as any } });
    });

    await this.createAudit({
      action: WorkScheduleAuditAction.MANUAL_MOVE_DAY_OFF,
      actor,
      targetUserId: dto.user_id,
      weekStartDate: weekStart,
      dateAffected: toDate,
      reason: dto.reason ?? null,
      before,
      after: { moved_to: toIsoDate(toDate) },
    });

    return this.getWeek(toIsoDate(weekStart));
  }

  async manualSwapDayOff(dto: { week_start_date: string; user_a_id: string; user_a_day_off_date: string; user_b_id: string; user_b_day_off_date: string; reason?: string }, actor: JwtActor) {
    const companyId = requireTenant(actor);
    const weekStart = startOfWeekMonday(new Date(dto.week_start_date));
    const schedule = await this.prisma.workWeekSchedule.findFirst({ where: { weekStartDate: weekStart, companyId }, select: { id: true } });
    if (!schedule) throw new NotFoundException('Semana no encontrada. Primero genera la semana.');

    await this.ensureEmployeeConfigs([dto.user_a_id, dto.user_b_id]);

    const dateA = normalizeDayLocal(new Date(dto.user_a_day_off_date));
    const dateB = normalizeDayLocal(new Date(dto.user_b_day_off_date));

    const list = await this.prisma.workDayAssignment.findMany({
      where: {
        weekScheduleId: schedule.id,
        OR: [
          { userId: dto.user_a_id, date: dateA },
          { userId: dto.user_b_id, date: dateB },
          { userId: dto.user_a_id, date: dateB },
          { userId: dto.user_b_id, date: dateA },
        ],
      },
    });

    const aDayOffA = list.find((x) => x.userId === dto.user_a_id && toIsoDate(x.date) === toIsoDate(dateA));
    const bDayOffB = list.find((x) => x.userId === dto.user_b_id && toIsoDate(x.date) === toIsoDate(dateB));

    if (!aDayOffA || !bDayOffB) throw new BadRequestException('No se encontraron asignaciones para swap');
    if (aDayOffA.status !== WorkAssignmentStatus.DAY_OFF) throw new BadRequestException('El día indicado de A no es libre');
    if (bDayOffB.status !== WorkAssignmentStatus.DAY_OFF) throw new BadRequestException('El día indicado de B no es libre');

    const defaultProfileId = await this.ensureDefaultProfile();

    const cfgA = await this.prisma.workEmployeeConfig.findFirst({
      where: {
        userId: dto.user_a_id,
        user: {
          OR: [
            { companyId },
            { companyMemberships: { some: { companyId, status: 'ACTIVE' } } },
          ],
        },
      },
      select: { scheduleProfileId: true, enabled: true },
    });
    const cfgB = await this.prisma.workEmployeeConfig.findFirst({
      where: {
        userId: dto.user_b_id,
        user: {
          OR: [
            { companyId },
            { companyMemberships: { some: { companyId, status: 'ACTIVE' } } },
          ],
        },
      },
      select: { scheduleProfileId: true, enabled: true },
    });
    if (cfgA && !cfgA.enabled) throw new BadRequestException('Empleado A inactivo en horarios');
    if (cfgB && !cfgB.enabled) throw new BadRequestException('Empleado B inactivo en horarios');

    const profileA = cfgA?.scheduleProfileId ?? defaultProfileId;
    const profileB = cfgB?.scheduleProfileId ?? defaultProfileId;

    const workTemplateForA = await this.prisma.workScheduleProfileDay.findUnique({
      where: { profileId_weekday: { profileId: profileA, weekday: weekday0Mon(dateA) } },
    });
    const workTemplateForB = await this.prisma.workScheduleProfileDay.findUnique({
      where: { profileId_weekday: { profileId: profileB, weekday: weekday0Mon(dateB) } },
    });

    if (!workTemplateForA?.isWorking) throw new BadRequestException('A no puede trabajar su día libre actual según el perfil');
    if (!workTemplateForB?.isWorking) throw new BadRequestException('B no puede trabajar su día libre actual según el perfil');

    const before = {
      a: { user_id: dto.user_a_id, day_off: toIsoDate(dateA) },
      b: { user_id: dto.user_b_id, day_off: toIsoDate(dateB) },
    };

    await this.prisma.$transaction(async (tx) => {
      // A: dateA becomes WORK, dateB becomes DAY_OFF
      const aDateB = list.find((x) => x.userId === dto.user_a_id && toIsoDate(x.date) === toIsoDate(dateB));
      if (!aDateB) throw new BadRequestException('No existe asignación de A para el día de B');
      if (aDateB.status !== WorkAssignmentStatus.WORK) throw new BadRequestException('A no está laborable en el día que recibiría libre');

      await tx.workDayAssignment.update({
        where: { id: aDayOffA.id },
        data: {
          status: WorkAssignmentStatus.WORK,
          startMinute: workTemplateForA.startMinute,
          endMinute: workTemplateForA.endMinute,
          manualOverride: true,
        },
      });

      await tx.workDayAssignment.update({
        where: { id: aDateB.id },
        data: {
          status: WorkAssignmentStatus.DAY_OFF,
          startMinute: null,
          endMinute: null,
          manualOverride: true,
          note: null,
        },
      });

      // B: dateB becomes WORK, dateA becomes DAY_OFF
      const bDateA = list.find((x) => x.userId === dto.user_b_id && toIsoDate(x.date) === toIsoDate(dateA));
      if (!bDateA) throw new BadRequestException('No existe asignación de B para el día de A');
      if (bDateA.status !== WorkAssignmentStatus.WORK) throw new BadRequestException('B no está laborable en el día que recibiría libre');

      await tx.workDayAssignment.update({
        where: { id: bDayOffB.id },
        data: {
          status: WorkAssignmentStatus.WORK,
          startMinute: workTemplateForB.startMinute,
          endMinute: workTemplateForB.endMinute,
          manualOverride: true,
        },
      });

      await tx.workDayAssignment.update({
        where: { id: bDateA.id },
        data: {
          status: WorkAssignmentStatus.DAY_OFF,
          startMinute: null,
          endMinute: null,
          manualOverride: true,
          note: null,
        },
      });

      await this.assertNoCoverageShortage(schedule.id, weekStart);
      const allWarnings = await this.computeValidationForSchedule(schedule.id, weekStart);
      await tx.workWeekSchedule.updateMany({ where: { id: schedule.id, companyId }, data: { warnings: allWarnings as any } });
    });

    await this.createAudit({
      action: WorkScheduleAuditAction.MANUAL_SWAP_DAY_OFF,
      actor,
      targetUserId: null,
      weekStartDate: weekStart,
      reason: dto.reason ?? null,
      before,
      after: { swapped: true },
    });

    return this.getWeek(toIsoDate(weekStart));
  }

  async listAudit(query: { target_user_id?: string; from?: string; to?: string }) {
    const where: Prisma.WorkScheduleAuditLogWhereInput = {};
    if (query.target_user_id) where.targetUserId = query.target_user_id;

    if (query.from || query.to) {
      where.createdAt = {};
      if (query.from) (where.createdAt as Prisma.DateTimeFilter).gte = new Date(query.from);
      if (query.to) (where.createdAt as Prisma.DateTimeFilter).lte = new Date(query.to);
    }

    const logs = await this.prisma.workScheduleAuditLog.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 250,
    });

    return logs.map((l) => ({
      id: l.id,
      action: l.action,
      actor_user_id: l.actorUserId,
      actor_user_name: l.actorUserName,
      target_user_id: l.targetUserId,
      week_start_date: l.weekStartDate ? toIsoDate(l.weekStartDate) : null,
      date_affected: l.dateAffected ? toIsoDate(l.dateAffected) : null,
      reason: l.reason,
      before: l.before,
      after: l.after,
      created_at: l.createdAt.toISOString(),
    }));
  }

  async reportMostChanges(query: { from?: string; to?: string }) {
    const where: Prisma.WorkScheduleAuditLogWhereInput = {
      action: { in: [WorkScheduleAuditAction.MANUAL_MOVE_DAY_OFF, WorkScheduleAuditAction.MANUAL_SWAP_DAY_OFF] },
    };
    if (query.from || query.to) {
      where.createdAt = {};
      if (query.from) (where.createdAt as Prisma.DateTimeFilter).gte = new Date(query.from);
      if (query.to) (where.createdAt as Prisma.DateTimeFilter).lte = new Date(query.to);
    }

    const rows = await this.prisma.workScheduleAuditLog.groupBy({
      by: ['targetUserId'],
      where,
      _count: { id: true },
      orderBy: { _count: { id: 'desc' } },
      take: 50,
    });

    const ids = rows.map((r) => r.targetUserId).filter((x): x is string => !!x);
    const users = await this.prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, nombreCompleto: true, role: true } });
    const userMap = new Map(users.map((u) => [u.id, u] as const));

    return rows
      .filter((r) => !!r.targetUserId)
      .map((r) => ({
        user_id: r.targetUserId,
        user_name: userMap.get(r.targetUserId!)?.nombreCompleto ?? '',
        role: userMap.get(r.targetUserId!)?.role ?? null,
        changes: r._count?.id ?? 0,
      }));
  }

  async reportLowCoverage(query: { from?: string; to?: string }) {
    const where: Prisma.WorkWeekScheduleWhereInput = {};
    if (query.from || query.to) {
      where.weekStartDate = {};
      if (query.from) (where.weekStartDate as Prisma.DateTimeFilter).gte = startOfWeekMonday(new Date(query.from));
      if (query.to) (where.weekStartDate as Prisma.DateTimeFilter).lte = startOfWeekMonday(new Date(query.to));
    }

    const weeks = await this.prisma.workWeekSchedule.findMany({
      where,
      orderBy: { weekStartDate: 'desc' },
      take: 26,
      select: { weekStartDate: true, warnings: true },
    });

    const result: Array<any> = [];
    for (const w of weeks) {
      const warnings = Array.isArray(w.warnings) ? (w.warnings as any[]) : [];
      for (const item of warnings) {
        if (item?.type === 'COVERAGE_SHORTAGE') {
          result.push({ week_start_date: toIsoDate(w.weekStartDate), ...item });
        }
      }
    }

    return result;
  }

  private async createAudit(args: {
    action: WorkScheduleAuditAction;
    actor: JwtActor;
    targetUserId?: string | null;
    weekStartDate?: Date;
    dateAffected?: Date;
    reason?: string | null;
    before: unknown;
    after: unknown;
  }) {
    await this.prisma.workScheduleAuditLog.create({
      data: {
        action: args.action,
        actorUserId: args.actor.id,
        actorUserName: args.actor.nombreCompleto ?? null,
        targetUserId: args.targetUserId ?? null,
        weekStartDate: args.weekStartDate ?? null,
        dateAffected: args.dateAffected ?? null,
        reason: args.reason ?? null,
        before: args.before as any,
        after: args.after as any,
      },
    });
  }
}
