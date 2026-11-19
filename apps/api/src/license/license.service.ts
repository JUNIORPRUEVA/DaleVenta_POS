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
import { isAdminLike, requireTenant, type TenantUser } from '../auth/tenant-context';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import { buildEntitlements } from './plans/license-entitlements.service';
import { LicenseRenewalService } from './renewal/license-renewal.service';
import {
  resolveLicenseAccess,
  type LicenseAccess,
} from './license.access.policy';

type LicenseUpdateInput = {
  maxUsers?: unknown;
  maxProducts?: unknown;
  expiresAt?: unknown;
  notes?: unknown;
  licenseKey?: unknown;
  plan?: unknown;
  companyName?: unknown;
  businessName?: unknown;
  taxId?: unknown;
  businessPhone?: unknown;
  businessAddress?: unknown;
  businessType?: unknown;
  responsibleName?: unknown;
  responsibleEmail?: unknown;
  responsibleWhatsapp?: unknown;
  legalRepresentativeName?: unknown;
  legalRepresentativeCedula?: unknown;
  legalRepresentativeRole?: unknown;
  name?: unknown;
  actorEmail?: unknown;
};

type PrismaExecutor = PrismaService | Prisma.TransactionClient;
type QuotaResource = 'users' | 'products';

@Injectable()
export class LicenseService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly renewal: LicenseRenewalService,
  ) {}

  /**
   * Inicia la **demo de 7 dias** de una empresa (una sola vez en su vida).
   *
   * No se llama sola en ningun sitio: el registro ya crea la prueba, y para el
   * resto de empresas la demo se abre con una **accion administrativa
   * explicita** (`POST /license/admin/:companyId/trial`). Asi una empresa
   * antigua sin fechas de prueba no recibe una demo nueva por el simple hecho
   * de entrar, y cerrar sesion o reinstalar no renueva nada.
   *
   * Reglas cerradas, todas comprobadas antes de escribir:
   * - Si ya tuvo prueba (`trialStartedAt`), no hay otra: se lanza 409.
   * - Si ya pago alguna vez (`licenseActivatedAt`), no se le cambia a demo.
   * - Si la licencia esta activa, bloqueada o vencida por pago, tampoco.
   * La fecha de fin es **siempre** 7 dias despues del inicio.
   */
  async ensureTrialForCompany(companyId: string, actorEmail?: string | null) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: {
        id: true,
        licenseStatus: true,
        trialStartedAt: true,
        trialEndsAt: true,
        licenseActivatedAt: true,
        licenseExpiresAt: true,
        licenseBlockedAt: true,
      },
    });
    if (!company) throw new ForbiddenException('Empresa no encontrada');
    if (company.trialStartedAt) {
      throw new ConflictException({
        code: 'TRIAL_ALREADY_USED',
        message: 'Esta empresa ya tuvo su prueba gratuita de 7 dias.',
      });
    }
    if (
      company.licenseActivatedAt ||
      company.licenseExpiresAt ||
      company.licenseBlockedAt ||
      company.licenseStatus !== LicenseStatus.TRIAL
    ) {
      throw new ConflictException({
        code: 'TRIAL_NOT_ALLOWED',
        message:
          'La empresa ya tiene historial de licencia; la demo solo se abre a empresas nuevas.',
      });
    }

    const started = new Date();
    const endsAt = this.addDays(started, 7);
    await this.prisma.company.update({
      where: { id: companyId },
      data: {
        trialStartedAt: started,
        trialEndsAt: endsAt,
        licenseStatus: LicenseStatus.TRIAL,
        status: 'ACTIVE',
        maxUsers: 2,
        maxProducts: 100,
      },
      select: { id: true },
    });
    await this.writeAuditLog(
      companyId,
      'license.trial_started',
      { trialStartedAt: null, trialEndsAt: null, licenseStatus: company.licenseStatus },
      { trialStartedAt: started, trialEndsAt: endsAt, licenseStatus: LicenseStatus.TRIAL },
      { actorEmail: actorEmail ?? null, notes: 'Demo de 7 dias iniciada' },
    );
    return { startedAt: started, endsAt, days: 7 };
  }

  /**
   * Compuerta del **trabajo offline** (autorizacion de emergencia de 48 h).
   *
   * Solo se autoriza con acceso `FULL`: una licencia vencida o una cuenta
   * suspendida pueden entrar a la app para renovar o pedir ayuda, pero **no**
   * deben poder seguir vendiendo sin conexion, que es justo lo que la
   * suspension tiene que impedir.
   *
   * El login ya no llama aqui: la app entra siempre y es
   * `LicenseAccessInterceptor` el que limita las rutas con el nivel que calcula
   * `resolveLicenseAccess`.
   */
  async assertCompanyCanUseApp(companyId?: string | null) {
    const id = (companyId ?? '').trim();
    if (!id) return;
    const access = await this.getLicenseAccess(id);
    if (access.level === 'FULL') return;
    throw this.licenseInactiveException(await this.getCompanyLicenseStatus(id));
  }

  /**
   * Lectura minima para el JWT y el interceptor de acceso: una sola consulta a
   * `Company`, sin contar usuarios ni productos.
   */
  async getLicenseAccess(companyId?: string | null): Promise<LicenseAccess> {
    const id = (companyId ?? '').trim();
    if (!id) return resolveLicenseAccess(null);
    const company = await this.prisma.company.findUnique({
      where: { id },
      select: {
        status: true,
        licenseStatus: true,
        trialEndsAt: true,
        licenseExpiresAt: true,
        licenseActivatedAt: true,
      },
    });
    return resolveLicenseAccess(company);
  }

  async assertCanCreateUser(companyId: string) {
    await this.prisma.$transaction((tx) =>
      this.assertCanCreateUserInTransaction(tx, companyId),
    );
  }

  async assertCanCreateProduct(companyId: string) {
    await this.prisma.$transaction((tx) =>
      this.assertCanCreateProductInTransaction(tx, companyId),
    );
  }

  async assertCanCreateUserInTransaction(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    await this.assertCanConsumeQuota(tx, companyId, 'users');
  }

  async assertCanCreateProductInTransaction(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    await this.assertCanConsumeQuota(tx, companyId, 'products');
  }

  async getMyLicense(user: TenantUser) {
    const companyId = requireTenant(user);
    const status = await this.getCompanyLicenseStatus(companyId);
    // La proxima cuota se calcula **solo** para esta ruta: las comprobaciones
    // de cupo no pagan dos consultas extra por cada producto creado.
    const renewal = await this.renewal.snapshot(companyId);
    // El nivel de acceso (FULL/RESTRICTED/BLOCKED) sale de la **misma**
    // politica que usa el guard y el login: la app no repite la regla de si la
    // licencia vencio ni puede discrepar del servidor.
    const access = await this.getLicenseAccess(companyId);
    return { ...status, renewal, access };
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

  async getAdminCompanyUsage(companyId: string) {
    const status = await this.getCompanyLicenseStatus(companyId);
    return {
      companyId: status.companyId,
      companyName: status.companyName,
      plan: status.plan,
      status: status.status,
      rawStatus: status.rawStatus,
      isUsable: status.isUsable,
      expiresAt: status.periodEndsAt,
      updatedAt: status.updatedAt,
      products: {
        resource: 'products',
        current: status.usage.products,
        limit: status.limits.maxProducts,
        enforced: true,
        semantics: 'active_non_archived_products',
      },
      users: {
        resource: 'users',
        current: status.usage.users,
        limit: status.limits.maxUsers,
        enforced: true,
        semantics: 'active_non_blocked_users_or_active_memberships',
      },
      warehouses: {
        resource: 'warehouses',
        current: null,
        limit: null,
        enforced: false,
        supported: false,
      },
      devices: {
        resource: 'devices',
        current: null,
        limit: null,
        enforced: false,
        supported: false,
      },
    };
  }

  // Los antiguos `activateMyLicense`, `blockMyLicense` y `updateMyLimits`
  // (autoservicio del propietario) se eliminaron: permitian activar la
  // licencia o ampliar cupos y fecha sin pagar. La activacion solo ocurre al
  // subir el comprobante (`LicenseActivationService`) o desde el equipo con el
  // secreto de administracion.
  /**
   * RESUMEN DE LA CUENTA PARA EL ASISTENTE (APPYRA IA).
   *
   * El asistente tiene que poder decir «tu licencia venció el 12 de marzo» o «estás en el plan
   * Emprendedor con 3 de 5 usuarios» sin inventarlo. Este método devuelve **sólo** lo que sirve para
   * responder eso.
   *
   * QUÉ SE QUEDA FUERA, Y POR QUÉ
   * -----------------------------
   * - `licenseKey`: es una credencial. Un asistente que la repita en un chat la deja escrita en un
   *   historial.
   * - `notes`: son notas internas del equipo de soporte.
   * - `account.*`: correo y teléfono del responsable y cédula del representante legal son datos
   *   personales y no hacen falta para responder por el plan.
   *
   * Es de **sólo lectura** y siempre de una empresa concreta, la que viene firmada en el token.
   */
  async getAssistantAccountSummary(companyId: string) {
    const status = await this.getCompanyLicenseStatus(companyId);
    return {
      companyName: status.companyName,
      plan: status.plan,
      planLabel: status.licenseTypeLabel,
      status: status.status,
      isUsable: status.isUsable,
      blockReason: status.blockReason,
      activatedAt: status.licenseActivatedAt,
      expiresAt: status.periodEndsAt,
      daysRemaining: status.daysRemaining,
      isTrial: status.status === LicenseStatus.TRIAL,
      limits: {
        maxUsers: status.limits.maxUsers,
        maxProducts: status.limits.maxProducts,
      },
      usage: {
        users: status.usage.users,
        products: status.usage.products,
      },
    };
  }


  async activateCompany(companyId: string, dto: LicenseUpdateInput) {
    const before = await this.companySnapshot(companyId);
    const data = this.licenseData(dto);
    const displayName = this.displayNameValue(dto);
    const shouldCreateFreshLicense =
      before.licenseStatus === LicenseStatus.BLOCKED ||
      before.licenseStatus === LicenseStatus.EXPIRED ||
      !before.licenseKey ||
      (before.licenseExpiresAt && before.licenseExpiresAt.getTime() < Date.now());
    await this.prisma.$transaction(async (tx) => {
      await tx.company.update({
        where: { id: companyId },
        data: {
          ...data,
          ...(displayName ? { name: displayName } : {}),
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
      if (displayName) {
        await this.syncAppConfigCompanyName(tx, companyId, displayName);
      }
      await this.syncCompanyAccount(tx, companyId, dto, displayName);
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
    const displayName = this.displayNameValue(dto);
    await this.prisma.$transaction(async (tx) => {
      await tx.company.update({
        where: { id: companyId },
        data: {
          ...this.licenseData(dto),
          ...(displayName ? { name: displayName } : {}),
        },
        select: { id: true },
      });
      if (displayName) {
        await this.syncAppConfigCompanyName(tx, companyId, displayName);
      }
      await this.syncCompanyAccount(tx, companyId, dto, displayName);
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

  async getCompanyLicenseStatus(
    companyId: string,
    db: PrismaExecutor = this.prisma,
  ) {
    const company = await db.company.findUnique({
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
        maxWarehouses: true,
        planCode: true,
        planCatalogVersion: true,
        updatedAt: true,
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
      this.countBillableUsers(companyId, db),
      this.countBillableProducts(companyId, db),
      db.companyMember.findFirst({
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
      db.appConfig.findFirst({
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
      companyName: company.name,
      slug: company.slug,
      plan: company.plan,
      planCode: company.planCode,
      planCatalogVersion: company.planCatalogVersion,
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
      updatedAt: company.updatedAt,
      periodStartedAt: periodStart,
      periodEndsAt: periodEnd,
      licenseKey: company.licenseKey,
      notes: company.licenseNotes,
      daysRemaining: this.daysRemaining(periodEnd),
      limits: {
        maxUsers: effectiveLimits.maxUsers,
        maxProducts: effectiveLimits.maxProducts,
        maxWarehouses: company.maxWarehouses ?? 1,
        configuredMaxUsers: company.maxUsers,
        configuredMaxProducts: company.maxProducts,
        configuredMaxWarehouses: company.maxWarehouses,
      },
      usage: {
        users,
        products,
      },
      account: {
        businessName: company.name,
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

  async countBillableProducts(
    companyId: string,
    db: PrismaExecutor = this.prisma,
  ) {
    return db.product.count({ where: { companyId, archivedAt: null } });
  }

  async countBillableUsers(
    companyId: string,
    db: PrismaExecutor = this.prisma,
  ) {
    return db.user.count({ where: this.activeUserWhere(companyId) });
  }

  private async assertCanConsumeQuota(
    tx: Prisma.TransactionClient,
    companyId: string,
    resource: QuotaResource,
  ) {
    await this.lockCompanyQuota(tx, companyId, resource);
    const status = await this.getCompanyLicenseStatus(companyId, tx);
    if (!status.isUsable) {
      throw new ForbiddenException(status.blockReason ?? 'Licencia no activa');
    }

    // El cupo sale del **plan + las excepciones vigentes** del CRM, no solo del
    // numero copiado en la empresa: si soporte concede usuarios extra, tienen
    // que servir de verdad.
    const limits = await this.effectivePlanLimits(tx, companyId);
    const limit = resource === 'users' ? limits.maxUsers : limits.maxProducts;
    const current =
      resource === 'users' ? status.usage.users : status.usage.products;
    if (limit > 0 && current >= limit) {
      throw this.planLimitReachedException(resource, limit, current, status.plan);
    }
  }

  /** Cupos vigentes: catalogo del plan + excepcion del CRM, si la hay. */
  private async effectivePlanLimits(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    const [company, override] = await Promise.all([
      tx.company.findUnique({
        where: { id: companyId },
        select: {
          planCode: true,
          planCatalogVersion: true,
          maxUsers: true,
          maxProducts: true,
          maxWarehouses: true,
        },
      }),
      tx.licenseCompanyOverride.findUnique({ where: { companyId } }),
    ]);
    if (!company) throw new ForbiddenException('Empresa no encontrada');
    const plan = company.planCode
      ? await tx.licensePlan.findUnique({ where: { code: company.planCode } })
      : null;
    const entitlements = buildEntitlements(company, plan, override);
    return {
      maxUsers: entitlements.maxUsers,
      maxProducts: entitlements.maxProducts,
    };
  }

  private async lockCompanyQuota(
    tx: Prisma.TransactionClient,
    companyId: string,
    resource: QuotaResource,
  ) {
    await tx.$queryRaw`
      SELECT pg_advisory_xact_lock(hashtext(${`daleventas:quota:${resource}:${companyId}`})) IS NULL AS locked
    `;
  }

  private planLimitReachedException(
    resource: QuotaResource,
    limit: number,
    current: number,
    plan: string,
  ) {
    const label = resource === 'users' ? 'usuarios' : 'productos';
    const action =
      resource === 'users'
        ? 'crear mas usuarios'
        : 'seguir agregando productos';
    return new ConflictException({
      code: 'PLAN_LIMIT_REACHED',
      errorCode: 'PLAN_LIMIT_REACHED',
      resource,
      limit,
      current,
      plan,
      message: `Tu plan permite ${limit} ${label}. Aumenta el limite para ${action}.`,
    });
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

  private displayNameValue(dto: LicenseUpdateInput) {
    return (
      this.stringValue(dto.companyName) ??
      this.stringValue(dto.businessName) ??
      this.stringValue(dto.name)
    );
  }

  async syncAppConfigCompanyName(
    tx: Prisma.TransactionClient,
    companyId: string,
    companyName: string,
  ) {
    await tx.appConfig.upsert({
      where: { companyId },
      create: {
        id: `company_${companyId}`,
        companyId,
        companyName,
      },
      update: { companyName },
    });
  }

  private async syncCompanyAccount(
    tx: Prisma.TransactionClient,
    companyId: string,
    dto: LicenseUpdateInput,
    displayName?: string | null,
  ) {
    const appConfigData: Prisma.AppConfigUpdateInput = {};
    const companyName = displayName ?? this.fieldValue(dto, 'businessName');
    const taxId = this.fieldValue(dto, 'taxId');
    const phone = this.fieldValue(dto, 'businessPhone');
    const address = this.fieldValue(dto, 'businessAddress');
    const description = this.fieldValue(dto, 'businessType');
    const legalName =
      this.fieldValue(dto, 'legalRepresentativeName') ??
      this.fieldValue(dto, 'responsibleName');
    const legalCedula = this.fieldValue(dto, 'legalRepresentativeCedula');
    const legalRole = this.fieldValue(dto, 'legalRepresentativeRole');

    if (companyName !== undefined) appConfigData.companyName = companyName ?? '';
    if (taxId !== undefined) appConfigData.rnc = taxId ?? '';
    if (phone !== undefined) appConfigData.phone = phone ?? '';
    if (address !== undefined) appConfigData.address = address ?? '';
    if (description !== undefined) appConfigData.description = description ?? '';
    if (legalName !== undefined) {
      appConfigData.legalRepresentativeName = legalName ?? '';
    }
    if (legalCedula !== undefined) {
      appConfigData.legalRepresentativeCedula = legalCedula ?? '';
    }
    if (legalRole !== undefined) {
      appConfigData.legalRepresentativeRole = legalRole ?? '';
    }

    if (Object.keys(appConfigData).length > 0) {
      await tx.appConfig.upsert({
        where: { companyId },
        create: {
          id: `company_${companyId}`,
          companyId,
          companyName: companyName ?? '',
          rnc: taxId ?? '',
          phone: phone ?? '',
          address: address ?? '',
          description: description ?? '',
          legalRepresentativeName: legalName ?? '',
          legalRepresentativeCedula: legalCedula ?? '',
          legalRepresentativeRole: legalRole ?? '',
        },
        update: appConfigData,
      });
    }

    const responsibleData: Prisma.UserUpdateInput = {};
    const responsibleName = this.fieldValue(dto, 'responsibleName');
    const responsibleEmail = this.fieldValue(dto, 'responsibleEmail');
    const responsibleWhatsapp = this.fieldValue(dto, 'responsibleWhatsapp');
    if (responsibleName) responsibleData.nombreCompleto = responsibleName;
    if (responsibleEmail) responsibleData.email = responsibleEmail;
    if (responsibleWhatsapp) responsibleData.telefono = responsibleWhatsapp;
    if (Object.keys(responsibleData).length === 0) return;

    const owner = await tx.companyMember.findFirst({
      where: { companyId, status: 'ACTIVE', role: 'OWNER' },
      orderBy: { createdAt: 'asc' },
      select: { userId: true },
    });
    if (!owner) return;
    await tx.user.update({
      where: { id: owner.userId },
      data: responsibleData,
      select: { id: true },
    });
  }

  private requireAdmin(user: TenantUser) {
    if (!isAdminLike(user)) {
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

  private fieldValue(dto: Record<string, unknown>, key: string) {
    if (!Object.prototype.hasOwnProperty.call(dto, key)) return undefined;
    return this.stringValue(dto[key]);
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

  /**
   * Deja la empresa lista para borrarse.
   *
   * Antes se intentaba borrar tabla por tabla en orden alfabetico y fallaba con
   * 500: entre tablas de la misma empresa hay claves foraneas
   * `ON DELETE RESTRICT` (por ejemplo
   * `terminals(company_id, default_warehouse_id) -> warehouses`), asi que
   * `warehouses` se intentaba vaciar antes que `terminals`.
   *
   * La base ya esta bien disenada para esto: **todas** las claves foraneas hacia
   * `companies` son `ON DELETE CASCADE` salvo dos (`users`, que el llamador
   * desvincula, y `password_reset_audit_logs`, que se limpia aqui). Por eso el
   * borrado del grafo completo lo hace Postgres en una sola sentencia al
   * eliminar la empresa, y las dependencias RESTRICT entre tablas de la misma
   * empresa se resuelven juntas en lugar de en un orden arbitrario.
   *
   * Las pruebas de la base local confirman que `DELETE FROM companies` con datos
   * de inventario, terminales y comprobantes funciona.
   */
  private async deleteCompanyOwnedRows(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    // Unica tabla con datos de la empresa que **no** cae en cascada. El cast es
    // necesario: `$executeRawUnsafe` manda el parametro como texto y la columna
    // es uuid (Postgres no compara uuid con text sin conversion explicita).
    await tx.$executeRawUnsafe(
      'DELETE FROM "password_reset_audit_logs" WHERE company_id = $1::uuid',
      companyId,
    );
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

  publishCrmLicenseChange(companyId: string, action: string, license: unknown) {
    this.emitLicenseEvent(companyId, `license.crm.${action}`, license);
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
