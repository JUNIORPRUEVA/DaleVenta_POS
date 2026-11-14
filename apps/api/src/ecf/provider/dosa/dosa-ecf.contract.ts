import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";

/**
 * Contrato de emisión de DOSA — **borrador, no transmisible**.
 *
 * Basado en la documentación PÚBLICA del proveedor (no en credenciales ni en
 * pruebas contra su API). El objetivo de este archivo es que la estructura esté
 * lista y que lo que falta sea visible, no que parezca terminado.
 *
 * Regla: nada de aquí autoriza emisión. Un borrador de este módulo lleva
 * `status: "DRAFT_NOT_TRANSMITTABLE"` y no existe ningún transporte que lo envíe.
 */

export const DOSA_ECF_EMISSION_PATH = "/fe/api/emision/ecf/EnviarFactura";
export const DOSA_ECF_CREDIT_NOTE_PATH = "/fe/api/emision/ecf/NotaDesdeFactura";
export const DOSA_AUTH_HEADER = "X-API-KEY";
export const DOSA_ECF_VERSION = "1.0";

/** `tipoeCF` numérico que usa DOSA para cada tipo interno. */
export const DOSA_TIPOS_ECF: Record<EcfDocumentType, "31" | "32" | "34"> = {
  E31: "31",
  E32: "32",
  E34: "34",
};

/**
 * Códigos de estado que devuelve el proveedor para el comprobante.
 *
 * Se copian tal cual de la tabla oficial. La tabla y sus propios ejemplos se
 * contradicen en el código `0` (ver `DOSA_STATUS_TABLE_CONFLICT`), así que el
 * mapeo a estados internos NO se implementa todavía.
 */
export type DosaFiscalStatus = "0" | "1" | "2" | "3" | "4";

export const DOSA_FISCAL_STATUS_LABEL: Record<DosaFiscalStatus, string> = {
  "0": "No encontrado",
  "1": "Aceptado",
  "2": "Rechazado",
  "3": "En proceso",
  "4": "Aceptado condicional",
};

/**
 * Conflicto conocido y NO resuelto en la documentación del proveedor:
 * la tabla dice que `0` es «No encontrado» mientras que su ejemplo de manejo de
 * respuestas trata `0` como «Rechazado». Interpretarlo mal cambiaría el estado
 * fiscal de un comprobante, así que se deja explícito.
 */
export const DOSA_STATUS_TABLE_CONFLICT = {
  code: "0",
  tableSays: "No encontrado",
  exampleSays: "Rechazado",
  resolved: false,
} as const;

/** Códigos de error documentados públicamente, por área. */
export const DOSA_ERROR_CODES: Readonly<Record<string, string>> = {
  "1001": "RNC del emisor",
  "1002": "Secuencia duplicada",
  "1003": "Fecha",
  "1004": "Totales",
  "1005": "ITBIS",
  "1934": "MontoGravadoI1",
  "1964": "MontoExento",
  "2001": "RNC del comprador",
  "2002": "Identificador de extranjero",
  "3001": "Referencia inexistente",
  "3002": "Nota de crédito excede el original",
};

/**
 * Huecos del contrato que impiden transmitir. Se mantiene en código para que la
 * lista viaje con el proyecto y no dependa de una conversación.
 */
export const DOSA_CONTRACT_GAPS = [
  "Formato exacto de fecha (la documentación muestra dd-MM-yyyy; falta confirmación).",
  "Cuándo usar 3 (Mixta) y 4 (Servicio profesional) en indicadorFacturacion: el modelo común solo distingue bien de servicio.",
  "Valores del catálogo de codigoModificacion: el documento dice «Código del tipo de modificación» pero no publica la tabla; los ejemplos solo muestran 1.",
  "Forma del request para E34: los ejemplos de NotaDesdeFactura usan claves PascalCase (Encabezado, DetallesItems.Items, Referencia) y el ejemplo de EnviarFactura camelCase.",
  "Si `paginacion` es obligatoria o solo para comprobantes con muchas líneas.",
  "Valores válidos de codigoModificacion por tipo de nota de crédito.",
  "Significado operativo de codigo 0 frente a codigo 2 (tabla vs ejemplo).",
  "Si un envío fallido consume la secuencia (afecta a la idempotencia).",
  "Alcance de la API Key de TEST: ¿una empresa o varias bajo el mismo partner?",
] as const;

