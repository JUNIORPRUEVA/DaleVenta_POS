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
 * La estrategia `UNVERIFIED_PLAINTEXT_SECRET` existe para poder probar el
 * mecanismo con peticiones sintéticas, pero está marcada como **no verificada**
 * y exige habilitación explícita. Que una prueba sintética pase **no** demuestra
 * autenticidad real: solo que el comparador funciona.
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
};

export const DOSA_SIGNATURE_HEADER = "x-dosa-signature";

/** Configuración desde entorno. Sin variable, queda bloqueado. */
export function readDosaSignatureConfig(env: {
  DOSA_WEBHOOK_SIGNATURE_STRATEGY?: string;
  DOSA_WEBHOOK_SECRET?: string;
}): DosaSignatureConfig {
  const raw = (env.DOSA_WEBHOOK_SIGNATURE_STRATEGY ?? "").trim().toUpperCase();
  const strategy: DosaSignatureStrategyId =
    raw === "UNVERIFIED_PLAINTEXT_SECRET"
      ? "UNVERIFIED_PLAINTEXT_SECRET"
      : "BLOCKED";
  const secret = (env.DOSA_WEBHOOK_SECRET ?? "").trim();
  return { strategy, secret: secret.length > 0 ? secret : null };
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
