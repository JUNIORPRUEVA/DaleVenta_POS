import { createHash } from "crypto";

import forge from "node-forge";

import {
  ECF_CERTIFICATE_ERRORS,
  type EcfCertificateErrorCode,
} from "./ecf-certificate.errors";

/**
 * Inspección CRIPTOGRÁFICA de un certificado PKCS#12 (.pfx / .p12).
 *
 * Qué hace: abre el contenedor, extrae el certificado X.509 y la clave privada,
 * comprueba que ambos se corresponden y devuelve metadatos verificables.
 *
 * Qué NO hace:
 *  - No valida la cadena de confianza ni la revocación (requiere red y una AC
 *    de referencia; queda declarado como `NOT_EVALUATED`).
 *  - No compara la identidad del titular con el expediente (eso es una regla de
 *    negocio, en `ecf-certificate.policy.ts`).
 *  - No persiste nada: el material vive en memoria durante la petición.
 *
 * Sobre el borrado de memoria: JavaScript no garantiza el borrado de cadenas
 * internas. Lo que sí se hace es no retener el material, no registrarlo y poner
 * a cero el búfer de entrada en cuanto se usa (mejor esfuerzo, no una garantía).
 */

export type CertificateInspection = {
  subjectCommonName: string | null;
  subjectOrganization: string | null;
  /** Campo `serialNumber` del sujeto: suele llevar el RNC o la cédula. */
  subjectSerialNumber: string | null;
  issuerCommonName: string | null;
  serialNumberHex: string;
  notBefore: Date;
  notAfter: Date;
  signatureAlgorithm: string | null;
  /** Huella SHA-256 del DER del certificado, en hexadecimal con dos puntos. */
  fingerprintSha256: string;
  hasPrivateKey: boolean;
  /**
   * `null` cuando no se pudo comprobar (algoritmo no RSA). Nunca `true` por
   * omisión: la ausencia de comprobación no es una comprobación superada.
   */
  keyMatchesCertificate: boolean | null;
  /** Número de certificados del contenedor (titular + cadena incluida). */
  certificatesInContainer: number;
};

export type CertificateInspectionResult =
  | { ok: true; inspection: CertificateInspection }
  | { ok: false; code: EcfCertificateErrorCode; detail: string };

