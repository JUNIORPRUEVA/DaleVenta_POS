/**
 * Clasificación de la respuesta de emisión de DOSA.
 *
 * Basado en la documentación oficial del proveedor
 * (`alapaix13/DosaInvoicecloud-Documentation`, README §"Respuesta del Sistema"
 * y §"Códigos de Respuesta del Sistema"). La respuesta real es **plana**, no
 * envuelta en `data`:
 *
 * ```json
 * { "trackId": "...", "codigo": "4", "estado": "Aceptado Condicional",
 *   "rnc": "101742186", "encf": "E320000000004",
 *   "url": "https://ecf.dgii.gov.do/testecf/consulta...",
 *   "codigoSeguridad": "EAkbyR", "fechaFirma": "15-11-2025 14:46:41",
 *   "secuenciaUtilizada": true, "fechaRecepcion": "...",
 *   "mensajes": [{ "valor": "...", "codigo": 1934 }] }
 * ```
 *
 * Reglas que este módulo respeta:
 *
 * 1. **No inventa estados.** Se aplica la tabla pública de códigos DGII
 *    (`1` Aceptado, `2` Rechazado, `3` En proceso, `4` Aceptado condicional).
 * 2. **`codigo 0` NO se resuelve.** La tabla del proveedor dice «No encontrado»
 *    pero su propio ejemplo de manejo de respuestas trata `0` como «Rechazado».
 *    Dos fuentes del mismo proveedor se contradicen; interpretarlo cambiaría el
 *    estado fiscal de un comprobante, así que queda `UNRESOLVED` y se reporta.
 * 3. **`codigo` se trata como valor observado**: la documentación lo muestra
 *    como cadena (`"4"`) aunque el tipo declarado sea numérico, así que se
 *    conserva tal cual llegó, con su tipo primitivo.
 * 4. **`estado: "Error de envío"` (HTTP 502) significa que la DGII no recibió
 *    nada** y el propio proveedor indica que se puede reintentar con el MISMO
 *    eNCF. Es el único caso donde el reintento es seguro y se marca como tal.
 * 5. **`secuenciaUtilizada` se propaga.** Es lo que permite decidir si la
 *    secuencia se consumió, sin deducirlo del código de estado.
 * 6. **Nunca se declara aprobación.** `impliesFiscalAuthorization` y
 *    `isDgiiApproval` son siempre `false`: la respuesta del proveedor es
 *    evidencia, no autorización.
 */

export type DosaDgiiOutcome =
  | "ACCEPTED"
  | "CONDITIONALLY_ACCEPTED"
  | "REJECTED"
  | "IN_PROCESS"
  | "UNRESOLVED"
  /** HTTP 502 + `estado: "Error de envío"`: la DGII no recibió el eCF. */
  | "NOT_RECEIVED";

export type DosaQrData = {
  /** URL de consulta pública del comprobante. */
  consultaUrl: string | null;
  codigoSeguridad: string | null;
  fechaFirma: string | null;
  encf: string | null;
  rnc: string | null;
  /** `true` solo si están presentes todos los componentes del QR de la DGII. */
  complete: boolean;
};

export type DosaResponseClassification = {
  outcome: DosaDgiiOutcome;
  /** Valor crudo del proveedor. Sin coerción. */
  codigo: string | number | null;
  /** Tipo primitivo observado, útil para detectar cambios de contrato. */
  codigoType: "number" | "string" | "absent";
  /** Motivo legible cuando el resultado no se puede determinar. */
  unresolvedReason: string | null;
  mensajes: string[];
  qr: DosaQrData | null;
  eNCF: string | null;
  trackId: string | null;
  /** La DGII consumió la secuencia. `null` si el proveedor no lo informó. */
  secuenciaUtilizada: boolean | null;
  /** `true` solo si el proveedor afirma que la DGII no recibió el eCF. */
  safeToRetrySameEncf: boolean;
  /** Nunca `true`: una respuesta del proveedor no es aprobación DGII. */
  impliesFiscalAuthorization: false;
  isDgiiApproval: false;
};

const TABLE_OUTCOME: Record<string, DosaDgiiOutcome> = {
  "1": "ACCEPTED",
  "2": "REJECTED",
  "3": "IN_PROCESS",
  "4": "CONDITIONALLY_ACCEPTED",
};

/** El conflicto: la tabla dice «No encontrado», el ejemplo dice «Rechazado». */
const CONFLICT_CODE = "0";

const TEXT_OUTCOME: ReadonlyArray<[RegExp, DosaDgiiOutcome]> = [
  [/aceptado\s+condicional/i, "CONDITIONALLY_ACCEPTED"],
  [/^\s*aceptado\s*$/i, "ACCEPTED"],
  [/^\s*rechazado\s*$/i, "REJECTED"],
  [/en\s+proceso/i, "IN_PROCESS"],
  [/^\s*pendiente\s+dgii\s*$/i, "IN_PROCESS"],
];

/** El proveedor usa este texto para decir que la DGII no recibió el eCF. */
const NOT_RECEIVED_TEXT = /error\s+de\s+env[ií]o/i;

