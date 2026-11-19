import { Injectable } from '@nestjs/common';
import { LicenseOrderStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import {
  daysUntil,
  NEXT_DUE_WINDOW_DAYS,
  renewalStateFor,
  type RenewalState,
} from './license-renewal.policy';

export type RenewalOrderInfo = {
  id: string;
  reference: string;
  amount: number;
  currency: string;
  status: LicenseOrderStatus;
  months: number;
  expiresAt: Date;
};

export type RenewalSnapshot = {
  state: RenewalState;
  /** Vencimiento del periodo pagado. */
  dueDate: Date | null;
  daysLeft: number | null;
  /** Importe de la proxima cuota (o de la orden abierta, si ya existe). */
  amount: number | null;
  currency: string;
  planCode: string | null;
  planName: string | null;
  /** Dias de antelacion con los que aparece la cuota. */
  windowDays: number;
  /** Orden abierta o en revision, si la hay. */
  order: RenewalOrderInfo | null;
};

const OPEN_STATUSES: LicenseOrderStatus[] = [
  LicenseOrderStatus.CREATED,
  LicenseOrderStatus.AWAITING_TRANSFER,
  LicenseOrderStatus.EVIDENCE_RECEIVED,
  LicenseOrderStatus.UNCONFIRMED,
];

const REVIEW_STATUSES: LicenseOrderStatus[] = [
  LicenseOrderStatus.EVIDENCE_RECEIVED,
  LicenseOrderStatus.UNCONFIRMED,
];

/**
 * Estado de la proxima cuota. **No** crea nada: solo lee.
 *
 * La orden la genera el cliente al pulsar «Pagar ahora» (o el recordatorio,
 * que reutiliza la que ya exista). Asi el estado de la pantalla nunca deja
 * ordenes huerfanas ni dos verdades sobre el mismo periodo.
 */
@Injectable()
export class LicenseRenewalService {
  constructor(private readonly prisma: PrismaService) {}

  async snapshot(
    companyId: string,
    now: Date = new Date(),
    db: PrismaService | Prisma.TransactionClient = this.prisma,
  ): Promise<RenewalSnapshot> {
    const company = await db.company.findUnique({
      where: { id: companyId },
      select: {
        planCode: true,
        licenseStatus: true,
        licenseExpiresAt: true,
      },
    });
    const periodEnd = company?.licenseExpiresAt ?? null;

    const [plan, order] = await Promise.all([
      company?.planCode
        ? db.licensePlan.findUnique({
            where: { code: company.planCode.trim().toLowerCase() },
            select: { code: true, name: true, monthlyPrice: true, currency: true },
          })
        : Promise.resolve(null),
      db.licensePaymentOrder.findFirst({
        where: {
          companyId,
          status: { in: OPEN_STATUSES },
          expiresAt: { gt: now },
        },
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          reference: true,
          amount: true,
          currency: true,
          status: true,
          months: true,
          expiresAt: true,
        },
      }),
      ]);

    const paymentInReview =
      !!order && REVIEW_STATUSES.includes(order.status);
    const state = renewalStateFor({ now, periodEnd, paymentInReview });
    const daysLeft = periodEnd ? daysUntil(periodEnd, now) : null;
    const fallbackAmount = plan ? plan.monthlyPrice.toNumber() : null;

    return {
      state,
      dueDate: periodEnd,
      daysLeft,
      // Si ya hay una orden abierta manda su importe: es lo que el cliente
      // tiene delante para transferir.
      amount: order ? order.amount.toNumber() : fallbackAmount,
      currency: order?.currency ?? plan?.currency ?? 'DOP',
      planCode: plan?.code ?? company?.planCode ?? null,
      planName: plan?.name ?? null,
      windowDays: NEXT_DUE_WINDOW_DAYS,
      order: order
        ? {
            id: order.id,
            reference: order.reference,
            amount: order.amount.toNumber(),
            currency: order.currency,
            status: order.status,
            months: order.months,
            expiresAt: order.expiresAt,
          }
        : null,
    };
  }
}
