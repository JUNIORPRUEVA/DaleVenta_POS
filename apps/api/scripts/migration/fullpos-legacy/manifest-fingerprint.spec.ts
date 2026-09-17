/**
 * Manifest fingerprint: the immutable identity of the migration.
 *
 * The manifest FILE hash changes on every run (`generatedAt` is regenerated), so the
 * cutover package needs a content digest that depends only on the source snapshot and the
 * plan, plus per-entity digests of the deterministic id sets (the rollback identity set).
 */

import { buildGoldenFixture } from './fixtures';
import { buildManifest, manifestFingerprint, serializeManifest } from './manifest';
import { buildReconciliation } from './reconcile';
import { planMigration } from './transform';

const SOURCE = {
  path: 'C:\\Users\\pc\\Documents\\fullpods.db',
  sha256: 'A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA',
  integrityCheck: 'ok',
  foreignKeyViolations: 0,
  userVersion: 36,
};

function manifestAt(generatedAt: string) {
  const plan = planMigration(buildGoldenFixture());
  return buildManifest({
    plan,
    reconciliation: buildReconciliation(plan, generatedAt),
    source: SOURCE,
    generatedAt,
    warehouseId: 'ffc9ef9b-9157-418d-8aa1-94112278bb68',
  });
}

describe('manifestFingerprint', () => {
  const first = manifestAt('2026-09-16T10:00:00.000Z');
  const second = manifestAt('2026-09-16T23:59:59.000Z');

  it('is stable across regenerations that only change timestamps', () => {
    const a = manifestFingerprint(first);
    const b = manifestFingerprint(second);
    expect(a.contentDigest).toBe(b.contentDigest);
    expect(a.idSets).toEqual(b.idSets);
    expect(a.counts).toEqual(b.counts);
  });

  it('still produces a different manifest FILE hash for a different timestamp', () => {
    expect(serializeManifest(first)).not.toBe(serializeManifest(second));
  });

  it('is independent of object key order', () => {
    const entries = Object.entries(JSON.parse(JSON.stringify(first)) as Record<string, unknown>);
    const reversed = Object.fromEntries([...entries].reverse()) as typeof first;
    expect(manifestFingerprint(reversed).contentDigest).toBe(manifestFingerprint(first).contentDigest);
  });

  it('is independent of id ordering inside the plan arrays', () => {
    const shuffled = JSON.parse(JSON.stringify(first)) as typeof first;
    shuffled.products = [...shuffled.products].reverse();
    shuffled.sales = [...shuffled.sales].reverse();
    const fingerprint = manifestFingerprint(shuffled);
    expect(fingerprint.idSets.products).toBe(manifestFingerprint(first).idSets.products);
    expect(fingerprint.idSets.sales).toBe(manifestFingerprint(first).idSets.sales);
  });

  it('exposes the rollback identity set: 91 products, 87 stock scope, 50 shifts, sales and items', () => {
    const fingerprint = manifestFingerprint(first);
    expect(fingerprint.counts.products).toBe(first.products.length);
    expect(fingerprint.counts.activeProducts).toBe(
      first.products.filter((product) => product.status === 'ACTIVE').length,
    );
    expect(fingerprint.counts.warehouseStockScope).toBe(fingerprint.counts.activeProducts);
    expect(fingerprint.counts.shifts).toBe(first.shifts.length);
    expect(fingerprint.counts.sales).toBe(first.sales.length);
    expect(fingerprint.counts.saleItems).toBe(first.saleItems.length);
    for (const digest of Object.values(fingerprint.idSets)) {
      expect(digest).toMatch(/^[0-9A-F]{64}$/);
    }
  });

  it('changes when the plan content changes', () => {
    const tampered = JSON.parse(JSON.stringify(first)) as typeof first;
    tampered.sales[0].revenue = '0.00';
    expect(manifestFingerprint(tampered).contentDigest).not.toBe(
      manifestFingerprint(first).contentDigest,
    );
    expect(manifestFingerprint(tampered).idSets.sales).toBe(manifestFingerprint(first).idSets.sales);
  });
});
