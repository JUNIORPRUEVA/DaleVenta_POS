import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { CrmLicenseService } from './crm-license.service';
import { LicenseService } from './license.service';

const fixtureUrl = process.env.CRM_LICENSE_FIXTURE_URL;
const local = fixtureUrl ? describe : describe.skip;

local('CRM license changes preserve each company fiscal numbering', () => {
  let db: PrismaClient;
  let service: CrmLicenseService;
  const ids = [randomUUID(), randomUUID()];
  const future = new Date(Date.now() + 45 * 86400000);

  beforeAll(async () => {
    const url = new URL(fixtureUrl!);
    if (url.hostname !== '127.0.0.1' || !['55519', '56701', '56711'].includes(url.port) ||
        url.pathname !== '/crm_license_fixture' || url.search || url.hash) {
      throw Error('unsafe_fixture_target');
    }
    db = new PrismaClient({ datasources: { db: { url: fixtureUrl } } });
    await db.$connect();
    const licenses = new LicenseService(db as any, {} as any, { emitCompany: jest.fn() } as any);
    service = new CrmLicenseService(db as any, licenses, { get: () => 'true' } as any);
    for (const [index, id] of ids.entries()) {
      await db.company.create({ data: {
        id, name: `Synthetic fiscal license ${index}`, slug: `crm-fiscal-${id}`,
        licenseStatus: 'ACTIVE', licenseKey: `SYNTHETIC-${id}`, licenseExpiresAt: future,
      } });
      await db.appConfig.create({ data: {
        id: randomUUID(), companyId: id, companyName: `Synthetic fiscal license ${index}`,
        rnc: `10100000${index + 1}`,
      } });
      await db.ecfCompanyConfiguration.create({ data: {
        companyId: id, enabled: true, environment: 'SANDBOX', allowSalesWithoutEcf: true,
      } });
      await db.ecfDgiiAuthorizedSequence.create({ data: {
        companyId: id, environment: 'SANDBOX', documentType: 'E31',
        authorizationNumber: 'SYNTHETIC-NOT-DGII', rangeFrom: 1, rangeTo: 100,
        approvedQuantity: 100, expiresAt: future, declarationVersion: 'synthetic-local-only',
      } });
      await db.ecfSequence.create({ data: {
        companyId: id, environment: 'SANDBOX', documentType: 'E31', prefix: 'E31',
        startNumber: 1, nextNumber: index + 4, endNumber: 100, validUntil: future,
      } });
    }
  });

  afterAll(async () => {
    if (db) {
      await db.company.deleteMany({ where: { id: { in: ids } } });
      await db.$disconnect();
    }
  });

  async function fiscalState() {
    return Promise.all(ids.map(async companyId => ({
      config: await db.ecfCompanyConfiguration.findUnique({ where: { companyId } }),
      authorization: await db.ecfDgiiAuthorizedSequence.findMany({ where: { companyId } }),
      ranges: await db.ecfSequence.findMany({ where: { companyId } }),
    })));
  }

  it('profile, suspend, reactivate and revoke leave authorization, expiry and counters unchanged', async () => {
    const fiscalBefore = await fiscalState();
    const otherCompany = await db.company.findUniqueOrThrow({ where: { id: ids[1] } });
    const otherConfig = await db.appConfig.findUnique({ where: { companyId: ids[1] } });
    for (const action of ['update', 'suspend', 'reactivate', 'revoke']) {
      const company = await db.company.findUniqueOrThrow({ where: { id: ids[0] } });
      await service.command(ids[0], {
        operationId: randomUUID(), serviceId: randomUUID(), actorId: 'usr_' + 'b'.repeat(24),
        expectedVersion: company.updatedAt.toISOString(), action, reason: 'Synthetic fiscal preservation',
        ...(action === 'update' ? { fields: { name: 'Synthetic corrected issuer' } } : {}),
        ...(action === 'revoke' ? { confirmationName: company.name } : {}),
      });
      expect(await fiscalState()).toEqual(fiscalBefore);
      expect(await db.company.findUniqueOrThrow({ where: { id: ids[1] } })).toEqual(otherCompany);
      expect(await db.appConfig.findUnique({ where: { companyId: ids[1] } })).toEqual(otherConfig);
    }
    const issuer = await db.appConfig.findUniqueOrThrow({ where: { companyId: ids[0] } });
    expect(issuer.companyName).toBe('Synthetic corrected issuer');
    expect(issuer.rnc).toBe('101000001');
    expect((await db.ecfCompanyConfiguration.findUniqueOrThrow({ where: { companyId: ids[0] } })).enabled).toBe(true);
    expect(await db.companyLicenseAuditLog.count({ where: { companyId: ids[0] } })).toBe(4);
  });
});
