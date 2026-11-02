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
  ) {}

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
    // 1. Firma
    const signature = verifyDosaSignature({
      headers: input.headers,
      config: this.signature,
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
         "signature_status","received_at")
      VALUES
        (gen_random_uuid(), ${company.companyId}::uuid, ${dedupeKey},
         ${"empresa.conectada"}, ${payload.postulacionId},
         ${payload.estadoCertificacion}, ${rawHash}, ${summary}::jsonb,
         ${signature.strategy}, NOW())
      ON CONFLICT ("company_id","dedupe_key") DO NOTHING
      RETURNING "id"
    `;

    if (rows.length === 0) {
      return {
        accepted: true,
        status: 200,
        duplicate: true,
        eventId: null,
        code: "ECF_DOSA_WEBHOOK_DUPLICATE",
      };
    }

    return {
      accepted: true,
      status: 200,
      duplicate: false,
      eventId: rows[0].id,
      code: "ECF_DOSA_WEBHOOK_RECORDED",
    };
  }
}

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
