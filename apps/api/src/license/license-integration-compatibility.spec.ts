import { LicenseActivationService } from './orders/license-activation.service';
import { LicenseEntitlementsService } from './plans/license-entitlements.service';
import { LicenseService } from './license.service';
import { WarehousesService } from '../warehouses/warehouses.service';

const now = new Date('2026-11-19T12:00:00Z');
const plan = {
  code: 'basico', name: 'FullPOS Básico', version: 1,
  maxUsers: 2, maxProducts: 100, maxWarehouses: 1, multiWarehouse: false,
  ecf: false, taxes: false, wholesale: false, uom: false, ecfMonthlyQuota: null, active: true,
};
const concession = {
  extraUsers: 4, extraProducts: 200, extraWarehouses: 2,
  allowEcf: true, allowTaxes: true, allowWholesale: true, allowUom: true,
  allowMultiWarehouse: true, expiresAt: null,
};

describe('integracion IA y planes: compatibilidad de clientes', () => {
  it.each([null, new Date('2026-12-19T12:00:00Z')])('renueva conservando funciones concedidas y meses pagados (%s)', async expiresAt => {
    const update = jest.fn().mockResolvedValue({ id: 'company-a' });
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([{ id: 'company-a' }]),
      company: {
        findUnique: jest.fn().mockResolvedValue({ licenseStatus: 'ACTIVE', licenseExpiresAt: new Date('2026-12-31T12:00:00Z'),
          licenseActivatedAt: new Date('2026-01-01T00:00:00Z'), ncfEnabled: true, taxEnabled: true,
          wholesalePriceListsEnabled: true, measurementUnitsEnabled: true }), update,
      },
      licenseCompanyOverride: { findUnique: jest.fn().mockResolvedValue({ ...concession, expiresAt }) },
    };
    const service = new LicenseActivationService({ licensePlan: { findUnique: async () => plan } } as never);
    const result = await service.applyPlan({ companyId: 'company-a', planCode: 'basico', months: 1, now, tx: tx as never });
    expect(result.periodStart.toISOString()).toBe('2026-12-31T12:00:00.000Z');
    expect(result.periodEnd.toISOString()).toBe('2027-01-31T12:00:00.000Z');
    expect(result.turnedOff).toEqual([]);
    expect(update.mock.calls[0][0].data).toMatchObject({ ncfEnabled: true, taxEnabled: true,
      wholesalePriceListsEnabled: true, measurementUnitsEnabled: true, maxUsers: 2 });
    expect(tx.licenseCompanyOverride.findUnique).toHaveBeenCalledWith({ where: { companyId: 'company-a' } });
  });

  it('no conserva concesiones caducadas ni enciende modulos por una concesion', async () => {
    const update = jest.fn().mockResolvedValue({ id: 'company-a' });
    const tx = { $queryRaw: jest.fn(), company: {
      findUnique: async () => ({ licenseStatus: 'ACTIVE', licenseExpiresAt: null, licenseActivatedAt: null,
        ncfEnabled: true, taxEnabled: false, wholesalePriceListsEnabled: false, measurementUnitsEnabled: false }), update,
    }, licenseCompanyOverride: { findUnique: async () => ({ ...concession, expiresAt: new Date('2026-11-18') }) } };
    const service = new LicenseActivationService({ licensePlan: { findUnique: async () => plan } } as never);
    const result = await service.applyPlan({ companyId: 'company-a', planCode: 'basico', now, tx: tx as never });
    expect(result.turnedOff).toEqual(['ncfEnabled']);
    expect(update.mock.calls[0][0].data).toMatchObject({ ncfEnabled: false, taxEnabled: false });
  });

  it('una empresa sin catalogo puede seguir creando almacenes sin un limite nuevo', async () => {
    const company = { planCode: null, planCatalogVersion: null, maxUsers: 5, maxProducts: 500, maxWarehouses: null };
    const db = { company: { findUnique: async () => company }, licenseCompanyOverride: { findUnique: async () => null } };
    const entitlements = new LicenseEntitlementsService(db as never);
    await expect(entitlements.assertWarehouseSlot('company-a', 8)).resolves.toMatchObject({ source: 'none' });
    const create = jest.fn().mockResolvedValue({ id: 'warehouse-new' });
    const count = jest.fn().mockResolvedValue(8);
    const tx = { $queryRaw: jest.fn().mockResolvedValue([{ id: 'company-a' }]),
      company: { findUnique: async () => company }, licenseCompanyOverride: { findUnique: async () => null },
      warehouse: { count, create } };
    const prisma = { company: { findUnique: async () => ({ multiWarehouseEnabled: true }) },
      $transaction: async (run: (db: typeof tx) => unknown) => run(tx) };
    const warehouses = new WarehousesService(prisma as never, {} as never, entitlements);
    await expect(warehouses.create({ id: 'user-a', companyId: 'company-a', role: 'ADMIN' } as never,
      { name: 'Sucursal', code: 'NEW' } as never)).resolves.toMatchObject({ id: 'warehouse-new' });
    expect(create.mock.calls[0][0].data.companyId).toBe('company-a');
  });

  it('la IA informa el catalogo y cupos con concesiones sin filtrar secretos', async () => {
    const db = { company: { findUnique: async () => ({ planCode: 'basico', planCatalogVersion: 1,
      maxUsers: 2, maxProducts: 100, maxWarehouses: 1 }) }, licensePlan: { findUnique: async () => plan },
      licenseCompanyOverride: { findUnique: async () => concession } };
    const service = new LicenseService(db as never, {} as never, {} as never, {} as never);
    jest.spyOn(service, 'getCompanyLicenseStatus').mockResolvedValue({ companyName: 'Ficticia', plan: 'STANDARD',
      licenseTypeLabel: 'Standard', status: 'ACTIVE', isUsable: true, limits: { maxUsers: 2, maxProducts: 100 },
      usage: { users: 4, products: 90 }, licenseKey: 'synthetic-excluded', notes: 'internal-excluded',
      account: { responsibleEmail: 'private@example.invalid' } } as never);
    const result = await service.getAssistantAccountSummary('company-a');
    expect(result).toMatchObject({ planCode: 'basico', planLabel: 'FullPOS Básico', limits: { maxUsers: 6, maxProducts: 300 } });
    expect(JSON.stringify(result)).not.toMatch(/synthetic-excluded|internal-excluded|private@example/);
    expect((service as any).activateMyLicense).toBeUndefined();
    expect((service as any).updateMyLimits).toBeUndefined();
  });
});
