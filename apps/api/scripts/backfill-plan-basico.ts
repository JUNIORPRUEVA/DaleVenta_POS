import { PrismaClient, Prisma, LicenseStatus } from '@prisma/client';
import { buildEntitlements } from '../src/license/plans/license-entitlements.service';

/**
 * Migra a los clientes que YA estaban trabajando al catalogo de planes.
 *
 * Que hace, por empresa:
 *  - Le asigna el plan indicado (`basico` por defecto) y su version de catalogo.
 *  - **Conserva** el estado de la licencia y el vencimiento: los meses que el
 *    cliente ya tiene pagados no se tocan.
 *  - **Conserva** los limites y las funciones que ya usaba: lo que el plan no
 *    incluye se concede como excepcion (`license_company_overrides`), con su
 *    motivo. Sin eso, pasar de «sin plan» a Basico le quitaria facturacion
 *    electronica, impuestos o almacenes a quien los estaba usando.
 *  - Deja rastro en `company_license_audit_logs`.
 *
 * Es **idempotente**: solo mira empresas sin `plan_code`, asi que ejecutarlo dos
 * veces no cambia nada la segunda.
 *
 * Uso (desde apps/api):
 *   npx ts-node --transpile-only -P tsconfig.scripts.json scripts/backfill-plan-basico.ts
 *       -> simulacion: no escribe nada, muestra que haria
 *   npx ts-node --transpile-only -P tsconfig.scripts.json scripts/backfill-plan-basico.ts --apply
 *       -> aplica
 *
 * Opciones:
 *   --plan=basico          plan destino (por defecto basico)
 *   --include-trial        incluye tambien las empresas en prueba
 *   --company=<slug|uuid>  una sola empresa (para ensayar)
 *   --operator=<texto>     quien queda en la auditoria (por defecto deploy-backfill)
 *   --report=<ruta.json>   escribe el informe en un archivo
 */

type Options = {
  apply: boolean;
  planCode: string;
  includeTrial: boolean;
  company: string | null;
  operator: string;
  reportPath: string | null;
  authorizedBy: string | null;
};

type CompanyRow = {
  id: string;
  slug: string;
  name: string;
  status: string;
  licenseStatus: string;
  licenseActivatedAt: Date | null;
  licenseExpiresAt: Date | null;
  planCode: string | null;
  planCatalogVersion: number | null;
  maxUsers: number;
  maxProducts: number;
  maxWarehouses: number | null;
  ncfEnabled: boolean;
  taxEnabled: boolean;
  wholesalePriceListsEnabled: boolean;
  measurementUnitsEnabled: boolean;
  multiWarehouseEnabled: boolean;
};

type Result = {
  slug: string;
  name: string;
  id: string;
  decision: 'MIGRADA' | 'YA-TIENE-PLAN' | 'OMITIDA' | 'SALTADA' | 'ERROR';
  planCode: string | null;
  expiresAt: string | null;
  monthsLeft: number | null;
  compensaciones: string[];
  motivo: string | null;
};

function parseArgs(argv: string[]): Options {
  const get = (name: string) =>
    argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3) ?? null;
  return {
    apply: argv.includes('--apply'),
    planCode: (get('plan') ?? 'basico').trim().toLowerCase(),
    includeTrial: argv.includes('--include-trial'),
    company: get('company'),
    operator: get('operator') ?? 'deploy-backfill',
    reportPath: get('report'),
    authorizedBy: get('autorizado-por'),
  };
}

