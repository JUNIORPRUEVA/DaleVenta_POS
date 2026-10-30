import { GuardianAutoEnrollmentService } from './guardian.auto-enrollment.service';
import {
  isCompanyAllowedForAutoEnrollment,
  isCompanyLicenseEligible,
  resolveGuardianAutoEnrollmentConfig,
} from './guardian.auto-enrollment.config';
import { GUARDIAN_ENROLLMENT_CODE_PREFIX } from './guardian.enrollment.service';

/**
 * Auto-enrolamiento: reglas de seguridad y de cuota.
 *
 * Estas pruebas cubren lo que puede romper producción si se afloja:
 * aislamiento por empresa, fail-closed, cuota de instalaciones, límite de
 * concesiones, revocación y no filtrar el código en la auditoría.
 */

type CompanyRow = {
  guardianEnabled: boolean;
  status: string;
  licenseStatus: string;
  licenseBlockedAt: Date | null;
  licenseExpiresAt: Date | null;
};

function createFakeStore(options: {
  companies: Record<string, CompanyRow>;
  credentials?: Array<{ id: string; companyId: string; installId: string | null; enabled: boolean; revokedAt: Date | null; expiresAt: Date | null }>;
  codes?: Array<{ id: string; companyId: string; createdAt: Date; revokedAt: Date | null; expiresAt: Date; codeHash: string; maxUses: number }>;
}) {
  const companies = { ...options.companies };
  const credentials = [...(options.credentials ?? [])];
  const codes = [...(options.codes ?? [])];
  const audits: Array<Record<string, unknown>> = [];
  let credentialSeq = 0;

  const store = {
    company: {
      async findUnique(args: { where: { id: string } }) {
        const row = companies[args.where.id];
        return row ? { ...row } : null;
      },
      async update(args: {
        where: { id: string };
        data: { guardianEnabled: boolean; guardianEnabledAt?: Date | null; guardianEnabledBy?: string | null };
      }) {
        const row = companies[args.where.id];
        if (row) row.guardianEnabled = args.data.guardianEnabled;
        return row ?? null;
      },
    },
    guardianMachineCredential: {
      async count(args: {
        where: { companyId: string; enabled: boolean; revokedAt: null; OR: Array<Record<string, unknown>> };
      }) {
        const now = Date.now();
        return credentials.filter(
          (credential) =>
            credential.companyId === args.where.companyId &&
            credential.enabled &&
            credential.revokedAt === null &&
            (credential.expiresAt === null || credential.expiresAt.getTime() > now),
        ).length;
      },
      async findFirst(args: { where: { companyId: string; installId: string } }) {
        const found = credentials.find(
          (credential) =>
            credential.companyId === args.where.companyId &&
            credential.installId === args.where.installId,
        );
        return found ? { id: found.id } : null;
      },
      async updateMany(args: { where: { companyId: string; revokedAt: null }; data: { enabled: boolean; revokedAt: Date } }) {
        let count = 0;
        for (const credential of credentials) {
          if (credential.companyId === args.where.companyId && credential.revokedAt === null) {
            credential.revokedAt = args.data.revokedAt;
            credential.enabled = args.data.enabled;
            count += 1;
          }
        }
        return { count };
      },
    },
    guardianEnrollmentCode: {
      async count(args: { where: { companyId: string; createdAt: { gte: Date } } }) {
        return codes.filter(
          (code) =>
            code.companyId === args.where.companyId &&
            code.createdAt.getTime() >= args.where.createdAt.gte.getTime(),
        ).length;
      },
      async create(args: {
        data: {
          companyId: string;
          codeHash: string;
          codePrefix: string;
          label: string;
          maxUses: number;
          expiresAt: Date;
        };
      }) {
        credentialSeq += 1;
        const row = {
          id: `code-${credentialSeq}`,
          companyId: args.data.companyId,
          createdAt: new Date(),
          revokedAt: null,
          expiresAt: args.data.expiresAt,
          codeHash: args.data.codeHash,
          maxUses: args.data.maxUses,
        };
        codes.push(row);
        return { id: row.id, expiresAt: row.expiresAt };
      },
      async updateMany(args: { where: { companyId: string; revokedAt: null; expiresAt: { gt: Date } }; data: { revokedAt: Date } }) {
        let count = 0;
        for (const code of codes) {
          if (
            code.companyId === args.where.companyId &&
            code.revokedAt === null &&
            code.expiresAt.getTime() > args.where.expiresAt.gt.getTime()
          ) {
            code.revokedAt = args.data.revokedAt;
            count += 1;
          }
        }
        return { count };
      },
    },
    guardianAccessLog: {
      async create(args: { data: Record<string, unknown> }) {
        audits.push(args.data);
        return args.data;
      },
    },
  };

  return { store, companies, credentials, codes, audits };
}

