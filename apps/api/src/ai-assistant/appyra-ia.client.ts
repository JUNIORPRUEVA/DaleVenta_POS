import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Cliente servidor-a-servidor del runtime de agentes de APPYRA IA.
 *
 * FullPOS conserva su endpoint `/ai/chat` como fachada: el panel flotante no habla con
 * APPYRA IA directamente ni recibe credenciales. Este cliente es el único punto que conoce
 * la credencial de integración y el único que decide qué contexto sale de la empresa.
 *
 * Reglas que se aplican aquí y no en un prompt:
 * 1. El contexto es una **lista blanca** (`route`, `module`, `screenName`). Cualquier otro
 *    dato del cliente —incluido `entityType`/`entityId`, que puede identificar a un cliente
 *    real— se descarta antes de enviarlo.
 * 2. Sin reintentos automáticos: reintentar a ciegas duplica turnos. El llamador puede
 *    reenviar con el mismo `clientMessageId` y APPYRA IA devuelve el turno guardado.
 * 3. En los errores se registra **status y código**, nunca el token ni el cuerpo del
 *    mensaje del usuario.
 *
 * El tiempo de espera por defecto (60 s) está pensado para un modelo local: medido con
 * `qwen2.5-coder:7b` en CPU, una respuesta fría supera los 20 s y la integración caía al
 * respaldo por reglas sin que APPYRA IA hubiera fallado.
 */

export interface AppyraIaAppContext {
  readonly route?: string;
  readonly module?: string;
  readonly screenName?: string;
}

export interface AppyraIaChatInput {
  readonly message: string;
  readonly conversationId?: string;
  readonly clientMessageId?: string;
  /** Archivos ya procesados por el motor multimedia cuyo texto debe usar el turno. */
  readonly mediaJobIds?: readonly string[];
  /**
   * Contexto de empresa firmado (`x-appyra-company-context`).
   *
   * Lo genera este backend con la empresa de la sesión; sin él, APPYRA rechaza cualquier operación
   * sobre incidencias (varias empresas comparten el tenant `fulltech`).
   */
  readonly companyContext?: string;
  readonly context: AppyraIaAppContext;
}

export interface AppyraIaMediaUpload {
  readonly buffer: Buffer;
  readonly filename: string;
  readonly mimetype: string;
}

export interface AppyraIaMediaResult {
  readonly jobId: string;
  readonly status: string;
  readonly engine: string | null;
}

export interface AppyraIaSource {
  readonly title: string;
  readonly category?: string;
  readonly source?: string;
}

export interface AppyraIaChatResult {
  readonly conversationId: string | null;
  readonly agentName: string | null;
  readonly agentVersion: number | null;
  readonly text: string;
  readonly mode: string;
  readonly model: string | null;
  readonly escalated: boolean;
  readonly requiresHumanReview: boolean;
  readonly handoffReasons: readonly string[];
  readonly limitations: readonly string[];
  readonly sources: readonly AppyraIaSource[];
}

export type AppyraIaErrorKind = 'disabled' | 'configuration' | 'timeout' | 'http' | 'payload';

/** Contrato de respuesta que ya consume el panel flotante de FullPOS. */
export interface AppyraIaChatResponse {
  readonly source: 'appyra-ia' | 'appyra-ia-rules';
  readonly content: string;
  readonly citations: Array<{
    id: string;
    module: string;
    category: string;
    title: string;
  }>;
  readonly denied: boolean;
  readonly requiresHumanReview: boolean;
  readonly conversationId?: string;
  readonly agentName?: string;
  readonly agentVersion?: number;
}

/**
 * Traduce el turno de APPYRA IA al contrato de FullPOS.
 *
 * `simulated` significa que APPYRA IA respondió con sus reglas y no con un modelo: se marca
 * como `appyra-ia-rules` para no presentar una plantilla como respuesta de IA.
 */
export function toFullPosChatResponse(
  result: AppyraIaChatResult,
  module: string,
): AppyraIaChatResponse {
  const citations = result.sources.map((source, index) => ({
    id: `appyra:${index + 1}`,
    module: module === '' ? 'general' : module,
    category: source.category ?? 'appyra-ia',
    title: source.title,
  }));

  return {
    source: result.mode === 'simulated' ? 'appyra-ia-rules' : 'appyra-ia',
    content: result.text,
    citations,
    denied: false,
    requiresHumanReview: result.escalated || result.requiresHumanReview,
    ...(result.conversationId === null ? {} : { conversationId: result.conversationId }),
    ...(result.agentName === null ? {} : { agentName: result.agentName }),
    ...(result.agentVersion === null ? {} : { agentVersion: result.agentVersion }),
  };
}

