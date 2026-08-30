import { Prisma, PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

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
] as const;

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

function isMissingUserTable(error: unknown) {
  if (typeof error === 'object' && error !== null) {
    const value = error as { code?: unknown; message?: unknown };
    const code = typeof value.code === 'string' ? value.code : '';
    const message = typeof value.message === 'string' ? value.message : '';
    return code === 'P2021' || message.includes('table `public.User` does not exist');
  }
  return false;
}

async function upsertUser({ email, password, nombreCompleto, telefono, role }: { email: string; password: string; nombreCompleto: string; telefono: string; role: Role }): Promise<{ id: string; email: string; fallback: boolean }> {
  const passwordHash = await bcrypt.hash(password, 10);
  try {
    const user = await prisma.user.upsert({
      where: { email },
      update: { nombreCompleto, telefono, role, passwordHash, blocked: false },
      create: { email, passwordHash, nombreCompleto, telefono, edad: 0, role, blocked: false, tieneHijos: false, estaCasado: false, casaPropia: false, vehiculo: false, licenciaConducir: false }
    });
    return { id: user.id, email: user.email, fallback: false };
  } catch (error) {
    if (!isMissingUserTable(error)) throw error;

    let rows: Array<{ id: string; email: string }>;
    try {
      rows = await prisma.$queryRaw<Array<{ id: string; email: string }>>(Prisma.sql`
        INSERT INTO users (email, "passwordHash", role)
        VALUES (${email}, ${passwordHash}, CAST(${role} AS "Role"))
        ON CONFLICT (email)
        DO UPDATE SET "passwordHash" = EXCLUDED."passwordHash", role = EXCLUDED.role
        RETURNING id, email
      `);
    } catch {
      rows = await prisma.$queryRaw<Array<{ id: string; email: string }>>(Prisma.sql`
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
  const units = await upsertGlobalUnits();

  const admin = await upsertUser({
    email: adminEmail,
    password: adminPassword,
    nombreCompleto: 'Administrador',
    telefono: '0000000000',
    role: Role.ADMIN
  });

  console.log('Seed completed (admin enforced):', {
    admin: admin.email,
    role: 'ADMIN',
    globalUnits: units.skipped ? 'skipped' : units.count,
    mode: admin.fallback ? 'users-table-fallback' : 'prisma-user-model'
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
