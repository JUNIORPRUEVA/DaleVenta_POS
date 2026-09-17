/**
 * Deterministic UUIDv5 derivation.
 *
 * Covers required test cases 32, 33 and the id-stability part of 34/39.
 * The expected values were computed independently with Python's `uuid` module
 * (see the reference vectors below), so they validate the implementation itself,
 * not just its self-consistency.
 */

import {
  MIGRATION_NAMESPACE_UUID,
  SOURCE_SYSTEM,
  TARGET_COMPANY_ID,
} from './constants';
import { deriveTargetId, deriveTargetIdForTenant, uuidV5 } from './deterministic-uuid';
import { LEGACY_TABLE } from './constants';

const NAMESPACE_DNS = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
const OTHER_TENANT = '00000000-0000-4000-8000-000000000000';

describe('uuidV5', () => {
  it('matches the RFC 4122 test vector', () => {
    expect(uuidV5(NAMESPACE_DNS, 'www.example.com')).toBe('2ed6657d-e927-568b-95e1-2665a8aea6a2');
  });

  it('produces a syntactically valid version-5 UUID', () => {
    const value = uuidV5(MIGRATION_NAMESPACE_UUID, 'name');
    expect(value).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it('rejects an invalid namespace', () => {
    expect(() => uuidV5('not-a-uuid', 'name')).toThrow(/UUID inválido/);
  });
});

describe('deriveTargetId', () => {
  it('32. is stable across runs (idempotent)', () => {
    const first = deriveTargetId(LEGACY_TABLE.products, 51);
    const second = deriveTargetId(LEGACY_TABLE.products, 51);
    expect(first).toBe(second);
  });

  it('matches the independent reference values', () => {
    expect(deriveTargetId(LEGACY_TABLE.products, 51)).toBe('3e5030c1-27fd-5ce5-8662-a1ee43707d22');
    expect(deriveTargetId(LEGACY_TABLE.sales, 6)).toBe('da8d339b-7243-5276-becf-7c0754099d90');
    expect(deriveTargetId(LEGACY_TABLE.saleItems, 6)).toBe('b37a08b8-84b1-57a2-8c7e-ab4e55c396b6');
    expect(deriveTargetId(LEGACY_TABLE.cashSessions, 2)).toBe('2f314713-d841-5003-9705-2c219cd54188');
  });

  it('33. gives different UUIDs for the same legacy id in different tables', () => {
    const asProduct = deriveTargetId(LEGACY_TABLE.products, 51);
    const asSale = deriveTargetId(LEGACY_TABLE.sales, 51);
    expect(asProduct).not.toBe(asSale);
    expect(asSale).toBe('842006e9-d20c-59e7-bf79-8921cfbd4ec6');
  });

  it('gives different UUIDs for different tenants', () => {
    const tenantA = deriveTargetIdForTenant({
      companyId: TARGET_COMPANY_ID,
      sourceSystem: SOURCE_SYSTEM,
      legacyTable: LEGACY_TABLE.products,
      legacyId: 51,
    });
    const tenantB = deriveTargetIdForTenant({
      companyId: OTHER_TENANT,
      sourceSystem: SOURCE_SYSTEM,
      legacyTable: LEGACY_TABLE.products,
      legacyId: 51,
    });
    expect(tenantA).not.toBe(tenantB);
    expect(tenantB).toBe('ce7bd565-a927-5ecc-947c-ca4bf59a3847');
  });

  it('gives different UUIDs for different source systems', () => {
    const fullpos = deriveTargetIdForTenant({
      companyId: TARGET_COMPANY_ID,
      sourceSystem: SOURCE_SYSTEM,
      legacyTable: LEGACY_TABLE.products,
      legacyId: 51,
    });
    const other = deriveTargetIdForTenant({
      companyId: TARGET_COMPANY_ID,
      sourceSystem: 'ANOTHER_SYSTEM',
      legacyTable: LEGACY_TABLE.products,
      legacyId: 51,
    });
    expect(fullpos).not.toBe(other);
  });

  it('is not affected by id type (number vs string)', () => {
    expect(deriveTargetId(LEGACY_TABLE.products, 51)).toBe(deriveTargetId(LEGACY_TABLE.products, '51'));
  });
});
