import { timingSafeEqual } from "node:crypto";

/**
 * Verificación de `X-Dosa-Signature` como **estrategia intercambiable**.
 *
 * Qué tenemos hoy, y qué NO demuestra:
 *
 * * El proveedor entregó `fulltech_webhook_secret.txt` (64 caracteres hex).
 * * Un humano escribió «`X-Dosa-Signature = secret`».
 *
 * Esa frase **no** demuestra si la cabecera lleva el secreto en claro, un MAC,
 * o un HMAC con timestamp. Por eso el valor por defecto es `BLOCKED`: sin
 * estrategia habilitada, ningún evento se considera auténtico.
 *
 * La estrategia `UNVERIFIED_PLAINTEXT_SECRET` existe solo para el laboratorio
 * local. **No basta con que el valor por defecto sea `BLOCKED`**: si alguien
 * configura la estrategia no verificada en un entorno que no sea laboratorio,
 * el sistema no la acepta. Hay dos barreras independientes:
 *
 * 1. `readDosaSignatureConfig` **degrada a `BLOCKED`** cuando el entorno no es
 *    de laboratorio, aunque la variable pida lo contrario.
 * 2. `assertDosaSignatureLabSafety` lanza en el arranque, para que el error sea
 *    ruidoso en vez de silencioso.
 *
 * Y una tercera, conceptual: aunque la estrategia estuviera activa, ese modo
 * nunca convierte un evento en autorización fiscal; solo permite probar el
 * mecanismo con tráfico propio.
 */

export type DosaSignatureStrategyId =
  | "BLOCKED"
  | "UNVERIFIED_PLAINTEXT_SECRET";

export type DosaSignatureRejection =
  | "SIGNATURE_HEADER_MISSING"
  | "STRATEGY_BLOCKED"
  | "SECRET_NOT_CONFIGURED"
  | "SIGNATURE_MISMATCH";

export type DosaSignatureResult =
  | { ok: true; strategy: DosaSignatureStrategyId }
  | { ok: false; strategy: DosaSignatureStrategyId; reason: DosaSignatureRejection };

export type DosaSignatureConfig = {
  strategy: DosaSignatureStrategyId;
  /** Secreto del webhook. Nunca se registra ni se devuelve. */
  secret: string | null;
  /** Motivo por el que la estrategia pedida no se aplicó, si aplica. */
  downgradedFrom?: DosaSignatureStrategyId;
  downgradeReason?: "NOT_A_LOCAL_LAB_ENVIRONMENT";
};

export const DOSA_SIGNATURE_HEADER = "x-dosa-signature";

/** Entornos de aplicación donde el laboratorio local es legítimo. */
export const DOSA_LAB_APP_ENVS: readonly string[] = [
  "local",
  "local-boot",
  "lab",
  "test",
  "e2e",
];

export type DosaSafetyEnv = {
  DOSA_WEBHOOK_SIGNATURE_STRATEGY?: string;
  DOSA_WEBHOOK_SECRET?: string;
  NODE_ENV?: string;
  APP_ENV?: string;
  DATABASE_URL?: string;
};

/**
 * ¿Estamos en un laboratorio local de verdad?
 *
 * Las tres condiciones son obligatorias a la vez. Cualquier valor ausente
 * implica «no es laboratorio», que es el lado seguro.
 */
export function isLocalLabEnvironment(env: DosaSafetyEnv): boolean {
  if ((env.NODE_ENV ?? "").trim().toLowerCase() === "production") return false;
  const appEnv = (env.APP_ENV ?? "").trim().toLowerCase();
  if (!DOSA_LAB_APP_ENVS.includes(appEnv)) return false;
  return isLoopbackDatabaseUrl(env.DATABASE_URL);
}

/** La base debe ser de loopback: si apunta fuera, no es laboratorio. */
export function isLoopbackDatabaseUrl(value: string | undefined): boolean {
  const raw = (value ?? "").trim();
  if (raw.length === 0) return false;
  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    return (
      host === "localhost" ||
      host === "127.0.0.1" ||
      host === "::1" ||
      host === "[::1]"
    );
  } catch {
    return false;
  }
}

