import { PrismaClient, ProductSource } from "@prisma/client";
import * as bcrypt from "bcryptjs";

const prisma = new PrismaClient();
const email = "w10.visual@daleventa.local";
const password = process.env.W10_VISUAL_PASSWORD;

async function main() {
  if (!password) throw new Error("W10_VISUAL_PASSWORD is required.");
  const [{ db }] = await prisma.$queryRawUnsafe<Array<{ db: string }>>(
    "select current_database() as db",
  );
  if (!db.includes("validation") && !db.includes("uat")) {
    throw new Error(`Unsafe W10 visual database: ${db}`);
  }
  if (db === "daleventa") throw new Error("Refusing production database.");

  await prisma.user.deleteMany({ where: { email } });
  await prisma.company.deleteMany({ where: { slug: "w10-visual-uat" } });
  await prisma.unitOfMeasure.upsert({
    where: { id: "W10_VIS_YARD" },
    update: {
      code: "W10_VIS_YARD",
      name: "Yarda W10 Visual",
      symbol: "yd",
      category: "LENGTH",
      allowDecimals: true,
      precision: 3,
    },
    create: {
      id: "W10_VIS_YARD",
      code: "W10_VIS_YARD",
      name: "Yarda W10 Visual",
      symbol: "yd",
      category: "LENGTH",
      allowDecimals: true,
      precision: 3,
    },
  });

  const company = await prisma.company.create({
    data: {
      name: "W10 Visual UAT",
      slug: "w10-visual-uat",
      productSource: ProductSource.LOCAL,
      measurementUnitsEnabled: true,
    },
  });
  const source = await prisma.warehouse.create({
    data: {
      companyId: company.id,
      name: "Principal W10",
      code: "PRI",
      isDefault: true,
      isActive: true,
    },
  });
  const destination = await prisma.warehouse.create({
    data: {
      companyId: company.id,
      name: "Sucursal W10",
      code: "SUC",
      isDefault: false,
      isActive: true,
    },
  });
  const product = await prisma.product.create({
    data: {
      companyId: company.id,
      nombre: "Tela Azul W10 Visual",
      codigo: "W10-YD",
      categoria: "W10",
      costo: "1",
      precio: "2",
      stock: "20.5",
      unitOfMeasureId: "W10_VIS_YARD",
    },
  });
  await prisma.warehouseStock.createMany({
    data: [
      {
        companyId: company.id,
        warehouseId: source.id,
        productId: product.id,
        quantity: "20.5",
      },
      {
        companyId: company.id,
        warehouseId: destination.id,
        productId: product.id,
        quantity: "0",
      },
    ],
  });
  await prisma.user.create({
    data: {
      companyId: company.id,
      email,
      passwordHash: await bcrypt.hash(password, 10),
      nombreCompleto: "Admin W10 Visual",
      telefono: "000",
      edad: 30,
      role: "ADMIN",
    },
  });

  console.log(
    JSON.stringify({
      db,
      email,
      company: company.slug,
      source: source.code,
      destination: destination.code,
      product: product.nombre,
    }),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => prisma.$disconnect());
