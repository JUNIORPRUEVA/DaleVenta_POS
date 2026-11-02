import { randomUUID } from "node:crypto";
import {
  assessDosaEmissionGate,
  type DosaEmissionGateDecision,
} from "./dosa-emission.gate";
import type { DosaCredentialService } from "./dosa-credential.service";
import type { DosaCredentialEnvironment } from "./dosa-credential-vault.service";
import {
  DosaEmissionClient,
  type DosaEmissionConfig,
  type DosaHttpTransport,
  type DosaSendResult,
} from "./dosa-emission.client";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";

/**
 * Configuración fiscal de la empresa, leída del servidor.
 *
 * El `provider` se lee como texto (`provider::text`) porque el enum `EcfProvider`
 * de la base de datos **hoy solo admite `ALANUBE`**. Añadir `DOSA` al enum es una
 * migración de tipo que necesita `ALTER TYPE ... ADD VALUE` y no se hace aquí sin
 * autorización; mientras tanto, esta lectura permite verificar la compuerta y
 * probar el recorrido completo con un doble, sin fingir que la base ya lo admite.
 */
export interface DosaCompanyFiscalConfigReader {
  read(companyId: string): Promise<{
    ecfEnabled: boolean;
    /** Texto tal cual: `ALANUBE`, `DOSA` o lo que venga. */
    provider: string;
  } | null>;
}

export const ECF_DOSA_FISCAL_CONFIG = Symbol("ECF_DOSA_FISCAL_CONFIG");

/** Token del transporte HTTP de emision. En pruebas se inyecta un doble. */
export const ECF_DOSA_EMISSION_TRANSPORT = Symbol("ECF_DOSA_EMISSION_TRANSPORT");

export type DosaEmitBlocked = {
  ok: false;
  code: "ECF_DOSA_GATE_BLOCKED" | "ECF_DOSA_CREDENTIALS_UNAVAILABLE";
  blockingReasons: readonly string[];
};

export type DosaEmitDone = {
  ok: true;
  /** Clasificación del proveedor. Nunca es una aceptación fiscal de FullPOS. */
  result: DosaSendResult;
  idempotencyKey: string;
};

export type DosaEmitResult = DosaEmitBlocked | DosaEmitDone;

/**
 * Emisión DOSA conectada a las compuertas reales.
 *
 * Orden obligatorio, sin atajos:
 *
 * 1. Leer la configuración fiscal **del servidor** (nunca del cliente).
 * 2. Evaluar `assessDosaEmissionGate` con la evidencia disponible.
 * 3. Si no está autorizado: **no se toca la red ni la bóveda**.
 * 4. Si está autorizado: abrir la credencial cifrada de ESA empresa y ESE RNC.
 * 5. Enviar con el cliente, que a su vez garantiza idempotencia por clave.
 *
 * Esta clase no crea documentos, no consume secuencias y no cambia estados: eso
 * lo hace el orquestador de emisión, que es quien tiene la transacción.
 */
export class DosaEmissionService {
  /**
   * Un cliente por empresa y entorno.
   *
   * Es obligatorio reutilizarlo: el cliente guarda las claves de idempotencia
   * ya enviadas y el estado del cortacircuitos. Si se creara uno nuevo en cada
   * llamada, un reintento con la misma clave volvería a salir a la red y el
   * cortacircuitos nunca se abriría.
   */
  private readonly clients = new Map<string, DosaEmissionClient>();

  constructor(
    private readonly deps: {
      fiscalConfig: DosaCompanyFiscalConfigReader;
      credentials: DosaCredentialService;
      config: DosaEmissionConfig;
      transport: DosaHttpTransport;
    },
  ) {}

  /** Decide sin efectos. Útil para mostrar al operador qué falta exactamente. */
  async assess(input: {
    companyId: string;
    rnc: string;
    documentType: EcfDocumentType;
    senderTaxId: string | null;
    sequenceAvailable: boolean;
  }): Promise<DosaEmissionGateDecision & { credentialStatus: string | null }> {
    const fiscal = await this.deps.fiscalConfig.read(input.companyId);
    const environment: DosaCredentialEnvironment =
      this.deps.config.environment === "PRODUCTION" ? "production" : "test";
    const credential = await this.deps.credentials.inspect({
      companyId: input.companyId,
      rnc: input.rnc,
      environment,
    });

    const decision = assessDosaEmissionGate({
      companyEcfEnabled: fiscal?.ecfEnabled === true,
      companyProviderIsDosa: normalizeProvider(fiscal?.provider) === "DOSA",
      credentialStatus: credential?.status ?? null,
      credentialEnvironment: credential?.environment ?? null,
      environment,
      senderTaxId: input.senderTaxId,
      configuredTestRnc: this.deps.config.testRnc,
      providerEmissionEnabled: this.deps.config.enabled,
      productionEmissionEnabled: this.deps.config.productionEnabled,
      sequenceAvailable: input.sequenceAvailable,
      documentType: input.documentType,
    });

    return { ...decision, credentialStatus: credential?.status ?? null };
  }

  async emit(input: {
    companyId: string;
    rnc: string;
    documentType: EcfDocumentType;
    senderTaxId: string | null;
    sequenceAvailable: boolean;
    body: DosaEcfRequestBody;
    /** Clave de idempotencia: la tentativa ya reclamada por el orquestador. */
    idempotencyKey?: string;
  }): Promise<DosaEmitResult> {
    const decision = await this.assess(input);
    if (!decision.allowed) {
      return {
        ok: false,
        code: "ECF_DOSA_GATE_BLOCKED",
        blockingReasons: decision.blockingReasons,
      };
    }

    const environment: DosaCredentialEnvironment =
      this.deps.config.environment === "PRODUCTION" ? "production" : "test";

    let bundle: { apiKeyProduccion?: string; apiKeyTest?: string };
    try {
      bundle = await this.deps.credentials.openForEmission({
        companyId: input.companyId,
        rnc: input.rnc,
        environment,
        // La compuerta ya autorizó; este es el único punto donde se declara.
        authorized: true,
      });
    } catch {
      return {
        ok: false,
        code: "ECF_DOSA_CREDENTIALS_UNAVAILABLE",
        blockingReasons: ["ECF_DOSA_CREDENTIALS_UNAVAILABLE"],
      };
    }

    const apiKey =
      environment === "production"
        ? (bundle.apiKeyProduccion ?? "")
        : (bundle.apiKeyTest ?? bundle.apiKeyProduccion ?? "");
    if (apiKey.trim().length === 0) {
      return {
        ok: false,
        code: "ECF_DOSA_CREDENTIALS_UNAVAILABLE",
        blockingReasons: ["ECF_DOSA_CREDENTIALS_MISSING_FOR_ENVIRONMENT"],
      };
    }

    const client = this.clientFor(input.companyId, environment, apiKey);

    const idempotencyKey = input.idempotencyKey ?? randomUUID();
    const result = await client.sendEcf({ body: input.body, idempotencyKey });
    return { ok: true, result, idempotencyKey };
  }

  private clientFor(
    companyId: string,
    environment: DosaCredentialEnvironment,
    apiKey: string,
  ): DosaEmissionClient {
    const key = `${companyId}|${environment}`;
    const existing = this.clients.get(key);
    if (existing) return existing;
    const created = new DosaEmissionClient(this.deps.transport, {
      ...this.deps.config,
      apiKey,
      apiKeyIsProduction: environment === "production",
    });
    this.clients.set(key, created);
    return created;
  }
}

function normalizeProvider(value: string | undefined): string {
  return `${value ?? ""}`.trim().toUpperCase();
}
