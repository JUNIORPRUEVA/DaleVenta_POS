import { Injectable } from "@nestjs/common";
import {
  DosaCredentialVault,
  DosaCredentialVaultError,
  type DosaCredentialBundle,
  type DosaCredentialContext,
  type DosaCredentialEnvironment,
  type DosaCredentialInspection,
  type DosaCredentialStatus,
  type SealedDosaCredential,
} from "./dosa-credential-vault.service";
import {
  activationBlockers,
  type DosaActivationEvidence,
} from "./dosa-activation-authority.service";
import { splitCredentialsByEnvironment } from "./dosa-credential-environments";

/**
 * Persistencia de credenciales fiscales cifradas, **aislada por empresa/RNC y
 * entorno**.
 *
 * La tabla guarda el criptograma y los metadatos, nunca el valor. La clave
 * única `(company_id, rnc, environment)` es lo que impide que un RNC herede las
 * credenciales de otro: no existe ninguna consulta que lea credenciales por RNC
 * sin empresa.
 *
 * Todo acceso a base de datos es SQL parametrizado, igual que en el webhook, de
 * modo que esta pieza no depende de volver a generar el cliente Prisma.
 */

export type StoredDosaCredential = {
  companyId: string;
  rnc: string;
  environment: DosaCredentialEnvironment;
  status: DosaCredentialStatus;
  source: "WEBHOOK" | "MANUAL";
  sealed: SealedDosaCredential;
  updatedAt: string | null;
};

export interface DosaCredentialStore {
  upsert(row: StoredDosaCredential): Promise<void>;
  find(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }): Promise<StoredDosaCredential | null>;
  listByCompany(companyId: string): Promise<StoredDosaCredential[]>;
  setStatus(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
    status: DosaCredentialStatus;
  }): Promise<boolean>;
}

export const ECF_DOSA_CREDENTIAL_STORE = Symbol("ECF_DOSA_CREDENTIAL_STORE");

/** Cliente mínimo (SQL parametrizado). */
export interface DosaRawClient {
  $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T>;
}

type CredentialRow = {
  company_id: string;
  rnc: string;
  environment: string;
  status: string;
  source: string;
  key_version: number;
  ciphertext: string;
  iv: string;
  auth_tag: string;
  fingerprint: string;
  present: unknown;
  updated_at: Date | string | null;
};

export class PrismaDosaCredentialStore implements DosaCredentialStore {
  constructor(private readonly prisma: DosaRawClient) {}

  /**
   * Escribe la credencial de UN ambiente.
   *
   * Reglas del `ON CONFLICT` (aprendidas del incidente del 07/11):
   *
   * 1. **Nunca degrada un estado ya alcanzado.** Una fila `CONFIRMED` o
   *    `ACTIVE` conserva su estado aunque llegue material nuevo (rotación
   *    autorizada); solo una fila en `PENDING_CONFIRMATION` puede seguir siéndolo.
   * 2. **No reescribe si nada cambió.** El `WHERE` compara el `fingerprint` del
   *    criptograma: un reintento del mismo paquete no toca la fila ni su fecha.
   * 3. **`created_at` no se actualiza.** Es la fecha de alta, no la de edición;
   *    `updated_at` sí.
   *
   * La clave única `(company_id, rnc, environment)` sigue siendo el aislamiento:
   * un ambiente no puede escribir la fila de otro.
   */
  async upsert(row: StoredDosaCredential): Promise<void> {
    await this.prisma.$queryRaw`
      INSERT INTO "ecf_dosa_company_credentials"
        ("id","company_id","rnc","environment","status","source","key_version",
         "ciphertext","iv","auth_tag","fingerprint","present","created_at","updated_at")
      VALUES
        (gen_random_uuid(), ${row.companyId}::uuid, ${normalizeRnc(row.rnc)},
         ${row.environment}, ${row.status}, ${row.source}, ${row.sealed.keyVersion},
         ${row.sealed.ciphertext}, ${row.sealed.iv}, ${row.sealed.authTag},
         ${row.sealed.fingerprint}, ${JSON.stringify(row.sealed.present)}::jsonb,
         NOW(), NOW())
      ON CONFLICT ("company_id","rnc","environment") DO UPDATE SET
        "status" = CASE
          WHEN "ecf_dosa_company_credentials"."status" IN ('CONFIRMED','ACTIVE')
            THEN "ecf_dosa_company_credentials"."status"
          ELSE EXCLUDED."status"
        END,
        "source" = EXCLUDED."source",
        "key_version" = EXCLUDED."key_version",
        "ciphertext" = EXCLUDED."ciphertext",
        "iv" = EXCLUDED."iv",
        "auth_tag" = EXCLUDED."auth_tag",
        "fingerprint" = EXCLUDED."fingerprint",
        "present" = EXCLUDED."present",
        "updated_at" = NOW()
      WHERE "ecf_dosa_company_credentials"."fingerprint"
            IS DISTINCT FROM EXCLUDED."fingerprint"
    `;
  }

