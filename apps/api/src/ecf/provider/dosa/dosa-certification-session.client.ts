/**
 * Cliente del contrato de **sesiones de certificación** de DOSA.
 *
 * Contrato entregado por el proveedor (2026-11-04):
 *
 * * `POST {base}/api/certificacion/sesiones`
 * * Cabecera `X-Dosa-Secret-Key` con la clave **de servidor** (`sk_...`).
 * * Cuerpo: `{ rnc_emisor, correo, return_url? }`.
 * * Respuesta `201` con `{ url, path, token, expires_at, postulacion_id, prueba }`.
 *
 * Reglas de este módulo, que no se negocian:
 *
 * 1. **Solo backend.** La clave secreta nunca sale de aquí: no se registra, no
 *    se devuelve y no viaja en ningún resultado.
 * 2. **No es la API de emisión.** Emitir usa `X-API-KEY` y otro host lógico
 *    (`/fe/api/emision/...`). Aquí se rechaza explícitamente esa ruta para que
 *    un error de configuración no pueda acabar emitiendo un comprobante.
 * 3. **Falla cerrado.** Sin bandera, sin clave o con clave mal formada, no se
 *    toca la red.
 * 4. **Respuesta validada al detalle.** Un `201` no basta: si `url`, `token`,
 *    `expires_at`, `postulacion_id` o `prueba` no tienen la forma esperada, el
 *    resultado es un fallo, no una sesión a medias.
 * 5. **Incertidumbre explícita.** Un timeout o un 5xx no significa «no se creó»:
 *    se marca como incierto para que quien llama **no** reintente a ciegas y
 *    duplique la postulación.
 */

import { DOSA_ECF_EMISSION_PATH, DOSA_ECF_CREDIT_NOTE_PATH } from "./dosa-ecf.contract";

/** Ruta confirmada del contrato de sesiones. */
export const DOSA_CERTIFICATION_SESSIONS_PATH = "/api/certificacion/sesiones";

/** Cabecera del contrato de sesiones (clave de servidor). */
export const DOSA_SESSION_AUTH_HEADER = "X-Dosa-Secret-Key";

/** Prefijo que debe tener la clave de servidor. */
export const DOSA_SERVER_SECRET_PREFIX = "sk_";

export const DOSA_SESSION_DEFAULT_TIMEOUT_MS = 15_000;

/** Base por defecto del API de DOSA (sin `/fe`, que es solo de emisión). */
export const DOSA_SESSION_DEFAULT_BASE_URL = "https://dosasystem.com";

export type DosaCertificationSession = {
  /** Enlace oficial de la sesión. Secreto de un solo uso: no se registra. */
  url: string;
  path: string;
  /** Token de la sesión. Nunca se registra ni se devuelve al navegador. */
  token: string;
  expiresAt: string;
  postulacionId: string;
  prueba: boolean;
};

export type DosaSessionConfig = {
  baseUrl: string;
  secretKey: string | null;
  enabled: boolean;
  timeoutMs: number;
  /** Orígenes permitidos para `return_url`. */
  allowedReturnOrigins: readonly string[];
};

export type DosaSessionEnv = NodeJS.ProcessEnv & {
  DOSA_SESSION_BASE_URL?: string;
  DOSA_SECRET_KEY?: string;
  DOSA_CERTIFICATION_SESSIONS_ENABLED?: string;
  DOSA_SESSION_TIMEOUT_MS?: string;
  DOSA_SESSION_ALLOWED_RETURN_ORIGINS?: string;
};

function emptyToNull(value: string | undefined | null): string | null {
  const trimmed = (value ?? "").trim();
  return trimmed.length > 0 ? trimmed : null;
}

function parseOrigins(raw: string | undefined): readonly string[] {
  return (raw ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase().replace(/\/+$/, ""))
    .filter((item) => item.length > 0);
}

