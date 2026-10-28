/**
 * Credenciales de máquina contra PostgreSQL REAL: aislamiento multiempresa.
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55501/guardian_uat_test'
 *   npx jest --runInBand src/guardian/guardian.machine.pg.integration-spec.ts
 *
 * Prueba lo que los mocks no pueden probar: que la búsqueda por hash funciona
 * con el índice real y que dos empresas distintas no se mezclan.
 */
import { PrismaClient } from '@prisma/client';
import { GuardianMachineService, hashGuardianMachineKey } from './guardian.machine.service';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;

const RUN_ID = `gm${Date.now().toString(36)}`;

describeOnPg('credenciales de máquina sobre PostgreSQL real', () => {
  let prisma: PrismaClient;
  let machine: GuardianMachineService;
  let companyA: { id: string };
  let companyB: { id: string };
  const testStartedAt = new Date();
  const keyA = `gmk_${RUN_ID}a`.padEnd(48, 'a');
  const keyB = `gmk_${RUN_ID}b`.padEnd(48, 'b');

  beforeAll(async () => {
    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    machine = new GuardianMachineService(prisma as any);

    companyA = await prisma.company.create({
      data: { name: `Guardian Machine A ${RUN_ID}`, slug: `guardian-machine-a-${RUN_ID}` },
      select: { id: true },
    });
    companyB = await prisma.company.create({
      data: { name: `Guardian Machine B ${RUN_ID}`, slug: `guardian-machine-b-${RUN_ID}` },
      select: { id: true },
    });

    await prisma.guardianMachineCredential.create({
      data: {
        companyId: companyA.id,
        label: 'POS UAT A',
        keyHash: hashGuardianMachineKey(keyA),
        keyPrefix: keyA.slice(0, 12),
        installId: 'pos-a',
        enabled: true,
      },
    });
    await prisma.guardianMachineCredential.create({
      data: {
        companyId: companyB.id,
        label: 'POS UAT B',
        keyHash: hashGuardianMachineKey(keyB),
        keyPrefix: keyB.slice(0, 12),
        installId: 'pos-b',
        enabled: true,
      },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-machine-' } } });
    await prisma?.guardianAccessLog.deleteMany({ where: { createdAt: { gte: testStartedAt } } });
    await prisma?.$disconnect();
  });

  it('resuelve la empresa correcta para cada credencial', async () => {
    const a = await machine.authenticate(keyA);
    const b = await machine.authenticate(keyB);

    expect(a?.companyId).toBe(companyA.id);
    expect(b?.companyId).toBe(companyB.id);
    expect(a?.companyId).not.toBe(b?.companyId);
    expect(a?.installId).toBe('pos-a');
  });

  it('una clave inexistente no resuelve ninguna empresa', async () => {
    await expect(machine.authenticate(`gmk_${'z'.repeat(40)}`)).resolves.toBeNull();
  });

  it('revocar la credencial la invalida de inmediato', async () => {
    await prisma.guardianMachineCredential.updateMany({
      where: { companyId: companyB.id },
      data: { revokedAt: new Date() },
    });
    await expect(machine.authenticate(keyB)).resolves.toBeNull();
    await expect(machine.authenticate(keyA)).resolves.not.toBeNull();
  });

  it('el uso queda auditado con rol MACHINE', async () => {
    const identity = await machine.authenticate(keyA);
    await machine.recordUsage({
      identity: identity!,
      ip: '10.0.0.9',
      requestId: 'req-machine-1',
      acceptedEvents: 2,
      totalEvents: 2,
    });

    const log = await prisma.guardianAccessLog.findFirst({
      where: { companyId: companyA.id, action: 'MACHINE_INGEST' },
      orderBy: { createdAt: 'desc' },
    });
    expect(log?.actorRole).toBe('MACHINE');
    expect(log?.requestId).toBe('req-machine-1');

    const credential = await prisma.guardianMachineCredential.findFirst({
      where: { companyId: companyA.id },
    });
    expect(credential?.lastUsedAt).not.toBeNull();
  });

  it('nunca guarda la clave en claro', async () => {
    const rows = await prisma.guardianMachineCredential.findMany({
      where: { companyId: { in: [companyA.id, companyB.id] } },
      select: { keyHash: true, keyPrefix: true },
    });
    for (const row of rows) {
      expect(row.keyHash).toHaveLength(64);
      expect(JSON.stringify(row)).not.toContain(keyA);
      expect(JSON.stringify(row)).not.toContain(keyB);
    }
  });
});
