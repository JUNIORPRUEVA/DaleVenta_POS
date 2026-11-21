/**
 * Saneado de URLs para el log de peticiones.
 *
 * Motivo: el webhook de WhatsApp Cloud API recibe el `hub.verify_token` en la
 * query string durante la verificación GET de Meta. Loguear `req.originalUrl`
 * en crudo escribe ese token (secreto) en los logs del contenedor.
 *
 * Regla: la ruta se conserva íntegra (útil para depurar) y solo se enmascaran
 * los VALORES de los parámetros sensibles.
 */

const SENSITIVE_PARAMS = new Set([
  'verify_token',
  'hub.verify_token',
  'token',
  'handoff',
  'ticket',
  'reset_token',
  'id_token',
  'access_token',
  'refresh_token',
  'api_key',
  'apikey',
  'secret',
  'client_secret',
  'password',
  'signature',
  'sig',
  'authorization',
]);

const REDACTED = '***';

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/g, ' '));
  } catch {
    return value;
  }
}

/**
 * Devuelve la URL con los valores de parámetros sensibles enmascarados.
 * Sin query string devuelve la URL original sin cambios.
 */
export function sanitizeRequestUrl(rawUrl: string | undefined | null): string {
  const url = String(rawUrl ?? '');
  const queryStart = url.indexOf('?');
  if (queryStart === -1) return url;

  const base = url.slice(0, queryStart);
  const query = url.slice(queryStart + 1);
  if (!query) return base;

  const sanitized = query
    .split('&')
    .map((pair) => {
      if (!pair) return pair;
      const equals = pair.indexOf('=');
      if (equals === -1) {
        // Parámetro sin `=` (bandera): solo se enmascara si el nombre es sensible.
        return SENSITIVE_PARAMS.has(safeDecode(pair).toLowerCase()) ? `${pair}=${REDACTED}` : pair;
      }
      const key = pair.slice(0, equals);
      if (SENSITIVE_PARAMS.has(safeDecode(key).toLowerCase())) {
        return `${key}=${REDACTED}`;
      }
      return pair;
    })
    .join('&');

  return `${base}?${sanitized}`;
}
