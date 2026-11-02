/**
 * Contratos LOCALES de los servicios de certificación de Alanube.
 *
 * Alcance de esta fase: tipos, constructores de petición y validadores PUROS.
 * No hay cliente HTTP aquí, no se ejecuta ninguna llamada y no se envía nada a
 * Alanube. Los constructores producen la forma exacta de la petición para que el
 * cliente (fase siguiente) solo tenga que pasarla al transporte existente.
 *
 * Fuente: documentación pública de Alanube para República Dominicana
 * (`/dom/v1`), el instructivo adjunto al ticket 4490 y la referencia de proceso
 * ya versionada en `ecf-dgii-certification-reference.ts`.
 *
 * Regla de los constructores: deterministas y sin secretos innecesarios. El
 * certificado va SOLO en el alta de empresa y nunca se registra en auditoría.
 */

/** Operación de certificación soportada por este módulo. */
export type EcfCertificationOperation =
  | "PROVIDER_INFO"
  | "COMPANY_ENROLL"
  | "COMPANY_INFO"
  | "SIGN_HABILITATION"
  | "SET_TESTS_CREATE"
  | "SET_TESTS_CHECK";

export type EcfCertificationContract = {
  operation: EcfCertificationOperation;
  method: "POST" | "GET";
  /** Ruta relativa a la base `/dom/v1`. */
  path: string;
  /** Hueco de `ecf-dgii-certification-reference.ts` que cubre, si aplica. */
  gapKey: string | null;
  /** Qué devuelve y qué se puede afirmar con su resultado. */
  scope: string;
};

/**
 * Las seis operaciones y su ruta documentada.
 *
 * `gapKey` enlaza con `ECF_CERTIFICATION_GAPS`: así el plan, el código y la
 * referencia hablan del mismo hueco sin duplicar nombres.
 */
export const ECF_CERTIFICATION_CONTRACTS: readonly EcfCertificationContract[] = [
  {
    operation: "PROVIDER_INFO",
    method: "GET",
    path: "/provider-info",
    gapKey: "PROVIDER_INFO_SERVICE",
    scope:
      "Datos del proveedor (tipo, nombre y versión del software, RNC y razón social). No autoriza nada.",
  },
  {
    operation: "COMPANY_ENROLL",
    method: "POST",
    path: "/company",
    gapKey: null,
    scope:
      "Alta de la empresa como compañía asociada. Requiere el certificado de firma digital.",
  },
  {
    operation: "COMPANY_INFO",
    method: "GET",
    path: "/company/{idCompany}",
    gapKey: "COMPANY_INFO_SERVICE",
    scope:
      "Datos de la empresa y sus URLs de recepción, aprobación comercial y autenticación.",
  },
  {
    operation: "SIGN_HABILITATION",
    method: "POST",
    path: "/sign-document/idCompany/{idCompany}",
    gapKey: "HABILITATION_SIGNING_SERVICE",
    scope:
      "Firma el XML de habilitación y devuelve el enlace del documento firmado. Firmar no es presentar.",
  },
  {
    operation: "SET_TESTS_CREATE",
    method: "POST",
    path: "/set-tests",
    gapKey: "SET_TESTS_GENERATE_SERVICE",
    scope: "Genera el set de pruebas de la compañía asociada.",
  },
  {
    operation: "SET_TESTS_CHECK",
    method: "GET",
    // La consulta identifica el SET concreto Y la compañía asociada. La versión
    // anterior (`/check-set-tests/{idCompany}`) omitía el identificador del set:
    // con ella se habría consultado una ruta inexistente y, peor, se habrían
    // podido intercambiar ambos identificadores sin que nada lo notara.
    path: "/check-set-tests/{id}/idCompany/{idCompany}",
    gapKey: "SET_TESTS_QUERY_SERVICE",
    scope:
      "Consulta el estado de UN set de pruebas de la compañía asociada y sus enlaces de descarga. El resultado lo emite la DGII a través del proveedor.",
  },
] as const;

