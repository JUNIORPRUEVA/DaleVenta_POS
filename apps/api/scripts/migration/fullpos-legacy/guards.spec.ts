/**
 * Guards: everything that must abort before any write.
 * Covers required test cases 34-37.
 */

import {
  EXPECTED_SOURCE_SHA256,
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_OWNER_USER_ID,
  TARGET_TERMINAL_ID,
  TARGET_WAREHOUSE_ID,
} from './constants';
import { assertSourceSha256, assertTargetSnapshot } from './guards';
import { buildSnapshot, OTHER_TENANT_ID as OTHER_TENANT } from './test-support';

describe('assertSourceSha256', () => {
  it('accepts the expected hash (case-insensitive)', () => {
    expect(() => assertSourceSha256(EXPECTED_SOURCE_SHA256.toLowerCase())).not.toThrow();
  });

  it('34. aborts when the source SHA256 differs', () => {
    expect(() => assertSourceSha256('DEADBEEF')).toThrow(/SOURCE_HASH_MISMATCH/);
  });
});

describe('assertTargetSnapshot', () => {
  it('passes for the locked tenant with a clean baseline', () => {
    expect(() => assertTargetSnapshot(buildSnapshot())).not.toThrow();
  });

  it('35. aborts when the target company id differs', () => {
    const snapshot = buildSnapshot({
      company: {
        id: OTHER_TENANT,
        name: TARGET_COMPANY_NAME,
        status: 'ACTIVE',
        plan: 'STANDARD',
        licenseStatus: 'TRIAL',
        productSource: null,
        maxProducts: 100,
      },
    });
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_COMPANY_MISMATCH/);
  });

  it('aborts when the target company name differs', () => {
    const snapshot = buildSnapshot({
      company: {
        id: TARGET_COMPANY_ID,
        name: 'Otra empresa',
        status: 'ACTIVE',
        plan: 'STANDARD',
        licenseStatus: 'TRIAL',
        productSource: null,
        maxProducts: 100,
      },
    });
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_COMPANY_NAME_MISMATCH/);
  });

  it('aborts when the company does not exist', () => {
    expect(() => assertTargetSnapshot(buildSnapshot({ company: null }))).toThrow(
      /TARGET_COMPANY_MISSING/,
    );
  });

  it('36. aborts when the warehouse id differs', () => {
    const snapshot = buildSnapshot({
      warehouse: { id: OTHER_TENANT, companyId: TARGET_COMPANY_ID, name: 'W', code: 'W', isActive: true },
    });
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_WAREHOUSE_MISMATCH/);
  });

  it('37. aborts when the warehouse belongs to another tenant', () => {
    const snapshot = buildSnapshot({
      warehouse: {
        id: TARGET_WAREHOUSE_ID,
        companyId: OTHER_TENANT,
        name: 'W',
        code: 'W',
        isActive: true,
      },
    });
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_WAREHOUSE_OTHER_TENANT/);
  });

  it('37. aborts when the terminal belongs to another tenant', () => {
    const snapshot = buildSnapshot({
      terminal: {
        id: TARGET_TERMINAL_ID,
        companyId: OTHER_TENANT,
        name: 'T',
        code: 'T',
        isActive: true,
        defaultWarehouseId: TARGET_WAREHOUSE_ID,
      },
    });
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_TERMINAL_OTHER_TENANT/);
  });

  it('aborts when the terminal points to another warehouse', () => {
    const snapshot = buildSnapshot({
      terminal: {
        id: TARGET_TERMINAL_ID,
        companyId: TARGET_COMPANY_ID,
        name: 'T',
        code: 'T',
        isActive: true,
        defaultWarehouseId: OTHER_TENANT,
      },
    });
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_TERMINAL_WAREHOUSE_MISMATCH/);
  });

  it('aborts when the terminal is missing', () => {
    expect(() => assertTargetSnapshot(buildSnapshot({ terminal: null }))).toThrow(
      /TARGET_TERMINAL_MISSING/,
    );
  });

  it('aborts when the owner user belongs to another tenant', () => {
    const snapshot = buildSnapshot({
      ownerUser: { id: TARGET_OWNER_USER_ID, companyId: OTHER_TENANT, blocked: false },
    });
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_OWNER_OTHER_TENANT/);
  });

  it('aborts when the tenant baseline is not empty', () => {
    const snapshot = buildSnapshot();
    snapshot.baseline.sales = 1;
    expect(() => assertTargetSnapshot(snapshot)).toThrow(/TARGET_BASELINE_NOT_EMPTY/);
  });

  it('can skip the baseline check explicitly', () => {
    const snapshot = buildSnapshot();
    snapshot.baseline.sales = 1;
    expect(() => assertTargetSnapshot(snapshot, { requireCleanBaseline: false })).not.toThrow();
  });
});
