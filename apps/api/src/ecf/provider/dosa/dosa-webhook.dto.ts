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
 * 1. **Estructura estricta**: si falta o sobra algo crítico, se rechaza. Un
 *    payload fuera de esquema no se "arregla" con valores por defecto.
 * 2. **NUNCA se copian las credenciales al resultado que se loguea o persiste.**
 *    Solo se devuelve qué credenciales vinieron (`present`) y su longitud no.
 *    El valor vive en un campo que el llamador tiene prohibido registrar.
 * 3. **El RNC del evento es una PISTA**, no la identidad: se valida contra la
 *    vinculación guardada en el servidor (`dosa-company-linking.policy.ts`).
 */

/** Credenciales tal como llegan. Nunca se registran ni se envían al cliente. */
export type DosaWebhookCredentials = {
  apiKeyProduccion?: string;
  apiKeyTest?: string;
  apiSecret?: string;
};

export type DosaWebhookPayload = {
  postulacionId: string;
  rnc: string;
  razonSocial: string;
  correo: string;
  /** `Produccion` / `Test` / etc. No se normaliza a un enum propio: el valor
   *  lo decide el proveedor y no lo usamos para autorizar nada. */
  ambiente: string;
  estadoCertificacion: string;
  /** Presencia de cada credencial. Sin valores. */
  presente: {
    apiKeyProduccion: boolean;
    apiKeyTest: boolean;
    apiSecret: boolean;
  };
  credencialesPendientes: boolean;
  disponiblesDesde: string;
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

  const postulacionId = text(body.postulacion_id);
  if (!postulacionId) {
    return { ok: false, reason: "MISSING_FIELD", field: "postulacion_id" };
  }

  const rnc = text(body.rnc);
  if (!rnc || normalizeRnc(rnc) === null) {
    return { ok: false, reason: "MISSING_FIELD", field: "rnc" };
  }

  const razonSocial = text(body.razon_social);
  if (!razonSocial) {
    return { ok: false, reason: "MISSING_FIELD", field: "razon_social" };
  }

  const estadoCertificacion = text(body.estado_certificacion);
  if (!estadoCertificacion) {
    return {
      ok: false,
      reason: "MISSING_FIELD",
      field: "estado_certificacion",
    };
  }

  const disponiblesDesde = text(body.disponibles_desde);
  if (!disponiblesDesde || Number.isNaN(Date.parse(disponiblesDesde))) {
    return { ok: false, reason: "INVALID_FIELD", field: "disponibles_desde" };
  }

  if (typeof body.credenciales_pendientes !== "boolean") {
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
    postulacionId,
    rnc,
    razonSocial,
    correo: text(body.correo) ?? "",
    ambiente: text(body.ambiente) ?? "",
    estadoCertificacion,
    presente: {
      apiKeyProduccion: secretos.apiKeyProduccion !== undefined,
      apiKeyTest: secretos.apiKeyTest !== undefined,
      apiSecret: secretos.apiSecret !== undefined,
    },
    credencialesPendientes: body.credenciales_pendientes,
    disponiblesDesde,
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

function normalizeRnc(value: string): string | null {
  const cleaned = value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
  if (cleaned.length < 8 || cleaned.length > 11) return null;
  return cleaned;
}