const ACTIVE_COMPANY: CompanyRow = {
  guardianEnabled: false,
  status: 'ACTIVE',
  licenseStatus: 'ACTIVE',
  licenseBlockedAt: null,
  licenseExpiresAt: null,
};

const COMPANY_A = '11111111-1111-4111-8111-111111111111';
const COMPANY_B = '22222222-2222-4222-8222-222222222222';

const BASE_ENV = { ...process.env };

function setEnv(values: Record<string, string | undefined>) {
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
}

describe('configuracion del auto-enrolamiento', () => {
  afterEach(() => {
    process.env = { ...BASE_ENV };
  });

  it('esta deshabilitado y sin empresas por defecto (fail-closed)', () => {
    setEnv({
      GUARDIAN_AUTO_ENROLL_ENABLED: undefined,
      GUARDIAN_AUTO_ENROLL_COMPANIES: undefined,
    });
    const config = resolveGuardianAutoEnrollmentConfig();
    expect(config.enabled).toBe(false);
    expect(config.allowedCompanyIds).toEqual([]);
    expect(isCompanyAllowedForAutoEnrollment(config, COMPANY_A)).toBe(false);
  });

  it('una lista vacia nunca autoriza y el comodin autoriza a todas', () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: '' });
    expect(isCompanyAllowedForAutoEnrollment(resolveGuardianAutoEnrollmentConfig(), COMPANY_A)).toBe(false);

    setEnv({ GUARDIAN_AUTO_ENROLL_COMPANIES: '*' });
    expect(isCompanyAllowedForAutoEnrollment(resolveGuardianAutoEnrollmentConfig(), COMPANY_A)).toBe(true);

    setEnv({ GUARDIAN_AUTO_ENROLL_COMPANIES: `${COMPANY_A}, ${COMPANY_B}` });
    const config = resolveGuardianAutoEnrollmentConfig();
    expect(isCompanyAllowedForAutoEnrollment(config, COMPANY_A)).toBe(true);
    expect(isCompanyAllowedForAutoEnrollment(config, 'otra-empresa')).toBe(false);
  });

  it('acota la vida de la autorizacion y la cuota de instalaciones', () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_GRANT_TTL_SECONDS: '1', GUARDIAN_MAX_INSTALLATIONS_PER_COMPANY: '9999' });
    const config = resolveGuardianAutoEnrollmentConfig();
    expect(config.grantTtlSeconds).toBe(60);
    expect(config.maxInstallationsPerCompany).toBe(200);
  });

  it('la elegibilidad exige empresa activa, sin bloqueo y con licencia vigente', () => {
    expect(isCompanyLicenseEligible(ACTIVE_COMPANY)).toBe(true);
    expect(isCompanyLicenseEligible({ ...ACTIVE_COMPANY, status: 'SUSPENDED' })).toBe(false);
    expect(isCompanyLicenseEligible({ ...ACTIVE_COMPANY, licenseBlockedAt: new Date() })).toBe(false);
    expect(
      isCompanyLicenseEligible({ ...ACTIVE_COMPANY, licenseExpiresAt: new Date(Date.now() - 1_000) }),
    ).toBe(false);
    expect(isCompanyLicenseEligible({ ...ACTIVE_COMPANY, licenseStatus: 'EXPIRED' })).toBe(false);
    expect(isCompanyLicenseEligible(null)).toBe(false);
  });
});

