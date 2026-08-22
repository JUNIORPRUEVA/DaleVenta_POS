/**
 * Regression tests for prisma/seed.cjs — production seed safety.
 *
 * Forensic context (2026-08-22, CASO B):
 * - seed.cjs `upsertDefaultCompany()` used to overwrite `Company.name` with the
 *   product default ("FullPOS Cloud") via the `update` branch of an upsert on
 *   slug `daleventa-pos`, with NO audit event, on EVERY seed run (RUN_SEED=true
 *   at backend startup or manual `npm run seed`).
 * - seed.cjs `upsertUser()` also reset the admin passwordHash and other user
 *   fields; `upsertCompanyMember()` re-set role/status/joinedAt; `upsertAppConfig()`
 *   overwrote companyName.
 *
 * These tests lock the SAFE contract:
 *   - EXISTING company/AppConfig/user/member  → `update` must be a NO-OP
 *   - NEW company/AppConfig/user/member       → `create` seeds initial values
 *   - Repeated runs must be idempotent (no destructive writes)
 */

// eslint-disable-next-line @typescript-eslint/no-require-imports
const seed = require('./seed.cjs');

jest.mock('@prisma/client', () => {
  const mockPrisma = {
    company: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
    },
    appConfig: { upsert: jest.fn() },
    user: { upsert: jest.fn() },
    companyMember: { upsert: jest.fn() },
    $queryRaw: jest.fn(),
    $disconnect: jest.fn(),
  };
  return {
    Prisma: {
      sql: (strings: TemplateStringsArray) => ({ strings }),
    },
    PrismaClient: jest.fn(() => mockPrisma),
    Role: { ADMIN: 'ADMIN', ASISTENTE: 'ASISTENTE', CAJERO: 'CAJERO', VENDEDOR: 'VENDEDOR' },
    CompanyMemberRole: { OWNER: 'OWNER', ADMIN: 'ADMIN', CASHIER: 'CASHIER', SELLER: 'SELLER', VIEWER: 'VIEWER' },
    CompanyMemberStatus: { ACTIVE: 'ACTIVE' },
  };
});

type UpsertCall = {
  where?: Record<string, unknown>;
  update?: Record<string, unknown>;
  create?: Record<string, unknown>;
};

function lastUpsertArgs(mock: jest.Mock): UpsertCall {
  const calls = mock.mock.calls as Array<[UpsertCall]>;
  return calls[calls.length - 1][0];
}

function getMockPrisma() {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { PrismaClient } = require('@prisma/client');
  return new PrismaClient() as unknown as {
    company: { upsert: jest.Mock; findUnique: jest.Mock };
    appConfig: { upsert: jest.Mock };
    user: { upsert: jest.Mock };
    companyMember: { upsert: jest.Mock };
  };
}

