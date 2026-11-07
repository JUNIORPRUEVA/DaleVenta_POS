import { Inject, Injectable, Logger, Optional } from "@nestjs/common";
import { createHash } from "node:crypto";
import {
  parseDosaWebhookPayload,
  redactDosaWebhookEvent,
  type DosaWebhookPayload,
} from "./dosa-webhook.dto";
import {
  readDosaSignatureConfig,
  verifyDosaSignature,
  type DosaSignatureConfig,
  type DosaSignatureRejection,
} from "./dosa-webhook-signature.policy";
import type { DosaCredentialService } from "./dosa-credential.service";
import type { DosaCredentialEnvironment } from "./dosa-credential-vault.service";

/** Cliente mínimo (SQL parametrizado). Se puede sustituir por un doble. */
export interface DosaWebhookStore {
  $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T>;
}

export const ECF_DOSA_WEBHOOK_STORE = Symbol("ECF_DOSA_WEBHOOK_STORE");

/**
 * Correlación empresa ↔ RNC. **Debe ser server-side.**
 *
 * La única fuente autoritativa que existe hoy es
 * `ecf_dosa_certification_sessions`, creada por nuestro backend. El RNC que
 * llega en el evento es una PISTA: nunca selecciona tenant por sí solo.
 */
export interface DosaCompanyResolver {
  resolveByRnc(rnc: string): Promise<{
    companyId: string;
    ecfEnabled: boolean;
    /**
     * `true` si la empresa tiene autorización vigente para el asistente.
     * Lo resuelve el servidor junto con el resto de la fila, para que el webhook
     * no tenga que leer entorno ni hacer una segunda consulta.
     */
    portalEligible?: boolean;
  } | null>;
}

export const ECF_DOSA_COMPANY_RESOLVER = Symbol("ECF_DOSA_COMPANY_RESOLVER");

/** Permite inyectar la configuracion de firma en pruebas. */
export const ECF_DOSA_SIGNATURE_CONFIG = Symbol("ECF_DOSA_SIGNATURE_CONFIG");

/**
 * Contrato MÍNIMO de la sesión de certificación para el webhook.
 *
 * Solo dos operaciones, y ninguna puede cambiar `status` ni autorizar nada:
 *
 * * `recordEventHint` — deja constancia de que llegó un evento.
 * * `bindProviderPostulation` — asocia el `postulacion_id` del proveedor al
 *   intento ACTIVO. La propia consulta impide que un identificador se vincule a
 *   otra empresa, que se sobrescriba uno ya confirmado y que se invente una
 *   sesión inexistente.
 *
 * Es la única puerta por la que un evento autenticado puede tocar identificadores
 * del proveedor. El navegador nunca los envía.
 */
export interface DosaSessionHintRecorder {
  recordEventHint(input: {
    companyId: string;
    rnc: string;
    eventType: string;
  }): Promise<{ updated: boolean }>;
  bindProviderPostulation(input: {
    companyId: string;
    rnc: string;
    providerPostulationId: string;
  }): Promise<{ bound: boolean }>;
}

export const ECF_DOSA_SESSION_HINTS = Symbol("ECF_DOSA_SESSION_HINTS");

export type DosaWebhookOutcome =
  | { accepted: false; status: number; code: string; reason: string }
  | {
      accepted: true;
      status: number;
      duplicate: boolean;
      eventId: string | null;
      code: string;
    };

/**
 * Pipeline del webhook DOSA.
 *
 * Orden estricto, y cada paso falla cerrado:
 *
 * 1. **Firma** — estrategia intercambiable, `BLOCKED` por defecto.
 * 2. **Esquema** — payload real de DOSA, sin tolerar desviaciones.
 * 3. **Correlación** — RNC → empresa, solo desde vinculación de servidor.
 * 4. **Opt-in** — una empresa sin e-CF habilitado no procesa eventos.
 * 5. **Idempotencia** — índice único (company_id, dedupe_key); un reintento
 *    devuelve `duplicate` y no reprocesa.
 * 6. **Persistencia REDACTADA** — jamás se guardan ni se loguean credenciales.
 *
 * Lo que este servicio NO hace, por diseño: activar emisión, marcar aceptación
 * DGII, ni cambiar el estado de la sesión. Un evento es **evidencia candidata**.
 */
@Injectable()
export class DosaWebhookService {
  /**
   * Registro de RECHAZOS.
   *
   * Un evento rechazado no deja fila en la base, así que sin esta línea un
   * webhook mal configurado (estrategia `BLOCKED`, secreto distinto, unidad de
   * `t` equivocada, RNC desconocido) fallaría en completo silencio: el cliente
   * se queda esperando credenciales y nada lo explica. Se registran solo el
   * código y el motivo: nunca el cuerpo, ni cabeceras, ni el secreto.
   */
  private readonly logger = new Logger(DosaWebhookService.name);

