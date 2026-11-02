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
} as const;

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
 * Unidad de medida: DOSA la exige en cada ítem.
 *
 * El catálogo de códigos válidos del proveedor no está documentado en los
 * materiales que tenemos, así que **no se traduce ni se inventa**: se exige que
 * venga informada y se envía tal cual. Si falta, el documento se rechaza.
 */
function unidadMedida(line: EcfLine): string | null {
  const raw = (line.unitOfMeasure ?? "").trim();
  if (raw.length === 0) return null;
  if (raw.length > 32) return null;
  return raw;
}

const UNVERIFIED_IN_DRAFT: readonly string[] = [
  "Formato de fecha (se emite dd-MM-yyyy según la documentación pública).",
  "Catálogo de códigos de unidadMedida: se exige informada, pero no se traduce porque no está documentado.",
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
  if (document.unsupportedFields && Object.keys(document.unsupportedFields).length > 0) {
    return { ok: false, blockedReason: DOSA_MAPPER_BLOCKED.unsupportedFields };
  }

  const items: DosaEcfItem[] = [];
  for (const line of document.lines) {
    const unidad = unidadMedida(line);
    if (unidad === null) {
      // Dato fiscal obligatorio ausente: se rechaza antes de construir el
      // borrador. Mandarlo sin unidad produciría un comprobante inválido.
      return {
        ok: false,
        blockedReason: `${DOSA_MAPPER_BLOCKED.unitOfMeasureRequired}:${line.lineNumber}`,
      };
    }
    items.push({
      numeroLinea: line.lineNumber,
      indicadorFacturacion: indicadorFacturacion(line),
      nombreItem: line.name,
      indicadorBienoServicio: indicadorBienoServicio(line),
      unidadMedida: unidad,
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
              codigoModificacion: String(metadata.modificationCode ?? 1),
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
