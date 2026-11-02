/**
 * Barrera del punto de envío DOSA.
 *
 * Por qué existe, y por qué no basta con la compuerta de configuración:
 *
 * `mapEcfToDosaDraft` devuelve un borrador marcado `DRAFT_NOT_TRANSMITTABLE`.
 * Ese `status` es una **propiedad del objeto borrador**, no del cuerpo JSON. Con
 * solo extraer `.body` (o `payload` desde el puerto del proveedor) se obtiene un
 * objeto que ya no dice en ningún sitio que no es transmisible: si además
 * alguien activa `DOSA_EMISSION_ENABLED`, `assessDosaEmissionGate` lo dejaría
 * pasar porque comprueba empresa, credencial, entorno y secuencia — pero **no
 * mira el documento**.
 *
 * Esta barrera cierra ese hueco en el único lugar que no se puede saltar: el
 * punto de envío. Valida el **contenido fiscal del cuerpo** que va a salir a la
 * red, sin depender de ninguna bandera de configuración. Si el cuerpo es en
 * realidad un borrador completo, falta un dato obligatorio (por ejemplo
 * `unidadMedida`), el `eNCF` no es coherente con el tipo, el emisor no es la
 * empresa autenticada o los totales no cuadran, no se abre la bóveda y no se
 * toca la red.
 *
 * Es una función pura: no lee entorno, no consulta base de datos y no hace red.
 *
 * Las identidades aritméticas comprobadas (`Σ montoItem`, `MontoTotal`) no son
 * política de negocio nuestra: son la definición de los totales del comprobante
 * y son exactamente los campos que el proveedor valida con sus errores 1004,
 * 1934 y 1964. Rechazar localmente un cuerpo que el proveedor rechazaría igual
 * evita consumir una secuencia en un envío condenado.
 */

import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";

/** Códigos estables de bloqueo de la barrera. */
export const DOSA_BARRIER_BLOCKED = {
  /** El cuerpo no es un objeto plano. */
  bodyNotObject: "DOSA_BARRIER_BODY_NOT_OBJECT",
  /** El cuerpo trae claves ajenas al contrato (típico de un borrador sin extraer). */
  unexpectedShape: "DOSA_BARRIER_UNEXPECTED_SHAPE",
  headerMissing: "DOSA_BARRIER_HEADER_MISSING",
  versionMissing: "DOSA_BARRIER_VERSION_MISSING",
  documentTypeMismatch: "DOSA_BARRIER_DOCUMENT_TYPE_MISMATCH",
  encfMalformed: "DOSA_BARRIER_ENCF_MALFORMED",
  issueDateMissing: "DOSA_BARRIER_ISSUE_DATE_MISSING",
  senderRncMissing: "DOSA_BARRIER_SENDER_RNC_MISSING",
  senderRncMismatch: "DOSA_BARRIER_SENDER_RNC_MISMATCH",
  senderNameMissing: "DOSA_BARRIER_SENDER_NAME_MISSING",
  itemsEmpty: "DOSA_BARRIER_ITEMS_EMPTY",
  itemInvalid: "DOSA_BARRIER_ITEM_INVALID",
  itemUnitMissing: "DOSA_BARRIER_ITEM_UNIT_MISSING",
  totalsMissing: "DOSA_BARRIER_TOTALS_MISSING",
  totalsIncoherent: "DOSA_BARRIER_TOTALS_INCOHERENT",
  referenceMissing: "DOSA_BARRIER_REFERENCE_MISSING",
  referenceUnexpected: "DOSA_BARRIER_REFERENCE_UNEXPECTED",
} as const;

export type DosaBarrierDecision = {
  allowed: boolean;
  blockingReasons: readonly string[];
};

export type DosaBarrierContext = {
  /** Tipo de comprobante que el orquestador cree estar enviando. */
  documentType: EcfDocumentType;
  /** RNC de la empresa autenticada: el comprobante debe emitirse a su nombre. */
  companyRnc: string;
  /**
   * Cuerpo del borrador del que salió el envío, si el llamador lo conserva.
   * Cuando se aporta, el cuerpo enviado debe ser **exactamente** ese objeto:
   * así se detecta cualquier mutación entre el mapeo y el envío.
   */
  draftBody?: unknown;
};

const BODY_KEYS = ["encabezado", "detallesItems", "informacionReferencia"] as const;
const HEADER_KEYS = [
  "version",
  "idDoc",
  "emisor",
  "comprador",
  "totales",
] as const;

