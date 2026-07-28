const { Prisma, PrismaClient, Role } = require('@prisma/client');
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

async function main() {
  const adminEmail = process.env.ADMIN_EMAIL || 'admin@daleventa.local';
  const adminPassword = process.env.ADMIN_PASSWORD;
  if (!adminPassword) throw new Error('ADMIN_PASSWORD is required to run seed');

  const company = await upsertDefaultCompany();
  await upsertAppConfig(company);

  const admin = await upsertUser({
    companyId: company.id,
    email: adminEmail,
    password: adminPassword,
    nombreCompleto: 'Administrador',
    telefono: '0000000000',
    role: Role.ADMIN,
  });

  console.log('Seed completed (admin enforced):', {
    admin: admin.email,
    company: company.slug,
    role: 'ADMIN',
    mode: admin.fallback ? 'users-table-fallback' : 'prisma-user-model',
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
