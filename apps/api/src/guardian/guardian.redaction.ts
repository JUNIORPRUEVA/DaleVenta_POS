/**
 * Sanitización de evidencias antes de persistirlas.
 *
 * Regla: Guardian nunca debe almacenar contraseñas, tokens, credenciales,
 * datos fiscales sensibles ni datos personales innecesarios. Se aplica dos
 * veces: en el cliente y aquí (el servidor no confía en el cliente).
 */

const SENSITIVE_KEY_PATTERN =
  /(pass(word|wd)?|token|secret|authorization|cookie|api[-_]?key|apikey|jwt|refresh|session|credit[-_]?card|card[-_]?number|cvv|cvc|pin|cedula|c[eé]dula|rnc|nif|tax[-_]?id|email|correo|phone|telefono|tel[eé]fono|whatsapp|address|direccion|direcci[oó]n|nombre[-_]?cliente|customer[-_]?name)/i;

const EMAIL_PATTERN = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const BEARER_PATTERN = /\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}/gi;
const JWT_PATTERN = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\b/g;
const LONG_DIGITS_PATTERN = /\b\d{8,}\b/g;
const WINDOWS_PATH_PATTERN = /[A-Za-z]:\\[^\s"')]+/g;
const UNIX_PATH_PATTERN = /\/(?:Users|home|var|opt|srv)\/[^\s"')]+/g;

/**
 * Credenciales embebidas en texto libre: `password=...`, `clave: ...`,
 * `token=...`. Un mensaje de error de un ORM suele incluir la sentencia o los
 * parámetros, y ese es exactamente el caso que no puede llegar a Guardian.
 */
const INLINE_SECRET_PATTERN =
  /\b(password|passwd|pwd|clave|contrasena|contraseña|secret|secreto|token|api[-_]?key|apikey|authorization)\b(\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;&"'}\])]{2,})/gi;

export const REDACTED = '[redacted]';

/** Redacta un texto libre (mensajes de error, stack, descripciones). */
export function redactText(input: unknown, maxChars = 20_000): string {
  const text = typeof input === 'string' ? input : String(input ?? '');
  if (!text) return '';

  return text
    .replace(INLINE_SECRET_PATTERN, (_match, name: string) => `${name}=${REDACTED}`)
    .replace(WINDOWS_PATH_PATTERN, '<ruta>')
    .replace(UNIX_PATH_PATTERN, '<ruta>')
    .replace(JWT_PATTERN, '[token]')
    .replace(BEARER_PATTERN, '[credencial]')
    .replace(EMAIL_PATTERN, '[email]')
    .replace(LONG_DIGITS_PATTERN, '[numero]')
    .slice(0, maxChars);
}

/**
 * Redacta recursivamente un objeto de contexto.
 * - Claves sensibles → `[redacted]` (no se conserva el valor).
 * - Profundidad máxima 3, máximo 40 claves por objeto, máximo 500 caracteres por string.
 */
export function redactContext(value: unknown, depth = 0): unknown {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return redactText(value, 500);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value === 'bigint') return Number(value);
  if (Array.isArray(value)) {
    if (depth >= 3) return [];
    return value.slice(0, 20).map((item) => redactContext(item, depth + 1));
  }
  if (typeof value === 'object') {
    if (depth >= 3) return {};
    const out: Record<string, unknown> = {};
    for (const [key, raw] of Object.entries(value as Record<string, unknown>).slice(0, 40)) {
      const safeKey = String(key).trim().slice(0, 80);
      if (!safeKey) continue;
      out[safeKey] = SENSITIVE_KEY_PATTERN.test(safeKey)
        ? REDACTED
        : redactContext(raw, depth + 1);
    }
    return out;
  }
  return null;
}

/** Cabeceras HTTP permitidas como evidencia (nunca cookies ni auth). */
export function sanitizeHeaders(headers: Record<string, unknown> | undefined): Record<string, unknown> {
  const allowed = ['user-agent', 'content-type', 'accept-language', 'x-client-platform', 'x-client-app-version'];
  const out: Record<string, unknown> = {};
  const source = headers ?? {};
  for (const name of allowed) {
    const raw = source[name];
    if (typeof raw === 'string' && raw.trim()) out[name] = redactText(raw, 200);
  }
  return out;
}

/** Devuelve true si el objeto serializado contiene credenciales o PII evidente. */
export function containsSensitiveData(serialized: string): boolean {
  if (!serialized) return false;
  return (
    JWT_PATTERN.test(serialized) ||
    /"?(password|passwd|token|authorization|apiKey|api_key|secret)"?\s*[:=]\s*"[^"]{6,}"/i.test(serialized) ||
    EMAIL_PATTERN.test(serialized) ||
    BEARER_PATTERN.test(serialized)
  );
}
