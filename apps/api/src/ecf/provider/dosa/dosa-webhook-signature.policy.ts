import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Verificación de `X-Dosa-Signature`.
 *
 * **Contrato confirmado oficialmente por DOSA** (2026-11-02):
 *
 * * Cabecera `X-Dosa-Signature`.
 * * Formato `t=<hora>,v1=<firma>`.
 * * `firma = HMAC-SHA256(webhookSecret, t + "." + rawRequestBody)`.
 *
 * Lo que el proveedor **no** confirmó, y que este archivo YA NO deja abierto:
 *
 * * La **unidad de `t`** (segundos epoch vs milisegundos epoch). Ver §P1: se
 *   resuelve por **magnitud**, que es aritmética y no una suposición.
 * * La **codificación del digest** (hex vs base64). Se aceptan ambas: exigir el
 *   HMAC correcto del cuerpo exacto no se debilita por admitir dos formas de
 *   escribir el mismo resultado.
 * * La **interpretación del secreto** (texto literal vs 32 bytes de hex). Ver
 *   §P5: se aceptan las dos lecturas ACOTADAS del mismo secreto.
 * * Que `t` sea epoch Unix en absoluto.
 *
 * Las dudas que siguen vivas viajan en `DOSA_WEBHOOK_PENDING_QUESTIONS`.
 *
 * Estrategias:
 *
 * * `BLOCKED` (por defecto) — ningún evento se considera auténtico.
 * * `HMAC_SHA256_TIMESTAMPED` — la estrategia real del contrato confirmado.
 * * `UNVERIFIED_PLAINTEXT_SECRET` — solo laboratorio local, para poder ejercitar
 *   el pipeline sin calcular un HMAC. Sigue degradando a `BLOCKED` fuera de
 *   laboratorio y hay una barrera de arranque independiente.
 */

export type DosaSignatureStrategyId =
  | "BLOCKED"
  | "UNVERIFIED_PLAINTEXT_SECRET"
  | "HMAC_SHA256_TIMESTAMPED";

export type DosaSignatureRejection =
  | "SIGNATURE_HEADER_MISSING"
  | "SIGNATURE_HEADER_MALFORMED"
  | "SIGNATURE_TIMESTAMP_INVALID"
  | "SIGNATURE_ALGORITHM_UNSUPPORTED"
  | "SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE"
  | "RAW_BODY_UNAVAILABLE"
  | "STRATEGY_BLOCKED"
  | "SECRET_NOT_CONFIGURED"
  | "SIGNATURE_MISMATCH"
  | "CONFIG_INVALID";

export type DosaSignatureResult =
  | { ok: true; strategy: DosaSignatureStrategyId }
  | { ok: false; strategy: DosaSignatureStrategyId; reason: DosaSignatureRejection };

/** Unidad del campo `t`. No confirmada por el proveedor. */
export type DosaTimestampUnit = "seconds" | "milliseconds";

/**
 * Ajuste de la unidad de `t`.
 *
 * `auto` (por defecto) **deduce** la unidad del propio valor, con aritmética:
 * un epoch en segundos del siglo XXI tiene 10 dígitos (~1.7e9) y uno en
 * milisegundos tiene 13 (~1.7e12). El umbral es 1e11, que en segundos sería el
 * año 5138 y en milisegundos 1973: no hay ninguna fecha plausible en el medio.
 *
 * Esto **no debilita la protección anti-replay**: si el valor es ambiguo, está
 * a miles de años de «ahora» y la ventana de 300 s lo rechaza igual. La unidad
 * solo decide qué motivo de rechazo se informa, nunca si un evento caducado se
 * acepta.
 */
export type DosaTimestampUnitSetting = DosaTimestampUnit | "auto";

/**
 * Cómo se interpreta el secreto del webhook. **No confirmado.**
 *
 * El secreto entregado tiene 64 caracteres hexadecimales. Eso admite dos
 * lecturas incompatibles entre sí:
 *
 * * `utf8` — los 64 caracteres son el secreto tal cual (64 bytes) y se usan
 *   literalmente como clave HMAC. Es el valor por defecto porque es la lectura
 *   que no transforma nada.
 * * `hex` — los 64 caracteres codifican 32 bytes binarios que son la clave.
 *
 * Elegir mal hace que TODA firma del proveedor se rechace. El fallo es seguro
 * (cerrado), pero silencioso en cuanto a la causa: por eso queda configurable y
 * declarado como pendiente en `DOSA_WEBHOOK_PENDING_QUESTIONS`.
 */
