import type {
  AlanubeHttpTransport,
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "./alanube-safe-http.types";

const MAX_RESPONSE_BYTES = 1024 * 1024;

export class AlanubeRealHttpTransport implements AlanubeHttpTransport {
  async execute(request: AlanubeSafeRequest): Promise<AlanubeTransportResult> {
    let target: URL;
    try { target = new URL(request.url); }
    catch { return this.error("CONFIGURATION_ERROR", "URL Alanube no permitida.", request.requestId); }
    if (
      target.protocol !== "https:" ||
      target.hostname !== "sandbox.alanube.co" ||
      target.port || target.search || target.hash ||
      !/^\/dom\/v1\/(company(?:\/[A-Za-z0-9_-]+)?|(?:fiscal-invoices|invoices|credit-notes)\/[A-Za-z0-9_-]+)$/.test(target.pathname) ||
      target.username ||
      target.password
    ) {
      return this.error("CONFIGURATION_ERROR", "URL Alanube no permitida.", request.requestId);
    }
    if (request.method !== "GET" || request.body !== undefined) {
      return this.error("CONFIGURATION_ERROR", "POST fiscal deshabilitado; contratos pendientes.", request.requestId);
    }
    if (!Number.isFinite(request.timeoutMs) || request.timeoutMs < 1 || request.timeoutMs > 30000) {
      return this.error("CONFIGURATION_ERROR", "Timeout Alanube inválido.", request.requestId);
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), request.timeoutMs);
    try {
      const response = await fetch(target, {
        method: request.method,
        headers: request.headers,
        body: request.body ? JSON.stringify(request.body) : undefined,
        redirect: "manual",
        signal: controller.signal,
      });
      if (response.status >= 300 && response.status < 400) {
        return this.error("REDIRECT_BLOCKED", "Alanube respondió con redirección bloqueada.", request.requestId);
      }
      const text = await limitedText(response, MAX_RESPONSE_BYTES);
      return {
        ok: true,
        response: {
          statusCode: response.status,
          headers: {},
          body: parseJsonSafely(text),
          requestId: request.requestId,
        },
      };
    } catch (error) {
      const code = controller.signal.aborted ? "TIMEOUT" : "NETWORK_ERROR";
      return this.error(code, "No se pudo completar la comunicación con Alanube.", request.requestId);
    } finally {
      clearTimeout(timeout);
    }
  }

  private error(
    errorCode: Exclude<AlanubeTransportResult, { ok: true }>["errorCode"],
    safeMessage: string,
    requestId: string,
  ): AlanubeTransportResult {
    return { ok: false, errorCode, safeMessage, requestId };
  }
}

async function limitedText(response: Response, maxBytes: number) {
  if (!response.body) return "";
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let size = 0;
  let text = "";
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > maxBytes) {
        await reader.cancel();
        throw new Error("ALANUBE_RESPONSE_TOO_LARGE");
      }
      text += decoder.decode(chunk.value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    reader.releaseLock();
  }
}

function parseJsonSafely(text: string) {
  if (!text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch {
    return { raw: "[NON_JSON_REDACTED]" };
  }
}
