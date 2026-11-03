/**
 * Códigos estables de la validación de certificado.
 *
 * Son códigos propios del producto: el cliente recibe un motivo concreto y
 * nunca un mensaje del proveedor ni un stack. Ninguno de ellos afirma nada sobre
 * la DGII: la validación es criptográfica y local.
 */
export const ECF_CERTIFICATE_ERRORS = {
  FILE_REQUIRED: "ECF_CERTIFICATE_FILE_REQUIRED",
  PASSWORD_REQUIRED: "ECF_CERTIFICATE_PASSWORD_REQUIRED",
  TOO_LARGE: "ECF_CERTIFICATE_TOO_LARGE",
  EXTENSION_NOT_ALLOWED: "ECF_CERTIFICATE_EXTENSION_NOT_ALLOWED",
  INVALID_FORMAT: "ECF_CERTIFICATE_INVALID_FORMAT",
  WRONG_PASSWORD: "ECF_CERTIFICATE_WRONG_PASSWORD",
  NO_CERTIFICATE: "ECF_CERTIFICATE_MISSING_CERTIFICATE",
  NO_PRIVATE_KEY: "ECF_CERTIFICATE_NO_PRIVATE_KEY",
  KEY_MISMATCH: "ECF_CERTIFICATE_KEY_MISMATCH",
  EXPIRED: "ECF_CERTIFICATE_EXPIRED",
  NOT_YET_VALID: "ECF_CERTIFICATE_NOT_YET_VALID",
  IDENTITY_MISMATCH: "ECF_CERTIFICATE_IDENTITY_MISMATCH",
  /**
   * El certificado es criptograficamente correcto pero el expediente no tiene
   * ningun identificador con el que compararlo. No es un rechazo del archivo:
   * es «todavia no verificable» y no habilita a continuar.
   */
  IDENTITY_NOT_VERIFIABLE: "ECF_CERTIFICATE_IDENTITY_NOT_VERIFIABLE",
  UNSUPPORTED_ALGORITHM: "ECF_CERTIFICATE_UNSUPPORTED_KEY",
} as const;

export type EcfCertificateErrorCode =
  (typeof ECF_CERTIFICATE_ERRORS)[keyof typeof ECF_CERTIFICATE_ERRORS];

/** Mensaje para el usuario final, en español y sin jerga técnica. */
export const ECF_CERTIFICATE_MESSAGES: Readonly<
  Record<EcfCertificateErrorCode, string>
> = {
  [ECF_CERTIFICATE_ERRORS.FILE_REQUIRED]:
    "Selecciona tu archivo de certificado (.pfx o .p12).",
  [ECF_CERTIFICATE_ERRORS.PASSWORD_REQUIRED]:
    "Escribe la contraseña del certificado.",
  [ECF_CERTIFICATE_ERRORS.TOO_LARGE]:
    "El archivo es demasiado grande. El máximo son 2 MB.",
  [ECF_CERTIFICATE_ERRORS.EXTENSION_NOT_ALLOWED]:
    "El archivo debe ser .pfx o .p12.",
  [ECF_CERTIFICATE_ERRORS.INVALID_FORMAT]:
    "El archivo no es un certificado PKCS#12 válido.",
  [ECF_CERTIFICATE_ERRORS.WRONG_PASSWORD]:
    "La contraseña no corresponde a este certificado.",
  [ECF_CERTIFICATE_ERRORS.NO_CERTIFICATE]:
    "El archivo no contiene un certificado X.509.",
  [ECF_CERTIFICATE_ERRORS.NO_PRIVATE_KEY]:
    "El certificado no incluye su clave privada; sin ella no puede firmar.",
  [ECF_CERTIFICATE_ERRORS.KEY_MISMATCH]:
    "La clave privada del archivo no corresponde al certificado.",
  [ECF_CERTIFICATE_ERRORS.EXPIRED]:
    "El certificado está vencido.",
  [ECF_CERTIFICATE_ERRORS.NOT_YET_VALID]:
    "El certificado todavía no está vigente.",
  [ECF_CERTIFICATE_ERRORS.IDENTITY_MISMATCH]:
    "El certificado no corresponde a la empresa o al representante del expediente.",
  [ECF_CERTIFICATE_ERRORS.IDENTITY_NOT_VERIFIABLE]:
    "El certificado se abrió correctamente, pero el expediente todavía no tiene " +
    "la cédula del representante legal para comprobar que es el titular.",
  [ECF_CERTIFICATE_ERRORS.UNSUPPORTED_ALGORITHM]:
    "La clave del certificado usa un algoritmo que no se puede comprobar aquí.",
};
