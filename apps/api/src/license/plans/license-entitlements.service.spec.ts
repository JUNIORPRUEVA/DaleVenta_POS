import {
  buildEntitlements,
  isFeatureIncluded,
} from './license-entitlements.service';

const now = new Date('2026-11-16T12:00:00.000Z');

const company = {
  planCode: 'basico',
  planCatalogVersion: 1,
  maxUsers: 2,
  maxProducts: 100,
  maxWarehouses: 1,
};

const basico = {
  code: 'basico',
  name: 'FullPOS Básico',
  version: 1,
  maxUsers: 2,
  maxProducts: 100,
  maxWarehouses: 1,
  multiWarehouse: false,
  ecf: false,
  taxes: false,
  wholesale: false,
  uom: true,
  ecfMonthlyQuota: null,
};

const pro = {
  ...basico,
  code: 'pro',
  name: 'FullPOS Pro',
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  multiWarehouse: true,
  ecf: true,
  taxes: true,
  wholesale: true,
  ecfMonthlyQuota: 1500,
};

describe('buildEntitlements', () => {
  it('Básico no incluye e-CF, impuestos ni mayoreo', () => {
    const result = buildEntitlements(company, basico, null, now);
    expect(result.maxWarehouses).toBe(1);
    expect(result.features).toEqual({
      ecf: false,
      taxes: false,
      wholesale: false,
      uom: true,
    });
    expect(isFeatureIncluded(result, 'ecf')).toBe(false);
    expect(isFeatureIncluded(result, 'wholesale')).toBe(false);
    expect(isFeatureIncluded(result, 'uom')).toBe(true);
  });

  it('Pro incluye todo y permite 5 almacenes', () => {
    const result = buildEntitlements(
      { ...company, planCode: 'pro' },
      pro,
      null,
      now,
    );
    expect(result.maxWarehouses).toBe(5);
    expect(result.features.ecf).toBe(true);
    expect(result.ecfMonthlyQuota).toBe(1500);
    expect(result.source).toBe('plan');
  });

  it('suma las excepciones vigentes a las cuotas', () => {
    const result = buildEntitlements(company, basico, {
      extraUsers: 1,
      extraProducts: 200,
      extraWarehouses: 2,
      allowEcf: true,
      allowTaxes: false,
      allowWholesale: false,
      allowUom: false,
      allowMultiWarehouse: false,
      expiresAt: new Date('2026-12-01T00:00:00.000Z'),
    }, now);
    expect(result.maxUsers).toBe(3);
    expect(result.maxProducts).toBe(300);
    expect(result.maxWarehouses).toBe(3);
    expect(result.features.ecf).toBe(true);
    expect(result.overrideApplied).toBe(true);
  });

  it('ignora una excepción caducada', () => {
    const result = buildEntitlements(company, basico, {
      extraUsers: 5,
      extraProducts: 0,
      extraWarehouses: 5,
      allowEcf: true,
      allowTaxes: true,
      allowWholesale: true,
      allowUom: true,
      allowMultiWarehouse: true,
      expiresAt: new Date('2026-11-01T00:00:00.000Z'),
    }, now);
    expect(result.maxUsers).toBe(2);
    expect(result.features.ecf).toBe(false);
    expect(result.overrideApplied).toBe(false);
  });

  it('una empresa sin plan no se recorta (compatibilidad)', () => {
    const result = buildEntitlements(
      { planCode: null, planCatalogVersion: null, maxUsers: 7, maxProducts: 70, maxWarehouses: null },
      null,
      null,
      now,
    );
    expect(result.source).toBe('none');
    expect(result.maxWarehouses).toBe(1);
    expect(isFeatureIncluded(result, 'ecf')).toBe(true);
    expect(result.multiWarehouse).toBe(true);
  });

  it('una excepcion concede multi-almacen aunque el plan no lo incluya', () => {
    const sinExcepcion = buildEntitlements(company, basico, null, now);
    expect(sinExcepcion.multiWarehouse).toBe(false);

    const conExcepcion = buildEntitlements(company, basico, {
      extraUsers: 0,
      extraProducts: 0,
      extraWarehouses: 0,
      allowEcf: false,
      allowTaxes: false,
      allowWholesale: false,
      allowUom: false,
      allowMultiWarehouse: true,
      expiresAt: null,
    }, now);
    expect(conExcepcion.multiWarehouse).toBe(true);
    expect(conExcepcion.overrideApplied).toBe(true);
  });
});
