/**
 * Esquema del evento de webhook de DOSA.
 *
 * Basado en la muestra REAL entregada por el proveedor
 * (`03_WEBHOOK_EJEMPLO_SANITIZADO.json`):
 *
 * ```json
 * {
 *   "postulacion_id": "…", "rnc": "…", "razon_social": "…", "correo": "…",
 *   "ambiente": "Produccion", "estado_certificacion": "finalizado",
 *   "credenciales": { "api_key_produccion": "…", "api_key_test": "…",
 *                     "api_secret": "…" },
 *   "credenciales_pendientes": false,
 *   "disponibles_desde": "2026-11-01T22:50:12Z"
 * }
 * ```
 *
 * Reglas de este validador:
 *
 * 1. **Estructura estricta** en lo que identifica el evento: `rnc` y
 *    `razon_social` son obligatorios. Un payload sin identidad no se "arregla"
 *    con valores por defecto.
 * 2. **Los campos que el proveedor manda en `null` se aceptan como `null`.**
 *    DOSA lo pidió el 06/11/2026: en el primer evento de conexión
 *    (`empresa.conectada`) y en el de prueba de firma (`webhook.prueba`)
 *    todavía no existe proceso de certificación, así que `postulacion_id` y
 *    `estado_certificacion` llegan en `null`, y solo los eventos de llaves
 *    traen `disponibles_desde`.
 *
 *    La distinción es deliberada: **ausente/null se acepta; presente con el
 *    tipo equivocado se rechaza.** Un `postulacion_id` numérico o un
 *    `disponibles_desde` que no es fecha siguen siendo un error.
 *
 *    Aceptarlos no autoriza nada: ninguno de estos campos decide identidad,
 *    empresa ni activación.
 * 3. **NUNCA se copian las credenciales al resultado que se loguea o persiste.**
 *    Solo se devuelve qué credenciales vinieron (`present`) y su longitud no.
 *    El valor vive en un campo que el llamador tiene prohibido registrar.
 * 4. **El RNC del evento es una PISTA**, no la identidad: se valida contra la
 *    vinculación guardada en el servidor (`dosa-company-linking.policy.ts`).
 */

/** Credenciales tal como llegan. Nunca se registran ni se envían al cliente. */
export type DosaWebhookCredentials = {
  apiKeyProduccion?: string;
  apiKeyTest?: string;
  apiSecret?: string;
};

export type DosaWebhookPayload = {
  /**
   * `null` en los eventos que preceden a la postulación (`empresa.conectada`,
   * `webhook.prueba`). Nunca se usa para correlacionar: la empresa sale del RNC.
   */
  postulacionId: string | null;
  rnc: string;
  razonSocial: string;
  correo: string;
  /** `Produccion` / `Test` / etc. No se normaliza a un enum propio: el valor
   *  lo decide el proveedor y no lo usamos para autorizar nada. */
  ambiente: string;
  /** `null` mientras no exista proceso de certificación (ver cabecera). */
  estadoCertificacion: string | null;
  /** Presencia de cada credencial. Sin valores. */
  presente: {
    apiKeyProduccion: boolean;
    apiKeyTest: boolean;
    apiSecret: boolean;
  };
  /**
   * Ausente en los eventos que no son de llaves → `false`. Cuando viene, el
   * proveedor lo manda como booleano y se respeta su valor.
   */
  credencialesPendientes: boolean;
  /** `null` cuando el evento no es de llaves (solo esos traen la fecha). */
  disponiblesDesde: string | null;
};

export type DosaWebhookCredentialBundle = {
  payload: DosaWebhookPayload;
  /**
   * Valores sensibles. Uso EXCLUSIVO para escribirlos en el gestor de secretos.
   * PROHIBIDO: loguearlos, persistirlos en claro, devolverlos por HTTP.
   */
  secretos: DosaWebhookCredentials;
};

export type DosaWebhookParseResult =
  | { ok: true; value: DosaWebhookCredentialBundle }
  | { ok: false; reason: string; field?: string };

const MAX_FIELD = 256;

