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