  constructor(
    @Inject(ECF_DOSA_WEBHOOK_STORE) private readonly store: DosaWebhookStore,
    @Inject(ECF_DOSA_COMPANY_RESOLVER)
    private readonly resolver: DosaCompanyResolver,
    @Optional()
    @Inject(ECF_DOSA_SIGNATURE_CONFIG)
    private readonly injectedSignature?: DosaSignatureConfig,
    @Optional()
    @Inject(DosaWebhookService.CREDENTIALS)
    private readonly credentials?: DosaCredentialService,
    @Optional()
    @Inject(ECF_DOSA_SESSION_HINTS)
    private readonly sessionHints?: DosaSessionHintRecorder,
  ) {}

  /** Token para inyectar la boveda de credenciales sin acoplar el modulo. */
  static readonly CREDENTIALS = Symbol("ECF_DOSA_CREDENTIALS");

  /** Configuracion efectiva: la inyectada o, si no, la del entorno. */
  private get signature(): DosaSignatureConfig {
    return (
      this.injectedSignature ??
      readDosaSignatureConfig(process.env as Record<string, string>)
    );
  }

  async handle(input: {
    headers: Record<string, string | string[] | undefined>;
    rawBody: Buffer | undefined;
    body: unknown;
  }): Promise<DosaWebhookOutcome> {
    // 1. Firma — se verifica sobre los BYTES ORIGINALES, nunca sobre el JSON
    //    re-serializado: `HMAC-SHA256(secret, t + "." + rawBody)`.
    const signature = verifyDosaSignature({
      headers: input.headers,
      config: this.signature,
      rawBody: input.rawBody,
    });
    if (!signature.ok) {
      this.logger.warn(
        `Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_BLOCKED / ${signature.reason} ` +
          `(estrategia ${signature.strategy})`,
      );
      return {
        accepted: false,
        status: httpStatusForSignatureRejection(signature.reason),
        code: "ECF_DOSA_WEBHOOK_BLOCKED",
        reason: signature.reason,
      };
    }

    if (!input.rawBody) {
      // Cinturón para la estrategia de laboratorio, que no consume el cuerpo
      // para verificar pero sí lo necesita para la huella y la deduplicación.
      return {
        accepted: false,
        status: 400,
        code: "ECF_DOSA_WEBHOOK_RAW_BODY_MISSING",
        reason: "RAW_BODY_UNAVAILABLE",
      };
    }

    // 2. Esquema
    const parsed = parseDosaWebhookPayload(input.body);
    if (!parsed.ok) {
      this.logger.warn(
        `Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_INVALID_PAYLOAD / ${parsed.reason}${
          parsed.field ? `:${parsed.field}` : ""
        }`,
      );
      return {
        accepted: false,
        status: 400,
        code: "ECF_DOSA_WEBHOOK_INVALID_PAYLOAD",
        reason: parsed.field ? `${parsed.reason}:${parsed.field}` : parsed.reason,
      };
    }
    const { payload } = parsed.value;

    // 3. Correlación server-side
    const company = await this.resolver.resolveByRnc(payload.rnc);
    if (!company) {
      // El RNC es la única forma de correlacionar: si no lo conocemos, el evento
      // se rechaza sin guardar. Sin esta línea sería invisible.
      this.logger.warn(
        `Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_UNKNOWN_RNC / rnc=${payload.rnc}`,
      );
      return {
        accepted: false,
        status: 404,
        code: "ECF_DOSA_WEBHOOK_UNKNOWN_RNC",
        reason: "UNKNOWN_RNC",
      };
    }

    // La certificación del piloto precede a la activación de emisión. Fuera
    // del piloto se conserva la compuerta histórica de e-CF habilitado.
    // `portalEligible` lo resuelve el servidor desde la autorización POR EMPRESA
    // guardada en base; ya no depende de una variable del despliegue.
    if (!company.ecfEnabled && company.portalEligible !== true) {
      this.logger.warn(
        `Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_ECF_DISABLED / company=${company.companyId}`,
      );
      return {
        accepted: false,
        status: 409,
        code: "ECF_DOSA_WEBHOOK_ECF_DISABLED",
        reason: "ECF_DISABLED",
      };
    }

    // 5. Idempotencia + 6. persistencia redactada
    const rawHash = createHash("sha256")
      .update(input.rawBody)
      .digest("hex");
    // La identidad del evento combina la referencia lógica (postulación, estado,
    // fecha de disponibilidad) con el cuerpo EXACTO recibido.
    //
    // Consecuencia buscada: un reintento idéntico sigue siendo `duplicate` (mismo
    // cuerpo, mismo hash), pero un envío del mismo evento con **otro contenido**
    // —por ejemplo credenciales nuevas— deja de descartarse en silencio y se
    // procesa como evento propio. La política de rotación decide después qué
    // hacer con las credenciales; aquí solo se garantiza que no se pierden.
    const dedupeKey = dedupeKeyOf(payload, rawHash);
    // El tipo de evento sale de lo que el proveedor envía, no de una constante
    // nuestra: ver `classifyDosaEventType`.
    const classification = classifyDosaEventType(payload);
    const summary = JSON.stringify({
      event: classification.eventType,
      classified: classification.classified,
      ...redactDosaWebhookEvent(payload),
    });

    const rows = await this.store.$queryRaw<{ id: string }[]>`
      INSERT INTO "ecf_dosa_webhook_events"
        ("id","company_id","dedupe_key","event_type","postulacion_id",
         "estado_certificacion","raw_body_sha256","payload_summary",
         "signature_status","processing_state","received_at")
      VALUES
        (gen_random_uuid(), ${company.companyId}::uuid, ${dedupeKey},
         ${classification.eventType}, ${payload.postulacionId},
         ${payload.estadoCertificacion}, ${rawHash}, ${summary}::jsonb,
         ${signature.strategy}, ${PENDING_STATE}, NOW())
      ON CONFLICT ("company_id","dedupe_key") DO NOTHING
      RETURNING "id"
    `;

    if (rows.length > 0) {
      return this.completeEvent({
        eventId: rows[0].id,
        companyId: company.companyId,
        dedupeKey,
        payload,
        secretos: parsed.value.secretos,
        eventType: classification.eventType,
        resumed: false,
      });
    }

    // Ya existia. Si quedo a medias (el proceso anterior murio entre la
    // insercion y el guardado de credenciales), se REANUDA en vez de darlo por
    // duplicado: de lo contrario el evento quedaria incompleto para siempre.
    const existing = await this.store.$queryRaw<
      Array<{ id: string; processing_state: string | null }>
    >`
      SELECT "id", "processing_state"
        FROM "ecf_dosa_webhook_events"
       WHERE "company_id" = ${company.companyId}::uuid
         AND "dedupe_key" = ${dedupeKey}
       LIMIT 1
    `;

    if (existing.length > 0 && existing[0].processing_state === PENDING_STATE) {
      return this.completeEvent({
        eventId: existing[0].id,
        companyId: company.companyId,
        dedupeKey,
        payload,
        secretos: parsed.value.secretos,
        eventType: classification.eventType,
        resumed: true,
      });
    }

    return {
      accepted: true,
      status: 200,
      duplicate: true,
      eventId: null,
      code: "ECF_DOSA_WEBHOOK_DUPLICATE",
    };
  }

