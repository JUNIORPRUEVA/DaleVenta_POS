import { createCipheriv, createDecipheriv, createHash, hkdfSync, randomBytes } from "node:crypto";

/**
 * Bóveda de credenciales fiscales de DOSA — **cifrada, por empresa/RNC y con
 * control de acceso explícito**.
 *
 * Decisiones que no se negocian:
 *
 * 1. **Nunca texto claro.** Se cifra con AES-256-GCM. La clave se deriva con
 *    HKDF-SHA256 a partir de una clave maestra del entorno
 *    (`DOSA_CREDENTIALS_MASTER_KEY`) y del contexto
 *    `<companyId>:<rnc>:<environment>`, que además va como AAD. Consecuencia:
 *    un criptograma de la empresa A **no se puede descifrar** en el contexto de
 *    la empresa B aunque alguien lo copie entre filas.
 * 2. **Sin clave maestra no hay bóveda.** Si falta o es inválida, `seal` y
 *    `open` fallan cerrado; jamás se degrada a texto claro ni a una clave por
 *    defecto.
 * 3. **Nada de secretos en auditoría ni en respuestas.** `inspect()` devuelve
 *    solo presencia, huella y versión de clave. No existe ningún método que
 *    devuelva el valor a una capa distinta de `open()`.
 * 4. **`open()` exige propósito.** Solo se abre para `EMISSION` y solo si el
 *    llamador declara una autorización vigente; cualquier otro propósito
 *    lanza.
 * 5. **Un webhook no activa nada.** Lo que llega del proveedor entra como
 *    `PENDING_CONFIRMATION`; pasar a `CONFIRMED`/`ACTIVE` es un acto humano
 *    posterior y nunca ocurre aquí.
 */

export type DosaCredentialEnvironment = "test" | "production";

export type DosaCredentialStatus =
  | "PENDING_CONFIRMATION"
  | "CONFIRMED"
  | "ACTIVE"
  | "REVOKED";

/** Credenciales en claro. Su única salida legítima es `open()`. */
export type DosaCredentialBundle = {
  apiKeyProduccion?: string;
  apiKeyTest?: string;
  apiSecret?: string;
};

/** Lo único que se puede persistir o registrar. */
export type SealedDosaCredential = {
  ciphertext: string;
  iv: string;
  authTag: string;
  keyVersion: number;
  /** SHA-256 del conjunto de valores: detecta cambios sin revelar nada. */
  fingerprint: string;
  /** Qué credenciales vienen, sin sus valores. */
  present: { apiKeyProduccion: boolean; apiKeyTest: boolean; apiSecret: boolean };
};

/** Vista segura para UI, logs y auditoría. */
export type DosaCredentialInspection = {
  companyId: string;
  rnc: string;
  environment: DosaCredentialEnvironment;
  status: DosaCredentialStatus;
  keyVersion: number;
  fingerprint: string;
  present: SealedDosaCredential["present"];
  updatedAt: string | null;
};

export type DosaCredentialContext = {
  companyId: string;
  rnc: string;
  environment: DosaCredentialEnvironment;
};

export type DosaCredentialVaultRejection =
  | "DOSA_CREDENTIALS_KEY_MISSING"
  | "DOSA_CREDENTIALS_KEY_INVALID"
  | "DOSA_CREDENTIALS_EMPTY_BUNDLE"
  | "DOSA_CREDENTIALS_TAMPERED"
  | "DOSA_CREDENTIALS_CONTEXT_MISMATCH"
  | "DOSA_CREDENTIALS_OPEN_NOT_AUTHORIZED";

export class DosaCredentialVaultError extends Error {
  constructor(readonly code: DosaCredentialVaultRejection, message?: string) {
    super(message ? `${code}: ${message}` : code);
    this.name = "DosaCredentialVaultError";
  }
}

const ALGORITHM = "aes-256-gcm";
const IV_BYTES = 12;
const KEY_BYTES = 32;
export const DOSA_CREDENTIAL_KEY_VERSION = 1;

export class DosaCredentialVault {
  private readonly masterKey: Buffer | null;

  constructor(masterKeyBase64: string | null | undefined) {
    this.masterKey = parseMasterKey(masterKeyBase64);
  }

  /** Clave maestra presente y con el tamaño correcto. */
  get isReady(): boolean {
    return this.masterKey !== null;
  }