/** `true` si la configuración pediría la estrategia no verificada. */
export function requestsUnverifiedStrategy(env: DosaSafetyEnv): boolean {
  return (
    (env.DOSA_WEBHOOK_SIGNATURE_STRATEGY ?? "").trim().toUpperCase() ===
    "UNVERIFIED_PLAINTEXT_SECRET"
  );
}

/**
 * Barrera de arranque: si se pide la estrategia no verificada fuera de un
 * laboratorio local, la aplicación **no arranca**. Fallar ruidosamente es
 * preferible a arrancar creyendo que hay autenticación.
 */
export function assertDosaSignatureLabSafety(
  env: DosaSafetyEnv = process.env,
): void {
  if (!requestsUnverifiedStrategy(env)) return;
  if (isLocalLabEnvironment(env)) return;
  throw new Error(
    "DOSA safety refused startup: DOSA_WEBHOOK_SIGNATURE_STRATEGY=" +
      "UNVERIFIED_PLAINTEXT_SECRET solo se permite en un laboratorio local " +
      "(NODE_ENV!=production, APP_ENV local/test y DATABASE_URL de loopback).",
  );
}

/**
 * Configuración desde entorno. Sin variable, queda bloqueado. Y aunque la
 * variable pida la estrategia no verificada, solo se aplica en laboratorio.
 */
export function readDosaSignatureConfig(env: DosaSafetyEnv): DosaSignatureConfig {
  const raw = (env.DOSA_WEBHOOK_SIGNATURE_STRATEGY ?? "").trim().toUpperCase();
  const secret = (env.DOSA_WEBHOOK_SECRET ?? "").trim();
  const secretValue = secret.length > 0 ? secret : null;

  if (raw !== "UNVERIFIED_PLAINTEXT_SECRET") {
    return { strategy: "BLOCKED", secret: secretValue };
  }

  if (!isLocalLabEnvironment(env)) {
    return {
      strategy: "BLOCKED",
      secret: secretValue,
      downgradedFrom: "UNVERIFIED_PLAINTEXT_SECRET",
      downgradeReason: "NOT_A_LOCAL_LAB_ENVIRONMENT",
    };
  }

  return { strategy: "UNVERIFIED_PLAINTEXT_SECRET", secret: secretValue };
}

export function verifyDosaSignature(input: {
  headers: Record<string, string | string[] | undefined>;
  config: DosaSignatureConfig;
}): DosaSignatureResult {
  const { config } = input;
  const provided = headerValue(input.headers, DOSA_SIGNATURE_HEADER);
  if (provided === null) {
    return {
      ok: false,
      strategy: config.strategy,
      reason: "SIGNATURE_HEADER_MISSING",
    };
  }
  if (config.strategy === "BLOCKED") {
    return { ok: false, strategy: config.strategy, reason: "STRATEGY_BLOCKED" };
  }
  if (!config.secret) {
    return {
      ok: false,
      strategy: config.strategy,
      reason: "SECRET_NOT_CONFIGURED",
    };
  }
  const a = Buffer.from(provided, "utf8");
  const b = Buffer.from(config.secret, "utf8");
  if (a.length !== b.length) {
    return {
      ok: false,
      strategy: config.strategy,
      reason: "SIGNATURE_MISMATCH",
    };
  }
  if (!timingSafeEqual(a, b)) {
    return {
      ok: false,
      strategy: config.strategy,
      reason: "SIGNATURE_MISMATCH",
    };
  }
  return { ok: true, strategy: config.strategy };
}

function headerValue(
  headers: Record<string, string | string[] | undefined>,
  name: string,
): string | null {
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() !== name) continue;
    if (typeof value === "string") {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }
    if (Array.isArray(value)) {
      const first = value.find(
        (item) => typeof item === "string" && item.trim().length > 0,
      );
      return first ? first.trim() : null;
    }
    return null;
  }
  return null;
}
