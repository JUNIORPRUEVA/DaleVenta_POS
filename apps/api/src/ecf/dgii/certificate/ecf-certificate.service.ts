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
  type EcfCertificateIdentity,
} from "./ecf-certificate.policy";

/**
 * Informe que recibe la aplicación. **No contiene material del certificado**:
 * ni el archivo, ni la contraseña, ni la clave privada. Solo datos verificables
 * del certificado y el resultado de cada comprobación.
 */
export type EcfCertificateReport = {
  valid: boolean;
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
  notes: string[];
};

/**
 * Validación de certificado digital para la habilitación e-CF.
 *
 * No persiste nada. No envía el certificado a ningún proveedor. No afirma que la
 * DGII lo haya aceptado: solo dice si el archivo es un PKCS#12 correcto, si la
 * contraseña lo abre, si la clave privada corresponde al certificado y si está
 * vigente.
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
  }): EcfCertificateReport {
    const password = (input.password ?? "").trim();
    if (password.length === 0) {
      throw new BadRequestException(ECF_CERTIFICATE_ERRORS.PASSWORD_REQUIRED);
    }

    const inspection = inspectPkcs12(input.buffer, password);
    if (!inspection.ok) {
      return this.failure(inspection.code);
    }

    const policy = evaluateCertificate({
      inspection: inspection.inspection,
      fileName: input.fileName,
      sizeBytes: input.size,
      now: input.now ?? new Date(),
      expectedTaxId: input.expectedTaxId,
      expectedRepresentativeId: input.expectedRepresentativeId,
    });

    return {
      valid: policy.valid,
      code: policy.code,
      message: policy.code
        ? ECF_CERTIFICATE_MESSAGES[policy.code]
        : "El certificado es válido y está vigente.",
      certificate: this.summarize(inspection.inspection, policy.daysRemaining),
      checks: policy.checks,
      identity: policy.identity,
      notes: policy.notes,
    };
  }

  private failure(code: EcfCertificateErrorCode): EcfCertificateReport {
    return {
      valid: false,
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
