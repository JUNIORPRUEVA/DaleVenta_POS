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
        "status" = EXCLUDED."status",
        "source" = EXCLUDED."source",
        "key_version" = EXCLUDED."key_version",
        "ciphertext" = EXCLUDED."ciphertext",
        "iv" = EXCLUDED."iv",
        "auth_tag" = EXCLUDED."auth_tag",
        "fingerprint" = EXCLUDED."fingerprint",
        "present" = EXCLUDED."present",
        "updated_at" = NOW()
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

export type DosaCredentialIngestResult =
  | { ok: true; status: DosaCredentialStatus; fingerprint: string }
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

  async ingestFromProvider(input: {
    companyId: string;
    rnc: string;
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
    const context = contextOf(input);
    let sealed: SealedDosaCredential;
    try {
      sealed = this.vault.seal(context, input.bundle);
    } catch (error) {
      return { ok: false, blockedReason: codeOf(error) };
    }

    await this.store.upsert({
      companyId: input.companyId,
      rnc: normalizeRnc(input.rnc),
      environment: input.environment,
      status: "PENDING_CONFIRMATION",
      source: "WEBHOOK",
      sealed,
      updatedAt: null,
    });
    return { ok: true, status: "PENDING_CONFIRMATION", fingerprint: sealed.fingerprint };
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
