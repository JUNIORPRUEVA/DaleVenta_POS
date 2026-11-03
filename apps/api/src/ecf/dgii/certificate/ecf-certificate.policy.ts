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

/**
 * Cómo se resolvió la identidad del titular.
 *
 * `MATCH_COMPANY` y `MATCH_REPRESENTATIVE` son distintos a propósito: un
 * certificado tributario dominicano puede emitirse a la empresa (RNC) **o a la
 * persona** que la representa. Ambos casos son válidos, pero el diagnóstico
 * debe decir cuál se usó para que el usuario entienda el resultado.
 *
 * `NOT_VERIFIABLE` no es un rechazo: significa que el expediente todavía no
 * tiene ningún identificador con el que comparar. Nunca se trata como correcto.
 */
export type EcfCertificateIdentity =
  | "MATCH_COMPANY"
  | "MATCH_REPRESENTATIVE"
  | "MISMATCH"
  | "NOT_VERIFIABLE"
  | "NOT_EVALUATED";

export type EcfCertificateHolderKind = "PERSON" | "ORGANIZATION" | "UNKNOWN";

/**
 * Diagnóstico SEGURO de la validación.
 *
 * Regla: aquí no viaja ningún identificador, ni el nombre del titular, ni la
 * huella completa. Solo booleanos, enums y fechas, que es lo necesario para
 * saber qué condición falló sin exponer datos personales ni material del
 * certificado.
 */
export type EcfCertificateDiagnostics = {
  /** Con qué dato del expediente se reconoció al titular, si se reconoció. */
  identityMatchedAs: "COMPANY" | "REPRESENTATIVE" | null;
  /** Qué datos canónicos existen (booleanos, nunca sus valores). */
  canonical: {
    hasCompanyTaxId: boolean;
    hasRepresentativeId: boolean;
  };
  /** Nombres estables de los campos canónicos que faltan. */
  missingCanonicalFields: string[];
  /** Qué campos del certificado aportaron dígitos comparables. */
  certificate: {
    hasSerialNumber: boolean;
    hasCommonNameDigits: boolean;
    hasOrganizationDigits: boolean;
    holderKind: EcfCertificateHolderKind;
    certificatesInContainer: number;
  };
  validity: {
    notBefore: string;
    notAfter: string;
    daysRemaining: number;
  };
  privateKey: {
    present: boolean;
    matchesCertificate: boolean | null;
  };
};

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
  /**
   * `true` solo si el certificado es utilizable **y** su titular está
   * identificado con un dato del expediente. Es la señal que habilita el botón
   * «Continuar»; `valid` por sí solo no lo es.
   */
  canProceed: boolean;
  code: EcfCertificateErrorCode | null;
  checks: EcfCertificateChecks;
  identity: EcfCertificateIdentity;
  daysRemaining: number | null;
  diagnostics: EcfCertificateDiagnostics;
  notes: string[];
};

function digitsOf(value: string | null | undefined): string {
  return (value ?? "").replace(/\D/g, "");
}

function daysBetween(from: Date, to: Date): number {
  return Math.floor((to.getTime() - from.getTime()) / 86_400_000);
}

/**
 * Longitudes plausibles de un identificador dominicano: 9 dígitos (RNC o
 * cédula antigua) y 11 (cédula). Se usa como filtro, no como validación.
 */
function isComparableId(digits: string): boolean {
  return digits.length === 9 || digits.length === 11;
}

/** Identificador normalizado (solo dígitos) o `null` si no es comparable. */
function comparableId(value: string | null | undefined): string | null {
  const digits = digitsOf(value);
  return isComparableId(digits) ? digits : null;
}

/**
 * Dígitos comparables de un campo del certificado.
 *
 * Se devuelven dos formas por campo, para no perder información según cómo lo
 * haya escrito la autoridad certificadora:
 *  - cada secuencia de 9+ dígitos seguida (`00112345678`);
 *  - el campo completo reducido a dígitos, cuando tiene longitud de
 *    identificador (`001-1234567-8` → `00112345678`).
 *
 * La comparación posterior es de **igualdad exacta**, nunca `includes`: una
 * subcadena produciría falsos positivos (`40323211222` dentro de
 * `140323211222`, por ejemplo).
 */
