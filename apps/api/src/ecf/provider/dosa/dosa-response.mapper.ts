/**
 * Clasificación de la respuesta de emisión de DOSA.
 *
 * Reglas que este módulo respeta y que no son negociables:
 *
 * 1. **No inventa estados.** El único mapeo que se aplica es el de la tabla
 *    pública del proveedor (`1` Aceptado, `2` Rechazado, `3` En proceso,
 *    `4` Aceptado condicional). El `0` está en conflicto documentado
 *    (`DOSA_STATUS_TABLE_CONFLICT`) y por eso queda **sin resolver**: no se
 *    interpreta como aceptado ni como rechazado.
 * 2. **`codigo` se trata como valor observado**, no como un tipo cerrado: se
 *    conserva tal cual llegó, incluido su tipo primitivo. Un `"1"` (texto) y un
 *    `1` (número) se registran distintos en lugar de coercionarse en silencio.
 * 3. **Un resultado aceptado no autoriza nada.** La aceptación del proveedor no
 *    es aprobación de la DGII y no habilita emisión: `impliesFiscalAuthorization`
 *    y `isDgiiApproval` son siempre `false`.
 * 4. Los tres estados de la DGII (Aceptado / Aceptado condicional / Rechazado)
 *    se reconocen también en texto; si el texto y el código se contradicen, el
 *    resultado es `UNRESOLVED` y se reporta el conflicto.
 */

export type DosaDgiiOutcome =
  | "ACCEPTED"
  | "CONDITIONALLY_ACCEPTED"
  | "REJECTED"
  | "IN_PROCESS"
  | "UNRESOLVED";

export type DosaResponseClassification = {
  outcome: DosaDgiiOutcome;
  /** Valor crudo del proveedor. Sin coerción. */
  codigo: string | number | null;
  /** Tipo primitivo observado, útil para detectar cambios de contrato. */
  codigoType: "number" | "string" | "absent";
  /** Motivo legible cuando el resultado no se puede determinar. */
  unresolvedReason: string | null;
  mensajes: string[];
  /** Datos de QR tal como llegaron (campo + valor). Puede venir ausente. */
  qr: { field: string; value: string } | null;
  eNCF: string | null;
  trackId: string | null;
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

/** El conflicto documentado: la tabla dice una cosa y el ejemplo otra. */
const CONFLICT_CODE = "0";

const TEXT_OUTCOME: ReadonlyArray<[RegExp, DosaDgiiOutcome]> = [
  [/aceptado\s+condicional/i, "CONDITIONALLY_ACCEPTED"],
  [/^\s*aceptado\s*$/i, "ACCEPTED"],
  [/^\s*rechazado\s*$/i, "REJECTED"],
  [/en\s+proceso/i, "IN_PROCESS"],
];

/** Claves donde el proveedor podría devolver el QR; se buscan por nombre. */
const QR_KEY = /qr/i;

export function classifyDosaResponse(input: unknown): DosaResponseClassification {
  const envelope = asRecord(input);
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

  const fromCode =
    codeKey !== null && codeKey !== CONFLICT_CODE
      ? (TABLE_OUTCOME[codeKey] ?? null)
      : null;

  const textValues = collectStrings(data).filter(
    (value) =>
      /aceptado|rechazado|en\s+proceso/i.test(value) && value.length <= 200,
  );
  const fromText =
    textValues
      .map((value) => TEXT_OUTCOME.find(([pattern]) => pattern.test(value))?.[1])
      .find((outcome) => outcome !== undefined) ?? null;

  let outcome: DosaDgiiOutcome;
  let unresolvedReason: string | null = null;

  if (codeKey === CONFLICT_CODE) {
    outcome = "UNRESOLVED";
    unresolvedReason = "DOSA_STATUS_TABLE_CONFLICT: codigo 0 ambiguo";
  } else if (fromCode && fromText && fromCode !== fromText) {
    outcome = "UNRESOLVED";
    unresolvedReason = `DOSA_STATUS_TEXT_CODE_CONFLICT: codigo=${codeKey} texto=${fromText}`;
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

  return {
    outcome,
    codigo,
    codigoType,
    unresolvedReason,
    mensajes,
    qr: findQr(data),
    eNCF: firstString(data, ["encf", "eNCF", "e_ncf", "ncf"]),
    trackId: firstString(data, ["trackId", "track_id", "trackid"]),
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

function findQr(
  data: Record<string, unknown> | null,
): { field: string; value: string } | null {
  if (!data) return null;
  for (const [key, value] of Object.entries(data)) {
    if (!QR_KEY.test(key)) continue;
    const collected = pickQrValue(value);
    if (collected) return { field: key, value: collected };
  }
  return null;
}

/** El QR puede venir como cadena, como objeto con `url`, o como lista. */
function pickQrValue(value: unknown): string | null {
  if (typeof value === "string") return value.trim() || null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = pickQrValue(item);
      if (found) return found;
    }
    return null;
  }
  const record = asRecord(value);
  if (!record) return null;
  for (const [key, inner] of Object.entries(record)) {
    if (!/url|link|contenido|value|valor|qr/i.test(key)) continue;
    const found = pickQrValue(inner);
    if (found) return found;
  }
  return null;
}

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
    const text =
      record && typeof record.valor === "string"
        ? record.valor
        : record && typeof record.mensaje === "string"
          ? record.mensaje
          : null;
    if (text?.trim()) result.push(text.trim());
  }
  return result;
}

function collectStrings(data: Record<string, unknown> | null): string[] {
  if (!data) return [];
  const result: string[] = [];
  for (const [key, value] of Object.entries(data)) {
    if (/mensaje|message|error/i.test(key)) continue;
    if (typeof value === "string") result.push(value);
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
