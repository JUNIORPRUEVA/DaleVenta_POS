import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CompanyStatus, Prisma } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';
import type { Request } from 'express';
import { PrismaService } from '../prisma/prisma.service';

type CompanySeed = {
  id: string;
  name: string;
  slug: string;
  licenseKey: string | null;
  plan: string;
  licenseStatus: string;
  maxUsers: number;
  maxProducts: number;
  createdAt: Date;
  updatedAt: Date;
};

type ModuleMetric = {
  code: string;
  total: number;
  today: number;
};

@Injectable()
export class UsageTelemetryService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(UsageTelemetryService.name);
  private timer?: NodeJS.Timeout;
  private running = false;
  private readonly requestTelemetrySeen = new Map<string, number>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  onModuleInit() {
    if (!this.enabled) return;
    const intervalMs = this.intervalMinutes * 60_000;
    const initialDelayMs = Math.min(60_000, Math.max(5_000, intervalMs / 6));
    this.timer = setInterval(() => {
      void this.flushAllCompanies('interval');
    }, intervalMs);
    setTimeout(() => {
      void this.flushAllCompanies('startup');
    }, initialDelayMs);
    this.logger.log(`Usage telemetry enabled; interval=${this.intervalMinutes}m`);
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  async flushAllCompanies(reason: 'startup' | 'interval' | 'manual') {
    if (!this.enabled) {
      return { ok: true, enabled: false, sent: 0, reason };
    }
    if (!this.appyraBaseUrl) {
      return { ok: true, enabled: true, sent: 0, skipped: true, reason: 'missing_appyra_base_url' };
    }
    if (this.running) {
      return { ok: true, enabled: true, skipped: true, reason: 'already_running' };
    }

    this.running = true;
    try {
      const companies = await this.prisma.company.findMany({
        where: { status: { not: CompanyStatus.ARCHIVED } },
        orderBy: { updatedAt: 'desc' },
        take: this.maxCompaniesPerRun,
        select: {
          id: true,
          name: true,
          slug: true,
          licenseKey: true,
          plan: true,
          licenseStatus: true,
          maxUsers: true,
          maxProducts: true,
          createdAt: true,
          updatedAt: true,
        },
      });

      let sent = 0;
      let failed = 0;
      for (const company of companies) {
        try {
          await this.sendToAppyra(await this.buildCompanyUsagePayload(company));
          sent += 1;
        } catch (error) {
          failed += 1;
          this.logger.warn(`Usage telemetry failed for company=${company.id}: ${this.errorMessage(error)}`);
        }
      }

      return { ok: true, enabled: true, reason, sent, failed, total: companies.length };
    } finally {
      this.running = false;
    }
  }

  recordRequestUsage(req: Request & { user?: { companyId?: string | null } }) {
    if (!this.enabled || !this.appyraBaseUrl) return;
    const companyId = req.user?.companyId?.trim();
    if (!companyId) return;

    const headers = req.headers;
    const client = this.requestClientContext(req);
    const featureCode = this.featureCodeFromPath(req.path || req.url || '');
    const throttleKey = `${companyId}:${client.deviceId}:${client.platform}:${featureCode}`;
    if (this.isRequestTelemetryThrottled(throttleKey)) return;

    void this.sendRequestUsage(companyId, {
      platform: client.platform,
      deviceFamily: client.deviceFamily,
      deviceId: client.deviceId,
      appVersion: this.headerValue(headers['x-client-app-version']) || this.appVersion,
      osVersion: this.headerValue(headers['x-client-os-version']),
      deviceModel: this.headerValue(headers['x-client-device-model']),
      featureCode,
      method: req.method,
      route: this.routeForMetrics(req.path || req.url || ''),
    });
  }

  private async buildCompanyUsagePayload(company: CompanySeed) {
    const now = new Date();
    const todayStart = this.startOfDay(now);
    const sevenDaysAgo = this.daysAgo(7);
    const monthStart = this.startOfMonth(now);

    const [
      usersTotal,
      usersActive,
      productsTotal,
      productsWithStock,
      clientsTotal,
      loginSessionsWeek,
      usersSeenWeek,
      lastApiActivity,
      salesToday,
      salesWeek,
      salesMonth,
      salesTotal,
      lastSale,
      salesAmountToday,
      salesAmountMonth,
      cashSessionsToday,
      cashSessionsTotal,
      openCashSessions,
      cashMovementsToday,
      quotesToday,
      quotesTotal,
      purchasesToday,
      purchasesTotal,
      purchaseInvoicesTotal,
      closesToday,
      closesTotal,
      fiscalInvoicesMonth,
      ncfSequencesTotal,
      serviceOrdersToday,
      serviceOrdersTotal,
      payrollEmployees,
    ] = await Promise.all([
      this.prisma.user.count({ where: { companyId: company.id } }),
      this.prisma.user.count({ where: { companyId: company.id, blocked: false } }),
      this.prisma.product.count({ where: { companyId: company.id } }),
      this.prisma.product.count({ where: { companyId: company.id, stock: { gt: new Prisma.Decimal(0) } } }),
      this.prisma.client.count({ where: { companyId: company.id, isDeleted: false } }),
      this.prisma.authSession.count({
        where: { companyId: company.id, revokedAt: null, lastUsedAt: { gte: sevenDaysAgo } },
      }),
      this.prisma.user.count({
        where: {
          companyId: company.id,
          authSessions: {
            some: { companyId: company.id, revokedAt: null, lastUsedAt: { gte: sevenDaysAgo } },
          },
        },
      }),
      this.prisma.authSession.findFirst({
        where: { companyId: company.id, lastUsedAt: { not: null } },
        orderBy: { lastUsedAt: 'desc' },
        select: { lastUsedAt: true },
      }),
      this.prisma.sale.count({ where: this.saleWhere(company.id, todayStart) }),
      this.prisma.sale.count({ where: this.saleWhere(company.id, sevenDaysAgo) }),
      this.prisma.sale.count({ where: this.saleWhere(company.id, monthStart) }),
      this.prisma.sale.count({ where: this.saleWhere(company.id) }),
      this.prisma.sale.findFirst({
        where: this.saleWhere(company.id),
        orderBy: { saleDate: 'desc' },
        select: { saleDate: true },
      }),
      this.prisma.sale.aggregate({ where: this.saleWhere(company.id, todayStart), _sum: { totalSold: true } }),
      this.prisma.sale.aggregate({ where: this.saleWhere(company.id, monthStart), _sum: { totalSold: true } }),
      this.prisma.cashSession.count({ where: { companyId: company.id, openedAt: { gte: todayStart } } }),
      this.prisma.cashSession.count({ where: { companyId: company.id } }),
      this.prisma.cashSession.count({ where: { companyId: company.id, status: 'OPEN' } }),
      this.prisma.cashMovement.count({ where: { companyId: company.id, createdAt: { gte: todayStart } } }),
      this.prisma.cotizacion.count({ where: { companyId: company.id, createdAt: { gte: todayStart } } }),
      this.prisma.cotizacion.count({ where: { companyId: company.id } }),
      this.prisma.purchaseOrder.count({ where: { companyId: company.id, createdAt: { gte: todayStart }, deletedAt: null } }),
      this.prisma.purchaseOrder.count({ where: { companyId: company.id, deletedAt: null } }),
      this.prisma.purchaseInvoice.count({ where: { companyId: company.id, deletedAt: null } }),
      this.prisma.close.count({ where: { companyId: company.id, date: { gte: todayStart } } }),
      this.prisma.close.count({ where: { companyId: company.id } }),
      this.prisma.fiscalInvoice.count({ where: { companyId: company.id, createdAt: { gte: monthStart } } }),
      this.prisma.ncfSequence.count({ where: { companyId: company.id, active: true } }),
      this.prisma.serviceOrder.count({
        where: { client: { companyId: company.id }, createdAt: { gte: todayStart } },
      }),
      this.prisma.serviceOrder.count({ where: { client: { companyId: company.id } } }),
      this.prisma.payrollEmployee.count({ where: { companyId: company.id } }),
    ]);

    const modules = [
      this.moduleMetric('sales', salesTotal, salesToday),
      this.moduleMetric('cash', cashSessionsTotal + cashMovementsToday, cashSessionsToday + cashMovementsToday),
      this.moduleMetric('inventory', productsTotal, 0),
      this.moduleMetric('customers', clientsTotal, 0),
      this.moduleMetric('quotes', quotesTotal, quotesToday),
      this.moduleMetric('purchases', purchasesTotal + purchaseInvoicesTotal, purchasesToday),
      this.moduleMetric('accounting', closesTotal + fiscalInvoicesMonth, closesToday + fiscalInvoicesMonth),
      this.moduleMetric('fiscal', ncfSequencesTotal + fiscalInvoicesMonth, fiscalInvoicesMonth),
      this.moduleMetric('service_orders', serviceOrdersTotal, serviceOrdersToday),
      this.moduleMetric('payroll', payrollEmployees, 0),
    ];
    const modulesUsed = modules.filter((module) => module.total > 0).map((module) => module.code);
    const modulesUsedToday = modules.filter((module) => module.today > 0).map((module) => module.code);
    const modulesUnused = modules.filter((module) => module.total <= 0).map((module) => module.code);

    return {
      app_code: 'DALEVENTAS_POS',
      project_code: 'DALEVENTAS_POS',
      business_id: company.id,
      license_key: company.licenseKey,
      device_id: `daleventas-api-${company.id}`,
      session_id: `summary-${this.isoDate(now)}`,
      app_version: this.appVersion,
      event_type: 'daily_usage_summary',
      occurred_at: now.toISOString(),
      active_seconds: this.estimateActiveSeconds(salesToday, cashSessionsToday, modulesUsedToday.length),
      metrics: {
        business_name: company.name,
        business_slug: company.slug,
        plan: company.plan,
        license_status: company.licenseStatus,
        max_users: company.maxUsers,
        max_products: company.maxProducts,
        users_total: usersTotal,
        users_active: usersActive,
        products_total: productsTotal,
        products_with_stock: productsWithStock,
        customers_total: clientsTotal,
        login_sessions_7_days: loginSessionsWeek,
        users_seen_7_days: usersSeenWeek,
        last_api_activity_at: lastApiActivity?.lastUsedAt?.toISOString() ?? '',
        sales_today: salesToday,
        sales_7_days: salesWeek,
        sales_this_month: salesMonth,
        sales_total: salesTotal,
        sales_amount_today: this.decimalToNumber(salesAmountToday._sum.totalSold),
        sales_amount_this_month: this.decimalToNumber(salesAmountMonth._sum.totalSold),
        last_sale_at: lastSale?.saleDate?.toISOString() ?? '',
        cash_sessions_today: cashSessionsToday,
        cash_sessions_total: cashSessionsTotal,
        open_cash_sessions: openCashSessions,
        cash_movements_today: cashMovementsToday,
        quotes_today: quotesToday,
        quotes_total: quotesTotal,
        purchases_today: purchasesToday,
        purchases_total: purchasesTotal,
        purchase_invoices_total: purchaseInvoicesTotal,
        closes_today: closesToday,
        closes_total: closesTotal,
        fiscal_invoices_month: fiscalInvoicesMonth,
        ncf_sequences_active: ncfSequencesTotal,
        service_orders_today: serviceOrdersToday,
        service_orders_total: serviceOrdersTotal,
        payroll_employees: payrollEmployees,
        modules_used: modulesUsed.join(','),
        modules_used_today: modulesUsedToday.join(','),
        modules_unused: modulesUnused.join(','),
        telemetry_reason: 'aggregated_business_usage',
      },
      metadata: {
        report_id: randomUUID(),
        generated_by: 'daleventas-api',
        generated_at: now.toISOString(),
        privacy: 'aggregate_metrics_only',
      },
    };
  }

  private async sendRequestUsage(
    companyId: string,
    client: {
      platform: string;
      deviceFamily: string;
      deviceId: string;
      appVersion: string;
      osVersion: string;
      deviceModel: string;
      featureCode: string;
      method: string;
      route: string;
    },
  ) {
    try {
      const company = await this.prisma.company.findUnique({
        where: { id: companyId },
        select: { id: true, name: true, slug: true, licenseKey: true },
      });
      if (!company) return;

      const now = new Date();
      await this.sendToAppyra({
        app_code: 'DALEVENTAS_POS',
        project_code: 'DALEVENTAS_POS',
        business_id: company.id,
        license_key: company.licenseKey,
        device_id: client.deviceId,
        session_id: `${client.deviceId}-${this.isoDate(now)}`,
        app_version: client.appVersion,
        event_type: 'client_request_heartbeat',
        occurred_at: now.toISOString(),
        active_seconds: this.requestHeartbeatSeconds,
        metrics: {
          business_name: company.name,
          business_slug: company.slug,
          platform: client.platform,
          device_family: client.deviceFamily,
          os_version: client.osVersion,
          device_model: client.deviceModel,
          feature_code: client.featureCode,
          request_method: client.method,
          route: client.route,
          telemetry_reason: 'client_platform_usage',
        },
        metadata: {
          generated_by: 'daleventas-api',
          generated_at: now.toISOString(),
          privacy: 'technical_usage_only',
        },
      });
    } catch (error) {
      this.logger.debug(`Client usage telemetry skipped: ${this.errorMessage(error)}`);
    }
  }

  private async sendToAppyra(payload: Record<string, unknown>) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(`${this.appyraBaseUrl}/api/usage/heartbeat`, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          ...(this.ingestSecret ? { 'x-usage-ingest-secret': this.ingestSecret } : {}),
        },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        const text = await response.text().catch(() => '');
        throw new Error(`Appyra usage ingest failed ${response.status}: ${text.slice(0, 240)}`);
      }
    } finally {
      clearTimeout(timeout);
    }
  }

  private saleWhere(companyId: string, from?: Date): Prisma.SaleWhereInput {
    return {
      companyId,
      kind: 'invoice',
      isDeleted: false,
      ...(from ? { saleDate: { gte: from } } : {}),
    };
  }

  private moduleMetric(code: string, total: number, today: number): ModuleMetric {
    return { code, total, today };
  }

  private estimateActiveSeconds(salesToday: number, cashSessionsToday: number, modulesUsedToday: number) {
    const seconds = salesToday * 90 + cashSessionsToday * 600 + modulesUsedToday * 180;
    return Math.min(86400, Math.max(0, seconds));
  }

  private requestClientContext(req: Request) {
    const headers = req.headers;
    const explicitPlatform = this.normalizePlatform(this.headerValue(headers['x-client-platform']));
    const userAgent = this.headerValue(headers['user-agent']);
    const platform = explicitPlatform || this.platformFromUserAgent(userAgent);
    const deviceFamily =
      this.normalizeDeviceFamily(this.headerValue(headers['x-client-device-family'])) ||
      this.deviceFamilyForPlatform(platform);
    const rawDeviceId = this.headerValue(headers['x-client-device-id']);
    const deviceId = rawDeviceId
      ? `client-${this.sanitizeToken(rawDeviceId, 96)}`
      : `ua-${this.shortHash(`${platform}:${userAgent || 'unknown'}`)}`;
    return { platform, deviceFamily, deviceId };
  }

  private isRequestTelemetryThrottled(key: string) {
    const now = Date.now();
    const previous = this.requestTelemetrySeen.get(key) ?? 0;
    if (now - previous < this.requestTelemetryThrottleMs) return true;
    this.requestTelemetrySeen.set(key, now);
    if (this.requestTelemetrySeen.size > 5000) {
      const cutoff = now - this.requestTelemetryThrottleMs * 3;
      for (const [entryKey, value] of this.requestTelemetrySeen) {
        if (value < cutoff) this.requestTelemetrySeen.delete(entryKey);
      }
    }
    return false;
  }

  private platformFromUserAgent(userAgent: string) {
    const ua = userAgent.toLowerCase();
    if (ua.includes('android')) return 'android';
    if (ua.includes('iphone') || ua.includes('ipad') || ua.includes('ios')) return 'ios';
    if (ua.includes('windows')) return 'windows';
    if (ua.includes('mac os') || ua.includes('macintosh')) return 'macos';
    if (ua.includes('linux')) return 'linux';
    if (ua.includes('mozilla') || ua.includes('chrome') || ua.includes('safari')) return 'web';
    if (ua.includes('dart')) return 'unknown_native';
    return 'unknown';
  }

  private deviceFamilyForPlatform(platform: string) {
    if (platform === 'android' || platform === 'ios') return 'mobile';
    if (platform === 'windows' || platform === 'macos' || platform === 'linux') return 'desktop';
    if (platform === 'web') return 'web';
    return 'unknown';
  }

  private normalizePlatform(value: string) {
    const platform = this.sanitizeToken(value.toLowerCase(), 40);
    const allowed = new Set(['windows', 'android', 'ios', 'web', 'macos', 'linux']);
    return allowed.has(platform) ? platform : '';
  }

  private normalizeDeviceFamily(value: string) {
    const family = this.sanitizeToken(value.toLowerCase(), 40);
    const allowed = new Set(['desktop', 'mobile', 'tablet', 'web', 'unknown']);
    return allowed.has(family) ? family : '';
  }

  private featureCodeFromPath(path: string) {
    const clean = path.split('?')[0].split('/').filter(Boolean);
    const first = clean[0] || 'api';
    return this.sanitizeToken(first.toLowerCase().replace(/-/g, '_'), 60) || 'api';
  }

  private routeForMetrics(path: string) {
    const clean = path.split('?')[0].split('/').filter(Boolean).slice(0, 2).join('/');
    return clean ? `/${this.sanitizeRoute(clean)}` : '/';
  }

  private sanitizeRoute(value: string) {
    return value.replace(/[^a-zA-Z0-9/_-]/g, '').slice(0, 120);
  }

  private sanitizeToken(value: string, maxLength: number) {
    return value.replace(/[^a-zA-Z0-9_.-]/g, '').slice(0, maxLength);
  }

  private shortHash(value: string) {
    return createHash('sha256').update(value).digest('hex').slice(0, 24);
  }

  private headerValue(value: string | string[] | undefined) {
    const text = Array.isArray(value) ? value[0] : value;
    return (text ?? '').toString().trim().slice(0, 160);
  }

  private startOfDay(date: Date) {
    const { year, month, day } = this.timeZoneParts(date);
    return this.zonedDateToUtc(year, month, day);
  }

  private startOfMonth(date: Date) {
    const { year, month } = this.timeZoneParts(date);
    return this.zonedDateToUtc(year, month, 1);
  }

  private daysAgo(days: number) {
    return new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  }

  private isoDate(date: Date) {
    const { year, month, day } = this.timeZoneParts(date);
    return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  }

  private decimalToNumber(value: Prisma.Decimal | null | undefined) {
    if (!value) return 0;
    return Number(value.toFixed(2));
  }

  private errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }

  private get enabled() {
    return (this.config.get<string>('APPYRA_USAGE_TELEMETRY_ENABLED') ?? 'true').trim().toLowerCase() !== 'false';
  }

  private get appyraBaseUrl() {
    return (
      this.config.get<string>('APPYRA_USAGE_API_BASE_URL') ??
      this.config.get<string>('FULLPOS_INTEGRATION_BASE_URL') ??
      ''
    ).trim().replace(/\/+$/, '');
  }

  private get ingestSecret() {
    return (this.config.get<string>('APPYRA_USAGE_INGEST_SECRET') ?? '').trim();
  }

  private get intervalMinutes() {
    const raw = Number(this.config.get<string>('APPYRA_USAGE_TELEMETRY_INTERVAL_MINUTES') ?? '30');
    return Number.isFinite(raw) ? Math.max(5, raw) : 30;
  }

  private get maxCompaniesPerRun() {
    const raw = Number(this.config.get<string>('APPYRA_USAGE_TELEMETRY_COMPANY_LIMIT') ?? '250');
    return Number.isFinite(raw) ? Math.min(1000, Math.max(1, raw)) : 250;
  }

  private get timeoutMs() {
    const raw = Number(this.config.get<string>('APPYRA_USAGE_TELEMETRY_TIMEOUT_MS') ?? '12000');
    return Number.isFinite(raw) ? Math.max(1000, raw) : 12000;
  }

  private get requestTelemetryThrottleMs() {
    const raw = Number(this.config.get<string>('APPYRA_USAGE_CLIENT_THROTTLE_SECONDS') ?? '300');
    const seconds = Number.isFinite(raw) ? Math.max(60, raw) : 300;
    return seconds * 1000;
  }

  private get requestHeartbeatSeconds() {
    const raw = Number(this.config.get<string>('APPYRA_USAGE_CLIENT_ACTIVE_SECONDS') ?? '60');
    return Number.isFinite(raw) ? Math.min(600, Math.max(0, raw)) : 60;
  }

  private get appVersion() {
    return (this.config.get<string>('APP_VERSION') ?? process.env.npm_package_version ?? 'api').trim();
  }

  private get timeZone() {
    return (this.config.get<string>('APPYRA_USAGE_TELEMETRY_TIME_ZONE') ?? 'America/Santo_Domingo').trim();
  }

  private timeZoneParts(date: Date) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: this.timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const value = (type: string) => Number(parts.find((part) => part.type === type)?.value);
    return { year: value('year'), month: value('month'), day: value('day') };
  }

  private zonedDateToUtc(year: number, month: number, day: number) {
    const utcGuess = new Date(Date.UTC(year, month - 1, day));
    return new Date(utcGuess.getTime() - this.timeZoneOffsetMs(utcGuess));
  }

  private timeZoneOffsetMs(date: Date) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: this.timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    }).formatToParts(date);
    const value = (type: string) => Number(parts.find((part) => part.type === type)?.value);
    const asUtc = Date.UTC(
      value('year'),
      value('month') - 1,
      value('day'),
      value('hour'),
      value('minute'),
      value('second'),
    );
    return asUtc - date.getTime();
  }
}
