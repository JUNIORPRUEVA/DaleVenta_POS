import type { CertificateInspection } from "./ecf-certificate-inspector";
import {
  ECF_CERTIFICATE_ERRORS,
  type EcfCertificateErrorCode,
} from "./ecf-certificate.errors";

/**
 * Reglas de aceptación de un certificado para el proceso de habilitación.
 *
 * Son funciones puras: reciben la inspección criptográfica ya hecha y deciden.
 * Separan tres cosas que suelen confundirse:
 *
 *  1. **Comprobación criptográfica** (formato, contraseña, clave, vigencia): aquí
 *     sí se puede afirmar PASS o FAIL.
 *  2. **Identidad del titular**: solo se evalúa si se conoce el dato esperado.
 *     Sin dato, se declara `NOT_EVALUATED`, nunca PASS por omisión.
 *  3. **Confianza y revocación**: quedan `NOT_EVALUATED` siempre; requieren red y
 *     una autoridad de certificación de referencia.
 */

export const ECF_CERTIFICATE_LIMITS = {
  /** 2 MB: un PFX con cadena no llega a eso. */
  maxBytes: 2 * 1024 * 1024,
  allowedExtensions: [".pfx", ".p12"],
  /** Margen mínimo de vigencia para que el trámite tenga sentido. */
  minDaysRemaining: 1,
} as const;

export type EcfCertificateCheckStatus = "PASS" | "FAIL" | "NOT_EVALUATED";

export type EcfCertificateIdentity =
  | "MATCH"
  | "MISMATCH"
  | "NOT_EVALUATED";

export type EcfCertificateChecks = {
  format: EcfCertificateCheckStatus;
  password: EcfCertificateCheckStatus;
  privateKey: EcfCertificateCheckStatus;
  keyMatch: EcfCertificateCheckStatus;
  validity: EcfCertificateCheckStatus;
  identity: EcfCertificateCheckStatus;
  trustChain: EcfCertificateCheckStatus;
  revocation: EcfCertificateCheckStatus;
};

export type EcfCertificatePolicyResult = {
  valid: boolean;
  code: EcfCertificateErrorCode | null;
  checks: EcfCertificateChecks;
  identity: EcfCertificateIdentity;
  daysRemaining: number | null;
  notes: string[];
};

function digitsOf(value: string | null | undefined): string {
  return (value ?? "").replace(/\D/g, "");
}

function daysBetween(from: Date, to: Date): number {
  return Math.floor((to.getTime() - from.getTime()) / 86_400_000);
}

/**
 * ¿Aparece alguno de los identificadores esperados en los campos de identidad del
 * sujeto? Se comparan solo dígitos para no depender del formato (guiones, puntos).
 */
function identityMatches(
  inspection: CertificateInspection,
  expected: readonly string[],
): boolean | null {
  const wanted = expected.map(digitsOf).filter((value) => value.length >= 9);
  if (wanted.length === 0) return null;
  const haystack = [
    inspection.subjectSerialNumber,
    inspection.subjectCommonName,
    inspection.subjectOrganization,
  ]
    .map(digitsOf)
    .filter((value) => value.length > 0)
    .join("|");
  if (haystack.length === 0) return false;
  return wanted.some((value) => haystack.includes(value));
}

export function evaluateCertificate(input: {
  inspection: CertificateInspection;
  fileName: string;
  sizeBytes: number;
  now: Date;
  /** RNC de la empresa y cédula del representante, si se conocen. */
  expectedTaxId?: string | null;
  expectedRepresentativeId?: string | null;
}): EcfCertificatePolicyResult {
  const { inspection, fileName, sizeBytes, now } = input;
  const lowerName = fileName.toLowerCase();
  const notes: string[] = [];
  const checks: EcfCertificateChecks = {
    format: "PASS",
    password: "PASS",
    privateKey: "PASS",
    keyMatch:
      inspection.keyMatchesCertificate === true
        ? "PASS"
        : inspection.keyMatchesCertificate === false
          ? "FAIL"
          : "NOT_EVALUATED",
    validity: "PASS",
    identity: "NOT_EVALUATED",
    trustChain: "NOT_EVALUATED",
    revocation: "NOT_EVALUATED",
  };

  const reject = (code: EcfCertificateErrorCode): EcfCertificatePolicyResult => ({
    valid: false,
    code,
    checks,
    identity: "NOT_EVALUATED",
    daysRemaining: daysBetween(now, inspection.notAfter),
    notes: [
      ...notes,
      "Esta comprobación es local: no confirma ninguna aceptación por la DGII.",
    ],
  });

  if (sizeBytes > ECF_CERTIFICATE_LIMITS.maxBytes) {
    checks.format = "FAIL";
    return reject(ECF_CERTIFICATE_ERRORS.TOO_LARGE);
  }
  if (
    !ECF_CERTIFICATE_LIMITS.allowedExtensions.some((extension) =>
      lowerName.endsWith(extension),
    )
  ) {
    checks.format = "FAIL";
    return reject(ECF_CERTIFICATE_ERRORS.EXTENSION_NOT_ALLOWED);
  }
  if (inspection.notAfter.getTime() <= now.getTime()) {
    checks.validity = "FAIL";
    return reject(ECF_CERTIFICATE_ERRORS.EXPIRED);
  }
  if (inspection.notBefore.getTime() > now.getTime()) {
    checks.validity = "FAIL";
    return reject(ECF_CERTIFICATE_ERRORS.NOT_YET_VALID);
  }
  if (inspection.keyMatchesCertificate === false) {
    return reject(ECF_CERTIFICATE_ERRORS.KEY_MISMATCH);
  }

  const daysRemaining = daysBetween(now, inspection.notAfter);
  const identity = identityMatches(inspection, [
    input.expectedTaxId ?? "",
    input.expectedRepresentativeId ?? "",
  ]);
  if (identity === null) {
    checks.identity = "NOT_EVALUATED";
    notes.push(
      "La identidad del titular todavía no se compara con el expediente. Se " +
        "verificará cuando el expediente tenga los datos del representante.",
    );
  } else if (identity) {
    checks.identity = "PASS";
    notes.push(
      "El identificador del titular coincide con un dato del expediente, pero " +
        "esa coincidencia no es una validación oficial de identidad.",
    );
  } else {
    checks.identity = "FAIL";
    return {
      valid: false,
      code: ECF_CERTIFICATE_ERRORS.IDENTITY_MISMATCH,
      checks,
      identity: "MISMATCH",
      daysRemaining,
      notes: [
        ...notes,
        "El titular del certificado no coincide con el RNC ni con la cédula " +
          "registrados en el expediente.",
      ],
    };
  }

  notes.push(
    "Esta comprobación es criptográfica y local: no confirma ninguna aceptación " +
      "por la DGII ni que el certificado ya esté registrado como emisor.",
  );
  notes.push(
    "La cadena de confianza y la revocación del certificado no se han " +
      "comprobado: requieren conexión con la autoridad de certificación.",
  );
  notes.push(
    daysRemaining <= 30
      ? `El certificado caduca en ${daysRemaining} día(s). Conviene renovarlo antes de iniciar el trámite.`
      : `El certificado es válido hasta ${inspection.notAfter.toISOString().slice(0, 10)}.`,
  );

  return {
    valid: true,
    code: null,
    checks,
    identity: checks.identity === "PASS" ? "MATCH" : "NOT_EVALUATED",
    daysRemaining,
    notes,
  };
}
