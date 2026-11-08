/**
 * Declaración de la numeración que la DGII autorizó a una empresa.
 *
 * Por qué existe
 * -------------
 * El sistema no puede leer la autorización de la DGII: no hay API para eso. El
 * cliente la ve en la Oficina Virtual y la transcribe. Para que eso sea un
 * control y no una promesa, aquí se valida todo lo que se puede validar sin red
 * (tipo soportado, coherencia del rango, cantidad declarada, vencimiento) y se
 * exige una declaración explícita que queda registrada con su versión de texto.
 *
 * Este módulo es **puro**: no lee entorno, no accede a base de datos y no hace
 * red. Toda la decisión se toma con lo que recibe.
 */

/** Versión del texto de la declaración. Si el texto cambia, sube a `v2`. */
export const ECF_DGII_DECLARATION_VERSION = "v1";

/**
 * Texto que el cliente acepta al declarar. Se guarda la VERSIÓN, no el texto,
 * para que la auditoría pueda reconstruir exactamente qué aceptó cada empresa.
 */
export const ECF_DGII_DECLARATION_TEXT =
  "Declaro que estos datos son los que la DGII autorizó a mi empresa, que la " +
  "numeración que registro corresponde a ese rango y que no usaré números " +
  "fuera de él. Entiendo que emitir fuera del rango autorizado puede " +
  "invalidar el comprobante.";

/**
 * Tipos que hoy pueden declarar numeración. Se amplía cuando el camino de
 * emisión soporte el tipo; declarar un rango que no se puede usar solo confunde.
 * `E32` queda fuera hasta separar su prueba de sandbox del flujo comercial.
 */
export const ECF_SEQUENCE_TYPES = ["E31", "E34"] as const;
export type EcfSequenceType = (typeof ECF_SEQUENCE_TYPES)[number];

export const ECF_DGII_DECLARATION_ERRORS = {
  declarationRequired: "ECF_DGII_DECLARATION_REQUIRED",
  typeUnsupported: "ECF_DGII_SEQUENCE_TYPE_UNSUPPORTED",
  authorizationRequired: "ECF_DGII_SEQUENCE_AUTHORIZATION_REQUIRED",
  rangeInvalid: "ECF_DGII_SEQUENCE_RANGE_INVALID",
  quantityMismatch: "ECF_DGII_SEQUENCE_QUANTITY_MISMATCH",
  expired: "ECF_DGII_SEQUENCE_EXPIRED",
  notAuthorized: "ECF_SEQUENCE_NOT_AUTHORIZED",
  exceedsAuthorized: "ECF_SEQUENCE_EXCEEDS_AUTHORIZED",
} as const;

export type EcfAuthorizationInput = {
  documentType: string;
  authorizationNumber: string;
  rangeFrom: number;
  rangeTo: number;
  approvedQuantity: number;
  expiresAt?: string | null;
  declarationAccepted: boolean;
};

export type EcfAuthorizationAccepted = {
  ok: true;
  documentType: EcfSequenceType;
  authorizationNumber: string;
  rangeFrom: number;
  rangeTo: number;
  approvedQuantity: number;
  expiresAt: Date | null;
};

export type EcfAuthorizationRejected = {
  ok: false;
  code: string;
  message: string;
};

