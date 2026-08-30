const { Prisma, PrismaClient, Role, CompanyMemberRole, CompanyMemberStatus } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

const globalUnits = [
  { id: 'UNIT', code: 'UNIT', name: 'Unidad', symbol: 'u', category: 'COUNT', allowDecimals: false, precision: 0 },
  { id: 'YARD', code: 'YARD', name: 'Yarda', symbol: 'yd', category: 'LENGTH', allowDecimals: true, precision: 3 },
  { id: 'METER', code: 'METER', name: 'Metro', symbol: 'm', category: 'LENGTH', allowDecimals: true, precision: 3 },
  { id: 'FOOT', code: 'FOOT', name: 'Pie', symbol: 'ft', category: 'LENGTH', allowDecimals: true, precision: 3 },
  { id: 'INCH', code: 'INCH', name: 'Pulgada', symbol: 'in', category: 'LENGTH', allowDecimals: true, precision: 3 },
  { id: 'POUND', code: 'POUND', name: 'Libra', symbol: 'lb', category: 'WEIGHT', allowDecimals: true, precision: 3 },
  { id: 'KILOGRAM', code: 'KILOGRAM', name: 'Kilogramo', symbol: 'kg', category: 'WEIGHT', allowDecimals: true, precision: 3 },
  { id: 'GRAM', code: 'GRAM', name: 'Gramo', symbol: 'g', category: 'WEIGHT', allowDecimals: true, precision: 3 },
  { id: 'OUNCE', code: 'OUNCE', name: 'Onza', symbol: 'oz', category: 'WEIGHT', allowDecimals: true, precision: 3 },
  { id: 'LITER', code: 'LITER', name: 'Litro', symbol: 'L', category: 'VOLUME', allowDecimals: true, precision: 3 },
  { id: 'MILLILITER', code: 'MILLILITER', name: 'Mililitro', symbol: 'ml', category: 'VOLUME', allowDecimals: true, precision: 3 },
  { id: 'GALLON', code: 'GALLON', name: 'Galon', symbol: 'gal', category: 'VOLUME', allowDecimals: true, precision: 3 },
];

async function upsertGlobalUnits() {
  if (!prisma.unitOfMeasure?.upsert) return { skipped: true, count: 0 };
  for (const unit of globalUnits) {
    await prisma.unitOfMeasure.upsert({
      where: { id: unit.id },
      update: {},
      create: unit,
    });
  }
  return { skipped: false, count: globalUnits.length };
}

function isMissingUserTable(error) {
  if (error && typeof error === 'object') {
    const code = typeof error.code === 'string' ? error.code : '';
    const message = typeof error.message === 'string' ? error.message : '';
    return code === 'P2021' || message.includes('table `public.User` does not exist');
  }
  return false;
}

async function upsertDefaultCompany() {
  return prisma.company.upsert({
    where: { slug: 'daleventa-pos' },
    // SAFETY (2026-08-22, forensic CASO B): the `update` branch must NEVER
    // overwrite tenant-owned fields on an EXISTING company. Doing so silently
    // reverted the real company name to the product default ("FullPOS Cloud")
    // with NO audit event on every seed run, and would also clobber
    // Appyra-managed license data (status/plan/maxUsers). Only `create` seeds
    // initial/default values for a brand-new company; `update` is a no-op so
    // production tenants (name, status, plan, maxUsers, limits) are preserved.
    update: {},
    create: {
      name: 'FullPOS Cloud',
      slug: 'daleventa-pos',
      status: 'ACTIVE',
      plan: 'ENTERPRISE',
      maxUsers: 1000,
    },
  });
}

async function upsertAppConfig(company) {
  return prisma.appConfig.upsert({
    where: { id: 'global' },
    // SAFETY: never overwrite an EXISTING tenant AppConfig (companyName, rnc,
    // phone, address, logo, businessHours, description, ...). Only `create`
    // seeds the initial config for a brand-new setup.
    update: {},
    create: {
      id: 'global',
      companyId: company.id,
      companyName: company.name,
    },
  });
}

async function upsertUser({ companyId, email, password, nombreCompleto, telefono, role }) {
  const passwordHash = await bcrypt.hash(password, 10);
  try {
    const user = await prisma.user.upsert({
      where: { email },
      // SAFETY: never overwrite an EXISTING user's credentials or data. The
      // `update` branch must NOT reset passwordHash (would change the admin
      // password on every seed run), nor role/companyId/nombreCompleto/
      // telefono/blocked. Only `create` bootstraps a new admin.
      update: {},
      create: {
        companyId,
        email,
        passwordHash,
        nombreCompleto,
        telefono,
        edad: 0,
        role,
        blocked: false,
        tieneHijos: false,
        estaCasado: false,
        casaPropia: false,
        vehiculo: false,
        licenciaConducir: false,
      },
    });
    return { id: user.id, email: user.email, fallback: false };
  } catch (error) {
    if (!isMissingUserTable(error)) throw error;

    let rows;
    try {
      rows = await prisma.$queryRaw(Prisma.sql`
        INSERT INTO users (email, "passwordHash", role)
        VALUES (${email}, ${passwordHash}, CAST(${role} AS "Role"))
        ON CONFLICT (email)
        -- SAFETY: only enforce the ADMIN role on an existing legacy user;
        -- never reset their passwordHash on every seed run.
        DO UPDATE SET role = EXCLUDED.role
        RETURNING id, email
      `);
    } catch {
      rows = await prisma.$queryRaw(Prisma.sql`
        INSERT INTO users (email, "passwordHash", role)
        VALUES (${email}, ${passwordHash}, ${role})
        ON CONFLICT (email)
        -- SAFETY: only enforce the ADMIN role on an existing legacy user;
        -- never reset their passwordHash on every seed run.
        DO UPDATE SET role = EXCLUDED.role
        RETURNING id, email
      `);
    }

    const row = rows[0];
    if (!row) throw new Error('No se pudo upsert el usuario admin en tabla users');
    return { id: row.id, email: row.email, fallback: true };
  }
}