describe('concesion de auto-enrolamiento', () => {
  afterEach(() => {
    process.env = { ...BASE_ENV };
  });

  it('rechaza todo si el interruptor esta apagado', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'false', GUARDIAN_AUTO_ENROLL_COMPANIES: '*' });
    const { store } = createFakeStore({ companies: { [COMPANY_A]: { ...ACTIVE_COMPANY } } });
    const service = new GuardianAutoEnrollmentService(store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'AUTO_ENROLLMENT_DISABLED' });
  });

  it('no auto-enrola empresas fuera de la lista autorizada', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_B });
    const { store } = createFakeStore({ companies: { [COMPANY_A]: { ...ACTIVE_COMPANY } } });
    const service = new GuardianAutoEnrollmentService(store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'COMPANY_NOT_ALLOWED' });
  });

  it('emite un codigo de un solo uso y activa la empresa autorizada', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A });
    const fake = createFakeStore({ companies: { [COMPANY_A]: { ...ACTIVE_COMPANY } } });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
      platform: 'windows',
      appVersion: '1.0.6',
    });

    expect(outcome.ok).toBe(true);
    if (!outcome.ok) return;
    expect(outcome.code.startsWith(GUARDIAN_ENROLLMENT_CODE_PREFIX)).toBe(true);
    expect(outcome.activated).toBe(true);
    expect(outcome.companyId).toBe(COMPANY_A);
    // La empresa solo pasa a activa por la lista de despliegue, nunca por el cliente.
    expect(fake.companies[COMPANY_A].guardianEnabled).toBe(true);
    // El codigo en claro jamas se persiste: solo su hash.
    expect(fake.codes).toHaveLength(1);
    expect(fake.codes[0].codeHash).not.toBe(outcome.code);
    expect(fake.codes[0].maxUses).toBe(1);
    expect(fake.codes[0].companyId).toBe(COMPANY_A);
    // Caducidad corta.
    const ttlMs = fake.codes[0].expiresAt.getTime() - Date.now();
    expect(ttlMs).toBeGreaterThan(60_000);
    expect(ttlMs).toBeLessThanOrEqual(300_000 + 5_000);
  });

  it('respeta el control administrativo: sin activacion automatica no se concede', async () => {
    setEnv({
      GUARDIAN_AUTO_ENROLL_ENABLED: 'true',
      GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A,
      GUARDIAN_AUTO_ENROLL_ACTIVATE: 'false',
    });
    const fake = createFakeStore({ companies: { [COMPANY_A]: { ...ACTIVE_COMPANY } } });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'COMPANY_GUARDIAN_DISABLED' });
    expect(fake.codes).toHaveLength(0);
  });

  it('una empresa desactivada por un administrador no se reactiva sola', async () => {
    setEnv({
      GUARDIAN_AUTO_ENROLL_ENABLED: 'true',
      GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A,
      GUARDIAN_AUTO_ENROLL_ACTIVATE: 'false',
    });
    const fake = createFakeStore({
      companies: { [COMPANY_A]: { ...ACTIVE_COMPANY, guardianEnabled: false } },
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'COMPANY_GUARDIAN_DISABLED' });
    expect(fake.companies[COMPANY_A].guardianEnabled).toBe(false);
  });

  it('rechaza empresas sin licencia vigente', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A });
    const fake = createFakeStore({
      companies: {
        [COMPANY_A]: {
          ...ACTIVE_COMPANY,
          licenseExpiresAt: new Date(Date.now() - 86_400_000),
        },
      },
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'COMPANY_NOT_ELIGIBLE' });
    expect(fake.companies[COMPANY_A].guardianEnabled).toBe(false);
  });

  it('aplica la cuota de instalaciones pero permite rotar la del mismo equipo', async () => {
    setEnv({
      GUARDIAN_AUTO_ENROLL_ENABLED: 'true',
      GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A,
      GUARDIAN_MAX_INSTALLATIONS_PER_COMPANY: '2',
    });
    const credentials = [
      { id: 'c1', companyId: COMPANY_A, installId: 'install-1', enabled: true, revokedAt: null, expiresAt: null },
      { id: 'c2', companyId: COMPANY_A, installId: 'install-2', enabled: true, revokedAt: null, expiresAt: null },
    ];
    const fake = createFakeStore({
      companies: { [COMPANY_A]: { ...ACTIVE_COMPANY, guardianEnabled: true } },
      credentials,
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const third = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-3',
    });
    expect(third).toMatchObject({ ok: false, code: 'INSTALLATION_LIMIT_REACHED' });

    const rotate = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-1',
    });
    expect(rotate.ok).toBe(true);
  });

  it('limita las autorizaciones por empresa y hora', async () => {
    setEnv({
      GUARDIAN_AUTO_ENROLL_ENABLED: 'true',
      GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A,
      GUARDIAN_AUTO_ENROLL_GRANTS_PER_HOUR: '2',
    });
    const now = Date.now();
    const fake = createFakeStore({
      companies: { [COMPANY_A]: { ...ACTIVE_COMPANY, guardianEnabled: true } },
      codes: [
        { id: 'k1', companyId: COMPANY_A, createdAt: new Date(now - 60_000), revokedAt: null, expiresAt: new Date(now), codeHash: 'a'.repeat(64), maxUses: 1 },
        { id: 'k2', companyId: COMPANY_A, createdAt: new Date(now - 120_000), revokedAt: null, expiresAt: new Date(now), codeHash: 'b'.repeat(64), maxUses: 1 },
      ],
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-xyz123',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'ENROLLMENT_RATE_LIMITED' });
  });

  it('el aislamiento por empresa se mantiene: la concesion usa siempre la empresa de la sesion', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: '*' });
    const fake = createFakeStore({
      companies: {
        [COMPANY_A]: { ...ACTIVE_COMPANY, guardianEnabled: true },
        [COMPANY_B]: { ...ACTIVE_COMPANY, guardianEnabled: true },
      },
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const a = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-a',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });
    const b = await service.requestGrant({
      companyId: COMPANY_B,
      actorUserId: 'user-b',
      actorRole: 'ADMIN',
      installId: 'install-bbbbbb',
    });

    expect(a.ok && b.ok).toBe(true);
    const byCompany = fake.codes.map((code) => code.companyId).sort();
    expect(byCompany).toEqual([COMPANY_A, COMPANY_B].sort());
    expect(new Set(fake.codes.map((code) => code.codeHash)).size).toBe(2);
  });

  it('la auditoria no registra el codigo ni la credencial', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A });
    const fake = createFakeStore({
      companies: { [COMPANY_A]: { ...ACTIVE_COMPANY, guardianEnabled: true } },
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });

    expect(outcome.ok).toBe(true);
    if (!outcome.ok) return;
    const serialized = JSON.stringify(fake.audits);
    expect(serialized).not.toContain(outcome.code);
    expect(serialized).not.toContain(COMPANY_A.slice(0, 0) + 'gmk_');
    expect(fake.audits.map((row) => row.action)).toContain('ENROLLMENT_GRANT_ISSUED');
  });

  it('un installId mal formado se rechaza antes de tocar la base', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A });
    const fake = createFakeStore({ companies: { [COMPANY_A]: { ...ACTIVE_COMPANY } } });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'ab',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'INSTALL_ID_INVALID' });
    expect(fake.codes).toHaveLength(0);
  });
});

