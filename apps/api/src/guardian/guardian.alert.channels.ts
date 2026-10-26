import { createHash } from 'node:crypto';

export type GuardianAlertPayload = {
  to: string;
  text: string;
  dedupeKey: string;
  allowOutsideBusinessHours: boolean;
  templateName?: string;
  /** Parámetros posicionales del cuerpo de la plantilla HSM. */
  templateParams?: string[];
};

export type GuardianChannelClassification = 'transient' | 'permanent';

export type GuardianChannelResult = {
  ok: boolean;
  providerMessageId?: string;
  httpStatus?: number;
  error?: string;
  classification?: GuardianChannelClassification;
};

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
        language: { code: String(this.options.templateLanguage ?? 'es').trim() || 'es' },
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
        return {
          ok: false,
          httpStatus: response.status,
          error: bodyText.slice(0, 400) || `HTTP ${response.status}`,
          classification: classifyHttpStatus(response.status),
        };
      }

      let providerMessageId: string | undefined;
      try {
        const parsed = JSON.parse(bodyText);
        providerMessageId = parsed?.messages?.[0]?.id ? String(parsed.messages[0].id) : undefined;
      } catch {
        providerMessageId = undefined;
      }

      return { ok: true, httpStatus: response.status, providerMessageId };
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

      return { ok: true, httpStatus: response.status, providerMessageId: 'webhook-accepted' };
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
      return { ok: true, providerMessageId: `outbox:${row.id}` };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message.slice(0, 400) : String(error),
        classification: 'transient',
      };
    }
  }
}