/**
 * Estado de cada hueco declarado en la referencia de certificación.
 *
 * `CONTRACT_DEFINED` significa: la forma de la petición y la validación de la
 * respuesta existen y están probadas, pero NO hay cliente ni llamada real. Se
 * usa un valor distinto de `IMPLEMENTED` a propósito para que ninguna pantalla
 * pueda afirmar que el hueco está cerrado.
 */
export type EcfCertificationGapStatus =
  | "PENDING"
  | "CONTRACT_DEFINED"
  | "IMPLEMENTED";

export const ECF_CERTIFICATION_GAP_STATUS: Readonly<
  Record<string, EcfCertificationGapStatus>
> = {
  PROVIDER_INFO_SERVICE: "CONTRACT_DEFINED",
  COMPANY_INFO_SERVICE: "CONTRACT_DEFINED",
  HABILITATION_SIGNING_SERVICE: "CONTRACT_DEFINED",
  SET_TESTS_GENERATE_SERVICE: "CONTRACT_DEFINED",
  SET_TESTS_QUERY_SERVICE: "CONTRACT_DEFINED",
};

// ---------------------------------------------------------------------------
// Peticiones
// ---------------------------------------------------------------------------

export type EcfCertificationRequest = {
  operation: EcfCertificationOperation;
  method: "POST" | "GET";
  path: string;
  /** Cuerpo a serializar. `undefined` en GET. */
  body?: Record<string, unknown>;
};

/** Los dos tipos de compañía que admite el proveedor. */
export type EcfAlanubeCompanyType = "primary" | "associated";

export type EcfCompanyCertificatePayload = {
  /** PKCS#12 en base64. Se usa UNA vez y no se registra. */
  p12: string;
  /** Contraseña del certificado. Nunca se registra ni se devuelve. */
  password: string;
};

/** Datos para el alta de la compañía asociada. */
export type EcfCompanyEnrollInput = {
  type: EcfAlanubeCompanyType;
  legalName: string;
  taxId: string;
  certificate: EcfCompanyCertificatePayload;
};

/** Datos del set de pruebas, según el contrato ya versionado. */
export type EcfSetTestsInput = {
  idCompany: string;
  /** 0–99, documentado por Alanube. */
  retryNumber: number;
  billingIndicator: string;
  itemName: string;
  goodServiceIndicator: string;
  itemDescription: string;
  unitPriceItem: number;
};

export type EcfSignHabilitationInput = {
  idCompany: string;
  /** XML a firmar (contenido, no ruta). */
  xml: string;
};

function contractOf(operation: EcfCertificationOperation) {
  const contract = ECF_CERTIFICATION_CONTRACTS.find(
    (item) => item.operation === operation,
  );
  if (!contract) {
    // Falla cerrada: una operación sin contrato no se puede inventar.
    throw new Error(`ECF_CERTIFICATION_CONTRACT_UNKNOWN:${operation}`);
  }
  return contract;
}

/** `GET /provider-info`. */
export function buildProviderInfoRequest(): EcfCertificationRequest {
  const contract = contractOf("PROVIDER_INFO");
  return { operation: contract.operation, method: contract.method, path: contract.path };
}

/** `POST /company` con `type` y objeto `certificate`. */
export function buildCompanyEnrollRequest(
  input: EcfCompanyEnrollInput,
): EcfCertificationRequest {
  const contract = contractOf("COMPANY_ENROLL");
  return {
    operation: contract.operation,
    method: contract.method,
    path: contract.path,
    body: {
      type: input.type,
      legalName: input.legalName,
      taxId: input.taxId,
      certificate: {
        p12: input.certificate.p12,
        password: input.certificate.password,
      },
    },
  };
}

