import { PrismaClient, LicenseStatus } from '@prisma/client';
import { buildEntitlements } from '../src/license/plans/license-entitlements.service';

/**
 * Radiografia de licencias antes y despues del despliegue.
 *
 * No escribe nada. Sirve para responder, con datos y no de memoria:
 *  - ¿Hay empresas activas sin plan asignado? (lo que migra el backfill)
 *  - ¿Cada empresa conserva su vencimiento y sus meses?
 *  - ¿Alguna usa una funcion que su plan no cubre?
 *  - ¿Alguna supera los limites de usuarios, productos o almacenes?
 *
 * Uso (desde apps/api):
 *   npx ts-node --transpile-only -P tsconfig.scripts.json scripts/plan-migration-check.ts
 *   npx ts-node --transpile-only -P tsconfig.scripts.json scripts/plan-migration-check.ts --json
 *
 * Codigo de salida: 0 sin hallazgos, 2 con hallazgos que hay que revisar.
 */

type Hallazgo = {
  slug: string;
  code: string;
  detalle: string;
};

async function main() {
  const asJson = process.argv.includes('--json');
  const prisma = new PrismaClient();
  const hallazgos: Hallazgo[] = [];

  try {
    const plans = await prisma.licensePlan.findMany({ orderBy: { monthlyPrice: 'asc' } });
    const byCode = new Map(plans.map((p) => [p.code, p] as const));

    const companies = await prisma.company.findMany({
      where: { status: { not: 'ARCHIVED' } },
      orderBy: { name: 'asc' },
      select: {
        id: true,
        slug: true,
        name: true,
        status: true,
        licenseStatus: true,
        licenseExpiresAt: true,
        planCode: true,
        planCatalogVersion: true,
        maxUsers: true,
        maxProducts: true,
        maxWarehouses: true,
        ncfEnabled: true,
        taxEnabled: true,
        wholesalePriceListsEnabled: true,
        measurementUnitsEnabled: true,
        multiWarehouseEnabled: true,
        users: { select: { id: true } },
        _count: { select: { users: true } },
      },
    });

    const overrides = await prisma.licenseCompanyOverride.findMany();
    const overrideByCompany = new Map(overrides.map((o) => [o.companyId, o] as const));

    const productsByCompany = await prisma.product.groupBy({
      by: ['companyId'],
      _count: { _all: true },
    });
    const productCount = new Map(
      productsByCompany.map((row) => [row.companyId, row._count._all] as const),
    );
    const warehousesByCompany = await prisma.warehouse.groupBy({
      by: ['companyId'],
      _count: { _all: true },
    });
    const warehouseCount = new Map(
      warehousesByCompany.map((row) => [row.companyId, row._count._all] as const),
    );

    const filas = companies.map((company) => {
      const plan = company.planCode ? byCode.get(company.planCode) ?? null : null;
      const override = overrideByCompany.get(company.id) ?? null;
      const ent = buildEntitlements(
        {
          planCode: company.planCode,
          planCatalogVersion: company.planCatalogVersion,
          maxUsers: company.maxUsers,
          maxProducts: company.maxProducts,
          maxWarehouses: company.maxWarehouses,
        },
        plan,
        override,
        new Date(),
      );

      const activa =
        company.licenseStatus === LicenseStatus.ACTIVE ||
        company.licenseStatus === LicenseStatus.TRIAL;

      if (activa && !company.planCode) {
        hallazgos.push({
          slug: company.slug,
          code: 'ACTIVA_SIN_PLAN',
          detalle: 'la migracion aun no se aplico a esta empresa',
        });
      }
      if (company.planCode && !plan) {
        hallazgos.push({
          slug: company.slug,
          code: 'PLAN_DESCONOCIDO',
          detalle: `planCode=${company.planCode} no esta en el catalogo`,
        });
      }
      if (activa && !company.licenseExpiresAt) {
        hallazgos.push({
          slug: company.slug,
          code: 'ACTIVA_SIN_VENCIMIENTO',
          detalle: 'licencia sin fecha: revisar si es perpetua o un dato incompleto',
        });
      }
      // Sin plan asignado no se recorta nada (`source: none`), asi que las
      // funciones encendidas no son una incidencia: son lo normal antes de
      // migrar. Solo se comprueba cuando ya hay plan.
      const conPlan = ent.source === 'plan';
      if (conPlan && company.ncfEnabled && !ent.features.ecf) {
        hallazgos.push({
          slug: company.slug,
          code: 'FEATURE_SIN_COBERTURA',
          detalle: 'tiene facturacion electronica encendida y su plan no la incluye',
        });
      }
      if (conPlan && company.taxEnabled && !ent.features.taxes) {
        hallazgos.push({
          slug: company.slug,
          code: 'FEATURE_SIN_COBERTURA',
          detalle: 'tiene impuestos encendidos y su plan no los incluye',
        });
      }
      if (conPlan && company.wholesalePriceListsEnabled && !ent.features.wholesale) {
        hallazgos.push({
          slug: company.slug,
          code: 'FEATURE_SIN_COBERTURA',
          detalle: 'tiene mayoreo encendido y su plan no lo incluye',
        });
      }
      if (conPlan && company.measurementUnitsEnabled && !ent.features.uom) {
        hallazgos.push({
          slug: company.slug,
          code: 'FEATURE_SIN_COBERTURA',
          detalle: 'tiene unidades de medida encendidas y su plan no las incluye',
        });
      }
      if (conPlan && company.multiWarehouseEnabled && !ent.multiWarehouse) {
        hallazgos.push({
          slug: company.slug,
          code: 'FEATURE_SIN_COBERTURA',
          detalle: 'tiene multi-almacen encendido y su plan no lo incluye',
        });
      }

      const usuarios = company._count.users;
      const productos = productCount.get(company.id) ?? 0;
      const almacenes = warehouseCount.get(company.id) ?? 0;
      if (usuarios > ent.maxUsers) {
        hallazgos.push({
          slug: company.slug,
          code: 'EXCEDE_LIMITE',
          detalle: `${usuarios} usuarios con tope ${ent.maxUsers}`,
        });
      }
      if (productos > ent.maxProducts) {
        hallazgos.push({
          slug: company.slug,
          code: 'EXCEDE_LIMITE',
          detalle: `${productos} productos con tope ${ent.maxProducts}`,
        });
      }
      if (almacenes > ent.maxWarehouses) {
        hallazgos.push({
          slug: company.slug,
          code: 'EXCEDE_LIMITE',
          detalle: `${almacenes} almacenes con tope ${ent.maxWarehouses}`,
        });
      }

      return {
        slug: company.slug,
        name: company.name,
        estado: company.licenseStatus,
        planCode: company.planCode,
        vence: company.licenseExpiresAt?.toISOString().slice(0, 10) ?? null,
        limiteUsuarios: ent.maxUsers,
        limiteProductos: ent.maxProducts,
        limiteAlmacenes: ent.maxWarehouses,
        features: ent.features,
        multiWarehouse: ent.multiWarehouse,
        excepcion: ent.overrideApplied,
        uso: { usuarios, productos, almacenes },
      };
    });

    if (asJson) {
      console.log(
        JSON.stringify(
          {
            planes: plans.map((p) => ({
              code: p.code,
              name: p.name,
              price: p.monthlyPrice.toString(),
              maxUsers: p.maxUsers,
              maxProducts: p.maxProducts,
              maxWarehouses: p.maxWarehouses,
              multiWarehouse: p.multiWarehouse,
              features: { ecf: p.ecf, taxes: p.taxes, wholesale: p.wholesale, uom: p.uom },
              active: p.active,
            })),
            empresas: filas,
            hallazgos,
          },
          null,
          2,
        ),
      );
    } else {
      console.log(`Catalogo: ${plans.length} planes`);
      for (const p of plans) {
        console.log(
          `  ${p.code.padEnd(9)} RD$${p.monthlyPrice.toString().padStart(7)} · ` +
            `${p.maxUsers}u/${p.maxProducts}p/${p.maxWarehouses}a · ` +
            `${[p.ecf ? 'eCF' : null, p.taxes ? 'ITBIS' : null, p.wholesale ? 'mayoreo' : null, p.multiWarehouse ? 'multi-almacen' : null].filter(Boolean).join(', ') || 'sin extras'}` +
            (p.active ? '' : ' · INACTIVO'),
        );
      }
      console.log(`\nEmpresas: ${filas.length}`);
      for (const f of filas) {
        console.log(
          `  ${f.slug.padEnd(24)} ${f.estado.padEnd(8)} ` +
            `${(f.planCode ?? '(sin plan)').padEnd(9)} ` +
            `vence=${f.vence ?? '—'} ` +
            `topes=${f.limiteUsuarios}/${f.limiteProductos}/${f.limiteAlmacenes}` +
            (f.excepcion ? ' (con excepcion)' : '') +
            ` uso=${f.uso.usuarios}/${f.uso.productos}/${f.uso.almacenes}`,
        );
      }
      console.log(`\nHallazgos: ${hallazgos.length}`);
      for (const h of hallazgos) {
        console.log(`  ${h.code.padEnd(24)} ${h.slug}: ${h.detalle}`);
      }
    }

    if (hallazgos.length) process.exitCode = 2;
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('error en la radiografia de licencias', error);
  process.exitCode = 1;
});