describe('prisma/seed.cjs — production seed safety', () => {
  let prisma: ReturnType<typeof getMockPrisma>;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma = getMockPrisma();
    process.env.ADMIN_PASSWORD = 'test-password';
    process.env.ADMIN_EMAIL = 'admin@test.local';
  });

  afterEach(() => {
    delete process.env.ADMIN_PASSWORD;
    delete process.env.ADMIN_EMAIL;
  });

  describe('upsertDefaultCompany (Company)', () => {
    it('TEST 1 — existing company: update must NOT touch name/status/plan/maxUsers', async () => {
      prisma.company.upsert.mockResolvedValue({ id: 'c1', name: 'FULLTECH, SRL', slug: 'daleventa-pos' });

      const result = await seed.upsertDefaultCompany();

      const args = lastUpsertArgs(prisma.company.upsert);
      expect(args.where).toEqual({ slug: 'daleventa-pos' });
      // update is a NO-OP: no name, no license fields
      expect(args.update).toEqual({});
      // create still seeds initial values for a brand-new company
      expect(args.create?.name).toBe('FullPOS Cloud');
      expect(args.create?.status).toBe('ACTIVE');
      expect(args.create?.plan).toBe('ENTERPRISE');
      expect(args.create?.maxUsers).toBe(1000);
      expect(result.name).toBe('FULLTECH, SRL');
    });
  });

  describe('upsertAppConfig (AppConfig)', () => {
    it('TEST 2 — existing app_config: update must NOT overwrite companyName/rnc/phone/address/logo', async () => {
      prisma.appConfig.upsert.mockResolvedValue({
        id: 'global',
        companyName: 'FULLTECH, SRL',
        rnc: 'R-REAL',
        phone: '809-REAL',
      });

      const result = await seed.upsertAppConfig({ id: 'c1', name: 'FULLTECH, SRL' });

      const args = lastUpsertArgs(prisma.appConfig.upsert);
      expect(args.where).toEqual({ id: 'global' });
      expect(args.update).toEqual({});
      expect(args.create?.companyName).toBe('FULLTECH, SRL');
      expect(result.companyName).toBe('FULLTECH, SRL');
    });
  });

  describe('upsertUser (admin)', () => {
    it('TEST 3 — existing admin: update must NOT reset passwordHash/role/companyId/blocked', async () => {
      prisma.user.upsert.mockResolvedValue({ id: 'u1', email: 'admin@test.local' });

      await seed.upsertUser({
        companyId: 'c1',
        email: 'admin@test.local',
        password: 'whatever',
        nombreCompleto: 'Administrador',
        telefono: '0000000000',
        role: 'ADMIN',
      });

      const args = lastUpsertArgs(prisma.user.upsert);
      expect(args.where).toEqual({ email: 'admin@test.local' });
      // CRITICAL: password must NOT be reset on existing users
      expect(args.update).toEqual({});
      // create seeds the bootstrap admin with a hashed password
      expect(args.create?.email).toBe('admin@test.local');
      expect(args.create?.passwordHash).toBeTruthy();
      expect(args.create?.role).toBe('ADMIN');
      expect(args.create?.blocked).toBe(false);
    });
  });

  describe('upsertCompanyMember (membership)', () => {
    it('existing member: update must NOT re-set role/status/joinedAt', async () => {
      prisma.companyMember.upsert.mockResolvedValue({ userId: 'u1', companyId: 'c1' });

      await seed.upsertCompanyMember({ userId: 'u1', companyId: 'c1', role: 'ADMIN' });

      const args = lastUpsertArgs(prisma.companyMember.upsert);
      expect(args.update).toEqual({});
      expect(args.create?.role).toBe('OWNER'); // ADMIN maps to OWNER
      expect(args.create?.status).toBe('ACTIVE');
      expect(args.create?.joinedAt).toBeInstanceOf(Date);
    });
  });

  describe('main() full bootstrap', () => {
    it('TEST 4 — NEW company: creates Company + AppConfig + admin + company_member', async () => {
      prisma.company.findUnique.mockResolvedValue(null); // no existing company
      prisma.company.upsert.mockResolvedValue({ id: 'c-new', slug: 'daleventa-pos', name: 'FullPOS Cloud' });
      prisma.appConfig.upsert.mockResolvedValue({ id: 'global', companyId: 'c-new', companyName: 'FullPOS Cloud' });
      prisma.user.upsert.mockResolvedValue({ id: 'u-new', email: 'admin@test.local' });
      prisma.companyMember.upsert.mockResolvedValue({ userId: 'u-new', companyId: 'c-new' });

      await seed.main();

      expect(prisma.company.findUnique).toHaveBeenCalledWith({ where: { slug: 'daleventa-pos' } });
      expect(prisma.company.upsert).toHaveBeenCalled();
      expect(prisma.appConfig.upsert).toHaveBeenCalled();
      expect(prisma.user.upsert).toHaveBeenCalled();
      expect(prisma.companyMember.upsert).toHaveBeenCalled();

      const memberArgs = lastUpsertArgs(prisma.companyMember.upsert);
      expect(memberArgs.create?.userId).toBe('u-new');
      expect(memberArgs.create?.companyId).toBe('c-new');
    });

    it('TEST 5 — second run on existing tenant: idempotent, no destructive writes, no backfill of nulls', async () => {
      prisma.company.findUnique.mockResolvedValue({ id: 'c1' }); // existing
      prisma.company.upsert.mockResolvedValue({ id: 'c1', name: 'FULLTECH, SRL', slug: 'daleventa-pos' });
      prisma.appConfig.upsert.mockResolvedValue({ id: 'global', companyId: 'c1', companyName: 'FULLTECH, SRL' });
      prisma.user.upsert.mockResolvedValue({ id: 'u1', email: 'admin@test.local' });
      prisma.companyMember.upsert.mockResolvedValue({ userId: 'u1', companyId: 'c1' });

      await seed.main();
      await seed.main();

      // update branches stay no-ops across repeated runs
      expect(lastUpsertArgs(prisma.company.upsert).update).toEqual({});
      expect(lastUpsertArgs(prisma.appConfig.upsert).update).toEqual({});
      expect(lastUpsertArgs(prisma.user.upsert).update).toEqual({});
      expect(lastUpsertArgs(prisma.companyMember.upsert).update).toEqual({});
      // backfillDefaultCompany only runs for NEW companies; existing tenant must skip
      expect(prisma.company.upsert.mock.calls.length).toBe(2); // twice, both no-op updates
    });
  });

  describe('backfillDefaultCompany', () => {
    it('is skipped safely when models have no updateMany', async () => {
      const results = await seed.backfillDefaultCompany('c1');
      expect(Array.isArray(results)).toBe(true);
      expect(results.length).toBeGreaterThan(0);
    });
  });
});
