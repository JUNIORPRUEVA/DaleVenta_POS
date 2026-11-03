import forge from "node-forge";

import { ECF_CERTIFICATE_ERRORS } from "./ecf-certificate.errors";
import { inspectPkcs12 } from "./ecf-certificate-inspector";
import { evaluateCertificate } from "./ecf-certificate.policy";
import { EcfCertificateService } from "./ecf-certificate.service";

/**
 * Certificados SINTÉTICOS generados en memoria.
 *
 * No se usa ningún certificado real: cada prueba crea su propio par de claves y
 * su propio PKCS#12 con fechas controladas.
 */
function buildKeyPair() {
  // 1024 bits es suficiente para estas pruebas y tarda milisegundos.
  return forge.pki.rsa.generateKeyPair(1024);
}

function buildCertificate(options: {
  keys: forge.pki.rsa.KeyPair;
  notBefore: Date;
  notAfter: Date;
  commonName: string;
  organization?: string;
  serialNumber?: string;
}) {
  const certificate = forge.pki.createCertificate();
  certificate.publicKey = options.keys.publicKey;
  certificate.serialNumber = "01";
  certificate.validity.notBefore = options.notBefore;
  certificate.validity.notAfter = options.notAfter;
  const attributes: Array<{ name: string; value: string }> = [
    { name: "commonName", value: options.commonName },
  ];
  if (options.organization) {
    attributes.push({ name: "organizationName", value: options.organization });
  }
  if (options.serialNumber) {
    attributes.push({ name: "serialNumber", value: options.serialNumber });
  }
  certificate.setSubject(attributes);
  certificate.setIssuer(attributes);
  certificate.sign(options.keys.privateKey, forge.md.sha256.create());
  return certificate;
}

function buildP12(input: {
  certificate: forge.pki.Certificate;
  privateKey?: forge.pki.rsa.PrivateKey;
  password: string;
}): Buffer {
  const asn1 = forge.pkcs12.toPkcs12Asn1(
    input.privateKey ?? null,
    [input.certificate],
    input.password,
  );
  return Buffer.from(forge.asn1.toDer(asn1).getBytes(), "binary");
}

const now = new Date("2026-10-31T12:00:00.000Z");

function validCertificateFixture(password = "clave-de-prueba") {
  const keys = buildKeyPair();
  const certificate = buildCertificate({
    keys,
    notBefore: new Date("2026-01-01T00:00:00.000Z"),
    notAfter: new Date("2027-01-01T00:00:00.000Z"),
    commonName: "MANOLO LIO",
    organization: "ECF VISUAL UAT DEMO",
    serialNumber: "40323211222",
  });
  return {
    keys,
    certificate,
    password,
    bytes: () => buildP12({ certificate, privateKey: keys.privateKey, password }),
  };
}

describe("certificado digital — inspección PKCS#12", () => {
  it("abre un contenedor correcto y devuelve datos verificables", () => {
    const fixture = validCertificateFixture();
    const result = inspectPkcs12(fixture.bytes(), fixture.password);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.inspection.subjectCommonName).toBe("MANOLO LIO");
    expect(result.inspection.subjectOrganization).toBe("ECF VISUAL UAT DEMO");
    expect(result.inspection.subjectSerialNumber).toBe("40323211222");
    expect(result.inspection.hasPrivateKey).toBe(true);
    expect(result.inspection.keyMatchesCertificate).toBe(true);
    expect(result.inspection.fingerprintSha256).toMatch(/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
    expect(result.inspection.notAfter.getUTCFullYear()).toBe(2027);
  });

  it("rechaza una contraseña equivocada y no confunde el motivo", () => {
    const fixture = validCertificateFixture();
    const result = inspectPkcs12(fixture.bytes(), "otra-clave");
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(ECF_CERTIFICATE_ERRORS.WRONG_PASSWORD);
  });

  it("rechaza un archivo que no es PKCS#12", () => {
    const result = inspectPkcs12(Buffer.from("no soy un certificado"), "x");
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(ECF_CERTIFICATE_ERRORS.INVALID_FORMAT);
  });

  it("detecta que la clave privada no corresponde al certificado", () => {
    const fixture = validCertificateFixture();
    const other = buildKeyPair();
    const bytes = buildP12({
      certificate: fixture.certificate,
      privateKey: other.privateKey,
      password: fixture.password,
    });
    const result = inspectPkcs12(bytes, fixture.password);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(ECF_CERTIFICATE_ERRORS.KEY_MISMATCH);
  });

  it("detecta un contenedor sin clave privada", () => {
    const fixture = validCertificateFixture();
    const bytes = buildP12({
      certificate: fixture.certificate,
      password: fixture.password,
    });
    const result = inspectPkcs12(bytes, fixture.password);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(ECF_CERTIFICATE_ERRORS.NO_PRIVATE_KEY);
  });
});