const TIPO_ECF_BY_DOCUMENT: Readonly<Record<EcfDocumentType, string>> = {
  E31: "31",
  E32: "32",
  E34: "34",
};

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmpty(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

/**
 * Convierte un importe a centésimas. Solo acepta la forma que el contrato
 * declara (decimal sin separador de miles). Devuelve `null` si no es un importe.
 */
function cents(value: unknown): number | null {
  if (typeof value !== "string") return null;
  if (!/^-?\d+(\.\d{1,2})?$/.test(value.trim())) return null;
  const parsed = Number.parseFloat(value.trim());
  if (!Number.isFinite(parsed)) return null;
  return Math.round(parsed * 100);
}

function onlyKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
): string[] {
  return Object.keys(value).filter((key) => !allowed.includes(key));
}

/**
 * Decide si un cuerpo concreto puede salir a la red.
 *
 * `allowed` solo es `true` si todas las comprobaciones pasan. No hay camino
 * "casi válido": un solo motivo de bloqueo es suficiente para detener el envío.
 */
export function assessDosaDocumentBarrier(
  body: unknown,
  context: DosaBarrierContext,
): DosaBarrierDecision {
  const blockingReasons: string[] = [];
  const block = (reason: string) => blockingReasons.push(reason);

  if (!isPlainObject(body)) {
    return { allowed: false, blockingReasons: [DOSA_BARRIER_BLOCKED.bodyNotObject] };
  }

  // 1. Forma: el cuerpo debe ser el contrato, no un borrador ni un envoltorio.
  for (const extra of onlyKeys(body, BODY_KEYS)) {
    block(`${DOSA_BARRIER_BLOCKED.unexpectedShape}:${extra}`);
  }
  if (context.draftBody !== undefined && body !== context.draftBody) {
    // El llamador conserva el borrador y lo enviado no es el mismo objeto:
    // hubo una reconstrucción o una mutación por el camino.
    block(`${DOSA_BARRIER_BLOCKED.unexpectedShape}:DRAFT_BODY_REPLACED`);
  }

  const encabezado = body["encabezado"];
  if (!isPlainObject(encabezado)) {
    block(DOSA_BARRIER_BLOCKED.headerMissing);
    return { allowed: false, blockingReasons };
  }
  for (const extra of onlyKeys(encabezado, HEADER_KEYS)) {
    block(`${DOSA_BARRIER_BLOCKED.unexpectedShape}:encabezado.${extra}`);
  }

  if (nonEmpty(encabezado["version"]) === null) {
    block(DOSA_BARRIER_BLOCKED.versionMissing);
  }

  // 2. Identificación del documento y coherencia con el tipo declarado.
  const idDoc = encabezado["idDoc"];
  if (!isPlainObject(idDoc)) {
    block(DOSA_BARRIER_BLOCKED.headerMissing);
    return { allowed: false, blockingReasons };
  }

  const expectedTipo = TIPO_ECF_BY_DOCUMENT[context.documentType];
  const tipo = nonEmpty(idDoc["tipoeCF"]);
  if (tipo === null || tipo !== expectedTipo) {
    block(
      `${DOSA_BARRIER_BLOCKED.documentTypeMismatch}:${expectedTipo ?? "UNKNOWN"}/${tipo ?? "MISSING"}`,
    );
  }

  const encf = nonEmpty(idDoc["eNCF"]);
  if (
    encf === null ||
    tipo === null ||
    !new RegExp(`^E${tipo}\\d{10}$`).test(encf)
  ) {
    block(DOSA_BARRIER_BLOCKED.encfMalformed);
  }

  if (nonEmpty(idDoc["fechaEmision"]) === null) {
    block(DOSA_BARRIER_BLOCKED.issueDateMissing);
  }

  // 3. Emisor: identificado y con el mismo RNC que la empresa autenticada.
  const emisor = encabezado["emisor"];
  if (!isPlainObject(emisor)) {
    block(DOSA_BARRIER_BLOCKED.headerMissing);
    return { allowed: false, blockingReasons };
  }

  const senderRnc = nonEmpty(emisor["RNCEmisor"]);
  if (senderRnc === null) {
    block(DOSA_BARRIER_BLOCKED.senderRncMissing);
  } else if (senderRnc !== context.companyRnc.trim()) {
    block(DOSA_BARRIER_BLOCKED.senderRncMismatch);
  }
  if (nonEmpty(emisor["RazonSocialEmisor"]) === null) {
    block(DOSA_BARRIER_BLOCKED.senderNameMissing);
  }

  // 4. Líneas: cada una con sus datos fiscales obligatorios.
  const items = body["detallesItems"];
  if (!Array.isArray(items) || items.length === 0) {
    block(DOSA_BARRIER_BLOCKED.itemsEmpty);
    return { allowed: false, blockingReasons };
  }

  const seenLines = new Set<number>();
  let lineSumCents = 0;
  for (const [index, raw] of items.entries()) {
    const label = `#${index + 1}`;
    if (!isPlainObject(raw)) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:NOT_OBJECT`);
      continue;
    }

    const lineNumber = raw["numeroLinea"];
    if (
      typeof lineNumber !== "number" ||
      !Number.isInteger(lineNumber) ||
      lineNumber < 1 ||
      seenLines.has(lineNumber)
    ) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:NUMERO_LINEA`);
    } else {
      seenLines.add(lineNumber);
    }

    const indicadorFacturacion = raw["indicadorFacturacion"];
    if (
      indicadorFacturacion !== 1 &&
      indicadorFacturacion !== 2 &&
      indicadorFacturacion !== 3 &&
      indicadorFacturacion !== 4
    ) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:INDICADOR_FACTURACION`);
    }

    const indicadorBienoServicio = raw["indicadorBienoServicio"];
    if (indicadorBienoServicio !== 1 && indicadorBienoServicio !== 2) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:INDICADOR_BIENO_SERVICIO`);
    }

    // Sin unidad de medida el documento no es transmisible para DOSA. Es el
    // dato que el mapeador exige; la barrera lo vuelve a comprobar aquí porque
    // un cuerpo puede llegar construido a mano.
    const unidad = nonEmpty(raw["unidadMedida"]);
    if (unidad === null || unidad.length > 32) {
      block(`${DOSA_BARRIER_BLOCKED.itemUnitMissing}:${label}`);
    }

    if (nonEmpty(raw["nombreItem"]) === null) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:NOMBRE_ITEM`);
    }

    const cantidad = cents(raw["cantidadItem"]);
    if (cantidad === null || cantidad <= 0) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:CANTIDAD`);
    }

    const precio = cents(raw["precioUnitarioItem"]);
    if (precio === null || precio < 0) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:PRECIO_UNITARIO`);
    }

    const monto = cents(raw["montoItem"]);
    if (monto === null || monto < 0) {
      block(`${DOSA_BARRIER_BLOCKED.itemInvalid}:${label}:MONTO_ITEM`);
    } else {
      lineSumCents += monto;
    }
  }

  // 5. Totales presentes y coherentes con las líneas.
  const totales = encabezado["totales"];
  if (!isPlainObject(totales)) {
    block(DOSA_BARRIER_BLOCKED.totalsMissing);
    return { allowed: false, blockingReasons };
  }

  const montoGravadoTotal = cents(totales["MontoGravadoTotal"]);
  const montoGravadoI1 = cents(totales["MontoGravadoI1"]);
  const montoExento = cents(totales["MontoExento"]);
  const totalItbis = cents(totales["TotalITBIS"]);
  const montoTotal = cents(totales["MontoTotal"]);
  const itbis1 = cents(totales["ITBIS1"]);

  if (
    montoGravadoTotal === null ||
    montoGravadoI1 === null ||
    montoExento === null ||
    totalItbis === null ||
    montoTotal === null ||
    itbis1 === null
  ) {
    block(DOSA_BARRIER_BLOCKED.totalsMissing);
    return { allowed: false, blockingReasons };
  }

  const negative = [
    montoGravadoTotal,
    montoGravadoI1,
    montoExento,
    totalItbis,
    montoTotal,
    itbis1,
  ].some((value) => value < 0);
  if (negative) {
    block(`${DOSA_BARRIER_BLOCKED.totalsIncoherent}:NEGATIVE`);
  }

  if (montoGravadoI1 > montoGravadoTotal) {
    block(`${DOSA_BARRIER_BLOCKED.totalsIncoherent}:GRAVADO_I1`);
  }

  if (lineSumCents !== montoGravadoTotal + montoExento) {
    block(`${DOSA_BARRIER_BLOCKED.totalsIncoherent}:SUMA_LINEAS`);
  }

  if (montoTotal !== montoGravadoTotal + montoExento + totalItbis) {
    block(`${DOSA_BARRIER_BLOCKED.totalsIncoherent}:MONTO_TOTAL`);
  }

  // 6. Referencia: obligatoria en E34, prohibida en el resto.
  const referencia = body["informacionReferencia"];
  if (context.documentType === "E34") {
    if (!isPlainObject(referencia)) {
      block(DOSA_BARRIER_BLOCKED.referenceMissing);
    } else {
      if (nonEmpty(referencia["NCFModificado"]) === null) {
        block(`${DOSA_BARRIER_BLOCKED.referenceMissing}:NCF_MODIFICADO`);
      }
      if (nonEmpty(referencia["codigoModificacion"]) === null) {
        block(`${DOSA_BARRIER_BLOCKED.referenceMissing}:CODIGO_MODIFICACION`);
      }
    }
  } else if (referencia !== undefined) {
    block(DOSA_BARRIER_BLOCKED.referenceUnexpected);
  }

  return { allowed: blockingReasons.length === 0, blockingReasons };
}