function monthsBetween(from: Date, to: Date) {
  const days = (to.getTime() - from.getTime()) / 86_400_000;
  return Math.max(0, Math.round((days / 30.4) * 10) / 10);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  // Candado: este script cambia el plan de clientes reales. Sin una
  // autorizacion escrita no se aplica, aunque se pase --apply. En produccion se
  // queda en simulacion (que es lo que se revisa antes de decidir).
  if (options.apply && !options.authorizedBy) {
    throw new Error(
      'El backfill se queda en simulacion: para aplicar hace falta ' +
        '--autorizado-por="<quien autoriza>" ademas de --apply.',
    );
  }

  const prisma = new PrismaClient();
  const results: Result[] = [];

  try {
    const plan = await prisma.licensePlan.findUnique({
      where: { code: options.planCode },
    });
    if (!plan || !plan.active) {
      throw new Error(
        `El plan "${options.planCode}" no existe o esta inactivo. ` +
          'Ejecuta antes scripts/seed-license-plans.ts.',
      );
    }

    const statuses: LicenseStatus[] = options.includeTrial
      ? [LicenseStatus.ACTIVE, LicenseStatus.TRIAL]
      : [LicenseStatus.ACTIVE];
    const where: Prisma.CompanyWhereInput = {
      planCode: null,
      status: { not: 'ARCHIVED' },
      licenseStatus: { in: statuses },
    };
    if (options.company) {
      const esUuid =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          options.company,
        );
      where.OR = esUuid
        ? [{ id: options.company }]
        : [{ slug: options.company }];
    }

    const companies = (await prisma.company.findMany({
      where,
      orderBy: { name: 'asc' },
      select: {
        id: true,
        slug: true,
        name: true,
        status: true,
        licenseStatus: true,
        licenseActivatedAt: true,
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
      },
    })) as CompanyRow[];

    console.log(
      `Plan destino: ${plan.code} v${plan.version} · ` +
        (options.apply ? 'APLICANDO' : 'SIMULACION (sin escribir)'),
    );
    console.log(`Empresas sin plan a revisar: ${companies.length}\n`);

    for (const company of companies) {
      try {
        const result = await migrateCompany(prisma, company, plan, options);
        results.push(result);
      } catch (error) {
        results.push({
          slug: company.slug,
          name: company.name,
          id: company.id,
          decision: 'ERROR',
          planCode: plan.code,
          expiresAt: company.licenseExpiresAt?.toISOString() ?? null,
          monthsLeft: null,
          compensaciones: [],
          motivo: error instanceof Error ? error.message : String(error),
        });
      }
    }

    printReport(results, options);
    if (options.reportPath) {
      const { writeFileSync } = await import('node:fs');
      writeFileSync(
        options.reportPath,
        JSON.stringify({ applied: options.apply, plan: plan.code, results }, null, 2),
        'utf8',
      );
      console.log(`\nInforme escrito en ${options.reportPath}`);
    }

    const errores = results.filter((r) => r.decision === 'ERROR');
    const recortes = results.filter(
      (r) => r.decision === 'SALTADA' && r.motivo?.includes('recortaria'),
    );
    if (errores.length || recortes.length) {
      console.error('\nHay empresas que NO se pueden migrar sin revisar. No se toco ninguna de ellas.');
      process.exitCode = 2;
    }
  } finally {
    await prisma.$disconnect();
  }
}