export type DosaSecretEncoding = "utf8" | "hex";

/**
 * Ajuste de la interpretación del secreto.
 *
 * `auto` (por defecto) acepta **las dos lecturas acotadas** de un secreto hex:
 * los caracteres tal cual (utf8) o los 32 bytes que codifican (hex). Son dos
 * interpretaciones fijas del MISMO secreto, no una prueba a ciegas de variantes:
 * la firma sigue teniendo que ser el HMAC correcto del cuerpo exacto.
 *
 * La seguridad no se reduce: el atacante necesita el mismo secreto en cualquier
 * caso, y el conjunto de claves aceptadas se deriva determinísticamente de él.
 * Es la misma tolerancia que ya se aplica al digest (hex o base64).
 */
export type DosaSecretEncodingSetting = DosaSecretEncoding | "auto";

export type DosaSignatureConfig = {
  strategy: DosaSignatureStrategyId;
  /** Secreto del webhook. Nunca se registra ni se devuelve. */
  secret: string | null;
  /**
   * Unidad de `t`. `auto` por defecto: se deduce por magnitud.
   * Opcional para no romper dobles de prueba: `readDosaSignatureConfig`
   * siempre la rellena.
   */
  timestampUnit?: DosaTimestampUnitSetting;
  /** Ventana anti-replay, en segundos. Por defecto 300. */
  toleranceSeconds?: number;
  /** Cómo se interpretan los caracteres del secreto. `auto` por defecto. */
  secretEncoding?: DosaSecretEncodingSetting;
  /** Motivo por el que la estrategia pedida no se aplicó, si aplica. */
  downgradedFrom?: DosaSignatureStrategyId;
  downgradeReason?: "NOT_A_LOCAL_LAB_ENVIRONMENT";
};

/**
 * Datos que dependen del proveedor.
 *
 * P1 y P5 **ya no son bloqueantes**: el receptor resuelve la unidad de `t` por
 * magnitud y acepta las dos lecturas acotadas de un secreto hex. Lo que sigue
 * aquí es lo que aún no tiene respuesta y sí puede afectar la operación.
 */
export const DOSA_WEBHOOK_PENDING_QUESTIONS = [
  "¿`t` son segundos o milisegundos? RESUELTO por magnitud; falta la confirmación escrita del proveedor",
  "¿El digest de `v1` va en hex o en base64? (se aceptan ambos)",
  "¿`t` es realmente epoch Unix, o el timestamp de su reloj interno?",
  "¿Hay rotación de secreto? Si la hay, ¿se envían varios `v1` en la cabecera?",
  "¿El secreto de 64 caracteres hex es TEXTO LITERAL o 32 bytes decodificados? RESUELTO: se aceptan las dos lecturas acotadas",
] as const;

export const DOSA_SIGNATURE_HEADER = "x-dosa-signature";

/** Ventana anti-replay por defecto: 5 minutos. */
export const DOSA_DEFAULT_TOLERANCE_SECONDS = 300;

/** Entornos de aplicación donde el laboratorio local es legítimo. */
export const DOSA_LAB_APP_ENVS: readonly string[] = [
  "local",
  "local-boot",
  "lab",
  "test",
  "e2e",
];

