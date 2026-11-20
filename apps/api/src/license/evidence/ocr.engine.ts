import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

const run = promisify(execFile);

export type OcrResult =
  | { ok: true; text: string; engine: string }
  | { ok: false; error: string; engine: string };

/**
 * Motor de lectura de comprobantes.
 *
 * **No** usa IA de pago. Reutiliza el Media Engine de APPYRA (OCR local con
 * RapidOCR) por HTTP. Si no esta configurado o falla, se devuelve `ok:false`
 * y el comprobante queda pendiente de revision: nunca se inventa una lectura.
 */
@Injectable()
export class OcrEngine {
  private readonly logger = new Logger(OcrEngine.name);

  constructor(private readonly config: ConfigService) {}

  private baseUrl() {
    return (
      this.config.get<string>('APPYRA_MEDIA_BASE_URL')?.trim().replace(/\/+$/, '') ?? ''
    );
  }

  isConfigured() {
    return this.baseUrl().length > 0 || this.localWorker() != null;
  }

  /** OCR local real: el media-worker de APPYRA (RapidOCR) por CLI. */
  private localWorker() {
    const python = this.config.get<string>('APPYRA_MEDIA_PYTHON')?.trim();
    const worker = this.config.get<string>('APPYRA_MEDIA_WORKER')?.trim();
    if (!python || !worker) return null;
    return { python, worker };
  }

  /** Ruta del Media Engine que devuelve el texto del documento. */
  private ocrPath() {
    return this.config.get<string>('APPYRA_MEDIA_OCR_PATH')?.trim() || '/v1/media/ocr';
  }

  private token() {
    return (
      this.config.get<string>('APPYRA_MEDIA_TOKEN')?.trim() ||
      this.config.get<string>('APPYRA_INTEGRATION_TOKEN')?.trim() ||
      ''
    );
  }