function certificateDigitCandidates(values: Array<string | null>): Set<string> {
  const out = new Set<string>();
  for (const value of values) {
    if (!value) continue;
    for (const run of value.match(/\d+/g) ?? []) {
      if (run.length >= 9) out.add(run);
    }
    const whole = digitsOf(value);
    if (isComparableId(whole)) out.add(whole);
  }
  return out;
}

/**
 * Compara el titular del certificado con los datos canónicos.
 *
 * Distingue tres desenlaces que antes se confundían:
 *
 *  - `MATCH_*`: el titular coincide con un dato registrado de ESA empresa.
 *  - `MISMATCH`: hay datos suficientes y el titular no coincide con ninguno.
 *  - `null`: todavía no se puede decidir. Ocurre cuando falta justo el dato del
 *    tipo de titular que el certificado declara: un certificado a nombre de una
 *    **persona** sin la cédula del representante registrada no es «ajeno», es
 *    «todavía no verificable». Rechazarlo sería acusar al usuario de un error
 *    que es una falta de datos del expediente.
 */
function resolveIdentity(
  inspection: CertificateInspection,
  input: {
    taxId: string | null;
    representativeId: string | null;
    holderKind: EcfCertificateHolderKind;
  },
): "MATCH_COMPANY" | "MATCH_REPRESENTATIVE" | "MISMATCH" | null {
  const candidates = certificateDigitCandidates([
    inspection.subjectSerialNumber,
    inspection.subjectCommonName,
    inspection.subjectOrganization,
  ]);
  if (input.taxId && candidates.has(input.taxId)) return "MATCH_COMPANY";
  if (input.representativeId && candidates.has(input.representativeId)) {
    return "MATCH_REPRESENTATIVE";
  }

  const hasAnyCanonical = Boolean(input.taxId || input.representativeId);
  if (!hasAnyCanonical) return null;
  // Falta el dato del tipo de titular que el certificado declara.
  if (!input.representativeId && input.holderKind === "PERSON") return null;
  if (!input.taxId && input.holderKind === "ORGANIZATION") return null;
  return "MISMATCH";
}

/**
 * Tipo de titular según los atributos del sujeto. Es informativo: ayuda a
 * entender por qué un certificado a nombre de una persona puede ser correcto
 * (representante legal o delegado) aunque el RNC del emisor sea otro.
 */
function holderKindOf(
  inspection: CertificateInspection,
): EcfCertificateHolderKind {
  const organization = (inspection.subjectOrganization ?? "").trim();
  const digitsInOrganization = digitsOf(organization).length >= 9;
  if (digitsInOrganization) return "ORGANIZATION";
  const hasPersonDigits = certificateDigitCandidates([
    inspection.subjectCommonName,
    inspection.subjectSerialNumber,
  ]).size > 0;
  if (hasPersonDigits) return "PERSON";
  if (organization.length > 0) return "ORGANIZATION";
  return "UNKNOWN";
}

