import { DOSA_ECF_CREDIT_NOTE_PATH, DOSA_ECF_EMISSION_PATH } from "./dosa-ecf.contract";

/**
 * Cliente de **consultas** a la API de DOSA.
 *
 * Contrato confirmado por el proveedor (2026-11-02):
 *
 * * Las consultas se autentican con la cabecera `X-Dosa-Secret-Key`.
 * * Su valor es la clave secreta `sk_...`.
 * * **No se firma cada solicitud** (a diferencia del webhook, que sí lleva
 *   `X-Dosa-Signature` con HMAC).
 *
 * Este cliente existe para tener la superficie lista y las credenciales
 * separadas. **Hoy no tiene ningún punto de llamada y no debe tenerlo**: los
 * endpoints concretos de consulta no están confirmados, y el propio encargo
 * prohíbe hacer llamadas reales hasta tenerlos. Por eso hay tres barreras
 * antes de tocar la red:
 *
 * 1. `DOSA_API_QUERIES_ENABLED` debe valer `true` (por defecto, apagado).
 * 2. Debe existir `DOSA_SECRET_KEY` con forma de clave secreta (`sk_...`).
 * 3. Debe existir `DOSA_BASE_URL`.
 *
 * Y una cuarta, estructural: la ruta pedida **no puede ser** una de emisión.
 * Emitir es otro camino, con otras credenciales (`X-API-KEY`, TEST/producción).
 * Mezclarlos permitiría que un fallo de consulta terminara enviando un
 * comprobante.
 *
 * La clave nunca se registra, nunca se devuelve y nunca viaja en el resultado.
 */

/** Cabecera de autenticación de consultas. Confirmada por el proveedor. */
export const DOSA_QUERY_AUTH_HEADER = "X-Dosa-Secret-Key";

/** Prefijo de la clave secreta de consulta. Confirmado por el proveedor. */
export const DOSA_SECRET_KEY_PREFIX = "sk_";

export const DOSA_DEFAULT_QUERY_TIMEOUT_MS = 15_000;

export type DosaQueryAuthConfig = {
  baseUrl: string;
  /** Clave `sk_...`. Nunca se registra ni se devuelve. */
  secretKey: string | null;
  enabled: boolean;
  timeoutMs: number;
};

export type DosaQueryAuthEnv = NodeJS.ProcessEnv & {
  DOSA_BASE_URL?: string;
  DOSA_SECRET_KEY?: string;
  DOSA_API_QUERIES_ENABLED?: string;
  DOSA_QUERY_TIMEOUT_MS?: string;
};

export function readDosaQueryAuthConfig(
  env: DosaQueryAuthEnv = process.env,
): DosaQueryAuthConfig {
  const timeout = Number.parseInt((env.DOSA_QUERY_TIMEOUT_MS ?? "").trim(), 10);
  return {
    baseUrl: (env.DOSA_BASE_URL ?? "").trim().replace(/\/+$/, ""),
    secretKey: emptyToNull(env.DOSA_SECRET_KEY),
    enabled: (env.DOSA_API_QUERIES_ENABLED ?? "").trim().toLowerCase() === "true",
    timeoutMs:
      Number.isFinite(timeout) && timeout > 0
        ? Math.min(timeout, 120_000)
        : DOSA_DEFAULT_QUERY_TIMEOUT_MS,
  };
}

export type DosaQueryResult =
  | { ok: true; status: number; body: unknown }
  | { ok: false; code: string; reason: string; status?: number };

export type DosaFetchLike = (
  input: string,
  init: {
    method: string;
    headers: Record<string, string>;
    signal?: AbortSignal;
  },
) => Promise<{ status: number; text(): Promise<string> }>;

/**
 * Rutas que este cliente NUNCA puede llamar: emisión y nota de crédito.
 * Se comparan en minúsculas sobre el path normalizado.
 */
const FORBIDDEN_PATHS: readonly string[] = [
  DOSA_ECF_EMISSION_PATH.toLowerCase(),
  DOSA_ECF_CREDIT_NOTE_PATH.toLowerCase(),
];

