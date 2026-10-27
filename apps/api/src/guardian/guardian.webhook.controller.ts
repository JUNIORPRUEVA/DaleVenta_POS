import { Controller, Get, HttpCode, Post, Query, Req, Res } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { Request, Response } from 'express';
import { GuardianAlertService } from './guardian.alert.service';
import { mapMetaStatus } from './guardian.alert.delivery';
import { resolveGuardianWhatsAppProfile } from './guardian.whatsapp.config';

/**
 * Webhook de estados de WhatsApp Cloud API (Meta).
 *
 * Seguridad:
 * - Verificación GET con `hub.verify_token` (`GUARDIAN_WA_VERIFY_TOKEN`).
 * - POST con firma `X-Hub-Signature-256` (HMAC SHA-256 del cuerpo CRUDO).
 * - Sin `GUARDIAN_WA_APP_SECRET` configurado se rechaza (fail-closed).
 * - Solo se procesan estados del Phone Number ID propio: un webhook de otra
 *   WABA no puede alterar alertas de APPYRA.
 */
@Controller('guardian/webhooks')
export class GuardianWebhookController {
  constructor(private readonly alerts: GuardianAlertService) {}

  @Get('whatsapp')
  verify(
    @Query('hub.mode') mode?: string,
    @Query('hub.verify_token') token?: string,
    @Query('hub.challenge') challenge?: string,
    @Res() res?: Response,
  ) {
    const expected = String(process.env.GUARDIAN_WA_VERIFY_TOKEN ?? '').trim();
    if (!expected || mode !== 'subscribe' || String(token ?? '').trim() !== expected) {
      return res!.status(403).json({ ok: false });
    }
    return res!.status(200).send(String(challenge ?? ''));
  }

  @Post('whatsapp')
  @HttpCode(200)
  async receive(@Req() req: Request, @Res() res: Response) {
    const secret = String(process.env.GUARDIAN_WA_APP_SECRET ?? '').trim();
    const raw = (req as Request & { rawBody?: Buffer }).rawBody;
    const signature = String(req.header('x-hub-signature-256') ?? '').trim();

    if (!secret) {
      return res.status(503).json({ ok: false, reason: 'WEBHOOK_NOT_CONFIGURED' });
    }
    if (!raw || !signature) {
      return res.status(401).json({ ok: false, reason: 'SIGNATURE_REQUIRED' });
    }

    const expected = `sha256=${createHmac('sha256', secret).update(raw).digest('hex')}`;
    const expectedBuffer = Buffer.from(expected);
    const providedBuffer = Buffer.from(signature);
    const valid =
      expectedBuffer.length === providedBuffer.length && timingSafeEqual(expectedBuffer, providedBuffer);

    if (!valid) {
      return res.status(401).json({ ok: false, reason: 'INVALID_SIGNATURE' });
    }

    let payload: any = null;
    try {
      payload = JSON.parse(raw.toString('utf8'));
    } catch {
      return res.status(400).json({ ok: false, reason: 'INVALID_JSON' });
    }

    const results: Array<{ id: string; status: string; updated: number }> = [];
    const profile = resolveGuardianWhatsAppProfile();
    const configuredPhoneId = profile.sender.phoneNumberId;
    // `entry[].id` de Meta es el **WABA ID**, no el Phone Number ID: compararlo
    // contra el número descartaba todos los eventos reales. El filtro por número
    // se aplica en `value.metadata.phone_number_id`, que es el campo correcto.
    const configuredWabaId = profile.sender.wabaId;
    let ignored = 0;

    for (const entry of payload?.entry ?? []) {
      const entryId = entry?.id ? String(entry.id) : '';
      if (configuredWabaId && entryId && entryId !== configuredWabaId) {
        ignored += 1;
        continue;
      }
      for (const change of entry?.changes ?? []) {
        const metadataPhoneId = change?.value?.metadata?.phone_number_id;
        if (configuredPhoneId && metadataPhoneId && String(metadataPhoneId) !== configuredPhoneId) {
          ignored += 1;
          continue;
        }

        for (const status of change?.value?.statuses ?? []) {
          const mapped = mapMetaStatus(status?.status);
          if (mapped === 'unknown') {
            // Estados no relacionados con entrega: se confirman sin tocar la alerta.
            ignored += 1;
            continue;
          }
          const providerError =
            status?.errors?.[0]?.message ?? status?.errors?.[0]?.title ?? null;
          const outcome = await this.alerts.markDelivery(
            String(status.id ?? ''),
            mapped,
            providerError ? String(providerError) : null,
          );
          results.push({ id: String(status.id ?? ''), status: mapped, updated: outcome.updated });
        }
      }
    }

    return res.status(200).json({ ok: true, processed: results.length, ignored, results });
  }
}