/** `GET /company/{idCompany}`. */
export function buildCompanyInfoRequest(
  idCompany: string,
): EcfCertificationRequest {
  const contract = contractOf("COMPANY_INFO");
  return {
    operation: contract.operation,
    method: contract.method,
    path: contract.path.replace("{idCompany}", encodeURIComponent(idCompany)),
  };
}

/** `POST /sign-document/idCompany/{idCompany}`. */
export function buildSignHabilitationRequest(
  input: EcfSignHabilitationInput,
): EcfCertificationRequest {
  const contract = contractOf("SIGN_HABILITATION");
  return {
    operation: contract.operation,
    method: contract.method,
    path: contract.path.replace(
      "{idCompany}",
      encodeURIComponent(input.idCompany),
    ),
    body: { xml: input.xml },
  };
}

/** `POST /set-tests`. */
export function buildSetTestsRequest(
  input: EcfSetTestsInput,
): EcfCertificationRequest {
  const contract = contractOf("SET_TESTS_CREATE");
  return {
    operation: contract.operation,
    method: contract.method,
    path: contract.path,
    body: {
      idCompany: input.idCompany,
      retryNumber: input.retryNumber,
      billingIndicator: input.billingIndicator,
      itemName: input.itemName,
      goodServiceIndicator: input.goodServiceIndicator,
      itemDescription: input.itemDescription,
      unitPriceItem: input.unitPriceItem,
    },
  };
}

/** `GET /check-set-tests/{id}/idCompany/{idCompany}`. */
export function buildCheckSetTestsRequest(
  idSet: string,
  idCompany: string,
): EcfCertificationRequest {
  const contract = contractOf("SET_TESTS_CHECK");
  return {
    operation: contract.operation,
    method: contract.method,
    path: contract.path
      .replace("{id}", encodeURIComponent(idSet))
      .replace("{idCompany}", encodeURIComponent(idCompany)),
  };
}

// ---------------------------------------------------------------------------
// Validaciones locales (fail-closed, sin red)
// ---------------------------------------------------------------------------

export type EcfCertificationValidation =
  | { ok: true }
  | { ok: false; code: string; detail: string };

const OK: EcfCertificationValidation = { ok: true };

function fail(code: string, detail: string): EcfCertificationValidation {
  return { ok: false, code, detail };
}