export function evaluateCertificate(input: {
  inspection: CertificateInspection;
  fileName: string;
  sizeBytes: number;
  now: Date;
  /** RNC de la empresa y cédula del representante, si se conocen. */
  expectedTaxId?: string | null;
  expectedRepresentativeId?: string | null;
  /** Campos canónicos que faltan (nombres estables, nunca valores). */
  missingCanonicalFields?: readonly string[];
}): EcfCertificatePolicyResult {
  const { inspection, fileName, sizeBytes, now } = input;
  const lowerName = fileName.toLowerCase();
  const notes: string[] = [];

  const taxId = comparableId(input.expectedTaxId);
  const representativeId = comparableId(input.expectedRepresentativeId);
  const daysRemaining = daysBetween(now, inspection.notAfter);
  const holderKind = holderKindOf(inspection);

  const diagnostics: EcfCertificateDiagnostics = {
    identityMatchedAs: null,
    canonical: {
      hasCompanyTaxId: Boolean((input.expectedTaxId ?? "").trim()),
      hasRepresentativeId: Boolean((input.expectedRepresentativeId ?? "").trim()),
    },
    missingCanonicalFields: [...(input.missingCanonicalFields ?? [])],
    certificate: {
      hasSerialNumber: Boolean((inspection.subjectSerialNumber ?? "").trim()),
      hasCommonNameDigits:
        certificateDigitCandidates([inspection.subjectCommonName]).size > 0,
      hasOrganizationDigits:
        certificateDigitCandidates([inspection.subjectOrganization]).size > 0,
      holderKind,
      certificatesInContainer: inspection.certificatesInContainer,
    },
    validity: {
      notBefore: inspection.notBefore.toISOString(),
      notAfter: inspection.notAfter.toISOString(),
      daysRemaining,
    },
    privateKey: {
      present: inspection.hasPrivateKey,
      matchesCertificate: inspection.keyMatchesCertificate,
    },
  };

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

  const result = (
    valid: boolean,
    code: EcfCertificateErrorCode | null,
    identity: EcfCertificateIdentity,
    extraNotes: readonly string[],
  ): EcfCertificatePolicyResult => ({
    valid,
    // Solo habilita a continuar si el archivo sirve Y el titular está
    // identificado. «No verificable» nunca cuenta como correcto.
    canProceed: valid && identity !== "NOT_VERIFIABLE",
    code,
    checks,
    identity,
    daysRemaining,
    diagnostics,
    notes: [
      ...notes,
      ...extraNotes,
      "Esta comprobación es local: no confirma ninguna aceptación por la DGII.",
    ],
  });

  const reject = (code: EcfCertificateErrorCode): EcfCertificatePolicyResult =>
    result(false, code, "NOT_EVALUATED", notes);

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

  const resolved = resolveIdentity(inspection, {
    taxId,
    representativeId,
    holderKind,
  });
  if (resolved === null) {
    // Ni RNC ni cédula comparables (o falta justo el del tipo de titular que el
    // certificado declara): no se puede afirmar nada. Se declara y se bloquea el
    // avance, sin rechazar el archivo.
    checks.identity = "NOT_EVALUATED";
    diagnostics.identityMatchedAs = null;
    const missingRepresentative =
      !representativeId ||
      diagnostics.missingCanonicalFields.includes(
        "representative.identification",
      );
    const missingCompany =
      !taxId || diagnostics.missingCanonicalFields.includes("company.rnc");
    const missingNotes: string[] = [];
    if (missingRepresentative) {
      missingNotes.push(
        "Falta la cédula del representante legal en los datos de la empresa.",
      );
    }
    if (missingCompany) {
      missingNotes.push("Falta el RNC de la empresa en los datos fiscales.");
    }
    return result(
      true,
      ECF_CERTIFICATE_ERRORS.IDENTITY_NOT_VERIFIABLE,
      "NOT_VERIFIABLE",
      [
        "El archivo y la clave privada son correctos, pero todavía no se puede " +
          "comprobar que el certificado sea de tu empresa o de su representante.",
        ...missingNotes,
        "Complétalo en «Datos de la empresa» y vuelve a validar el mismo archivo: " +
          "no tienes que volver a empezar.",
      ],
    );
  }

  if (resolved === "MISMATCH") {
    checks.identity = "FAIL";
    diagnostics.identityMatchedAs = null;
    return result(false, ECF_CERTIFICATE_ERRORS.IDENTITY_MISMATCH, "MISMATCH", [
      "El titular del certificado no coincide con el RNC de la empresa ni con la " +
        "cédula del representante legal registrada en el expediente.",
      "Revisa que sea el certificado que la DGII emitió a tu empresa o a tu " +
        "representante, y que sus datos estén completos.",
    ]);
  }

  checks.identity = "PASS";
  diagnostics.identityMatchedAs =
    resolved === "MATCH_COMPANY" ? "COMPANY" : "REPRESENTATIVE";
  notes.push(
    resolved === "MATCH_COMPANY"
      ? "El titular coincide con el RNC de la empresa registrado en el expediente."
      : "El titular coincide con la cédula del representante legal registrada en " +
          "el expediente: el certificado está emitido a la persona que representa " +
          "a la empresa.",
  );
  notes.push(
    "La coincidencia es con los datos registrados en FullPOS; no es una " +
      "validación oficial de identidad de la DGII.",
  );

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

  return result(true, null, resolved, notes);
}