describe("certificado digital — reglas de aceptación", () => {
  function inspectValid(options?: { notAfter?: Date; notBefore?: Date }) {
    const keys = buildKeyPair();
    const certificate = buildCertificate({
      keys,
      notBefore: options?.notBefore ?? new Date("2026-01-01T00:00:00.000Z"),
      notAfter: options?.notAfter ?? new Date("2027-01-01T00:00:00.000Z"),
      commonName: "MANOLO LIO",
      organization: "ECF VISUAL UAT DEMO",
      serialNumber: "40323211222",
    });
    const result = inspectPkcs12(
      buildP12({ certificate, privateKey: keys.privateKey, password: "x" }),
      "x",
    );
    if (!result.ok) throw new Error(`fixture inválido: ${result.code}`);
    return result.inspection;
  }

  it("acepta un certificado vigente y con clave coincidente", () => {
    const result = evaluateCertificate({
      inspection: inspectValid(),
      fileName: "certificado.pfx",
      sizeBytes: 4096,
      now,
    });
    expect(result.valid).toBe(true);
    expect(result.code).toBeNull();
    expect(result.checks.validity).toBe("PASS");
    expect(result.checks.keyMatch).toBe("PASS");
    // Lo que NO se puede afirmar queda declarado.
    expect(result.checks.trustChain).toBe("NOT_EVALUATED");
    expect(result.checks.revocation).toBe("NOT_EVALUATED");
    expect(result.checks.identity).toBe("NOT_EVALUATED");
    expect(result.notes.join(" ")).toContain("no confirma");
  });

  it("rechaza un certificado vencido", () => {
    const inspection = inspectValid({
      notBefore: new Date("2024-01-01T00:00:00.000Z"),
      notAfter: new Date("2025-01-01T00:00:00.000Z"),
    });
    const result = evaluateCertificate({
      inspection,
      fileName: "certificado.pfx",
      sizeBytes: 4096,
      now,
    });
    expect(result.valid).toBe(false);
    expect(result.code).toBe(ECF_CERTIFICATE_ERRORS.EXPIRED);
    expect(result.checks.validity).toBe("FAIL");
  });

  it("rechaza un certificado que aún no es vigente", () => {
    const inspection = inspectValid({
      notBefore: new Date("2027-06-01T00:00:00.000Z"),
      notAfter: new Date("2028-06-01T00:00:00.000Z"),
    });
    const result = evaluateCertificate({
      inspection,
      fileName: "certificado.pfx",
      sizeBytes: 4096,
      now,
    });
    expect(result.code).toBe(ECF_CERTIFICATE_ERRORS.NOT_YET_VALID);
  });

  it("rechaza extensiones y tamaños no admitidos", () => {
    const inspection = inspectValid();
    expect(
      evaluateCertificate({
        inspection,
        fileName: "certificado.txt",
        sizeBytes: 4096,
        now,
      }).code,
    ).toBe(ECF_CERTIFICATE_ERRORS.EXTENSION_NOT_ALLOWED);
    expect(
      evaluateCertificate({
        inspection,
        fileName: "certificado.p12",
        sizeBytes: 3 * 1024 * 1024,
        now,
      }).code,
    ).toBe(ECF_CERTIFICATE_ERRORS.TOO_LARGE);
  });

  it("compara la identidad solo cuando hay un dato esperado", () => {
    const inspection = inspectValid();
    const match = evaluateCertificate({
      inspection,
      fileName: "c.pfx",
      sizeBytes: 4096,
      now,
      expectedTaxId: "40323211222",
    });
    expect(match.identity).toBe("MATCH");

    const mismatch = evaluateCertificate({
      inspection,
      fileName: "c.pfx",
      sizeBytes: 4096,
      now,
      expectedTaxId: "133020232",
      expectedRepresentativeId: "00100000001",
    });
    expect(mismatch.valid).toBe(false);
    expect(mismatch.code).toBe(ECF_CERTIFICATE_ERRORS.IDENTITY_MISMATCH);
    expect(mismatch.identity).toBe("MISMATCH");
  });

  it("avisa cuando el certificado caduca pronto", () => {
    const inspection = inspectValid({
      notBefore: new Date("2026-01-01T00:00:00.000Z"),
      notAfter: new Date("2026-11-10T00:00:00.000Z"),
    });
    const result = evaluateCertificate({
      inspection,
      fileName: "c.pfx",
      sizeBytes: 4096,
      now,
    });
    expect(result.valid).toBe(true);
    expect(result.notes.join(" ")).toContain("caduca en");
  });
});

describe("certificado digital — informe al cliente", () => {
  const service = new EcfCertificateService();

  it("devuelve un informe sin material del certificado", () => {
    const fixture = validCertificateFixture("clave-secreta-123");
    const report = service.validate({
      fileName: "certificado.pfx",
      buffer: fixture.bytes(),
      size: 4096,
      password: "clave-secreta-123",
      now,
    });
    expect(report.valid).toBe(true);
    expect(report.certificate?.commonName).toBe("MANOLO LIO");
    expect(report.certificate?.fingerprintShort).toMatch(/^…/);
    const serialized = JSON.stringify(report);
    expect(serialized).not.toContain("clave-secreta-123");
    expect(serialized).not.toContain("PRIVATE KEY");
    expect(serialized.toLowerCase()).not.toContain("base64");
    expect(serialized).not.toContain(fixture.password);
  });

  it("explica el motivo cuando la contraseña es incorrecta", () => {
    const fixture = validCertificateFixture();
    const report = service.validate({
      fileName: "certificado.pfx",
      buffer: fixture.bytes(),
      size: 4096,
      password: "incorrecta",
      now,
    });
    expect(report.valid).toBe(false);
    expect(report.code).toBe(ECF_CERTIFICATE_ERRORS.WRONG_PASSWORD);
    expect(report.message).toContain("contraseña");
    expect(report.checks.password).toBe("FAIL");
    expect(report.certificate).toBeNull();
  });

  it("exige contraseña", () => {
    const fixture = validCertificateFixture();
    expect(() =>
      service.validate({
        fileName: "certificado.pfx",
        buffer: fixture.bytes(),
        size: 4096,
        password: "   ",
        now,
      }),
    ).toThrow(/ECF_CERTIFICATE_PASSWORD_REQUIRED/);
  });
});
