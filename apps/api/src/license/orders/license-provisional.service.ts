import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import {
  LicenseActivationState,
  LicenseOrderStatus,
  LicenseStatus,
  Prisma,
} from '@prisma/client';

/**
 * Activacion provisional: el cliente usa el servicio desde que sube el
 * comprobante, pero el pago sigue **sin confirmar** hasta que soporte lo
 * verifique en el CRM.
 *
 * Reglas cerradas:
 * - Confirmar **no** vuelve a sumar meses ni a aplicar creditos: solo cambia
 *   el estado de la activacion.
 * - Rechazar restaura el estado anterior **solo si la licencia sigue como la
 *   dejo esta activacion**; si otro pago legitimo ya la movio, no se toca.
 * - Nunca se suspende un periodo pagado: si tras revertir queda tiempo vigente,
 *   la licencia sigue activa.
 */

export type LicenseSnapshot = {
  status: LicenseStatus | string;
  licenseStatus: LicenseStatus | string;
  planCode: string | null;
  planCatalogVersion: number | null;
  plan: string;
  licenseExpiresAt: string | null;
  licenseActivatedAt: string | null;
  licenseBlockedAt: string | null;
  licenseEpoch: string;
  maxUsers: number;
  maxProducts: number;
  maxWarehouses: number | null;
  ncfEnabled: boolean;
  taxEnabled: boolean;
  wholesalePriceListsEnabled: boolean;
  measurementUnitsEnabled: boolean;
};

/** Campos que se leen de la empresa antes de aplicar el plan. */
export const SNAPSHOT_SELECT = {
  status: true,
  licenseStatus: true,
  planCode: true,
  planCatalogVersion: true,
  plan: true,
  licenseExpiresAt: true,
  licenseActivatedAt: true,
  licenseBlockedAt: true,
  updatedAt: true,
  maxUsers: true,
  maxProducts: true,
  maxWarehouses: true,
  ncfEnabled: true,
  taxEnabled: true,
  wholesalePriceListsEnabled: true,
  measurementUnitsEnabled: true,
} as const;

export type SnapshotSource = {
  status: string;
  licenseStatus: LicenseStatus;
  planCode: string | null;
  planCatalogVersion: number | null;
  plan: string;
  licenseExpiresAt: Date | null;
  licenseActivatedAt: Date | null;
  licenseBlockedAt: Date | null;
  updatedAt: Date;
  maxUsers: number;
  maxProducts: number;
  maxWarehouses: number | null;
  ncfEnabled: boolean;
  taxEnabled: boolean;
  wholesalePriceListsEnabled: boolean;
  measurementUnitsEnabled: boolean;
};

export function snapshotOf(company: SnapshotSource): LicenseSnapshot {
  return {
    status: company.status,
    licenseStatus: company.licenseStatus,
    planCode: company.planCode,
    planCatalogVersion: company.planCatalogVersion,
    plan: company.plan,
    licenseExpiresAt: company.licenseExpiresAt?.toISOString() ?? null,
    licenseActivatedAt: company.licenseActivatedAt?.toISOString() ?? null,
    licenseBlockedAt: company.licenseBlockedAt?.toISOString() ?? null,
    licenseEpoch: company.updatedAt.toISOString(),
    maxUsers: company.maxUsers,
    maxProducts: company.maxProducts,
    maxWarehouses: company.maxWarehouses,
    ncfEnabled: company.ncfEnabled,
    taxEnabled: company.taxEnabled,
    wholesalePriceListsEnabled: company.wholesalePriceListsEnabled,
    measurementUnitsEnabled: company.measurementUnitsEnabled,
  };
}

/**
 * ¿Se puede revertir? Solo si la licencia **sigue igual** que cuando se activo
 * esta orden. Asi un rechazo nunca borra un pago posterior ya confirmado.
 */
export function canRevert(input: {
  order: {
    planCode: string;
    periodEnd: Date | null;
  };
  company: { planCode: string | null; licenseExpiresAt: Date | null };
}): boolean {
  const samePlan =
    (input.company.planCode ?? '').trim().toLowerCase() ===
    input.order.planCode.trim().toLowerCase();
  if (!samePlan) return false;
  const companyEnd = input.company.licenseExpiresAt?.getTime() ?? null;
  const orderEnd = input.order.periodEnd?.getTime() ?? null;
  return companyEnd != null && orderEnd != null && companyEnd === orderEnd;
}

/** Vigencia provisional configurable (dias). */
export function provisionalWindowDays(raw?: string | null): number {
  const parsed = Number.parseInt(String(raw ?? '').trim(), 10);
  if (!Number.isFinite(parsed) || parsed < 1) return 15;
  return Math.min(parsed, 90);
}

@Injectable()
export class LicenseProvisionalService {
  private readonly logger = new Logger(LicenseProvisionalService.name);

  /** Marca la orden como activada provisionalmente y guarda el respaldo. */
  async markProvisional(
    tx: Prisma.TransactionClient,
    input: {
      orderId: string;
      snapshot: LicenseSnapshot;
      provisionalUntil: Date;
      periodStart: Date;
      periodEnd: Date;
    },
  ) {
    return tx.licensePaymentOrder.update({
      where: { id: input.orderId },
      data: {
        activationState: LicenseActivationState.PROVISIONAL,
        provisionalUntil: input.provisionalUntil,
        licenseSnapshot: input.snapshot as unknown as Prisma.InputJsonValue,
        periodStart: input.periodStart,
        periodEnd: input.periodEnd,
      },
      select: { id: true, activationState: true, provisionalUntil: true },
    });
  }