async function migrateCompany(
  prisma: PrismaClient,
  company: CompanyRow,
  plan: {
    code: string;
    name: string;
    version: number;
    maxUsers: number;
    maxProducts: number;
    maxWarehouses: number;
    multiWarehouse: boolean;
    ecf: boolean;
    taxes: boolean;
    wholesale: boolean;
    uom: boolean;
    ecfMonthlyQuota: number | null;
  },
  options: Options,
): Promise<Result> {
  const now = new Date();
  const before = await prisma.licenseCompanyOverride.findUnique({
    where: { companyId: company.id },
  });

  // Lo que el plan no cubre y la empresa YA usa se concede como excepcion.
  const extraUsers = Math.max(0, company.maxUsers - plan.maxUsers);
  const extraProducts = Math.max(0, company.maxProducts - plan.maxProducts);
  const extraWarehouses = Math.max(
    0,
    (company.maxWarehouses ?? 1) - plan.maxWarehouses,
  );
  const allowEcf = company.ncfEnabled && !plan.ecf;
  const allowTaxes = company.taxEnabled && !plan.taxes;
  const allowWholesale = company.wholesalePriceListsEnabled && !plan.wholesale;
  const allowUom = company.measurementUnitsEnabled && !plan.uom;
  const allowMultiWarehouse = company.multiWarehouseEnabled && !plan.multiWarehouse;

  const compensaciones: string[] = [];
  if (extraUsers) compensaciones.push(`+${extraUsers} usuarios`);
  if (extraProducts) compensaciones.push(`+${extraProducts} productos`);
  if (extraWarehouses) compensaciones.push(`+${extraWarehouses} almacenes`);
  if (allowEcf) compensaciones.push('e-CF');
  if (allowTaxes) compensaciones.push('impuestos');
  if (allowWholesale) compensaciones.push('mayoreo');
  if (allowUom) compensaciones.push('unidades de medida');
  if (allowMultiWarehouse) compensaciones.push('multi-almacen');

  const tieneCompensacion = compensaciones.length > 0;

  const overrideDespues = {
    extraUsers: (before?.extraUsers ?? 0) + extraUsers,
    extraProducts: (before?.extraProducts ?? 0) + extraProducts,
    extraWarehouses: (before?.extraWarehouses ?? 0) + extraWarehouses,
    allowEcf: (before?.allowEcf ?? false) || allowEcf,
    allowTaxes: (before?.allowTaxes ?? false) || allowTaxes,
    allowWholesale: (before?.allowWholesale ?? false) || allowWholesale,
    allowUom: (before?.allowUom ?? false) || allowUom,
    allowMultiWarehouse:
      (before?.allowMultiWarehouse ?? false) || allowMultiWarehouse,
    expiresAt: before?.expiresAt ?? null,
  };

  // Verificacion: el paquete efectivo no puede quedar por debajo de lo que la
  // empresa ya tiene concedido ni de las funciones que ya usa.
  const antes = buildEntitlements(
    {
      planCode: null,
      planCatalogVersion: null,
      maxUsers: company.maxUsers,
      maxProducts: company.maxProducts,
      maxWarehouses: company.maxWarehouses,
    },
    null,
    before,
    now,
  );
  const despues = buildEntitlements(
    {
      planCode: plan.code,
      planCatalogVersion: plan.version,
      maxUsers: company.maxUsers,
      maxProducts: company.maxProducts,
      maxWarehouses: company.maxWarehouses,
    },
    plan,
    overrideDespues,
    now,
  );
  const recortes: string[] = [];
  if (despues.maxUsers < antes.maxUsers) recortes.push('usuarios');
  if (despues.maxProducts < antes.maxProducts) recortes.push('productos');
  if (despues.maxWarehouses < antes.maxWarehouses) recortes.push('almacenes');
  if (company.ncfEnabled && !despues.features.ecf) recortes.push('e-CF');
  if (company.taxEnabled && !despues.features.taxes) recortes.push('impuestos');
  if (company.wholesalePriceListsEnabled && !despues.features.wholesale) {
    recortes.push('mayoreo');
  }
  if (company.measurementUnitsEnabled && !despues.features.uom) {
    recortes.push('unidades de medida');
  }
  if (company.multiWarehouseEnabled && !despues.multiWarehouse) {
    recortes.push('multi-almacen');
  }
  if (recortes.length) {
    return {
      slug: company.slug,
      name: company.name,
      id: company.id,
      decision: 'SALTADA',
      planCode: plan.code,
      expiresAt: company.licenseExpiresAt?.toISOString() ?? null,
      monthsLeft: company.licenseExpiresAt
        ? monthsBetween(now, company.licenseExpiresAt)
        : null,
      compensaciones,
      motivo: `la migracion recortaria: ${recortes.join(', ')}`,
    };
  }

  if (!options.apply) {
    return {
      slug: company.slug,
      name: company.name,
      id: company.id,
      decision: 'MIGRADA',
      planCode: plan.code,
      expiresAt: company.licenseExpiresAt?.toISOString() ?? null,
      monthsLeft: company.licenseExpiresAt
        ? monthsBetween(now, company.licenseExpiresAt)
        : null,
      compensaciones,
      motivo: 'simulacion',
    };
  }

  await prisma.$transaction(
    async (tx) => {
      // Bloquea la empresa: si el cliente esta comprando en este momento, se
      // espera y se vuelve a comprobar el estado dentro de la transaccion.
      await tx.$queryRaw`SELECT id FROM companies WHERE id = ${company.id}::uuid FOR UPDATE`;
      const fresh = await tx.company.findUnique({
        where: { id: company.id },
        select: { planCode: true, licenseStatus: true },
      });
      if (!fresh || fresh.planCode) {
        throw new Error('la empresa ya tiene plan: no se toca');
      }
      await tx.company.update({
        where: { id: company.id },
        data: {
          planCode: plan.code,
          planCatalogVersion: plan.version,
          // Sin tocar: licenseStatus, licenseExpiresAt, licenseActivatedAt,
          // status, limites ni interruptores de la empresa.
        },
        select: { id: true },
      });

      if (tieneCompensacion) {
        await tx.licenseCompanyOverride.upsert({
          where: { companyId: company.id },
          create: {
            companyId: company.id,
            ...overrideDespues,
            note:
              'Migracion al catalogo de planes en el despliegue: se conservan los ' +
              'limites y funciones que la empresa ya tenia.',
            grantedBy: options.operator,
          },
          update: {
            ...overrideDespues,
            grantedBy: options.operator,
            grantedAt: new Date(),
          },
        });
      }

      await tx.companyLicenseAuditLog.create({
        data: {
          companyId: company.id,
          actorEmail: options.operator,
          action: 'license.plan.catalog_backfill',
          reason: compensaciones.length
            ? `Plan ${plan.code} con excepciones: ${compensaciones.join(', ')}`
            : `Plan ${plan.code} sin excepciones`,
          before: {
            planCode: null,
            licenseStatus: company.licenseStatus,
            licenseExpiresAt: company.licenseExpiresAt?.toISOString() ?? null,
            maxUsers: company.maxUsers,
            maxProducts: company.maxProducts,
            maxWarehouses: company.maxWarehouses,
            override: before
              ? {
                  ...before,
                  grantedAt: before.grantedAt.toISOString(),
                  expiresAt: before.expiresAt?.toISOString() ?? null,
                }
              : null,
          },
          after: {
            planCode: plan.code,
            planCatalogVersion: plan.version,
            licenseStatus: company.licenseStatus,
            licenseExpiresAt: company.licenseExpiresAt?.toISOString() ?? null,
            override: tieneCompensacion
              ? {
                  ...overrideDespues,
                  expiresAt: overrideDespues.expiresAt?.toISOString() ?? null,
                }
              : null,
          },
        },
      });
    },
    { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted, timeout: 20000 },
  );

  return {
    slug: company.slug,
    name: company.name,
    id: company.id,
    decision: 'MIGRADA',
    planCode: plan.code,
    expiresAt: company.licenseExpiresAt?.toISOString() ?? null,
    monthsLeft: company.licenseExpiresAt
      ? monthsBetween(now, company.licenseExpiresAt)
      : null,
    compensaciones,
    motivo: null,
  };
}

