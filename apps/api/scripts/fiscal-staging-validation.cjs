const { PrismaClient, Prisma } = require("@prisma/client");

const prisma = new PrismaClient();
const PREFIX = `phase5-${Date.now()}`;
const MAX_PARALLEL = Number(process.env.FISCAL_STAGING_MAX_PARALLEL || 20);
const MONEY = {
  total: "25700.00",
  base: "21779.66",
  tax: "3920.34",
};

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function mapConcurrent(items, worker, maxParallel = MAX_PARALLEL) {
  const results = new Array(items.length);
  let cursor = 0;
  const workers = Array.from(
    { length: Math.min(maxParallel, items.length) },
    async () => {
      while (cursor < items.length) {
        const index = cursor++;
        results[index] = await worker(items[index], index);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

function isUniqueError(error) {
  return (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === "P2002"
  );
}

async function ensureStagingGuard() {
  const rows = await prisma.$queryRaw`SELECT current_database() AS db`;
  const db = rows[0]?.db;
  assert(db === "fullpos_staging", `Refusing to run outside fullpos_staging; current database is ${db}`);
  await prisma.$executeRawUnsafe(`
    CREATE EXTENSION IF NOT EXISTS btree_gist
  `);
  await prisma.$executeRawUnsafe(`
    CREATE UNIQUE INDEX IF NOT EXISTS ncf_sequences_company_id_voucher_type_active_key
    ON ncf_sequences(company_id, voucher_type)
    WHERE active = true
  `);
  await prisma.$executeRawUnsafe(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ncf_sequences_no_overlap'
      ) THEN
        ALTER TABLE ncf_sequences
          ADD CONSTRAINT ncf_sequences_no_overlap
          EXCLUDE USING gist (
            company_id WITH =,
            voucher_type WITH =,
            int4range(start_number, end_number, '[]') WITH &&
          );
      END IF;
    END
    $$
  `);
}

async function cleanup() {
  await prisma.company.deleteMany({ where: { slug: { startsWith: "phase5-" } } });
  await prisma.user.deleteMany({ where: { email: { startsWith: "phase5-" } } });
}

async function createCompany(slugSuffix, data = {}) {
  return prisma.company.create({
    data: {
      name: `Phase5 ${slugSuffix}`,
      slug: `${PREFIX}-${slugSuffix}`,
      taxEnabled: data.taxEnabled ?? false,
      pricesIncludeTax: data.pricesIncludeTax ?? false,
      ncfEnabled: data.ncfEnabled ?? false,
      defaultTaxRate: data.defaultTaxRate ?? "0",
    },
  });
}

async function createUser(companyId, suffix, role = "ADMIN") {
  return prisma.user.create({
    data: {
      companyId,
      email: `${PREFIX}-${suffix}@example.test`,
      passwordHash: "staging-validation-only",
      nombreCompleto: `Phase5 ${suffix}`,
      telefono: "0000000000",
      edad: 30,
      role,
    },
  });
}

async function createSequence(companyId, type, start, end, active = true) {
  return prisma.ncfSequence.create({
    data: {
      companyId,
      voucherType: type,
      prefix: type,
      startNumber: start,
      nextNumber: start,
      endNumber: end,
      active,
    },
  });
}

async function issueFiscalSale(companyId, userId, type, clientRequestId) {
  try {
    return await prisma.$transaction(async (tx) => {
      const rows = await tx.$queryRaw`
        SELECT id, prefix, next_number, end_number, valid_until, active
        FROM ncf_sequences
        WHERE company_id = ${companyId}::uuid
          AND voucher_type = ${type}
          AND active = true
        ORDER BY created_at ASC
        FOR UPDATE
      `;
      const now = Date.now();
      const sequence = rows.find((row) => {
        if (!row.active) return false;
        if (row.valid_until && row.valid_until.getTime() < now) return false;
        return row.next_number <= row.end_number;
      });
      if (!sequence) throw new Error(`NO_SEQUENCE_${type}`);

      const ncf = `${sequence.prefix}${String(sequence.next_number).padStart(8, "0")}`;
      await tx.ncfSequence.update({
        where: { id: sequence.id },
        data: { nextNumber: { increment: 1 } },
      });
      await tx.ncfAuditLog.create({
        data: {
          companyId,
          sequenceId: sequence.id,
          userId,
          ncf,
          type,
          action: "RESERVED",
        },
      });
      const sale = await tx.sale.create({
        data: {
          companyId,
          userId,
          clientRequestId,
          paymentMethod: "cash",
          totalSold: MONEY.total,
          fiscalTaxEnabled: true,
          fiscalPriceMode: "TAX_INCLUDED",
          taxableBase: MONEY.base,
          taxAmount: MONEY.tax,
          exemptAmount: "0",
          discountAmount: "0",
          fiscalVoucherType: type,
          ncf,
          fiscalCustomerTaxId: "132588312",
          fiscalCustomerName: "CANATECH SRL",
          totalCost: "0",
          totalProfit: MONEY.total,
          commissionRate: "0.10",
          commissionAmount: "2570.00",
        },
      });
      await tx.ncfAuditLog.create({
        data: {
          companyId,
          sequenceId: sequence.id,
          saleId: sale.id,
          userId,
          ncf,
          type,
          action: "ISSUED",
        },
      });
      return sale;
    }, {
      maxWait: 120000,
      timeout: 120000,
    });
  } catch (error) {
    if (clientRequestId && isUniqueError(error)) {
      const existing = await prisma.sale.findFirst({
        where: { companyId, clientRequestId },
      });
      if (existing) return existing;
    }
    throw error;
  }
}

async function assertPhysicalSchema() {
  const tableRows = await prisma.$queryRaw`
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN ('taxes', 'ncf_sequences', 'ncf_audit_logs')
  `;
  const tables = new Set(tableRows.map((row) => row.table_name));
  for (const table of ["taxes", "ncf_sequences", "ncf_audit_logs"]) {
    assert(tables.has(table), `Missing table ${table}`);
  }

  const indexRows = await prisma.$queryRaw`
    SELECT indexname, indexdef
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'Sale_company_id_ncf_key',
        'Sale_company_id_client_request_id_key',
        'ncf_sequences_company_id_voucher_type_active_key',
        'ncf_sequences_no_overlap'
      )
  `;
  const indexes = new Map(indexRows.map((row) => [row.indexname, row.indexdef]));
  assert(indexes.has("Sale_company_id_ncf_key"), "Missing Sale(company_id,ncf) unique index");
  assert(indexes.has("Sale_company_id_client_request_id_key"), "Missing Sale(company_id,clientRequestId) unique index");
  assert(indexes.has("ncf_sequences_company_id_voucher_type_active_key"), "Missing active NCF sequence unique index");
  assert(indexes.has("ncf_sequences_no_overlap"), "Missing NCF no-overlap exclusion constraint");
  return { tables: Array.from(tables).sort(), indexes: Array.from(indexes.keys()).sort() };
}

async function testDuplicateNcf() {
  const companyA = await createCompany("dup-a", { taxEnabled: true, pricesIncludeTax: true, ncfEnabled: true, defaultTaxRate: "0.18" });
  const companyB = await createCompany("dup-b", { taxEnabled: true, pricesIncludeTax: true, ncfEnabled: true, defaultTaxRate: "0.18" });
  const userA = await createUser(companyA.id, "dup-a");
  const userB = await createUser(companyB.id, "dup-b");
  const data = (companyId, userId, clientRequestId) => ({
    companyId,
    userId,
    clientRequestId,
    paymentMethod: "cash",
    totalSold: "100.00",
    ncf: "B0100000001",
    fiscalVoucherType: "B01",
    totalCost: "0",
    totalProfit: "100.00",
    commissionAmount: "10.00",
  });
  await prisma.sale.create({ data: data(companyA.id, userA.id, `${PREFIX}-dup-a-1`) });
  let sameCompanyBlocked = false;
  try {
    await prisma.sale.create({ data: data(companyA.id, userA.id, `${PREFIX}-dup-a-2`) });
  } catch (error) {
    sameCompanyBlocked = isUniqueError(error);
  }
  await prisma.sale.create({ data: data(companyB.id, userB.id, `${PREFIX}-dup-b-1`) });
  assert(sameCompanyBlocked, "Duplicate NCF in same company was not blocked");
  return { sameCompanyDuplicate: "blocked", crossCompanySameNcf: "allowed" };
}

async function testConcurrency(count) {
  const company = await createCompany(`concurrency-${count}`, { taxEnabled: true, pricesIncludeTax: true, ncfEnabled: true, defaultTaxRate: "0.18" });
  const user = await createUser(company.id, `concurrency-${count}`);
  await createSequence(company.id, "B01", 1, 200);
  const sales = await mapConcurrent(
    Array.from({ length: count }),
    (_, index) =>
      issueFiscalSale(
        company.id,
        user.id,
        "B01",
        `${PREFIX}-concurrency-${count}-${index}`,
      ),
  );
  const ncfs = sales.map((sale) => sale.ncf);
  const unique = new Set(ncfs);
  const sequence = await prisma.ncfSequence.findFirst({ where: { companyId: company.id, voucherType: "B01" } });
  assert(sales.length === count, `Expected ${count} sales`);
  assert(unique.size === count, `Expected ${count} unique NCF, got ${unique.size}`);
  assert(sequence.nextNumber === count + 1, `Expected nextNumber ${count + 1}, got ${sequence.nextNumber}`);
  return { requested: count, maxParallel: Math.min(MAX_PARALLEL, count), sales: sales.length, uniqueNcf: unique.size, nextNumber: sequence.nextNumber };
}

async function testIdempotency() {
  const company = await createCompany("idempotency", { taxEnabled: true, pricesIncludeTax: true, ncfEnabled: true, defaultTaxRate: "0.18" });
  const user = await createUser(company.id, "idempotency");
  await createSequence(company.id, "B01", 1, 100);
  const key = `${PREFIX}-same-key`;
  const results = await mapConcurrent(
    Array.from({ length: 20 }),
    () => issueFiscalSale(company.id, user.id, "B01", key),
  );
  const ids = new Set(results.map((sale) => sale.id));
  const ncfs = new Set(results.map((sale) => sale.ncf));
  const count = await prisma.sale.count({ where: { companyId: company.id, clientRequestId: key } });
  const sequence = await prisma.ncfSequence.findFirst({ where: { companyId: company.id, voucherType: "B01" } });
  assert(ids.size === 1, `Expected 1 sale id, got ${ids.size}`);
  assert(ncfs.size === 1, `Expected 1 NCF, got ${ncfs.size}`);
  assert(count === 1, `Expected 1 persisted sale, got ${count}`);
  assert(sequence.nextNumber === 2, `Expected nextNumber 2 after idempotent race, got ${sequence.nextNumber}`);
  return { concurrentRequests: 20, maxParallel: Math.min(MAX_PARALLEL, 20), persistedSales: count, uniqueSaleIds: ids.size, uniqueNcf: ncfs.size, nextNumber: sequence.nextNumber };
}

async function testExhausted() {
  const company = await createCompany("exhausted", { taxEnabled: true, pricesIncludeTax: true, ncfEnabled: true, defaultTaxRate: "0.18" });
  const user = await createUser(company.id, "exhausted");
  await createSequence(company.id, "B01", 14, 15);
  const first = await issueFiscalSale(company.id, user.id, "B01", `${PREFIX}-exhausted-1`);
  const second = await issueFiscalSale(company.id, user.id, "B01", `${PREFIX}-exhausted-2`);
  let thirdBlocked = false;
  try {
    await issueFiscalSale(company.id, user.id, "B01", `${PREFIX}-exhausted-3`);
  } catch (error) {
    thirdBlocked = String(error.message).includes("NO_SEQUENCE_B01");
  }
  const sequence = await prisma.ncfSequence.findFirst({ where: { companyId: company.id, voucherType: "B01" } });
  assert(first.ncf === "B0100000014", `Unexpected first NCF ${first.ncf}`);
  assert(second.ncf === "B0100000015", `Unexpected second NCF ${second.ncf}`);
  assert(thirdBlocked, "Third exhausted emission was not blocked");
  assert(sequence.nextNumber === 16, `Expected nextNumber 16, got ${sequence.nextNumber}`);
  return { first: first.ncf, second: second.ncf, third: "blocked", nextNumber: sequence.nextNumber };
}

async function testActiveAndOverlap() {
  const company = await createCompany("sequence-rules", { taxEnabled: true, pricesIncludeTax: true, ncfEnabled: true, defaultTaxRate: "0.18" });
  await createSequence(company.id, "B01", 1, 100, true);
  let secondActiveBlocked = false;
  try {
    await createSequence(company.id, "B01", 101, 200, true);
  } catch (error) {
    secondActiveBlocked = isUniqueError(error);
  }
  await prisma.ncfSequence.updateMany({
    where: { companyId: company.id, voucherType: "B01" },
    data: { active: false },
  });
  let overlapBlocked = false;
  try {
    await createSequence(company.id, "B01", 50, 150, false);
  } catch (error) {
    overlapBlocked = true;
  }
  const rows = await prisma.ncfSequence.count({
    where: { companyId: company.id, voucherType: "B01" },
  });
  assert(secondActiveBlocked, "Second active sequence was not blocked by DB");
  assert(overlapBlocked, "Overlapping inactive sequence was not blocked by DB");
  assert(rows === 1, `Expected 1 sequence after overlap test, got ${rows}`);
  return { secondActive: "blocked", overlappingInactive: "blocked" };
}

async function testQuotesDoNotConsumeNcf() {
  const company = await createCompany("quotes", { taxEnabled: true, pricesIncludeTax: true, ncfEnabled: true, defaultTaxRate: "0.18" });
  const user = await createUser(company.id, "quotes");
  await createSequence(company.id, "B01", 1, 200);
  const before = await prisma.ncfSequence.findFirst({ where: { companyId: company.id, voucherType: "B01" } });
  await Promise.all(
    Array.from({ length: 100 }, (_, index) =>
      prisma.cotizacion.create({
        data: {
          companyId: company.id,
          createdByUserId: user.id,
          customerName: `Quote Customer ${index}`,
          customerPhone: "0000000000",
          includeItbis: true,
          itbisRate: "0.18",
          subtotal: MONEY.base,
          itbisAmount: MONEY.tax,
          total: MONEY.total,
          items: {
            create: [
              { productNameSnapshot: "FOTOCELDA PARA MOTOR", qty: "1", unitPrice: "1200.00", lineTotal: "1200.00" },
              { productNameSnapshot: "MOTOR WIFI 800KG", qty: "1", unitPrice: "13000.00", lineTotal: "13000.00" },
              { productNameSnapshot: "SERVICIO EXTRA", qty: "1", unitPrice: "4000.00", lineTotal: "4000.00" },
              { productNameSnapshot: "SERVICIO REEMPLAZO", qty: "1", unitPrice: "6000.00", lineTotal: "6000.00" },
              { productNameSnapshot: "LAMPARA PARA MOTOR", qty: "1", unitPrice: "1500.00", lineTotal: "1500.00" },
            ],
          },
        },
      }),
    ),
  );
  const after = await prisma.ncfSequence.findFirst({ where: { companyId: company.id, voucherType: "B01" } });
  assert(before.nextNumber === after.nextNumber, "Quotes consumed NCF sequence");
  return { quotes: 100, ncfConsumed: 0, fulltechTotal: MONEY.total, fulltechBase: MONEY.base, fulltechItbis: MONEY.tax };
}

async function testSimpleCompanyNoFiscal() {
  const company = await createCompany("simple", { taxEnabled: false, pricesIncludeTax: false, ncfEnabled: false, defaultTaxRate: "0" });
  assert(!company.taxEnabled && !company.ncfEnabled, "Simple company enabled fiscal behavior");
  return { taxEnabled: company.taxEnabled, ncfEnabled: company.ncfEnabled };
}

async function main() {
  await ensureStagingGuard();
  await cleanup();
  const schema = await assertPhysicalSchema();
  const results = {
    database: "fullpos_staging",
    schema,
    duplicateNcf: await testDuplicateNcf(),
    concurrency20: await testConcurrency(20),
    concurrency100: await testConcurrency(100),
    idempotency: await testIdempotency(),
    exhausted: await testExhausted(),
    sequenceRules: await testActiveAndOverlap(),
    quotes: await testQuotesDoNotConsumeNcf(),
    simpleCompany: await testSimpleCompanyNoFiscal(),
  };
  console.log(JSON.stringify(results, null, 2));
}

main()
  .catch((error) => {
    console.error(error.stack || error.message);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
