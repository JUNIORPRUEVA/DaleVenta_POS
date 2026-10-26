import { createHash } from 'node:crypto';

export type GuardianAlertPayload = {
  to: string;
  text: string;
  dedupeKey: string;
  allowOutsideBusinessHours: boolean;
  templateName?: string;
  /** Idioma de la plantilla (`es`, `es_DO`, `en_US`…). */
  templateLanguage?: string;
  /** Parámetros posicionales del cuerpo de la plantilla HSM. */
  templateParams?: string[];
};

export type GuardianChannelClassification = 'transient' | 'permanent';

/**
 * Evidencia real del envío, tal como la puede demostrar cada capa:
 * - `accepted`: el proveedor devolvió un identificador de mensaje.
 * - `queued`: la alerta solo quedó en una cola local; ningún proveedor la ha visto.
 * - `sent`: hubo respuesta correcta sin identificador (significado histórico de SENT).
 */
export type GuardianChannelAcceptance = 'accepted' | 'queued' | 'sent';

export type GuardianChannelResult = {
  ok: boolean;
  providerMessageId?: string;
  httpStatus?: number;
  error?: string;
  classification?: GuardianChannelClassification;
  acceptance?: GuardianChannelAcceptance;
  /** Espera indicada por el proveedor (`Retry-After`) cuando aplica. */
  retryAfterMs?: number;
};

/**
 * Interpreta `Retry-After` (segundos o fecha HTTP) con un límite superior para
 * que un proveedor no pueda aparcar una alerta crítica durante horas.
 */
export function parseRetryAfterMs(raw: unknown, now = Date.now(), maxMs = 15 * 60_000): number | undefined {
  const value = String(raw ?? '').trim();
  if (!value) return undefined;

  if (/^\d+$/.test(value)) {
    const seconds = Number.parseInt(value, 10);
    if (!Number.isFinite(seconds) || seconds <= 0) return undefined;
    return Math.min(maxMs, seconds * 1_000);
  }

  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return undefined;
  const delta = timestamp - now;
  if (delta <= 0) return undefined;
  return Math.min(maxMs, delta);
}

/**
 * Traduce un error de Meta a un motivo accionable y estable.
 * No se registra el cuerpo completo de la respuesta (puede contener datos del
 * destinatario); solo el código y una descripción acotada.
 */
export function describeMetaError(httpStatus: number, bodyText: string): string {
  const KNOWN: Record<number, string> = {
    190: 'token de acceso inválido o expirado',
    100: 'parámetro inválido en la petición',
    131000: 'error genérico de Meta',
    131026: 'el destinatario no puede recibir mensajes (sin WhatsApp o ventana cerrada)',
    131047: 'fuera de la ventana de 24 h: se requiere plantilla aprobada',
    131051: 'tipo de mensaje no soportado',
    132000: 'la plantilla no está aprobada o no existe',
    132001: 'la plantilla aún no existe en el idioma solicitado',
    133010: 'el número de teléfono no está registrado en la WABA',
  };

  let code: number | undefined;
  let message = '';
  try {
    const parsed = JSON.parse(bodyText);
    code = Number(parsed?.error?.code ?? Number.NaN);
    message = String(parsed?.error?.message ?? '').slice(0, 160);
  } catch {
    message = bodyText.slice(0, 160);
  }

  if (Number.isFinite(code) && KNOWN[code!]) {
    return `HTTP ${httpStatus} (${code}): ${KNOWN[code!]}`;
  }
  if (Number.isFinite(code)) {
    return `HTTP ${httpStatus} (${code}): ${message || 'error del proveedor'}`;
  }
  return `HTTP ${httpStatus}: ${message || 'error del proveedor'}`;
}

export interface GuardianAlertChannel {
  readonly name: string;
  isConfigured(): boolean;
  send(payload: GuardianAlertPayload): Promise<GuardianChannelResult>;
}

export function hashRecipient(value: string): string {
  return createHash('sha256').update(String(value ?? '').trim()).digest('hex').slice(0, 40);
}

function classifyHttpStatus(status: number): GuardianChannelClassification {
  if (status === 429 || status >= 500 || status === 0) return 'transient';
  return 'permanent';
}

/**
 * WhatsApp Cloud API (Meta, canal oficial).
 *
 * Requiere `GUARDIAN_WA_CLOUD_TOKEN` y `GUARDIAN_WA_PHONE_NUMBER_ID`.
 * Sin credenciales no está configurado y el servicio usa el siguiente canal.
 */
export class WhatsAppCloudChannel implements GuardianAlertChannel {
  readonly name = 'whatsapp_cloud';

  constructor(
    private readonly options: {
      token: string;
      phoneNumberId: string;
      apiVersion?: string;
      templateName?: string;
      templateLanguage?: string;
      timeoutMs?: number;
      fetchImpl?: typeof fetch;
    },
  ) {}

  isConfigured(): boolean {
    return this.options.token.trim().length > 0 && this.options.phoneNumberId.trim().length > 0;
  }

  /**
   * Meta exige una plantilla aprobada para mensajes iniciados por el negocio
   * fuera de la ventana de 24 h. Las alertas administrativas son siempre
   * iniciadas por el negocio, así que la plantilla es la vía correcta.
   */
  private buildBody(payload: GuardianAlertPayload) {
    const templateName = String(payload.templateName ?? this.options.templateName ?? '').trim();
    const to = payload.to.replace(/[^0-9]/g, '');

    if (!templateName) {
      return {
        messaging_product: 'whatsapp',
        to,
        type: 'text',
        text: { preview_url: false, body: payload.text },
      };
    }

    const params = (payload.templateParams ?? []).map((value) => ({
      type: 'text',
      text: String(value ?? '').slice(0, 400),
    }));

    return {
      messaging_product: 'whatsapp',
      to,
      type: 'template',
      template: {
        name: templateName,
        language: {
          code:
            String(payload.templateLanguage ?? this.options.templateLanguage ?? 'es').trim() || 'es',
        },
        ...(params.length ? { components: [{ type: 'body', parameters: params }] } : {}),
      },
    };
  }

