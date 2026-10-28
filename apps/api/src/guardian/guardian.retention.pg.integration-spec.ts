/**
 * FASE C — Retención y purga sobre PostgreSQL REAL.
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 */
import { PrismaClient } from '@prisma/client';
import { GuardianRetentionService } from './guardian.retention.service';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `rt${Date.now().toString(36)}`;

describeOnPg('Guardian retención — PostgreSQL real', () => {
  let prisma: PrismaClient;
  let service: GuardianRetentionService;
  let company: { id: string };
  const ids: Record<string, string> = {};

  const seedIncident = async (params: {
    key: string;
    severity: 'SEV1' | 'SEV2' | 'SEV3' | 'SEV4';
    status: 'OPEN' | 'RESOLVED';
    daysAgo: number;
  }) => {
    const row = await prisma.guardianIncident.create({
      data: {
        eventId: `evt-${params.key}-${RUN_ID}`,
        companyId: company.id,
        fingerprint: `fp-${params.key}`,
        module: 'cash',
        operation: 'closeSession',
        severity: params.severity,
        status: params.status,
        occurredAt: new Date(Date.now() - params.daysAgo * 24 * 60 * 60 * 1000),
        payload: {},
        evidences: {
          create: [{ kind: 'context', label: 'ctx', content: { a: 1 } }],
        },
      },
      select: { id: true },
    });
    ids[params.key] = row.id;
    return row.id;
  };

  beforeAll(async () => {
    process.env.GUARDIAN_RETENTION_DAYS = '90';
    process.env.GUARDIAN_RETENTION_CRITICAL_DAYS = '365';
    process.env.GUARDIAN_RETENTION_MAX_PER_COMPANY = '5000';

    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    service = new GuardianRetentionService(prisma as any);

    company = await prisma.company.create({
      data: { name: `Guardian Retención ${RUN_ID}`, slug: `guardian-retention-${RUN_ID}` },
      select: { id: true },
    });

    await seedIncident({ key: 'low-old', severity: 'SEV4', status: 'RESOLVED', daysAgo: 120 });
    await seedIncident({ key: 'low-recent', severity: 'SEV4', status: 'RESOLVED', daysAgo: 5 });
    await seedIncident({ key: 'low-open', severity: 'SEV4', status: 'OPEN', daysAgo: 200 });
    await seedIncident({ key: 'critical-200', severity: 'SEV1', status: 'RESOLVED', daysAgo: 200 });
    await seedIncident({ key: 'critical-400', severity: 'SEV1', status: 'RESOLVED', daysAgo: 400 });
  }, 90_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-retention-' } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_RETENTION_DAYS;
    delete process.env.GUARDIAN_RETENTION_CRITICAL_DAYS;
    delete process.env.GUARDIAN_RETENTION_MAX_PER_COMPANY;
  });

  it('en modo simulación cuenta sin borrar nada', async () => {
    const before = await prisma.guardianIncident.count({ where: { companyId: company.id } });
    const result = await service.run({ dryRun: true });
    const after = await prisma.guardianIncident.count({ where: { companyId: company.id } });

    expect(result.dryRun).toBe(true);
    expect(result.expiredIncidents).toBeGreaterThanOrEqual(2);
    expect(result.keptForInvestigation).toBeGreaterThanOrEqual(1);
    expect(before).toBe(after);
  }, 60_000);

  it('aplica solo a incidentes cerrados y fuera de retención, conservando críticos y abiertos', async () => {
    const result = await service.run({ dryRun: false });

    expect(result.expiredIncidents).toBeGreaterThanOrEqual(2);

    const remaining = await prisma.guardianIncident.findMany({
      where: { companyId: company.id },
      select: { id: true },
    });
    const remainingIds = remaining.map((row) => row.id);

    expect(remainingIds).not.toContain(ids['low-old']);
    expect(remainingIds).not.toContain(ids['critical-400']);
    expect(remainingIds).toContain(ids['low-recent']);
    expect(remainingIds).toContain(ids['low-open']);
    expect(remainingIds).toContain(ids['critical-200']);
  }, 60_000);

  it('la eliminación arrastra evidencias (FK en cascada)', async () => {
    const evidences = await prisma.guardianEvidence.count({
      where: { incidentId: ids['low-old'] },
    });
    expect(evidences).toBe(0);
  }, 30_000);

  it('reporta métricas de almacenamiento por tabla', async () => {
    const metrics = await service.metrics();
    expect(metrics.byTable.length).toBeGreaterThan(0);
    expect(metrics.totalBytes).toBeGreaterThan(0);
    expect(metrics.byTable.some((row) => row.table === 'guardian_incidents')).toBe(true);
  }, 30_000);

  it('nunca borra un incidente con alerta pendiente de entrega', async () => {
    const incidentId = await seedIncident({
      key: 'with-alert',
      severity: 'SEV4',
      status: 'RESOLVED',
      daysAgo: 200,
    });
    await prisma.guardianAlert.create({
      data: {
        incidentId,
        channel: 'whatsapp_cloud',
        recipientHash: 'hash',
        dedupeKey: `guardian:alert:initial:${incidentId}`,
        kind: 'initial',
        state: 'PENDING',
      },
    });

    await service.run({ dryRun: false });

    const stillThere = await prisma.guardianIncident.findUnique({ where: { id: incidentId } });
    expect(stillThere).not.toBeNull();
  }, 60_000);

  it('borra en lotes acotados y es reanudable entre ejecuciones', async () => {
    // Dos candidatos claramente fuera de retención, borrados con lote de 1.
    await seedIncident({ key: 'batch-a', severity: 'SEV4', status: 'CLOSED', daysAgo: 400 });
    await seedIncident({ key: 'batch-b', severity: 'SEV4', status: 'CLOSED', daysAgo: 401 });

    const previousBatch = process.env.GUARDIAN_RETENTION_BATCH_SIZE;
    const previousMax = process.env.GUARDIAN_RETENTION_MAX_BATCHES;
    process.env.GUARDIAN_RETENTION_BATCH_SIZE = '1';
    process.env.GUARDIAN_RETENTION_MAX_BATCHES = '1';
    try {
      // Primera ejecución: un solo lote de un incidente.
      const first = await service.run({ dryRun: false });
      expect(first.batches).toBe(1);
      expect(first.deletedInBatches).toBe(1);

      // Segunda ejecución: continúa donde quedó, sin repetir trabajo.
      const second = await service.run({ dryRun: false });
      expect(second.deletedInBatches).toBe(1);
      expect(second.batches).toBe(1);

      // Tercera: ya no queda nada que borrar en ese predicado.
      const third = await service.run({ dryRun: false });
      expect(third.deletedInBatches).toBe(0);
    } finally {
      if (previousBatch === undefined) delete process.env.GUARDIAN_RETENTION_BATCH_SIZE;
      else process.env.GUARDIAN_RETENTION_BATCH_SIZE = previousBatch;
      if (previousMax === undefined) delete process.env.GUARDIAN_RETENTION_MAX_BATCHES;
      else process.env.GUARDIAN_RETENTION_MAX_BATCHES = previousMax;
    }
  }, 120_000);
});