function isNonEmpty(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/** Identificador de compañía del proveedor: no vacío y sin espacios. */
export function validateIdCompany(value: unknown): EcfCertificationValidation {
  if (!isNonEmpty(value)) {
    return fail("ECF_ALANUBE_ID_COMPANY_REQUIRED", "Falta el idCompany.");
  }
  if (/\s/.test(value)) {
    return fail(
      "ECF_ALANUBE_ID_COMPANY_INVALID",
      "El idCompany no puede contener espacios.",
    );
  }
  return OK;
}

/** Entrada del set de pruebas: rangos y campos obligatorios. */
export function validateSetTestsInput(
  input: EcfSetTestsInput,
): EcfCertificationValidation {
  const idCheck = validateIdCompany(input.idCompany);
  if (!idCheck.ok) return idCheck;
  if (
    !Number.isInteger(input.retryNumber) ||
    input.retryNumber < 0 ||
    input.retryNumber > 99
  ) {
    return fail(
      "ECF_ALANUBE_RETRY_NUMBER_INVALID",
      "retryNumber debe ser un entero entre 0 y 99.",
    );
  }
  const required: Array<[keyof EcfSetTestsInput, unknown]> = [
    ["billingIndicator", input.billingIndicator],
    ["itemName", input.itemName],
    ["goodServiceIndicator", input.goodServiceIndicator],
    ["itemDescription", input.itemDescription],
  ];
  for (const [field, value] of required) {
    if (!isNonEmpty(value)) {
      return fail(
        "ECF_ALANUBE_SET_TESTS_FIELD_REQUIRED",
        `Falta el campo ${String(field)}.`,
      );
    }
  }
  if (!Number.isFinite(input.unitPriceItem) || input.unitPriceItem <= 0) {
    return fail(
      "ECF_ALANUBE_UNIT_PRICE_INVALID",
      "unitPriceItem debe ser un número mayor que cero.",
    );
  }
  return OK;
}

/** El XML a firmar no puede ir vacío. */
export function validateSignHabilitationInput(
  input: EcfSignHabilitationInput,
): EcfCertificationValidation {
  const idCheck = validateIdCompany(input.idCompany);
  if (!idCheck.ok) return idCheck;
  if (!isNonEmpty(input.xml)) {
    return fail("ECF_ALANUBE_XML_REQUIRED", "No hay XML para firmar.");
  }
  return OK;
}

/**
 * Ambos identificadores de la consulta del set: el del SET y el de la COMPAÑÍA.
 *
 * Se validan por separado y se comprueba que no sean el mismo valor, porque un
 * intercambio silencioso produciría una petición a una ruta con forma válida pero
 * con los datos cruzados: el proveedor respondería «no encontrado» y parecería
 * un problema de estado del set.
 */
export function validateSetTestsIdentifiers(
  idSet: unknown,
  idCompany: unknown,
): EcfCertificationValidation {
  const companyCheck = validateIdCompany(idCompany);
  if (!companyCheck.ok) return companyCheck;
  if (!isNonEmpty(idSet)) {
    return fail(
      "ECF_ALANUBE_SET_TESTS_ID_REQUIRED",
      "Falta el identificador del set de pruebas.",
    );
  }
  if (/\s/.test(idSet)) {
    return fail(
      "ECF_ALANUBE_SET_TESTS_ID_INVALID",
      "El identificador del set no puede contener espacios.",
    );
  }
  if (idSet === idCompany) {
    return fail(
      "ECF_ALANUBE_IDENTIFIERS_SWAPPED",
      "El identificador del set y el de la compañía no pueden ser el mismo valor.",
    );
  }
  return OK;
}

/**
 * Forma mínima de una respuesta de información del proveedor.
 * No se valida lo que no se conoce: solo lo que se puede afirmar.
 */
export function validateProviderInfoResponse(
  body: unknown,
): EcfCertificationValidation {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return fail(
      "ECF_ALANUBE_PROVIDER_INFO_INVALID",
      "La respuesta del proveedor no es un objeto.",
    );
  }
  const record = body as Record<string, unknown>;
  for (const field of ["name", "taxId"]) {
    if (!isNonEmpty(record[field])) {
      return fail(
        "ECF_ALANUBE_PROVIDER_INFO_INCOMPLETE",
        `La respuesta del proveedor no incluye ${field}.`,
      );
    }
  }
  return OK;
}

/** Forma mínima de la información de la compañía (incluye `companyUrls`). */
export function validateCompanyInfoResponse(
  body: unknown,
): EcfCertificationValidation {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return fail(
      "ECF_ALANUBE_COMPANY_INFO_INVALID",
      "La respuesta de la compañía no es un objeto.",
    );
  }
  const record = body as Record<string, unknown>;
  if (!isNonEmpty(record.id)) {
    return fail(
      "ECF_ALANUBE_COMPANY_INFO_INCOMPLETE",
      "La respuesta de la compañía no incluye el identificador.",
    );
  }
  return OK;
}

/**
 * Redacta una petición para auditoría: nunca devuelve el certificado ni la
 * contraseña, solo su presencia.
 */
export function redactCertificationRequest(
  request: EcfCertificationRequest,
): Record<string, unknown> {
  const body = request.body ? { ...request.body } : undefined;
  if (body && "certificate" in body) {
    body.certificate = {
      p12: "[REDACTED]",
      password: "[REDACTED]",
    };
  }
  if (body && "xml" in body) {
    body.xml = "[REDACTED_XML]";
  }
  return {
    operation: request.operation,
    method: request.method,
    path: request.path,
    body,
  };
}
