import { createHash, randomUUID } from "node:crypto";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import { DOSA_ECF_EMISSION_PATH } from "./dosa-ecf.contract";
import { DOSA_UNIDAD_MEDIDA_CODES } from "./dosa-ecf.mapper";
import {
  classifyDosaResponse,
  type DosaResponseClassification,
} from "./dosa-response.mapper";
import type { DosaHttpResponse, DosaHttpTransport } from "./dosa-emission.client";
import { toDosaOutboundRequest } from "./dosa-request.serializer";

/**
 * Probador E31 de TEST — **aislado del flujo comercial**.
 *
 * Este módulo no importa Prisma, no conoce empresas, no toca
 * `ecf_company_configurations` y no puede activar ni desactivar e-CF de nadie.
 * Esa ausencia de dependencias es la garantía estructural: no hay forma de que
 * una prueba fiscal altere la facturación de un cliente aunque el operador se
 * equivoque de comando.
 *
 * Reglas que aplica, en este orden y sin excepciones:
 *
 * 1. **Solo TEST.** Si el entorno no es TEST, no hay envío.
 * 2. **URL documentada.** El destino debe ser exactamente el host oficial de
 *    DOSA; cualquier otra URL (incluida cualquier variante de DGII) se rechaza.
 * 3. **Identidad.** El RNC emisor del cuerpo debe ser el RNC de prueba
 *    configurado; el proveedor rechaza la petición si no coincide con el de la
 *    API Key, y nosotros no adivinamos.
 * 4. **Secuencia.** El e-NCF debe estar dentro del rango autorizado.
 * 5. **Coherencia fiscal.** Los totales deben cuadrar con las líneas.
 * 6. **Autorización explícita.** Sin token de autorización calculado a partir del
 *    e-NCF, no hay POST externo.
 * 7. **Un solo intento.** Nunca reintenta. Un resultado incierto se registra como
 *    incierto y se detiene.
 * 8. **Evidencia.** Cada intento deja un registro con hash de la respuesta y sin
 *    la clave.
 */

export const DOSA_PROBE_BLOCKED = {
  notTestEnvironment: "DOSA_PROBE_NOT_TEST_ENVIRONMENT",
  unroutableBaseUrl: "DOSA_PROBE_BASE_URL_NOT_DOCUMENTED",
  apiKeyMissing: "DOSA_PROBE_API_KEY_MISSING",
  testRncMissing: "DOSA_PROBE_TEST_RNC_MISSING",
  rncMismatch: "DOSA_PROBE_SENDER_RNC_MISMATCH",
  encfOutsideRange: "DOSA_PROBE_ENCF_OUTSIDE_ALLOWED_RANGE",
  totalsIncoherent: "DOSA_PROBE_TOTALS_INCOHERENT",
  notAuthorized: "DOSA_PROBE_EXTERNAL_POST_NOT_AUTHORIZED",
  unsupportedType: "DOSA_PROBE_DOCUMENT_TYPE_UNSUPPORTED",
  unitOfMeasureInvalid: "DOSA_PROBE_UNIT_OF_MEASURE_INVALID",
} as const;

/** Host oficial y único admitido para la emisión. */
export const DOSA_PROBE_ALLOWED_ORIGIN = "https://dosasystem.com";

export type DosaProbeConfig = {
  environment: "TEST" | "PRODUCTION";
  baseUrl: string;
  apiKey: string;
  /** RNC de prueba entregado por el proveedor (p. ej. 133306001). */
  testRnc: string;
  /** Rango de secuencias autorizado para la prueba, inclusive. */
  sequenceRange: { prefix: string; from: number; to: number };
  timeoutMs: number;
};

export type DosaProbeEvidence = {
  attemptId: string;
  at: string;
  encf: string;
  senderRnc: string;
  environment: DosaProbeConfig["environment"];
  baseUrl: string;
  /** Nunca el valor de la clave: solo su longitud. */
  apiKeyLength: number;
  outcome: "BLOCKED" | "RESPONSE" | "UNCERTAIN" | "TRANSPORT_ERROR";
  blockedReasons?: readonly string[];
  httpStatus: number | null;
  classification: DosaResponseClassification | null;
  responseSha256: string | null;
  /** `true` solo si el proveedor afirma que la DGII no recibió nada. */
  safeToRetrySameEncf: boolean;
};

export type DosaProbeResult =
  | { ok: false; blockedReasons: readonly string[]; evidence: DosaProbeEvidence }
  | { ok: true; evidence: DosaProbeEvidence };

export type DosaProbeReadiness = {
  allowed: boolean;
  blockedReasons: readonly string[];
};

/** Token de autorización exigido para un POST externo, derivado del e-NCF. */
export function probeAuthorizationToken(encf: string): string {
  return `AUTHORIZE-${encf.trim().toUpperCase()}`;
}