/** Normaliza y valida la declaración completa del cliente. */
export function validateAuthorizationDeclaration(
  input: EcfAuthorizationInput,
  now: Date = new Date(),
): EcfAuthorizationAccepted | EcfAuthorizationRejected {
  const documentType = `${input.documentType ?? ""}`.trim().toUpperCase();
  if (!ECF_SEQUENCE_TYPES.includes(documentType as EcfSequenceType)) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.typeUnsupported,
      message: `Tipo de comprobante no soportado todavía: ${documentType || "(vacío)"}.`,
    };
  }

  if (input.declarationAccepted !== true) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.declarationRequired,
      message: "Debes aceptar la declaración para guardar la numeración.",
    };
  }

  // El número de autorización es el dato que une la fila con el papel de la DGII.
  const authorizationNumber = `${input.authorizationNumber ?? ""}`.trim();
  if (!/^[0-9A-Za-z-]{4,64}$/.test(authorizationNumber)) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.authorizationRequired,
      message:
        "Escribe el número de autorización tal como aparece en la Oficina Virtual de la DGII.",
    };
  }

  const rangeFrom = Number(input.rangeFrom);
  const rangeTo = Number(input.rangeTo);
  if (
    !Number.isInteger(rangeFrom) ||
    !Number.isInteger(rangeTo) ||
    rangeFrom < 1 ||
    rangeTo < rangeFrom
  ) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.rangeInvalid,
      message: "El número final no puede ser menor que el inicial.",
    };
  }

  const approvedQuantity = Number(input.approvedQuantity);
  if (!Number.isInteger(approvedQuantity) || approvedQuantity < 1) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.rangeInvalid,
      message: "La cantidad aprobada por la DGII debe ser mayor que cero.",
    };
  }

  const declaredQuantity = rangeTo - rangeFrom + 1;
  if (declaredQuantity !== approvedQuantity) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.quantityMismatch,
      message:
        `La DGII aprobó ${approvedQuantity} comprobantes y el rango declara ` +
        `${declaredQuantity}. Corrige los números o la cantidad aprobada.`,
    };
  }

  const expiresAt = parseExpiry(input.expiresAt);
  if (expiresAt instanceof Date && expiresAt.getTime() <= now.getTime()) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.expired,
      message: `La autorización de la DGII venció el ${formatDate(expiresAt)}.`,
    };
  }

  return {
    ok: true,
    documentType: documentType as EcfSequenceType,
    authorizationNumber,
    rangeFrom,
    rangeTo,
    approvedQuantity,
    expiresAt: expiresAt instanceof Date ? expiresAt : null,
  };
}

export type AuthorizedRange = {
  authorizationNumber: string;
  rangeFrom: number;
  rangeTo: number;
  approvedQuantity: number;
  expiresAt: Date | null;
};

export type DeclaredRangeCheck =
  | { ok: true }
  | { ok: false; code: string; message: string };

/**
 * Comprueba un rango que se quiere declarar contra lo autorizado por la DGII.
 * Es la única puerta: sin autorización registrada no se declara numeración.
 */
export function checkDeclaredRangeWithinAuthorization(
  declared: { startNumber: number; endNumber: number },
  authorization: AuthorizedRange | null,
  now: Date = new Date(),
): DeclaredRangeCheck {
  if (authorization === null) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.notAuthorized,
      message:
        "Falta declarar la numeración autorizada por la DGII para este tipo de comprobante.",
    };
  }

  if (authorization.expiresAt !== null && authorization.expiresAt.getTime() <= now.getTime()) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.expired,
      message: `La autorización de la DGII venció el ${formatDate(authorization.expiresAt)}.`,
    };
  }

  if (
    declared.startNumber < authorization.rangeFrom ||
    declared.endNumber > authorization.rangeTo
  ) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.exceedsAuthorized,
      message:
        `La DGII autorizó del ${authorization.rangeFrom} al ${authorization.rangeTo} ` +
        `(autorización ${authorization.authorizationNumber}). El rango declarado se sale de ahí.`,
    };
  }

  const quantity = declared.endNumber - declared.startNumber + 1;
  if (quantity > authorization.approvedQuantity) {
    return {
      ok: false,
      code: ECF_DGII_DECLARATION_ERRORS.exceedsAuthorized,
      message:
        `La DGII aprobó ${authorization.approvedQuantity} comprobantes; estás declarando ${quantity}.`,
    };
  }

  return { ok: true };
}

function parseExpiry(value: string | null | undefined): Date | null {
  if (value === null || value === undefined) return null;
  const trimmed = `${value}`.trim();
  if (trimmed.length === 0) return null;
  // Fecha sin hora: la DGII autoriza hasta el ÚLTIMO día inclusive, así que se
  // interpreta como fin de ese día. Parsearla a medianoche bloquearía la
  // emisión justo ese día.
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    const endOfDay = new Date(`${trimmed}T23:59:59.999Z`);
    return Number.isNaN(endOfDay.getTime()) ? null : endOfDay;
  }
  const parsed = new Date(trimmed);
  // Una fecha inválida se trata como «sin vencimiento» solo si venía vacía;
  // si venía con contenido y no se puede leer, se rechaza más arriba como rango
  // inválido para no aceptar una fecha basura en silencio.
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatDate(date: Date): string {
  const day = `${date.getUTCDate()}`.padStart(2, "0");
  const month = `${date.getUTCMonth() + 1}`.padStart(2, "0");
  return `${day}/${month}/${date.getUTCFullYear()}`;
}