export type DosaSafetyEnv = NodeJS.ProcessEnv & {
  DOSA_WEBHOOK_SIGNATURE_STRATEGY?: string;
  DOSA_WEBHOOK_SECRET?: string;
  DOSA_WEBHOOK_SECRET_ENCODING?: string;
  DOSA_WEBHOOK_TIMESTAMP_UNIT?: string;
  DOSA_WEBHOOK_TOLERANCE_SECONDS?: string;
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
 * Configuración desde entorno. Sin estrategia válida, queda bloqueado.
 *
 * `HMAC_SHA256_TIMESTAMPED` se acepta en cualquier entorno porque es
 * verificable. `UNVERIFIED_PLAINTEXT_SECRET` solo en laboratorio local.
 */
export function readDosaSignatureConfig(env: DosaSafetyEnv): DosaSignatureConfig {
  const raw = (env.DOSA_WEBHOOK_SIGNATURE_STRATEGY ?? "").trim().toUpperCase();
  const secret = (env.DOSA_WEBHOOK_SECRET ?? "").trim();
  const secretValue = secret.length > 0 ? secret : null;
  const timestampUnit = parseTimestampUnit(env.DOSA_WEBHOOK_TIMESTAMP_UNIT);
  const toleranceSeconds = parseTolerance(env.DOSA_WEBHOOK_TOLERANCE_SECONDS);
  const secretEncoding = parseSecretEncoding(env.DOSA_WEBHOOK_SECRET_ENCODING);

  if (raw === "HMAC_SHA256_TIMESTAMPED") {
    return {
      strategy: "HMAC_SHA256_TIMESTAMPED",
      secret: secretValue,
      secretEncoding,
      timestampUnit,
      toleranceSeconds,
    };
  }

  if (raw !== "UNVERIFIED_PLAINTEXT_SECRET") {
    return {
      strategy: "BLOCKED",
      secret: secretValue,
      secretEncoding,
      timestampUnit,
      toleranceSeconds,
    };
  }

  if (!isLocalLabEnvironment(env)) {
    return {
      strategy: "BLOCKED",
      secret: secretValue,
      secretEncoding,
      timestampUnit,
      toleranceSeconds,
      downgradedFrom: "UNVERIFIED_PLAINTEXT_SECRET",
      downgradeReason: "NOT_A_LOCAL_LAB_ENVIRONMENT",
    };
  }

  return {
    strategy: "UNVERIFIED_PLAINTEXT_SECRET",
    secret: secretValue,
    secretEncoding,
    timestampUnit,
    toleranceSeconds,
  };
}

/**
 * Lectura de la codificación del secreto.
 *
 * `auto` por defecto: se prueban las dos lecturas cuando el secreto es hex.
 * Un valor no reconocido cae a `auto`, nunca a una lectura forzada.
 */
function parseSecretEncoding(
  value: string | undefined,
): DosaSecretEncodingSetting {
  const raw = (value ?? "").trim().toLowerCase();
  if (raw === "hex") return "hex";
  if (raw === "utf8") return "utf8";
  return "auto";
}

type KeyCandidate = { encoding: DosaSecretEncoding; key: Buffer };

/**
 * Claves HMAC candidatas para el secreto configurado.
 *
 * `utf8` y `hex` fuerzan una sola lectura. `auto` devuelve las dos **solo si el
 * secreto es hex de longitud par**: fuera de ese caso `hex` no es una lectura
 * posible y fingirla sería inventar.
 *
 * Devolver `null` significa «la configuración es imposible» (se pidió `hex` y el
 * secreto no lo es). No se cae a `utf8` en silencio: reinterpretar el secreto
 * cambiaria el resultado de la verificación sin que nadie se entere.
 */
function keyCandidates(
  secret: string,
  encoding: DosaSecretEncodingSetting,
): KeyCandidate[] | null {
  const isEvenHex = /^[0-9A-Fa-f]+$/.test(secret) && secret.length % 2 === 0;
  if (encoding === "hex") {
    if (!isEvenHex) return null;
    return [{ encoding: "hex", key: Buffer.from(secret, "hex") }];
  }
  if (encoding === "utf8") {
    return [{ encoding: "utf8", key: Buffer.from(secret, "utf8") }];
  }
  const candidates: KeyCandidate[] = [
    { encoding: "utf8", key: Buffer.from(secret, "utf8") },
  ];
  if (isEvenHex) {
    candidates.push({ encoding: "hex", key: Buffer.from(secret, "hex") });
  }
  return candidates;
}

/**
 * Unidad de `t` efectiva.
 *
 * Con un ajuste explicito se respeta. Con `auto` se deduce del orden de
 * magnitud: `>= 1e11` no puede ser un epoch en segundos de este siglo, asi que
 * se interpreta como milisegundos. Ver `DosaTimestampUnitSetting`.
 */
export function resolveTimestampUnit(
  timestampRaw: string,
  setting: DosaTimestampUnitSetting,
): DosaTimestampUnit {
  if (setting !== "auto") return setting;
  const value = Number.parseInt(`${timestampRaw}`.trim(), 10);
  if (!Number.isFinite(value)) return "seconds";
  return value >= 100_000_000_000 ? "milliseconds" : "seconds";
}

function parseTimestampUnit(
  value: string | undefined,
): DosaTimestampUnitSetting {
  const raw = (value ?? "").trim().toLowerCase();
  if (raw === "milliseconds" || raw === "ms") return "milliseconds";
  if (raw === "seconds" || raw === "s") return "seconds";
  // `auto` por defecto: deducir por magnitud en vez de suponer.
  return "auto";
}

function parseTolerance(value: string | undefined): number {
  const raw = (value ?? "").trim();
  if (raw.length === 0) return DOSA_DEFAULT_TOLERANCE_SECONDS;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DOSA_DEFAULT_TOLERANCE_SECONDS;
  }
  // Techo defensivo: una tolerancia enorme anularía la protección anti-replay.
  return Math.min(parsed, 86_400);
}