/** Valida el entorno antes de construir nada. No lanza: informa. */
export function assessProbeReadiness(input: {
  config: DosaProbeConfig;
  body: DosaEcfRequestBody;
  encf: string;
}): DosaProbeReadiness {
  const blockedReasons: string[] = [];
  const { config, body, encf } = input;

  if (config.environment !== "TEST") {
    blockedReasons.push(DOSA_PROBE_BLOCKED.notTestEnvironment);
  }
  if (!isDocumentedBaseUrl(config.baseUrl)) {
    blockedReasons.push(DOSA_PROBE_BLOCKED.unroutableBaseUrl);
  }
  if (config.apiKey.trim().length === 0) {
    blockedReasons.push(DOSA_PROBE_BLOCKED.apiKeyMissing);
  }
  if (config.testRnc.trim().length === 0) {
    blockedReasons.push(DOSA_PROBE_BLOCKED.testRncMissing);
  }
  if (body.encabezado.idDoc.tipoeCF !== "31") {
    blockedReasons.push(DOSA_PROBE_BLOCKED.unsupportedType);
  }
  if (normalize(body.encabezado.emisor.RNCEmisor) !== normalize(config.testRnc)) {
    blockedReasons.push(DOSA_PROBE_BLOCKED.rncMismatch);
  }
  if (!isWithinRange(encf, config.sequenceRange)) {
    blockedReasons.push(DOSA_PROBE_BLOCKED.encfOutsideRange);
  }
  if (!totalsAreCoherent(body)) {
    blockedReasons.push(DOSA_PROBE_BLOCKED.totalsIncoherent);
  }
  // `unidadMedida` es un código entero del catálogo de DOSA. Se comprueba aquí
  // también, no solo en la CLI, para que ninguna invocación programática envíe
  // un comprobante sin unidad o con un código fuera de catálogo.
  const itemUnitInvalid = (body.detallesItems ?? []).some(
    (item) =>
      typeof item.unidadMedida !== "number" ||
      !DOSA_UNIDAD_MEDIDA_CODES.includes(item.unidadMedida),
  );
  if (itemUnitInvalid) {
    blockedReasons.push(DOSA_PROBE_BLOCKED.unitOfMeasureInvalid);
  }

  return { allowed: blockedReasons.length === 0, blockedReasons };
}

export class DosaE31TestProbe {
  constructor(
    private readonly deps: {
      transport: DosaHttpTransport;
      config: DosaProbeConfig;
      now?: () => Date;
      /** Receptor de evidencia. En la CLI escribe un fichero local. */
      onEvidence?: (evidence: DosaProbeEvidence) => void | Promise<void>;
    },
  ) {}

  /**
   * Ejecuta **un único intento**, y solo con autorización explícita.
   *
   * `authorizationToken` debe ser exactamente `AUTHORIZE-<eNCF>`. Sin eso no hay
   * petición: así un comando copiado por error no puede consumir una secuencia.
   */
  async run(input: {
    body: DosaEcfRequestBody;
    encf: string;
    authorizationToken: string | null;
  }): Promise<DosaProbeResult> {
    const readiness = assessProbeReadiness({
      config: this.deps.config,
      body: input.body,
      encf: input.encf,
    });

    if (!readiness.allowed) {
      const evidence = this.buildEvidence({
        encf: input.encf,
        body: input.body,
        outcome: "BLOCKED",
        blockedReasons: readiness.blockedReasons,
        httpStatus: null,
        classification: null,
        responseSha256: null,
      });
      await this.emit(evidence);
      return { ok: false, blockedReasons: readiness.blockedReasons, evidence };
    }

    if (
      (input.authorizationToken ?? "").trim() !==
      probeAuthorizationToken(input.encf)
    ) {
      const evidence = this.buildEvidence({
        encf: input.encf,
        body: input.body,
        outcome: "BLOCKED",
        blockedReasons: [DOSA_PROBE_BLOCKED.notAuthorized],
        httpStatus: null,
        classification: null,
        responseSha256: null,
      });
      await this.emit(evidence);
      return {
        ok: false,
        blockedReasons: [DOSA_PROBE_BLOCKED.notAuthorized],
        evidence,
      };
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.deps.config.timeoutMs);
    try {
      const response = await this.send(input.body, controller.signal);
      const parsed = safeParse(response.body);
      const classification =
        parsed === null ? null : classifyDosaResponse(parsed);
      const evidence = this.buildEvidence({
        encf: input.encf,
        body: input.body,
        outcome: "RESPONSE",
        httpStatus: response.status,
        classification,
        responseSha256: sha256(response.body),
      });
      await this.emit(evidence);
      return { ok: true, evidence };
    } catch {
      // Un fallo de transporte es INCIERTO: no se reintenta automáticamente.
      const evidence = this.buildEvidence({
        encf: input.encf,
        body: input.body,
        outcome: controller.signal.aborted ? "UNCERTAIN" : "TRANSPORT_ERROR",
        httpStatus: null,
        classification: null,
        responseSha256: null,
      });
      await this.emit(evidence);
      return { ok: true, evidence };
    } finally {
      clearTimeout(timer);
    }
  }

