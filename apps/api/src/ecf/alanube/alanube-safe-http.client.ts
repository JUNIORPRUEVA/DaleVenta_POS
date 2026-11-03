import { randomUUID } from "node:crypto";
import { Inject, Injectable, Optional } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { EcfSecretResolverService } from "../ecf-secret-resolver.service";
import type { AlanubeDomMapping } from "../fiscal-core/alanube-dom.contract";
import { alanubeTypeFor, validateAlanubeRequestConformance } from "../fiscal-core/alanube-dom.contract";
import {
  ALANUBE_AUTH_CONTRACT,
  ALANUBE_DOM_SANDBOX_BASE_URL,
} from "./alanube-contract-matrix";
import type {
  AlanubeHttpTransport,
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "./alanube-safe-http.types";
import { AlanubeSimulatedTransport } from "./alanube-simulated.transport";
import { ALANUBE_HTTP_TRANSPORT } from "./alanube-transport.provider";

@Injectable()
export class AlanubeSafeHttpClient {
  constructor(
    private readonly config: ConfigService,
    private readonly secrets: EcfSecretResolverService,
    @Optional()
    @Inject(ALANUBE_HTTP_TRANSPORT)
    transport?: AlanubeHttpTransport,
  ) {
    this.transport = transport ?? new AlanubeSimulatedTransport();
  }

  private readonly transport: AlanubeHttpTransport;

  async prepareFiscalPost(mapping: AlanubeDomMapping): Promise<AlanubeTransportResult> {
    const guard = await this.assertSafeRuntime();
    if (!guard.ok) return guard;
    if (this.read("ALANUBE_ENABLE_REAL_CALLS", "false") !== "true") {
      return this.blocked("REAL_CALLS_DISABLED", "Las llamadas reales a Alanube están deshabilitadas.");
    }
    const type = alanubeTypeFor(mapping.kind);
    if (!type || !validateAlanubeRequestConformance(type, mapping.payload).ok) {
      return this.blocked("CONFIGURATION_ERROR", "Payload DOM inválido; transporte no invocado.");
    }
    // No public sender exists. Keep fiscal POSTs inert until a complete,
    // audited sending workflow replaces this preparation-only API.
    return this.blocked("CONFIGURATION_ERROR", "Envío fiscal bloqueado: contrato y flujo de emisión pendientes.");
  }

  /* Request serialization is local only; it never resolves a secret or sends. */
  buildRequest(mapping: AlanubeDomMapping, token: string): AlanubeSafeRequest {
    const baseUrl = this.normalizeBaseUrl(
      this.read("ALANUBE_BASE_URL", ALANUBE_DOM_SANDBOX_BASE_URL),
    );
    this.assertAllowedSandboxUrl(baseUrl);
    return {
      method: "POST",
      url: `${baseUrl}/${mapping.kind}`,
      headers: {
        [ALANUBE_AUTH_CONTRACT.header]: `${ALANUBE_AUTH_CONTRACT.valueFormat.replace("<token>", token)}`,
        "content-type": "application/json",
      },
      body: mapping.payload,
      timeoutMs: Number(this.read("ALANUBE_TIMEOUT_MS", "10000")),
      requestId: `ecf-${randomUUID()}`,
    };
  }

  private async assertSafeRuntime(): Promise<AlanubeTransportResult | { ok: true }> {
    if (this.read("ALANUBE_ENV", "sandbox") !== "sandbox") {
      return this.blocked("PRODUCTION_BLOCKED", "Solo Sandbox está permitido.");
    }
    if (this.read("ECF_EMISSION_ENABLED", "false") === "true") {
      return this.blocked(
        "CONFIGURATION_ERROR",
        "La emisión no puede estar habilitada para preparar transporte.",
      );
    }
    if (this.read("ECF_ALANUBE_AUTH_TESTS_ENABLED", "false") === "true") {
      return this.blocked(
        "CONFIGURATION_ERROR",
        "Las pruebas reales de autenticación no están habilitadas en esta fase.",
      );
    }
    return { ok: true };
  }

  private blocked(
    errorCode: Exclude<AlanubeTransportResult, { ok: true }>["errorCode"],
    safeMessage: string,
  ): AlanubeTransportResult {
    return { ok: false, errorCode, safeMessage, requestId: `ecf-${randomUUID()}` };
  }

  private assertAllowedSandboxUrl(value: string) {
    const url = new URL(value);
    if (
      url.protocol !== "https:" ||
      url.hostname !== "sandbox.alanube.co" ||
      url.port || url.search || url.hash ||
      url.pathname !== "/dom/v1" ||
      url.username ||
      url.password
    ) {
      throw new Error("URL Alanube Sandbox no permitida.");
    }
  }

  private normalizeBaseUrl(value: string) {
    return value.trim().replace(/\/+$/, "");
  }

  private read(key: string, fallback: string) {
    return (this.config.get<string>(key) ?? process.env[key] ?? fallback).trim();
  }
}
