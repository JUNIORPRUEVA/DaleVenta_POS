/**
 * FASE 8 — Opt-in de Guardian por empresa sobre PostgreSQL real.
 *
 * Cubre, con evidencia y sin tocar bases compartidas:
 *   1. Empresa nueva: Guardian DESACTIVADO por defecto → ingesta rechazada.
 *   2. Activación explícita → ingesta aceptada.
 *   3. Desactivación → ingesta rechazada y cola pendiente neutralizada.
 *   4. Una credencial de máquina válida NO salta la desactivación.
 *   5. Aislamiento entre empresas (A activada, B desactivada).
 *   6. Desactivar NO borra el historial.
 *
 * Ejecutar con GUARDIAN_UAT_DATABASE_URL apuntando a una base EFÍMERA.
 */
import { PrismaClient } from '@prisma/client';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianMachineService, hashGuardianMachineKey } from './guardian.machine.service';
import { GuardianPlatformService } from './guardian.platform.service';
import { GuardianIncidentsService } from './guardian.incidents.service';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';
import { GUARDIAN_COMPANY_DISABLED } from './guardian.company.policy';

const DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = DATABASE_URL ? describe : describe.skip;
const RUN_ID = `optin${Date.now().toString(36)}`;

function event(overrides: Partial<GuardianIngestEventDto> = {}): GuardianIngestEventDto {
  return {
    eventId: `evt-${Math.random().toString(36).slice(2, 12)}-${Date.now().toString(36)}`,
    severity: 'SEV2',
    module: 'cash',
    operation: 'closeSession',
    exceptionType: 'TimeoutError',
    platform: 'windows',
    appVersion: '1.0.6+149',
    deviceId: `dev-${RUN_ID}`,
    occurredAt: new Date().toISOString(),
    message: 'timeout',
    stack: 'Error: timeout\n    at CashService.close (cash.service.ts:10:1)',
    ...overrides,
  } as GuardianIngestEventDto;
}

describeOnPg('Guardian opt-in por empresa sobre PostgreSQL real', () => {
  let prisma: PrismaClient;
  let ingest: GuardianIngestService;
  let machine: GuardianMachineService;
  let platform: GuardianPlatformService;
  let companyA: { id: string };
  let companyB: { id: string };

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_INGEST_ENABLED = 'true';
    prisma = new PrismaClient({ datasources: { db: { url: DATABASE_URL } } });
    await prisma.$connect();
    ingest = new GuardianIngestService(prisma as any, new GuardianQuotaService(prisma as any));
    machine = new GuardianMachineService(prisma as any);
    platform = new GuardianPlatformService(
      prisma as any,
      new GuardianIncidentsService(prisma as any),
    );

    companyA = await prisma.company.create({
      data: { name: `Optin A ${RUN_ID}`, slug: `optin-a-${RUN_ID}` },
      select: { id: true },
    });
    companyB = await prisma.company.create({
      data: { name: `Optin B ${RUN_ID}`, slug: `optin-b-${RUN_ID}` },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { contains: RUN_ID } } });
    await prisma?.$disconnect();
  });

  it('una empresa nueva nace con Guardian DESACTIVADO', async () => {
    const rows = await prisma.company.findMany({
      where: { id: { in: [companyA.id, companyB.id] } },
      select: { guardianEnabled: true, guardianEnabledAt: true },
    });
    expect(rows).toHaveLength(2);
    expect(rows.every((row) => row.guardianEnabled === false)).toBe(true);
    expect(rows.every((row) => row.guardianEnabledAt === null)).toBe(true);
  }, 30_000);

  it('con Guardian desactivado la ingesta se rechaza sin persistir', async () => {
    const outcome = await ingest.ingestBatch({ companyId: companyA.id, events: [event()] });
    expect(outcome.accepted).toBe(0);
    expect(outcome.disabled).toBe(true);
    expect(outcome.results[0]).toMatchObject({ status: 'rejected', reason: GUARDIAN_COMPANY_DISABLED });

    const stored = await prisma.guardianIncident.count({ where: { companyId: companyA.id } });
    expect(stored).toBe(0);
  }, 30_000);

  it('activada explícitamente, la ingesta se acepta', async () => {
    const updated = await platform.setCompanyGuardianEnabled(companyA.id, true);
    expect(updated?.guardianEnabled).toBe(true);

    const outcome = await ingest.ingestBatch({ companyId: companyA.id, events: [event()] });
    expect(outcome.accepted).toBe(1);
    expect(outcome.disabled).toBeUndefined();
  }, 30_000);

  it('aislamiento: A activada acepta, B desactivada rechaza el mismo evento', async () => {
    const sameEvent = event();
    const [outcomeA, outcomeB] = await Promise.all([
      ingest.ingestBatch({ companyId: companyA.id, events: [sameEvent] }),
      ingest.ingestBatch({ companyId: companyB.id, events: [sameEvent] }),
    ]);

    expect(outcomeA.accepted).toBe(1);
    expect(outcomeB.accepted).toBe(0);
    expect(outcomeB.results[0]).toMatchObject({ reason: GUARDIAN_COMPANY_DISABLED });

    const inB = await prisma.guardianIncident.count({ where: { companyId: companyB.id } });
    expect(inB).toBe(0);
  }, 30_000);

  it('una credencial de máquina válida no salta la desactivación de la empresa', async () => {
    const rawKey = `gmk_${'b'.repeat(40)}`;
    await prisma.guardianMachineCredential.create({
      data: {
        companyId: companyB.id,
        label: `cred-${RUN_ID}`,
        keyHash: hashGuardianMachineKey(rawKey),
        keyPrefix: rawKey.slice(0, 12),
        enabled: true,
      },
    });

    // Empresa B sigue desactivada: la credencial es válida pero no autoriza.
    await expect(machine.authenticate(rawKey)).resolves.toBeNull();

    // Con la empresa activada, la misma credencial sí autentica.
    await platform.setCompanyGuardianEnabled(companyB.id, true);
    const identity = await machine.authenticate(rawKey);
    expect(identity).toMatchObject({ companyId: companyB.id });
  }, 30_000);

  it('desactivar bloquea nuevas ingestas y no borra el historial', async () => {
    const before = await prisma.guardianIncident.count({ where: { companyId: companyA.id } });
    expect(before).toBeGreaterThan(0);

    // Deja un incidente en cola para comprobar la neutralización.
    const pending = await ingest.ingestBatch({ companyId: companyA.id, events: [event()] });
    expect(pending.accepted).toBe(1);

    await platform.setCompanyGuardianEnabled(companyA.id, false);

    const after = await prisma.guardianIncident.count({ where: { companyId: companyA.id } });
    expect(after).toBeGreaterThanOrEqual(before + 1); // nada se borró

    const inQueue = await prisma.guardianIncident.count({
      where: { companyId: companyA.id, processingState: 'PENDING' },
    });
    expect(inQueue).toBe(0); // lo pendiente pasó a SKIPPED

    const rejected = await ingest.ingestBatch({ companyId: companyA.id, events: [event()] });
    expect(rejected.accepted).toBe(0);
    expect(rejected.disabled).toBe(true);
  }, 60_000);
});
