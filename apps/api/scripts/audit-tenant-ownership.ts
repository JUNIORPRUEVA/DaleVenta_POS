import { PrismaClient } from '@prisma/client';
import * as fs from 'node:fs';
import * as path from 'node:path';

type TableAudit = {
  table: string;
  totalRows: number;
  rowsWithCompany: number;
  rowsMissingCompany: number;
  invalidCompanyReferences: number;
  ambiguousOwnership: number;
  parentMismatch: number;
  safeToEnforce: boolean;
  repairPreviewSql: string[];
};

const prisma = new PrismaClient();
const apply = process.argv.includes('--apply');
const root = path.resolve(__dirname, '..');
const docsDir = path.join(root, 'docs');

const parentRules = [
  { table: 'sale_items', tenantColumn: 'company_id', parentColumn: 'sale_id', parentTable: 'sales', parentPk: 'id' },
  { table: 'purchase_order_items', tenantColumn: 'company_id', parentColumn: 'purchase_order_id', parentTable: 'purchase_orders', parentPk: 'id' },
  { table: 'purchase_receipt_items', tenantColumn: 'company_id', parentColumn: 'purchase_receipt_id', parentTable: 'purchase_receipts', parentPk: 'id' },
  { table: 'cotizacion_items', tenantColumn: 'company_id', parentColumn: 'cotizacion_id', parentTable: 'Cotizacion', parentPk: 'id' },
  { table: 'close_transfers', tenantColumn: 'company_id', parentColumn: 'close_id', parentTable: 'closes', parentPk: 'id' },
];

async function tableExists(table: string) {
  const rows = await prisma.$queryRaw<Array<{ exists: boolean }>>`
    SELECT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = ${table}
    ) AS "exists"
  `;
  return rows[0]?.exists === true;
}

async function columnExists(table: string, column: string) {
  const rows = await prisma.$queryRaw<Array<{ exists: boolean }>>`
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = ${table} AND column_name = ${column}
    ) AS "exists"
  `;
  return rows[0]?.exists === true;
}

async function scalar(sql: string, params: unknown[] = []) {
  const rows = await prisma.$queryRawUnsafe<Array<{ value: bigint | number }>>(sql, ...params);
  return Number(rows[0]?.value ?? 0);
}

async function main() {
  const tenantTables = await prisma.$queryRaw<Array<{ table_name: string }>>`
    SELECT table_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'company_id'
    ORDER BY table_name
  `;

  const audits: TableAudit[] = [];
  for (const { table_name: table } of tenantTables) {
    if (!/^[a-zA-Z0-9_]+$/.test(table)) throw new Error(`Unsafe table name: ${table}`);
    const totalRows = await scalar(`SELECT COUNT(*)::int AS value FROM "${table}"`);
    const rowsWithCompany = await scalar(`SELECT COUNT(*)::int AS value FROM "${table}" WHERE company_id IS NOT NULL`);
    const rowsMissingCompany = totalRows - rowsWithCompany;
    const invalidCompanyReferences = table === 'companies'
      ? 0
      : await scalar(`SELECT COUNT(*)::int AS value FROM "${table}" t LEFT JOIN companies c ON c.id = t.company_id WHERE t.company_id IS NOT NULL AND c.id IS NULL`);

    let ambiguousOwnership = 0;
    let parentMismatch = 0;
    let recoverableMissingCompany = 0;
    const repairPreviewSql: string[] = [];

    for (const rule of parentRules.filter((item) => item.table === table)) {
      if (!(await tableExists(rule.parentTable))) continue;
      if (!(await columnExists(rule.table, rule.tenantColumn))) continue;
      if (!(await columnExists(rule.parentTable, 'company_id'))) continue;
      parentMismatch += await scalar(
        `SELECT COUNT(*)::int AS value
         FROM "${rule.table}" child
         JOIN "${rule.parentTable}" parent ON parent."${rule.parentPk}" = child."${rule.parentColumn}"
         WHERE child.company_id IS NOT NULL
           AND parent.company_id IS NOT NULL
           AND child.company_id <> parent.company_id`,
      );
      const missingRecoverable = await scalar(
        `SELECT COUNT(*)::int AS value
         FROM "${rule.table}" child
         JOIN "${rule.parentTable}" parent ON parent."${rule.parentPk}" = child."${rule.parentColumn}"
         WHERE child.company_id IS NULL AND parent.company_id IS NOT NULL`,
      );
      if (missingRecoverable > 0) {
        recoverableMissingCompany += missingRecoverable;
        repairPreviewSql.push(
          `UPDATE "${rule.table}" child SET company_id = parent.company_id FROM "${rule.parentTable}" parent WHERE parent."${rule.parentPk}" = child."${rule.parentColumn}" AND child.company_id IS NULL AND parent.company_id IS NOT NULL;`,
        );
        if (apply) {
          await prisma.$executeRawUnsafe(
            `UPDATE "${rule.table}" child SET company_id = parent.company_id FROM "${rule.parentTable}" parent WHERE parent."${rule.parentPk}" = child."${rule.parentColumn}" AND child.company_id IS NULL AND parent.company_id IS NOT NULL`,
          );
        }
      }
    }

    ambiguousOwnership += Math.max(0, rowsMissingCompany - recoverableMissingCompany);
    audits.push({
      table,
      totalRows,
      rowsWithCompany,
      rowsMissingCompany,
      invalidCompanyReferences,
      ambiguousOwnership,
      parentMismatch,
      safeToEnforce: rowsMissingCompany === 0 && invalidCompanyReferences === 0 && ambiguousOwnership === 0 && parentMismatch === 0,
      repairPreviewSql,
    });
  }

  fs.mkdirSync(docsDir, { recursive: true });
  fs.writeFileSync(path.join(docsDir, 'tenant-backfill-report.json'), JSON.stringify({ generatedAt: new Date().toISOString(), apply, tables: audits }, null, 2));
  const md = [
    '# Tenant Backfill Report',
    '',
    `Generated at: ${new Date().toISOString()}`,
    `Mode: ${apply ? 'apply' : 'dry-run'}`,
    '',
    '| Table | Total | With Company | Missing | Invalid FK | Ambiguous | Parent Mismatch | Safe |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |',
    ...audits.map((row) => `| ${row.table} | ${row.totalRows} | ${row.rowsWithCompany} | ${row.rowsMissingCompany} | ${row.invalidCompanyReferences} | ${row.ambiguousOwnership} | ${row.parentMismatch} | ${row.safeToEnforce} |`),
    '',
    '## SQL Repair Preview',
    '',
    ...audits.flatMap((row) => row.repairPreviewSql.map((sql) => `- ${sql}`)),
    '',
  ].join('\n');
  fs.writeFileSync(path.join(docsDir, 'TENANT_BACKFILL_REPORT.md'), md);

  const unsafe = audits.filter((row) => !row.safeToEnforce);
  if (unsafe.length) {
    console.error(`Tenant ownership audit found ${unsafe.length} table(s) that are not safe to enforce.`);
    process.exitCode = 2;
  } else {
    console.log('Tenant ownership audit passed.');
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