export function readDosaSessionConfig(
  env: DosaSessionEnv = process.env,
): DosaSessionConfig {
  const timeout = Number.parseInt((env.DOSA_SESSION_TIMEOUT_MS ?? "").trim(), 10);
  return {
    baseUrl: (
      emptyToNull(env.DOSA_SESSION_BASE_URL) ?? DOSA_SESSION_DEFAULT_BASE_URL
    ).replace(/\/+$/, ""),
    secretKey: emptyToNull(env.DOSA_SECRET_KEY),
    enabled:
      (env.DOSA_CERTIFICATION_SESSIONS_ENABLED ?? "").trim().toLowerCase() ===
      "true",
    timeoutMs:
      Number.isFinite(timeout) && timeout > 0
        ? Math.min(timeout, 120_000)
        : DOSA_SESSION_DEFAULT_TIMEOUT_MS,
    allowedReturnOrigins: parseOrigins(env.DOSA_SESSION_ALLOWED_RETURN_ORIGINS),
  };
}

export type DosaSessionFailureCode =
  | "DOSA_SESSION_DISABLED"
  | "DOSA_SESSION_SECRET_MISSING"
  | "DOSA_SESSION_SECRET_MALFORMED"
  | "DOSA_SESSION_BASE_URL_INVALID"
  | "DOSA_SESSION_RNC_INVALID"
  | "DOSA_SESSION_EMAIL_INVALID"
  | "DOSA_SESSION_RETURN_URL_NOT_ALLOWED"
  | "DOSA_SESSION_NETWORK_UNCERTAIN"
  | "DOSA_SESSION_BAD_STATUS"
  | "DOSA_SESSION_MALFORMED_RESPONSE"
  | "DOSA_SESSION_EXPIRED";

export type DosaSessionResult =
  | { ok: true; status: 201; session: DosaCertificationSession }
  | {
      ok: false;
      code: DosaSessionFailureCode;
      reason: string;
      status?: number;
      /** `true` cuando no se puede saber si DOSA creó la sesión. */
      uncertain?: boolean;
    };

export type DosaFetchLike = (
  input: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body?: string;
    signal?: AbortSignal;
  },
) => Promise<{ status: number; text(): Promise<string> }>;

/**
 * Oculta el token de una URL de sesión. Para diagnóstico y trazas.
 *
 * Devuelve origen + ruta, sin query ni fragmento: en `…/sesion/abc?token=xyz`
 * la parte útil es el path, y el resto es la credencial.
 */
export function redactSessionUrl(value: string): string {
  try {
    const parsed = new URL(value);
    return `${parsed.origin}${parsed.pathname}`;
  } catch {
    return "<url-invalida>";
  }
}

/** Rutas prohibidas en este cliente: emisión y nota de crédito. */
const FORBIDDEN_PATHS: readonly string[] = [
  DOSA_ECF_EMISSION_PATH.toLowerCase(),
  DOSA_ECF_CREDIT_NOTE_PATH.toLowerCase(),
];

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** RNC (9 dígitos) o cédula (11). Se aceptan guiones y se ignoran. */
export function normalizeDosaRnc(value: string): string | null {
  const digits = (value ?? "").replace(/[\s-]/g, "");
  return /^\d{9}$|^\d{11}$/.test(digits) ? digits : null;
}

export function isDosaEmailValid(value: string): boolean {
  const trimmed = (value ?? "").trim();
  return trimmed.length > 3 && trimmed.length <= 254 && EMAIL_PATTERN.test(trimmed);
}

export type DosaSessionRequest = {
  rncEmisor: string;
  correo: string;
  returnUrl?: string | null;
};

export class DosaCertificationSessionClient {
  constructor(
    private readonly config: DosaSessionConfig = readDosaSessionConfig(),
    private readonly fetchImpl?: DosaFetchLike,
  ) {}

  /** `true` si la configuración permitiría una llamada. No la hace. */
  describeReadiness(): {
    ready: boolean;
    blockingReasons: readonly DosaSessionFailureCode[];
    hasSecretKey: boolean;
  } {
    const reasons = this.configurationProblems();
    return {
      ready: reasons.length === 0,
      blockingReasons: reasons,
      hasSecretKey: this.config.secretKey !== null,
    };
  }