  async extractText(input: {
    buffer: Buffer;
    mime: string;
    fileName: string;
  }): Promise<OcrResult> {
    const baseUrl = this.baseUrl();
    const local = this.localWorker();
    if (!baseUrl && !local) {
      return { ok: false, error: 'ocr-not-configured', engine: 'none' };
    }
    // Preferencia: motor local por CLI (sin red, sin IA de pago).
    if (local) {
      return this.extractWithWorker(local, input);
    }
    const token = this.token();
    if (this.config.get<string>('APPYRA_MEDIA_OCR_PROTOCOL') === 'appyra-jobs') {
      return this.extractWithMediaJobs(baseUrl, token, input);
    }
    try {
      const form = new FormData();
      form.append(
        'file',
        new Blob([new Uint8Array(input.buffer)], { type: input.mime }),
        input.fileName || 'comprobante',
      );
      form.append('mode', 'ocr');
      form.append('language', 'spa');
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 45_000);
      const response = await fetch(`${baseUrl}${this.ocrPath()}`, {
        method: 'POST',
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
        body: form,
        signal: controller.signal,
      }).finally(() => clearTimeout(timeout));
      if (!response.ok) {
        return {
          ok: false,
          error: `ocr-http-${response.status}`,
          engine: 'media-engine',
        };
      }
      const data = (await response.json()) as {
        text?: unknown;
        engine?: unknown;
      };
      const text = typeof data.text === 'string' ? data.text : '';
      if (!text.trim()) {
        return { ok: false, error: 'ocr-empty', engine: 'media-engine' };
      }
      return {
        ok: true,
        text,
        engine: typeof data.engine === 'string' ? data.engine : 'media-engine',
      };
    } catch (error) {
      const message =
        error instanceof Error ? error.message.slice(0, 120) : 'ocr-error';
      this.logger.warn(`OCR no disponible: ${message}`);
      return { ok: false, error: 'ocr-error', engine: 'media-engine' };
    }
  }

  /** Contrato existente de APPYRA: POST /v1/media y GET del resultado del trabajo. */
  private async extractWithMediaJobs(
    baseUrl: string,
    token: string,
    input: { buffer: Buffer; mime: string; fileName: string },
  ): Promise<OcrResult> {
    if (!token) return { ok: false, error: 'ocr-token-required', engine: 'media-engine' };
    const configured = Number(this.config.get('APPYRA_MEDIA_OCR_TIMEOUT_MS') ?? 45000);
    const timeoutMs = Number.isFinite(configured) ? Math.min(120000, Math.max(1000, configured)) : 45000;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const headers = { Authorization: `Bearer ${token}` };
    const capability = input.mime === 'application/pdf' ? 'EXTRACT_DOCUMENT' : 'EXTRACT_IMAGE_TEXT';
    try {
      const form = new FormData();
      form.append('file', new Blob([new Uint8Array(input.buffer)], { type: input.mime }), input.fileName || 'comprobante');
      form.append('capability', capability);
      form.append('sourceChannel', 'fullpos-license');
      form.append('allowExternal', 'false');
      const submitted = await fetch(`${baseUrl}/v1/media`, {
        method: 'POST', headers, body: form, signal: controller.signal, redirect: 'error',
      });
      if (submitted.status !== 202) return { ok: false, error: `ocr-http-${submitted.status}`, engine: 'media-engine' };
      const job = await submitted.json() as { jobId?: unknown };
      if (typeof job.jobId !== 'string' || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(job.jobId)) {
        return { ok: false, error: 'ocr-invalid-job', engine: 'media-engine' };
      }
      while (!controller.signal.aborted) {
        const response = await fetch(`${baseUrl}/v1/media/${job.jobId}/result`, {
          headers, signal: controller.signal, redirect: 'error',
        });
        if (response.status !== 200) return { ok: false, error: `ocr-http-${response.status}`, engine: 'media-engine' };
        const data = await response.json() as {
          jobId?: unknown; status?: unknown; capability?: unknown; externalCalls?: unknown;
          result?: { text?: unknown; capability?: unknown } | null;
        };
        if (data.jobId !== job.jobId || data.capability !== capability) {
          return { ok: false, error: 'ocr-job-mismatch', engine: 'media-engine' };
        }
        if (data.status === 'COMPLETED') {
          if (data.externalCalls !== 0 || data.result?.capability !== capability) {
            return { ok: false, error: 'ocr-unverified-result', engine: 'media-engine' };
          }
          const text = data.result?.text;
          return typeof text === 'string' && text.trim()
            ? { ok: true, text, engine: 'media-engine' }
            : { ok: false, error: 'ocr-empty', engine: 'media-engine' };
        }
        if (data.status !== 'PENDING' && data.status !== 'PROCESSING') {
          return { ok: false, error: 'ocr-job-failed', engine: 'media-engine' };
        }
        await new Promise(resolve => setTimeout(resolve, Math.min(700, timeoutMs)));
      }
      return { ok: false, error: 'ocr-timeout', engine: 'media-engine' };
    } catch {
      return { ok: false, error: controller.signal.aborted ? 'ocr-timeout' : 'ocr-error', engine: 'media-engine' };
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * Ejecuta `media_worker.py --mode ocr` sobre un archivo temporal.
   * `execFile` (sin shell) y con tiempo maximo: un comprobante roto no puede
   * dejar colgada la subida.
   */
  private async extractWithWorker(
    local: { python: string; worker: string },
    input: { buffer: Buffer; mime: string; fileName: string },
  ): Promise<OcrResult> {
    const dir = await mkdtemp(join(tmpdir(), 'appyra-ocr-'));
    const ext = extensionFor(input.mime, input.fileName);
    const inputPath = join(dir, `evidence${ext}`);
    const outputPath = join(dir, 'ocr.json');
    try {
      await writeFile(inputPath, input.buffer);
      const timeoutMs = Number(this.config.get('APPYRA_MEDIA_OCR_TIMEOUT_MS') ?? 120000);
      await run(
        local.python,
        [
          local.worker,
          '--mode',
          'ocr',
          '--input',
          inputPath,
          '--output',
          outputPath,
          '--languages',
          this.config.get<string>('APPYRA_MEDIA_OCR_LANGS')?.trim() || 'es,en',
        ],
        { timeout: Number.isFinite(timeoutMs) ? timeoutMs : 120000, windowsHide: true, maxBuffer: 8 * 1024 * 1024 },
      );
      const raw = await readFile(outputPath, 'utf8');
      const data = JSON.parse(raw) as { text?: unknown; engine?: unknown };
      const text = typeof data.text === 'string' ? data.text : '';
      if (!text.trim()) {
        return { ok: false, error: 'ocr-empty', engine: 'rapidocr' };
      }
      return {
        ok: true,
        text,
        engine: typeof data.engine === 'string' ? data.engine : 'rapidocr',
      };
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 140) : 'ocr-error';
      this.logger.warn(`OCR local fallo: ${message}`);
      return { ok: false, error: 'ocr-error', engine: 'rapidocr' };
    } finally {
      await rm(dir, { recursive: true, force: true }).catch(() => undefined);
    }
  }
}

function extensionFor(mime: string, fileName: string) {
  const nameExt = /\.[a-z0-9]{2,5}$/i.exec(fileName ?? '')?.[0];
  if (nameExt) return nameExt.toLowerCase();
  if (mime === 'application/pdf') return '.pdf';
  if (mime === 'image/png') return '.png';
  if (mime === 'image/webp') return '.webp';
  return '.jpg';
}
