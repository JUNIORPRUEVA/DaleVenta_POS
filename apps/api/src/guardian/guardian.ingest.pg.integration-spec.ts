/**
 * FASE 1 — Ingesta de incidentes contra PostgreSQL REAL (UAT aislado).
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 *   npx jest --runInBand src/guardian/guardian.ingest.pg.integration-spec.ts
 */
import { PrismaClient } from '@prisma/client';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianIncidentsService } from './guardian.incidents.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;

const RUN_ID = `gd${Date.now().toString(36)}`;

function event(overrides: Partial<GuardianIngestEventDto> = {}): GuardianIngestEventDto {
  return {
    eventId: `evt-${Math.random().toString(36).slice(2, 12)}-${Date.now().toString(36)}`,
    severity: 'SEV2',
    module: 'cash',
    operation: 'closeSession',
    exceptionType: 'TimeoutError',
    platform: 'windows',
    appVersion: '1.4.5',
    deviceId: `dev-${RUN_ID}`,
    occurredAt: new Date().toISOString(),
    message: 'timeout al cerrar turno',
    stack: 'Error: timeout\n    at CashService.close (cash.service.ts:412:19)',
    context: { saleId: 'abc', user: { email: 'a@b.com', password: 'secreto' } },
    ...overrides,
  } as GuardianIngestEventDto;
}

