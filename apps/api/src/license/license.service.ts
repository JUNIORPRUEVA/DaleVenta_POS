import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { LicenseStatus, Prisma, Role } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';

type LicenseUpdateInput = {
  maxUsers?: unknown;
  maxProducts?: unknown;
  expiresAt?: unknown;
  notes?: unknown;
  licenseKey?: unknown;
  plan?: unknown;
  actorEmail?: unknown;
};

@Injectable()
export class LicenseService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly realtime: CatalogRealtimeRelayService,
  ) {}

  async ensureTrialForCompany(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true, trialStartedAt: true, trialEndsAt: true },
    });
    if (!company) return;
    if (company.trialStartedAt && company.trialEndsAt) return;

    const started = company.trialStartedAt ?? new Date();
    await this.prisma.company.update({
      where: { id: companyId },
      data: {
        trialStartedAt: started,
        trialEndsAt: company.trialEndsAt ?? this.addDays(started, 7),
        maxUsers: 2,
        maxProducts: 100,
      },
      select: { id: true },
    });
  }

  async assertCompanyCanUseApp(companyId?: string | null) {
    const id = (companyId ?? '').trim();
    if (!id) return;
    const status = await this.getCompanyLicenseStatus(id);
    if (!status.isUsable) {
      throw this.licenseInactiveException(status);
    }
  }

  async assertCanCreateUser(companyId: string) {
    const status = await this.getCompanyLicenseStatus(companyId);
    if (!status.isUsable) {
      throw new ForbiddenException(status.blockReason ?? 'Licencia no activa');
    }
    if (status.limits.maxUsers > 0 && status.usage.users >= status.limits.maxUsers) {
      throw new ConflictException(
        `La licencia permite ${status.limits.maxUsers} usuarios. Aumenta el limite para crear mas usuarios.`,
      );
    }
  }

  async assertCanCreateProduct(companyId: string) {
    const status = await this.getCompanyLicenseStatus(companyId);
    if (!status.isUsable) {
      throw new ForbiddenException(status.blockReason ?? 'Licencia no activa');
    }
    if (
      status.limits.maxProducts > 0 &&
      status.usage.products >= status.limits.maxProducts
    ) {
      throw new ConflictException(
        `La licencia permite ${status.limits.maxProducts} productos. Aumenta el limite para seguir creciendo.`,
      );
    }
  }

  async getMyLicense(user: TenantUser) {
    const companyId = requireTenant(user);
    return this.getCompanyLicenseStatus(companyId);
  }

  async listAdminCompanies(params: {
    page?: unknown;
    limit?: unknown;
    query?: unknown;
    status?: unknown;
  }) {
    const page = this.pageValue(params.page);
    const limit = this.limitValue(params.limit);
    const search = typeof params.query === 'string' ? params.query.trim() : '';
    const rawStatus = typeof params.status === 'string' ? params.status.trim().toUpperCase() : '';
    const where: Prisma.CompanyWhereInput = {};
    if (search) {
      where.OR = [
        { name: { contains: search, mode: 'insensitive' } },
        { slug: { contains: search, mode: 'insensitive' } },
        { licenseKey: { contains: search, mode: 'insensitive' } },
      ];
    }
    if (rawStatus && Object.values(LicenseStatus).includes(rawStatus as LicenseStatus)) {
      where.licenseStatus = rawStatus as LicenseStatus;
    }

    const [total, companies] = await Promise.all([
      this.prisma.company.count({ where }),
      this.prisma.company.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        select: { id: true },
      }),
    ]);
    const items = await Promise.all(
      companies.map((company) => this.getCompanyLicenseStatus(company.id)),
    );
    return { page, limit, total, items };
  }

  async getAdminCompany(companyId: string) {
    const license = await this.getCompanyLicenseStatus(companyId);
    const auditLogs = await this.prisma.companyLicenseAuditLog.findMany({
      where: { companyId },
      orderBy: { createdAt: 'desc' },
      take: 25,
    });
    return { ...license, auditLogs };
  }

  async activateMyLicense(user: TenantUser, dto: LicenseUpdateInput) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    return this.activateCompany(companyId, this.withRequestActor(user, dto));
  }

  async blockMyLicense(user: TenantUser, dto: LicenseUpdateInput) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    return this.blockCompany(companyId, this.withRequestActor(user, dto));
  }

  async updateMyLimits(user: TenantUser, dto: LicenseUpdateInput) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    return this.updateCompanyLicense(companyId, this.withRequestActor(user, dto));
  }

  async activateCompany(companyId: string, dto: LicenseUpdateInput) {
    const before = await this.companySnapshot(companyId);
    const data = this.licenseData(dto);
    const shouldCreateFreshLicense =
      before.licenseStatus === LicenseStatus.BLOCKED ||
      before.licenseStatus === LicenseStatus.EXPIRED ||
      !before.licenseKey ||
      (before.licenseExpiresAt && before.licenseExpiresAt.getTime() < Date.now());
    await this.prisma.company.update({
      where: { id: companyId },
      data: {
        ...data,
        status: 'ACTIVE',
        licenseStatus: LicenseStatus.ACTIVE,
        licenseActivatedAt: new Date(),
        licenseBlockedAt: null,
        licenseKey:
          data.licenseKey ??
          (shouldCreateFreshLicense ? this.generateLicenseKey() : before.licenseKey),
      },
      select: { id: true },
    });
    const after = await this.getCompanyLicenseStatus(companyId);
    await this.writeAuditLog(
      companyId,
      shouldCreateFreshLicense ? 'license.create_new' : 'license.activate',
      before,
      after,
      dto,
    );
    this.emitLicenseEvent(companyId, 'license.activated', after);
    return after;
  }

  async blockCompany(companyId: string, dto: LicenseUpdateInput) {
    const before = await this.companySnapshot(companyId);
    const notes = this.stringValue(dto.notes);
    await this.prisma.company.update({
      where: { id: companyId },
      data: {
        status: 'SUSPENDED',
        licenseStatus: LicenseStatus.BLOCKED,
        licenseBlockedAt: new Date(),
        licenseNotes: notes,
      },
      select: { id: true },
    });
    await this.revokeCompanySessions(companyId, 'license_blocked');
    const after = await this.getCompanyLicenseStatus(companyId);
    await this.writeAuditLog(companyId, 'license.block', before, after, dto);
    this.emitLicenseEvent(companyId, 'license.blocked', after);
    return after;
  }

  async updateCompanyLicense(companyId: string, dto: LicenseUpdateInput) {
    const before = await this.companySnapshot(companyId);
    await this.prisma.company.update({
      where: { id: companyId },
      data: this.licenseData(dto),
      select: { id: true },
    });
    const after = await this.getCompanyLicenseStatus(companyId);
    await this.writeAuditLog(companyId, 'license.update_limits', before, after, dto);
    this.emitLicenseEvent(companyId, 'license.updated', after);
    return after;
  }

  async deleteCompanyLicense(companyId: string, dto: LicenseUpdateInput) {
    const before = await this.companySnapshot(companyId);
    const notes = this.stringValue(dto.notes) ?? 'Licencia eliminada desde Appyra';
    await this.prisma.company.update({
      where: { id: companyId },
      data: {
        status: 'SUSPENDED',
        licenseStatus: LicenseStatus.BLOCKED,
        licenseBlockedAt: new Date(),
        licenseNotes: notes,
        licenseKey: null,
        licenseExpiresAt: null,
      },
      select: { id: true },
    });
    await this.revokeCompanySessions(companyId, 'license_deleted');
    const after = await this.getCompanyLicenseStatus(companyId);
    await this.writeAuditLog(companyId, 'license.delete', before, after, dto);
    this.emitLicenseEvent(companyId, 'license.deleted', after);
    return after;
  }

  async permanentlyDeleteCompanyLicense(companyId: string, dto: LicenseUpdateInput) {
    const before = await this.companySnapshot(companyId);
    const receiptId = `license_purge_${Date.now()}_${randomUUID().slice(0, 8)}`;
    await this.revokeCompanySessions(companyId, 'license_permanently_deleted');

    await this.prisma.$transaction(async (tx) => {
      await this.deleteCompanyOwnedRows(tx, companyId);
      await tx.companyMember.deleteMany({ where: { companyId } });
      await tx.user.updateMany({
        where: { companyId },
        data: { companyId: null, blocked: true },
      });
      await tx.company.delete({ where: { id: companyId } });
    });

    this.emitLicenseEvent(companyId, 'license.permanently_deleted', {
      companyId,
      companyName: before.name,
      receiptId,
    });

    return {
      ok: true,
      deleted: true,
      receiptId,
      companyId,
      companyName: before.name,
      message: 'Empresa, licencia y datos asociados eliminados completamente.',
    };
  }

  async assertAdminSecret(rawSecret?: string | string[]) {
    const configured = (
      this.config.get<string>('LICENSE_ADMIN_SECRET') ??
      process.env.LICENSE_ADMIN_SECRET ??
      ''
    ).trim();
    if (!configured) {
      throw new ForbiddenException('LICENSE_ADMIN_SECRET no esta configurado');
    }
    const received = Array.isArray(rawSecret) ? rawSecret[0] : rawSecret;
    if ((received ?? '').trim() !== configured) {
      throw new ForbiddenException('Secreto de licencias invalido');
    }
  }

  private async getCompanyLicenseStatus(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: {
        id: true,
        name: true,
        slug: true,
        status: true,
        plan: true,
        licenseStatus: true,
        licenseKey: true,
        trialStartedAt: true,
        trialEndsAt: true,
        licenseActivatedAt: true,
        licenseExpiresAt: true,
        licenseBlockedAt: true,
        licenseNotes: true,
        maxUsers: true,
        maxProducts: true,
      },
    });
    if (!company) throw new ForbiddenException('Empresa no encontrada');

    const now = new Date();
    const trialExpired =
      company.licenseStatus === LicenseStatus.TRIAL &&
      !!company.trialEndsAt &&
      company.trialEndsAt.getTime() < now.getTime();
    const paidExpired =
      company.licenseStatus === LicenseStatus.ACTIVE &&
      !!company.licenseExpiresAt &&
      company.licenseExpiresAt.getTime() < now.getTime();
    const effectiveStatus = trialExpired || paidExpired
      ? LicenseStatus.EXPIRED
      : company.licenseStatus;
    const isUsable =
      company.status === 'ACTIVE' &&
      (effectiveStatus === LicenseStatus.TRIAL ||
        effectiveStatus === LicenseStatus.ACTIVE);

    const [users, products, owner, appConfig] = await Promise.all([
      this.prisma.user.count({
        where: this.activeUserWhere(companyId),
      }),
      this.prisma.product.count({ where: { companyId } }),
      this.prisma.companyMember.findFirst({
        where: {
          companyId,
          status: 'ACTIVE',
          role: 'OWNER',
        },
        orderBy: { createdAt: 'asc' },
        select: {
          user: {
            select: {
              id: true,
              email: true,
              nombreCompleto: true,
              telefono: true,
            },
          },
        },
      }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        orderBy: { createdAt: 'asc' },
        select: {
          companyName: true,
          rnc: true,
          phone: true,
          address: true,
          description: true,
          legalRepresentativeName: true,
          legalRepresentativeCedula: true,
          legalRepresentativeRole: true,
        },
      }),
    ]);
    const responsible = owner?.user ?? null;
    const legalResponsibleName = appConfig?.legalRepresentativeName?.trim() || null;

    const effectiveLimits = this.effectiveLimits(company);

    const periodStart =
      effectiveStatus === LicenseStatus.TRIAL
        ? company.trialStartedAt
        : company.licenseActivatedAt ?? company.trialStartedAt;
    const periodEnd =
      effectiveStatus === LicenseStatus.TRIAL
        ? company.trialEndsAt
        : company.licenseExpiresAt;

    return {
      companyId: company.id,
      companyName: appConfig?.companyName || company.name,
      slug: company.slug,
      plan: company.plan,
      licenseType: this.licenseType(company.plan, effectiveStatus, effectiveLimits),
      licenseTypeLabel: this.licenseTypeLabel(company.plan, effectiveStatus, effectiveLimits),
      status: effectiveStatus,
      rawStatus: company.licenseStatus,
      isUsable,
      blockReason: this.blockReason(company.status, effectiveStatus),
      trialStartedAt: company.trialStartedAt,
      trialEndsAt: company.trialEndsAt,
      licenseActivatedAt: company.licenseActivatedAt,
      licenseExpiresAt: company.licenseExpiresAt,
      licenseBlockedAt: company.licenseBlockedAt,
      periodStartedAt: periodStart,
      periodEndsAt: periodEnd,
      licenseKey: company.licenseKey,
      notes: company.licenseNotes,
      daysRemaining: this.daysRemaining(periodEnd),
      limits: {
        maxUsers: effectiveLimits.maxUsers,
        maxProducts: effectiveLimits.maxProducts,
        configuredMaxUsers: company.maxUsers,
        configuredMaxProducts: company.maxProducts,
      },
      usage: {
        users,
        products,
      },
      account: {
        businessName: appConfig?.companyName || company.name,
        taxId: appConfig?.rnc || null,
        businessPhone: appConfig?.phone || null,
        businessAddress: appConfig?.address || null,
        businessType: appConfig?.description || null,
        responsibleName: legalResponsibleName || responsible?.nombreCompleto || null,
        responsibleEmail: responsible?.email || null,
        responsibleWhatsapp: responsible?.telefono || null,
        responsibleUserId: responsible?.id || null,
        legalRepresentativeName: legalResponsibleName,
        legalRepresentativeCedula: appConfig?.legalRepresentativeCedula || null,
        legalRepresentativeRole: appConfig?.legalRepresentativeRole || null,
      },
    };
  }

  private activeUserWhere(companyId: string): Prisma.UserWhereInput {
    return {
      blocked: false,
      OR: [
        { companyId },
        {
          companyMemberships: {
            some: { companyId, status: 'ACTIVE' },
          },
        },
      ],
    };
  }

  private licenseData(dto: LicenseUpdateInput): Prisma.CompanyUpdateInput {
    const data: Prisma.CompanyUpdateInput = {};
    const maxUsers = this.positiveInt(dto.maxUsers);
    const maxProducts = this.positiveInt(dto.maxProducts);
    const expiresAt = this.optionalDate(dto.expiresAt);
    const notes = this.stringValue(dto.notes);
    const licenseKey = this.stringValue(dto.licenseKey);
    const plan = this.planValue(dto.plan);
    if (maxUsers !== undefined) data.maxUsers = maxUsers;
    if (maxProducts !== undefined) data.maxProducts = maxProducts;
    if (expiresAt !== undefined) data.licenseExpiresAt = expiresAt;
    if (notes !== undefined) data.licenseNotes = notes;
    if (licenseKey !== undefined) data.licenseKey = licenseKey;
    if (plan !== undefined) {
      data.plan = plan;
      if (plan === 'STANDARD') {
        data.maxUsers = maxUsers ?? 2;
        data.maxProducts = maxProducts ?? 100;
      }
    }
    return data;
  }

  private requireAdmin(user: TenantUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException('Solo un administrador puede modificar licencias');
    }
  }

  private positiveInt(value: unknown) {
    if (value === undefined || value === null || value === '') return undefined;
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < 1) {
      throw new BadRequestException('Los limites deben ser enteros positivos');
    }
    return parsed;
  }

  private planValue(value: unknown) {
    if (value === undefined || value === null || value === '') return undefined;
    const cleaned = `${value}`.trim().toUpperCase();
    if (cleaned === 'BASIC' || cleaned === 'BASICO' || cleaned === 'BÁSICO') {
      return 'STANDARD' as const;
    }
    if (cleaned === 'STANDARD' || cleaned === 'ENTERPRISE') {
      return cleaned as 'STANDARD' | 'ENTERPRISE';
    }
    throw new BadRequestException('Plan de licencia invalido');
  }

  private effectiveLimits(company: {
    plan: string;
    licenseStatus: LicenseStatus;
    maxUsers: number;
    maxProducts: number;
  }) {
    return {
      maxUsers: Math.max(1, company.maxUsers || 2),
      maxProducts: Math.max(1, company.maxProducts || 100),
    };
  }

  private licenseType(
    plan: string,
    status: LicenseStatus,
    limits: { maxUsers: number; maxProducts: number },
  ) {
    if (status === LicenseStatus.TRIAL) return 'TRIAL';
    if (plan === 'ENTERPRISE') return 'ENTERPRISE';
    if (plan === 'STANDARD' && (limits.maxUsers > 2 || limits.maxProducts > 100)) {
      return 'BASIC_EXTENDED';
    }
    return 'BASIC';
  }

  private licenseTypeLabel(
    plan: string,
    status: LicenseStatus,
    limits: { maxUsers: number; maxProducts: number },
  ) {
    switch (this.licenseType(plan, status, limits)) {
      case 'TRIAL':
        return 'Plan demo';
      case 'ENTERPRISE':
        return 'Plan enterprise';
      case 'BASIC_EXTENDED':
        return 'Plan basico ampliado';
      default:
        return 'Plan basico';
    }
  }

  private optionalDate(value: unknown) {
    if (value === undefined) return undefined;
    if (value === null || value === '') return null;
    const date = new Date(`${value}`);
    if (Number.isNaN(date.getTime())) {
      throw new BadRequestException('Fecha de expiracion invalida');
    }
    return date;
  }

  private stringValue(value: unknown) {
    if (typeof value !== 'string') return undefined;
    const cleaned = value.trim();
    return cleaned.length > 0 ? cleaned : null;
  }

  private pageValue(value: unknown) {
    const parsed = Number(value);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
  }

  private limitValue(value: unknown) {
    const parsed = Number(value);
    if (!Number.isInteger(parsed)) return 25;
    return Math.min(100, Math.max(1, parsed));
  }

  private addDays(date: Date, days: number) {
    return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
  }

  private daysRemaining(date?: Date | null) {
    if (!date) return null;
    return Math.ceil((date.getTime() - Date.now()) / (24 * 60 * 60 * 1000));
  }

  private blockReason(companyStatus: string, licenseStatus: LicenseStatus) {
    if (licenseStatus === LicenseStatus.BLOCKED) return 'Licencia bloqueada';
    if (licenseStatus === LicenseStatus.EXPIRED) return 'Licencia expirada';
    if (companyStatus !== 'ACTIVE') return 'Empresa suspendida';
    return null;
  }

  private licenseInactiveException(status: {
    status?: LicenseStatus | string | null;
    rawStatus?: LicenseStatus | string | null;
    blockReason?: string | null;
    licenseTypeLabel?: string | null;
    periodEndsAt?: Date | string | null;
    daysRemaining?: number | null;
  }) {
    const rawStatus = `${status.rawStatus ?? status.status ?? ''}`.toUpperCase();
    const effectiveStatus = `${status.status ?? rawStatus}`.toUpperCase();
    const reason = status.blockReason ?? 'Licencia no activa';
    const errorCode = effectiveStatus === LicenseStatus.EXPIRED
      ? 'LICENSE_EXPIRED'
      : rawStatus === LicenseStatus.BLOCKED
        ? 'LICENSE_BLOCKED'
        : 'LICENSE_INACTIVE';

    return new UnauthorizedException({
      message: reason,
      errorCode,
      licenseStatus: effectiveStatus,
      rawLicenseStatus: rawStatus,
      licenseTypeLabel: status.licenseTypeLabel ?? null,
      periodEndsAt: status.periodEndsAt ?? null,
      daysRemaining: status.daysRemaining ?? null,
      supportPhone: '829-534-4286',
      purchaseUrl: 'https://wa.me/18295344286',
    });
  }

  private generateLicenseKey() {
    return `DV-${randomUUID().replace(/-/g, '').slice(0, 20).toUpperCase()}`;
  }

  private withRequestActor(user: TenantUser, dto: LicenseUpdateInput) {
    return {
      ...dto,
      actorEmail: (dto.actorEmail as string | undefined) ?? user.id,
    };
  }

  private async revokeCompanySessions(companyId: string, reason: string) {
    await this.prisma.authSession.updateMany({
      where: { companyId, revokedAt: null },
      data: { revokedAt: new Date(), revocationReason: reason },
    });
  }

  private async companySnapshot(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: {
        id: true,
        name: true,
        status: true,
        plan: true,
        licenseStatus: true,
        licenseKey: true,
        trialEndsAt: true,
        licenseExpiresAt: true,
        licenseBlockedAt: true,
        licenseNotes: true,
        maxUsers: true,
        maxProducts: true,
      },
    });
    if (!company) throw new ForbiddenException('Empresa no encontrada');
    return company;
  }

  private async deleteCompanyOwnedRows(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    const rows = await tx.$queryRaw<Array<{ table_name: string }>>(Prisma.sql`
      SELECT table_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND column_name = 'company_id'
        AND table_name NOT IN ('companies', 'company_members', 'users')
      ORDER BY table_name ASC
    `);

    for (const row of rows) {
      const tableName = row.table_name;
      if (!/^[a-zA-Z0-9_]+$/.test(tableName)) {
        throw new Error(`Unsafe table name discovered: ${tableName}`);
      }
      await tx.$executeRawUnsafe(
        `DELETE FROM "${tableName}" WHERE company_id = $1`,
        companyId,
      );
    }
  }

  private async writeAuditLog(
    companyId: string,
    action: string,
    before: unknown,
    after: unknown,
    dto: LicenseUpdateInput,
  ) {
    try {
      const actorEmail = this.stringValue(dto.actorEmail);
      const reason = this.stringValue(dto.notes);
      await this.prisma.companyLicenseAuditLog.create({
        data: {
          companyId,
          actorEmail,
          action,
          reason,
          before: this.jsonValue(before),
          after: this.jsonValue(after),
        },
        select: { id: true },
      });
    } catch {
      // License changes must not fail because audit storage is unavailable.
    }
  }

  private jsonValue(value: unknown): Prisma.InputJsonValue {
    return JSON.parse(JSON.stringify(value ?? null)) as Prisma.InputJsonValue;
  }

  private emitLicenseEvent(companyId: string, type: string, license: unknown) {
    try {
      this.realtime.emitCompany(companyId, 'license.event', {
        eventId: randomUUID(),
        type,
        companyId,
        license,
        emittedAt: new Date().toISOString(),
      });
    } catch {
      // Backend enforcement remains authoritative even if realtime is unavailable.
    }
  }
}