export class AppyraIaError extends Error {
  constructor(
    readonly kind: AppyraIaErrorKind,
    message: string,
    readonly status?: number,
    readonly code?: string,
  ) {
    super(message);
    this.name = 'AppyraIaError';
  }
}

/** Coincide con la validación del DTO de APPYRA IA (`RuntimeAppContextDto`). */
const ROUTE_PATTERN = /^\/[A-Za-z0-9/_-]*$/;
const MODULE_PATTERN = /^[A-Za-z0-9_-]+$/;
const MAX_ROUTE = 120;
const MAX_MODULE = 60;
const MAX_SCREEN = 120;

const DEFAULT_TIMEOUT_MS = 60_000;
const MIN_TIMEOUT_MS = 1_000;
const MAX_TIMEOUT_MS = 120_000;

const DEFAULT_MEDIA_TIMEOUT_MS = 60_000;
const MIN_MEDIA_TIMEOUT_MS = 5_000;
const MAX_MEDIA_TIMEOUT_MS = 300_000;

const DEFAULT_PRODUCT_KEY = 'fullpos';

interface AppyraIaRuntimeConfig {
  readonly enabled: boolean;
  readonly baseUrl: string;
  readonly token: string;
  readonly mediaToken: string;
  readonly productKey: string;
  readonly timeoutMs: number;
  readonly mediaTimeoutMs: number;
}

@Injectable()
export class AppyraIaClient {
  private readonly logger = new Logger(AppyraIaClient.name);

  constructor(private readonly config: ConfigService) {}

  /** `true` sólo si la bandera está encendida y hay URL y credencial. */
  isEnabled(): boolean {
    const runtime = this.readConfig();
    return runtime.enabled && runtime.baseUrl !== '' && runtime.token !== '';
  }

