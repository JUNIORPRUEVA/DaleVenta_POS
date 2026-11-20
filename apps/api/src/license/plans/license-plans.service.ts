import { Injectable, Logger, type OnModuleInit } from '@nestjs/common';
import type { LicensePlan } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * Catálogo público de planes.
 *
 * Es la única fuente de precios y límites que consume la app: nunca se
 * escriben precios en el cliente.
 * Ver docs/planes-de-pago/05-definicion-tecnica-de-planes.md
 */
export type PublicLicensePlan = {
  code: string;
  name: string;
  version: number;
  monthlyPrice: string;
  currency: string;
  limits: {
    maxUsers: number;
    maxProducts: number;
    maxWarehouses: number;
  };
  features: {
    multiWarehouse: boolean;
    wholesale: boolean;
    uom: boolean;
    ecf: boolean;
    taxes: boolean;
  };
  ecfMonthlyQuota: number | null;
};

@Injectable()
export class LicensePlansService implements OnModuleInit {
  private readonly logger = new Logger(LicensePlansService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Aviso temprano: si el catálogo está vacío, la app no tiene precios que
   * mostrar. No se siembra solo para no sobrescribir precios ya ajustados.
   */
  async onModuleInit() {
    try {
      const total = await this.prisma.licensePlan.count();
      if (total === 0) {
        this.logger.warn(
          'Catalogo de planes vacio: ejecutar scripts/seed-license-plans.ts antes de publicar precios',
        );
      }
    } catch {
      // La comprobacion no debe impedir el arranque de la API.
    }
  }

  async listPublic(): Promise<{ plans: PublicLicensePlan[] }> {
    const rows = await this.prisma.licensePlan.findMany({
      where: { active: true },
      orderBy: [{ monthlyPrice: 'asc' }, { code: 'asc' }],
    });
    return { plans: rows.map((row) => this.toPublic(row)) };
  }

  async findByCode(code: string): Promise<LicensePlan | null> {
    const normalized = (code ?? '').trim().toLowerCase();
    if (!normalized) return null;
    return this.prisma.licensePlan.findFirst({
      where: { code: normalized, active: true },
    });
  }

  private toPublic(row: LicensePlan): PublicLicensePlan {
    return {
      code: row.code,
      name: row.name,
      version: row.version,
      monthlyPrice: row.monthlyPrice.toString(),
      currency: row.currency,
      limits: {
        maxUsers: row.maxUsers,
        maxProducts: row.maxProducts,
        maxWarehouses: row.maxWarehouses,
      },
      features: {
        multiWarehouse: row.multiWarehouse,
        wholesale: row.wholesale,
        uom: row.uom,
        ecf: row.ecf,
        taxes: row.taxes,
      },
      ecfMonthlyQuota: row.ecfMonthlyQuota,
    };
  }
}
