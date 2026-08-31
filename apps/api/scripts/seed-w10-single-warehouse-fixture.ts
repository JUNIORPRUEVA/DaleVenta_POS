import { PrismaClient, ProductSource } from "@prisma/client";
import * as bcrypt from "bcryptjs";

const prisma = new PrismaClient();
const email = "w10.single@daleventa.local";
const password = process.env.W10_VISUAL_PASSWORD;

async function assertSafeDatabase() {
  const [{ db }] = await prisma.$queryRawUnsafe<Array<{ db: string }>>(
    "select current_database() as db",
  );
  if (!db.includes("validation") && !db.includes("uat")) {
    throw new Error(`Unsafe W10 single-warehouse database: ${db}`);
  }
  if (db === "daleventa") throw new Error("Refusing production database.");
  return db;
}

async function main() {
  if (!password) throw new Error("W10_VISUAL_PASSWORD is required.");
  const db = await assertSafeDatabase();

  await prisma.user.deleteMany({ where: { email } });
  await prisma.company.deleteMany({ where: { slug: "w10-single-warehouse-uat" } });

  const company = await prisma.company.create({
    data: {
      name: "W10 Single Warehouse UAT",
      slug: "w10-single-warehouse-uat",
      productSource: ProductSource.LOCAL,
      measurementUnitsEnabled: true,
    },
  });
  const warehouse = await prisma.warehouse.create({
    data: {
      companyId: company.id,
      name: "Principal Unico W10",
      code: "UNI",
      isDefault: true,
      isActive: true,
    },
  });
  await prisma.user.create({
    data: {
      companyId: company.id,
      email,
      passwordHash: await bcrypt.hash(password, 10),
      nombreCompleto: "Admin W10 Single",
      telefono: "000",
      edad: 30,
      role: "ADMIN",
    },
  });

  console.log(JSON.stringify({ db, email, company: company.slug, warehouse: warehouse.code }));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => prisma.$disconnect());