function companyMemberRoleFromLegacyRole(role) {
  if (role === Role.ADMIN) return CompanyMemberRole?.OWNER ?? 'OWNER';
  if (role === Role.ASISTENTE) return CompanyMemberRole?.ADMIN ?? 'ADMIN';
  if (role === Role.CAJERO) return CompanyMemberRole?.CASHIER ?? 'CASHIER';
  if (role === Role.VENDEDOR) return CompanyMemberRole?.SELLER ?? 'SELLER';
  return CompanyMemberRole?.VIEWER ?? 'VIEWER';
}

async function upsertCompanyMember({ userId, companyId, role }) {
  if (!prisma.companyMember?.upsert) return { skipped: true };
  return prisma.companyMember.upsert({
    where: { userId_companyId: { userId, companyId } },
    // SAFETY: never overwrite an EXISTING membership (role, status, joinedAt).
    // Only `create` sets the initial membership for a new admin.
    update: {},
    create: {
      userId,
      companyId,
      role: companyMemberRoleFromLegacyRole(role),
      status: CompanyMemberStatus?.ACTIVE ?? 'ACTIVE',
      joinedAt: new Date(),
    },
  });
}

async function safeBackfill(modelName, companyId) {
  const model = prisma[modelName];
  if (!model?.updateMany) return { modelName, count: 0, skipped: true };

  try {
    const result = await model.updateMany({
      where: { companyId: null },
      data: { companyId },
    });
    return { modelName, count: result.count, skipped: false };
  } catch (error) {
    return {
      modelName,
      count: 0,
      skipped: true,
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}

async function backfillDefaultCompany(companyId) {
  const models = [
    'user',
    'product',
    'supplier',
    'purchaseInvoice',
    'purchaseOrder',
    'client',
    'sale',
    'saleCreditPayment',
    'cashboxDaily',
    'cashSession',
    'cashMovement',
    'close',
    'depositOrder',
    'fiscalInvoice',
    'payableService',
    'payablePayment',
    'payrollEmployee',
    'payrollPeriod',
    'payrollEmployeeConfig',
    'payrollEntry',
    'payrollEmployeePeriodStatus',
    'payrollServiceCommissionRequest',
    'warrantyProductConfig',
    'cotizacion',
    'workScheduleProfile',
    'workCoverageRule',
    'workWeekSchedule',
    'workScheduleAuditLog',
    'aiAssistantConversationTurn',
    'aiAssistantMemory',
  ];

  const results = [];
  for (const modelName of models) {
    results.push(await safeBackfill(modelName, companyId));
  }
  return results;
}

async function main() {
  const adminEmail = process.env.ADMIN_EMAIL || 'admin@daleventa.local';
  const adminPassword = process.env.ADMIN_PASSWORD;
  if (!adminPassword) throw new Error('ADMIN_PASSWORD is required to run seed');
  const units = await upsertGlobalUnits();

  const existingCompany = await prisma.company.findUnique({ where: { slug: 'daleventa-pos' } });
  const company = await upsertDefaultCompany();
  await upsertAppConfig(company);
  // SAFETY: only backfill orphaned rows (companyId = null) when bootstrapping a
  // brand-NEW company. On an existing production company this would otherwise
  // reassign ambiguous rows (possibly belonging to other tenants) to this one.
  const backfill = existingCompany ? [] : await backfillDefaultCompany(company.id);

  const admin = await upsertUser({
    companyId: company.id,
    email: adminEmail,
    password: adminPassword,
    nombreCompleto: 'Administrador',
    telefono: '0000000000',
    role: Role.ADMIN,
  });
  await upsertCompanyMember({
    userId: admin.id,
    companyId: company.id,
    role: Role.ADMIN,
  });

  console.log('Seed completed (admin enforced):', {
    admin: admin.email,
    company: company.slug,
    role: 'ADMIN',
    mode: admin.fallback ? 'users-table-fallback' : 'prisma-user-model',
    globalUnits: units.skipped ? 'skipped' : units.count,
    backfill: backfill
      .filter((item) => !item.skipped && item.count > 0)
      .map((item) => `${item.modelName}:${item.count}`),
  });
}

if (require.main === module) {
  main()
    .then(async () => {
      await prisma.$disconnect();
    })
    .catch(async (e) => {
      console.error(e);
      await prisma.$disconnect();
      process.exit(1);
    });
}

module.exports = {
  upsertDefaultCompany,
  upsertAppConfig,
  upsertUser,
  upsertCompanyMember,
  upsertGlobalUnits,
  backfillDefaultCompany,
  main,
  prisma,
};
