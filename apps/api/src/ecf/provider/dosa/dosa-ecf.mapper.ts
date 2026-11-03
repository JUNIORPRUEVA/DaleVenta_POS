import type { EcfIssuanceMetadata } from "../../fiscal-core/alanube-dom.contract";
import {
  dec,
  money,
  moneyString,
  quantity,
  ECF_QUANTITY_SCALE,
} from "../../fiscal-core/ecf-money";
import type {
  EcfDocumentType,
  EcfFiscalDocument,
  EcfLine,
} from "../../fiscal-core/ecf-fiscal-document";
import {
  DOSA_CONTRACT_GAPS,
  DOSA_ECF_VERSION,
  DOSA_TIPOS_ECF,
  type DosaEcfItem,
  type DosaEmissionDraft,
} from "./dosa-ecf.contract";

export type DosaMappingResult =
  | { ok: true; draft: DosaEmissionDraft }
  | { ok: false; blockedReason: string };

export const DOSA_MAPPER_BLOCKED = {
  unsupportedType: "DOSA_TYPE_UNSUPPORTED",
  missingEncf: "DOSA_ENCF_REQUIRED",
  unsupportedCurrency: "DOSA_CURRENCY_UNSUPPORTED",
  referenceRequired: "DOSA_REFERENCE_REQUIRED",
  unsupportedFields: "DOSA_UNSUPPORTED_FIELDS",
  unitOfMeasureRequired: "DOSA_UNIT_OF_MEASURE_REQUIRED",
  unitOfMeasureUnmapped: "DOSA_UNIT_OF_MEASURE_UNMAPPED",
  modificationCodeRequired: "DOSA_MODIFICATION_CODE_REQUIRED",
  modificationCodeUnsupported: "DOSA_MODIFICATION_CODE_UNSUPPORTED",
} as const;

/**
 * Causa de la nota de crédito (`Referencia.CodigoModificacion`).
 *
 * Valores según el documento `NOTAS_CREDITO_DESDE_FACTURA.md` entregado por el
 * propietario del producto: 1 = anulación, 2 = corrección de texto, 3 =
 * corrección de montos. El README público del proveedor **no** publica la tabla
 * (solo sus ejemplos usan 1), así que estos valores no se pueden verificar aquí
 * contra el proveedor: viajan con la nota para que la emisión no invente una
 * causa.
 *
 * El 4 que admite el modelo compartido de Alanube **no** está documentado para
 * DOSA y por eso se rechaza en lugar de enviarse a ciegas.
 */
export const DOSA_CODIGO_MODIFICACION: Readonly<Record<number, string>> = {
  1: "Anulación",
  2: "Corrección de texto",
  3: "Corrección de montos",
};

/**
 * `indicadorFacturacion` de DOSA — **naturaleza del ítem**, no impuesto.
 *
 * 1 = Producto · 2 = Servicio · 3 = Mixta · 4 = Servicio profesional.
 *
 * Antes este campo se rellenaba con la codificación de impuesto de la DGII
 * (1 = ITBIS 18 %, 2 = ITBIS 16 %, 3 = ITBIS 0 %, 4 = exento). Son dos
 * catálogos distintos y el resultado habría sido un JSON con la naturaleza
 * equivocada en cada línea.
 *
 * 3 y 4 no son alcanzables desde el modelo actual: `EcfGoodServiceIndicator`
 * solo distingue `GOOD` y `SERVICE`, no «mixta» ni «servicio profesional». No se
 * deduce uno del otro: no hay dato que lo sustente.
 */
function indicadorFacturacion(line: EcfLine): 1 | 2 {
  return line.goodServiceIndicator === "GOOD" ? 1 : 2;
}

/**
 * `indicadorBienoServicio` de DOSA: 1 = Servicio, 2 = Bien.
 *
 * Está **al revés** que el código de la DGII, donde 1 es bien y 2 es servicio.
 * El mapeador anterior tenía la inversión: emitía 1 para un bien.
 */
function indicadorBienoServicio(line: EcfLine): 1 | 2 {
  return line.goodServiceIndicator === "GOOD" ? 2 : 1;
}

/**
 * Traducción de la unidad de medida de FullPOS al **código entero** del catalogo
 * oficial de DOSA.
 *
 * HECHO verificado en el README público del proveedor (`Catálogo de Unidades de
 * Medida`, 20 códigos): `unidadMedida` es un **Integer**, no una cadena, y sus
 * valores son 1 Unidad, 2 Caja, 3 Kilogramo, 4 Gramo, 5 Libra, 6 Onza, 7 Metro,
 * 8 Centímetro, 9 Pulgada, 10 Pie, 11 Yarda, 12 Litro, 13 Mililitro, 14 Galón,
 * 15 Docena, 16 Paquete, 17 Servicio, 18 Hora, 19 Día, 20 Mes.
 *
 * Solo se traducen los códigos de unidad que FullPOS **tiene de verdad**
 * (`unit_of_measures` globales del seed). No se inventan equivalencias para
 * códigos que FullPOS no ofrece hoy (2 Caja, 8 Centímetro, 15 Docena, 16
 * Paquete, 17 Servicio, 18 Hora, 19 Día, 20 Mes): si una empresa crea una unidad
 * propia con un código desconocido, el documento se **rechaza** con un motivo
 * claro en lugar de enviar un número adivinado.
 */