/** Interpretación que efectivamente validó la firma. Es evidencia, no un secreto. */
export type DosaResolvedInterpretation = {
  timestampUnit: DosaTimestampUnit;
  secretEncoding: DosaSecretEncoding;
};

export function verifyDosaSignature(input: {
  headers: Record<string, string | string[] | undefined>;
  config: DosaSignatureConfig;
  /** Bytes EXACTOS recibidos. Obligatorio para HMAC. */
  rawBody?: Buffer;
  /** Inyectable para pruebas deterministas. */
  nowMs?: number;
  /**
   * Se invoca SOLO cuando la firma es válida, con la interpretación que la
   * validó. Sirve para poder responder «¿segundos o milisegundos?» y «¿texto o
   * hex?» con un hecho en vez de con una suposición, sin registrar secretos.
   */
  onResolved?: (info: DosaResolvedInterpretation) => void;
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

  if (config.strategy === "UNVERIFIED_PLAINTEXT_SECRET") {
    return constantTimeEquals(
      Buffer.from(provided, "utf8"),
      Buffer.from(config.secret, "utf8"),
    )
      ? { ok: true, strategy: config.strategy }
      : {
          ok: false,
          strategy: config.strategy,
          reason: "SIGNATURE_MISMATCH",
        };
  }

  return verifyHmacTimestamped({
    header: provided,
    secret: config.secret,
    secretEncoding: config.secretEncoding ?? "auto",
    rawBody: input.rawBody,
    timestampUnit: config.timestampUnit ?? "auto",
    toleranceSeconds: config.toleranceSeconds ?? DOSA_DEFAULT_TOLERANCE_SECONDS,
    nowMs: input.nowMs ?? Date.now(),
    onResolved: input.onResolved,
  });
}

/**
 * Núcleo del contrato confirmado: `HMAC-SHA256(secret, t + "." + rawBody)`.
 *
 * Se firma sobre los BYTES EXACTOS del cuerpo. Nunca se re-serializa el JSON:
 * reordenar claves o normalizar espacios cambiaría el digest y convertiría
 * eventos legítimos en «firma inválida».
 */
function verifyHmacTimestamped(input: {
  header: string;
  secret: string;
  secretEncoding: DosaSecretEncodingSetting;
  rawBody: Buffer | undefined;
  timestampUnit: DosaTimestampUnitSetting;
  toleranceSeconds: number;
  nowMs: number;
  onResolved?: (info: DosaResolvedInterpretation) => void;
}): DosaSignatureResult {
  const strategy: DosaSignatureStrategyId = "HMAC_SHA256_TIMESTAMPED";
  const fail = (reason: DosaSignatureRejection): DosaSignatureResult => ({
    ok: false,
    strategy,
    reason,
  });

  if (!input.rawBody || input.rawBody.length === 0) {
    // Sin los bytes originales no se puede verificar: se rechaza, no se adivina.
    return fail("RAW_BODY_UNAVAILABLE");
  }

  const parsed = parseSignatureHeader(input.header);
  if (!parsed.ok) return fail(parsed.reason);

  const { timestampRaw, signature } = parsed;

  const candidates = keyCandidates(input.secret, input.secretEncoding);
  if (candidates === null) {
    // Un secreto que dice ser hex y no lo es: no se reinterpreta en silencio.
    return fail("CONFIG_INVALID");
  }

  // Digest del mensaje firmado: `t` TAL CUAL llegó, un punto, y el cuerpo.
  // Se prueban las interpretaciones ACOTADAS del mismo secreto (una, o dos con
  // `auto`). No es una búsqueda de variantes hasta que alguna funcione: la
  // firma tiene que ser el HMAC exacto del cuerpo exacto con la clave correcta.
  let matched: KeyCandidate | null = null;
  for (const candidate of candidates) {
    const expected = createHmac("sha256", candidate.key)
      .update(`${timestampRaw}.`, "utf8")
      .update(input.rawBody)
      .digest();
    // Se compara en tiempo constante contra las codificaciones admitidas.
    if (matchesAnyEncoding(expected, signature)) {
      matched = candidate;
      break;
    }
  }
  if (matched === null) {
    return fail("SIGNATURE_MISMATCH");
  }

  // Anti-replay: solo se evalúa DESPUÉS de autenticar, para no revelar el
  // comportamiento de la ventana a quien no tiene el secreto.
  const unit = resolveTimestampUnit(timestampRaw, input.timestampUnit);
  const stampMs = toEpochMs(timestampRaw, unit);
  if (stampMs === null) return fail("SIGNATURE_TIMESTAMP_INVALID");
  const toleranceMs = input.toleranceSeconds * 1000;
  if (Math.abs(input.nowMs - stampMs) > toleranceMs) {
    return fail("SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE");
  }

  // Evidencia: qué interpretación validó la firma. No es un secreto.
  input.onResolved?.({
    timestampUnit: unit,
    secretEncoding: matched.encoding,
  });
  return { ok: true, strategy };
}

/**
 * Parseo ESTRICTO de `t=<hora>,v1=<firma>`.
 *
 * Se rechaza en vez de tolerar: claves desconocidas, `t` o `v1` duplicados,
 * partes sin `=` y valores vacíos. Un `v1` duplicado es ambiguo (podría ser
 * rotación de secreto, algo no confirmado) y elegir uno «a ojo» sería inventar.
 */
export function parseSignatureHeader(
  header: string,
):
  | { ok: true; timestampRaw: string; signature: string }
  | { ok: false; reason: DosaSignatureRejection } {
  const parts = header.split(",");
  let timestampRaw: string | null = null;
  let signature: string | null = null;

  for (const part of parts) {
    const trimmed = part.trim();
    if (trimmed.length === 0) {
      return { ok: false, reason: "SIGNATURE_HEADER_MALFORMED" };
    }
    const separator = trimmed.indexOf("=");
    if (separator <= 0) {
      return { ok: false, reason: "SIGNATURE_HEADER_MALFORMED" };
    }
    const key = trimmed.slice(0, separator).trim().toLowerCase();
    const value = trimmed.slice(separator + 1).trim();
    if (value.length === 0) {
      return { ok: false, reason: "SIGNATURE_HEADER_MALFORMED" };
    }
    if (key === "t") {
      if (timestampRaw !== null) {
        return { ok: false, reason: "SIGNATURE_HEADER_MALFORMED" };
      }
      timestampRaw = value;
      continue;
    }
    if (key === "v1") {
      if (signature !== null) {
        return { ok: false, reason: "SIGNATURE_HEADER_MALFORMED" };
      }
      signature = value;
      continue;
    }
    // Otro esquema (`v0`, `v2`…) no está confirmado: no se acepta ni se ignora.
    return { ok: false, reason: "SIGNATURE_ALGORITHM_UNSUPPORTED" };
  }

  if (timestampRaw === null || signature === null) {
    return { ok: false, reason: "SIGNATURE_HEADER_MALFORMED" };
  }
  if (!/^[0-9]{1,20}$/.test(timestampRaw)) {
    return { ok: false, reason: "SIGNATURE_TIMESTAMP_INVALID" };
  }
  if (!/^[A-Za-z0-9+/=_-]{16,128}$/.test(signature)) {
    return { ok: false, reason: "SIGNATURE_HEADER_MALFORMED" };
  }
  return { ok: true, timestampRaw, signature };
}

/** Convierte `t` a milisegundos según la unidad configurada. */
function toEpochMs(raw: string, unit: DosaTimestampUnit): number | null {
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value <= 0) return null;
  return unit === "milliseconds" ? value : value * 1000;
}