export class DosaApiClient {
  constructor(
    private readonly config: DosaQueryAuthConfig = readDosaQueryAuthConfig(),
    private readonly fetchImpl?: DosaFetchLike,
  ) {}

  /** `true` si la configuración permitiría una llamada. No la hace. */
  describeReadiness(): {
    ready: boolean;
    blockingReasons: readonly string[];
    /** Solo presencia. Nunca el valor. */
    hasSecretKey: boolean;
  } {
    const reasons = this.configurationProblems();
    return {
      ready: reasons.length === 0,
      blockingReasons: reasons,
      hasSecretKey: this.config.secretKey !== null,
    };
  }

  /**
   * Consulta GET autenticada con `X-Dosa-Secret-Key`.
   *
   * Sin configuración completa no se toca la red: se devuelve un resultado con
   * el motivo. Fallar cerrado es preferible a una petición a medio autenticar.
   */
  async getJson(path: string): Promise<DosaQueryResult> {
    const problems = this.configurationProblems();
    if (problems.length > 0) {
      return {
        ok: false,
        code: "ECF_DOSA_QUERY_NOT_CONFIGURED",
        reason: problems.join("+"),
      };
    }

    const normalized = normalizePath(path);
    if (normalized === null) {
      return {
        ok: false,
        code: "ECF_DOSA_QUERY_INVALID_PATH",
        reason: "PATH_MUST_BE_ABSOLUTE",
      };
    }
    if (FORBIDDEN_PATHS.includes(normalized.toLowerCase())) {
      // Este cliente no emite. Ni por error de programación.
      return {
        ok: false,
        code: "ECF_DOSA_QUERY_NOT_FOR_EMISSION",
        reason: "EMISSION_PATH_IS_NOT_A_QUERY",
      };
    }

    const doFetch = this.fetchImpl ?? (globalThis.fetch as unknown as DosaFetchLike);
    if (typeof doFetch !== "function") {
      return {
        ok: false,
        code: "ECF_DOSA_QUERY_TRANSPORT_UNAVAILABLE",
        reason: "FETCH_NOT_AVAILABLE",
      };
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);
    try {
      const response = await doFetch(`${this.config.baseUrl}${normalized}`, {
        method: "GET",
        headers: {
          [DOSA_QUERY_AUTH_HEADER]: this.config.secretKey as string,
          Accept: "application/json",
        },
        signal: controller.signal,
      });
      const text = await response.text();
      if (response.status >= 200 && response.status < 300) {
        return { ok: true, status: response.status, body: safeJson(text) };
      }
      return {
        ok: false,
        status: response.status,
        code: "ECF_DOSA_QUERY_HTTP_ERROR",
        reason: `HTTP_${response.status}`,
      };
    } catch (error) {
      // El mensaje de un error de red puede arrastrar la URL; la clave nunca,
      // porque no se incluye en la URL.
      return {
        ok: false,
        code: "ECF_DOSA_QUERY_TRANSPORT_ERROR",
        reason: error instanceof Error ? error.name : "UNKNOWN",
      };
    } finally {
      clearTimeout(timer);
    }
  }

  private configurationProblems(): string[] {
    const problems: string[] = [];
    if (!this.config.enabled) problems.push("QUERIES_DISABLED");
    if (!this.config.secretKey) problems.push("SECRET_KEY_MISSING");
    else if (!this.config.secretKey.startsWith(DOSA_SECRET_KEY_PREFIX)) {
      // Evita que una clave de emisión acabe en la cabecera de consulta.
      problems.push("SECRET_KEY_MALFORMED");
    }
    if (this.config.baseUrl.length === 0) problems.push("BASE_URL_MISSING");
    return problems;
  }
}

function emptyToNull(value: string | undefined): string | null {
  const trimmed = (value ?? "").trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizePath(path: string): string | null {
  const raw = (path ?? "").trim();
  if (raw.length === 0 || !raw.startsWith("/")) return null;
  return raw;
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    // Sin cuerpo JSON no se inventa estructura.
    return null;
  }
}