    // Las credenciales del evento se guardan CIFRADAS y en estado
    // PENDING_CONFIRMATION. Que lleguen no las activa: activarlas exige
    // confirmacion del proveedor, aprobacion DGII y autorizacion administrativa.
  /**
   * Cierra el evento: guarda las credenciales cifradas y solo entonces lo marca
   * como completo.
   *
   * Si el guardado falla, el evento queda en `PENDING_CREDENTIALS` y se responde
   * 5xx para que el proveedor reintente; el reenvio lo reanuda. Nunca se responde
   * 2xx con el trabajo obligatorio sin hacer, y nunca se silencia el error.
   */
  private async completeEvent(input: {
    eventId: string;
    companyId: string;
    dedupeKey: string;
    payload: { rnc: string; ambiente: string; postulacionId: string };
    secretos: { apiKeyProduccion?: string; apiKeyTest?: string; apiSecret?: string };
    /** Tipo de evento que se persistió: clasificado o pendiente de clasificación. */
    eventType: string;
    resumed: boolean;
  }): Promise<DosaWebhookOutcome> {
    const hasCredentials =
      (input.secretos.apiKeyProduccion ?? "").trim().length > 0 ||
      (input.secretos.apiKeyTest ?? "").trim().length > 0 ||
      (input.secretos.apiSecret ?? "").trim().length > 0;

    if (hasCredentials) {
      if (!this.credentials) {
        // Sin boveda no se puede cumplir la obligacion: se falla, no se finge.
        return {
          accepted: false,
          status: 500,
          code: "ECF_DOSA_WEBHOOK_CREDENTIALS_UNAVAILABLE",
          reason: "CREDENTIAL_SERVICE_NOT_CONFIGURED",
        };
      }

      const stored = await this.credentials.ingestFromProvider({
        companyId: input.companyId,
        rnc: input.payload.rnc,
        environment: environmentOf(input.payload.ambiente),
        bundle: input.secretos,
        // La firma ya se verifico antes de llegar aqui.
        signatureAuthenticated: true,
      });

      if (!stored.ok) {
        // Error real, no silenciado. El evento sigue en PENDING_CREDENTIALS.
        return {
          accepted: false,
          status: 500,
          code: "ECF_DOSA_WEBHOOK_CREDENTIALS_FAILED",
          reason: stored.blockedReason,
        };
      }

      // Rotación no autorizada: el evento queda registrado, las credenciales
      // vigentes quedan intactas y el caso pasa a revisión humana. Nunca se
      // sustituye una clave activa porque un webhook lo diga.
      if ((stored.conflicts ?? []).length > 0) {
        await this.store.$queryRaw`
          UPDATE "ecf_dosa_webhook_events"
             SET "processing_state" = ${CONFLICT_STATE}
           WHERE "id" = ${input.eventId}::uuid
             AND "company_id" = ${input.companyId}::uuid
        `;

        return {
          accepted: true,
          status: 200,
          duplicate: false,
          eventId: input.eventId,
          code: "ECF_DOSA_WEBHOOK_CONFLICT_PENDING_REVIEW",
        };
      }
    }

    await this.store.$queryRaw`
      UPDATE "ecf_dosa_webhook_events"
         SET "processing_state" = ${COMPLETE_STATE},
             "credentials_stored_at" = NOW()
       WHERE "id" = ${input.eventId}::uuid
         AND "company_id" = ${input.companyId}::uuid
    `;

    // Pista de correlación con la postulación EN CURSO de esa empresa y ese RNC.
    //
    // Es best-effort y deliberadamente débil: `recordEventHint` solo escribe
    // `last_event_type` / `last_event_at`. No toca `status`, ni autoriza nada.
    // Si la empresa no tiene un intento activo, no se crea ninguna fila.
    //
    // Un fallo aquí NO invalida el evento ya persistido: el hecho fiscal queda
    // registrado y la pista es un extra. Se ignora para no convertir un
    // problema cosmético en un reintento del proveedor.
    if (this.sessionHints) {
      try {
        await this.sessionHints.recordEventHint({
          companyId: input.companyId,
          rnc: input.payload.rnc,
          eventType: input.eventType,
        });
      } catch {
        // Intencionadamente no se propaga: ver el comentario anterior.
      }

      // Vínculo REAL con la postulación: Empresa → RNC → intento activo →
      // `postulacion_id`. Lo garantiza una sola sentencia SQL que exige intento
      // activo, no sobrescribe un identificador ya confirmado y no acepta un
      // identificador que ya pertenezca a otra empresa.
      //
      // Si devuelve `false` no se fuerza nada: el evento ya está persistido con
      // su `postulacion_id`, así que la reconciliación es posible después. Este
      // servicio NO crea sesiones ni elige una «a la primera que aparezca».
      try {
        await this.sessionHints.bindProviderPostulation({
          companyId: input.companyId,
          rnc: input.payload.rnc,
          providerPostulationId: input.payload.postulacionId,
        });
      } catch {
        // Igual que la pista: el hecho fiscal ya quedó registrado.
      }
    }

    return {
      accepted: true,
      status: 200,
      duplicate: false,
      eventId: input.eventId,
      code: input.resumed
        ? "ECF_DOSA_WEBHOOK_RESUMED"
        : "ECF_DOSA_WEBHOOK_RECORDED",
    };
  }
}

