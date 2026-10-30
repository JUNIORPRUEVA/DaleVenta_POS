/**
 * Auto-enrolamiento de instalaciones sobre PostgreSQL real.
 *
 * Cubre con evidencia y sin tocar bases compartidas:
 *   1. Sin autorización de despliegue, ninguna empresa puede auto-enrolarse.
 *   2. Empresa autorizada y con licencia vigente: se concede y se activa.
 *   3. El código concede UNA credencial ligada al `installId` de la instalación.
 *   4. Reintentar el enrolamiento del mismo equipo ROTA, no duplica.
 *   5. Aislamiento: dos empresas, un código por empresa, cero cruces.
 *   6. Desactivación administrativa: credencial revocada al instante.
 *   7. La cuota de instalaciones por empresa se respeta.
 *
 * Ejecutar con GUARDIAN_UAT_DATABASE_URL apuntando a una base EFÍMERA.
 */
import { PrismaClient } from '@prisma/client';
import { GuardianAutoEnrollmentService } from './guardian.auto-enrollment.service';
import { GuardianEnrollmentService } from './guardian.enrollment.service';
import { GuardianMachineService } from './guardian.machine.service';

const DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = DATABASE_URL ? describe : describe.skip;
const RUN_ID = `autoenr${Date.now().toString(36)}`;

const ENV_KEYS = [
  'GUARDIAN_AUTO_ENROLL_ENABLED',
  'GUARDIAN_AUTO_ENROLL_COMPANIES',
  'GUARDIAN_AUTO_ENROLL_ACTIVATE',
  'GUARDIAN_MAX_INSTALLATIONS_PER_COMPANY',
  'GUARDIAN_AUTO_ENROLL_GRANTS_PER_HOUR',
] as const;

