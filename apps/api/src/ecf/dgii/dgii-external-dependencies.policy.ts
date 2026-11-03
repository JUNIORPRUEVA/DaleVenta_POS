/**
 * Dependencias externas de la DGII que este producto NO da por supuestas.
 *
 * Origen: investigación independiente sobre el procedimiento de postulación
 * (comunicaciones CA5244, CA5388 y CA5241 de la DGII, y el artículo 14 de la
 * Norma 10-21). Cada hallazgo se traduce aquí en una restricción EJECUTABLE y no
 * en una integración nueva: no se asume que exista una API autorizada, no se
 * modela su contrato y no se conecta nada.
 *
 * Regla que este módulo mantiene: **una operación administrativa sin API
 * autorizada confirmada es una acción del cliente**, nunca un paso automático ni
 * una espera del proveedor. Si mañana alguien reclasifica una de estas claves, la
 * clase se fuerza de vuelta a `CLIENT_ACTION` (ver `activationClassOf`).
 */

export type DgiiExternalFinding = {
  /** Identificador corto para pruebas y documentación. */
  key: string;
  /** Referencia de origen del hallazgo. */
  reference: string;
  /** Qué dice el hallazgo, en una frase. */
  statement: string;
  /** Qué NO se puede asumir en el código por este hallazgo. */
  notAssumed: string;
};

export const DGII_EXTERNAL_FINDINGS: readonly DgiiExternalFinding[] = [
  {
    key: "PROVIDER_EXCLUSIVITY",
    reference: "DGII CA5244",
    statement:
      "Una postulación en curso no puede coexistir con otra de un proveedor distinto; cambiar de proveedor obliga a iniciar de nuevo el procedimiento.",
    notAssumed:
      "No se ofrece cambio de proveedor ni se reutiliza un expediente para otro proveedor: se declara la restricción al cliente.",
  },
  {
    key: "DELEGATION_REQUEST",
    reference: "DGII CA5388",
    statement:
      "Existe una solicitud de delegación vinculada al proveedor cuyo alcance técnico sigue sin confirmarse.",
    notAssumed:
      "No se modela la delegación como paso automático ni se afirma que esté disponible: queda pendiente de confirmación externa.",
  },
  {
    key: "DELEGATED_SIGNER",
    reference: "Norma 10-21, artículo 14",
    statement:
      "La norma contempla delegación para firmar comprobantes electrónicos bajo condiciones específicas.",
    notAssumed:
      "La delegación de firma no se extiende a la declaración jurada: son actos distintos y este producto no los equipara.",
  },
  {
    key: "CERTIFICATE_IDENTITY",
    reference: "DGII CA5241",
    statement:
      "Una firma puede rechazarse por discrepancias entre el certificado, el administrador e-CF y los datos del RNC.",
    notAssumed:
      "La comprobación local compara certificado y expediente; no verifica el rol de administrador e-CF en la DGII, así que un certificado válido no garantiza aceptación.",
  },
];

/** Operación administrativa que hoy no tiene API autorizada confirmada. */
export type DgiiOperationWithoutApi = {
  key: string;
  label: string;
  /** Paso del catálogo de activación al que pertenece la operación. */
  stepKey: string;
  /** Por qué se considera sin API autorizada. */
  evidence: string;
};

export const DGII_OPERATIONS_WITHOUT_AUTHORIZED_API: readonly DgiiOperationWithoutApi[] =
  [
    {
      key: "POSTULATION",
      label: "Postulación del emisor",
      stepKey: "DGII_POSTULATION",
      evidence: "Sin contrato autorizado confirmado (CA5244 / CA5388).",
    },
    {
      key: "XML_SUBMISSION",
      label: "Presentación del XML de postulación",
      stepKey: "DGII_POSTULATION",
      evidence:
        "El XML se incorpora al expediente, pero su presentación en el portal es manual.",
    },
    {
      key: "PDF_UPLOAD",
      label: "Carga del PDF del expediente",
      stepKey: "DGII_POSTULATION",
      evidence: "No hay endpoint autorizado para adjuntarlo a la DGII.",
    },
    {
      key: "URL_REGISTRATION",
      label: "Registro de la URL de servicios",
      stepKey: "SERVICE_URLS",
      evidence: "Se registra en el portal de la DGII, no por API.",
    },
    {
      key: "SWORN_DECLARATION",
      label: "Presentación de la declaración jurada",
      stepKey: "SWORN_DECLARATION",
      evidence:
        "Acto propio del representante; la delegación de firma no lo cubre (Norma 10-21, art. 14).",
    },
  ];

/**
 * Pasos que NO pueden ser automáticos ni quedar en espera del proveedor.
 *
 * Se usa como garantía: cualquier clave listada aquí se resuelve como
 * `CLIENT_ACTION` aunque el catálogo la clasifique de otra forma.
 */
export const DGII_MANUAL_ONLY_STEP_KEYS: ReadonlySet<string> = new Set(
  DGII_OPERATIONS_WITHOUT_AUTHORIZED_API.map((operation) => operation.stepKey),
);

/** Pasos que una delegación de firma NO cubre. */
export const DGII_NOT_COVERED_BY_DELEGATED_SIGNATURE: ReadonlySet<string> =
  new Set(["SWORN_DECLARATION"]);

/** ¿La delegación de firma alcanza a este paso? Siempre `false` para actos propios. */
export function isCoveredByDelegatedSignature(stepKey: string): boolean {
  return !DGII_NOT_COVERED_BY_DELEGATED_SIGNATURE.has(stepKey);
}

/** ¿Esta operación depende de una API que todavía no está autorizada? */
export function hasAuthorizedApi(stepKey: string): boolean {
  return !DGII_MANUAL_ONLY_STEP_KEYS.has(stepKey);
}

/** Hallazgo por clave, para citarlo en la interfaz o en la documentación. */
export function findingOf(key: string): DgiiExternalFinding | undefined {
  return DGII_EXTERNAL_FINDINGS.find((finding) => finding.key === key);
}