  async find(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }): Promise<StoredDosaCredential | null> {
    const rows = await this.prisma.$queryRaw<CredentialRow[]>`
      SELECT "company_id","rnc","environment","status","source","key_version",
             "ciphertext","iv","auth_tag","fingerprint","present","updated_at"
        FROM "ecf_dosa_company_credentials"
       WHERE "company_id" = ${input.companyId}::uuid
         AND "rnc" = ${normalizeRnc(input.rnc)}
         AND "environment" = ${input.environment}
       LIMIT 1
    `;
    return rows.length === 0 ? null : toStored(rows[0]);
  }

  async listByCompany(companyId: string): Promise<StoredDosaCredential[]> {
    const rows = await this.prisma.$queryRaw<CredentialRow[]>`
      SELECT "company_id","rnc","environment","status","source","key_version",
             "ciphertext","iv","auth_tag","fingerprint","present","updated_at"
        FROM "ecf_dosa_company_credentials"
       WHERE "company_id" = ${companyId}::uuid
       ORDER BY "rnc" ASC, "environment" ASC
    `;
    return rows.map(toStored);
  }

  async setStatus(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
    status: DosaCredentialStatus;
  }): Promise<boolean> {
    const rows = await this.prisma.$queryRaw<{ id: string }[]>`
      UPDATE "ecf_dosa_company_credentials"
         SET "status" = ${input.status}, "updated_at" = NOW()
       WHERE "company_id" = ${input.companyId}::uuid
         AND "rnc" = ${normalizeRnc(input.rnc)}
         AND "environment" = ${input.environment}
      RETURNING "id"
    `;
    return rows.length > 0;
  }
}

function toStored(row: CredentialRow): StoredDosaCredential {
  const present = (row.present ?? {}) as Record<string, unknown>;
  return {
    companyId: row.company_id,
    rnc: row.rnc,
    environment: row.environment === "production" ? "production" : "test",
    status: row.status as DosaCredentialStatus,
    source: row.source === "MANUAL" ? "MANUAL" : "WEBHOOK",
    sealed: {
      ciphertext: row.ciphertext,
      iv: row.iv,
      authTag: row.auth_tag,
      keyVersion: row.key_version,
      fingerprint: row.fingerprint,
      present: {
        apiKeyProduccion: present.apiKeyProduccion === true,
        apiKeyTest: present.apiKeyTest === true,
        apiSecret: present.apiSecret === true,
      },
    },
    updatedAt:
      row.updated_at instanceof Date
        ? row.updated_at.toISOString()
        : (row.updated_at ?? null),
  };
}

function normalizeRnc(value: string): string {
  return (value ?? "").replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}

export type DosaCredentialIngestStored = {
  environment: DosaCredentialEnvironment;
  status: DosaCredentialStatus;
  fingerprint: string;
};

export type DosaCredentialIngestResult =
  | {
      ok: true;
      /**
       * Estado y huella del ambiente principal (producción si vino, si no test).
       * Se conservan para no romper a los llamadores existentes.
       */
      status: DosaCredentialStatus;
      fingerprint: string;
      /** Qué se guardó y en qué ambiente. Sin valores. */
      stored: DosaCredentialIngestStored[];
      /** Ambientes que el paquete no traía y por tanto no se tocaron. */
      skipped: DosaCredentialEnvironment[];
      /**
       * Ambientes cuyo material entrante difiere del ya ACTIVO o CONFIRMADO.
       * No se escribieron: una rotación así exige revisión humana.
       */
      conflicts: DosaCredentialEnvironment[];
    }
  | { ok: false; blockedReason: string };

