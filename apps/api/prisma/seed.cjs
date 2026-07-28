const { Prisma, PrismaClient, Role, CompanyMemberRole, CompanyMemberStatus } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

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
    update: {
      name: 'DaleVenta POS',
      status: 'ACTIVE',
      plan: 'ENTERPRISE',
      maxUsers: 1000,
    },
    create: {
      name: 'DaleVenta POS',
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
    update: {
      companyId: company.id,
      companyName: company.name,
    },
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
      update: { companyId, nombreCompleto, telefono, role, passwordHash, blocked: false },
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
        DO UPDATE SET "passwordHash" = EXCLUDED."passwordHash", role = EXCLUDED.role
        RETURNING id, email
      `);
    } catch {
      rows = await prisma.$queryRaw(Prisma.sql`
        INSERT INTO users (email, "passwordHash", role)
        VALUES (${email}, ${passwordHash}, ${role})
        ON CONFLICT (email)
        DO UPDATE SET "passwordHash" = EXCLUDED."passwordHash", role = EXCLUDED.role
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
    update: {
      role: companyMemberRoleFromLegacyRole(role),
      status: CompanyMemberStatus?.ACTIVE ?? 'ACTIVE',
      joinedAt: new Date(),
    },
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

  const company = await upsertDefaultCompany();
  await upsertAppConfig(company);
  const backfill = await backfillDefaultCompany(company.id);

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
    backfill: backfill
      .filter((item) => !item.skipped && item.count > 0)
      .map((item) => `${item.modelName}:${item.count}`),
  });
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