function attribute(
  attributes: forge.pki.Certificate["subject"]["attributes"],
  name: string,
): string | null {
  const found = attributes.find(
    (entry: { name?: string; shortName?: string }) =>
      entry.name === name || entry.shortName === name,
  );
  const value = found?.value;
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function formatFingerprint(hex: string): string {
  return (hex.toUpperCase().match(/.{2}/g) ?? []).join(":");
}

/**
 * Comprueba que la clave privada corresponde al certificado.
 *
 * Solo se implementa la comparación RSA (módulo y exponente), que es la que usan
 * los certificados de firma tributaria en este contexto. Para otros algoritmos
 * devuelve `null`: preferimos declarar «no comprobado» antes que mentir.
 */
function privateKeyMatches(
  certificate: forge.pki.Certificate,
  privateKey: forge.pki.rsa.PrivateKey | null,
): boolean | null {
  if (!privateKey) return null;
  const certKey = certificate.publicKey as
    | (forge.pki.rsa.PublicKey & { n?: unknown; e?: unknown })
    | undefined;
  if (!certKey || certKey.n === undefined || certKey.e === undefined) {
    return null;
  }
  try {
    const modulus = certKey.n as unknown as { toString: (radix: number) => string };
    const exponent = certKey.e as unknown as { toString: (radix: number) => string };
    return (
      modulus.toString(16) === privateKey.n.toString(16) &&
      exponent.toString(16) === privateKey.e.toString(16)
    );
  } catch {
    return null;
  }
}

/**
 * Inspecciona el contenedor. No lanza: devuelve un resultado tipado.
 *
 * Se ejecuta con el menor tiempo posible de vida del material: al terminar, el
 * búfer recibido se sobrescribe con ceros.
 */
export function inspectPkcs12(
  bytes: Buffer,
  password: string,
): CertificateInspectionResult {
  let der: forge.asn1.Asn1;
  try {
    der = forge.asn1.fromDer(forge.util.createBuffer(bytes.toString("binary")));
  } catch {
    return {
      ok: false,
      code: ECF_CERTIFICATE_ERRORS.INVALID_FORMAT,
      detail: "El archivo no contiene estructura ASN.1 legible.",
    };
  }

  let p12: forge.pkcs12.Pkcs12Pfx;
  try {
    p12 = forge.pkcs12.pkcs12FromAsn1(der, password);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    // El proveedor de la librería distingue el fallo de MAC del resto.
    const wrongPassword = /password|mac could not be verified/i.test(message);
    return {
      ok: false,
      code: wrongPassword
        ? ECF_CERTIFICATE_ERRORS.WRONG_PASSWORD
        : ECF_CERTIFICATE_ERRORS.INVALID_FORMAT,
      detail: wrongPassword
        ? "La contraseña no permite abrir el contenedor."
        : "El contenedor PKCS#12 no se pudo abrir.",
    };
  } finally {
    bytes.fill(0);
  }

  const certBags =
    p12.getBags({ bagType: forge.pki.oids.certBag })[
      forge.pki.oids.certBag
    ] ?? [];
  const shroudedKeyBags =
    p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[
      forge.pki.oids.pkcs8ShroudedKeyBag
    ] ?? [];
  const plainKeyBags =
    p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag] ??
    [];

  const certificate = certBags
    .map((bag) => bag.cert)
    .find((cert): cert is forge.pki.Certificate => Boolean(cert));
  if (!certificate) {
    return {
      ok: false,
      code: ECF_CERTIFICATE_ERRORS.NO_CERTIFICATE,
      detail: "No se encontró un certificado X.509 en el contenedor.",
    };
  }

  const privateKey =
    (shroudedKeyBags[0]?.key as forge.pki.rsa.PrivateKey | undefined) ??
    (plainKeyBags[0]?.key as forge.pki.rsa.PrivateKey | undefined) ??
    null;

  if (!privateKey) {
    return {
      ok: false,
      code: ECF_CERTIFICATE_ERRORS.NO_PRIVATE_KEY,
      detail: "El contenedor no incluye la clave privada.",
    };
  }

  const matches = privateKeyMatches(certificate, privateKey);
  if (matches === false) {
    return {
      ok: false,
      code: ECF_CERTIFICATE_ERRORS.KEY_MISMATCH,
      detail: "La clave privada no corresponde a la clave pública del certificado.",
    };
  }

  let fingerprint: string;
  try {
    fingerprint = createHash("sha256")
      .update(
        Buffer.from(
          forge.asn1.toDer(forge.pki.certificateToAsn1(certificate)).getBytes(),
          "binary",
        ),
      )
      .digest("hex");
  } catch {
    return {
      ok: false,
      code: ECF_CERTIFICATE_ERRORS.UNSUPPORTED_ALGORITHM,
      detail: "No se pudo calcular la huella del certificado.",
    };
  }

  return {
    ok: true,
    inspection: {
      subjectCommonName: attribute(certificate.subject.attributes, "commonName"),
      subjectOrganization: attribute(
        certificate.subject.attributes,
        "organizationName",
      ),
      subjectSerialNumber: attribute(
        certificate.subject.attributes,
        "serialNumber",
      ),
      issuerCommonName: attribute(certificate.issuer.attributes, "commonName"),
      serialNumberHex: certificate.serialNumber,
      notBefore: certificate.validity.notBefore,
      notAfter: certificate.validity.notAfter,
      signatureAlgorithm: certificate.signatureOid ?? null,
      fingerprintSha256: formatFingerprint(fingerprint),
      hasPrivateKey: true,
      keyMatchesCertificate: matches,
      certificatesInContainer: certBags.length,
    },
  };
}