/**
 * Servicio de credenciales fiscales.
 *
 * Reglas de entrada y salida:
 *
 * * **`ingestFromProvider`** solo acepta credenciales si el evento venía
 *   autenticado. Guarda siempre como `PENDING_CONFIRMATION`: un evento del
 *   proveedor **no activa** facturación.
 * * **`promote`** es el único camino a `ACTIVE` y exige, a la vez, confirmación
 *   del proveedor, aprobación DGII y autorización administrativa explícita. Si
 *   falta una, no cambia nada.
 * * **`openForEmission`** es el único método que devuelve valores, y solo con
 *   autorización vigente declarada por el llamador.
 * * Todo lo demás (`inspect`, `listForCompany`) devuelve metadatos sin valores.
 */
@Injectable()
export class DosaCredentialService {
  constructor(
    private readonly store: DosaCredentialStore,
    private readonly vault: DosaCredentialVault,
  ) {}

  /**
   * Ingesta de credenciales recibidas del proveedor (evento ya autenticado).
   *
   * **Reparte por ambiente.** El campo `environment` de la entrada describe el
   * ambiente de la CERTIFICACIÓN declarado por el evento; no decide dónde va
   * cada clave. `apiKeyProduccion` va a la fila `production`, `apiKeyTest` a la
   * fila `test` y `apiSecret` acompaña a ambas. Ver
   * `dosa-credential-environments.ts`.
   *
   * Consecuencia buscada: un evento `ambiente=Produccion` que trae las dos
   * llaves deja de esconder la de TEST dentro de producción. Y un evento que
   * solo trae una de las dos **no borra** la otra: el ambiente sin su clave
   * identificadora no se toca.
   */
  async ingestFromProvider(input: {
    companyId: string;
    rnc: string;
    /** Ambiente declarado por el evento (evidencia). No ubica las claves. */
    environment: DosaCredentialEnvironment;
    bundle: DosaCredentialBundle;
    /** Verdadero solo si la firma del evento se verificó. */
    signatureAuthenticated: boolean;
  }): Promise<DosaCredentialIngestResult> {
    if (!input.signatureAuthenticated) {
      return {
        ok: false,
        blockedReason: "ECF_DOSA_CREDENTIALS_EVENT_NOT_AUTHENTICATED",
      };
    }

    const split = splitCredentialsByEnvironment(input.bundle, input.environment);
    if (split.targets.length === 0) {
      return {
        ok: false,
        blockedReason: "ECF_DOSA_CREDENTIALS_EMPTY_BUNDLE",
      };
    }

    const stored: DosaCredentialIngestStored[] = [];
    const conflicts: DosaCredentialEnvironment[] = [];

    for (const target of split.targets) {
      const context: DosaCredentialContext = {
        companyId: input.companyId,
        rnc: normalizeRnc(input.rnc),
        environment: target.environment,
      };

      let sealed: SealedDosaCredential;
      try {
        sealed = this.vault.seal(context, target.bundle);
      } catch (error) {
        return { ok: false, blockedReason: codeOf(error) };
      }

      // Una credencial ya confirmada o activa NO se sustituye por otra que
      // llegue por webhook. Rotarla es una decisión humana: se registra el
      // conflicto, se deja la fila intacta y el evento queda en revisión.
      const current = await this.store.find({
        companyId: input.companyId,
        rnc: normalizeRnc(input.rnc),
        environment: target.environment,
      });
      const isProtected =
        current !== null &&
        (current.status === "CONFIRMED" || current.status === "ACTIVE");
      if (isProtected && current.sealed.fingerprint !== sealed.fingerprint) {
        conflicts.push(target.environment);
        continue;
      }

      await this.store.upsert({
        companyId: input.companyId,
        rnc: normalizeRnc(input.rnc),
        environment: target.environment,
        status: "PENDING_CONFIRMATION",
        source: "WEBHOOK",
        sealed,
        updatedAt: null,
      });

      stored.push({
        environment: target.environment,
        status: "PENDING_CONFIRMATION",
        fingerprint: sealed.fingerprint,
      });
    }

    // Si todo lo que venía era un conflicto, no hay nada nuevo que guardar.
    if (stored.length === 0 && conflicts.length > 0) {
      return {
        ok: true,
        status: "PENDING_CONFIRMATION",
        fingerprint: "",
        stored: [],
        skipped: split.skipped.map((entry) => entry.environment),
        conflicts,
      };
    }

    const primary =
      stored.find((entry) => entry.environment === "production") ?? stored[0];

    return {
      ok: true,
      status: primary.status,
      fingerprint: primary.fingerprint,
      stored,
      skipped: split.skipped.map((entry) => entry.environment),
      conflicts,
    };
  }