describe('desactivacion administrativa', () => {
  afterEach(() => {
    process.env = { ...BASE_ENV };
  });

  it('apaga el monitoreo y revoca credenciales y autorizaciones pendientes', async () => {
    setEnv({ GUARDIAN_AUTO_ENROLL_ENABLED: 'true', GUARDIAN_AUTO_ENROLL_COMPANIES: '*' });
    const now = Date.now();
    const fake = createFakeStore({
      companies: { [COMPANY_A]: { ...ACTIVE_COMPANY, guardianEnabled: true } },
      credentials: [
        { id: 'c1', companyId: COMPANY_A, installId: 'install-1', enabled: true, revokedAt: null, expiresAt: null },
      ],
      codes: [
        { id: 'k1', companyId: COMPANY_A, createdAt: new Date(now), revokedAt: null, expiresAt: new Date(now + 300_000), codeHash: 'c'.repeat(64), maxUses: 1 },
      ],
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    const result = await service.disableForCompany({
      companyId: COMPANY_A,
      actorUserId: 'admin-1',
      actorRole: 'ADMIN',
    });

    expect(result).toEqual({ credentialsRevoked: 1, grantsRevoked: 1 });
    expect(fake.companies[COMPANY_A].guardianEnabled).toBe(false);
    expect(fake.credentials[0].enabled).toBe(false);
    expect(fake.credentials[0].revokedAt).not.toBeNull();
    expect(fake.codes[0].revokedAt).not.toBeNull();
    expect(fake.audits.map((row) => row.action)).toContain('COMPANY_GUARDIAN_DISABLED_BY_ADMIN');
  });

  it('tras desactivar, la empresa ya no recibe autorizaciones', async () => {
    setEnv({
      GUARDIAN_AUTO_ENROLL_ENABLED: 'true',
      GUARDIAN_AUTO_ENROLL_COMPANIES: COMPANY_A,
      GUARDIAN_AUTO_ENROLL_ACTIVATE: 'false',
    });
    const fake = createFakeStore({
      companies: { [COMPANY_A]: { ...ACTIVE_COMPANY, guardianEnabled: true } },
    });
    const service = new GuardianAutoEnrollmentService(fake.store);

    await service.disableForCompany({ companyId: COMPANY_A, actorUserId: 'admin-1', actorRole: 'ADMIN' });
    const outcome = await service.requestGrant({
      companyId: COMPANY_A,
      actorUserId: 'user-1',
      actorRole: 'ADMIN',
      installId: 'install-aaaaaa',
    });

    expect(outcome).toMatchObject({ ok: false, code: 'COMPANY_GUARDIAN_DISABLED' });
  });
});
