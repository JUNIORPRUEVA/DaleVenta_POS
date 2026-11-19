import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron } from '@nestjs/schedule';
import { LicenseActivationState, LicenseOrderStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { LicenseProvisionalService } from './license-provisional.service';

/**
 * Politica de vigencia de la activacion provisional.
 *
 * `LICENSE_PROVISIONAL_DAYS` (1..90, por defecto 15) decide cuanto tiempo puede
 * estar una activacion sin verificar. Al cumplirse:
 *
 * - `LICENSE_PROVISIONAL_EXPIRY_ACTION=keep` (por defecto): el servicio
 *   **continua** (el cliente pago y solo falta la revision) y la orden queda
 *   marcada `EXPIRED_REVIEW` para que el CRM la priorice.
 * - `LICENSE_PROVISIONAL_EXPIRY_ACTION=revert`: se revoca como si se hubiera
 *   rechazado. Solo se usa si el negocio decide cortar al vencer.
 */
@Injectable()
export class LicenseProvisionalScheduler {
  private readonly logger = new Logger(LicenseProvisionalScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly provisional: LicenseProvisionalService,
    private readonly config: ConfigService,
  ) {}

  private action() {
    const raw = String(
      this.config.get<string>('LICENSE_PROVISIONAL_EXPIRY_ACTION') ?? '',
    )
      .trim()
      .toLowerCase();
    return raw === 'revert' ? 'revert' : 'keep';
  }

  @Cron('30 6 * * *', { timeZone: 'America/Santo_Domingo' })
  async runDaily() {
    try {
      const summary = await this.runCheck(new Date());
      if (summary.reviewed > 0) {
        this.logger.warn(
          `Activaciones provisionales vencidas: ${summary.reviewed} (${summary.action})`,
        );
      }
    } catch (error) {
      this.logger.warn(
        `Revision de activaciones provisionales: ${error instanceof Error ? error.message : 'error'}`,
      );
    }
  }

  /** Separado del cron para poder probarlo con una fecha fija. */
  async runCheck(now: Date) {
    const action = this.action();
    const orders = await this.prisma.licensePaymentOrder.findMany({
      where: {
        activationState: LicenseActivationState.PROVISIONAL,
        provisionalUntil: { lt: now },
        status: {
          in: [LicenseOrderStatus.UNCONFIRMED, LicenseOrderStatus.EVIDENCE_RECEIVED],
        },
      },
      select: { id: true, companyId: true, reference: true },
      take: 200,
    });

    let reverted = 0;
    for (const order of orders) {
      if (action === 'revert') {
        const result = await this.prisma.$transaction((tx) =>
          this.provisional.revert(tx, { orderId: order.id, now }),
        );
        if (result.reverted) reverted += 1;
        continue;
      }
      // Sin corte: se deja constancia para que soporte lo vea en el CRM.
      await this.prisma.licensePaymentOrder.update({
        where: { id: order.id },
        data: { activationState: LicenseActivationState.EXPIRED_REVIEW },
        select: { id: true },
      });
      await this.prisma.companyLicenseAuditLog.create({
        data: {
          companyId: order.companyId,
          actorEmail: null,
          action: 'license.provisional_expired_review',
          reason: order.reference,
          after: {
            reference: order.reference,
            action,
          } satisfies Prisma.InputJsonValue,
        },
      });
    }
    return { reviewed: orders.length, reverted, action };
  }
}