  /**
   * Reclasifica un paquete ya guardado: separa la clave TEST que pudo quedar
   * dentro de la fila de producción.
   *
   * Para qué existe: la primera entrega real (06–07/11/2026) guardó las dos
   * llaves bajo `environment=production`. Sin este camino habría que pedirle al
   * proveedor un reenvío solo para recolocar una clave que **ya** está cifrada
   * en la bóveda.
   *
   * Garantías:
   *
   * 1. **Requiere autorización explícita** (`authorized`); la bóveda rechaza el
   *    descifrado sin ella (`DOSA_CREDENTIALS_OPEN_NOT_AUTHORIZED`).
   * 2. **No modifica la fila de origen.** Solo escribe los ambientes que faltan
   *    o cuyo `fingerprint` difiere; `production` nunca se toca.
   * 3. **Idempotente**: si el ambiente destino ya tiene el mismo `fingerprint`,
   *    informa `already` y no escribe.
   * 4. **Sin valores en la respuesta**: solo ambientes, estados y huellas.
   * 5. No activa nada: lo que escriba entra como `PENDING_CONFIRMATION`.
   */
  async reclassifyStoredCredentials(input: {
    companyId: string;
    rnc: string;
    /** Ambiente que contiene el paquete completo a repartir. */
    sourceEnvironment: DosaCredentialEnvironment;
    authorized: boolean;
    /** Con `true` calcula el resultado pero no escribe nada. */
    dryRun?: boolean;
  }): Promise<{
    ok: boolean;
    blockedReason?: string;
    /** Ambientes que se escribirían (o se escribieron, si no es dry-run). */
    written: DosaCredentialIngestStored[];
    already: DosaCredentialEnvironment[];
    applied: boolean;
  }> {
    const dryRun = input.dryRun === true;
    const source = await this.store.find({
      companyId: input.companyId,
      rnc: input.rnc,
      environment: input.sourceEnvironment,
    });
    if (!source) {
      return {
        ok: false,
        blockedReason: "DOSA_CREDENTIALS_NOT_FOUND",
        written: [],
        already: [],
        applied: false,
      };
    }

    let bundle: DosaCredentialBundle;
    try {
      bundle = this.vault.open({
        sealed: source.sealed,
        context: {
          companyId: source.companyId,
          rnc: source.rnc,
          environment: source.environment,
        },
        purpose: "REMEDIATION",
        authorized: input.authorized,
      });
    } catch (error) {
      return {
        ok: false,
        blockedReason: codeOf(error),
        written: [],
        already: [],
        applied: false,
      };
    }

    const split = splitCredentialsByEnvironment(bundle);
    const written: DosaCredentialIngestStored[] = [];
    const already: DosaCredentialEnvironment[] = [];

    for (const target of split.targets) {
      // El ambiente de origen no se reescribe: su contenido no cambia.
      if (target.environment === input.sourceEnvironment) {
        already.push(target.environment);
        continue;
      }

      const current = await this.store.find({
        companyId: input.companyId,
        rnc: input.rnc,
        environment: target.environment,
      });

      let sealed: SealedDosaCredential;
      try {
        sealed = this.vault.seal(
          {
            companyId: input.companyId,
            rnc: normalizeRnc(input.rnc),
            environment: target.environment,
          },
          target.bundle,
        );
      } catch (error) {
        return {
          ok: false,
          blockedReason: codeOf(error),
          written,
          already,
          applied: false,
        };
      }

      if (current && current.sealed.fingerprint === sealed.fingerprint) {
        already.push(target.environment);
        continue;
      }

      if (!dryRun) {
        await this.store.upsert({
          companyId: input.companyId,
          rnc: normalizeRnc(input.rnc),
          environment: target.environment,
          status: "PENDING_CONFIRMATION",
          source: "WEBHOOK",
          sealed,
          updatedAt: null,
        });
      }

      written.push({
        environment: target.environment,
        status: "PENDING_CONFIRMATION",
        fingerprint: sealed.fingerprint,
      });
    }

    return { ok: true, written, already, applied: !dryRun };
  }