  private send(body: DosaEcfRequestBody, signal: AbortSignal) {
    const url = `${this.deps.config.baseUrl.replace(/\/+$/, "")}${DOSA_ECF_EMISSION_PATH}`;
    return this.deps.transport.post(url, {
      headers: {
        "Content-Type": "application/json",
        "X-API-KEY": this.deps.config.apiKey,
      },
      body: JSON.stringify(toDosaOutboundRequest(body)),
      signal,
    });
  }

  private buildEvidence(input: {
    encf: string;
    body: DosaEcfRequestBody;
    outcome: DosaProbeEvidence["outcome"];
    blockedReasons?: readonly string[];
    httpStatus: number | null;
    classification: DosaResponseClassification | null;
    responseSha256: string | null;
  }): DosaProbeEvidence {
    return {
      attemptId: randomUUID(),
      at: (this.deps.now?.() ?? new Date()).toISOString(),
      encf: input.encf,
      senderRnc: input.body.encabezado.emisor.RNCEmisor,
      environment: this.deps.config.environment,
      baseUrl: this.deps.config.baseUrl,
      apiKeyLength: this.deps.config.apiKey.length,
      outcome: input.outcome,
      ...(input.blockedReasons ? { blockedReasons: input.blockedReasons } : {}),
      httpStatus: input.httpStatus,
      classification: input.classification,
      responseSha256: input.responseSha256,
      safeToRetrySameEncf:
        input.classification?.safeToRetrySameEncf === true,
    };
  }

  private async emit(evidence: DosaProbeEvidence): Promise<void> {
    await this.deps.onEvidence?.(evidence);
  }
}

function isDocumentedBaseUrl(value: string): boolean {
  const raw = (value ?? "").trim().replace(/\/+$/, "");
  return raw === DOSA_PROBE_ALLOWED_ORIGIN;
}

function normalize(value: string): string {
  return (value ?? "").replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}

function isWithinRange(
  encf: string,
  range: DosaProbeConfig["sequenceRange"],
): boolean {
  const value = normalize(encf);
  const prefix = normalize(range.prefix);
  if (!value.startsWith(prefix)) return false;
  const digits = value.slice(prefix.length);
  if (!/^\d+$/.test(digits)) return false;
  const number = Number.parseInt(digits, 10);
  return number >= range.from && number <= range.to;
}

/** Céntimos enteros para comparar sin errores de coma flotante. */
function cents(value: string): number | null {
  const raw = (value ?? "").trim();
  // El contrato del proveedor serializa TODOS los importes con dos decimales.
  // Un importe sin decimales es una senal de formato incorrecto: se rechaza.
  if (!/^-?\d+\.\d{2}$/.test(raw)) return null;
  const [whole, fraction = ""] = raw.split(".");
  const sign = whole.startsWith("-") ? -1 : 1;
  return (
    sign * (Math.abs(Number.parseInt(whole, 10)) * 100 + Number.parseInt(fraction, 10))
  );
}

/**
 * Coherencia fiscal del E31: cada línea cuadra con cantidad × precio, la suma de
 * líneas es el monto gravado y el total es la suma de sus partes.
 */
export function totalsAreCoherent(body: DosaEcfRequestBody): boolean {
  const totals = body.encabezado.totales;
  const gravado = cents(totals.MontoGravadoTotal);
  const gravadoI1 = cents(totals.MontoGravadoI1);
  const exento = cents(totals.MontoExento);
  const itbis = cents(totals.TotalITBIS);
  const total = cents(totals.MontoTotal);
  if ([gravado, gravadoI1, exento, itbis, total].some((v) => v === null)) {
    return false;
  }

  let sumItems = 0;
  for (const item of body.detallesItems) {
    const quantity = Number.parseFloat(item.cantidadItem);
    const price = cents(item.precioUnitarioItem);
    const amount = cents(item.montoItem);
    if (!Number.isFinite(quantity) || price === null || amount === null) return false;
    const expected = Math.round(price * quantity);
    if (expected !== amount) return false;
    sumItems += amount;
  }
  if (body.detallesItems.length > 0 && sumItems !== gravado) return false;
  // El total debe ser gravado + exento + impuestos.
  return total === (gravado as number) + (exento as number) + (itbis as number);
}

function safeParse(body: string): unknown | null {
  const text = (body ?? "").trim();
  if (text.length === 0) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

/** Tipo exportado para los dobles de transporte de las pruebas. */
export type { DosaHttpResponse, DosaHttpTransport };
