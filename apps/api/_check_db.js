// READ-ONLY: confirm companies in the .env DB + list accessible databases
require('dotenv').config();
const { Client } = require('pg');

async function main() {
  const pg = new Client({ connectionString: process.env.DATABASE_URL });
  await pg.connect();
  const companies = await pg.query(`SELECT id, name, slug FROM companies ORDER BY created_at`);
  console.log('COMPANIES in .env DB:', JSON.stringify(companies.rows));
  try {
    const dbs = await pg.query(`SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname`);
    console.log('ACCESSIBLE DATABASES:', JSON.stringify(dbs.rows.map((r) => r.datname)));
  } catch (e) {
    console.log('cannot list databases:', e.message.split('\n')[0]);
  }
  // does company 165e3fca exist here?
  const c = await pg.query(`SELECT count(*)::int AS n FROM companies WHERE id = '165e3fca-6225-479b-8805-d2205f10536c'::uuid`);
  console.log('company 165e3fca present in .env DB:', c.rows[0].n > 0);
  await pg.end();
}
main().catch((e) => { console.error('FATAL', e.message); process.exit(1); });
