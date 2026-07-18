import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

type EvolutionRuntimeConfig = {
  baseUrl: string;
  instanceName: string;
  apiKey: string;
};

type ResolveRuntimeConfigOptions = {
  senderUserId?: string | null;
  requirePersonalInstance?: boolean;
};

type EvolutionHttpError = {
  status?: number;
  message: string;
  responseBodyPreview?: string;
};

type EvolutionAttemptResult = {
  ok: boolean;
  status: number;
  bodyPreview: string;
  knownMediaBug?: boolean;
};

@Injectable()
export class EvolutionWhatsAppService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  private cachedConfig: { value: EvolutionRuntimeConfig; atMs: number } | null = null;
  private readonly requestTimeoutMs = 8_000;

  private normalizeBaseUrl(raw: string) {
    const trimmed = raw.trim();
    if (!trimmed) return '';
    return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
  }

  private normalizeSenderUserId(raw?: string | null) {
    const value = (raw ?? '').toString().trim();
    return value || null;
  }

  normalizeWhatsAppNumber(raw: string) {
    let input = (raw ?? '').toString().trim();
    if (!input) return '';

    const waMeMatch = /wa\.me\/([0-9]+)/i.exec(input);
    if (waMeMatch?.[1]) {
      input = waMeMatch[1];
    }

    input = input.replace(/(@c\.us|@s\.whatsapp\.net)$/i, '');

    let digits = input.replace(/[^0-9]/g, '');
    if (!digits) return '';

    if (digits.startsWith('00')) {
      digits = digits.replace(/^00+/, '');
      if (!digits) return '';
    }

    const isDominicanLocal = digits.length === 10 && /^(809|829|849)/.test(digits);
    if (isDominicanLocal) return `1${digits}`;

    if (digits.length === 11 && digits.startsWith('1')) return digits;

    return digits;
  }

  private async getGlobalRuntimeConfig(): Promise<EvolutionRuntimeConfig> {
    const disabled = (process.env.NOTIFICATIONS_ENABLED ?? '').trim().toLowerCase();
    if (disabled === '0' || disabled === 'false') {
      throw new BadRequestException('Notificaciones deshabilitadas por NOTIFICATIONS_ENABLED');
    }

    const now = Date.now();
    if (this.cachedConfig && now - this.cachedConfig.atMs < 30_000) {
      return this.cachedConfig.value;
    }

    const row = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: {
        evolutionApiBaseUrl: true,
        evolutionApiInstanceName: true,
        evolutionApiApiKey: true,
      },
    });

    const envBaseUrl = this.normalizeBaseUrl(
      (this.config.get<string>('EVOLUTION_API_URL') ?? '').trim(),
    );
    const envApiKey = (this.config.get<string>('EVOLUTION_API_KEY') ?? '').trim();
    const configuredBaseUrl = this.normalizeBaseUrl((row?.evolutionApiBaseUrl ?? '').trim());
    const baseUrl = envBaseUrl || configuredBaseUrl;
    const instanceName = (row?.evolutionApiInstanceName ?? '').trim();
    const apiKey = envApiKey || (row?.evolutionApiApiKey ?? '').trim();

    const value = { baseUrl, instanceName, apiKey };
    this.cachedConfig = { value, atMs: now };
    return value;
  }

  private async getRuntimeConfig(options: ResolveRuntimeConfigOptions = {}): Promise<EvolutionRuntimeConfig> {
    const baseConfig = await this.getGlobalRuntimeConfig();
    this.validateRuntimeConfig(baseConfig);

    const senderUserId = this.normalizeSenderUserId(options.senderUserId);
    if (!senderUserId) {
      return baseConfig;
    }

    const userInstance = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId: senderUserId },
      select: {
        instanceName: true,
        status: true,
      },
    });

    const instanceName = (userInstance?.instanceName ?? '').trim();
    if (!instanceName) {
      if (options.requirePersonalInstance) {
        throw new BadRequestException(
          'El usuario emisor no tiene una instancia personal de WhatsApp configurada.',
        );
      }
      return baseConfig;
    }

    return {
      ...baseConfig,
      instanceName,
    };
  }

  private stringifyPreview(value: unknown, maxChars = 900) {
    if (value == null) return '';
    const text = typeof value === 'string' ? value : JSON.stringify(value);
    const trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return `${trimmed.slice(0, maxChars)}…`;
  }

  private async readResponseBodySafe(res: Response) {
    try {
      const text = await res.text();
      return this.stringifyPreview(text);
    } catch {
      return '';
    }
  }

  private isMockEnabled() {
    const mock = (process.env.NOTIFICATIONS_MOCK_SUCCESS ?? '').trim().toLowerCase();
    return mock === '1' || mock === 'true' || mock === 'yes';
  }

  private validateRuntimeConfig(config: EvolutionRuntimeConfig) {
    if (!config.baseUrl) {
      throw new BadRequestException('Evolution API: falta Base URL en Ajustes > Configuración de API');
    }
    if (!config.instanceName) {
      throw new BadRequestException('Evolution API: falta Instance name en Ajustes > Configuración de API');
    }
    if (!config.apiKey) {
      throw new BadRequestException('Evolution API: falta API Key en Ajustes > Configuración de API');
    }
  }

  private validateNumber(rawNumber: string) {
    const number = this.normalizeWhatsAppNumber(rawNumber);
    if (!number) {
      throw new BadRequestException('Número de WhatsApp inválido');
    }
    return number;
  }

  private buildHttpError(status: number, bodyPreview: string, attemptLabel?: string) {
    const err: EvolutionHttpError = {
      status,
      message: `Evolution API error (HTTP ${status})`,
      responseBodyPreview: bodyPreview,
    };

    const suffix = [attemptLabel ? `Payload: ${attemptLabel}` : '', bodyPreview ? `Response: ${bodyPreview}` : '']
      .filter(Boolean)
      .join(' · ');
    const error = new Error(`${err.message}${suffix ? ` · ${suffix}` : ''}`) as Error & {
      status?: number;
    };
    error.status = status;
    return error;
  }

  private async postAttempt(
    endpoint: string,
    init: RequestInit,
    label?: string,
  ): Promise<EvolutionAttemptResult> {
    const res = await this.fetchWithTimeout(endpoint, init, this.requestTimeoutMs);
    const bodyPreview = res.ok ? '' : await this.readResponseBodySafe(res);
    const knownMediaBug = /ephemeralMessage/i.test(bodyPreview);
    if (res.ok) {
      return { ok: true, status: res.status, bodyPreview, knownMediaBug };
    }

    return {
      ok: false,
      status: res.status,
      bodyPreview: label ? `${label}${bodyPreview ? ` · ${bodyPreview}` : ''}` : bodyPreview,
      knownMediaBug,
    };
  }

  private async fetchWithTimeout(
    endpoint: string,
    init: RequestInit,
    timeoutMs: number,
  ) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    try {
      return await fetch(endpoint, {
        ...init,
        signal: controller.signal,
      });
    } catch (error) {
      if ((error as { name?: string })?.name === 'AbortError') {
        throw new Error(`Evolution API timeout after ${timeoutMs}ms`);
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  async sendTextMessage(params: { toNumber: string; message: string; senderUserId?: string | null; requirePersonalInstance?: boolean }) {
    const mockEnabled = this.isMockEnabled();

    // Mock mode: validate inputs but skip external calls.
    if (mockEnabled) {
      this.validateNumber(params.toNumber);
      const message = (params.message ?? '').toString();
      if (!message.trim()) {
        throw new BadRequestException('Mensaje vacío');
      }
      return;
    }

    const config = await this.getRuntimeConfig({
      senderUserId: params.senderUserId,
      requirePersonalInstance: params.requirePersonalInstance,
    });

    const number = this.validateNumber(params.toNumber);

    const message = (params.message ?? '').toString();
    if (!message.trim()) {
      throw new BadRequestException('Mensaje vacío');
    }

    const endpoint = `${config.baseUrl}/message/sendText/${encodeURIComponent(config.instanceName)}`;

    const res = await this.fetchWithTimeout(endpoint, {
      method: 'POST',
      headers: {
        apikey: config.apiKey,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ number, text: message }),
    }, this.requestTimeoutMs);

    if (res.ok) return;

    const bodyPreview = await this.readResponseBodySafe(res);
    throw this.buildHttpError(res.status, bodyPreview);
  }

  async sendPdfDocument(params: {
    toNumber: string;
    bytes: Uint8Array;
    fileName: string;
    caption?: string;
    senderUserId?: string | null;
    requirePersonalInstance?: boolean;
  }) {
    const mockEnabled = this.isMockEnabled();
    const number = this.validateNumber(params.toNumber);
    const bytes = params.bytes instanceof Uint8Array ? params.bytes : new Uint8Array(params.bytes);
    if (!bytes.length) {
      throw new BadRequestException('El PDF está vacío y no se puede enviar');
    }

    const fileName = (params.fileName ?? '').trim() || 'cotizacion.pdf';
    const caption = (params.caption ?? '').trim();

    if (mockEnabled) {
      return;
    }

    const config = await this.getRuntimeConfig({
      senderUserId: params.senderUserId,
      requirePersonalInstance: params.requirePersonalInstance,
    });

    const endpoint = `${config.baseUrl}/message/sendMedia/${encodeURIComponent(config.instanceName)}`;
    const mediaBase64 = Buffer.from(bytes).toString('base64');
    const multipartBytes = Uint8Array.from(bytes);
    const jsonHeaders = {
      apikey: config.apiKey,
      'content-type': 'application/json',
    };

    const attempts: Array<{ label: string; init: RequestInit }> = [
      {
        label: 'json:base64:fileName',
        init: {
          method: 'POST',
          headers: jsonHeaders,
          body: JSON.stringify({
            number,
            mediatype: 'document',
            mimetype: 'application/pdf',
            ...(caption ? { caption } : {}),
            media: mediaBase64,
            fileName,
          }),
        },
      },
      {
        label: 'json:base64:filename',
        init: {
          method: 'POST',
          headers: jsonHeaders,
          body: JSON.stringify({
            number,
            mediatype: 'document',
            mimetype: 'application/pdf',
            ...(caption ? { caption } : {}),
            media: mediaBase64,
            filename: fileName,
          }),
        },
      },
      {
        label: 'json:data-url:fileName',
        init: {
          method: 'POST',
          headers: jsonHeaders,
          body: JSON.stringify({
            number,
            mediatype: 'document',
            mimetype: 'application/pdf',
            ...(caption ? { caption } : {}),
            media: `data:application/pdf;base64,${mediaBase64}`,
            fileName,
          }),
        },
      },
      {
        label: 'multipart:file',
        init: {
          method: 'POST',
          headers: { apikey: config.apiKey },
          body: (() => {
            const fullMultipart = new FormData();
            fullMultipart.set('number', number);
            if (caption) {
              fullMultipart.set('caption', caption);
            }
            fullMultipart.set('mediatype', 'document');
            fullMultipart.set('mimetype', 'application/pdf');
            fullMultipart.set('fileName', fileName);
            fullMultipart.set('media', new Blob([multipartBytes], { type: 'application/pdf' }), fileName);
            return fullMultipart;
          })(),
        },
      },
      {
        label: 'json:document-alias',
        init: {
          method: 'POST',
          headers: jsonHeaders,
          body: JSON.stringify({
            number,
            mediatype: 'documentMessage',
            mimetype: 'application/pdf',
            ...(caption ? { caption } : {}),
            media: mediaBase64,
            fileName,
          }),
        },
      },
    ];

    let lastFailure: EvolutionAttemptResult | null = null;
    let serverErrors = 0;
    let attemptsTried = 0;
    const startedAt = Date.now();

    for (const attempt of attempts) {
      if (attemptsTried >= 12) break;
      if (Date.now() - startedAt > 20_000) break;
      attemptsTried += 1;

      const result = await this.postAttempt(endpoint, attempt.init, attempt.label);
      if (result.ok) {
        return;
      }

      lastFailure = result;

      if (result.status >= 500) {
        serverErrors += 1;
        if (serverErrors >= 4) {
          break;
        }
      }

      if (result.status === 401 || result.status === 403) {
        break;
      }

      const retryable = [400, 404, 415, 422].includes(result.status) || result.status >= 500;
      if (!retryable) {
        break;
      }
    }

    if (!lastFailure) {
      throw new Error('No se pudo enviar PDF con Evolution API');
    }

    throw this.buildHttpError(lastFailure.status, lastFailure.bodyPreview);
  }
}
