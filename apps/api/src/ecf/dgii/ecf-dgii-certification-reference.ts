/**
 * Referencia del PROCESO OFICIAL DE CERTIFICACIÓN e-CF.
 *
 * Fuente única y verificada: el instructivo que Alanube adjuntó al ticket 4490.
 * Documento: `docs/PROCESO DE CERTIFICACIÓN COMO EMISOR ELECTRÓNICO ANTE LA
 * DGII - REPÚBLICA DOMINICANA - Reseller.docx.pdf` (12 páginas).
 *
 * Regla de este módulo: contiene SOLO hechos que el documento afirma. No
 * describe endpoints —el PDF nombra los servicios pero delega las rutas a la
 * documentación técnica, apartado «Proceso de Certificación»— y no sustituye
 * ninguna resolución oficial de la DGII.
 *
 * Sirve para dos cosas concretas:
 *  1. Que la máquina de estados del producto hable el mismo idioma que el
 *     proceso real (5 etapas / 15 pasos de la DGII).
 *  2. Que los huecos de implementación sean datos, no memoria de nadie.
 */

import { ECF_DGII_REQUIREMENT_CATALOG } from "./ecf-dgii-habilitation.policy";

export const ECF_CERTIFICATION_SOURCE = {
  document:
    "docs/PROCESO DE CERTIFICACIÓN COMO EMISOR ELECTRÓNICO ANTE LA DGII - REPÚBLICA DOMINICANA - Reseller.docx.pdf",
  /** Huella de la copia en el repositorio (idéntica a la recibida). */
  sha256Prefix: "8bcd99b30ed58691",
  pages: 12,
  provider: "ALANUBE SOLUCIONES, S.R.L.",
  providerRnc: "132-10912-2",
  /** Los 15 pasos oficiales de la DGII se reducen a 5 etapas con Alanube. */
  dgiiSteps: 15,
} as const;

/** Insumos que el contribuyente debe tener ANTES de postular (documento §I). */
export const ECF_CERTIFICATION_PREREQUISITES = [
  "RNC actualizado en la OFV y datos del Representante Legal vigentes",
  "Certificado de Firma Digital a nombre del Representante Legal o Tributario designado",
  "Solicitud para ser emisor electrónico",
  "Empresa dada de alta en el ambiente productivo de la API de Alanube",
  "Credenciales del portal de certificación de la DGII del contribuyente",
] as const;

export type EcfCertificationStage = {
  /** Etapa del instructivo. */
  id: "I" | "II" | "III" | "IV" | "V";
  title: string;
  /** Pasos del proceso DGII que cubre esta etapa. */
  dgiiSteps: readonly number[];
  /** Pasos del catálogo del producto que la representan. */
  catalogKeys: readonly string[];
  /** Quién puede resolverla: no todo lo automatiza el sistema. */
  owner: "SYSTEM" | "CLIENT" | "PROVIDER" | "AUTHORITY" | "MIXED";
};

/**
 * Las 5 etapas del instructivo y su correspondencia con el catálogo existente.
 *
 * La etapa V aparece sin `catalogKeys` a propósito: hoy el producto NO tiene un
 * paso para la asignación de roles. Se declara como hueco en lugar de simularlo.
 */
export const ECF_CERTIFICATION_STAGES: readonly EcfCertificationStage[] = [
  {
    id: "I",
    title: "Crear y firmar la postulación para ser emisor electrónico",
    dgiiSteps: [1, 2, 3, 4],
    catalogKeys: [
      "DIGITAL_CERTIFICATE",
      "ALANUBE_REGISTRATION",
      "DGII_POSTULATION",
    ],
    owner: "MIXED",
  },
  {
    id: "II",
    title: "Firmado del XML de postulación",
    dgiiSteps: [4],
    catalogKeys: ["XML_SIGNATURE"],
    owner: "MIXED",
  },
  {
    id: "III",
    title: "Generación del set de pruebas",
    dgiiSteps: [4, 12],
    catalogKeys: ["SET_TESTS", "SIMULATIONS"],
    owner: "MIXED",
  },
  {
    id: "IV",
    title: "Confirmación de URL y firmado de la declaración jurada",
    dgiiSteps: [12, 13, 14, 15],
    catalogKeys: ["SERVICE_URLS", "SWORN_DECLARATION", "FINAL_AUTHORIZATION"],
    owner: "MIXED",
  },
  {
    id: "V",
    title: "Asignación de roles en la Oficina Virtual",
    dgiiSteps: [15],
    catalogKeys: ["ROLE_ASSIGNMENT"],
    owner: "CLIENT",
  },
];

