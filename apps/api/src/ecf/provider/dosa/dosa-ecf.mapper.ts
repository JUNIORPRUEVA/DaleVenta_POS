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
  unitOfMeasureUnmapped: "DOSA_UNIT_OF_MEASURE_UNMAPPED",
  modificationCodeRequired: "DOSA_MODIFICATION_CODE_REQUIRED",
  modificationCodeUnsupported: "DOSA_MODIFICATION_CODE_UNSUPPORTED",
  itbisTotalsMismatch: "DOSA_ITBIS_TOTALS_MISMATCH",
  taxableBaseMismatch: "DOSA_TAXABLE_BASE_MISMATCH",
  paymentFormUnsupported: "DOSA_PAYMENT_FORM_UNSUPPORTED",
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
 * `indicadorFacturacion` — **cómo se grava la línea**, según el catálogo de la
 * DGII.
 *
 * 0 = no facturable · 1 = ITBIS 18 % · 2 = ITBIS 16 % · 3 = ITBIS 0 % ·
 * 4 = exento.
 *
 * Corrección del proveedor (noviembre 2026): versiones anteriores describían
 * este campo como «naturaleza del ítem» (1 producto, 2 servicio…). No lo es: la
 * naturaleza viaja en `indicadorBienoServicio`. Por eso ahora se deriva del
 * **tratamiento tributario real de la línea**, que el modelo sí distingue.
 *
 * Tasa cero y exención son cosas distintas y no se pueden confundir: 3 es una
 * línea gravada al 0 % (va a `MontoGravadoI3`), 4 es una línea exenta (va a
 * `MontoExento`).
 */
const INDICADOR_FACTURACION_BY_CATEGORY: Readonly<
  Record<EcfLine["taxCategory"], 0 | 1 | 2 | 3 | 4>
> = {
  NON_BILLABLE: 0,
  ITBIS_18: 1,
  ITBIS_16: 2,
  ITBIS_0: 3,
  EXEMPT: 4,
};

function indicadorFacturacion(line: EcfLine): 0 | 1 | 2 | 3 | 4 {
  return INDICADOR_FACTURACION_BY_CATEGORY[line.taxCategory];
}

/**
 * `indicadorBienoServicio` — naturaleza del ítem: **1 = bien, 2 = servicio**.
 *
 * Así lo publica el catálogo de la DGII (y así lo corrigió el proveedor en
 * noviembre de 2026). El mapeador anterior tenía la inversión.
 */
function indicadorBienoServicio(line: EcfLine): 1 | 2 {
  return line.goodServiceIndicator === "GOOD" ? 1 : 2;
}

/**
 * Traducción de la unidad de medida de FullPOS al **código entero** del catálogo
 * oficial de la DGII.
 *
 * Corrección de noviembre 2026: la tabla anterior (1 Unidad, 2 Caja, 3…20) no
 * era la de la DGII. Los valores correctos son 43 Unidad, 6 Caja/Cajón,
 * 21 Kilogramo, 17 Gramo, 23 Libra, 26 Metro, 8 Centímetro, 55 Pulgada,
 * 33 Pie, 41 Yarda, 24 Litro, 15 Galón, 13 Docena, 31 Paquete, 19 Hora, 12 Día.
 *
 * Solo se traducen las unidades que FullPOS **tiene de verdad**. Onza y mililitro
 * no existen en el catálogo de la DGII: no se inventa una equivalencia, se
 * rechaza la línea con un motivo explícito.
 *
 * El campo es **opcional** en el contrato: si la línea no trae unidad, se omite en
 * lugar de bloquear el documento.
 */
export const DOSA_UNIDAD_MEDIDA_BY_FULLPOS_CODE: Readonly<Record<string, number>> = {
  UNIT: 43,
  YARD: 41,
  METER: 26,
  FOOT: 33,
  INCH: 55,
  POUND: 23,
  KILOGRAM: 21,
  GRAM: 17,
  LITER: 24,
  GALLON: 15,
};

/** Códigos válidos del catálogo de la DGII (1..57). */
export const DOSA_UNIDAD_MEDIDA_CODES: readonly number[] = Array.from(
  { length: 57 },
  (_value, index) => index + 1,
);

