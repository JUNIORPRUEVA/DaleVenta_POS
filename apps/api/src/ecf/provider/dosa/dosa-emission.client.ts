import {
  DOSA_AUTH_HEADER,
  DOSA_ECF_CREDIT_NOTE_PATH,
  DOSA_ECF_EMISSION_PATH,
  type DosaEcfRequestBody,
} from "./dosa-ecf.contract";

/**
 * Endpoint según el tipo de comprobante.
 *
 * El proveedor documenta **dos** rutas distintas: `EnviarFactura` para los
 * comprobantes de venta (E31, E32) y `NotaDesdeFactura` para las notas de
 * crédito (E34). Enviar una nota de crédito a `EnviarFactura` es un error de
 * contrato, así que la ruta se deriva del `tipoeCF` del cuerpo y no de una
 * constante fija.
 */
export function emissionPathFor(body: DosaEcfRequestBody): string {
  return body.encabezado?.idDoc?.tipoeCF === "34"
    ? DOSA_ECF_CREDIT_NOTE_PATH
    : DOSA_ECF_EMISSION_PATH;
}
import {
  classifyDosaResponse,
  type DosaResponseClassification,
} from "./dosa-response.mapper";

/**
 * Cliente HTTP de emisión de DOSA — **sin autorización de red por defecto**.
 *
 * Todo lo peligroso está desactivado hasta que se habilite explícitamente:
 *
 * * **`DOSA_EMISSION_ENABLED`** debe valer `true`; si no, `send()` no hace ni una
 *   petición y devuelve `EMISSION_DISABLED`. Así este archivo puede existir en
 *   el árbol sin que nada salga a internet por accidente.
 * * **Producción** exige además `DOSA_PRODUCTION_EMISSION_ENABLED=true`. Una
 *   clave de TEST nunca puede apuntar al host de producción: si el entorno es
 *   `PRODUCTION` y la clave no está marcada como de producción, se bloquea.
 * * **Sin reintentos automáticos.** Un timeout o un 502 dejan el intento en
 *   `UNCONFIRMED`, porque el comprobante **pudo** haberse recibido. Reintentar a
 *   ciegas consumiría la secuencia o duplicaría el documento.
 * * **Idempotencia**: la misma clave no se envía dos veces; el segundo intento
 *   se rechaza mientras el primero sigue vivo y después de completarse.
 * * **Cortacircuitos**: tras N fallos consecutivos se abre y no se envía nada
 *   durante el enfriamiento.
 * * **Redacción**: cualquier cabecera sensible se sustituye antes de exponerla.
 */

export type DosaHttpResponse = { status: number; body: string };

/** Transporte inyectable. En producción envuelve `fetch`; en pruebas, un doble. */
export interface DosaHttpTransport {
  post(
    url: string,
    init: {
      headers: Record<string, string>;
      body: string;
      signal: AbortSignal;
    },
  ): Promise<DosaHttpResponse>;
}

export type DosaEmissionEnvironment = "TEST" | "PRODUCTION";

export type DosaEmissionConfig = {
  enabled: boolean;
  environment: DosaEmissionEnvironment;
  baseUrl: string;
  apiKey: string;
  apiKeyIsProduction: boolean;
  productionEnabled: boolean;
  /** RNC de prueba exigido por la politica de identidad en TEST. */
  testRnc: string;
  timeoutMs: number;
  breakerThreshold: number;
  breakerCooldownMs: number;
};

export const DOSA_EMISSION_BLOCKED = {
  disabled: "DOSA_EMISSION_DISABLED",
  productionNotAuthorized: "DOSA_PRODUCTION_EMISSION_NOT_AUTHORIZED",
  apiKeyMissing: "DOSA_API_KEY_MISSING",
  keyEnvironmentMismatch: "DOSA_KEY_ENVIRONMENT_MISMATCH",
  baseUrlMissing: "DOSA_BASE_URL_MISSING",
  breakerOpen: "DOSA_BREAKER_OPEN",
  duplicateKey: "DOSA_DUPLICATE_IDEMPOTENCY_KEY",
  alreadySent: "DOSA_IDEMPOTENCY_KEY_ALREADY_SENT",
} as const;