  async send(payload: GuardianAlertPayload): Promise<GuardianChannelResult> {
    if (!this.isConfigured()) {
      return { ok: false, error: 'whatsapp_cloud no configurado', classification: 'permanent' };
    }

    const fetchImpl = this.options.fetchImpl ?? fetch;
    const version = this.options.apiVersion ?? 'v21.0';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 12_000);

    try {
      const response = await fetchImpl(
        `https://graph.facebook.com/${version}/${encodeURIComponent(this.options.phoneNumberId)}/messages`,
        {
          method: 'POST',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${this.options.token}`,
          },
          body: JSON.stringify(this.buildBody(payload)),
        },
      );

      const bodyText = await response.text().catch(() => '');
      if (!response.ok) {
        const retryAfterMs = parseRetryAfterMs(
          typeof response.headers?.get === 'function' ? response.headers.get('retry-after') : null,
        );
        return {
          ok: false,
          httpStatus: response.status,
          error: describeMetaError(response.status, bodyText),
          classification: classifyHttpStatus(response.status),
          ...(retryAfterMs ? { retryAfterMs } : {}),
        };
      }

      let providerMessageId: string | undefined;
      try {
        const parsed = JSON.parse(bodyText);
        providerMessageId = parsed?.messages?.[0]?.id ? String(parsed.messages[0].id) : undefined;
      } catch {
        providerMessageId = undefined;
      }

      // Un 200 con `messages[].id` significa aceptado por Meta, no entregado.
      return {
        ok: true,
        httpStatus: response.status,
        providerMessageId,
        acceptance: providerMessageId ? 'accepted' : 'sent',
      };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message.slice(0, 400) : String(error),
        classification: 'transient',
      };
    } finally {
      clearTimeout(timeout);
    }
  }
}

/**
 * Canal de respaldo independiente del proveedor de WhatsApp.
 * Un POST JSON a un webhook propio (relay de correo, Telegram, Slack, etc.).
 */
export class HttpWebhookChannel implements GuardianAlertChannel {
  readonly name = 'http_webhook';

  constructor(
    private readonly options: {
      url: string;
      secret?: string;
      timeoutMs?: number;
      fetchImpl?: typeof fetch;
    },
  ) {}

  isConfigured(): boolean {
    return this.options.url.trim().length > 0;
  }

  async send(payload: GuardianAlertPayload): Promise<GuardianChannelResult> {
    if (!this.isConfigured()) {
      return { ok: false, error: 'webhook no configurado', classification: 'permanent' };
    }

    const fetchImpl = this.options.fetchImpl ?? fetch;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 12_000);

    try {
      const response = await fetchImpl(this.options.url, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          ...(this.options.secret ? { 'x-guardian-secret': this.options.secret } : {}),
        },
        body: JSON.stringify({
          dedupeKey: payload.dedupeKey,
          to: payload.to,
          text: payload.text,
          source: 'appyra-guardian',
        }),
      });

      const bodyText = await response.text().catch(() => '');
      if (!response.ok) {
        return {
          ok: false,
          httpStatus: response.status,
          error: bodyText.slice(0, 400) || `HTTP ${response.status}`,
          classification: classifyHttpStatus(response.status),
        };
      }

      return {
        ok: true,
        httpStatus: response.status,
        // Id único por alerta: un identificador constante haría que un acuse de
        // entrega se aplicara a la primera alerta encontrada, no a la suya.
        providerMessageId: `webhook:${createHash('sha256')
          .update(String(payload.dedupeKey ?? ''))
          .digest('hex')
          .slice(0, 24)}`,
        // El relay confirmó la recepción del payload, no la entrega al humano.
        acceptance: 'accepted',
      };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message.slice(0, 400) : String(error),
        classification: 'transient',
      };
    } finally {
      clearTimeout(timeout);
    }
  }
}

/**
 * Canal Evolution: reutiliza `notification_outbox` (transporte ya probado).
 * Guardian solo encola; el despachador existente hace los reintentos.
 */
export class EvolutionOutboxChannel implements GuardianAlertChannel {
  readonly name = 'whatsapp_evolution';

  constructor(
    private readonly options: {
      enqueue: (input: {
        toNumber: string;
        messageText: string;
        dedupeKey: string;
        allowOutsideBusinessHours: boolean;
      }) => Promise<{ id: string }>;
      enabled: () => boolean;
    },
  ) {}

  isConfigured(): boolean {
    return this.options.enabled();
  }

  async send(payload: GuardianAlertPayload): Promise<GuardianChannelResult> {
    if (!this.isConfigured()) {
      return { ok: false, error: 'evolution deshabilitado', classification: 'permanent' };
    }
    try {
      const row = await this.options.enqueue({
        toNumber: payload.to,
        messageText: payload.text,
        dedupeKey: payload.dedupeKey,
        allowOutsideBusinessHours: true,
      });
      return {
        ok: true,
        providerMessageId: `outbox:${row.id}`,
        // Encolar en el outbox local NO es enviar: el despachador puede fallar.
        acceptance: 'queued',
      };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message.slice(0, 400) : String(error),
        classification: 'transient',
      };
    }
  }
}
