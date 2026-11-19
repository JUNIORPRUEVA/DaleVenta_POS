import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { CompanyPlan, LicenseStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export type ActivationResult = {
  planCode: string;
  planName: string;
  catalogVersion: number;
  months: number;
  periodStart: Date;
  periodEnd: Date;
  /** Interruptores que quedaron apagados porque el plan no los incluye. */
  turnedOff: string[];
};

/**
 * Aplica el paquete de un plan a la empresa.
 *
 * Regla de negocio cerrada: al activar, **todo lo opcional queda apagado**.
 * El cliente enciende lo que necesita. Si el plan **no** incluye una funcion,
 * se apaga aunque estuviera encendida antes: no se puede quedar mas de lo que
 * se paga.
 */
@Injectable()
export class LicenseActivationService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Renovacion: si la licencia sigue vigente, el nuevo periodo **suma** al
   * vencimiento; si ya vencio (o estaba en prueba), empieza hoy.
   */
  async applyPlan(input: {
    companyId: string;
    planCode: string;
    months?: number;
    now?: Date;
    /**
     * Transaccion de quien llama. El comprobante lo pasa para que activar y
     * registrar el pago sean **una sola** operacion: si falla el guardado, la
     * licencia no queda activada sin comprobante ni auditoria.
     */
    tx?: Prisma.TransactionClient;
  }): Promise<ActivationResult> {
    const now = input.now ?? new Date();
    const months = clampMonths(input.months ?? 1);
    const plan = await this.prisma.licensePlan.findUnique({
      where: { code: input.planCode.trim().toLowerCase() },
    });
    if (!plan || !plan.active) {
      throw new NotFoundException({
        code: 'PLAN_NOT_AVAILABLE',
        message: 'Ese plan no esta disponible en el catalogo.',
        planCode: input.planCode,
      });
    }

    const run = (tx: Prisma.TransactionClient) =>
      this.applyInTransaction(tx, input.companyId, plan, months, now);
    return input.tx ? run(input.tx) : this.prisma.$transaction(run);
  }

  private async applyInTransaction(
    tx: Prisma.TransactionClient,
    companyId: string,
    plan: {
      code: string;
      name: string;
      version: number;
      maxUsers: number;
      maxProducts: number;
      maxWarehouses: number;
      ecf: boolean;
      taxes: boolean;
      wholesale: boolean;
      uom: boolean;
    },
    months: number,
    now: Date,
  ): Promise<ActivationResult> {
    // A1: se bloquea la fila de la empresa **antes** de leer el vencimiento.
    // Sin esto, dos activaciones concurrentes leian el mismo periodo y la
    // segunda escribia un valor ya calculado: o se perdia un mes pagado o se
    // sumaba dos veces.
    await tx.$queryRaw`SELECT id FROM companies WHERE id = ${companyId}::uuid FOR UPDATE`;
    const company = await tx.company.findUnique({
        where: { id: companyId },
        select: {
          licenseStatus: true,
          licenseActivatedAt: true,
          licenseExpiresAt: true,
          ncfEnabled: true,
          taxEnabled: true,
          wholesalePriceListsEnabled: true,
          measurementUnitsEnabled: true,
        },
      });
      if (!company) throw new NotFoundException('Empresa no encontrada');
      if (company.licenseStatus === LicenseStatus.BLOCKED) {
        throw new BadRequestException({
          code: 'LICENSE_BLOCKED',
          message:
            'La empresa esta bloqueada. Contacta soporte para regularizar el pago.',
        });
      }

      const stillValid =
        company.licenseStatus === LicenseStatus.ACTIVE &&
        !!company.licenseExpiresAt &&
        company.licenseExpiresAt.getTime() > now.getTime();
      const periodStart = stillValid
        ? (company.licenseExpiresAt as Date)
        : now;
      const periodEnd = addMonths(periodStart, months);

      const turnedOff: string[] = [];
      const ecfEnabled = plan.ecf ? company.ncfEnabled : false;
      const taxesEnabled = plan.taxes ? company.taxEnabled : false;
      const wholesaleEnabled = plan.wholesale
        ? company.wholesalePriceListsEnabled
        : false;
      const uomEnabled = plan.uom ? company.measurementUnitsEnabled : false;
      if (company.ncfEnabled && !ecfEnabled) turnedOff.push('ncfEnabled');
      if (company.taxEnabled && !taxesEnabled) turnedOff.push('taxEnabled');
      if (company.wholesalePriceListsEnabled && !wholesaleEnabled) {
        turnedOff.push('wholesalePriceListsEnabled');
      }
      if (company.measurementUnitsEnabled && !uomEnabled) {
        turnedOff.push('measurementUnitsEnabled');
      }

      await tx.company.update({
        where: { id: companyId },
        data: {
          planCode: plan.code,
          planCatalogVersion: plan.version,
          plan: isEnterprise(plan.code)
            ? CompanyPlan.ENTERPRISE
            : CompanyPlan.STANDARD,
          maxUsers: plan.maxUsers,
          maxProducts: plan.maxProducts,
          maxWarehouses: plan.maxWarehouses,
          licenseStatus: LicenseStatus.ACTIVE,
          status: 'ACTIVE',
          licenseActivatedAt: company.licenseActivatedAt ?? now,
          licenseExpiresAt: periodEnd,
          licenseBlockedAt: null,
          ncfEnabled: ecfEnabled,
          taxEnabled: taxesEnabled,
          wholesalePriceListsEnabled: wholesaleEnabled,
          measurementUnitsEnabled: uomEnabled,
        },
        select: { id: true },
      });

      return {
        planCode: plan.code,
        planName: plan.name,
        catalogVersion: plan.version,
        months,
        periodStart,
        periodEnd,
        turnedOff,
      };
  }
}

export function addMonths(from: Date, months: number) {
  const result = new Date(from.getTime());
  const day = result.getUTCDate();
  result.setUTCMonth(result.getUTCMonth() + months);
  // 31 de enero + 1 mes no puede convertirse en 3 de marzo.
  if (result.getUTCDate() < day) {
    result.setUTCDate(0);
  }
  return result;
}

function clampMonths(value: number) {
  if (!Number.isFinite(value)) return 1;
  return Math.min(Math.max(Math.trunc(value), 1), 12);
}

function isEnterprise(code: string) {
  const normalized = code.trim().toUpperCase();
  return normalized === 'EMPRESA' || normalized === 'ENTERPRISE';
}