export const DOSA_UNIDAD_MEDIDA_BY_FULLPOS_CODE: Readonly<Record<string, number>> = {
  UNIT: 1, // Unidad
  YARD: 11, // Yarda
  METER: 7, // Metro
  FOOT: 10, // Pie
  INCH: 9, // Pulgada
  POUND: 5, // Libra
  KILOGRAM: 3, // Kilogramo
  GRAM: 4, // Gramo
  OUNCE: 6, // Onza
  LITER: 12, // Litro
  MILLILITER: 13, // Mililitro
  GALLON: 14, // Galón
};

/** Códigos válidos según el catalogo publicado por DOSA. */
export const DOSA_UNIDAD_MEDIDA_CODES: readonly number[] = Array.from(
  { length: 20 },
  (_value, index) => index + 1,
);

/**
 * Unidad de medida: DOSA la exige y la quiere como **código numérico**.
 *
 * Devuelve `null` si falta, y un motivo distinto si viene un código de FullPOS
 * que no está en la tabla verificada. Nunca se envía un valor por defecto.
 */
function unidadMedida(line: EcfLine): { code: number } | { blockedReason: string } {
  const raw = (line.unitOfMeasure ?? "").trim().toUpperCase();
  if (raw.length === 0) {
    return {
      blockedReason: `${DOSA_MAPPER_BLOCKED.unitOfMeasureRequired}:${line.lineNumber}`,
    };
  }
  const code = DOSA_UNIDAD_MEDIDA_BY_FULLPOS_CODE[raw];
  if (code === undefined) {
    return {
      blockedReason: `${DOSA_MAPPER_BLOCKED.unitOfMeasureUnmapped}:${line.lineNumber}:${raw}`,
    };
  }
  return { code };
}

const UNVERIFIED_IN_DRAFT: readonly string[] = [
  "Formato de fecha (se emite dd-MM-yyyy según la documentación pública).",
  "MontoGravadoI1 como suma de líneas al 18 %.",
  "ITBIS1 como tasa (18) en lugar de monto.",
  "paginacion omitida por no conocerse si es obligatoria.",
  ...DOSA_CONTRACT_GAPS,
];

/**
 * Traduce un documento fiscal interno al cuerpo de DOSA.
 *
 * No hay transporte aquí y no lo habrá hasta cerrar el contrato: el resultado es
 * un `DosaEmissionDraft` marcado como NO transmisible. Falla cerrado ante
 * cualquier cosa que el contrato público no cubra.
 */