export type DosaEcfIdDoc = {
  tipoeCF: "31" | "32" | "34";
  eNCF: string;
  fechaEmision: string;
  /** Solo E34: referencia al comprobante original. */
  tipoIngresos?: string;
  tipoPago?: string | number;
  indicadorMontoGravado?: number;
  fechavencimientosecuencia?: string;
  fechaLimitePago?: string;
  tablaFormasPago?: { formaDePago: Array<{ formaPago: string; montoPago: string }> };
};

export type DosaEcfEmisor = {
  RNCEmisor: string;
  RazonSocialEmisor: string;
  nombreComercial?: string;
  direccionEmisor?: string;
  fechaEmision?: string;
};

export type DosaEcfComprador = {
  RNCComprador?: string;
  RazonSocialComprador?: string;
};

export type DosaEcfTotales = {
  MontoGravadoTotal: string;
  MontoGravadoI1: string;
  /** Solo cuando hay líneas al 16 %. */
  MontoGravadoI2?: string;
  /** Solo cuando hay líneas al 0 % (no exentas). */
  MontoGravadoI3?: string;
  MontoExento: string;
  /** Tasas, no montos: la DGII las espera como número. */
  ITBIS1: number;
  ITBIS2?: number;
  ITBIS3?: number;
  TotalITBIS: string;
  TotalITBIS1?: string;
  TotalITBIS2?: string;
  TotalITBIS3?: string;
  MontoTotal: string;
};

export type DosaEcfItem = {
  numeroLinea: number;
  /**
   * Indicador de facturación de la **DGII**: cómo se grava la línea.
   *
   * 0 = no facturable · 1 = ITBIS 18 % · 2 = ITBIS 16 % · 3 = ITBIS 0 % ·
   * 4 = exento. **No** dice si es producto o servicio: eso va en
   * `indicadorBienoServicio`.
   *
   * Corrección del proveedor de noviembre 2026: las versiones anteriores del
   * documento describían este campo como naturaleza del ítem.
   */
  indicadorFacturacion: 0 | 1 | 2 | 3 | 4;
  nombreItem: string;
  /** Naturaleza del ítem: 1 = bien, 2 = servicio (catálogo DGII). */
  indicadorBienoServicio: 1 | 2;
  /**
   * Código **entero** del catálogo de unidades de medida de la DGII
   * (1..57). Opcional: si no se conoce la equivalencia, se omite en lugar de
   * inventar un código.
   */
  unidadMedida?: number;
  cantidadItem: string;
  precioUnitarioItem: string;
  montoItem: string;
};

export type DosaEcfReferencia = {
  NCFModificado: string;
  codigoModificacion: string;
  RazonModificacion?: string;
  FechaNCFModificado?: string;
};

export type DosaEcfRequestBody = {
  encabezado: {
    version: string;
    idDoc: DosaEcfIdDoc;
    emisor: DosaEcfEmisor;
    comprador?: DosaEcfComprador;
    totales: DosaEcfTotales;
  };
  detallesItems: DosaEcfItem[];
  informacionReferencia?: DosaEcfReferencia;
};

/**
 * Borrador de emisión. `status` es fijo: no existe un estado "listo para
 * enviar" mientras `DOSA_CONTRACT_GAPS` y la política de firma sigan abiertos.
 */
export type DosaEmissionDraft = {
  status: "DRAFT_NOT_TRANSMITTABLE";
  documentType: EcfDocumentType;
  body: DosaEcfRequestBody;
  /** Lo que aún no está confirmado y afecta directamente a este borrador. */
  unverified: readonly string[];
};
