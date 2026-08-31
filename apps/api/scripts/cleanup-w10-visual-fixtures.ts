import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  const [{ db }] = await prisma.$queryRawUnsafe<Array<{ db: string }>>(
    "select current_database() as db",
  );
  if (!db.includes("validation") && !db.includes("uat")) {
    throw new Error(`Unsafe W10 fixture cleanup database: ${db}`);
  }
  if (db === "daleventa") throw new Error("Refusing production database.");

  const userEmails = ["w10.visual@daleventa.local", "w10.single@daleventa.local"];
  const companySlugs = ["w10-visual-uat", "w10-single-warehouse-uat"];

  const users = await prisma.user.deleteMany({ where: { email: { in: userEmails } } });
  const companies = await prisma.company.deleteMany({
    where: { slug: { in: companySlugs } },
  });
  await prisma.unitOfMeasure.deleteMany({ where: { id: "W10_VIS_YARD" } });

  const remainingUsers = await prisma.user.count({
    where: { email: { in: userEmails } },
  });
  const remainingCompanies = await prisma.company.count({
    where: { slug: { in: companySlugs } },
  });

  console.log(
    JSON.stringify({
      db,
      deletedUsers: users.count,
      deletedCompanies: companies.count,
      remainingUsers,
      remainingCompanies,
    }),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => prisma.$disconnect());
