/**
 * Redacción centralizada de secretos para logs, diagnósticos e informes.
 *
 * Regla de oro: ningún valor sensible debe alcanzar stdout, un log, un informe
 * de auditoría o la salida de una herramienta de diagnóstico sin pasar por aquí.
 *
 * Es deliberadamente conservadora (fail-closed): ante la duda, redacta.
 *
 * Cobertura exigida: `DATABASE_URL`, contraseñas, JWT, Bearer tokens, API keys,
 * secretos, credenciales embebidas en URLs y variables sensibles.
 *
 * Excepción explícita y acotada: una *referencia* de secreto
 * (`env://ALANUBE_SANDBOX_TOKEN`, `secret://windows/Nombre`, `vault://ruta`)
 * no contiene material secreto, por diseño. Solo se conserva cuando la clave
 * termina en `Ref`/`Reference` **y** el valor es realmente un URI de referencia.
 */

export const REDACTED = "«redactado»";

/**
 * Fragmentos que, presentes en la clave normalizada, fuerzan la redacción del
 * valor. La comparación se hace sobre la clave normalizada (sin guiones, guiones
 * bajos, puntos ni espacios, en minúsculas), de modo que `DATABASE_URL`,
 * `database-url` y `databaseUrl` se tratan igual.
 */
const SENSITIVE_KEY_PARTS: readonly string[] = [
  "password",
  "passwd",
  "pwd",
  "secret",
  "token",
  "apikey",
  "privatekey",
  "credential",
  "authorization",
  "bearer",
  "jwt",
  "cookie",
  "sessionid",
  "connectionstring",
  "dsn",
  "databaseurl",
];

/** Sufijos de clave que identifican una referencia en lugar de un valor. */
const REFERENCE_KEY_SUFFIXES: readonly string[] = ["ref", "reference"];

/**
 * Referencia de secreto: URI con esquema, sin credenciales embebidas
 * (`usuario:clave@`). Nunca contiene el material secreto.
 */
const SECRET_REFERENCE_PATTERN = /^[a-z][a-z0-9+.-]*:\/\/[^\s@]{1,500}$/i;

/** JWT: tres segmentos base64url separados por puntos, empezando por `eyJ`. */
const JWT_PATTERN = /\beyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*/g;
/** Cabecera `Authorization: Bearer <token>`. */
const BEARER_PATTERN = /\b(bearer)\s+[A-Za-z0-9._~+/=-]{8,}/gi;
/** `esquema://usuario:clave@host` → conserva usuario y host, oculta la clave. */
const URL_CREDENTIALS_PATTERN =
  /([a-z][a-z0-9+.-]*:\/\/)([^/\s:@]{1,128}):([^/\s@]{1,256})@/gi;
/** Par `clave=valor` / `clave: valor` con nombre sensible dentro de un texto. */
const INLINE_PAIR_PATTERN =
  /([A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|apikey|credential|jwt|database[_-]?url|dsn)[A-Za-z0-9_.-]*)(\s*[=:]\s*)("?)([^\s,;}"']+)\3/gi;

/** Normaliza una clave: sin separadores, en minúsculas. */
export function normalizeKey(key: string): string {
  return key.replace(/[\s._-]+/g, "").toLowerCase();
}

/** `true` si el valor de esta clave nunca debe mostrarse. */
export function isSensitiveKey(key: string): boolean {
  const normalized = normalizeKey(key);
  if (!normalized) return false;
  return SENSITIVE_KEY_PARTS.some((part) => normalized.includes(part));
}

function isReferenceKey(key: string): boolean {
  const normalized = normalizeKey(key);
  return REFERENCE_KEY_SUFFIXES.some((suffix) => normalized.endsWith(suffix));
}

/** `true` si el valor es una referencia de secreto (URI con esquema, sin `@`). */
export function looksLikeSecretReference(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;
  return SECRET_REFERENCE_PATTERN.test(trimmed);
}

/**
 * Oculta credenciales embebidas en URLs, JWT, Bearer tokens y pares
 * `clave=valor` sensibles dentro de un texto libre (una línea de log).
 */
export function redactText(text: string): string {
  if (!text) return text;
  return text
    .replace(URL_CREDENTIALS_PATTERN, `$1$2:${REDACTED}@`)
    .replace(JWT_PATTERN, REDACTED)
    .replace(BEARER_PATTERN, `$1 ${REDACTED}`)
    .replace(INLINE_PAIR_PATTERN, `$1$2$3${REDACTED}$3`);
}

/** Oculta la contraseña de una URL conservando esquema, usuario, host y ruta. */
export function redactUrl(rawUrl: string): string {
  if (!rawUrl) return rawUrl;
  return redactText(rawUrl);
}

function isSafeReference(key: string, value: unknown): boolean {
  return (
    isReferenceKey(key) &&
    typeof value === "string" &&
    looksLikeSecretReference(value)
  );
}

/**
 * Redacta un valor de forma recursiva. Las claves sensibles se sustituyen por
 * completo; el resto de cadenas pasan por `redactText` por si llevan
 * credenciales embebidas. Nunca muta la entrada.
 */
export function redactSecrets(value: unknown, key = ""): unknown {
  if (key && isSensitiveKey(key) && !isSafeReference(key, value)) {
    return REDACTED;
  }
  if (value === null || value === undefined) return value;
  if (typeof value === "string") return redactText(value);
  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    typeof value === "bigint"
  ) {
    return value;
  }
  if (value instanceof Date) return value;
  if (Array.isArray(value)) {
    return value.map((item) => redactSecrets(item, key));
  }
  if (typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [entryKey, entryValue] of Object.entries(
      value as Record<string, unknown>,
    )) {
      out[entryKey] = redactSecrets(entryValue, entryKey);
    }
    return out;
  }
  // Funciones, símbolos y demás valores no serializables nunca se muestran.
  return REDACTED;
}

/**
 * Redacta un entorno (`process.env` o equivalente) y devuelve un objeto plano
 * con las claves ordenadas para que el diagnóstico sea determinista.
 */
export function redactEnv(
  env: Record<string, unknown> | NodeJS.ProcessEnv,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(env).sort()) {
    out[key] = redactSecrets(env[key], key);
  }
  return out;
}

/**
 * Serializa un entorno ya redactado como líneas `CLAVE=valor`, listo para
 * imprimir en un diagnóstico.
 */
export function formatRedactedEnv(
  env: Record<string, unknown> | NodeJS.ProcessEnv,
): string {
  const redacted = redactEnv(env);
  return Object.entries(redacted)
    .map(([key, value]) => `${key}=${String(value)}`)
    .join("\n");
}