/** Configuración desde entorno. Sin banderas, todo queda desactivado. */
export function readDosaEmissionConfig(
  env: NodeJS.ProcessEnv & {
    DOSA_EMISSION_ENABLED?: string;
    DOSA_EMISSION_ENVIRONMENT?: string;
    DOSA_BASE_URL?: string;
    DOSA_TEST_API_KEY?: string;
    DOSA_PRODUCTION_API_KEY?: string;
    DOSA_PRODUCTION_EMISSION_ENABLED?: string;
    DOSA_EMISSION_TIMEOUT_MS?: string;
    DOSA_TEST_RNC?: string;
  },
): DosaEmissionConfig {
  const environment: DosaEmissionEnvironment =
    (env.DOSA_EMISSION_ENVIRONMENT ?? "").trim().toUpperCase() === "PRODUCTION"
      ? "PRODUCTION"
      : "TEST";

  const testKey = (env.DOSA_TEST_API_KEY ?? "").trim();
  const prodKey = (env.DOSA_PRODUCTION_API_KEY ?? "").trim();
  const apiKey = environment === "PRODUCTION" ? prodKey : testKey;

  const timeout = Number.parseInt(env.DOSA_EMISSION_TIMEOUT_MS ?? "", 10);

  return {
    enabled: (env.DOSA_EMISSION_ENABLED ?? "").trim().toLowerCase() === "true",
    environment,
    baseUrl: (env.DOSA_BASE_URL ?? "").trim().replace(/\/+$/, ""),
    apiKey,
    apiKeyIsProduction: environment === "PRODUCTION" && prodKey.length > 0,
    productionEnabled:
      (env.DOSA_PRODUCTION_EMISSION_ENABLED ?? "").trim().toLowerCase() === "true",
    testRnc: (env.DOSA_TEST_RNC ?? "").trim(),
    timeoutMs: Number.isFinite(timeout) && timeout > 0 ? timeout : 15_000,
    breakerThreshold: 3,
    breakerCooldownMs: 60_000,
  };
}

/** Encabezados seguros para registrar. Nunca incluye el valor de la clave. */
export function redactDosaHeaders(
  headers: Record<string, string>,
): Record<string, string> {
  const safe: Record<string, string> = {};
  for (const [key, value] of Object.entries(headers)) {
    safe[key] = /api[-_]?key|authorization|secret|token/i.test(key)
      ? `[REDACTED:${value.length}]`
      : value;
  }
  return safe;
}

export type DosaSendResult =
  | { ok: false; blockedReason: string }
  | {
      ok: false;
      transportFailure: "TIMEOUT" | "NETWORK" | "HTTP";
      /** `true` cuando el comprobante pudo haberse recibido y NO se debe reintentar a ciegas. */
      unconfirmed: boolean;
      status: number | null;
      /**
       * Solo `true` cuando el propio proveedor afirma que la DGII no recibio
       * nada (`estado: "Error de envio"`). En cualquier otro fallo el reintento
       * con el mismo eNCF podria duplicar el comprobante.
       */
      retryPermitted: boolean;
      classification: DosaResponseClassification | null;
      /** Cuerpo crudo para la evidencia. `null` si no hubo respuesta legible. */
      raw: unknown | null;
    }
  | {
      ok: true;
      status: number;
      classification: DosaResponseClassification;
      /** Cuerpo crudo tal como lo devolvio el proveedor. */
      raw: unknown;
      redactedHeaders: Record<string, string>;
    };

export class DosaEmissionClient {
  private readonly sent = new Set<string>();
  private readonly inFlight = new Set<string>();
  private consecutiveFailures = 0;
  private openedAt: number | null = null;

  constructor(
    private readonly transport: DosaHttpTransport,
    private readonly config: DosaEmissionConfig,
    private readonly now: () => number = Date.now,
  ) {}

  /** Estado del cortacircuitos, para diagnóstico. */
  breakerState(): "CLOSED" | "OPEN" {
    if (this.openedAt === null) return "CLOSED";
    if (this.now() - this.openedAt >= this.config.breakerCooldownMs) {
      this.openedAt = null;
      this.consecutiveFailures = 0;
      return "CLOSED";
    }
    return "OPEN";
  }

