import { Inject, Injectable, Optional } from "@nestjs/common";
import { createHash } from "node:crypto";
import {
  parseDosaWebhookPayload,
  redactDosaWebhookEvent,
} from "./dosa-webhook.dto";
import {
  readDosaSignatureConfig,
  verifyDosaSignature,
  type DosaSignatureConfig,
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
  resolveByRnc(
    rnc: string,
  ): Promise<{ companyId: string; ecfEnabled: boolean } | null>;
}

export const ECF_DOSA_COMPANY_RESOLVER = Symbol("ECF_DOSA_COMPANY_RESOLVER");

/** Permite inyectar la configuracion de firma en pruebas. */
export const ECF_DOSA_SIGNATURE_CONFIG = Symbol("ECF_DOSA_SIGNATURE_CONFIG");

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
      return {
        accepted: false,
        status: 503,
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
      return {
        accepted: false,
        status: 404,
        code: "ECF_DOSA_WEBHOOK_UNKNOWN_RNC",
        reason: "UNKNOWN_RNC",
      };
    }

    // 4. Opt-in de la empresa
    if (!company.ecfEnabled) {
      return {
        accepted: false,
        status: 409,
        code: "ECF_DOSA_WEBHOOK_ECF_DISABLED",
        reason: "ECF_DISABLED",
      };
    }

    // 5. Idempotencia + 6. persistencia redactada
    const dedupeKey = dedupeKeyOf(payload);
    const rawHash = createHash("sha256")
      .update(input.rawBody)
      .digest("hex");
    const summary = JSON.stringify({
      event: "empresa.conectada",
      ...redactDosaWebhookEvent(payload),
    });

    const rows = await this.store.$queryRaw<{ id: string }[]>`
      INSERT INTO "ecf_dosa_webhook_events"
        ("id","company_id","dedupe_key","event_type","postulacion_id",
         "estado_certificacion","raw_body_sha256","payload_summary",
         "signature_status","processing_state","received_at")
      VALUES
        (gen_random_uuid(), ${company.companyId}::uuid, ${dedupeKey},
         ${"empresa.conectada"}, ${payload.postulacionId},
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
    payload: { rnc: string; ambiente: string };
    secretos: { apiKeyProduccion?: string; apiKeyTest?: string; apiSecret?: string };
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
    }

    await this.store.$queryRaw`
      UPDATE "ecf_dosa_webhook_events"
         SET "processing_state" = ${COMPLETE_STATE},
             "credentials_stored_at" = NOW()
       WHERE "id" = ${input.eventId}::uuid
         AND "company_id" = ${input.companyId}::uuid
    `;

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
 * Clave de idempotencia SIN identificador de evento.
 *
 * La muestra de DOSA no trae `event_id`, así que se usa la identidad de negocio
 * que sí es estable entre reintentos: postulación + estado + fecha de
 * disponibilidad. Se hashea para no exceder la columna.
 */
export function dedupeKeyOf(payload: {
  postulacionId: string;
  estadoCertificacion: string;
  disponiblesDesde: string;
}): string {
  return createHash("sha256")
    .update(
      `${payload.postulacionId}|${payload.estadoCertificacion}|${payload.disponiblesDesde}`,
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
