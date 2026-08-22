// READ-ONLY: find which database contains company 165e3fca and its current name
require('dotenv').config();
const { Client } = require('pg');

const COMPANY = '165e3fca-6225-479b-8805-d2205f10536c';
const base = process.env.DATABASE_URL; // postgres://user:pass@host:5432/daleventa_pos?sslmode=disable

// parse base url to reuse user:pass@host:port
const m = base.match(/^postgres(?:ql)?:\/\/([^@]+)@([^:\/]+)(?::(\d+))?\/([^?]+)/);
if (!m) { console.error('cannot parse DATABASE_URL'); process.exit(1); }
const auth = m[1]; // user:pass
const host = m[2];
const port = m[3] || '5432';

const candidates = [
  'daleventa_pos','fullpos_sistema','fullpos_proyecto','fullpos_staging',
  'fulltechapp_sistem','fulltechrelease','fulltechwed','fulltech_tienda','fulltechcatalog',
];

async function tryDb(db) {
  const url = `postgres://${auth}@${host}:${port}/${db}?sslmode=disable`;
  const c = new Client({ connectionString: url });
  try {
    await c.connect();
    const r = await c.query(`SELECT id, name, slug, updated_at FROM companies WHERE id = $1::uuid`, [COMPANY]);
    if (r.rows.length > 0) {
      console.log(`DB '${db}': COMPANY FOUND -> ${JSON.stringify(r.rows[0])}`);
    } else {
      const n = await c.query(`SELECT count(*)::int AS n FROM companies`);
      console.log(`DB '${db}': company not found (companies=${n.rows[0].n})`);
    }
    await c.end();
    return r.rows.length > 0;
  } catch (e) {
    console.log(`DB '${db}': ERROR (${e.message.split('\n')[0]})`);
    return false;
  }
}

(async () => {
  for (const db of candidates) {
    const found = await tryDb(db);
    if (found) break;
  }
})();
