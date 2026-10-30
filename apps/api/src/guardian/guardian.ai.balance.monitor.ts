import { Injectable, Logger } from '@nestjs/common';
import { guardianSecretValue } from './guardian.secret';
import { formatGuardianDateTime } from './guardian.time';
import { resolveGuardianWhatsAppProfile } from './guardian.whatsapp.config';
import {
  GuardianAlertPayload,
  HttpWebhookChannel,
  WhatsAppCloudChannel,
} from './guardian.alert.channels';
import { resolveGuardianAiRuntime } from './ai/guardian.ai.runtime';
import {
  GuardianAiBalanceSnapshot,
  describeBalanceState,
  isBalanceAlertState,
  probeDeepSeekBalance,
} from './ai/guardian.ai.balance';
import { resolveGuardianConfig } from './guardian.config';

export type GuardianAiBalanceNotification = {
  attempted: boolean;
  sent: boolean;
  channel: string | null;
  reason: string | null;
  recipients: number;
};

/**
 * Monitor del saldo de IA (DeepSeek) con aviso administrativo por WhatsApp.
 *
 * - Consulta el **endpoint oficial** de saldo; no consume tokens ni genera coste.
 * - Avisa al administrador de APPYRA (destinatarios centrales
 *   `GUARDIAN_ALERT_RECIPIENTS`) cuando el saldo está bajo, agotado, la
 *   facturación falla o el proveedor no responde, y también cuando se recupera.
 * - **Anti-ruido**: un aviso por estado cada `cooldownMinutes` (por defecto 6 h);
 *   el aviso de recuperación se envía una sola vez por transición.
 * - Si no hay canal utilizable, no se inventa un envío: se registra
 *   `channel=null` y el motivo real.
 *
 * El estado vive en memoria del proceso que ejecuta el ciclo (un único worker),
 * así que dos réplicas no duplican avisos.
 */
@Injectable()
export class GuardianAiBalanceMonitor {
  private readonly logger = new Logger(GuardianAiBalanceMonitor.name);
  private readonly lastNotifiedAt = new Map<string, number>();
  private lastState: string | null = null;
  private lastSnapshot: GuardianAiBalanceSnapshot | null = null;

  /** Última lectura conocida (sin consultar al proveedor). */
  getLastSnapshot(): GuardianAiBalanceSnapshot | null {
    return this.lastSnapshot;
  }

  /**
   * Consulta el saldo y, si hace falta, avisa. `notify=false` permite una
   * comprobación manual sin generar mensajes.
   */
  async check(options: { notify?: boolean } = {}): Promise<{
    snapshot: GuardianAiBalanceSnapshot;
    notification: GuardianAiBalanceNotification;
  }> {
    const config = resolveGuardianConfig();
    const runtime = resolveGuardianAiRuntime();
    const snapshot = await probeDeepSeekBalance({
      apiKey: guardianSecretValue(process.env, 'GUARDIAN_AI_API_KEY'),
      baseUrl: runtime.baseUrl,
      lowThreshold: config.aiBalanceLowThreshold,
    });
    this.lastSnapshot = snapshot;

    this.logger.log(
      `saldo IA estado=${snapshot.state} proveedor=${snapshot.provider} ` +
        `importe=${snapshot.totalBalance ?? 'n/d'} ${snapshot.currency ?? ''} umbral=${snapshot.lowThreshold ?? 'n/d'}`,
    );

    const notification: GuardianAiBalanceNotification = {
      attempted: false,
      sent: false,
      channel: null,
      reason: null,
      recipients: 0,
    };
    if (options.notify === false) {
      this.lastState = snapshot.state;
      return { snapshot, notification };
    }

    const recovery = snapshot.state === 'OK' && this.lastState !== null && this.lastState !== 'OK';
    const shouldAlert = isBalanceAlertState(snapshot.state) || recovery;
    if (!shouldAlert) {
      this.lastState = snapshot.state;
      return { snapshot, notification };
    }

    const cooldownKey = recovery ? 'RECOVERY' : snapshot.state;
    const cooldownMs = config.aiBalanceAlertCooldownMinutes * 60_000;
    const lastAt = this.lastNotifiedAt.get(cooldownKey) ?? 0;
    if (Date.now() - lastAt < cooldownMs) {
      notification.reason = `en espera de la ventana anti-ruido (${config.aiBalanceAlertCooldownMinutes} min)`;
      this.lastState = snapshot.state;
      return { snapshot, notification };
    }

    const delivered = await this.dispatch(
      recovery ? this.buildRecoveryMessage(snapshot) : this.buildAlertMessage(snapshot),
      recovery,
      snapshot,
    );
    notification.attempted = delivered.attempted;
    notification.sent = delivered.sent;
    notification.channel = delivered.channel;
    notification.reason = delivered.reason;
    notification.recipients = delivered.recipients;

    if (delivered.sent) {
      this.lastNotifiedAt.set(cooldownKey, Date.now());
    }
    this.lastState = snapshot.state;
    return { snapshot, notification };
  }

