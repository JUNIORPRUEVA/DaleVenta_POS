import {
  createCipheriv,
  createDecipheriv,
  hkdfSync,
  randomBytes,
} from "node:crypto";

/**
 * Cifrado autenticado de la URL de sesión DOSA en reposo.
 *
 * Decisiones:
 * - AES-256-GCM. La clave se deriva por contexto (empresa + RNC + intento) con
 *   HKDF-SHA256, así un criptograma copiado a otra fila no se puede abrir.
 * - Envoltorio versionado `fpv1:<keyVersion>:<iv>:<tag>:<ciphertext>`.
 * - Compatibilidad: un valor sin prefijo se considera texto plano histórico.
 * - Rotación: `open()` acepta cualquier versión presente en el key ring;
 *   `seal()` usa siempre la versión activa.
 * - Sin claves válidas no hay cifrado: `ready` es `false` y el llamador debe
 *   fallar cerrado. Nunca se degrada a texto claro.
 */

export const DOSA_SESSION_URL_PREFIX = "fpv1:";
const ALGORITHM = "aes-256-gcm";
const IV_BYTES = 12;
const KEY_BYTES = 32;

export type DosaSessionUrlCipherEnv = NodeJS.ProcessEnv & {
  /** Lista `version:base64,version:base64`. Las claves deben tener 32 bytes. */
  DOSA_SESSION_URL_KEYS?: string;
  DOSA_SESSION_URL_ACTIVE_KEY_VERSION?: string;
  /** Fallback: reutiliza la clave maestra de credenciales DOSA como versión 1. */
  DOSA_CREDENTIALS_MASTER_KEY?: string;
};

export class DosaSessionUrlCipher {
  constructor(
    private readonly keys: ReadonlyMap<number, Buffer>,
    private readonly activeVersion: number,
  ) {}

  get ready(): boolean {
    return this.keys.size > 0 && this.keys.has(this.activeVersion);
  }

  get currentKeyVersion(): number {
    return this.activeVersion;
  }

  seal(input: {
    companyId: string;
    rnc: string;
    sessionId: string;
    url: string;
  }): string {
    const master = this.keys.get(this.activeVersion);
    if (!master) throw new Error("DOSA_SESSION_URL_KEY_MISSING");
    const key = deriveKey(master, input);
    const iv = randomBytes(IV_BYTES);
    const cipher = createCipheriv(ALGORITHM, key, iv);
    cipher.setAAD(aadOf(input));
    const ciphertext = Buffer.concat([
      cipher.update(Buffer.from(input.url, "utf8")),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    return [
      DOSA_SESSION_URL_PREFIX.slice(0, -1),
      String(this.activeVersion),
      iv.toString("base64"),
      tag.toString("base64"),
      ciphertext.toString("base64"),
    ].join(":");
  }

  /**
   * Devuelve la URL descifrada, el texto plano histórico si no tiene prefijo,
   * o `null` si el criptograma está corrupto o la versión no existe.
   */
  open(input: {
    companyId: string;
    rnc: string;
    sessionId: string;
    stored: string;
  }): string | null {
    const stored = input.stored ?? "";
    if (!stored.startsWith(DOSA_SESSION_URL_PREFIX)) return stored;
    const parts = stored.split(":");
    if (parts.length !== 5) return null;
    const [, rawVersion, ivB64, tagB64, cipherB64] = parts;
    const version = Number.parseInt(rawVersion, 10);
    const master = this.keys.get(version);
    if (!master || !Number.isInteger(version)) return null;
    try {
      const key = deriveKey(master, input);
      const decipher = createDecipheriv(
        ALGORITHM,
        key,
        Buffer.from(ivB64, "base64"),
      );
      decipher.setAAD(aadOf(input));
      decipher.setAuthTag(Buffer.from(tagB64, "base64"));
      const plaintext = Buffer.concat([
        decipher.update(Buffer.from(cipherB64, "base64")),
        decipher.final(),
      ]);
      return plaintext.toString("utf8");
    } catch {
      return null;
    }
  }
}

export function createDosaSessionUrlCipher(
  env: DosaSessionUrlCipherEnv = process.env,
): DosaSessionUrlCipher {
  const keys = parseKeys(env);
  const requested = Number.parseInt(
    (env.DOSA_SESSION_URL_ACTIVE_KEY_VERSION ?? "").trim(),
    10,
  );
  const activeVersion =
    Number.isInteger(requested) && keys.has(requested)
      ? requested
      : Math.max(...keys.keys());
  return new DosaSessionUrlCipher(keys, Number.isFinite(activeVersion) ? activeVersion : 0);
}

function parseKeys(env: DosaSessionUrlCipherEnv): Map<number, Buffer> {
  const keys = new Map<number, Buffer>();
  const raw = (env.DOSA_SESSION_URL_KEYS ?? "").trim();
  if (raw.length > 0) {
    for (const entry of raw.split(",")) {
      const [rawVersion, rawKey] = entry.split(":");
      const version = Number.parseInt((rawVersion ?? "").trim(), 10);
      const key = parseKey(rawKey);
      if (Number.isInteger(version) && version > 0 && key) {
        keys.set(version, key);
      }
    }
    return keys;
  }
  const fallback = parseKey(env.DOSA_CREDENTIALS_MASTER_KEY);
  if (fallback) keys.set(1, fallback);
  return keys;
}

function parseKey(value: string | undefined): Buffer | null {
  const raw = (value ?? "").trim();
  if (!raw) return null;
  try {
    const key = Buffer.from(raw, "base64");
    return key.length === KEY_BYTES ? key : null;
  } catch {
    return null;
  }
}

function deriveKey(
  master: Buffer,
  context: { companyId: string; rnc: string; sessionId: string },
): Buffer {
  const info = aadOf(context);
  return Buffer.from(
    hkdfSync("sha256", master, Buffer.from("fullpos-dosa-session-url"), info, KEY_BYTES),
  );
}

function aadOf(context: {
  companyId: string;
  rnc: string;
  sessionId: string;
}): Buffer {
  return Buffer.from(
    `${context.companyId}:${normalizeRnc(context.rnc)}:${context.sessionId}`,
    "utf8",
  );
}

function normalizeRnc(value: string): string {
  return `${value ?? ""}`.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}