export function classifyDosaResponse(input: unknown): DosaResponseClassification {
  const envelope = asRecord(input);
  // La forma documentada es plana; se acepta `data` por tolerancia a cambios.
  const data = asRecord(envelope?.data) ?? envelope;

  const rawCode = data?.codigo;
  const codigoType: "number" | "string" | "absent" =
    typeof rawCode === "number"
      ? "number"
      : typeof rawCode === "string"
        ? "string"
        : "absent";
  const codigo =
    typeof rawCode === "number" || typeof rawCode === "string" ? rawCode : null;
  const codeKey = codigo === null ? null : String(codigo).trim();

  const mensajes = collectMessages(data);
  const estadoText = firstString(data, ["estado"]);

  const notReceived = estadoText !== null && NOT_RECEIVED_TEXT.test(estadoText);

  const fromCode =
    codeKey !== null && codeKey !== CONFLICT_CODE
      ? (TABLE_OUTCOME[codeKey] ?? null)
      : null;

  const fromText = estadoText
    ? (TEXT_OUTCOME.find(([pattern]) => pattern.test(estadoText))?.[1] ?? null)
    : null;

  let outcome: DosaDgiiOutcome;
  let unresolvedReason: string | null = null;

  if (notReceived) {
    outcome = "NOT_RECEIVED";
  } else if (codeKey === CONFLICT_CODE) {
    outcome = "UNRESOLVED";
    unresolvedReason =
      "DOSA_STATUS_TABLE_CONFLICT: la tabla dice 'No encontrado' y el ejemplo del proveedor trata 0 como rechazo";
  } else if (fromCode && fromText && fromCode !== fromText) {
    outcome = "UNRESOLVED";
    unresolvedReason = `DOSA_STATUS_TEXT_CODE_CONFLICT: codigo=${codeKey} estado=${estadoText}`;
  } else if (fromCode) {
    outcome = fromCode;
  } else if (fromText) {
    outcome = fromText;
    unresolvedReason = "DOSA_STATUS_FROM_TEXT_ONLY";
  } else if (codigo === null) {
    outcome = "UNRESOLVED";
    unresolvedReason = "DOSA_STATUS_CODE_ABSENT";
  } else {
    outcome = "UNRESOLVED";
    unresolvedReason = `DOSA_STATUS_CODE_UNKNOWN: ${codeKey}`;
  }

  const encf = firstString(data, ["encf", "eNCF", "e_ncf", "ncf"]);
  const rnc = firstString(data, ["rnc", "RNC", "rncEmisor", "RNCEmisor"]);
  const secuencia = data?.secuenciaUtilizada;

  return {
    outcome,
    codigo,
    codigoType,
    unresolvedReason,
    mensajes,
    qr: buildQr(data, { encf, rnc }),
    eNCF: encf,
    trackId: firstString(data, ["trackId", "track_id", "trackid"]),
    secuenciaUtilizada: typeof secuencia === "boolean" ? secuencia : null,
    safeToRetrySameEncf: outcome === "NOT_RECEIVED",
    impliesFiscalAuthorization: false,
    isDgiiApproval: false,
  };
}

/** Un resultado "aceptado" del proveedor no equivale a aprobación DGII. */
export function isDosaOutcomeFinal(outcome: DosaDgiiOutcome): boolean {
  return (
    outcome === "ACCEPTED" ||
    outcome === "CONDITIONALLY_ACCEPTED" ||
    outcome === "REJECTED"
  );
}

/**
 * QR de la DGII. La respuesta no trae un campo `qr`: trae sus componentes
 * (`url`, `codigoSeguridad`, `fechaFirma`, `encf`, `rnc`). Se construye desde
 * ahí y se conserva el descubrimiento por nombre para no perder el dato si el
 * proveedor añade un campo explícito.
 */
function buildQr(
  data: Record<string, unknown> | null,
  ids: { encf: string | null; rnc: string | null },
): DosaQrData | null {
  if (!data) return null;

  let consultaUrl = firstString(data, ["url", "urlConsulta", "consultaUrl", "urlQR"]);
  const codigoSeguridad = firstString(data, ["codigoSeguridad"]);
  const fechaFirma = firstString(data, ["fechaFirma"]);

  // Observed provider URL contained a literal '+' in the security code. URL
  // query parsing treats it as a space, making an accepted RFCE unfindable.
  // Repair only this exact encoding discrepancy on the official DGII hosts.
  if (consultaUrl && codigoSeguridad) {
    try {
      const url = new URL(consultaUrl);
      const entry = Array.from(url.searchParams).find(([key]) => key.toLowerCase() === "codigoseguridad");
      if (url.protocol === "https:" && ["fc.dgii.gov.do", "ecf.dgii.gov.do"].includes(url.hostname)
          && entry && entry[1] !== codigoSeguridad && entry[1].replace(/ /g, "+") === codigoSeguridad) {
        url.searchParams.set(entry[0], codigoSeguridad);
        consultaUrl = url.toString();
      }
    } catch { /* Preserve the observed URL; malformed evidence is not invented. */ }
  }

  if (!consultaUrl && !codigoSeguridad && !fechaFirma) return null;

  return {
    consultaUrl,
    codigoSeguridad,
    fechaFirma,
    encf: ids.encf,
    rnc: ids.rnc,
    complete: Boolean(consultaUrl && codigoSeguridad && ids.encf && ids.rnc),
  };
}

/** `mensajes` es un array de `{ valor, codigo }` según la documentación. */
function collectMessages(data: Record<string, unknown> | null): string[] {
  if (!data) return [];
  const raw = data.mensajes ?? data.mensaje ?? data.message ?? data.messages;
  const list = Array.isArray(raw) ? raw : raw === undefined ? [] : [raw];
  const result: string[] = [];
  for (const entry of list) {
    if (typeof entry === "string") {
      const trimmed = entry.trim();
      if (trimmed) result.push(trimmed);
      continue;
    }
    const record = asRecord(entry);
    if (!record) continue;
    const text =
      typeof record.valor === "string"
        ? record.valor
        : typeof record.mensaje === "string"
          ? record.mensaje
          : null;
    if (text?.trim()) result.push(text.trim());
  }
  return result;
}

function firstString(
  data: Record<string, unknown> | null,
  keys: string[],
): string | null {
  if (!data) return null;
  for (const key of keys) {
    const value = data[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}
