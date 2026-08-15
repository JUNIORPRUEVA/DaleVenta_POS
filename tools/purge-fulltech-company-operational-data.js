const { PrismaClient } = require('@prisma/client');
const fs = require('fs');
const path = require('path');

const prisma = new PrismaClient();

const dryRun = process.argv.includes('--dry-run');
const targetName = 'FULLTECH, SRL';
const targetRnc = '133080206';

async function main() {
  const appConfigs = await prisma.appConfig.findMany({
    where: {
      companyName: { equals: targetName, mode: 'insensitive' },
      rnc: targetRnc,
      companyId: { not: null },
    },
    select: {
      id: true,
      companyName: true,
      rnc: true,
      phone: true,
      company: {
        select: {
          id: true,
          name: true,
          createdAt: true,
          updatedAt: true,
        },
      },
    },
  });

  if (appConfigs.length !== 1) {
    console.log(JSON.stringify({ ok: false, reason: 'app_config_match_not_unique', appConfigs }, null, 2));
    process.exitCode = 1;
    return;
  }

  const matchedConfig = appConfigs[0];
  const company = matchedConfig.company;
  if (!company?.id) {
    console.log(JSON.stringify({ ok: false, reason: 'matched_config_without_company', matchedConfig }, null, 2));
    process.exitCode = 1;
    return;
  }

  const companyId = company.id;
  const snapshot = await collectSnapshot(companyId);
  const summary = summarize(snapshot);

  console.log(JSON.stringify({ dryRun, matchedConfig, company, summary }, null, 2));
  if (dryRun) return;

  const backupDir = path.join(process.cwd(), 'backups', 'purges');
  fs.mkdirSync(backupDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupPath = path.join(backupDir, `fulltech-operational-purge-${stamp}.json`);
  fs.writeFileSync(backupPath, JSON.stringify({ matchedConfig, company, snapshot }, null, 2));

  const result = await prisma.$transaction(async (tx) => {
    const saleIds = snapshot.sales.map((row) => row.id);
    const sessionIds = snapshot.cashSessions.map((row) => row.id);
    const cashboxIds = snapshot.cashboxDaily.map((row) => row.id);
    const cotizacionIds = snapshot.cotizaciones.map((row) => row.id);

    const deleted = {};
    deleted.openSalesTicketState = await tx.openSalesTicketState.deleteMany({
      where: { companyId },
    });
    deleted.saleCreditPayments = await tx.saleCreditPayment.deleteMany({
      where: { companyId },
    });
    deleted.saleItems = await tx.saleItem.deleteMany({
      where: { saleId: { in: saleIds } },
    });
    deleted.sales = await tx.sale.deleteMany({
      where: { companyId },
    });
    deleted.cashMovements = await tx.cashMovement.deleteMany({
      where: { companyId },
    });
    deleted.cashSessions = await tx.cashSession.deleteMany({
      where: { companyId },
    });
    deleted.cashboxDaily = await tx.cashboxDaily.deleteMany({
      where: { companyId },
    });
    deleted.cotizacionItems = await tx.cotizacionItem.deleteMany({
      where: { cotizacionId: { in: cotizacionIds } },
    });
    deleted.cotizaciones = await tx.cotizacion.deleteMany({
      where: { companyId },
    });

    return {
      deleted,
      ids: {
        saleIds,
        sessionIds,
        cashboxIds,
        cotizacionIds,
      },
    };
  });

  const after = await collectCounts(companyId);
  console.log(JSON.stringify({ ok: true, backupPath, result, after }, null, 2));
}

async function collectSnapshot(companyId) {
  const [
    openSalesTicketState,
    sales,
    saleItems,
    saleCreditPayments,
    cashboxDaily,
    cashSessions,
    cashMovements,
    cotizaciones,
    cotizacionItems,
  ] = await Promise.all([
    prisma.openSalesTicketState.findMany({ where: { companyId } }),
    prisma.sale.findMany({ where: { companyId }, orderBy: { createdAt: 'asc' } }),
    prisma.saleItem.findMany({ where: { sale: { companyId } }, orderBy: { createdAt: 'asc' } }),
    prisma.saleCreditPayment.findMany({ where: { companyId }, orderBy: { createdAt: 'asc' } }),
    prisma.cashboxDaily.findMany({ where: { companyId }, orderBy: { openedAt: 'asc' } }),
    prisma.cashSession.findMany({ where: { companyId }, orderBy: { openedAt: 'asc' } }),
    prisma.cashMovement.findMany({ where: { companyId }, orderBy: { createdAt: 'asc' } }),
    prisma.cotizacion.findMany({ where: { companyId }, orderBy: { createdAt: 'asc' } }),
    prisma.cotizacionItem.findMany({ where: { cotizacion: { companyId } }, orderBy: { createdAt: 'asc' } }),
  ]);
  return {
    openSalesTicketState,
    sales,
    saleItems,
    saleCreditPayments,
    cashboxDaily,
    cashSessions,
    cashMovements,
    cotizaciones,
    cotizacionItems,
  };
}

async function collectCounts(companyId) {
  const snapshot = await collectSnapshot(companyId);
  return summarize(snapshot);
}

function summarize(snapshot) {
  return Object.fromEntries(
    Object.entries(snapshot).map(([key, value]) => [key, Array.isArray(value) ? value.length : 0]),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
