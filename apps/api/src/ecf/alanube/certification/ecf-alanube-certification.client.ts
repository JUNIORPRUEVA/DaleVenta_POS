import { Inject, Injectable, Optional } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

import { ALANUBE_AUTH_CONTRACT, ALANUBE_DOM_SANDBOX_BASE_URL } from "../alanube-contract-matrix";
import type {
  AlanubeHttpTransport,
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "../alanube-safe-http.types";
import { AlanubeSimulatedTransport } from "../alanube-simulated.transport";
import { ALANUBE_HTTP_TRANSPORT } from "../alanube-transport.provider";
import {
  buildCheckSetTestsRequest,
  buildCompanyEnrollRequest,
  buildCompanyInfoRequest,
  buildProviderInfoRequest,
  buildSetTestsRequest,
  buildSignHabilitationRequest,
  validateCompanyInfoResponse,
  validateProviderInfoResponse,
  validateSetTestsIdentifiers,
  validateSetTestsInput,
  validateSignHabilitationInput,
  type EcfCertificationRequest,
  type EcfCompanyEnrollInput,
  type EcfSetTestsInput,
  type EcfSignHabilitationInput,
} from "./ecf-alanube-certification.contracts";

/**
 * Cliente de los servicios de CERTIFICACIÓN de Alanube.
 *
 * Reutiliza el transporte único del módulo (`ALANUBE_HTTP_TRANSPORT`) y el
 * contrato de autenticación ya versionado (`ALANUBE_AUTH_CONTRACT`). No crea un
 * segundo cliente HTTP, no resuelve secretos y no se conecta a producción: la
 * URL se valida contra el host oficial de sandbox.
 *
 * Nunca lanza por un fallo de red o del proveedor: devuelve un resultado tipado
 * para que el motor decida, y distingue con claridad:
 *
 *  - `REJECTED`  → el proveedor respondió «no» (definitivo, no reintentar tal cual).
 *  - `RETRYABLE` → no se aplicó (429, GET con timeout) y se puede reintentar.
 *  - `UNCERTAIN` → **no se sabe** si se aplicó (timeout, 5xx o respuesta
 *    ilegible en una operación que escribe). Prohibido reenviar a ciegas.
 *  - `CONTRACT_MISMATCH` / `UNCONFIGURED` → error nuestro, no del proveedor.
 *
 * Además marca `simulated` cuando la respuesta viene del simulador: una
 * respuesta técnica correcta NO es una aprobación oficial y aquí queda separado.
 */

export type EcfCertificationFailureKind =
  | "REJECTED"
  | "RETRYABLE"
  | "UNCERTAIN"
  | "CONTRACT_MISMATCH"
  | "UNCONFIGURED";

export type EcfCertificationOutcome<T> =
  | { ok: true; value: T; simulated: boolean }
  | {
      ok: false;
      kind: EcfCertificationFailureKind;
      code: string;
      detail: string;
      simulated: boolean;
    };

export type EcfProviderInfo = {
  name: string;
  taxId: string;
  softwareName: string | null;
  softwareVersion: string | null;
};

export type EcfCompanyInfo = {
  id: string;
  legalName: string | null;
  companyUrls: {
    receptionUrl: string | null;
    commercialApprovalUrl: string | null;
    authenticationUrl: string | null;
  };
};

export type EcfHabilitationSignature = {
  /** Enlace al documento firmado. Firmar no es presentar. */
  signedDocumentUrl: string | null;
  raw: Record<string, unknown>;
};

export type EcfSetTestsCreated = {
  id: string | null;
  raw: Record<string, unknown>;
};

export type EcfSetTestsStatus = {
  status: string | null;
  documentsZipUrl: string | null;
  resumesZipUrl: string | null;
  raw: Record<string, unknown>;
};

const SIMULATION_MARK = "SIMULATED_NOT_OFFICIAL";

export type EcfCertificationCallContext = {
  /** Token Bearer ya resuelto por la capa de secretos. Nunca se registra. */
  token: string;
  /** Clave de idempotencia: viaja como `requestId` para trazabilidad. */
  idempotencyKey: string;
};

@Injectable()
export class EcfAlanubeCertificationClient {
  constructor(
    private readonly config: ConfigService,
    @Optional()
    @Inject(ALANUBE_HTTP_TRANSPORT)
    transport?: AlanubeHttpTransport,
  ) {
    this.transport = transport ?? new AlanubeSimulatedTransport();
  }

  private readonly transport: AlanubeHttpTransport;

  getProviderInfo(ctx: EcfCertificationCallContext) {
    return this.call<EcfProviderInfo>(
      buildProviderInfoRequest(),
      ctx,
      { mutating: false },
      (body) => {
        const validation = validateProviderInfoResponse(body);
        if (!validation.ok) return { ok: false, detail: validation.detail };
        const record = body as Record<string, unknown>;
        return {
          ok: true,
          value: {
            name: String(record.name),
            taxId: String(record.taxId),
            softwareName: text(record.softwareName),
            softwareVersion: text(record.softwareVersion),
          },
        };
      },
    );
  }

  enrollCompany(input: EcfCompanyEnrollInput, ctx: EcfCertificationCallContext) {
    return this.call<EcfCompanyInfo>(
      buildCompanyEnrollRequest(input),
      ctx,
      { mutating: true },
      companyInfoResult,
    );
  }

  getCompanyInfo(idCompany: string, ctx: EcfCertificationCallContext) {
    return this.call<EcfCompanyInfo>(
      buildCompanyInfoRequest(idCompany),
      ctx,
      { mutating: false },
      companyInfoResult,
    );
  }

  signHabilitation(
    input: EcfSignHabilitationInput,
    ctx: EcfCertificationCallContext,
  ) {
    const validation = validateSignHabilitationInput(input);
    if (!validation.ok) {
      return Promise.resolve<EcfCertificationOutcome<EcfHabilitationSignature>>({
        ok: false,
        kind: "UNCONFIGURED",
        code: validation.code,
        detail: validation.detail,
        simulated: false,
      });
    }
    return this.call<EcfHabilitationSignature>(
      buildSignHabilitationRequest(input),
      ctx,
      { mutating: true },
      (body) => {
        const record = asRecord(body);
        if (!record) return { ok: false, detail: "Respuesta de firma ilegible." };
        return {
          ok: true,
          value: {
            signedDocumentUrl: text(
              record.signedDocumentUrl ?? record.url ?? record.documentUrl,
            ),
            raw: record,
          },
        };
      },
    );
  }

  createSetTests(input: EcfSetTestsInput, ctx: EcfCertificationCallContext) {
    const validation = validateSetTestsInput(input);
    if (!validation.ok) {
      return Promise.resolve<EcfCertificationOutcome<EcfSetTestsCreated>>({
        ok: false,
        kind: "UNCONFIGURED",
        code: validation.code,
        detail: validation.detail,
        simulated: false,
      });
    }
    return this.call<EcfSetTestsCreated>(
      buildSetTestsRequest(input),
      ctx,
      { mutating: true },
      (body) => {
        const record = asRecord(body);
        if (!record) {
          return { ok: false, detail: "Respuesta del set de pruebas ilegible." };
        }
        return { ok: true, value: { id: text(record.id), raw: record } };
      },
    );
  }

  checkSetTests(
    idSet: string,
    idCompany: string,
    ctx: EcfCertificationCallContext,
  ) {
    const validation = validateSetTestsIdentifiers(idSet, idCompany);
    if (!validation.ok) {
      return Promise.resolve<EcfCertificationOutcome<EcfSetTestsStatus>>({
        ok: false,
        kind: "UNCONFIGURED",
        code: validation.code,
        detail: validation.detail,
        simulated: false,
      });
    }
    return this.call<EcfSetTestsStatus>(
      buildCheckSetTestsRequest(idSet, idCompany),
      ctx,
      { mutating: false },
      (body) => {
        const record = asRecord(body);
        if (!record) {
          return { ok: false, detail: "Respuesta del estado del set ilegible." };
        }
        const documents = asRecord(record.documentsInfo);
        const resumes = asRecord(record.resumesInfo);
        return {
          ok: true,
          value: {
            status: text(record.status ?? record.setTestStatus),
            documentsZipUrl: text(documents?.zipUrl),
            resumesZipUrl: text(resumes?.zipUrl),
            raw: record,
          },
        };
      },
    );
  }

  // -------------------------------------------------------------------------

  private async call<T>(
    request: EcfCertificationRequest,
    ctx: EcfCertificationCallContext,
    options: { mutating: boolean },
    interpret: (
      body: unknown,
    ) => { ok: true; value: T } | { ok: false; detail: string },
  ): Promise<EcfCertificationOutcome<T>> {
    const baseUrl = this.baseUrl();
    if (!baseUrl) {
      return {
        ok: false,
        kind: "UNCONFIGURED",
        code: "ECF_ALANUBE_BASE_URL_INVALID",
        detail: "La URL de Alanube no apunta al sandbox oficial.",
        simulated: false,
      };
    }
    if (!ctx.token.trim()) {
      return {
        ok: false,
        kind: "UNCONFIGURED",
        code: "ECF_ALANUBE_TOKEN_REQUIRED",
        detail: "No hay credencial de Alanube disponible para esta operación.",
        simulated: false,
      };
    }

    const safeRequest: AlanubeSafeRequest = {
      method: request.method,
      url: `${baseUrl}${request.path}`,
      headers: {
        [ALANUBE_AUTH_CONTRACT.header]: ALANUBE_AUTH_CONTRACT.valueFormat.replace(
          "<token>",
          ctx.token,
        ),
        "content-type": "application/json",
      },
      ...(request.body === undefined ? {} : { body: request.body }),
      timeoutMs: Number(this.config.get<string>("ALANUBE_TIMEOUT_MS") ?? 10000),
      // Determinista: el mismo intento lógico reutiliza el mismo requestId.
      requestId: ctx.idempotencyKey,
    };

    const result = await this.transport.execute(safeRequest);
    return this.interpretResult(result, options, interpret, request.operation);
  }

  private interpretResult<T>(
    result: AlanubeTransportResult,
    options: { mutating: boolean },
    interpret: (
      body: unknown,
    ) => { ok: true; value: T } | { ok: false; detail: string },
    operation: string,
  ): EcfCertificationOutcome<T> {
    if (!result.ok) {
      // Un fallo de transporte no dice si el proveedor llegó a aplicarlo.
      if (result.errorCode === "TIMEOUT" || result.errorCode === "NETWORK_ERROR") {
        return options.mutating
          ? this.uncertain(operation, result.errorCode, result.safeMessage)
          : this.failure("RETRYABLE", result.errorCode, result.safeMessage);
      }
      if (
        result.errorCode === "REAL_CALLS_DISABLED" ||
        result.errorCode === "PRODUCTION_BLOCKED"
      ) {
        return this.failure("UNCONFIGURED", result.errorCode, result.safeMessage);
      }
      return this.failure("CONTRACT_MISMATCH", result.errorCode, result.safeMessage);
    }

    const { statusCode, body } = result.response;
    const simulated = containsSimulationMark(body);

    if (statusCode === 429) {
      return this.failure(
        "RETRYABLE",
        "ECF_ALANUBE_RATE_LIMITED",
        "El proveedor limitó las solicitudes; no se aplicó la operación.",
      );
    }
    if (statusCode >= 500) {
      return options.mutating
        ? this.uncertain(
            operation,
            "ECF_ALANUBE_SERVER_ERROR",
            `El proveedor respondió ${statusCode}.`,
          )
        : this.failure(
            "RETRYABLE",
            "ECF_ALANUBE_SERVER_ERROR",
            `El proveedor respondió ${statusCode}.`,
          );
    }
    if (statusCode >= 400) {
      return this.failure(
        "REJECTED",
        "ECF_ALANUBE_REJECTED",
        `El proveedor rechazó la operación (${statusCode}).`,
      );
    }

    const parsed = interpret(body);
    if (!parsed.ok) {
      // 2xx con un cuerpo que no cumple el contrato: en una escritura no se
      // puede afirmar que no se aplicó.
      return options.mutating
        ? this.uncertain(operation, "ECF_ALANUBE_CONTRACT_MISMATCH", parsed.detail)
        : this.failure("CONTRACT_MISMATCH", "ECF_ALANUBE_CONTRACT_MISMATCH", parsed.detail);
    }
    return { ok: true, value: parsed.value, simulated };
  }

  private failure(
    kind: EcfCertificationFailureKind,
    code: string,
    detail: string,
  ): EcfCertificationOutcome<never> {
    return { ok: false, kind, code, detail, simulated: false };
  }

  private uncertain(
    operation: string,
    code: string,
    detail: string,
  ): EcfCertificationOutcome<never> {
    return {
      ok: false,
      kind: "UNCERTAIN",
      code,
      detail: `${detail} No se puede saber si ${operation} se aplicó; hay que reconciliar antes de reintentar.`,
      simulated: false,
    };
  }

  /**
   * Base URL del sandbox oficial. Si la configuración apunta a otro host, se
   * devuelve `null` y la operación no se ejecuta (fallo cerrado).
   */
  private baseUrl(): string | null {
    const raw = (
      this.config.get<string>("ALANUBE_BASE_URL") ?? ALANUBE_DOM_SANDBOX_BASE_URL
    )
      .trim()
      .replace(/\/+$/, "");
    try {
      const url = new URL(raw);
      if (
        url.protocol !== "https:" ||
        url.hostname !== "sandbox.alanube.co" ||
        url.port ||
        url.search ||
        url.hash ||
        url.pathname !== "/dom/v1"
      ) {
        return null;
      }
      return raw;
    } catch {
      return null;
    }
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function text(value: unknown): string | null {
  const raw = typeof value === "string" ? value.trim() : "";
  return raw.length > 0 ? raw : null;
}

function containsSimulationMark(body: unknown): boolean {
  const record = asRecord(body);
  return record?.mark === SIMULATION_MARK;
}

function companyInfoResult(
  body: unknown,
): { ok: true; value: EcfCompanyInfo } | { ok: false; detail: string } {
  const validation = validateCompanyInfoResponse(body);
  if (!validation.ok) return { ok: false, detail: validation.detail };
  const record = body as Record<string, unknown>;
  const urls = asRecord(record.companyUrls);
  return {
    ok: true,
    value: {
      id: String(record.id),
      legalName: text(record.name ?? record.legalName),
      companyUrls: {
        receptionUrl: text(urls?.receptionUrl),
        commercialApprovalUrl: text(urls?.commercialApprovalUrl),
        authenticationUrl: text(urls?.authenticationUrl),
      },
    },
  };
}