export function mapEcfToDosaDraft(
  document: EcfFiscalDocument,
  metadata: EcfIssuanceMetadata,
): DosaMappingResult {
  if (!["E31", "E32", "E34"].includes(document.type)) {
    return { ok: false, blockedReason: DOSA_MAPPER_BLOCKED.unsupportedType };
  }
  const encf = (metadata.encf ?? "").trim();
  if (!new RegExp(`^${document.type}\\d{10}$`).test(encf)) {
    return { ok: false, blockedReason: DOSA_MAPPER_BLOCKED.missingEncf };
  }
  if (document.currency !== "DOP") {
    return { ok: false, blockedReason: DOSA_MAPPER_BLOCKED.unsupportedCurrency };
  }
  if (
    document.type === "E34" &&
    (document.reference?.originalENcf ?? "").trim().length === 0
  ) {
    return { ok: false, blockedReason: DOSA_MAPPER_BLOCKED.referenceRequired };
  }
  // El catalogo de `codigoModificacion` no esta publicado por el proveedor:
  // `NOTAS_CREDITO_DESDE_FACTURA.md` documenta 1/2/3 y sus ejemplos solo
  // muestran 1. Antes se enviaba `?? 1` cuando el llamador no lo aportaba, es
  // decir, se declaraba una causa de modificacion que nadie habia elegido.
  // Ahora se exige y se rechaza lo que no tenga causa documentada.
  if (document.type === "E34") {
    if (metadata.modificationCode === undefined) {
      return {
        ok: false,
        blockedReason: DOSA_MAPPER_BLOCKED.modificationCodeRequired,
      };
    }
    if (DOSA_CODIGO_MODIFICACION[metadata.modificationCode] === undefined) {
      return {
        ok: false,
        blockedReason: `${DOSA_MAPPER_BLOCKED.modificationCodeUnsupported}:${metadata.modificationCode}`,
      };
    }
  }
  if (document.unsupportedFields && Object.keys(document.unsupportedFields).length > 0) {
    return { ok: false, blockedReason: DOSA_MAPPER_BLOCKED.unsupportedFields };
  }

  const items: DosaEcfItem[] = [];
  for (const line of document.lines) {
    const unidad = unidadMedida(line);
    if ("blockedReason" in unidad) {
      // Dato fiscal obligatorio ausente o no traducible: se rechaza antes de
      // construir el borrador. Mandarlo sin unidad, o con un código inventado,
      // produciría un comprobante inválido.
      return { ok: false, blockedReason: unidad.blockedReason };
    }
    items.push({
      numeroLinea: line.lineNumber,
      indicadorFacturacion: indicadorFacturacion(line),
      nombreItem: line.name,
      indicadorBienoServicio: indicadorBienoServicio(line),
      unidadMedida: unidad.code,
      cantidadItem: quantityString(line.quantity),
      precioUnitarioItem: moneyString(line.unitPrice),
      montoItem: moneyString(lineAmount(line)),
    });
  }

  const draft: DosaEmissionDraft = {
    status: "DRAFT_NOT_TRANSMITTABLE",
    documentType: document.type,
    body: {
      encabezado: {
        version: DOSA_ECF_VERSION,
        idDoc: {
          tipoeCF: DOSA_TIPOS_ECF[document.type],
          eNCF: encf,
          fechaEmision: ddMmYyyy(document.issueDate),
          ...(metadata.incomeType !== undefined
            ? { tipoIngresos: String(metadata.incomeType).padStart(2, "0") }
            : {}),
          ...(metadata.paymentType !== undefined
            ? { tipoPago: String(metadata.paymentType) }
            : {}),
        },
        emisor: {
          RNCEmisor: document.sender.taxId,
          RazonSocialEmisor: document.sender.legalName,
        },
        ...(document.buyer
          ? {
              comprador: {
                ...(document.buyer.taxId ? { RNCComprador: document.buyer.taxId } : {}),
                ...(document.buyer.legalName
                  ? { RazonSocialComprador: document.buyer.legalName }
                  : {}),
              },
            }
          : {}),
        totales: {
          MontoGravadoTotal: moneyString(document.totals.taxableBase),
          MontoGravadoI1: moneyString(gravado18(document.lines)),
          MontoExento: moneyString(document.totals.exemptAmount),
          ITBIS1: "18",
          TotalITBIS: moneyString(document.totals.itbisAmount),
          MontoTotal: moneyString(document.totals.total),
        },
      },
      detallesItems: items,
      ...(document.reference?.originalENcf
        ? {
            informacionReferencia: {
              NCFModificado: document.reference.originalENcf,
              codigoModificacion: String(metadata.modificationCode),
              ...(document.reference.modificationReason
                ? { RazonModificacion: document.reference.modificationReason }
                : {}),
              ...(document.reference.originalIssueDate
                ? { FechaNCFModificado: ddMmYyyy(document.reference.originalIssueDate) }
                : {}),
            },
          }
        : {}),
    },
    unverified: UNVERIFIED_IN_DRAFT,
  };

  return { ok: true, draft };
}

/** Importe de la línea: cantidad × precio − descuento, redondeado a 2. */
function lineAmount(line: EcfLine) {
  return money(
    dec(line.quantity)
      .times(dec(line.unitPrice))
      .minus(dec(line.discountAmount ?? 0)),
  );
}

/** Base gravada al 18 %: suma de las líneas con esa categoría. */
function gravado18(lines: EcfLine[]) {
  return lines
    .filter((line) => line.taxCategory === "ITBIS_18")
    .reduce((total, line) => total.plus(lineAmount(line)), dec(0));
}

/** `2026-11-02` → `02-11-2026`. Si ya viene en ese formato, se respeta. */
function ddMmYyyy(value: string): string {
  const trimmed = value.trim();
  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(trimmed);
  if (iso) return `${iso[3]}-${iso[2]}-${iso[1]}`;
  return trimmed;
}

/** Cantidad sin ceros a la derecha, con escala de cantidad del dominio. */
function quantityString(value: EcfLine["quantity"]): string {
  const fixed = quantity(value).toFixed(ECF_QUANTITY_SCALE);
  const trimmed = fixed.replace(/0+$/, "").replace(/\.$/, "");
  return trimmed.length > 0 ? trimmed : "0";
}

/** Tipos que este mapeador reconoce hoy. */
export const DOSA_MAPPED_TYPES: readonly EcfDocumentType[] = ["E31", "E32", "E34"];
