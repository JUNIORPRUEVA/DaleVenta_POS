import { PrismaClient } from '@prisma/client';

/**
 * Siembra el catálogo oficial de planes (idempotente).
 *
 * Uso:
 *   npx ts-node --transpile-only -P tsconfig.scripts.json scripts/seed-license-plans.ts
 *
 * Reglas del catálogo (docs/planes-de-pago/05-definicion-tecnica-de-planes.md):
 * - Todo lo incluido llega APAGADO en la empresa; el catálogo solo dice qué se puede encender.
 * - Básico no incluye facturación electrónica ni impuestos.
 * - Multi-almacén solo en Pro y Empresa.
 */
const PLANS = [
  {
    code: 'basico',
    name: 'FullPOS Básico',
    monthlyPrice: '1000.00',
    maxUsers: 1,
    maxProducts: 100,
    maxWarehouses: 1,
    multiWarehouse: false,
    wholesale: false,
    uom: true,
    ecf: false,
    taxes: false,
    ecfMonthlyQuota: null as number | null,
  },
  {
    code: 'negocio',
    name: 'FullPOS Negocio',
    monthlyPrice: '2500.00',
    maxUsers: 3,
    maxProducts: 400,
    maxWarehouses: 1,
    multiWarehouse: false,
    wholesale: true,
    uom: true,
    ecf: true,
    taxes: true,
    ecfMonthlyQuota: 300,
  },
  {
    code: 'pro',
    name: 'FullPOS Pro',
    monthlyPrice: '3500.00',
    maxUsers: 4,
    maxProducts: 1000,
    maxWarehouses: 5,
    multiWarehouse: true,
    wholesale: true,
    uom: true,
    ecf: true,
    taxes: true,
    ecfMonthlyQuota: 1500,
  },
  {
    code: 'empresa',
    name: 'FullPOS Empresa',
    monthlyPrice: '5000.00',
    maxUsers: 7,
    maxProducts: 5000,
    maxWarehouses: 10,
    multiWarehouse: true,
    wholesale: true,
    uom: true,
    ecf: true,
    taxes: true,
    ecfMonthlyQuota: 5000,
  },
];

async function main() {
  const prisma = new PrismaClient();
  try {
    for (const plan of PLANS) {
      await prisma.licensePlan.upsert({
        where: { code: plan.code },
        create: {
          code: plan.code,
          name: plan.name,
          version: 1,
          monthlyPrice: plan.monthlyPrice,
          currency: 'DOP',
          maxUsers: plan.maxUsers,
          maxProducts: plan.maxProducts,
          maxWarehouses: plan.maxWarehouses,
          multiWarehouse: plan.multiWarehouse,
          wholesale: plan.wholesale,
          uom: plan.uom,
          ecf: plan.ecf,
          taxes: plan.taxes,
          ecfMonthlyQuota: plan.ecfMonthlyQuota,
          active: true,
        },
        update: {
          name: plan.name,
          monthlyPrice: plan.monthlyPrice,
          currency: 'DOP',
          maxUsers: plan.maxUsers,
          maxProducts: plan.maxProducts,
          maxWarehouses: plan.maxWarehouses,
          multiWarehouse: plan.multiWarehouse,
          wholesale: plan.wholesale,
          uom: plan.uom,
          ecf: plan.ecf,
          taxes: plan.taxes,
          ecfMonthlyQuota: plan.ecfMonthlyQuota,
          active: true,
        },
      });
      // eslint-disable-next-line no-console
      console.log(`plan ${plan.code} listo (RD$${plan.monthlyPrice})`);
    }
    const total = await prisma.licensePlan.count();
    // eslint-disable-next-line no-console
    console.log(`catalogo sembrado: ${total} planes`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('error sembrando el catalogo de planes', error);
  process.exitCode = 1;
});
