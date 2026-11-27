import { PrismaClient } from '@prisma/client';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { GuardianPlatformService } from './guardian.platform.service';

const url = process.env.GUARDIAN_DEFAULTS_LOCAL_DATABASE_URL;
const run = url ? describe : describe.skip;

run('Guardian defaults migration and company projection on isolated PostgreSQL', () => {
  let db: PrismaClient;
  const prefix = `guardian-defaults-${Date.now()}`;
  const original = { ...process.env };
  const apply = async () => {
    const sql = readFileSync(join(__dirname, '../../prisma/migrations/20261127190000_guardian_default_enabled/migration.sql'), 'utf8');
    for (const statement of sql.split(';').filter((part) => part.trim())) {
      await db.$executeRawUnsafe(statement);
    }
  };

  beforeAll(async () => {
    const target = new URL(url!);
    if (target.hostname !== '127.0.0.1' || target.pathname !== '/fullpos_guardian_defaults_local') {
      throw new Error('Defaults migration test requires its dedicated local database');
    }
    db = new PrismaClient({ datasources: { db: { url } } });
    await db.$connect();
  });
  afterAll(async () => {
    process.env = original;
    await db?.company.deleteMany({ where: { slug: { startsWith: prefix } } });
    await db?.$disconnect();
  });

  it('enables initial defaults, preserves explicit decisions, archived companies and license data', async () => {
    const expiry = new Date('2030-01-01T00:00:00Z');
    for (const [name, by, status] of [
      ['initial', null, 'ACTIVE'],
      ['platform', 'DISABLED_BY_PLATFORM', 'ACTIVE'],
      ['admin', 'DISABLED_BY_ADMIN', 'ACTIVE'],
      ['other-explicit', 'custom-decision', 'ACTIVE'],
      ['archived', null, 'ARCHIVED'],
    ] as const) {
      await db.company.create({ data: { name, slug: `${prefix}-${name}`, guardianEnabled: false,
        guardianEnabledBy: by, status, licenseExpiresAt: expiry } });
    }
    await apply();
    const rows = await db.company.findMany({ where: { slug: { startsWith: prefix } } });
    expect(rows.filter((row) => row.guardianEnabled).map((row) => row.name)).toEqual(['initial']);
    expect(rows.every((row) => row.licenseExpiresAt?.getTime() === expiry.getTime())).toBe(true);
    const initial = rows.find((row) => row.name === 'initial')!;
    expect(initial.guardianEnabledAt).not.toBeNull();
    await db.company.update({ where: { id: initial.id }, data: {
      guardianEnabled: false, guardianEnabledBy: 'DISABLED_BY_PLATFORM',
    } });
    await apply();
    expect((await db.company.findUniqueOrThrow({ where: { id: initial.id } })).guardianEnabled).toBe(false);
    const future = await db.company.create({ data: { name: 'future', slug: `${prefix}-future` } });
    expect(future.guardianEnabled).toBe(true);
  });

  it('reports only valid installations and distinguishes enrollment restrictions from monitoring', async () => {
    process.env.GUARDIAN_AUTO_ENROLL_ENABLED = 'true';
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = '*';
    const company = await db.company.create({ data: { name: 'projection', slug: `${prefix}-projection`, licenseStatus: 'ACTIVE' } });
    const lastUsedAt = new Date('2026-11-27T12:00:00Z');
    for (const [index, enabled, revokedAt, expiresAt] of [
      [0, true, null, null], [1, false, null, null],
      [2, true, new Date(), null], [3, true, null, new Date('2020-01-01')],
    ] as const) {
      await db.guardianMachineCredential.create({ data: {
        companyId: company.id, label: 'local test', keyHash: `${prefix}-${index}`,
        keyPrefix: 'local', installId: `${prefix}-${index}`, enabled, revokedAt, expiresAt, lastUsedAt,
      } });
    }
    const service = new GuardianPlatformService(db as any, {} as any);
    const row = (await service.companies()).find((item) => item.id === company.id)!;
    expect(row).toMatchObject({ monitored: true, activeInstallations: 1, openIncidents: 0,
      enrollmentAvailable: true, lastContactAt: lastUsedAt });
    expect(row).not.toHaveProperty('keyHash');
    expect(row).not.toHaveProperty('guardianEnabledBy');
    process.env.GUARDIAN_AUTO_ENROLL_COMPANIES = '';
    expect((await service.companies()).find((item) => item.id === company.id)).toMatchObject({
      monitored: true, enrollmentAvailable: false, enrollmentBlockReason: 'ENROLLMENT_RESTRICTED',
    });
  });
});
