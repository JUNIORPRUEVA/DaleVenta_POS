/* eslint-disable no-console */
/**
 * Backfill: recover fiscal snapshots already stored in Sales as reusable
 * Clients, so a fiscal customer (RNC/Cédula + razón social) can be recovered
 * by RNC in future sales.
 *
 * SAFE: defaults to DRY-RUN. Pass --apply to actually write.
 * IDEMPOTENT: reuses an existing active client with the same normalized
 * document; never creates duplicates; never touches NCF / sequences / sales.
 */
import { Prisma, PrismaClient } from "@prisma/client";

const apply = process.argv.includes("--apply");
const prisma = new PrismaClient();

function normalizeTaxId(input?: string | null): string {
  const raw = (input ?? "").trim();
  if (!raw) return "";
  return raw.replace(/\D/g, "");
}

async function main() {
  const sales = await prisma.sale.findMany({
    where: {
      fiscalCustomerTaxId: { not: null, not: "" },
      fiscalCustomerName: { not: null, not: "" },
    },
    select: {
      id: true,
      companyId: true,
      userId: true,
      fiscalCustomerTaxId: true,
      fiscalCustomerName: true,
    },
    orderBy: { createdAt: "asc" },
  });

  console.log(`Fiscal sales with identification: ${sales.length} (mode: ${apply ? "APPLY" : "DRY-RUN"})`);

  let created = 0;
  let reused = 0;
  let skipped = 0;

  for (const sale of sales) {
    const normalizedTaxId = normalizeTaxId(sale.fiscalCustomerTaxId);
    const name = (sale.fiscalCustomerName ?? "").trim();
    if (!normalizedTaxId || !name) {
      skipped += 1;
      continue;
    }

    const existing = await prisma.client.findFirst({
      where: { companyId: sale.companyId, isDeleted: false, taxId: normalizedTaxId },
      select: { id: true, businessName: true, nombre: true },
    });

    if (existing) {
      const updates: Prisma.ClientUncheckedUpdateInput = {};
      if (!existing.businessName) updates.businessName = name;
      if (!existing.nombre?.trim()) updates.nombre = name;
      if (apply && Object.keys(updates).length > 0) {
        await prisma.client.update({ where: { id: existing.id }, data: updates });
      }
      reused += 1;
      console.log(
        `  [reuse] sale=${sale.id} rnc=${normalizedTaxId} name=${name} client=${existing.id}`,
      );
      continue;
    }

    if (apply) {
      await prisma.client.create({
        data: {
          nombre: name,
          telefono: "",
          businessName: name,
          taxId: normalizedTaxId,
          taxIdType: "RNC",
          ownerId: sale.userId,
          companyId: sale.companyId,
          lastActivityAt: new Date(),
        },
      });
    }
    created += 1;
    console.log(
      `  [create] sale=${sale.id} rnc=${normalizedTaxId} name=${name} company=${sale.companyId}`,
    );
  }

  console.log(`\nCreated=${created} reused=${reused} skipped=${skipped}`);
  if (!apply) {
    console.log("DRY-RUN: no data was written. Re-run with --apply to persist.");
  }
}

main()
  .catch((error) => {
    console.error("BACKFILL FAILED:", error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
