import { ForbiddenException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { Prisma } from '@prisma/client';

/**
 * Funciones que el plan puede incluir o bloquear. El nombre es el que viaja en
 * las respuestas de error para que la app sepa que interruptor rechazar.
 */
export type LicenseFeature = 'ecf' | 'taxes' | 'wholesale' | 'uom';

export type EffectiveEntitlements = {
  planCode: string | null;
  planName: string | null;
  catalogVersion: number | null;
  /**
   * `plan`: la empresa tiene un plan asignado y sus limites son los del
   * catalogo. `none`: empresa antigua sin plan (prueba o piloto); no se le
   * recorta nada para no romper a quien ya estaba trabajando.
   */
  source: 'plan' | 'none';
  maxUsers: number;
  maxProducts: number;
  maxWarehouses: number;
  /**
   * El plan incluye gestion de multiples almacenes. Es una funcion comercial
   * aparte del interruptor `multiWarehouseEnabled` de la empresa: el plan
   * autoriza y la empresa decide si lo enciende.
   */
  multiWarehouse: boolean;
  features: Record<LicenseFeature, boolean>;
  ecfMonthlyQuota: number | null;
  /** true cuando alguna excepcion concedida por el propietario esta vigente. */
  overrideApplied: boolean;
};

type CompanyEntitlementRow = {
  planCode: string | null;
  planCatalogVersion: number | null;
  maxUsers: number;
  maxProducts: number;
  maxWarehouses: number | null;
};

type PlanRow = {
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
};

type OverrideRow = {
  extraUsers: number;
  extraProducts: number;
  extraWarehouses: number;
  allowEcf: boolean;
  allowTaxes: boolean;
  allowWholesale: boolean;
  allowUom: boolean;
  allowMultiWarehouse: boolean;
  expiresAt: Date | null;
};

@Injectable()
export class LicenseEntitlementsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Paquete efectivo de la empresa: catalogo + excepciones vigentes.
   */
  async getEntitlements(companyId: string, db: Prisma.TransactionClient = this.prisma): Promise<EffectiveEntitlements> {
    const company = await db.company.findUnique({
      where: { id: companyId },
      select: {
        planCode: true,
        planCatalogVersion: true,
        maxUsers: true,
        maxProducts: true,
        maxWarehouses: true,
      },
    });
    if (!company) {
      throw new ForbiddenException('Empresa no encontrada');
    }
    const [plan, override] = await Promise.all([
      company.planCode
        ? db.licensePlan.findUnique({
            where: { code: company.planCode },
            select: {
              code: true,
              name: true,
              version: true,
              maxUsers: true,
              maxProducts: true,
              maxWarehouses: true,
              multiWarehouse: true,
              ecf: true,
              taxes: true,
              wholesale: true,
              uom: true,
              ecfMonthlyQuota: true,
            },
          })
        : Promise.resolve(null),
      db.licenseCompanyOverride.findUnique({
        where: { companyId },
        select: {
          extraUsers: true,
          extraProducts: true,
          extraWarehouses: true,
          allowEcf: true,
          allowTaxes: true,
          allowWholesale: true,
          allowUom: true,
          allowMultiWarehouse: true,
          expiresAt: true,
        },
      }),
    ]);
    return buildEntitlements(company, plan, override, new Date());
  }

  /** true si el plan (o una excepcion) da derecho a la funcion. */
  async includesFeature(companyId: string, feature: LicenseFeature) {
    const entitlements = await this.getEntitlements(companyId);
    return isFeatureIncluded(entitlements, feature);
  }

  /**
   * Se llama antes de **encender** un interruptor. Apagar siempre esta
   * permitido: nadie queda atrapado dentro de una funcion.
   */
  async assertFeatureAllowed(companyId: string, feature: LicenseFeature) {
    const entitlements = await this.getEntitlements(companyId);
    if (isFeatureIncluded(entitlements, feature)) return entitlements;
    throw new ForbiddenException({
      code: 'PLAN_FEATURE_NOT_INCLUDED',
      message: planFeatureMessage(feature, entitlements.planName),
      feature,
      planCode: entitlements.planCode,
    });
  }

  /**
   * Limite de almacenes. El modulo de almacenes sigue activo en todos los
   * planes; lo que cambia es cuantos puede crear la empresa.
   */
  async assertWarehouseSlot(companyId: string, currentWarehouses: number) {
    const entitlements = await this.getEntitlements(companyId);
    if (entitlements.source === 'none') return entitlements;
    if (currentWarehouses < entitlements.maxWarehouses) return entitlements;
    throw new ForbiddenException({
      code: 'PLAN_LIMIT_WAREHOUSES',
      message: `Tu plan ${entitlements.planName ?? ''} permite ${entitlements.maxWarehouses} almacen(es). Amplia tu plan para crear otro.`.trim(),
      limit: entitlements.maxWarehouses,
      current: currentWarehouses,
      planCode: entitlements.planCode,
    });
  }
}

