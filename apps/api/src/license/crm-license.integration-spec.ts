import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { CrmLicenseService, parseCrmCommand } from './crm-license.service';
import { LicenseService } from './license.service';

// Explicit disposable database only; never infer a test target from application .env.
const fixtureUrl = process.env.CRM_LICENSE_FIXTURE_URL;
const suite = fixtureUrl ? describe : describe.skip;
suite('CRM management with isolated PostgreSQL', () => {
  let db: PrismaClient, service: CrmLicenseService, licenses: LicenseService;
  let company: any;
  const serviceId = randomUUID(), actorId = 'usr_' + 'a'.repeat(24);
  const future = new Date(Date.now() + 86400000 * 45);
  beforeAll(async () => {
    const url = new URL(fixtureUrl!);
    if (url.hostname !== '127.0.0.1' || !['55519', '56701'].includes(url.port) || url.pathname !== '/crm_license_fixture' || url.search || url.hash) throw Error('unsafe_fixture_target');
    db = new PrismaClient({ datasources: { db: { url: fixtureUrl } } });
    licenses = new LicenseService(db as any, {} as any, { emitCompany: jest.fn() } as any);
    service = new CrmLicenseService(db as any, licenses, { get: () => 'true' } as any);
    await db.$connect();
  });
  beforeEach(async () => {
    await db.user.deleteMany();
    await db.company.deleteMany();
    company = await db.company.create({ data: { name: 'Empresa ficticia', slug: 'fixture', licenseStatus: 'ACTIVE', licenseKey: 'FIXTURE-NOT-A-REAL-LICENSE', licenseExpiresAt: future, maxUsers: 5, maxProducts: 200 } });
  });
  afterAll(async () => { await db.$disconnect(); });
  const cmd = (action: string, extra = {}) => ({ operationId: randomUUID(), serviceId, actorId, action, expectedVersion: company.updatedAt.toISOString(), reason: 'Prueba local ficticia', ...extra });

  it('pages beyond 25 and 100 without hiding companies and filters effective expired states', async () => {
    await db.company.createMany({ data: Array.from({ length: 111 }, (_, i) => ({ name: `Fixture ${i}`, slug: `fixture-${i}`, licenseStatus: i % 2 ? 'ACTIVE' as const : 'TRIAL' as const, licenseExpiresAt: new Date(2000, 0, 1), trialEndsAt: new Date(2000, 0, 1) })) });
    const ids = new Set<string>();
    for (let page = 1; page <= 5; page++) {
      const r = await service.list({ page, limit: 25 }); expect(r.total).toBe(112);
      for (const row of r.items) ids.add(row.companyId);
    }
    expect(ids.size).toBe(112);
    const expired = await service.list({ status: 'VENCIDA', limit: 100 }); expect(expired.total).toBe(111);
    expect(expired.items.every(x => x.status === 'EXPIRED')).toBe(true);
    expect((await service.list({ status: 'ACTIVA', query: 'Empresa' })).total).toBe(1);
  });
  it('edits profile and limits without changing license key, expiry, activation or plan', async () => {
    await service.command(company.id, cmd('update', { fields: { name: 'Empresa corregida', maxUsers: 7, notes: 'Nota ficticia' } }));
    const after = await db.company.findUniqueOrThrow({ where: { id: company.id } });
    expect(after.name).toBe('Empresa corregida'); expect(after.maxUsers).toBe(7);
    for (const k of ['licenseKey', 'licenseExpiresAt', 'licenseActivatedAt', 'plan']) expect((after as any)[k]).toEqual(company[k]);
    expect((await db.appConfig.findUnique({ where: { companyId: company.id } }))?.companyName).toBe('Empresa corregida');
    const log = await db.companyLicenseAuditLog.findFirstOrThrow();
    expect(log.action).toBe('license.crm.update'); expect(JSON.stringify(log)).not.toContain(company.licenseKey);
  });
  it('retains dates of expired trials in the CRM while preserving the legacy projection', async () => {
    const end = new Date(Date.now() - 86400000 * 3);
    company = await db.company.update({ where: { id: company.id }, data: { licenseStatus: 'TRIAL', licenseExpiresAt: null, trialEndsAt: end } });
    const legacy = await licenses.getCompanyLicenseStatus(company.id);
    expect(legacy.periodEndsAt).toBeNull();
    const detail = await service.detail(company.id);
    expect(detail.status).toBe('EXPIRED'); expect(detail.periodEndsAt).toEqual(end); expect(detail.daysRemaining).toBeLessThanOrEqual(-3);
    expect((await service.list({ status: 'VENCIDA' })).items[0].periodEndsAt).toEqual(end);
  });
  it('edits effective catalog quotas through audited extras without changing paid dates or keys', async () => {
    await db.licensePlan.upsert({ where: { code: 'fixture-admin' }, update: {}, create: {
      code: 'fixture-admin', name: 'Plan sintético', monthlyPrice: '1', currency: 'DOP', version: 1,
      maxUsers: 2, maxProducts: 100, maxWarehouses: 1, multiWarehouse: false,
      ecf: false, taxes: false, wholesale: false, uom: true, active: true,
    } });
    company = await db.company.update({ where: { id: company.id }, data: { planCode: 'fixture-admin' } });
    const command = cmd('update', { fields: { maxUsers: 3, maxProducts: 140, maxWarehouses: 2, allowWholesale: true } });
    const result = await service.command(company.id, command);
    expect(result.license.limits.maxProducts).toBe(140);
    expect(result.license.limits.maxUsers).toBe(3);
    expect(result.license.commercial?.override?.allowWholesale).toBe(true);
    const grant = await db.licenseCompanyOverride.findUniqueOrThrow({ where: { companyId: company.id } });
    expect(grant.extraProducts).toBe(40); expect(grant.extraUsers).toBe(1); expect(grant.extraWarehouses).toBe(1);
    await service.command(company.id, command);
    const saved = await db.company.findUniqueOrThrow({ where: { id: company.id } });
    expect(saved.licenseExpiresAt).toEqual(company.licenseExpiresAt); expect(saved.licenseKey).toBe(company.licenseKey);
    expect((await db.licenseCompanyOverride.findUniqueOrThrow({ where: { companyId: company.id } })).extraProducts).toBe(40);
    expect(await db.companyLicenseAuditLog.count()).toBe(1);
    const logs = await db.companyLicenseAuditLog.findFirstOrThrow();
    expect((logs.after as any).commercial.override.extraProducts).toBe(40);
  });
  it('rejects quotas below the catalog and does not revive expired commercial grants implicitly', async () => {
    await db.licensePlan.upsert({ where: { code: 'fixture-admin' }, update: {}, create: {
      code: 'fixture-admin', name: 'Plan sintético', monthlyPrice: '1', maxUsers: 2, maxProducts: 100, maxWarehouses: 1,
    } });
    company = await db.company.update({ where: { id: company.id }, data: { planCode: 'fixture-admin' } });
    await expect(service.command(company.id, cmd('update', { fields: { maxProducts: 99 } }))).rejects.toThrow('limit_below_plan');
    await db.licenseCompanyOverride.create({ data: { companyId: company.id, extraProducts: 40, allowWholesale: true, expiresAt: new Date(2000, 0, 1) } });
    await expect(service.command(company.id, cmd('update', { fields: { maxProducts: 150 } }))).rejects.toThrow('override_expired');
    expect((await db.licenseCompanyOverride.findUniqueOrThrow({ where: { companyId: company.id } })).extraProducts).toBe(40);
    expect(await db.companyLicenseAuditLog.count()).toBe(0);
  });
  it('deduplicates simultaneous same UUID requests and rejects UUID reuse with changed payload', async () => {
    const command = cmd('suspend');
    const results = await Promise.all([service.command(company.id, command), service.command(company.id, command)]);
    expect(results.map(x => x.deduplicated).sort()).toEqual([false, true]); expect(await db.companyLicenseAuditLog.count()).toBe(1);
    await expect(service.command(company.id, { ...command, reason: 'Changed payload' })).rejects.toThrow('operation_id_reused');
  });
  it('rejects an old version after a different update', async () => {
    await service.command(company.id, cmd('update', { fields: { notes: 'First update' } }));
    await expect(service.command(company.id, cmd('suspend'))).rejects.toThrow('license_changed_reload');
    expect((await db.company.findUniqueOrThrow({ where: { id: company.id } })).licenseStatus).toBe('ACTIVE');
  });
  it('cannot reuse another company receipt and never mutates the other company', async () => {
    const other = await db.company.create({ data: { name: 'Otra empresa ficticia', slug: 'other-fixture', licenseStatus: 'ACTIVE', licenseKey: 'OTHER-FIXTURE', licenseExpiresAt: future } });
    const command = cmd('suspend'); await service.command(company.id, command);
    await expect(service.command(other.id, { ...command, expectedVersion: other.updatedAt.toISOString() })).rejects.toThrow('operation_id_reused');
    expect(await db.company.findUniqueOrThrow({ where: { id: other.id } })).toEqual(other);
    expect(await db.companyLicenseAuditLog.count({ where: { companyId: other.id } })).toBe(0);
  });
  it('revokes only sessions of the selected company and rejects limits below real usage', async () => {
    const other = await db.company.create({ data: { name: 'Otra empresa ficticia', slug: 'other-fixture' } });
    const users = await Promise.all([0,1].map(i => db.user.create({ data: { companyId: company.id, email: `fixture-${i}@example.invalid`, passwordHash: 'synthetic-not-a-login-hash', nombreCompleto: 'Usuario ficticio', telefono: '0000000000', edad: 25, role: 'ADMIN' } })));
    await expect(service.command(company.id, cmd('update', { fields: { maxUsers: 1 } }))).rejects.toThrow('limit_below_current_usage');
    await db.authSession.createMany({ data: [company.id, other.id].map(companyId => ({ userId: users[0].id, companyId, tokenFamily: randomUUID(), refreshTokenHash: 'fixture-only', expiresAt: future })) });
    await service.command(company.id, cmd('suspend'));
    expect(await db.authSession.count({ where: { companyId: company.id, revokedAt: { not: null } } })).toBe(1);
    expect(await db.authSession.count({ where: { companyId: other.id, revokedAt: null } })).toBe(1);
  });
  it('preserves a current paid period and key when suspending and reactivating', async () => {
    await service.command(company.id, cmd('suspend'));
    company = await db.company.findUniqueOrThrow({ where: { id: company.id } });
    await service.command(company.id, cmd('reactivate'));
    const after = await db.company.findUniqueOrThrow({ where: { id: company.id } });
    expect(after.licenseStatus).toBe('ACTIVE'); expect(after.licenseKey).toBe('FIXTURE-NOT-A-REAL-LICENSE'); expect(after.licenseExpiresAt).toEqual(future);
  });
  it('does not reactivate expired periods or create new keys', async () => {
    company = await db.company.update({ where: { id: company.id }, data: { licenseStatus: 'BLOCKED', status: 'SUSPENDED', licenseExpiresAt: new Date(2000, 0, 1) } });
    await expect(service.command(company.id, cmd('reactivate'))).rejects.toThrow('paid_period_required');
    expect(await db.companyLicenseAuditLog.count()).toBe(0);
  });
  it('requires typed confirmation to revoke and preserves company and configuration', async () => {
    await db.appConfig.create({ data: { id: 'fixture-config', companyId: company.id, companyName: company.name } });
    await expect(service.command(company.id, cmd('revoke', { confirmationName: 'Wrong company' }))).rejects.toThrow('confirmation_name_mismatch');
    await service.command(company.id, cmd('revoke', { confirmationName: company.name }));
    const after = await db.company.findUniqueOrThrow({ where: { id: company.id } });
    expect(after.licenseKey).toBeNull(); expect(after.status).toBe('SUSPENDED'); expect(await db.appConfig.count()).toBe(1);
  });
  it('rolls back a mutation when the mandatory audit insert fails', async () => {
    // A foreign-key failure after the update proves PostgreSQL rolls back the entire transaction.
    {
      // Inject the foreign-key failure on the actual transaction delegate.
      const proxied = { $transaction: (fn: any, opts: any) => db.$transaction(tx => fn(new Proxy(tx, { get: (t, k) => k === 'companyLicenseAuditLog' ? { ...t.companyLicenseAuditLog, create: (args: any) => t.companyLicenseAuditLog.create({ ...args, data: { ...args.data, companyId: randomUUID() } }) } : (t as any)[k] })), opts) };
      const broken = new CrmLicenseService(proxied as any, licenses, { get: () => 'true' } as any);
      await expect(broken.command(company.id, cmd('suspend'))).rejects.toThrow();
    }
    expect((await db.company.findUniqueOrThrow({ where: { id: company.id } })).licenseStatus).toBe('ACTIVE');
    expect(await db.companyLicenseAuditLog.count()).toBe(0);
  });
  it('default feature gate rejects writes and unknown payment/key fields are rejected', async () => {
    const disabled = new CrmLicenseService(db as any, licenses, { get: () => undefined } as any);
    await expect(disabled.command(company.id, cmd('suspend'))).rejects.toThrow('crm_management_disabled');
    for (const fields of [{ expiresAt: future }, { licenseKey: 'FORGED' }, { maxUsers: 0 }, { plan: 'PREMIUM' }]) expect(() => parseCrmCommand(cmd('update', { fields }))).toThrow('invalid_crm_command');
  });
});