  private configurationProblems(): DosaSessionFailureCode[] {
    const problems: DosaSessionFailureCode[] = [];
    if (!this.config.enabled) problems.push("DOSA_SESSION_DISABLED");
    if (!this.config.secretKey) problems.push("DOSA_SESSION_SECRET_MISSING");
    else if (!this.config.secretKey.startsWith(DOSA_SERVER_SECRET_PREFIX)) {
      problems.push("DOSA_SESSION_SECRET_MALFORMED");
    }
    if (!/^https?:\/\//i.test(this.config.baseUrl)) {
      problems.push("DOSA_SESSION_BASE_URL_INVALID");
    }
    return problems;
  }

  /**
   * Crea una sesión de certificación.
   *
   * El llamador debe pasar el RNC y el correo **de la empresa autenticada**:
   * este cliente no los deduce ni los acepta del navegador.
   */
  async createSession(request: DosaSessionRequest): Promise<DosaSessionResult> {
    const problems = this.configurationProblems();
    if (problems.length > 0) {
      return {
        ok: false,
        code: problems[0],
        reason: problems.join(","),
      };
    }

    const rnc = normalizeDosaRnc(request.rncEmisor);
    if (!rnc) {
      return {
        ok: false,
        code: "DOSA_SESSION_RNC_INVALID",
        reason: "El RNC de la empresa no tiene 9 ni 11 dígitos.",
      };
    }
    const correo = (request.correo ?? "").trim();
    if (!isDosaEmailValid(correo)) {
      return {
        ok: false,
        code: "DOSA_SESSION_EMAIL_INVALID",
        reason: "El correo de la empresa no es válido.",
      };
    }
    const returnUrl = (request.returnUrl ?? "").trim();
    if (returnUrl.length > 0) {
      const allowed = this.isReturnUrlAllowed(returnUrl);
      if (!allowed) {
        return {
          ok: false,
          code: "DOSA_SESSION_RETURN_URL_NOT_ALLOWED",
          reason: "return_url no es https o su origen no está permitido.",
        };
      }
    }

    const endpoint = `${this.config.baseUrl}${DOSA_CERTIFICATION_SESSIONS_PATH}`;
    for (const forbidden of FORBIDDEN_PATHS) {
      if (endpoint.toLowerCase().includes(forbidden)) {
        return {
          ok: false,
          code: "DOSA_SESSION_BASE_URL_INVALID",
          reason: "La base apunta a una ruta de emisión.",
        };
      }
    }

    const body = JSON.stringify({
      rnc_emisor: rnc,
      correo,
      ...(returnUrl.length > 0 ? { return_url: returnUrl } : {}),
    });

    let response: { status: number; text(): Promise<string> };
    try {
      response = await this.doFetch(endpoint, body);
    } catch {
      // Timeout o corte de red: DOSA pudo haber creado la sesión.
      return {
        ok: false,
        code: "DOSA_SESSION_NETWORK_UNCERTAIN",
        reason: "No hubo respuesta del proveedor.",
        uncertain: true,
      };
    }

    if (response.status === 201) {
      const raw = await safeText(response);
      return this.parseCreated(raw);
    }

    if (response.status >= 500) {
      return {
        ok: false,
        code: "DOSA_SESSION_NETWORK_UNCERTAIN",
        reason: "El proveedor respondió con un error de servidor.",
        status: response.status,
        uncertain: true,
      };
    }

    return {
      ok: false,
      code: "DOSA_SESSION_BAD_STATUS",
      reason: `El proveedor respondió ${response.status}.`,
      status: response.status,
    };
  }

