import { BadRequestException, Injectable } from "@nestjs/common";

import {
  ECF_CERTIFICATE_ERRORS,
  ECF_CERTIFICATE_MESSAGES,
  type EcfCertificateErrorCode,
} from "./ecf-certificate.errors";
import {
  inspectPkcs12,
  type CertificateInspection,
} from "./ecf-certificate-inspector";
import {
  evaluateCertificate,
  type EcfCertificateChecks,
  type EcfCertificateDiagnostics,
  type EcfCertificateIdentity,
} from "./ecf-certificate.policy";

/**
 * Informe que recibe la aplicación. **No contiene material del certificado**:
 * ni el archivo, ni la contraseña, ni la clave privada. Solo datos verificables
 * del certificado y el resultado de cada comprobación.
 */
export type EcfCertificateReport = {
  valid: boolean;
  /**
   * Única señal que habilita a continuar en el asistente. `valid` dice que el
   * archivo es correcto; `canProceed` añade que el titular está identificado.
   */
  canProceed: boolean;
  code: EcfCertificateErrorCode | null;
  message: string;
  certificate: {
    commonName: string | null;
    organization: string | null;
    serialNumber: string | null;
    issuer: string | null;
    notBefore: string;
    notAfter: string;
    daysRemaining: number | null;
    /** Huella abreviada para que el usuario reconozca SU certificado. */
    fingerprintShort: string;
  } | null;
  checks: EcfCertificateChecks;
  identity: EcfCertificateIdentity;
  /**
   * Qué condición falló, sin datos personales: booleanos, enums y fechas.
   * Nunca identificadores, nombres, contraseñas ni claves.
   */
  diagnostics: EcfCertificateDiagnostics;
  notes: string[];
};

/**
 * Validación de certificado digital para la habilitación e-CF.
 *
 * No persiste nada: el archivo vive en memoria durante la petición y su búfer se
 * sobrescribe al terminar la inspección. No envía el certificado a ningún
 * proveedor ni a la DGII. No afirma que la DGII lo haya aceptado: solo dice si
 * el archivo es un PKCS#12 correcto, si la contraseña lo abre, si la clave
 * privada corresponde al certificado, si está vigente y si el titular coincide
 * con los datos canónicos del expediente.
 */
@Injectable()
export class EcfCertificateService {
  validate(input: {
    fileName: string;
    buffer: Buffer;
    size: number;
    password: string | undefined;
    now?: Date;
    expectedTaxId?: string | null;
    expectedRepresentativeId?: string | null;
    /** De dónde salieron los datos esperados (siempre del backend). */
    identitySource?: "APPLICATION_SNAPSHOT" | "FISCAL_CONFIG" | "NONE";
    /** Campos canónicos ausentes; solo nombres, nunca valores. */
    missingCanonicalFields?: readonly string[];
  }): EcfCertificateReport {
    const password = (input.password ?? "").trim();
    if (password.length === 0) {
      throw new BadRequestException(ECF_CERTIFICATE_ERRORS.PASSWORD_REQUIRED);
    }

    const inspection = inspectPkcs12(input.buffer, password);
    if (!inspection.ok) {
      return this.failure(inspection.code, input);
    }

    const policy = evaluateCertificate({
      inspection: inspection.inspection,
      fileName: input.fileName,
      sizeBytes: input.size,
      now: input.now ?? new Date(),
      expectedTaxId: input.expectedTaxId,
      expectedRepresentativeId: input.expectedRepresentativeId,
      missingCanonicalFields: input.missingCanonicalFields,
    });

    return {
      valid: policy.valid,
      canProceed: policy.canProceed,
      code: policy.code,
      message: policy.code
        ? ECF_CERTIFICATE_MESSAGES[policy.code]
        : "El certificado es válido y está vigente.",
      certificate: this.summarize(inspection.inspection, policy.daysRemaining),
      checks: policy.checks,
      identity: policy.identity,
      diagnostics: policy.diagnostics,
      notes: policy.notes,
    };
  }

  private failure(
    code: EcfCertificateErrorCode,
    input: {
      expectedTaxId?: string | null;
      expectedRepresentativeId?: string | null;
      missingCanonicalFields?: readonly string[];
    },
  ): EcfCertificateReport {
    return {
      valid: false,
      canProceed: false,
      code,
      message: ECF_CERTIFICATE_MESSAGES[code],
      certificate: null,
      checks: {
        format: code === ECF_CERTIFICATE_ERRORS.WRONG_PASSWORD ? "PASS" : "FAIL",
        password:
          code === ECF_CERTIFICATE_ERRORS.WRONG_PASSWORD ? "FAIL" : "PASS",
        privateKey:
          code === ECF_CERTIFICATE_ERRORS.NO_PRIVATE_KEY ? "FAIL" : "NOT_EVALUATED",
        keyMatch:
          code === ECF_CERTIFICATE_ERRORS.KEY_MISMATCH ? "FAIL" : "NOT_EVALUATED",
        validity: "NOT_EVALUATED",
        identity: "NOT_EVALUATED",
        trustChain: "NOT_EVALUATED",
        revocation: "NOT_EVALUATED",
      },
      identity: "NOT_EVALUATED",
      // Sin inspección no hay datos del certificado que diagnosticar: se deja
      // constancia solo de qué datos canónicos existían.
      diagnostics: {
        identityMatchedAs: null,
        canonical: {
          hasCompanyTaxId: Boolean((input.expectedTaxId ?? "").trim()),
          hasRepresentativeId: Boolean(
            (input.expectedRepresentativeId ?? "").trim(),
          ),
        },
        missingCanonicalFields: [...(input.missingCanonicalFields ?? [])],
        certificate: {
          hasSerialNumber: false,
          hasCommonNameDigits: false,
          hasOrganizationDigits: false,
          holderKind: "UNKNOWN",
          certificatesInContainer: 0,
        },
        validity: {
          notBefore: "",
          notAfter: "",
          daysRemaining: 0,
        },
        privateKey: { present: false, matchesCertificate: null },
      },
      notes: [
        "No se pudo completar la comprobación criptográfica del archivo.",
        "Esta comprobación es local: no confirma ninguna aceptación por la DGII.",
      ],
    };
  }

  private summarize(
    inspection: CertificateInspection,
    daysRemaining: number | null,
  ): NonNullable<EcfCertificateReport["certificate"]> {
    const fingerprint = inspection.fingerprintSha256;
    return {
      commonName: inspection.subjectCommonName,
      organization: inspection.subjectOrganization,
      serialNumber: inspection.subjectSerialNumber,
      issuer: inspection.issuerCommonName,
      notBefore: inspection.notBefore.toISOString(),
      notAfter: inspection.notAfter.toISOString(),
      daysRemaining,
      fingerprintShort: `…${fingerprint.slice(-17)}`,
    };
  }
}