export function isFeatureIncluded(
  entitlements: EffectiveEntitlements,
  feature: LicenseFeature,
) {
  // Sin plan asignado no se recorta nada (empresas anteriores al catalogo).
  if (entitlements.source === 'none') return true;
  return entitlements.features[feature] === true;
}

export function buildEntitlements(
  company: CompanyEntitlementRow,
  plan: PlanRow | null,
  override: OverrideRow | null,
  now: Date = new Date(),
): EffectiveEntitlements {
  const activeOverride =
    override && (!override.expiresAt || override.expiresAt.getTime() > now.getTime())
      ? override
      : null;
  const planName = plan?.name ?? null;
  const source: 'plan' | 'none' = plan ? 'plan' : 'none';
  const baseUsers = plan?.maxUsers ?? company.maxUsers;
  const baseProducts = plan?.maxProducts ?? company.maxProducts;
  const baseWarehouses = plan?.maxWarehouses ?? company.maxWarehouses ?? 1;
  return {
    planCode: company.planCode ?? plan?.code ?? null,
    planName,
    catalogVersion: plan?.version ?? company.planCatalogVersion ?? null,
    source,
    maxUsers: baseUsers + (activeOverride?.extraUsers ?? 0),
    maxProducts: baseProducts + (activeOverride?.extraProducts ?? 0),
    maxWarehouses: baseWarehouses + (activeOverride?.extraWarehouses ?? 0),
    // Sin plan (empresa anterior al catalogo) no se recorta nada. Con plan, la
    // funcion la da el catalogo o una excepcion vigente.
    multiWarehouse: plan
      ? plan.multiWarehouse || (activeOverride?.allowMultiWarehouse ?? false)
      : true,
    features: {
      ecf: (plan?.ecf ?? false) || (activeOverride?.allowEcf ?? false),
      taxes: (plan?.taxes ?? false) || (activeOverride?.allowTaxes ?? false),
      wholesale: (plan?.wholesale ?? false) || (activeOverride?.allowWholesale ?? false),
      uom: (plan?.uom ?? false) || (activeOverride?.allowUom ?? false),
    },
    ecfMonthlyQuota: plan?.ecfMonthlyQuota ?? null,
    overrideApplied: !!activeOverride,
  };
}

function planFeatureMessage(feature: LicenseFeature, planName: string | null) {
  const label = FEATURE_LABELS[feature];
  const plan = planName ? `El plan ${planName}` : 'Tu plan actual';
  return `${plan} no incluye ${label}. Puedes cambiar de plan desde la seccion Planes.`;
}

const FEATURE_LABELS: Record<LicenseFeature, string> = {
  ecf: 'facturacion electronica',
  taxes: 'impuestos (ITBIS)',
  wholesale: 'mayoreo y listas de precio',
  uom: 'multi unidad de medida',
};

export type { CompanyEntitlementRow, PlanRow, OverrideRow };