  private async doFetch(
    endpoint: string,
    body: string,
  ): Promise<{ status: number; text(): Promise<string> }> {
    const init = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        [DOSA_SESSION_AUTH_HEADER]: this.config.secretKey as string,
      },
      body,
      signal: this.timeoutSignal(),
    };
    if (this.fetchImpl) return this.fetchImpl(endpoint, init);
    const globalFetch = (globalThis as { fetch?: DosaFetchLike }).fetch;
    if (!globalFetch) throw new Error("sin fetch");
    return globalFetch(endpoint, init);
  }

  private timeoutSignal(): AbortSignal | undefined {
    const controller = (globalThis as { AbortController?: typeof AbortController })
      .AbortController;
    if (!controller) return undefined;
    const instance = new controller();
    const timer = setTimeout(() => instance.abort(), this.config.timeoutMs);
    // No mantiene vivo el proceso por un temporizador de red.
    (timer as unknown as { unref?: () => void }).unref?.();
    return instance.signal;
  }

  private isReturnUrlAllowed(value: string): boolean {
    let parsed: URL;
    try {
      parsed = new URL(value);
    } catch {
      return false;
    }
    if (parsed.protocol !== "https:") return false;
    if (this.config.allowedReturnOrigins.length === 0) return false;
    return this.config.allowedReturnOrigins.includes(parsed.origin.toLowerCase());
  }

  private parseCreated(raw: string): DosaSessionResult {
    let payload: unknown;
    try {
      payload = JSON.parse(raw);
    } catch {
      return {
        ok: false,
        code: "DOSA_SESSION_MALFORMED_RESPONSE",
        reason: "La respuesta no es JSON.",
        status: 201,
      };
    }
    if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
      return {
        ok: false,
        code: "DOSA_SESSION_MALFORMED_RESPONSE",
        reason: "La respuesta no es un objeto.",
        status: 201,
      };
    }
    const record = payload as Record<string, unknown>;
    const url = typeof record.url === "string" ? record.url.trim() : "";
    const path = typeof record.path === "string" ? record.path.trim() : "";
    const token = typeof record.token === "string" ? record.token.trim() : "";
    const expiresAt =
      typeof record.expires_at === "string" ? record.expires_at.trim() : "";
    const postulacionId =
      record.postulacion_id === null || record.postulacion_id === undefined
        ? ""
        : String(record.postulacion_id).trim();
    const prueba = record.prueba;

    if (!this.isSessionUrlUsable(url)) {
      return this.malformed("url ausente, no https o de otro origen.");
    }
    if (!path.startsWith("/")) return this.malformed("path inválido.");
    if (token.length < 8) return this.malformed("token ausente o demasiado corto.");
    if (!postulacionId) return this.malformed("postulacion_id ausente.");
    if (typeof prueba !== "boolean") return this.malformed("prueba no es booleano.");

    const expiry = Date.parse(expiresAt);
    if (!Number.isFinite(expiry)) return this.malformed("expires_at ilegible.");
    if (expiry <= Date.now()) {
      return {
        ok: false,
        code: "DOSA_SESSION_EXPIRED",
        reason: "La sesión llegó ya caducada.",
        status: 201,
      };
    }

    return {
      ok: true,
      status: 201,
      session: {
        url,
        path,
        token,
        expiresAt: new Date(expiry).toISOString(),
        postulacionId,
        prueba,
      },
    };
  }

  private malformed(reason: string): DosaSessionResult {
    return {
      ok: false,
      code: "DOSA_SESSION_MALFORMED_RESPONSE",
      reason,
      status: 201,
    };
  }

  /**
   * La URL debe ser https y del mismo origen que la base del API. Así un
   * proveedor comprometido no puede enviarnos a otro dominio.
   */
  private isSessionUrlUsable(value: string): boolean {
    let parsed: URL;
    let base: URL;
    try {
      parsed = new URL(value);
      base = new URL(this.config.baseUrl);
    } catch {
      return false;
    }
    if (parsed.protocol !== "https:") return false;
    return parsed.host.toLowerCase() === base.host.toLowerCase();
  }
}

async function safeText(response: { text(): Promise<string> }): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "";
  }
}
