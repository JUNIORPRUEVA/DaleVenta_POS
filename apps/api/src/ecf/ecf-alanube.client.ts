import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

const DOM_SANDBOX_BASE_URL = "https://sandbox.alanube.co/dom/v1";

export type AlanubeRuntimeState = {
  environment: string;
  baseUrl: string;
  realCallsEnabled: boolean;
  credentialReferenceConfigured: boolean;
  testFiscalProfileConfigured: boolean;
  externalCallsBlocked: boolean;
  sandboxReady: boolean;
  productionBlocked: true;
};

@Injectable()
export class EcfAlanubeClient {
  constructor(private readonly config: ConfigService) {}

  getRuntimeState(): AlanubeRuntimeState {
    const environment = this.read("ALANUBE_ENV", "sandbox").toLowerCase();
    const baseUrl = this.normalizeBaseUrl(
      this.read("ALANUBE_BASE_URL", DOM_SANDBOX_BASE_URL),
    );
    return {
      environment,
      baseUrl,
      realCallsEnabled: this.read("ALANUBE_ENABLE_REAL_CALLS", "false") === "true",
      credentialReferenceConfigured: this.hasSecretReference(
        this.readOptional("ALANUBE_TOKEN_SECRET_REF"),
      ),
      testFiscalProfileConfigured: this.hasTestFiscalProfile(),
      externalCallsBlocked: true,
      sandboxReady: environment === "sandbox" && this.isDomSandboxUrl(baseUrl),
      productionBlocked: true,
    };
  }

  private normalizeBaseUrl(value: string) {
    return value.trim().replace(/\/+$/, "");
  }

  private isDomSandboxUrl(value: string) {
    try {
      const url = new URL(value);
      return (
        url.protocol === "https:" &&
        url.hostname === "sandbox.alanube.co" &&
        url.pathname === "/dom/v1"
      );
    } catch {
      return false;
    }
  }

  private read(key: string, fallback: string) {
    return (this.config.get<string>(key) ?? process.env[key] ?? fallback).trim();
  }

  private readOptional(key: string) {
    return (this.config.get<string>(key) ?? process.env[key] ?? "").trim();
  }

  private hasSecretReference(value: string) {
    return /^(env|secret|vault|uat):\/\/[A-Za-z0-9._:/@-]+$/.test(value);
  }

  private hasTestFiscalProfile() {
    return [
      "ALANUBE_TEST_RNC",
      "ALANUBE_TEST_SEQUENCE_FROM",
      "ALANUBE_TEST_SEQUENCE_TO",
      "ALANUBE_TEST_SEQUENCE_EXPIRES_ON",
    ].every((key) => this.readOptional(key).length > 0);
  }
}
