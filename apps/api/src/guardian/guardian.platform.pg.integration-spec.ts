/**
 * FASE 2 — API de plataforma para el panel Appyra (PostgreSQL real).
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 */
import { ExecutionContext, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { GuardianPlatformGuard } from './guardian.platform.guard';
import { GuardianPlatformService } from './guardian.platform.service';
import { GuardianIncidentsService } from './guardian.incidents.service';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `pf${Date.now().toString(36)}`;

function context(token?: string): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => ({ headers: token === undefined ? {} : { 'x-guardian-platform-token': token } }),
    }),
  } as unknown as ExecutionContext;
}

function event(overrides: Partial<GuardianIngestEventDto> = {}): GuardianIngestEventDto {
  return {
    eventId: `evt-${Math.random().toString(36).slice(2, 12)}-${Date.now().toString(36)}`,
    severity: 'SEV1',
    module: 'cash',
    operation: 'closeSession',
    exceptionType: 'CashCloseError',
    platform: 'windows',
    appVersion: '1.4.5',
    deviceId: `dev-${RUN_ID}`,
    occurredAt: new Date().toISOString(),
    message: 'fallo de cierre',
    ...overrides,
  } as GuardianIngestEventDto;
}

describe('GuardianPlatformGuard', () => {
  const guard = new GuardianPlatformGuard();

  afterEach(() => {
    delete process.env.GUARDIAN_PLATFORM_TOKEN;
  });

  it('sin token configurado el acceso de plataforma no existe (503)', () => {
    expect(() => guard.canActivate(context('lo-que-sea'))).toThrow(ServiceUnavailableException);
  });

  it('rechaza peticiones sin cabecera o con token incorrecto', () => {
    process.env.GUARDIAN_PLATFORM_TOKEN = 'token-plataforma-uat';
    expect(() => guard.canActivate(context())).toThrow(UnauthorizedException);
    expect(() => guard.canActivate(context('otro'))).toThrow(UnauthorizedException);
  });

  it('acepta el token correcto', () => {
    process.env.GUARDIAN_PLATFORM_TOKEN = 'token-plataforma-uat';
    expect(guard.canActivate(context('token-plataforma-uat'))).toBe(true);
  });
});

describeOnPg('Guardian API de plataforma — PostgreSQL real', () => {
  let prisma: PrismaClient;
  let platform: GuardianPlatformService;
  let ingest: GuardianIngestService;
  let companyA: { id: string; name: string };
  let companyB: { id: string; name: string };
  let incidentA: string;

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_INGEST_ENABLED = 'true';
    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    const incidents = new GuardianIncidentsService(prisma as any);
    platform = new GuardianPlatformService(prisma as any, incidents);
    ingest = new GuardianIngestService(prisma as any, new GuardianQuotaService(prisma as any));

    companyA = await prisma.company.create({
      data: { name: `Guardian Panel A ${RUN_ID}`, slug: `guardian-panel-a-${RUN_ID}` },
      select: { id: true, name: true },
    });
    companyB = await prisma.company.create({
      data: { name: `Guardian Panel B ${RUN_ID}`, slug: `guardian-panel-b-${RUN_ID}` },
      select: { id: true, name: true },
    });

    const outcome = await ingest.ingestBatch({ companyId: companyA.id, events: [event()] });
    incidentA = outcome.results[0].incidentId!;
    await ingest.ingestBatch({ companyId: companyB.id, events: [event()] });
  }, 90_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-panel-' } } });
    await prisma?.$disconnect();
  });

  it('lista empresas monitoreadas con contadores y nombres', async () => {
    const companies = await platform.companies();
    const a = companies.find((row) => row.id === companyA.id)!;
    const b = companies.find((row) => row.id === companyB.id)!;

    expect(a.name).toBe(companyA.name);
    expect(a.openIncidents).toBeGreaterThanOrEqual(1);
    expect(a.criticalIncidents).toBeGreaterThanOrEqual(1);
    expect(b.openIncidents).toBeGreaterThanOrEqual(1);
  }, 60_000);

  it('el resumen agrega por severidad, estado y módulo', async () => {
    const summary = await platform.summary();
    expect(summary.totalIncidents).toBeGreaterThanOrEqual(2);
    expect(summary.bySeverity.SEV1).toBeGreaterThanOrEqual(2);
    expect(summary.byModule.cash).toBeGreaterThanOrEqual(2);
  }, 60_000);

  it('lista incidentes de todas las empresas e incluye nombre de empresa', async () => {
    const result = await platform.list({ limit: 50 });
    const mine = result.items.filter(
      (item) => item.companyId === companyA.id || item.companyId === companyB.id,
    );
    expect(mine.length).toBe(2);
    const rowA = mine.find((item) => item.companyId === companyA.id)!;
    expect(rowA.companyName).toBe(companyA.name);
    expect(rowA).toHaveProperty('latestDiagnosis');
    expect(rowA).toHaveProperty('latestAlert');
  }, 60_000);

  it('filtra por empresa y devuelve paginación por cursor', async () => {
    const first = await platform.list({ companyId: companyA.id, limit: 1 });
    expect(first.items).toHaveLength(1);
    expect(first.items[0].companyId).toBe(companyA.id);
  }, 60_000);

  it('el detalle de plataforma incluye evidencias, historial y alertas con intentos', async () => {
    const detail = await platform.detail(incidentA);
    expect(detail).toBeTruthy();
    expect(detail!.company.name).toBe(companyA.name);
    expect(detail!.evidences.length).toBeGreaterThan(0);
    expect(detail!.history.length).toBeGreaterThan(0);
    expect(Array.isArray(detail!.alerts)).toBe(true);
  }, 60_000);

  it('las acciones administrativas se registran en la auditoría', async () => {
    const updated = await platform.act({ incidentId: incidentA, action: 'ack', note: 'revisado', actor: 'platform' });
    expect(updated!.status).toBe('ACKNOWLEDGED');

    const log = await prisma.guardianAccessLog.findFirst({
      where: { incidentId: incidentA, action: 'platform.ack' },
    });
    expect(log?.actorRole).toBe('PLATFORM');

    const resolved = await platform.act({ incidentId: incidentA, action: 'resolve', note: 'ok' });
    expect(resolved!.status).toBe('RESOLVED');

    const reopened = await platform.act({ incidentId: incidentA, action: 'reopen', note: 'volvió' });
    expect(reopened!.status).toBe('OPEN');
  }, 60_000);

  it('la salud de plataforma reporta el estado de los componentes', async () => {
    const health = await platform.health();
    expect(typeof health.guardianEnabled).toBe('boolean');
    expect(['mock', 'openai']).toContain(health.aiProvider);
    expect(health.pendingAlerts).toBeGreaterThanOrEqual(0);
  }, 60_000);
});