/**
 * Unidad de medida: código entero de la DGII, **opcional**.
 *
 * Acepta el código ya numérico (`43`) o el código de FullPOS (`UNIT`).
 * Devuelve `omit` cuando no hay dato —el contrato permite no enviarlo— y un
 * motivo distinto cuando el código existe pero no tiene equivalencia: en ese
 * caso se rechaza la línea en lugar de enviar un número adivinado.
 */
function unidadMedida(
  line: EcfLine,
): { code: number } | { omit: true } | { blockedReason: string } {
  const raw = (line.unitOfMeasure ?? "").trim();
  if (raw.length === 0) return { omit: true };

  // Ya viene como código de la DGII.
  if (/^\d+$/.test(raw)) {
    const numeric = Number.parseInt(raw, 10);
    if (DOSA_UNIDAD_MEDIDA_CODES.includes(numeric)) return { code: numeric };
    return {
      blockedReason: `${DOSA_MAPPER_BLOCKED.unitOfMeasureUnmapped}:${line.lineNumber}:${raw}`,
    };
  }

  const code = DOSA_UNIDAD_MEDIDA_BY_FULLPOS_CODE[raw.toUpperCase()];
  if (code === undefined) {
    return {
      blockedReason: `${DOSA_MAPPER_BLOCKED.unitOfMeasureUnmapped}:${line.lineNumber}:${raw.toUpperCase()}`,
    };
  }
  return { code };
}