  /** Mensaje administrativo (texto) con los datos reales del proveedor. */
  buildAlertMessage(snapshot: GuardianAiBalanceSnapshot): string {
    const saldo =
      snapshot.totalBalance !== null
        ? `${snapshot.totalBalance} ${snapshot.currency ?? ''}`.trim()
        : 'no informado por el proveedor';
    return [
      `APPYRA GUARDIAN — IA ${describeBalanceState(snapshot.state).toUpperCase()}`,
      '',
      `Proveedor: DeepSeek`,
      `Estado: ${describeBalanceState(snapshot.state)}`,
      `Saldo informado: ${saldo}`,
      snapshot.lowThreshold !== null ? `Umbral de aviso: ${snapshot.lowThreshold}` : null,
      `Consultado: ${formatGuardianDateTime(new Date(snapshot.checkedAt))}`,
      snapshot.httpStatus !== null ? `HTTP: ${snapshot.httpStatus}` : null,
      snapshot.error ? `Detalle: ${snapshot.error}` : null,
      '',
      'Acción: revisar el saldo y la facturación de la cuenta de IA.',
      'El diagnóstico automático puede dejar de funcionar hasta regularizar el pago.',
      'No se modificó información de ningún cliente.',
    ]
      .filter((line) => line !== null)
      .join('\n');
  }

  /** Aviso único de recuperación. */
  buildRecoveryMessage(snapshot: GuardianAiBalanceSnapshot): string {
    const saldo =
      snapshot.totalBalance !== null
        ? `${snapshot.totalBalance} ${snapshot.currency ?? ''}`.trim()
        : 'no informado por el proveedor';
    return [
      'APPYRA GUARDIAN — IA RESTABLECIDA',
      '',
      'Proveedor: DeepSeek',
      'Estado: operativo',
      `Saldo informado: ${saldo}`,
      `Consultado: ${formatGuardianDateTime(new Date(snapshot.checkedAt))}`,
      '',
      'El diagnóstico automático vuelve a estar disponible.',
      'No se modificó información de ningún cliente.',
    ].join('\n');
  }

  private async dispatch(
    text: string,
    recovery: boolean,
    snapshot: GuardianAiBalanceSnapshot,
  ): Promise<GuardianAiBalanceNotification> {
    const profile = resolveGuardianWhatsAppProfile();
    const recipients = profile.adminRecipients;
    const dedupeKey = `ai-balance:${recovery ? 'recovery' : snapshot.state}:${snapshot.checkedAt.slice(0, 10)}`;

    if (recipients.length === 0) {
      this.logger.warn(
        `Saldo IA ${snapshot.state}: sin destinatarios administrativos configurados (GUARDIAN_ALERT_RECIPIENTS)`,
      );
      return {
        attempted: false,
        sent: false,
        channel: null,
        reason: 'ALERT_RECIPIENT_NOT_CONFIGURED',
        recipients: 0,
      };
    }

    const token = guardianSecretValue(process.env, 'GUARDIAN_WA_CLOUD_TOKEN');
    const phoneNumberId = String(process.env.GUARDIAN_WA_PHONE_NUMBER_ID ?? '').trim();
    const templateName = String(
      process.env.GUARDIAN_WA_BILLING_TEMPLATE_NAME ?? 'guardian_billing_alert',
    ).trim();
    const templateLanguage = String(process.env.GUARDIAN_WA_TEMPLATE_LANG ?? 'es').trim();

    if (token && phoneNumberId) {
      const channel = new WhatsAppCloudChannel({
        token,
        phoneNumberId,
        apiVersion: profile.sender.apiVersion,
        templateName,
        templateLanguage,
      });
      let sent = 0;
      let lastError: string | null = null;
      for (const to of recipients) {
        const payload: GuardianAlertPayload = {
          to,
          text,
          dedupeKey,
          allowOutsideBusinessHours: true,
          templateName,
          templateLanguage,
          // Contrato de la plantilla: estado, saldo, moneda y hora.
          templateParams: [
            describeBalanceState(snapshot.state),
            snapshot.totalBalance ?? 'n/d',
            snapshot.currency ?? 'n/d',
            formatGuardianDateTime(new Date(snapshot.checkedAt)),
          ],
        };
        const result = await channel.send(payload);
        if (result.ok) sent += 1;
        else lastError = result.error ?? `HTTP ${result.httpStatus ?? 'n/d'}`;
      }
      this.logger.log(`saldo IA ${snapshot.state}: avisos enviados=${sent}/${recipients.length}`);
      return {
        attempted: true,
        sent: sent > 0,
        channel: 'whatsapp_cloud',
        reason: sent > 0 ? null : lastError ?? 'envio rechazado por el proveedor',
        recipients: sent,
      };
    }

    const webhookUrl = String(process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL ?? '').trim();
    if (webhookUrl) {
      const channel = new HttpWebhookChannel({
        url: webhookUrl,
        secret: guardianSecretValue(process.env, 'GUARDIAN_ALERT_FALLBACK_WEBHOOK_SECRET'),
      });
      const result = await channel.send({
        to: 'admin',
        text,
        dedupeKey,
        allowOutsideBusinessHours: true,
      });
      return {
        attempted: true,
        sent: result.ok,
        channel: 'http_webhook',
        reason: result.ok ? null : result.error ?? 'webhook rechazo el aviso',
        recipients: result.ok ? 1 : 0,
      };
    }

    this.logger.warn(
      `Saldo IA ${snapshot.state}: no hay canal de WhatsApp ni webhook configurado para el aviso`,
    );
    return {
      attempted: false,
      sent: false,
      channel: null,
      reason: 'WHATSAPP_SENDER_NOT_CONFIGURED',
      recipients: 0,
    };
  }
}
