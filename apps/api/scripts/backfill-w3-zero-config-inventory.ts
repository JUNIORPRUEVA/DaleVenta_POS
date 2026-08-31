import { PrismaClient } from "@prisma/client";
import { backfillZeroConfigInventoryForAllCompanies } from "../src/inventory/zero-config-inventory";

async function main() {
  const prisma = new PrismaClient();
  try {
    const summary = await backfillZeroConfigInventoryForAllCompanies(prisma);
    console.log(JSON.stringify(summary, null, 2));
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
