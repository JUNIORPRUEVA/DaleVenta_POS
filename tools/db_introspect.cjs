const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const env = fs.readFileSync(path.join(__dirname, '..', 'apps', 'api', '.env'), 'utf8');
const url = env.match(/^DATABASE_URL\s*=\s*(.+)$/m)[1].trim();

(async () => {
  const c = new Client({ connectionString: url });
  await c.connect();
  const cols = await c.query(
    "SELECT column_name, data_type FROM information_schema.columns WHERE table_name='Sale' ORDER BY ordinal_position",
  );
  console.log('Sale columns:', cols.rows.map((r) => r.column_name).join(', '));
  const cnt = await c.query('SELECT count(*) AS n FROM "Sale"');
  console.log('Sale rows:', cnt.rows[0].n);
  const kinds = await c.query('SELECT kind, count(*) AS n FROM "Sale" GROUP BY kind');
  console.log('kinds:', JSON.stringify(kinds.rows));
  const comps = await c.query(
    'SELECT company_id, count(*) AS n FROM "Sale" GROUP BY company_id ORDER BY n DESC LIMIT 5',
  );
  console.log('companies:', JSON.stringify(comps.rows));
  await c.end();
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