  seal(context: DosaCredentialContext, bundle: DosaCredentialBundle): SealedDosaCredential {
    const key = this.deriveKey(context);
    const present = {
      apiKeyProduccion: hasValue(bundle.apiKeyProduccion),
      apiKeyTest: hasValue(bundle.apiKeyTest),
      apiSecret: hasValue(bundle.apiSecret),
    };
    if (!present.apiKeyProduccion && !present.apiKeyTest && !present.apiSecret) {
      throw new DosaCredentialVaultError("DOSA_CREDENTIALS_EMPTY_BUNDLE");
    }

    const iv = randomBytes(IV_BYTES);
    const cipher = createCipheriv(ALGORITHM, key, iv);
    cipher.setAAD(aadOf(context));
    const plaintext = Buffer.from(JSON.stringify(bundle), "utf8");
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const authTag = cipher.getAuthTag();
    plaintext.fill(0);

    return {
      ciphertext: ciphertext.toString("base64"),
      iv: iv.toString("base64"),
      authTag: authTag.toString("base64"),
      keyVersion: DOSA_CREDENTIAL_KEY_VERSION,
      fingerprint: fingerprintOf(bundle),
      present,
    };
  }

  /**
   * Descifra. Solo para `EMISSION` y con autorización declarada por el
   * llamador (que es quien tiene la evidencia; la bóveda no la inventa).
   */
  open(input: {
    sealed: SealedDosaCredential;
    context: DosaCredentialContext;
    purpose: "EMISSION";
    authorized: boolean;
  }): DosaCredentialBundle {
    if (!input.authorized) {
      throw new DosaCredentialVaultError("DOSA_CREDENTIALS_OPEN_NOT_AUTHORIZED");
    }
    if (input.sealed.keyVersion !== DOSA_CREDENTIAL_KEY_VERSION) {
      throw new DosaCredentialVaultError(
        "DOSA_CREDENTIALS_CONTEXT_MISMATCH",
        `version ${input.sealed.keyVersion}`,
      );
    }
    const key = this.deriveKey(input.context);
    try {
      const decipher = createDecipheriv(
        ALGORITHM,
        key,
        Buffer.from(input.sealed.iv, "base64"),
      );
      decipher.setAAD(aadOf(input.context));
      decipher.setAuthTag(Buffer.from(input.sealed.authTag, "base64"));
      const plaintext = Buffer.concat([
        decipher.update(Buffer.from(input.sealed.ciphertext, "base64")),
        decipher.final(),
      ]);
      const parsed = JSON.parse(plaintext.toString("utf8")) as DosaCredentialBundle;
      plaintext.fill(0);
      return parsed;
    } catch {
      // El AAD incluye empresa/RNC/entorno: un criptograma movido de fila falla
      // aquí, que es exactamente lo que queremos que ocurra.
      throw new DosaCredentialVaultError("DOSA_CREDENTIALS_TAMPERED");
    }
  }

  private deriveKey(context: DosaCredentialContext): Buffer {
    if (!this.masterKey) {
      throw new DosaCredentialVaultError("DOSA_CREDENTIALS_KEY_MISSING");
    }
    const derived = hkdfSync(
      "sha256",
      this.masterKey,
      Buffer.from("fullpos-dosa-credentials", "utf8"),
      Buffer.from(aadOf(context)),
      KEY_BYTES,
    );
    return Buffer.from(derived);
  }
}

function aadOf(context: DosaCredentialContext): Buffer {
  return Buffer.from(
    `${context.companyId}:${normalizeRnc(context.rnc)}:${context.environment}`,
    "utf8",
  );
}

function parseMasterKey(value: string | null | undefined): Buffer | null {
  const raw = (value ?? "").trim();
  if (raw.length === 0) return null;
  let buffer: Buffer;
  try {
    buffer = Buffer.from(raw, "base64");
  } catch {
    return null;
  }
  return buffer.length === KEY_BYTES ? buffer : null;
}

function hasValue(value: string | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

/** Huella estable del conjunto de valores, sin revelar ninguno. */
function fingerprintOf(bundle: DosaCredentialBundle): string {
  const canonical = [
    `p=${bundle.apiKeyProduccion?.trim() ?? ""}`,
    `t=${bundle.apiKeyTest?.trim() ?? ""}`,
    `s=${bundle.apiSecret?.trim() ?? ""}`,
  ].join("|");
  return createHash("sha256").update(canonical).digest("hex");
}

function normalizeRnc(value: string): string {
  return (value ?? "").replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}