describeOnPg('Guardian ingest sobre PostgreSQL real', () => {
  let prisma: PrismaClient;
  let ingest: GuardianIngestService;
  let incidents: GuardianIncidentsService;
  let companyA: { id: string };
  let companyB: { id: string };
  const testStartedAt = new Date();

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_INGEST_ENABLED = 'true';
    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    const quota = new GuardianQuotaService(prisma as any);
    ingest = new GuardianIngestService(prisma as any, quota);
    incidents = new GuardianIncidentsService(prisma as any);

    companyA = await prisma.company.create({
      data: { name: `Guardian UAT A ${RUN_ID}`, slug: `guardian-uat-a-${RUN_ID}` },
      select: { id: true },
    });
    companyB = await prisma.company.create({
      data: { name: `Guardian UAT B ${RUN_ID}`, slug: `guardian-uat-b-${RUN_ID}` },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: `guardian-uat-` } } });
    await prisma?.guardianIncidentGroup.deleteMany({ where: { createdAt: { gte: testStartedAt } } });
    await prisma?.guardianAccessLog.deleteMany({ where: { createdAt: { gte: testStartedAt } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_ENABLED;
    delete process.env.GUARDIAN_INGEST_ENABLED;
  });

  it('reenviar el mismo eventId 10 veces produce 1 incidente y 9 duplicados', async () => {
    const sample = event({ eventId: `evt-dup-${RUN_ID}` });
    let accepted = 0;
    let duplicates = 0;

    for (let attempt = 0; attempt < 10; attempt += 1) {
      const outcome = await ingest.ingestBatch({
        companyId: companyA.id,
        userId: null,
        events: [sample],
        requestId: 'req-dup',
      });
      accepted += outcome.accepted;
      duplicates += outcome.duplicates;
    }

    const stored = await prisma.guardianIncident.count({
      where: { companyId: companyA.id, eventId: sample.eventId },
    });

    expect(accepted).toBe(1);
    expect(duplicates).toBe(9);
    expect(stored).toBe(1);
  }, 60_000);

  it('persiste antes de confirmar y guarda evidencias redactadas', async () => {
    const sample = event({ eventId: `evt-evidence-${RUN_ID}` });
    const outcome = await ingest.ingestBatch({
      companyId: companyA.id,
      userId: null,
      events: [sample],
    });

    expect(outcome.results[0].status).toBe('accepted');
    const incidentId = outcome.results[0].incidentId!;

    const stored = await prisma.guardianIncident.findUniqueOrThrow({
      where: { id: incidentId },
      include: { evidences: true, history: true },
    });

    const serialized = JSON.stringify(stored);
    expect(serialized).not.toContain('secreto');
    expect(serialized).not.toContain('a@b.com');
    expect(stored.evidences.length).toBeGreaterThanOrEqual(2);
    expect(stored.evidences.every((row) => row.redacted)).toBe(true);
    expect(stored.history).toHaveLength(1);
    expect(stored.history[0].toStatus).toBe('OPEN');
  }, 60_000);

  it('aísla empresas: mismo eventId en dos empresas y detalle cruzado imposible', async () => {
    const sharedEventId = `evt-shared-${RUN_ID}`;
    const [a, b] = await Promise.all([
      ingest.ingestBatch({ companyId: companyA.id, events: [event({ eventId: sharedEventId })] }),
      ingest.ingestBatch({ companyId: companyB.id, events: [event({ eventId: sharedEventId })] }),
    ]);

    expect(a.accepted).toBe(1);
    expect(b.accepted).toBe(1);

    const listA = await incidents.list({ companyId: companyA.id });
    const listB = await incidents.list({ companyId: companyB.id });
    const idsA = new Set(listA.items.map((item) => item.id));
    const idsB = listB.items.map((item) => item.id);
    const intersection = idsB.filter((id) => idsA.has(id));

    expect(idsA.size).toBeGreaterThan(0);
    expect(intersection).toEqual([]);

    const incidentA = a.results[0].incidentId!;
    await expect(incidents.detail(companyB.id, incidentA)).rejects.toThrow(/no encontrado/i);
  }, 60_000);

  it('un evento inválido no invalida el resto del lote', async () => {
    const good = event({ eventId: `evt-good-${RUN_ID}` });
    const bad = event({ eventId: `evt-bad-${RUN_ID}`, occurredAt: 'no-es-fecha' });

    const outcome = await ingest.ingestBatch({ companyId: companyA.id, events: [good, bad] });

    expect(outcome.accepted).toBe(1);
    expect(outcome.rejected).toBe(1);
    expect(outcome.results.find((item) => item.eventId === bad.eventId)?.reason).toBe(
      'INVALID_OCCURRED_AT',
    );
  }, 60_000);

  it('aplica cuotas por empresa cuando la política lo indica', async () => {
    await prisma.guardianCompanyQuota.upsert({
      where: { companyId: companyB.id },
      create: { companyId: companyB.id, enabled: true, incidentsPerHour: 1, incidentsPerDay: 1 },
      update: { enabled: true, incidentsPerHour: 1, incidentsPerDay: 1 },
    });

    const outcome = await ingest.ingestBatch({
      companyId: companyB.id,
      events: [event(), event(), event()],
    });

    expect(outcome.ok).toBe(false);
    expect(outcome.rejected).toBe(3);
    expect(outcome.results.every((item) => item.reason?.includes('QUOTA'))).toBe(true);

    await prisma.guardianCompanyQuota.delete({ where: { companyId: companyB.id } });
  }, 60_000);

  it('100 empresas x 5 eventos simultáneos: todo persistido, sin pérdidas', async () => {
    const companies = await Promise.all(
      Array.from({ length: 100 }, (_, index) =>
        prisma.company.create({
          data: {
            name: `Guardian UAT bulk ${index} ${RUN_ID}`,
            slug: `guardian-uat-bulk-${index}-${RUN_ID}`,
          },
          select: { id: true, slug: true },
        }),
      ),
    );

    const startedAt = Date.now();
    let accepted = 0;
    const concurrency = 20;

    for (let start = 0; start < companies.length; start += concurrency) {
      const slice = companies.slice(start, start + concurrency);
      const outcomes = await Promise.all(
        slice.map((company) =>
          ingest.ingestBatch({
            companyId: company.id,
            events: Array.from({ length: 5 }, () => event()),
          }),
        ),
      );
      accepted += outcomes.reduce((sum, outcome) => sum + outcome.accepted, 0);
    }

    const elapsedMs = Date.now() - startedAt;
    const stored = await prisma.guardianIncident.count({
      where: { companyId: { in: companies.map((company) => company.id) } },
    });

    // eslint-disable-next-line no-console
    console.log(
      `[uat] ingesta 100 empresas x 5 eventos: aceptados=${accepted} filas=${stored} ms=${elapsedMs} ` +
        `ritmo=${Math.round((stored / Math.max(1, elapsedMs)) * 1000)} inc/s`,
    );

    expect(accepted).toBe(500);
    expect(stored).toBe(500);
  }, 180_000);
});