const UNVERIFIED_IN_DRAFT: readonly string[] = [
  "Formato de fecha (se emite dd-MM-yyyy según la documentación pública).",
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
  // Solo E31, E32 y E34 están soportados, y no por comodidad: `EcfDocumentType`
  // del dominio fiscal solo declara esos tres. E43 (gastos menores), E44
  // (regímenes especiales) y E46 (exportación) existen en la documentación del
  // proveedor pero el modelo de ventas no puede producirlos todavía. En
  // particular E46 exige tasa 0 % en `MontoGravadoI3` porque su XSD no admite
  // `MontoExento`: es una restricción que habría que implementar junto con el
  // tipo, no antes.
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
      // Código de unidad sin equivalencia oficial: se rechaza antes de
      // construir el borrador. Mandarlo con un número inventado produciría un
      // comprobante fiscal inválido.
      return { ok: false, blockedReason: unidad.blockedReason };
    }
    items.push({
      numeroLinea: line.lineNumber,
      indicadorFacturacion: indicadorFacturacion(line),
      nombreItem: line.name,
      indicadorBienoServicio: indicadorBienoServicio(line),
      ...("code" in unidad ? { unidadMedida: unidad.code } : {}),
      cantidadItem: quantityString(line.quantity),
      precioUnitarioItem: moneyString(line.unitPrice),
      montoItem: moneyString(lineAmount(line)),
    });
  }

  // Los totales se calculan desde las líneas y se contrastan con el documento.
  // Si no cuadran, no se emite: es preferible un bloqueo a un comprobante con
  // el ITBIS mal declarado (errores 1004/1005/1934/1964 de la DGII).
  const tax = summarizeTaxes(document);
  if ("blockedReason" in tax) {
    return { ok: false, blockedReason: tax.blockedReason };
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
          // Fiscal line prices are net of ITBIS (DGII: 0 = tax excluded).
          indicadorMontoGravado: 0,
          ...(metadata.sequenceDueDate && document.type === "E31"
            ? { fechavencimientosecuencia: ddMmYyyy(metadata.sequenceDueDate) } : {}),
          ...(metadata.paymentDeadline ? { fechaLimitePago: ddMmYyyy(metadata.paymentDeadline) } : {}),
          ...(document.paymentForms && document.type !== "E34"
            ? { tablaFormasPago: { formaDePago: document.paymentForms.map(payment => ({
                formaPago: payment.code, montoPago: payment.amount,
              })) } } : {}),
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
          nombreComercial: document.sender.tradeName ?? document.sender.legalName,
          ...(document.sender.address ? { direccionEmisor: document.sender.address } : {}),
          fechaEmision: ddMmYyyy(document.issueDate),
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
          MontoGravadoTotal: moneyString(tax.taxableBase),
          MontoGravadoI1: moneyString(tax.baseI1),
          ...(tax.hasI2 ? { MontoGravadoI2: moneyString(tax.baseI2) } : {}),
          ...(tax.hasI3 ? { MontoGravadoI3: moneyString(tax.baseI3) } : {}),
          MontoExento: moneyString(tax.exempt),
          ITBIS1: 18,
          ...(tax.hasI2 ? { ITBIS2: 16 } : {}),
          ...(tax.hasI3 ? { ITBIS3: 0 } : {}),
          TotalITBIS: moneyString(tax.itbisTotal),
          TotalITBIS1: moneyString(tax.itbisI1),
          ...(tax.hasI2 ? { TotalITBIS2: moneyString(tax.itbisI2) } : {}),
          ...(tax.hasI3 ? { TotalITBIS3: moneyString(tax.itbisI3) } : {}),
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

/** Tasa oficial de cada categoría. No se toma de `taxRate`: es un catálogo fijo. */
const RATE_BY_CATEGORY: Readonly<Record<EcfLine["taxCategory"], number>> = {
  ITBIS_18: 18,
  ITBIS_16: 16,
  ITBIS_0: 0,
  EXEMPT: 0,
  NON_BILLABLE: 0,
};

type TaxSummary = {
  taxableBase: ReturnType<typeof money>;
  baseI1: ReturnType<typeof money>;
  baseI2: ReturnType<typeof money>;
  baseI3: ReturnType<typeof money>;
  exempt: ReturnType<typeof money>;
  itbisI1: ReturnType<typeof money>;
  itbisI2: ReturnType<typeof money>;
  itbisI3: ReturnType<typeof money>;
  itbisTotal: ReturnType<typeof money>;
  hasI2: boolean;
  hasI3: boolean;
};

/**
 * Resumen de impuestos por tasa, calculado desde las líneas.
 *
 * Distingue expresamente **tasa cero** (va a `MontoGravadoI3`) de **exento**
 * (va a `MontoExento`): son tratamientos fiscales distintos y la DGII los
 * reconcilia por separado (1964 frente a 1934).
 *
 * Falla cerrado si el resultado no coincide con lo que el documento declara.
 */
function summarizeTaxes(
  document: EcfFiscalDocument,
): TaxSummary | { blockedReason: string } {
  const base = (category: EcfLine["taxCategory"]) =>
    document.lines
      .filter((line) => line.taxCategory === category)
      .reduce((total, line) => total.plus(lineAmount(line)), dec(0));

  const itbis = (category: EcfLine["taxCategory"]) =>
    document.lines
      .filter((line) => line.taxCategory === category)
      .reduce(
        (total, line) =>
          total.plus(
            money(
              lineAmount(line)
                .times(RATE_BY_CATEGORY[category])
                .dividedBy(100),
            ),
          ),
        dec(0),
      );

  const baseI1 = base("ITBIS_18");
  const baseI2 = base("ITBIS_16");
  const baseI3 = base("ITBIS_0");
  const exempt = base("EXEMPT");
  const itbisI1 = itbis("ITBIS_18");
  const itbisI2 = itbis("ITBIS_16");
  const itbisI3 = itbis("ITBIS_0");
  const taxableBase = baseI1.plus(baseI2).plus(baseI3);
  const itbisTotal = itbisI1.plus(itbisI2).plus(itbisI3);

  const limit = dec("0.01");
  if (taxableBase.minus(dec(document.totals.taxableBase)).abs().gt(limit)) {
    return {
      blockedReason: `${DOSA_MAPPER_BLOCKED.taxableBaseMismatch}:${moneyString(taxableBase)}!=${moneyString(dec(document.totals.taxableBase))}`,
    };
  }
  if (itbisTotal.minus(dec(document.totals.itbisAmount)).abs().gt(limit)) {
    return {
      blockedReason: `${DOSA_MAPPER_BLOCKED.itbisTotalsMismatch}:${moneyString(itbisTotal)}!=${moneyString(dec(document.totals.itbisAmount))}`,
    };
  }
  if (exempt.minus(dec(document.totals.exemptAmount)).abs().gt(limit)) {
    return {
      blockedReason: `${DOSA_MAPPER_BLOCKED.taxableBaseMismatch}:exento:${moneyString(exempt)}!=${moneyString(dec(document.totals.exemptAmount))}`,
    };
  }

  return {
    taxableBase,
    baseI1,
    baseI2,
    baseI3,
    exempt,
    itbisI1,
    itbisI2,
    itbisI3,
    itbisTotal,
    hasI2: document.lines.some((line) => line.taxCategory === "ITBIS_16"),
    hasI3: document.lines.some((line) => line.taxCategory === "ITBIS_0"),
  };
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
