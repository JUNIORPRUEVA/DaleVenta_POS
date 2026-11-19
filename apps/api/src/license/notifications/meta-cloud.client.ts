import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export type MetaCloudConfig = {
  token: string;
  phoneNumberId: string;
  version: string;
  language: string;
};

export type MetaSendResult =
  | { ok: true; messageId: string | null; dryRun?: boolean }
  | { ok: false; error: string; status?: number };

export type MetaMediaResult =
  | { ok: true; mediaId: string }
  | { ok: false; error: string; status?: number };

const DEFAULT_VERSION = 'v21.0';
const DEFAULT_LANGUAGE = 'es';
const TIMEOUT_MS = 12_000;

/**
 * Cliente minimo de WhatsApp **Cloud API oficial** (sin Evolution API ni
 * proveedores intermedios). No lanza excepciones: devuelve `ok:false` para que
 * un fallo de WhatsApp nunca tumbe una licencia.
 */
@Injectable()
export class MetaCloudClient {
  private readonly logger = new Logger(MetaCloudClient.name);

  constructor(private readonly config: ConfigService) {}

  readConfig(): MetaCloudConfig {
    return {
      // Se reutiliza la integracion ya existente: FullPOS -> Guardian ->
      // cuenta compartida de WhatsApp Business (`WHATSAPP_*`).
      token:
        this.read('LICENSE_WA_TOKEN') ||
        this.read('GUARDIAN_WA_CLOUD_TOKEN') ||
        this.read('WHATSAPP_ACCESS_TOKEN'),
      phoneNumberId:
        this.read('LICENSE_WA_PHONE_NUMBER_ID') ||
        this.read('GUARDIAN_WA_PHONE_NUMBER_ID') ||
        this.read('WHATSAPP_PHONE_NUMBER_ID'),
      version:
        this.read('LICENSE_WA_VERSION') ||
        this.read('GUARDIAN_WA_VERSION') ||
        DEFAULT_VERSION,
      language:
        this.read('LICENSE_WA_TEMPLATE_LANG') ||
        this.read('GUARDIAN_WA_TEMPLATE_LANG') ||
        DEFAULT_LANGUAGE,
    };
  }

  /** Con `LICENSE_WA_DRY_RUN=true` se prepara el mensaje sin enviarlo. */
  isDryRun() {
    return this.read('LICENSE_WA_DRY_RUN') === 'true';
  }

  isConfigured() {
    const cfg = this.readConfig();
    return !!(cfg.token && cfg.phoneNumberId);
  }

  /** Numero del administrador que recibe los comprobantes. */
  adminRecipient() {
    const raw =
      this.read('LICENSE_ADMIN_WHATSAPP') ||
      this.read('GUARDIAN_WA_ADMIN_TO') ||
      '18093987826';
    return normalizePhone(raw);
  }

  async uploadMedia(input: {
    buffer: Buffer;
    mime: string;
    fileName: string;
  }): Promise<MetaMediaResult> {
    const cfg = this.readConfig();
    if (!cfg.token || !cfg.phoneNumberId) {
      return { ok: false, error: 'whatsapp-not-configured' };
    }
    const form = new FormData();
    form.append('messaging_product', 'whatsapp');
    form.append('type', input.mime);
    form.append(
      'file',
      new Blob([new Uint8Array(input.buffer)], { type: input.mime }),
      input.fileName,
    );
    try {
      const response = await fetch(
        `https://graph.facebook.com/${cfg.version}/${cfg.phoneNumberId}/media`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${cfg.token}` },
          body: form,
          signal: AbortSignal.timeout(TIMEOUT_MS),
        },
      );
      const body = (await response.json().catch(() => ({}))) as {
        id?: string;
        error?: { message?: string };
      };
      if (!response.ok || !body.id) {
        return {
          ok: false,
          error: body.error?.message ?? `http-${response.status}`,
          status: response.status,
        };
      }
      return { ok: true, mediaId: body.id };
    } catch (error) {
      return { ok: false, error: describeError(error) };
    }
  }

  /**
   * Solo plantillas: fuera de la ventana de 24 h WhatsApp rechaza el texto
   * libre, asi que no se intenta.
   */
  async sendTemplate(input: {
    to: string;
    name: string;
    language?: string;
    bodyParams: string[];
    headerMediaId?: string | null;
  }): Promise<MetaSendResult> {
    const cfg = this.readConfig();
    if (!cfg.token || !cfg.phoneNumberId) {
      return { ok: false, error: 'whatsapp-not-configured' };
    }
    const to = normalizePhone(input.to);
    if (!to) return { ok: false, error: 'missing-recipient' };
    if (this.isDryRun()) {
      // Prueba controlada: se deja el mensaje preparado y registrado, sin
      // escribir al numero real.
      this.logger.log(
        `[DRY-RUN] WhatsApp ${input.name} -> ${to} · media=${input.headerMediaId ? 'si' : 'no'} · params=${input.bodyParams.length}`,
      );
      return { ok: true, messageId: 'dry-run', dryRun: true };
    }

    const template: Record<string, unknown> = {
      name: input.name,
      language: { code: input.language || cfg.language },
    };
    if (input.headerMediaId) {
      template.components = [
        {
          type: 'header',
          parameters: [
            { type: 'image', image: { id: input.headerMediaId } },
          ],
        },
      ];
    }
    const payload = {
      messaging_product: 'whatsapp',
      to,
      type: 'template',
      template: {
        ...template,
        components: [
          ...((template.components as unknown[]) ?? []),
          {
            type: 'body',
            parameters: input.bodyParams.map((text) => ({
              type: 'text',
              text,
            })),
          },
        ],
      },
    };
    try {
      const response = await fetch(
        `https://graph.facebook.com/${cfg.version}/${cfg.phoneNumberId}/messages`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${cfg.token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(TIMEOUT_MS),
        },
      );
      const body = (await response.json().catch(() => ({}))) as {
        messages?: Array<{ id?: string }>;
        error?: { message?: string };
      };
      if (!response.ok) {
        return {
          ok: false,
          error: body.error?.message ?? `http-${response.status}`,
          status: response.status,
        };
      }
      return { ok: true, messageId: body.messages?.[0]?.id ?? null };
    } catch (error) {
      return { ok: false, error: describeError(error) };
    }
  }

  private read(key: string) {
    return (this.config.get<string>(key) ?? process.env[key] ?? '').trim();
  }
}

/** Deja solo digitos y quita el prefijo internacional escrito con `+`. */
export function normalizePhone(raw: string) {
  const digits = (raw ?? '').replace(/[^\d]/g, '');
  if (digits.length < 8) return '';
  return digits;
}

function describeError(error: unknown) {
  if (error instanceof Error) return error.message.slice(0, 300);
  return 'unknown-error';
}