  async inspect(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }): Promise<DosaCredentialInspection | null> {
    const row = await this.store.find(input);
    if (!row) return null;
    return {
      companyId: row.companyId,
      rnc: row.rnc,
      environment: row.environment,
      status: row.status,
      keyVersion: row.sealed.keyVersion,
      fingerprint: row.sealed.fingerprint,
      present: row.sealed.present,
      updatedAt: row.updatedAt,
    };
  }

  async listForCompany(companyId: string): Promise<DosaCredentialInspection[]> {
    const rows = await this.store.listByCompany(companyId);
    return rows.map((row) => ({
      companyId: row.companyId,
      rnc: row.rnc,
      environment: row.environment,
      status: row.status,
      keyVersion: row.sealed.keyVersion,
      fingerprint: row.sealed.fingerprint,
      present: row.sealed.present,
      updatedAt: row.updatedAt,
    }));
  }

  /**
   * Cambia el estado. La evidencia se recibe **ya leída de la base** por
   * `DosaAuthorizationReader`: esta capa no acepta «autorízame» como argumento.
   *
   * * `REVOKED` no exige evidencia (revocar siempre es posible).
   * * `CONFIRMED` exige confirmación del proveedor.
   * * `ACTIVE` exige las cuatro piezas: vínculo RNC↔empresa, confirmación del
   *   proveedor, aprobación DGII por registro oficial y autorización
   *   administrativa con actor real.
   */
  async promote(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
    to: "CONFIRMED" | "ACTIVE" | "REVOKED";
    evidence: DosaActivationEvidence;
  }): Promise<{ ok: true; status: DosaCredentialStatus } | { ok: false; blockedReason: string }> {
    if (input.to === "REVOKED") {
      const changed = await this.store.setStatus({ ...input, status: "REVOKED" });
      return changed
        ? { ok: true, status: "REVOKED" }
        : { ok: false, blockedReason: "ECF_DOSA_CREDENTIALS_NOT_FOUND" };
    }
    if (input.to === "CONFIRMED") {
      if (!input.evidence.identityLinked) {
        return { ok: false, blockedReason: "ECF_DOSA_ACTIVATION_RNC_NOT_LINKED" };
      }
      if (!input.evidence.providerConfirmed) {
        return { ok: false, blockedReason: "ECF_DOSA_CREDENTIALS_PROVIDER_NOT_CONFIRMED" };
      }
      const changed = await this.store.setStatus({ ...input, status: "CONFIRMED" });
      return changed
        ? { ok: true, status: "CONFIRMED" }
        : { ok: false, blockedReason: "ECF_DOSA_CREDENTIALS_NOT_FOUND" };
    }
    const blockers = activationBlockers(input.evidence);
    if (blockers.length > 0) {
      return {
        ok: false,
        blockedReason: `ECF_DOSA_CREDENTIALS_NOT_ACTIVATABLE:${blockers.join(",")}`,
      };
    }
    const changed = await this.store.setStatus({ ...input, status: "ACTIVE" });
    return changed
      ? { ok: true, status: "ACTIVE" }
      : { ok: false, blockedReason: "ECF_DOSA_CREDENTIALS_NOT_FOUND" };
  }

  /** Único camino que devuelve valores. Uso exclusivo del emisor autorizado. */
  async openForEmission(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
    authorized: boolean;
  }): Promise<DosaCredentialBundle> {
    const row = await this.store.find(input);
    if (!row) {
      throw new DosaCredentialVaultError("DOSA_CREDENTIALS_CONTEXT_MISMATCH", "not found");
    }
    return this.vault.open({
      sealed: row.sealed,
      context: contextOf(input),
      purpose: "EMISSION",
      authorized: input.authorized,
    });
  }
}

function contextOf(input: {
  companyId: string;
  rnc: string;
  environment: DosaCredentialEnvironment;
}): DosaCredentialContext {
  return {
    companyId: input.companyId,
    rnc: normalizeRnc(input.rnc),
    environment: input.environment,
  };
}

function codeOf(error: unknown): string {
  if (error instanceof DosaCredentialVaultError) return error.code;
  return "ECF_DOSA_CREDENTIALS_SEAL_FAILED";
}