/** Valida el payload del evento. Fallo cerrado ante cualquier desviación. */
export function parseDosaWebhookPayload(
  input: unknown,
): DosaWebhookParseResult {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return { ok: false, reason: "INVALID_BODY" };
  }
  const body = input as Record<string, unknown>;

  // Campos que el proveedor manda en `null` antes de que exista postulación.
  const postulacionId = nullableText(body.postulacion_id);
  if (!postulacionId.ok) {
    return { ok: false, reason: "INVALID_FIELD", field: "postulacion_id" };
  }

  const rnc = text(body.rnc);
  if (!rnc || normalizeRnc(rnc) === null) {
    return { ok: false, reason: "MISSING_FIELD", field: "rnc" };
  }

  const razonSocial = text(body.razon_social);
  if (!razonSocial) {
    return { ok: false, reason: "MISSING_FIELD", field: "razon_social" };
  }

  const estadoCertificacion = nullableText(body.estado_certificacion);
  if (!estadoCertificacion.ok) {
    return {
      ok: false,
      reason: "INVALID_FIELD",
      field: "estado_certificacion",
    };
  }

  // Solo los eventos de llaves traen la fecha; en el resto no es un error.
  const disponiblesDesde = nullableText(body.disponibles_desde);
  if (
    !disponiblesDesde.ok ||
    (disponiblesDesde.value !== null &&
      Number.isNaN(Date.parse(disponiblesDesde.value)))
  ) {
    return { ok: false, reason: "INVALID_FIELD", field: "disponibles_desde" };
  }

  // Un booleano ausente significa "no hay credenciales pendientes"; un valor de
  // otro tipo sigue siendo un payload mal formado.
  const credencialesPendientes = body.credenciales_pendientes;
  if (
    credencialesPendientes !== undefined &&
    typeof credencialesPendientes !== "boolean"
  ) {
    return {
      ok: false,
      reason: "INVALID_FIELD",
      field: "credenciales_pendientes",
    };
  }

  const credenciales = body.credenciales;
  if (
    credenciales !== undefined &&
    (credenciales === null ||
      typeof credenciales !== "object" ||
      Array.isArray(credenciales))
  ) {
    return { ok: false, reason: "INVALID_FIELD", field: "credenciales" };
  }
  const cr = (credenciales ?? {}) as Record<string, unknown>;
  const secretos: DosaWebhookCredentials = {
    ...(text(cr.api_key_produccion)
      ? { apiKeyProduccion: text(cr.api_key_produccion)! }
      : {}),
    ...(text(cr.api_key_test) ? { apiKeyTest: text(cr.api_key_test)! } : {}),
    ...(text(cr.api_secret) ? { apiSecret: text(cr.api_secret)! } : {}),
  };

  const payload: DosaWebhookPayload = {
    postulacionId: postulacionId.value,
    rnc,
    razonSocial,
    correo: text(body.correo) ?? "",
    ambiente: text(body.ambiente) ?? "",
    estadoCertificacion: estadoCertificacion.value,
    presente: {
      apiKeyProduccion: secretos.apiKeyProduccion !== undefined,
      apiKeyTest: secretos.apiKeyTest !== undefined,
      apiSecret: secretos.apiSecret !== undefined,
    },
    credencialesPendientes: credencialesPendientes === true,
    disponiblesDesde: disponiblesDesde.value,
  };

  return { ok: true, value: { payload, secretos } };
}

/**
 * Representación SEGURA del evento: lo único que se puede persistir o loguear.
 * Sustituye cualquier credencial por un marcador.
 */
export function redactDosaWebhookEvent(payload: DosaWebhookPayload) {
  return {
    postulacionId: payload.postulacionId,
    rnc: payload.rnc,
    razonSocial: payload.razonSocial,
    correo: payload.correo,
    ambiente: payload.ambiente,
    estadoCertificacion: payload.estadoCertificacion,
    credenciales: {
      apiKeyProduccion: payload.presente.apiKeyProduccion ? "[REDACTED]" : null,
      apiKeyTest: payload.presente.apiKeyTest ? "[REDACTED]" : null,
      apiSecret: payload.presente.apiSecret ? "[REDACTED]" : null,
    },
    credencialesPendientes: payload.credencialesPendientes,
    disponiblesDesde: payload.disponiblesDesde,
  };
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_FIELD) return null;
  return trimmed;
}

/**
 * Campo que puede venir ausente o en `null` sin invalidar el evento.
 *
 * Distingue **ausente** de **mal formado**, que es la única forma de aceptar
 * `null` sin abrir la puerta a cualquier cosa:
 *
 * * `undefined`, `null` o cadena vacía → `{ ok: true, value: null }`
 * * cadena con contenido → `{ ok: true, value }`
 * * cualquier otro tipo (número, objeto, booleano) → `{ ok: false }`
 */
function nullableText(
  value: unknown,
): { ok: true; value: string | null } | { ok: false } {
  if (value === undefined || value === null) return { ok: true, value: null };
  if (typeof value !== "string") return { ok: false };
  const trimmed = value.trim();
  if (trimmed.length === 0) return { ok: true, value: null };
  if (trimmed.length > MAX_FIELD) return { ok: false };
  return { ok: true, value: trimmed };
}

function normalizeRnc(value: string): string | null {
  const cleaned = value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
  if (cleaned.length < 8 || cleaned.length > 11) return null;
  return cleaned;
}
