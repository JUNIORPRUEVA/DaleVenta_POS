import { createHash } from "node:crypto";
import {
  DOSA_AUTH_HEADER,
  DOSA_ECF_CREDIT_NOTE_PATH,
  DOSA_ECF_EMISSION_PATH,
  type DosaEcfRequestBody,
} from "./dosa-ecf.contract";
import { toDosaOutboundRequest, type DosaOutboundRequestBody } from "./dosa-request.serializer";

/**
 * Endpoint según el tipo de comprobante.
 *
 * El proveedor documenta **dos** rutas distintas: `EnviarFactura` para los
 * comprobantes de venta (E31, E32) y `NotaDesdeFactura` para las notas de
 * crédito (E34). Enviar una nota de crédito a `EnviarFactura` es un error de
 * contrato, así que la ruta se deriva del `tipoeCF` del cuerpo y no de una
 * constante fija.
 */
export function emissionPathFor(body: DosaEcfRequestBody | DosaOutboundRequestBody): string {
  if (body.encabezado?.idDoc?.tipoeCF !== "34") return DOSA_ECF_EMISSION_PATH;
  const query = new URLSearchParams({
    nuevoENCF: body.encabezado.idDoc.eNCF, tipoeCF: "34",
    fechaEmision: body.encabezado.idDoc.fechaEmision,
  });
  if (body.informacionReferencia) {
    query.set("codigoModificacion", body.informacionReferencia.codigoModificacion);
    if (body.informacionReferencia.RazonModificacion) query.set("razonModificacion", body.informacionReferencia.RazonModificacion);
  }
  return `${DOSA_ECF_CREDIT_NOTE_PATH}?${query.toString()}`;
}
import {
  classifyDosaResponse,
  type DosaResponseClassification,
} from "./dosa-response.mapper";
import { outboundAuthViolation } from "./dosa-outbound-auth.policy";

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
 * * **Recuperación acotada.** Sólo el despacho persistido puede autorizar hasta
 *   tres llamadas con exactamente los mismos bytes, ruta y e-NCF ante timeout,
 *   red o 5xx. Cada repetición exige autorización y auditoría previas. Sin ese
 *   observador se hace una sola llamada; un resultado incierto queda sin confirmar.
 * * **Idempotencia**: se conserva una sola operación lógica por clave, incluso
 *   durante la recuperación. Se bloquean los envíos paralelos y posteriores a
 *   una respuesta interpretable; el orquestador impide otro despacho persistido.
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
       * nada (`estado: "Error de envio"`). Este indicador no autoriza la
       * recuperación auditada del despacho, que exige su propio observador.
       */
      retryPermitted: boolean;
      classification: DosaResponseClassification | null;
      /** Cuerpo crudo para la evidencia. `null` si no hubo respuesta legible. */
      raw: unknown | null;
      responseHash?: string;
    }
  | {
      ok: true;
      status: number;
      classification: DosaResponseClassification;
      /** Cuerpo crudo tal como lo devolvio el proveedor. */
      raw: unknown;
      redactedHeaders: Record<string, string>;
    };

export type DosaReplayInfo = Readonly<{
  ordinal: 2 | 3;
  reason: "TIMEOUT" | "NETWORK" | "HTTP_5XX";
  httpStatus: number | null;
  bodyHash: string;
  pathHash: string;
  requestHash: string;
  previousResponseHash: string | null;
}>;
export type DosaReplayObserver = (info: DosaReplayInfo) => Promise<boolean>;

/** Freeze bytes and full path (including E34 query) before the first request. */
export function freezeDosaHttpRequest(body: DosaEcfRequestBody | DosaOutboundRequestBody) {
  const path = emissionPathFor(body);
  const bodyText = JSON.stringify(toDosaOutboundRequest(body));
  const hash = (value: string) => createHash("sha256").update(value).digest("hex");
  return Object.freeze({ path, bodyText, bodyHash: hash(bodyText), pathHash: hash(path),
    requestHash: hash(JSON.stringify({ method: "POST", path, bodyText })) });
}

export class DosaEmissionClient {
  persistedDispatchIdentity() {
    return { destinationHash: createHash("sha256").update(this.config.baseUrl).digest("hex"),
      leaseMs: Math.max(30_000, 3 * this.config.timeoutMs + 30_000) };
  }
  private readonly sent = new Set<string>();
  private readonly inFlight = new Set<string>();
  private consecutiveFailures = 0;
  private openedAt: number | null = null;

  constructor(
    private readonly transport: DosaHttpTransport,
    private readonly config: DosaEmissionConfig,
    private readonly now: () => number = Date.now,
    private readonly wait: (ms: number) => Promise<void> = ms => new Promise(resolve => setTimeout(resolve, ms)),
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
    body: DosaEcfRequestBody | DosaOutboundRequestBody;
    idempotencyKey: string;
    /** Only normal dispatch supplies this server-side authorization/audit hook. */
    onReplay?: DosaReplayObserver;
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

    // La autenticación SALIENTE no es la firma del webhook entrante. Se comprueba
    // antes de tocar la red: si alguien añadiera `X-Dosa-Signature` o usara el
    // secreto del webhook como API Key, la petición no sale.
    const authViolation = outboundAuthViolation(headers, {
      apiKey: this.config.apiKey,
    });
    if (authViolation) {
      return { ok: false, blockedReason: authViolation };
    }

    const request = freezeDosaHttpRequest(input.body);
    const idempotencyKey = input.idempotencyKey;
    const url = `${this.config.baseUrl}${request.path}`;
    Object.freeze(headers);
    this.inFlight.add(idempotencyKey);
    try {
      let result = await this.perform(request, headers, idempotencyKey, url);
      for (const ordinal of [2, 3] as const) {
        if (!input.onReplay || result.ok || "blockedReason" in result || this.breakerState() === "OPEN") break;
        if (result.classification && ["ACCEPTED", "CONDITIONALLY_ACCEPTED", "REJECTED"].includes(result.classification.outcome)) break;
        const reason = result.transportFailure === "TIMEOUT" ? "TIMEOUT"
          : result.transportFailure === "NETWORK" ? "NETWORK"
          : result.status !== null && result.status >= 500 && result.status <= 599 ? "HTTP_5XX" : null;
        if (!reason) break;
        await this.wait(ordinal === 2 ? 1000 : 3000);
        if (this.breakerState() === "OPEN") break;
        const allowed = await input.onReplay(Object.freeze({ ordinal, reason, httpStatus: result.status,
          bodyHash: request.bodyHash, pathHash: request.pathHash, requestHash: request.requestHash,
          previousResponseHash: result.responseHash ?? null }));
        if (!allowed) break;
        result = await this.perform(request, headers, idempotencyKey, url);
      }
      return result;
    } finally {
      this.inFlight.delete(idempotencyKey);
    }
  }

  private async perform(request: ReturnType<typeof freezeDosaHttpRequest>, headers: Record<string, string>, idempotencyKey: string, url: string): Promise<DosaSendResult> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);

    try {
      const response = await this.transport.post(url, {
        headers,
        body: request.bodyText,
        signal: controller.signal,
      });

      if (response.status >= 500) {
        // 5xx: el proveedor pudo haberlo recibido. Sólo el observador del
        // despacho puede autorizar la recuperación idéntica y auditada.
        // `retryPermitted` conserva el significado histórico NOT_RECEIVED.
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
          responseHash: createHash("sha256").update(response.body).digest("hex"),
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
      // An interpretable response ends this logical dispatch, including 202
      // and rejections. No automatic replay of an observed fiscal result.
      this.sent.add(idempotencyKey);
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
