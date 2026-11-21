import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { LicenseActivationService } from './orders/license-activation.service';
import { LicenseEntitlementsService } from './plans/license-entitlements.service';
import { WarehousesService } from '../warehouses/warehouses.service';
import { LicenseService } from './license.service';

const fixtureUrl = process.env.LICENSE_PAYMENTS_FIXTURE_URL;
const suite = fixtureUrl ? describe : describe.skip;

suite('integracion IA/planes en PostgreSQL propio', () => {
  let db: PrismaClient;
  const ids: string[] = [];
  const planCode = `audit-${randomUUID().slice(0, 8)}`;
  beforeAll(async () => {
    const url = new URL(fixtureUrl!);
    if (url.hostname !== '127.0.0.1' || !['56701', '56711'].includes(url.port) || url.pathname !== '/appyra_license_e2e' || url.search || url.hash) {
      throw Error('unsafe_fixture_target');
    }
    db = new PrismaClient({ datasources: { db: { url: fixtureUrl } } });
    await db.licensePlan.create({ data: { code: planCode, name: 'Plan sintetico', version: 1,
      monthlyPrice: 100, maxUsers: 2, maxProducts: 100, maxWarehouses: 1, multiWarehouse: true } });
  });
  afterAll(async () => {
    if (!db) return;
    await db.company.deleteMany({ where: { id: { in: ids }, slug: { startsWith: 'ia-plan-audit-' } } });
    await db.licensePlan.deleteMany({ where: { code: planCode } });
    await db.$disconnect();
  });
  async function company(withPlan: boolean) {
    const id = randomUUID(); ids.push(id);
    return db.company.create({ data: { id, name: 'Empresa ficticia', slug: `ia-plan-audit-${id}`,
      planCode: withPlan ? planCode : null, licenseStatus: 'ACTIVE', multiWarehouseEnabled: true,
      ncfEnabled: true, taxEnabled: true, maxUsers: 7, maxProducts: 600,
      licenseActivatedAt: new Date('2026-01-01'), licenseExpiresAt: new Date('2027-03-31T12:00:00Z') } });
  }
  function warehouses() {
    return new WarehousesService(db as never, {} as never, new LicenseEntitlementsService(db as never));
  }
  it('renovaciones concurrentes suman dos meses y respetan concesiones solo de esa empresa', async () => {
    const a = await company(true), b = await company(true);
    await db.licenseCompanyOverride.create({ data: { companyId: a.id, allowEcf: true, allowTaxes: true, extraUsers: 5, extraProducts: 500 } });
    const service = new LicenseActivationService(db as never);
    await Promise.all([1, 2].map(() => service.applyPlan({ companyId: a.id, planCode, months: 1, now: new Date('2026-11-19') })));
    const after = await db.company.findUniqueOrThrow({ where: { id: a.id } });
    expect(after.licenseExpiresAt?.toISOString()).toBe('2027-05-30T12:00:00.000Z');
    expect(after.licenseActivatedAt).toEqual(a.licenseActivatedAt);
    expect(after.ncfEnabled).toBe(true); expect(after.taxEnabled).toBe(true);
    expect(await new LicenseEntitlementsService(db as never).getEntitlements(a.id)).toMatchObject({ maxUsers: 7, maxProducts: 600 });
    const status = await new LicenseService(db as never, {} as never, {} as never, {} as never).getCompanyLicenseStatus(a.id);
    expect(status.limits).toMatchObject({ maxUsers: 7, maxProducts: 600 });
    expect(await db.company.findUniqueOrThrow({ where: { id: b.id } })).toMatchObject({ licenseExpiresAt: b.licenseExpiresAt, ncfEnabled: true });
  });
  it('dos altas simultaneas no superan un almacen y la empresa legada sigue creando varios', async () => {
    const a = await company(true), b = await company(false);
    const service = warehouses();
    const user = (companyId: string) => ({ id: randomUUID(), companyId, role: 'ADMIN' } as never);
    const results = await Promise.allSettled(['ONE', 'TWO'].map(code => service.create(user(a.id), { name: code, code } as never)));
    expect(results.filter(r => r.status === 'fulfilled')).toHaveLength(1);
    expect(results.filter(r => r.status === 'rejected')).toHaveLength(1);
    expect(await db.warehouse.count({ where: { companyId: a.id } })).toBe(1);
    await Promise.all(['A', 'B', 'C'].map(code => service.create(user(b.id), { name: code, code } as never)));
    expect(await db.warehouse.count({ where: { companyId: b.id } })).toBe(3);
  });
});
