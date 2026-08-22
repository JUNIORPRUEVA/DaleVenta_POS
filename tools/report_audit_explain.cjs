/**
 * AUDIT: read-only measurement of the Reports module SQL queries.
 * ONLY runs SELECT / EXPLAIN / COUNT queries. NEVER writes.
 *
 * Usage: node tools/report_audit_explain.cjs
 * Reads DATABASE_URL from apps/api/.env
 */
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

function loadDbUrl() {
  const envPath = path.join(__dirname, '..', 'apps', 'api', '.env');
  const content = fs.readFileSync(envPath, 'utf8');
  const match = content.match(/^DATABASE_URL\s*=\s*(.+)$/m);
  if (!match) throw new Error('DATABASE_URL not found');
  return match[1].trim();
}

async function main() {
  const client = new Client({ connectionString: loadDbUrl() });
  await client.connect();
  console.log('Connected.\n');

  // 1. Top companies by invoice volume
  const companies = await client.query(`
    SELECT s.company_id, count(*) AS sales
    FROM "Sale" s
    WHERE s.kind = 'invoice' AND s.is_deleted = false
    GROUP BY s.company_id
    ORDER BY sales DESC
    LIMIT 3
  `);
  console.log('Top companies by active invoices:', companies.rows);
  if (companies.rows.length === 0) {
    console.log('No invoice sales found. Skipping measurements.');
    await client.end();
    return;
  }
  const companyId = companies.rows[0].company_id;

  // Representative ranges (DR time, stored as UTC in Postgres).
  const range30 = { from: '2026-07-23', to: '2026-08-22' };
  const rangeYear = { from: '2025-08-22', to: '2026-08-22' };
  // Matches reports.service parseDominicanDate: start=04:00Z, end=next day 03:59:59.999Z
  const qFrom = (d) => `${d}T04:00:00.000Z`;
  const qTo = (d) => `${d}T03:59:59.999Z`;

  // 2. Row volume for the top company (payload-size evidence)
  for (const [label, r] of Object.entries({ range30, rangeYear })) {
    const inv = await client.query(
      `SELECT count(*) AS invoices FROM "Sale"
       WHERE company_id=$1 AND kind='invoice' AND is_deleted=false
         AND sale_date >= $2 AND sale_date <= $3`,
      [companyId, qFrom(r.from), qTo(r.to)],
    );
    const items = await client.query(
      `SELECT count(*) AS items FROM "SaleItem" si
       JOIN "Sale" s ON s.id = si.sale_id
       WHERE s.company_id=$1 AND s.kind='invoice' AND s.is_deleted=false
         AND s.sale_date >= $2 AND s.sale_date <= $3`,
      [companyId, qFrom(r.from), qTo(r.to)],
    );
    const refunds = await client.query(
      `SELECT count(*) AS refunds FROM "Sale"
       WHERE company_id=$1 AND kind='refund' AND is_deleted=false
         AND sale_date >= $2 AND sale_date <= $3`,
      [companyId, qFrom(r.from), qTo(r.to)],
    );
    const deleted = await client.query(
      `SELECT count(*) AS deleted FROM "Sale"
       WHERE company_id=$1 AND kind='invoice' AND is_deleted=true
         AND deleted_at >= $2 AND deleted_at <= $3`,
      [companyId, qFrom(r.from), qTo(r.to)],
    );
    const movements = await client.query(
      `SELECT count(*) AS movements FROM "CashMovement"
       WHERE company_id=$1 AND created_at >= $2 AND created_at <= $3`,
      [companyId, qFrom(r.from), qTo(r.to)],
    );
    console.log(`[${label}] invoices=${inv.rows[0].invoices} items=${items.rows[0].items} refunds=${refunds.rows[0].refunds} deletedInRange=${deleted.rows[0].deleted} cashMovements=${movements.rows[0].movements}`);
  }

  // 3. EXPLAIN (estimate only) for each report query, last 30 days
  const r = range30;
  const queries = {
    'SALE_LIST (findMany invoice+items+product)': `
      EXPLAIN (FORMAT JSON)
      SELECT s.*, c.id AS c_id, c.nombre AS c_nombre,
             si.*, p.categoria AS p_categoria
      FROM "Sale" s
      LEFT JOIN "Client" c ON c.id = s.customer_id
      LEFT JOIN "SaleItem" si ON si.sale_id = s.id
      LEFT JOIN "Product" p ON p.id = si.product_id
      WHERE s.company_id=$1 AND s.kind='invoice' AND s.is_deleted=false
        AND s.sale_date >= $2 AND s.sale_date <= $3
      ORDER BY s.sale_date ASC`,
    'RETURNED_LIST (deletedAt range)': `
      EXPLAIN (FORMAT JSON)
      SELECT s.*, si.*, p.categoria AS p_categoria
      FROM "Sale" s
      LEFT JOIN "SaleItem" si ON si.sale_id = s.id
      LEFT JOIN "Product" p ON p.id = si.product_id
      WHERE s.company_id=$1 AND s.kind='invoice' AND s.is_deleted=true
        AND s.deleted_at >= $2 AND s.deleted_at <= $3
      ORDER BY s.deleted_at ASC`,
    'REFUND_LIST (kind=refund)': `
      EXPLAIN (FORMAT JSON)
      SELECT s.*, si.*, p.categoria AS p_categoria
      FROM "Sale" s
      LEFT JOIN "SaleItem" si ON si.sale_id = s.id
      LEFT JOIN "Product" p ON p.id = si.product_id
      WHERE s.company_id=$1 AND s.kind='refund' AND s.is_deleted=false
        AND s.sale_date >= $2 AND s.sale_date <= $3
      ORDER BY s.sale_date ASC`,
    'CASH_MOVEMENTS': `
      EXPLAIN (FORMAT JSON)
      SELECT * FROM "CashMovement"
      WHERE company_id=$1 AND created_at >= $2 AND created_at <= $3`,
    'PRODUCTS (catalog)': `
      EXPLAIN (FORMAT JSON)
      SELECT id, nombre, categoria, costo, precio, stock FROM "Product"
      WHERE company_id=$1`,
  };

  for (const [label, sql] of Object.entries(queries)) {
    try {
      const res = await client.query(sql, [companyId, qFrom(r.from), qTo(r.to)]);
      const plan = res.rows[0]['QUERY PLAN'];
      console.log(`\n=== ${label} ===`);
      const parsed = JSON.parse(plan[0]?.Plan ? JSON.stringify(plan) : '[]');
      if (Array.isArray(parsed)) {
        const top = parsed[0]?.Plan;
        console.log(JSON.stringify(top, null, 1).slice(0, 1800));
      } else {
        console.log(plan.join('\n').slice(0, 1500));
      }
    } catch (err) {
      console.log(`\n=== ${label} === ERROR: ${err.message}`);
    }
  }

  // 4. EXPLAIN ANALYZE on lightweight aggregates (real execution time)
  const analyzeQueries = {
    'COUNT invoices 30d': `
      EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      SELECT count(*) FROM "Sale"
      WHERE company_id=$1 AND kind='invoice' AND is_deleted=false
        AND sale_date >= $2 AND sale_date <= $3`,
    'SUM summary (total_sold/cost/profit) 30d': `
      EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      SELECT sum(total_sold), sum(total_cost), sum(total_profit), sum(commission_amount), count(*)
      FROM "Sale"
      WHERE company_id=$1 AND is_deleted=false
        AND sale_date >= $2 AND sale_date <= $3`,
    'COUNT cash movements 30d': `
      EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      SELECT count(*) FROM "CashMovement"
      WHERE company_id=$1 AND created_at >= $2 AND created_at <= $3`,
  };
  for (const [label, sql] of Object.entries(analyzeQueries)) {
    try {
      const t0 = Date.now();
      const res = await client.query(sql, [companyId, qFrom(r.from), qTo(r.to)]);
      const wall = Date.now() - t0;
      const parsed = JSON.parse(res.rows[0]['QUERY PLAN'][0]);
      const p = parsed.Plan;
      const analyze = parsed['Execution Time'] != null
        ? { wallMs: wall, execMs: parsed['Execution Time'], rows: p['Actual Rows'], loops: p['Actual Loops'] }
        : { wallMs: wall };
      console.log(`\n[ANALYZE] ${label}: ${JSON.stringify(analyze)}`);
      console.log('  plan:', (p['Node Type'] + (p['Index Name'] ? ` (idx ${p['Index Name']})` : '')));
    } catch (err) {
      console.log(`\n[ANALYZE] ${label}: ERROR ${err.message}`);
    }
  }

  await client.end();
  console.log('\nDone (read-only).');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
