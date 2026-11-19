import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { LicenseOrderStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { LicenseOrdersService } from '../orders/license-orders.service';
import {
  daysUntil,
  REMINDER_DAYS,
  renewalStateFor,
  shouldSendReminder,
} from '../renewal/license-renewal.policy';
import { LicenseNotifierService } from './license-notifier.service';

const MS_PER_DAY = 24 * 60 * 60 * 1000;
/** Estados en los que el cliente ya pago y espera verificacion. */
const REVIEW_STATUSES: LicenseOrderStatus[] = [
  LicenseOrderStatus.EVIDENCE_RECEIVED,
  LicenseOrderStatus.UNCONFIRMED,
];

@Injectable()
export class LicenseReminderScheduler {
  private readonly logger = new Logger(LicenseReminderScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifier: LicenseNotifierService,
    private readonly orders: LicenseOrdersService,
  ) {}

  /**
   * 9:00 en Republica Dominicana. Manda el aviso **una sola vez** por empresa
   * y periodo: la tabla `license_reminder_logs` es unica por
   * (empresa, nivel, vencimiento).
   */
  @Cron('0 9 * * *', { timeZone: 'America/Santo_Domingo' })
  async runDaily() {
    try {
      const summary = await this.runCheck(new Date());
      if (summary.queued > 0) {
        this.logger.log(
          `Recordatorios encolados: ${summary.queued} (revisadas ${summary.scanned})`,
        );
      }
    } catch (error) {
      this.logger.warn(`Recordatorios: ${describe(error)}`);
    }
  }

  /** Separado del cron para poder probarlo con una fecha fija. */
  async runCheck(now: Date) {
    const horizon = new Date(now.getTime() + 7 * MS_PER_DAY);
    const companies = await this.prisma.company.findMany({
      where: {
        status: 'ACTIVE',
        licenseStatus: 'ACTIVE',
        licenseExpiresAt: { gt: now, lte: horizon },
      },
      select: {
        id: true,
        name: true,
        planCode: true,
        licenseExpiresAt: true,
      },
    });

    let queued = 0;
    for (const company of companies) {
      const periodEnd = company.licenseExpiresAt;
      if (!periodEnd) continue;
      const days = daysUntil(periodEnd, now);
      // Si el cliente ya envio el comprobante, **no** se le reclama el pago:
      // esta esperando verificacion, no moroso.
      const inReview = await this.prisma.licensePaymentOrder.count({
        where: {
          companyId: company.id,
          status: { in: REVIEW_STATUSES },
        },
      });
      const state = renewalStateFor({
        now,
        periodEnd,
        paymentInReview: inReview > 0,
      });
      const decision = shouldSendReminder({
        state,
        daysLeft: days,
        reminderDays: REMINDER_DAYS,
      });
      if (!decision.send || !decision.kind) continue;
      const kind = decision.kind;
      const created = await this.claim(company.id, kind, periodEnd);
      if (!created) continue;

      const plan = company.planCode
        ? await this.prisma.licensePlan.findUnique({
            where: { code: company.planCode },
            select: { name: true },
          })
        : null;
      const order = await this.orders.ensureOpenOrder({
        companyId: company.id,
        planCode: company.planCode,
      });
      await this.notifier.enqueue({
        companyId: company.id,
        kind,
        payload: {
          planCode: company.planCode,
          planName: plan?.name ?? null,
          companyName: company.name,
          periodEnd: periodEnd.toISOString(),
          reference: order?.reference ?? null,
        },
      });
      queued += 1;
    }
    return { scanned: companies.length, queued };
  }

  /** true si este aviso no se habia enviado para este periodo. */
  private async claim(
    companyId: string,
    kind: 'REMINDER_5D' | 'REMINDER_1D',
    periodEnd: Date,
  ) {
    try {
      await this.prisma.licenseReminderLog.create({
        data: { companyId, kind, periodEndSnapshot: periodEnd, status: 'PENDING' },
        select: { id: true },
      });
      return true;
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        return false;
      }
      throw error;
    }
  }
}

function describe(error: unknown) {
  if (error instanceof Error) return error.message.slice(0, 300);
  return 'unknown-error';
}