/**
 * Compara el digest esperado contra el recibido, admitiendo hex o base64.
 *
 * No se corta en el primer acierto ni en el primer fallo: se acumulan los
 * resultados para que el tiempo no dependa de qué codificación llegó.
 */
function matchesAnyEncoding(expected: Buffer, candidate: string): boolean {
  const decoded: Buffer[] = [];

  const hex = decodeHex(candidate);
  if (hex) decoded.push(hex);
  const b64 = decodeBase64(candidate);
  if (b64) decoded.push(b64);

  let matched = false;
  for (const value of decoded) {
    matched = constantTimeEquals(value, expected) || matched;
  }
  return matched;
}

function decodeHex(value: string): Buffer | null {
  if (!/^[0-9A-Fa-f]+$/.test(value) || value.length % 2 !== 0) return null;
  try {
    return Buffer.from(value, "hex");
  } catch {
    return null;
  }
}

function decodeBase64(value: string): Buffer | null {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized)) return null;
  try {
    return Buffer.from(normalized, "base64");
  } catch {
    return null;
  }
}

/** Comparación en tiempo constante. Distinto tamaño ⇒ falso, sin lanzar. */
function constantTimeEquals(a: Buffer, b: Buffer): boolean {
  if (a.length !== b.length || a.length === 0) return false;
  return timingSafeEqual(a, b);
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
