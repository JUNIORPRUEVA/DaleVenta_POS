import { DOSA_AUTH_HEADER } from "./dosa-ecf.contract";

/**
 * Invariante de AUTENTICACIÓN SALIENTE de DOSA.
 *
 * El error que este módulo impide
 * -----------------------------
 * Es fácil suponer que el secreto del webhook entrante y la credencial de las
 * llamadas salientes son lo mismo, porque ambos "autentican" con DOSA. **No lo
 * son**:
 *
 * | Dirección | Mecanismo | De dónde sale |
 * | --- | --- | --- |
 * | Webhook ENTRANTE | `X-Dosa-Signature: t=…,v1=HMAC(secreto, "t." . cuerpo)` | `DOSA_WEBHOOK_SECRET` (o el `api_secret` del evento) |
 * | Llamada SALIENTE | Cabecera de API Key de **la empresa y el ambiente** | `ecf_dosa_company_credentials` cifrado |
 *
 * Por eso una petición saliente lleva **exactamente** dos cabeceras:
 * `Content-Type` y la de API Key. Si alguien añade la cabecera de firma, o
 * cualquier otra, la petición se bloquea antes de la red: preferimos un bloqueo
 * visible a enviar un comprobante con una credencial que no corresponde.
 *
 * También se rechaza una "firma" enviada como si fuera la API Key: un secreto de
 * webhook no autoriza emisión.
 */

/** Cabeceras admitidas en una petición de emisión. Comparadas en minúsculas. */
export const DOSA_OUTBOUND_ALLOWED_HEADERS: readonly string[] = [
  "content-type",
  DOSA_AUTH_HEADER.toLowerCase(),
];

export const DOSA_OUTBOUND_BLOCKED = {
  signatureHeader: "DOSA_OUTBOUND_SIGNATURE_HEADER_FORBIDDEN",
  unexpectedHeader: "DOSA_OUTBOUND_UNEXPECTED_HEADER",
  apiKeyMissing: "DOSA_OUTBOUND_API_KEY_MISSING",
  apiKeyLooksLikeSignature: "DOSA_OUTBOUND_API_KEY_LOOKS_LIKE_SIGNATURE",
} as const;

/**
 * Devuelve el motivo del bloqueo, o `null` si la petición es admisible.
 *
 * Función pura: no lee entorno, no toca red.
 */
export function outboundAuthViolation(
  headers: Record<string, string>,
  options: { apiKey?: string } = {},
): string | null {
  const entries = Object.entries(headers);
  const lowerKeys = entries.map(([key]) => key.toLowerCase());

  for (const [key] of entries) {
    const lower = key.toLowerCase();
    // Cabecera de firma del webhook: pertenece a la dirección contraria.
    if (lower.includes("signature") || lower === "x-dosa-signature") {
      return `${DOSA_OUTBOUND_BLOCKED.signatureHeader}:${key}`;
    }
    if (!DOSA_OUTBOUND_ALLOWED_HEADERS.includes(lower)) {
      return `${DOSA_OUTBOUND_BLOCKED.unexpectedHeader}:${key}`;
    }
  }

  if (!lowerKeys.includes(DOSA_AUTH_HEADER.toLowerCase())) {
    return DOSA_OUTBOUND_BLOCKED.apiKeyMissing;
  }

  // Una firma de webhook tiene la forma `t=<epoch>,v1=<hex|base64>`. Si eso
  // viajara como API Key, el proveedor rechazaría la emisión, pero además
  // significaría que alguien confundió los dos secretos: se corta aquí.
  const apiKey = (options.apiKey ?? "").trim();
  if (/^t=\d+,v1=/.test(apiKey)) {
    return DOSA_OUTBOUND_BLOCKED.apiKeyLooksLikeSignature;
  }

  return null;
}