function printReport(results: Result[], options: Options) {
  const ancho = Math.max(8, ...results.map((r) => r.slug.length));
  for (const r of results) {
    const extra = r.compensaciones.length
      ? ` | excepciones: ${r.compensaciones.join(', ')}`
      : '';
    const vence = r.expiresAt
      ? ` | vence ${r.expiresAt.slice(0, 10)} (~${r.monthsLeft} meses)`
      : ' | SIN VENCIMIENTO';
    const motivo = r.motivo && r.decision !== 'MIGRADA' ? ` | ${r.motivo}` : '';
    console.log(
      `${r.decision.padEnd(11)} ${r.slug.padEnd(ancho)} ${r.name}${vence}${extra}${motivo}`,
    );
  }
  const cuenta = (d: Result['decision']) =>
    results.filter((r) => r.decision === d).length;
  console.log(
    `\nResumen: ${cuenta('MIGRADA')} migradas · ${cuenta('SALTADA')} saltadas · ` +
      `${cuenta('ERROR')} errores · ${results.length} revisadas`,
  );
  if (!options.apply) {
    console.log('SIMULACION: no se escribio nada. Repite con --apply para aplicar.');
  }
}

main().catch((error) => {
  console.error('error en la migracion de planes', error);
  process.exitCode = 1;
});