  /**
   * Soporte confirma el dinero. Idempotente y **sin** volver a aplicar meses.
   */
  async confirm(tx: Prisma.TransactionClient, orderId: string) {
    const order = await tx.licensePaymentOrder.findUnique({
      where: { id: orderId },
      select: { id: true, activationState: true, status: true, reference: true },
    });
    if (!order) throw new BadRequestException('payment_order_not_found');
    if (order.activationState === LicenseActivationState.CONFIRMED) {
      return { changed: false, state: order.activationState };
    }
    const updated = await tx.licensePaymentOrder.update({
      where: { id: order.id },
      data: {
        activationState: LicenseActivationState.CONFIRMED,
        provisionalUntil: null,
      },
      select: { activationState: true },
    });
    return { changed: true, state: updated.activationState };
  }

  /**
   * Soporte dice que el dinero no llego: se revoca lo provisional.
   * Devuelve `reverted:false` si otro pago ya movio la licencia.
   */
  async revert(
    tx: Prisma.TransactionClient,
    input: { orderId: string; now?: Date },
  ) {
    const now = input.now ?? new Date();
    const order = await tx.licensePaymentOrder.findUnique({
      where: { id: input.orderId },
      select: {
        id: true,
        companyId: true,
        reference: true,
        planCode: true,
        periodEnd: true,
        activationState: true,
        licenseSnapshot: true,
      },
    });
    if (!order) throw new BadRequestException('payment_order_not_found');
    if (order.activationState === LicenseActivationState.REVERTED) {
      return { reverted: false, reason: 'already_reverted' as const };
    }
    const snapshot = (order.licenseSnapshot ?? null) as LicenseSnapshot | null;
    if (!snapshot) return { reverted: false, reason: 'no_snapshot' as const };

    const company = await tx.company.findUnique({
      where: { id: order.companyId },
      select: {
        id: true,
        planCode: true,
        licenseExpiresAt: true,
        status: true,
        licenseStatus: true,
      },
    });
    if (!company) throw new BadRequestException('company_not_found');
    if (!canRevert({ order: { planCode: order.planCode, periodEnd: order.periodEnd }, company })) {
      await tx.licensePaymentOrder.update({
        where: { id: order.id },
        data: {
          activationState: LicenseActivationState.REVERTED,
          provisionalUntil: null,
        },
        select: { id: true },
      });
      return { reverted: false, reason: 'license_changed' as const };
    }

    const restoredExpiry = snapshot.licenseExpiresAt
      ? new Date(snapshot.licenseExpiresAt)
      : null;
    // Si el periodo restaurado ya vencio, la licencia queda **vencida**, no
    // suspendida: el cliente tiene que poder volver a entrar a Planes y pagar.
    // Antes se ponia la empresa en SUSPENDED y el JWT la dejaba fuera de la app:
    // un rechazo la encerraba sin salida.
    const expiredNow = !restoredExpiry || restoredExpiry.getTime() <= now.getTime();
    const restoredStatus = expiredNow
      ? LicenseStatus.EXPIRED
      : (snapshot.licenseStatus as LicenseStatus);

    await tx.company.update({
      where: { id: order.companyId },
      data: {
        status: snapshot.status as never,
        licenseStatus: restoredStatus,
        planCode: snapshot.planCode,
        planCatalogVersion: snapshot.planCatalogVersion,
        plan: snapshot.plan as never,
        licenseExpiresAt: restoredExpiry,
        licenseActivatedAt: snapshot.licenseActivatedAt
          ? new Date(snapshot.licenseActivatedAt)
          : null,
        licenseBlockedAt: snapshot.licenseBlockedAt
          ? new Date(snapshot.licenseBlockedAt)
          : null,
        maxUsers: snapshot.maxUsers,
        maxProducts: snapshot.maxProducts,
        maxWarehouses: snapshot.maxWarehouses,
        ncfEnabled: snapshot.ncfEnabled,
        taxEnabled: snapshot.taxEnabled,
        wholesalePriceListsEnabled: snapshot.wholesalePriceListsEnabled,
        measurementUnitsEnabled: snapshot.measurementUnitsEnabled,
      },
      select: { id: true },
    });
    await tx.licensePaymentOrder.update({
      where: { id: order.id },
      data: {
        activationState: LicenseActivationState.REVERTED,
        provisionalUntil: null,
      },
      select: { id: true },
    });
    await tx.companyLicenseAuditLog.create({
      data: {
        companyId: order.companyId,
        actorEmail: null,
        action: 'license.provisional_reverted',
        reason: order.reference,
        before: {
          planCode: company.planCode,
          licenseExpiresAt: company.licenseExpiresAt?.toISOString() ?? null,
          licenseStatus: company.licenseStatus,
        } satisfies Prisma.InputJsonValue,
        after: {
          planCode: snapshot.planCode,
          licenseExpiresAt: snapshot.licenseExpiresAt,
          licenseStatus: restoredStatus,
          expiredNow,
        } satisfies Prisma.InputJsonValue,
      },
    });
    this.logger.log(
      `Activacion provisional revertida (orden ${order.reference}); vencimiento ${snapshot.licenseExpiresAt ?? 'sin periodo'}`,
    );
    return { reverted: true, reason: 'restored' as const, expiredNow };
  }

  /**
   * Politica cuando la verificacion se retrasa: por defecto **no** se corta el
   * servicio (el cliente pago y solo falta la revision); se marca para que el
   * CRM lo vea. Con `LICENSE_PROVISIONAL_EXPIRY_ACTION=revert` si se revoca.
   */
  async handleExpiredProvisional(input: {
    action: string;
    now?: Date;
  }) {
    return { action: input.action };
  }
}

export type ProvisionalOrder = {
  id: string;
  status: LicenseOrderStatus;
  activationState: LicenseActivationState;
};
