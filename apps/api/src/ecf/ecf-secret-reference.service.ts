import { BadRequestException, Injectable } from "@nestjs/common";

const SECRET_VALUE_HINTS = [
  "-----BEGIN",
  "PRIVATE KEY",
  "CERTIFICATE",
  "PASSWORD=",
  "TOKEN=",
  "eyJ",
];

@Injectable()
export class EcfSecretReferenceService {
  normalizeOptionalReference(value: string | null | undefined) {
    if (value === undefined) return undefined;
    const normalized = `${value ?? ""}`.trim();
    if (!normalized) return null;
    this.assertReferenceOnly(normalized);
    return normalized;
  }

  assertReferenceOnly(value: string) {
    if (value.includes("\n") || value.includes("\r")) {
      throw new BadRequestException(
        "La referencia de secreto no puede contener contenido multilínea.",
      );
    }
    const upper = value.toUpperCase();
    if (SECRET_VALUE_HINTS.some((hint) => upper.includes(hint.toUpperCase()))) {
      throw new BadRequestException(
        "No envíes certificados, contraseñas ni tokens; solo referencias seguras.",
      );
    }
    if (!/^(secret|vault|env|uat):\/\/[A-Za-z0-9._:\/@_-]{3,256}$/.test(value)) {
      throw new BadRequestException(
        "Referencia de secreto inválida. Usa un identificador tipo secret://, vault://, env:// o uat://.",
      );
    }
  }
}