  async chat(input: AppyraIaChatInput): Promise<AppyraIaChatResult> {
    const runtime = this.readConfig();
    if (!runtime.enabled) {
      throw new AppyraIaError('disabled', 'APPYRA IA está desactivado por configuración.');
    }
    if (runtime.baseUrl === '' || runtime.token === '') {
      throw new AppyraIaError('configuration', 'Falta la URL o la credencial de APPYRA IA.');
    }

    const body = this.buildBody(runtime.productKey, input);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), runtime.timeoutMs);

    let response: Response;
    try {
      response = await fetch(`${runtime.baseUrl}/agent-runtime/chat`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${runtime.token}`,
          'Content-Type': 'application/json',
          ...(input.companyContext === undefined
            ? {}
            : { 'x-appyra-company-context': input.companyContext }),
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        this.logger.warn(`APPYRA IA no respondió en ${runtime.timeoutMs} ms.`);
        throw new AppyraIaError('timeout', 'APPYRA IA no respondió a tiempo.');
      }
      this.logger.warn('No se pudo contactar con APPYRA IA.');
      throw new AppyraIaError('http', 'No se pudo contactar con APPYRA IA.');
    } finally {
      clearTimeout(timer);
    }

    if (!response.ok) {
      const code = await this.readErrorCode(response);
      this.logger.warn(
        `APPYRA IA respondió ${response.status}${code === undefined ? '' : ` (${code})`}.`,
      );
      throw new AppyraIaError(
        'http',
        `APPYRA IA respondió ${response.status}.`,
        response.status,
        code,
      );
    }

    let payload: unknown;
    try {
      payload = await response.json();
    } catch {
      throw new AppyraIaError('payload', 'APPYRA IA devolvió una respuesta ilegible.');
    }

    return this.mapResponse(payload);
  }

  /**
   * Sube un archivo al motor multimedia de APPYRA IA y espera a que termine.
   *
   * Devuelve el identificador del trabajo, que después viaja en el mensaje. El archivo **no** se
   * guarda en FullPOS: se reenvía en memoria y solo queda en el almacén del motor.
   */
  async uploadMedia(input: AppyraIaMediaUpload): Promise<AppyraIaMediaResult> {
    const runtime = this.readConfig();
    if (!runtime.enabled) {
      throw new AppyraIaError('disabled', 'APPYRA IA está desactivado por configuración.');
    }
    if (runtime.baseUrl === '' || runtime.mediaToken === '') {
      throw new AppyraIaError('configuration', 'Falta la credencial multimedia de APPYRA IA.');
    }

    const form = new FormData();
    // Copia explícita a un ArrayBuffer: `Buffer` usa `ArrayBufferLike` y el tipo de `Blob` exige
    // `ArrayBuffer`. Además el archivo no se retiene más allá de esta petición.
    const bytes = new ArrayBuffer(input.buffer.byteLength);
    new Uint8Array(bytes).set(input.buffer);
    form.append('file', new Blob([bytes], { type: input.mimetype }), input.filename);

    const response = await this.requestWithTimeout(
      `${runtime.baseUrl}/media`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${runtime.mediaToken}` },
        body: form,
      },
      runtime.mediaTimeoutMs,
      'subir el archivo',
    );

    if (!response.ok) {
      const code = await this.readErrorCode(response);
      this.logger.warn(
        `APPYRA IA rechazó el archivo con ${response.status}${code === undefined ? '' : ` (${code})`}.`,
      );
      throw new AppyraIaError(
        'http',
        `APPYRA IA respondió ${response.status} al subir el archivo.`,
        response.status,
        code,
      );
    }

    const created = (await response.json()) as Record<string, unknown>;
    const jobId = this.readString(created['jobId']);
    if (jobId === null) {
      throw new AppyraIaError('payload', 'APPYRA IA no devolvió el identificador del archivo.');
    }

    return this.waitForMedia(runtime, jobId);
  }

  private async waitForMedia(
    runtime: AppyraIaRuntimeConfig,
    jobId: string,
  ): Promise<AppyraIaMediaResult> {
    const deadline = Date.now() + runtime.mediaTimeoutMs;
    while (Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 1_500));
      const response = await this.requestWithTimeout(
        `${runtime.baseUrl}/media/${jobId}`,
        { headers: { Authorization: `Bearer ${runtime.mediaToken}` } },
        runtime.mediaTimeoutMs,
        'consultar el archivo',
      );
      if (!response.ok) {
        throw new AppyraIaError('http', `APPYRA IA respondió ${response.status}.`, response.status);
      }
      const job = (await response.json()) as Record<string, unknown>;
      const status = this.readString(job['status']) ?? '';
      if (status === 'FAILED' || status === 'CANCELLED') {
        throw new AppyraIaError('payload', `APPYRA IA no pudo procesar el archivo (${status}).`);
      }
      if (status === 'COMPLETED') {
        return { jobId, status, engine: this.readString(job['engine']) };
      }
    }
    throw new AppyraIaError('timeout', 'APPYRA IA no terminó de procesar el archivo a tiempo.');
  }

  private async requestWithTimeout(
    url: string,
    init: RequestInit,
    timeoutMs: number,
    action: string,
  ): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetch(url, { ...init, signal: controller.signal });
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        this.logger.warn(`APPYRA IA no respondió al ${action} en ${timeoutMs} ms.`);
        throw new AppyraIaError('timeout', `APPYRA IA no respondió al ${action} a tiempo.`);
      }
      this.logger.warn(`No se pudo contactar con APPYRA IA al ${action}.`);
      throw new AppyraIaError('http', `No se pudo contactar con APPYRA IA al ${action}.`);
    } finally {
      clearTimeout(timer);
    }
  }

  private readConfig(): AppyraIaRuntimeConfig {
    const enabled =
      (this.config.get<string>('APPYRA_IA_ENABLED') ?? '').trim().toLowerCase() === 'true';
    const baseUrl = (this.config.get<string>('APPYRA_IA_BASE_URL') ?? '')
      .trim()
      .replace(/\/+$/, '');
    const token = (this.config.get<string>('APPYRA_IA_RUNTIME_TOKEN') ?? '').trim();
    const mediaToken = (this.config.get<string>('APPYRA_IA_MEDIA_TOKEN') ?? '').trim();
    const productKey =
      (this.config.get<string>('APPYRA_IA_PRODUCT_KEY') ?? '').trim() || DEFAULT_PRODUCT_KEY;
    const rawTimeout = Number(this.config.get<string>('APPYRA_IA_TIMEOUT_MS') ?? '');
    const timeoutMs = Number.isFinite(rawTimeout)
      ? Math.min(Math.max(Math.trunc(rawTimeout), MIN_TIMEOUT_MS), MAX_TIMEOUT_MS)
      : DEFAULT_TIMEOUT_MS;
    const rawMediaTimeout = Number(this.config.get<string>('APPYRA_IA_MEDIA_TIMEOUT_MS') ?? '');
    const mediaTimeoutMs = Number.isFinite(rawMediaTimeout)
      ? Math.min(Math.max(Math.trunc(rawMediaTimeout), MIN_MEDIA_TIMEOUT_MS), MAX_MEDIA_TIMEOUT_MS)
      : DEFAULT_MEDIA_TIMEOUT_MS;

    return { enabled, baseUrl, token, mediaToken, productKey, timeoutMs, mediaTimeoutMs };
  }

  /**
   * Cuerpo con lista blanca. `entityType` y `entityId` no existen en `AppyraIaAppContext`
   * a propósito: un `clientId` es dato del negocio y no sale de la empresa.
   */
  private buildBody(productKey: string, input: AppyraIaChatInput): Record<string, unknown> {
    const context = this.normalizeContext(input.context);
    return {
      productKey,
      message: input.message,
      ...(input.conversationId === undefined ? {} : { conversationId: input.conversationId }),
      ...(input.clientMessageId === undefined
        ? {}
        : { clientMessageId: input.clientMessageId }),
      ...(input.mediaJobIds === undefined || input.mediaJobIds.length === 0
        ? {}
        : { mediaJobIds: [...input.mediaJobIds] }),
      ...(Object.keys(context).length === 0 ? {} : { context }),
    };
  }

  private normalizeContext(raw: AppyraIaAppContext): Record<string, string> {
    const normalized: Record<string, string> = {};

    const route = this.clean(raw.route);
    if (route !== undefined && route.length <= MAX_ROUTE && ROUTE_PATTERN.test(route)) {
      normalized.route = route;
    }

    const module = this.clean(raw.module);
    if (module !== undefined && module.length <= MAX_MODULE && MODULE_PATTERN.test(module)) {
      normalized.module = module;
    }

    const screenName = this.clean(raw.screenName);
    if (screenName !== undefined && screenName.length <= MAX_SCREEN) {
      normalized.screenName = screenName;
    }

    return normalized;
  }

  private clean(value: string | undefined): string | undefined {
    if (value === undefined) return undefined;
    const trimmed = value.replace(/\s+/g, ' ').trim();
    return trimmed === '' ? undefined : trimmed;
  }

  private async readErrorCode(response: Response): Promise<string | undefined> {
    try {
      const text = await response.text();
      if (text === '') return undefined;
      const parsed: unknown = JSON.parse(text);
      if (typeof parsed === 'object' && parsed !== null) {
        const record = parsed as Record<string, unknown>;
        for (const key of ['code', 'error', 'message']) {
          const value = record[key];
          if (typeof value === 'string' && value.trim() !== '') {
            return value.trim().slice(0, 60);
          }
          if (Array.isArray(value) && typeof value[0] === 'string') {
            return value[0].trim().slice(0, 60);
          }
        }
      }
      return undefined;
    } catch {
      return undefined;
    }
  }

  private mapResponse(payload: unknown): AppyraIaChatResult {
    if (typeof payload !== 'object' || payload === null) {
      throw new AppyraIaError('payload', 'APPYRA IA devolvió una respuesta inesperada.');
    }

    const root = payload as Record<string, unknown>;
    const reply = root['reply'];
    if (typeof reply !== 'object' || reply === null) {
      throw new AppyraIaError('payload', 'APPYRA IA no devolvió el turno de respuesta.');
    }

    const replyRecord = reply as Record<string, unknown>;
    const text = replyRecord['text'];
    if (typeof text !== 'string' || text.trim() === '') {
      throw new AppyraIaError('payload', 'APPYRA IA devolvió una respuesta vacía.');
    }

    const agent = root['agent'];
    const agentRecord =
      typeof agent === 'object' && agent !== null ? (agent as Record<string, unknown>) : null;

    return {
      conversationId: this.readString(root['conversationId']),
      agentName: agentRecord === null ? null : this.readString(agentRecord['name']),
      agentVersion:
        agentRecord !== null && typeof agentRecord['version'] === 'number'
          ? agentRecord['version']
          : null,
      text: text.trim(),
      mode: this.readString(replyRecord['mode']) ?? 'local',
      model: this.readString(replyRecord['model']),
      escalated: replyRecord['escalated'] === true,
      requiresHumanReview: replyRecord['requiresHumanReview'] === true,
      handoffReasons: this.readStringList(replyRecord['handoffReasons']),
      limitations: this.readStringList(replyRecord['limitations']),
      sources: this.readSources(replyRecord['sources']),
    };
  }

  private readString(value: unknown): string | null {
    return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
  }

  private readStringList(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value
      .filter((entry): entry is string => typeof entry === 'string' && entry.trim() !== '')
      .map((entry) => entry.trim());
  }

  private readSources(value: unknown): AppyraIaSource[] {
    if (!Array.isArray(value)) return [];
    const sources: AppyraIaSource[] = [];
    for (const entry of value) {
      if (typeof entry !== 'object' || entry === null) continue;
      const record = entry as Record<string, unknown>;
      const title = this.readString(record['title']);
      if (title === null) continue;
      const category = this.readString(record['category']);
      const source = this.readString(record['source']);
      sources.push({
        title,
        ...(category === null ? {} : { category }),
        ...(source === null ? {} : { source }),
      });
    }
    return sources;
  }
}
