import { randomUUID } from "node:crypto";
import {
  assessDosaEmissionGate,
  type DosaEmissionGateDecision,
} from "./dosa-emission.gate";
import { assessDosaDocumentBarrier } from "./dosa-emission.barrier";
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
  code:
    | "ECF_DOSA_GATE_BLOCKED"
    | "ECF_DOSA_CREDENTIALS_UNAVAILABLE"
    | "ECF_DOSA_DOCUMENT_BLOCKED";
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
 * Resultado de autorizar un despacho sin enviarlo.
 *
 * `client` sólo existe cuando TODAS las compuertas pasaron. Es la credencial de
 * esa empresa y de ese ambiente, ya cacheada por huella.
 */
export type DosaDispatchAuthorization =
  | {
      ok: false;
      code: "ECF_DOSA_DOCUMENT_BLOCKED" | "ECF_DOSA_GATE_BLOCKED" | "ECF_DOSA_CREDENTIALS_UNAVAILABLE";
      blockingReasons: readonly string[];
    }
  | {
      ok: true;
      client: DosaEmissionClient;
      environment: DosaCredentialEnvironment;
    };

/**
 * Emisión DOSA conectada a las compuertas reales.
 *
 * Orden obligatorio, sin atajos:
 *
 * 1. **Validar el documento** con `assessDosaDocumentBarrier`. Va primero y no
 *    depende de ninguna bandera: aunque alguien active `DOSA_EMISSION_ENABLED`
 *    por error, un cuerpo inválido (borrador sin extraer, `unidadMedida`
 *    ausente, `eNCF` incoherente, emisor de otra empresa, totales que no
 *    cuadran) no llega ni a la bóveda ni a la red.
 * 2. Leer la configuración fiscal **del servidor** (nunca del cliente).
 * 3. Evaluar `assessDosaEmissionGate` con la evidencia disponible.
 * 4. Si no está autorizado: **no se toca la red ni la bóveda**.
 * 5. Si está autorizado: abrir la credencial cifrada de ESA empresa y ESE RNC.
 * 6. Enviar con el cliente, que a su vez garantiza idempotencia por clave.
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

  /** Ambiente de emisión configurado en el servidor (`TEST` o `PRODUCTION`). */
  get environment(): DosaCredentialEnvironment {
    return this.deps.config.environment === "PRODUCTION" ? "production" : "test";
  }

  /** Decide sin efectos. Útil para mostrar al operador qué falta exactamente. */
  async assess(input: {
    companyId: string;
    rnc: string;
    documentType: EcfDocumentType;
    senderTaxId: string | null;
    sequenceAvailable: boolean;
  }): Promise<
    DosaEmissionGateDecision & {
      credentialStatus: string | null;
      credentialFingerprint: string | null;
    }
  > {
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
      // Identidad esperada en TEST: la de la EMPRESA que emite, no una variable
      // global. Cualquier empresa nueva queda cubierta sin configurar nada, y el
      // aislamiento lo garantiza el `rnc` de la petición (que la barrera del
      // documento ya contrasta con el emisor real del cuerpo).
      expectedTestRnc: input.rnc,
      providerEmissionEnabled: this.deps.config.enabled,
      productionEmissionEnabled: this.deps.config.productionEnabled,
      sequenceAvailable: input.sequenceAvailable,
      documentType: input.documentType,
    });

    return {
      ...decision,
      credentialStatus: credential?.status ?? null,
      credentialFingerprint: credential?.fingerprint ?? null,
    };
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
    const authorized = await this.authorizeForDispatch(input);
    if (!authorized.ok) {
      return {
        ok: false,
        code: authorized.code,
        blockingReasons: authorized.blockingReasons,
      };
    }

    const idempotencyKey = input.idempotencyKey ?? randomUUID();
    const result = await authorized.client.sendEcf({
      body: input.body,
      idempotencyKey,
    });
    return { ok: true, result, idempotencyKey };
  }

  /**
   * Autoriza un despacho y devuelve el CLIENTE ya configurado, **sin enviar**.
   *
   * Existe para que la persistencia y el envío puedan vivir en capas distintas
   * sin duplicar la política: `DosaEmissionDispatchService` necesita el cliente
   * autorizado para pasárselo a `EcfEmissionService.dispatchOnce`, que es quien
   * reclama la tentativa y guarda la evidencia. Si la autorización se repitiera
   * allí, tendríamos dos copias de las mismas reglas y una acabaría divergiendo.
   *
   * El orden es deliberado y no depende de ninguna bandera:
   *
   *  1. **Barrera del documento** — el cuerpo debe ser el contrato y su emisor
   *     debe ser la empresa autenticada. Un borrador extraído no se convierte
   *     en comprobante por el hecho de pedir el despacho.
   *  2. **Compuerta de configuración** — e-CF habilitado, proveedor DOSA,
   *     credencial ACTIVE, ambiente coherente, numeración disponible.
   *  3. **Bóveda** — se abre sólo después de que la compuerta autorice, y sólo
   *     la clave del ambiente seleccionado.
   */
  async authorizeForDispatch(input: {
    companyId: string;
    rnc: string;
    documentType: EcfDocumentType;
    senderTaxId: string | null;
    sequenceAvailable: boolean;
    body: DosaEcfRequestBody;
  }): Promise<DosaDispatchAuthorization> {
    // La barrera del documento va ANTES de la compuerta de configuración y no
    // depende de ninguna bandera: extraer el JSON de un borrador no convierte
    // el borrador en un comprobante transmisible.
    const barrier = assessDosaDocumentBarrier(input.body, {
      documentType: input.documentType,
      companyRnc: input.rnc,
    });
    if (!barrier.allowed) {
      return {
        ok: false,
        code: "ECF_DOSA_DOCUMENT_BLOCKED",
        blockingReasons: barrier.blockingReasons,
      };
    }

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

    // La credencial de ESTE entorno, y solo esa. Nunca se sustituye la clave de
    // TEST por la de produccion ni al reves: un fallback silencioso enviaria un
    // comprobante de pruebas firmado con credenciales productivas (o al
    // contrario), que es exactamente lo que no puede ocurrir.
    const apiKey =
      environment === "production"
        ? (bundle.apiKeyProduccion ?? "").trim()
        : (bundle.apiKeyTest ?? "").trim();

    if (apiKey.length === 0) {
      return {
        ok: false,
        code: "ECF_DOSA_CREDENTIALS_UNAVAILABLE",
        blockingReasons: [
          `ECF_DOSA_CREDENTIALS_MISSING_FOR_ENVIRONMENT:${environment.toUpperCase()}`,
        ],
      };
    }

    const client = this.clientFor(
      input.companyId,
      input.rnc,
      environment,
      decision.credentialFingerprint,
      apiKey,
    );

    return { ok: true, client, environment };
  }

  /**
   * Cliente por empresa + RNC + entorno + **huella de la credencial**.
   *
   * Incluir la huella es lo que hace que rotar o revocar una clave invalide el
   * cliente anterior: el siguiente envio pide un cliente distinto y el viejo se
   * descarta. Si la clave solo cambiara de valor con la misma clave de cache,
   * se seguiria enviando con la credencial vieja.
   */
  private clientFor(
    companyId: string,
    rnc: string,
    environment: DosaCredentialEnvironment,
    credentialFingerprint: string | null,
    apiKey: string,
  ): DosaEmissionClient {
    const scope = `${companyId}|${normalizeRnc(rnc)}|${environment}`;
    const key = `${scope}|${credentialFingerprint ?? "no-fingerprint"}`;
    const existing = this.clients.get(key);
    if (existing) return existing;

    // Invalidacion explicita: cualquier cliente de la misma empresa/RNC/entorno
    // con otra version de credencial deja de utilizarse.
    for (const stale of [...this.clients.keys()]) {
      if (stale.startsWith(`${scope}|`) && stale !== key) {
        this.clients.delete(stale);
      }
    }

    const created = new DosaEmissionClient(this.deps.transport, {
      ...this.deps.config,
      apiKey,
      apiKeyIsProduction: environment === "production",
    });
    this.clients.set(key, created);
    return created;
  }
}

function normalizeRnc(value: string): string {
  return `${value ?? ""}`.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}

function normalizeProvider(value: string | undefined): string {
  return `${value ?? ""}`.trim().toUpperCase();
}