/** Requisitos del set de pruebas tal como los fija el documento (§III). */
export const ECF_SET_TESTS_CONTRACT = {
  /** 10 documentos de cada tipo de comprobante. */
  documentsPerVoucherType: 10,
  /** 1 factura de consumo inferior a 250.000 DOP. */
  consumptionInvoices: 1,
  consumptionMaxAmountDop: 250000,
  /** Nombre exacto del XML que la DGII pide subir, dentro del ZIP de resúmenes. */
  requiredConsumptionXml: "E320000002000.xml",
  /** Prefijo de la carpeta del ZIP que contiene ese XML. */
  resumesFolderPrefix: "SET_TEST_RESUMES_",
  /** Campos que acepta el servicio de generación del set. */
  requestFields: [
    "idCompany",
    "retryNumber",
    "billingIndicator",
    "itemName",
    "goodServiceIndicator",
    "itemDescription",
    "unitPriceItem",
  ],
  /** Enlaces de descarga que devuelve la consulta del set. */
  zipFields: ["documentsInfo.zipUrl", "resumesInfo.zipUrl"],
} as const;

/** La DGII verifica el estado final en un máximo de dos días (documento §IV). */
export const ECF_CERTIFICATION_VERIFICATION_MAX_DAYS = 2;

/**
 * Servicios y pasos que el proceso exige y que el producto todavía NO tiene.
 *
 * Se declaran para que ninguna pantalla ni reporte pueda presentar el proceso
 * como completo. Cada hueco nombra el servicio del documento que lo cubriría.
 */
export const ECF_CERTIFICATION_GAPS = [
  {
    key: "PROVIDER_INFO_SERVICE",
    documentRef: "Etapa I, paso 3",
    reason:
      "Consulta de información del Proveedor (tipo, nombre y versión del software; RNC, razón social y nombre comercial de Alanube).",
  },
  {
    key: "COMPANY_INFO_SERVICE",
    documentRef: "Etapas I y IV",
    reason:
      "Consultar la información de una empresa para obtener las URL de recepción, aprobación comercial y autenticación.",
  },
  {
    key: "HABILITATION_SIGNING_SERVICE",
    documentRef: "Etapas II, IV y V",
    reason:
      "Servicio de firma de documentos de habilitación: recibe el XML y el idCompany y devuelve el enlace del XML firmado.",
  },
  {
    key: "SET_TESTS_GENERATE_SERVICE",
    documentRef: "Etapa III",
    reason: "Endpoint para generar el set de pruebas.",
  },
  {
    key: "SET_TESTS_QUERY_SERVICE",
    documentRef: "Etapa III",
    reason:
      "Endpoint para consultar el set de pruebas de la compañía asociada y sus enlaces de descarga.",
  },
] as const;

/** Claves del catálogo que la referencia usa y el catálogo no declara. */
export function missingCatalogKeys(): string[] {
  const known = new Set(ECF_DGII_REQUIREMENT_CATALOG.map((item) => item.key));
  const missing = new Set<string>();
  for (const stage of ECF_CERTIFICATION_STAGES) {
    for (const key of stage.catalogKeys) {
      if (!known.has(key)) missing.add(key);
    }
  }
  return [...missing];
}

/** Etapa del instructivo a la que pertenece una clave del catálogo, o `null`. */
export function stageOfCatalogKey(key: string): EcfCertificationStage | null {
  return (
    ECF_CERTIFICATION_STAGES.find((stage) =>
      stage.catalogKeys.includes(key),
    ) ?? null
  );
}

/** Progreso por etapa a partir de las claves ya resueltas del expediente. */
export function stageProgressOf(resolvedKeys: readonly string[]) {
  const resolved = new Set(resolvedKeys);
  return ECF_CERTIFICATION_STAGES.map((stage) => {
    const total = stage.catalogKeys.length;
    const done = stage.catalogKeys.filter((key) => resolved.has(key)).length;
    return {
      id: stage.id,
      title: stage.title,
      total,
      done,
      /** Una etapa sin pasos implementados no puede darse por completada. */
      implemented: total > 0,
      complete: total > 0 && done === total,
    };
  });
}

/**
 * ¿Puede considerarse certificada la empresa?
 *
 * Exige que todas las etapas tengan pasos resueltos **y** que la asignación de
 * roles cuente con evidencia oficial. Sin lo segundo, un expediente con todos
 * los pasos marcados seguiría sin poder declararse certificado: la DGII rechaza
 * los comprobantes cuando la delegación de roles no se completó de verdad.
 */
export function canDeclareCertified(
  resolvedKeys: readonly string[],
  options: { roleAssignmentEvidenced?: boolean } = {},
): boolean {
  const allStagesComplete = stageProgressOf(resolvedKeys).every(
    (stage) => stage.complete,
  );
  return allStagesComplete && options.roleAssignmentEvidenced === true;
}
