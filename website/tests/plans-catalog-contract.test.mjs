import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { plans } from '../src/config/site.ts';

// Read the seed as text only: importing it would execute a database write.
const seed = readFileSync(new URL('../../apps/api/scripts/seed-license-plans.ts', import.meta.url), 'utf8');

test('public offers agree with the existing backend catalogue, without executing its seed', () => {
  assert.equal(plans.length, 4);
  for (const plan of plans) {
    const block = seed.match(new RegExp(`\\{\\s*code: '${plan.id}'[\\s\\S]*?\\n  \\}`))?.[0];
    assert.ok(block, `Missing backend catalogue entry: ${plan.id}`);
    const number = field => {
      const match = block.match(new RegExp(`^\\s*${field}: '?([0-9.]+)`, 'm'));
      assert.ok(match, `Missing ${field} for ${plan.id}`);
      return Number(match[1]);
    };
    assert.equal(plan.monthly, number('monthlyPrice'), `${plan.id}: monthly price`);
    const labels = plan.specs.map(spec => spec.label);
    assert.ok(labels.includes(`${number('maxUsers')} ${number('maxUsers') === 1 ? 'usuario' : 'usuarios'}`));
    assert.ok(labels.includes(`${number('maxProducts').toLocaleString('en-US')} productos`));
    const warehouses = number('maxWarehouses');
    assert.ok(labels.includes(warehouses === 1 ? '1 almacén' : `Hasta ${warehouses} almacenes`));
    if (/ecf: false/.test(block)) assert.ok(plan.excluded.includes('Facturación electrónica'));
    if (/taxes: false/.test(block)) assert.ok(plan.excluded.includes('Impuestos (ITBIS)'));
    if (/multiWarehouse: false/.test(block)) assert.ok(plan.excluded.includes('Multi-almacén'));
  }
});