/** Estados de procesamiento persistidos del evento. */
export const PENDING_STATE = "PENDING_CREDENTIALS";
export const COMPLETE_STATE = "COMPLETE";
/**
 * El evento llegó autenticado y traía credenciales que **no coinciden** con las
 * vigentes. Se conserva como evidencia y se deja en revisión: la rotación es un
 * acto humano, no un efecto automático de un webhook.
 */
export const CONFLICT_STATE = "CONFLICT_PENDING_REVIEW";

/**
 * Código HTTP correcto para cada rechazo de firma.
 *
 * Por qué importa: un `5xx` es, por convención, «el servidor tuvo un problema,
 * vuelve a intentarlo». Devolverlo ante una firma inválida o un timestamp
 * expirado le dice al proveedor exactamente lo contrario de lo que pasa: el
 * evento **no se va a aceptar** repitiéndolo, así que solo se consigue que
 * reintente en vano (y que el reintento llegue aún más caducado).
 *
 * * `401` — no autenticado. Repetir con la misma cabecera no puede funcionar;
 *   el proveedor debe renovar la firma o revisar su secreto.
 * * `503` — el receptor está mal configurado (estrategia bloqueada, secreto
 *   ausente o inválido). Es transitorio desde el punto de vista del proveedor,
 *   así que reintentar sí tiene sentido cuando operaciones corrija el secreto.
 * * `500` — fallo propio del receptor (no pudimos leer el cuerpo crudo). No es
 *   culpa del emisor y no se arregla reintentando, pero tampoco es un problema
 *   de autenticación.
 *
 * La seguridad no cambia: el evento se rechaza igual en los tres casos y no se
 * ejecuta ninguna consulta. Solo cambia lo que el emisor entiende.
 */
