import { Controller, Post, Req, Res } from "@nestjs/common";
import type { Request, Response } from "express";
import { DosaWebhookService } from "./dosa-webhook.service";

/** Bandera de la ruta del webhook. Apagada por defecto. */
export function isDosaWebhookEndpointEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (env.DOSA_WEBHOOK_ENABLED ?? "").trim().toLowerCase() === "true";
}

/**
 * Endpoint del webhook de DOSA — **detrás de bandera y fail-closed**.
 *
 * Decisiones deliberadas:
 *
 * 1. **Nunca** responde `200 HTML`: si la ruta no está habilitada devuelve JSON
 *    con 503, y todas las respuestas son JSON con código explícito.
 * 2. Usa el `rawBody` que `main.ts` preserva byte a byte para `/webhook/`.
 * 3. No hay validación con `ValidationPipe`: el payload tiene campos que el
 *    proveedor decide y `forbidNonWhitelisted` lo rechazaría. La validación la
 *    hace `parseDosaWebhookPayload`, que falla cerrado.
 * 4. Read-only respecto al mundo: el servicio no llama a DOSA ni activa emisión.
 *
 * Ruta pública: `https://fullposcloud.fulltechrd.com/api/webhook/dosa` (el proxy
 * elimina `/api`). La variante sin `/api` (`/webhook/dosa`) también llega al
 * backend — verificado con tráfico real el 06/11/2026 —, pero la explícita es la
 * preferida.
 */
@Controller()
export class DosaWebhookController {
  constructor(private readonly service: DosaWebhookService) {}

  @Post("webhook/dosa")
  async receive(@Req() req: Request, @Res() res: Response): Promise<void> {
    if (!isDosaWebhookEndpointEnabled()) {
      res.status(503).json({
        accepted: false,
        code: "ECF_DOSA_WEBHOOK_DISABLED",
        reason: "ENDPOINT_DISABLED",
      });
      return;
    }

    const rawBody = (req as Request & { rawBody?: Buffer }).rawBody;
    const outcome = await this.service.handle({
      headers: req.headers as Record<string, string | string[] | undefined>,
      rawBody,
      body: req.body,
    });

    if (outcome.accepted) {
      res.status(outcome.status).json({
        accepted: true,
        duplicate: outcome.duplicate,
        eventId: outcome.eventId,
        code: outcome.code,
      });
      return;
    }

    res.status(outcome.status).json({
      accepted: false,
      code: outcome.code,
      reason: outcome.reason,
    });
  }
}
