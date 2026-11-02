import { Injectable } from "@nestjs/common";
import { readDosaWebhookEnvelope } from "./dosa-webhook.contract";
import { verifyDosaSignature } from "./dosa-webhook.verification";

/**
 * Resultado de intentar recibir un evento.
 *
 * Mientras el contrato de firma esté bloqueado solo existe una respuesta
 * posible: `rejected`. El tipo deja sitio al futuro `accepted`, pero hoy sería
 * imposible construirlo sin cambiar el estado del contrato.
 */
export type DosaWebhookOutcome =
  | { accepted: false; status: number; code: string; reason: string }
  | { accepted: true; eventId: string | null; eventType: string | null };

/**
 * Recepción de eventos DOSA — **desactivada por contrato**.
 *
 * Garantías deliberadas de esta etapa:
 *
 * 1. **No persiste nada.** No hay tabla, no hay escritura, no hay `prisma`.
 * 2. **No autentica nada.** La verificación de firma falla cerrado (ver
 *    `dosa-webhook.verification.ts`).
 * 3. **No activa emisión.** Ni siquiera en el futuro: un evento es evidencia,
 *    nunca autorización fiscal. La habilitación de emisión exige acto humano y
 *    compuertas fiscales del backend.
 * 4. **No filtra detalles.** La respuesta no revela el cálculo, el secreto ni
 *    el contenido del cuerpo.
 *
 * No hay controlador HTTP registrado para este servicio. Se deja inyectable para
 * poder cablearlo en la fase en la que DOSA entregue la fórmula de firma.
 */
@Injectable()
export class DosaWebhookReceiverService {
  /**
   * Punto de entrada único. Devuelve siempre `accepted: false` mientras el
   * contrato no esté resuelto.
   */
  receive(input: {
    headers: Record<string, string | string[] | undefined>;
    rawBody: Buffer | string | undefined;
    body: unknown;
  }): DosaWebhookOutcome {
    const verification = verifyDosaSignature({
      headers: input.headers,
      rawBody: input.rawBody,
    });
    if (!verification.ok) {
      return {
        accepted: false,
        // 503: el endpoint existe pero no está en condiciones de aceptar. Un
        // 2xx haría que DOSA diera por entregado un evento que no procesamos.
        status: 503,
        code: "ECF_DOSA_WEBHOOK_BLOCKED",
        reason: verification.reason,
      };
    }

    const envelope = readDosaWebhookEnvelope(input.body);
    if (!envelope.ok) {
      return {
        accepted: false,
        status: 400,
        code: "ECF_DOSA_WEBHOOK_INVALID_PAYLOAD",
        reason: envelope.reason,
      };
    }

    // Inalcanzable hoy: la verificación nunca devuelve `ok`. Se mantiene para
    // que el día que el contrato se resuelva el flujo sea explícito y revisable,
    // y para que el compilador obligue a tratarlo.
    return {
      accepted: true,
      eventId: envelope.envelope.eventId,
      eventType: envelope.envelope.eventType,
    };
  }
}