export function httpStatusForSignatureRejection(
  reason: DosaSignatureRejection,
): number {
  switch (reason) {
    case "STRATEGY_BLOCKED":
    case "SECRET_NOT_CONFIGURED":
    case "CONFIG_INVALID":
      return 503;
    case "RAW_BODY_UNAVAILABLE":
      return 500;
    default:
      return 401;
  }
}

/**
 * Etiqueta con la que se persiste un evento cuyo **tipo** no está confirmado.
 *
 * No es un código inventado de DOSA: es una marca nuestra que dice, sin
 * ambigüedad, «este evento está autenticado y persistido, pero su tipo todavía
 * no se puede afirmar». Ocupa `event_type`, que es `varchar(64)`.
 */
export const PENDING_CLASSIFICATION_EVENT_TYPE = "PENDING_CLASSIFICATION";

export type DosaEventClassification = {
  /** Valor que se guarda en `event_type`. */
  eventType: string;
  /** `true` solo si el proveedor envió un tipo de evento documentado. */
  classified: boolean;
};

/**
 * Tipo de evento según lo que el proveedor **realmente** envía.
 *
 * La muestra oficial de DOSA (`03_WEBHOOK_EJEMPLO_SANITIZADO.json`) tiene estos
 * campos: `postulacion_id`, `rnc`, `razon_social`, `correo`, `ambiente`,
 * `estado_certificacion`, `credenciales`, `credenciales_pendientes` y
 * `disponibles_desde`. **No hay ningún campo de tipo de evento.**
 *
 * Por eso aquí no se adivina: se marca como pendiente de clasificación. Etiquetar
 * un evento como `empresa.conectada` sin que el proveedor lo diga sería
 * justamente inventar el dato, y ese valor se estaba guardando como si fuera
 * observado. El día que DOSA documente un campo de tipo, este es el único punto
 * que hay que cambiar.
 *
 * Importante: esta etiqueta **no autoriza nada**. Ni la recepción de credenciales
 * ni la activación dependen de ella; la autoridad de activación mira la
 * evidencia persistida (postulación, estado de certificación, habilitación DGII
 * y autorización administrativa).
 */
export function classifyDosaEventType(
  payload: DosaWebhookPayload,
): DosaEventClassification {
  void payload;
  return { eventType: PENDING_CLASSIFICATION_EVENT_TYPE, classified: false };
}

/**
 * Clave de idempotencia SIN identificador de evento.
 *
 * La muestra de DOSA no trae `event_id`, así que se usa la identidad de negocio
 * que sí es estable entre reintentos: postulación + estado + fecha de
 * disponibilidad. Se hashea para no exceder la columna.
 */
export function dedupeKeyOf(
  payload: {
    postulacionId: string;
    estadoCertificacion: string;
    disponiblesDesde: string;
  },
  /**
   * SHA-256 del cuerpo exacto recibido. Sin él, un envío con el mismo
   * identificador lógico pero contenido distinto se descartaría como duplicado y
   * las credenciales nuevas se perderían. Es un hash del cuerpo: no expone
   * valores y no es reversible.
   */
  rawBodySha256 = "",
): string {
  return createHash("sha256")
    .update(
      `${payload.postulacionId}|${payload.estadoCertificacion}|${payload.disponiblesDesde}|${rawBodySha256}`,
    )
    .digest("hex");
}

/**
 * Entorno fiscal a partir del campo `ambiente` del proveedor.
 *
 * El proveedor usa `Produccion` / `Test`. Cualquier otro valor se trata como
 * `test`: es el lado seguro, porque una credencial de produccion mal etiquetada
 * nunca debe terminar marcada como productiva.
 */
export function environmentOf(ambiente: string): DosaCredentialEnvironment {
  return /produccion|production/i.test(ambiente ?? "")
    ? "production"
    : "test";
}