  async sendEcf(input: {
    body: DosaEcfRequestBody;
    idempotencyKey: string;
  }): Promise<DosaSendResult> {
    if (!this.config.enabled) {
      return { ok: false, blockedReason: DOSA_EMISSION_BLOCKED.disabled };
    }
    if (this.config.environment === "PRODUCTION" && !this.config.productionEnabled) {
      return {
        ok: false,
        blockedReason: DOSA_EMISSION_BLOCKED.productionNotAuthorized,
      };
    }
    if (!this.config.apiKey) {
      return { ok: false, blockedReason: DOSA_EMISSION_BLOCKED.apiKeyMissing };
    }
    if (this.config.environment === "PRODUCTION" && !this.config.apiKeyIsProduction) {
      return {
        ok: false,
        blockedReason: DOSA_EMISSION_BLOCKED.keyEnvironmentMismatch,
      };
    }
    if (!this.config.baseUrl) {
      return { ok: false, blockedReason: DOSA_EMISSION_BLOCKED.baseUrlMissing };
    }
    if (this.breakerState() === "OPEN") {
      return { ok: false, blockedReason: DOSA_EMISSION_BLOCKED.breakerOpen };
    }
    if (this.sent.has(input.idempotencyKey)) {
      return {
        ok: false,
        blockedReason: DOSA_EMISSION_BLOCKED.alreadySent,
      };
    }
    if (this.inFlight.has(input.idempotencyKey)) {
      return { ok: false, blockedReason: DOSA_EMISSION_BLOCKED.duplicateKey };
    }
    if (input.idempotencyKey.trim().length === 0) {
      return { ok: false, blockedReason: DOSA_EMISSION_BLOCKED.duplicateKey };
    }

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      [DOSA_AUTH_HEADER]: this.config.apiKey,
    };
    const url = `${this.config.baseUrl}${emissionPathFor(input.body)}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);

    this.inFlight.add(input.idempotencyKey);
    try {
      const response = await this.transport.post(url, {
        headers,
        body: JSON.stringify(input.body),
        signal: controller.signal,
      });

      if (response.status >= 500) {
        // 5xx: el proveedor pudo haberlo recibido. La unica excepcion
        // documentada es 502 con `estado: "Error de envio"`, donde el propio
        // proveedor afirma que la DGII no recibio el eCF y autoriza reenviar
        // con el MISMO eNCF.
        this.recordFailure();
        const classification = safeClassify(response.body);
        const notReceived = classification?.outcome === "NOT_RECEIVED";
        return {
          ok: false,
          transportFailure: "HTTP",
          unconfirmed: !notReceived,
          status: response.status,
          retryPermitted: notReceived,
          classification,
          raw: classification === null ? null : safeParse(response.body),
        };
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(response.body) as unknown;
      } catch {
        this.recordFailure();
        return {
          ok: false,
          transportFailure: "HTTP",
          unconfirmed: true,
          status: response.status,
          retryPermitted: false,
          classification: null,
          raw: null,
        };
      }

      const classification = classifyDosaResponse(parsed);
      // Se marca como enviado en cuanto hubo respuesta interpretable: un segundo
      // envío de la misma clave consumiría la secuencia.
      this.sent.add(input.idempotencyKey);
      this.consecutiveFailures = 0;

      return {
        ok: true,
        status: response.status,
        classification,
        raw: parsed,
        redactedHeaders: redactDosaHeaders(headers),
      };
    } catch {
      // Timeout (abort) o error de red: estado desconocido, nunca reintento ciego.
      this.recordFailure();
      return {
        ok: false,
        transportFailure: controller.signal.aborted ? "TIMEOUT" : "NETWORK",
        unconfirmed: true,
        status: null,
        retryPermitted: false,
        classification: null,
        raw: null,
      };
    } finally {
      clearTimeout(timer);
      this.inFlight.delete(input.idempotencyKey);
    }
  }

  private recordFailure(): void {
    this.consecutiveFailures += 1;
    if (this.consecutiveFailures >= this.config.breakerThreshold) {
      this.openedAt = this.now();
    }
  }
}

/** Transporte real basado en `fetch`. Solo se usa si la bandera está encendida. */
export function createFetchDosaTransport(): DosaHttpTransport {
  return {
    async post(url, init) {
      const response = await fetch(url, {
        method: "POST",
        headers: init.headers,
        body: init.body,
        signal: init.signal,
      });
      return { status: response.status, body: await response.text() };
    },
  };
}

/** Clasifica un cuerpo sin lanzar: un cuerpo ilegible no es una clasificación. */
function safeClassify(body: string): DosaResponseClassification | null {
  const parsed = safeParse(body);
  return parsed === null ? null : classifyDosaResponse(parsed);
}

/** Parsea sin lanzar. `null` si el cuerpo no es JSON. */
function safeParse(body: string): unknown | null {
  const text = (body ?? "").trim();
  if (text.length === 0) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}