describeOnPg('auto-enrolamiento Guardian sobre PostgreSQL real', () => {
  let prisma: PrismaClient;
  let autoEnrollment: GuardianAutoEnrollmentService;
  let enrollment: GuardianEnrollmentService;
  let machine: GuardianMachineService;
  let companyA: { id: string };
  let companyB: { id: string };
  let companyC: { id: string };
  const savedEnv: Record<string, string | undefined> = {};

  beforeAll(async () => {
    for (const key of ENV_KEYS) savedEnv[key] = process.env[key];
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_INGEST_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_ACTIVATE = 'true';
    // Las pruebas emiten varias autorizaciones seguidas para la misma empresa; el
    // limite horario real se cubre en la suite unitaria, aqui se evita el ruido.
    process.env.GUARDIAN_AUTO_ENROLL_GRANTS_PER_HOUR = '120';

    prisma = new PrismaClient({ datasources: { db: { url: DATABASE_URL } } });
    await prisma.$connect();
    autoEnrollment = new GuardianAutoEnrollmentService(prisma as any);
    enrollment = new GuardianEnrollmentService(prisma as any);
    machine = new GuardianMachineService(prisma as any);

    companyA = await prisma.company.create({
      data: { name: `Auto A ${RUN_ID}`, slug: `auto-a-${RUN_ID}` },
      select: { id: true },
    });
    companyB = await prisma.company.create({
      data: { name: `Auto B ${RUN_ID}`, slug: `auto-b-${RUN_ID}` },
      select: { id: true },
    });
    companyC = await prisma.company.create({
      data: { name: `Auto C ${RUN_ID}`, slug: `auto-c-${RUN_ID}` },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    for (const key of ENV_KEYS) {
      if (savedEnv[key] === undefined) delete process.env[key];
      else process.env[key] = savedEnv[key];
    }
    await prisma?.company.deleteMany({ where: { slug: { contains: RUN_ID } } });
    await prisma?.$disconnect();
  });

  it('sin empresas autorizadas no se concede nada', async () => {
    process.env.GUARDIAN_AUTO_ENROLL_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = '';
    const outcome = await autoEnrollment.requestGrant({
      companyId: companyA.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId: `dev-${RUN_ID}-a`,
    });
    expect(outcome).toMatchObject({ ok: false, code: 'COMPANY_NOT_ALLOWED' });

    const rows = await prisma.guardianEnrollmentCode.count({ where: { companyId: companyA.id } });
    expect(rows).toBe(0);
  }, 30_000);

  it('empresa autorizada: concede, activa y el canje emite credencial ligada al equipo', async () => {
    process.env.GUARDIAN_AUTO_ENROLL_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = `${companyA.id},${companyB.id}`;

    const grant = await autoEnrollment.requestGrant({
      companyId: companyA.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId: `dev-${RUN_ID}-a1`,
      platform: 'windows',
      appVersion: '1.0.6',
    });
    expect(grant.ok).toBe(true);
    if (!grant.ok) return;
    expect(grant.activated).toBe(true);

    const activated = await prisma.company.findUnique({
      where: { id: companyA.id },
      select: { guardianEnabled: true, guardianEnabledBy: true },
    });
    expect(activated?.guardianEnabled).toBe(true);
    expect(activated?.guardianEnabledBy).toBe('AUTO_ENROLLMENT');

    const enrolled = await enrollment.enroll({
      code: grant.code,
      installId: `dev-${RUN_ID}-a1`,
      platform: 'windows',
      appVersion: '1.0.6',
    });
    expect(enrolled.ok).toBe(true);
    if (!enrolled.ok) return;
    expect(enrolled.companyId).toBe(companyA.id);

    const credential = await prisma.guardianMachineCredential.findFirst({
      where: { companyId: companyA.id, installId: `dev-${RUN_ID}-a1` },
      select: { id: true, enabled: true, revokedAt: true },
    });
    expect(credential?.enabled).toBe(true);
    expect(credential?.revokedAt).toBeNull();

    const identity = await machine.authenticate(enrolled.credential);
    expect(identity?.companyId).toBe(companyA.id);
  }, 60_000);

  it('el mismo equipo reintenta: rota la credencial, no duplica la instalacion', async () => {
    process.env.GUARDIAN_AUTO_ENROLL_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = '*';

    const installId = `dev-${RUN_ID}-rot`;
    const first = await autoEnrollment.requestGrant({
      companyId: companyA.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId,
      platform: 'windows',
    });
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    const firstEnroll = await enrollment.enroll({ code: first.code, installId });
    expect(firstEnroll.ok).toBe(true);

    const second = await autoEnrollment.requestGrant({
      companyId: companyA.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId,
      platform: 'windows',
    });
    expect(second.ok).toBe(true);
    if (!second.ok) return;
    const secondEnroll = await enrollment.enroll({ code: second.code, installId });
    expect(secondEnroll.ok).toBe(true);

    const rows = await prisma.guardianMachineCredential.count({
      where: { companyId: companyA.id, installId },
    });
    expect(rows).toBe(1);
  }, 60_000);

  it('aislamiento: el codigo de una empresa nunca enrola en otra', async () => {
    process.env.GUARDIAN_AUTO_ENROLL_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = '*';

    const grant = await autoEnrollment.requestGrant({
      companyId: companyB.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId: `dev-${RUN_ID}-b1`,
      platform: 'windows',
    });
    expect(grant.ok).toBe(true);
    if (!grant.ok) return;

    const enrolled = await enrollment.enroll({ code: grant.code, installId: `dev-${RUN_ID}-b1` });
    expect(enrolled.ok).toBe(true);
    if (!enrolled.ok) return;
    expect(enrolled.companyId).toBe(companyB.id);

    const leaked = await prisma.guardianMachineCredential.count({
      where: { companyId: companyA.id, installId: `dev-${RUN_ID}-b1` },
    });
    expect(leaked).toBe(0);
  }, 60_000);

  it('la cuota de instalaciones por empresa se respeta', async () => {
    process.env.GUARDIAN_AUTO_ENROLL_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = '*';
    process.env.GUARDIAN_MAX_INSTALLATIONS_PER_COMPANY = '1';

    const active = await prisma.guardianMachineCredential.count({
      where: { companyId: companyC.id, enabled: true, revokedAt: null },
    });
    expect(active).toBe(0);

    const first = await autoEnrollment.requestGrant({
      companyId: companyC.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId: `dev-${RUN_ID}-c1`,
    });
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    const enrolled = await enrollment.enroll({ code: first.code, installId: `dev-${RUN_ID}-c1` });
    expect(enrolled.ok).toBe(true);

    const second = await autoEnrollment.requestGrant({
      companyId: companyC.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId: `dev-${RUN_ID}-c2`,
    });
    expect(second).toMatchObject({ ok: false, code: 'INSTALLATION_LIMIT_REACHED' });

    delete process.env.GUARDIAN_MAX_INSTALLATIONS_PER_COMPANY;
  }, 60_000);

  it('la desactivacion administrativa revoca la credencial al instante', async () => {
    process.env.GUARDIAN_AUTO_ENROLL_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = '*';

    const grant = await autoEnrollment.requestGrant({
      companyId: companyA.id,
      actorUserId: null,
      actorRole: 'ADMIN',
      installId: `dev-${RUN_ID}-rev`,
      platform: 'windows',
    });
    expect(grant.ok).toBe(true);
    if (!grant.ok) return;
    const enrolled = await enrollment.enroll({ code: grant.code, installId: `dev-${RUN_ID}-rev` });
    expect(enrolled.ok).toBe(true);
    if (!enrolled.ok) return;

    expect(await machine.authenticate(enrolled.credential)).not.toBeNull();

    const disabled = await autoEnrollment.disableForCompany({
      companyId: companyA.id,
      actorUserId: null,
      actorRole: 'ADMIN',
    });
    expect(disabled.credentialsRevoked).toBeGreaterThan(0);

    expect(await machine.authenticate(enrolled.credential)).toBeNull();
    const company = await prisma.company.findUnique({
      where: { id: companyA.id },
      select: { guardianEnabled: true },
    });
    expect(company?.guardianEnabled).toBe(false);
    // El historial no se borra: solo se revoca.
    const stillThere = await prisma.guardianMachineCredential.count({
      where: { companyId: companyA.id },
    });
    expect(stillThere).toBeGreaterThan(0);
  }, 60_000);
});
