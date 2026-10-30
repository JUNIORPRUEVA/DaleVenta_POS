import { E32_SANDBOX_URL, isE32UatTarget } from "./e32-sandbox.policy";
import type { AlanubeTransportResult } from "../alanube/alanube-safe-http.types";
import { validateAlanubeRequestConformance } from "../fiscal-core/alanube-dom.contract";
import { e32SafeObservation } from "./e32-sandbox.observation";

export type E32WireRequest = { method: "POST" | "GET"; path: string; body?: unknown; requestId: string };
export type E32WireResult = AlanubeTransportResult & { rawBody?: Buffer };
export interface E32TrialWire { readonly mode: "SANDBOX" | "MOCK_ONLY"; execute(input: E32WireRequest): Promise<E32WireResult>; }

// Deliberately not registered as the application's general transport.
// Its sole caller must consume the durable first-trial claim before execute.
export class E32SandboxOneShotWire implements E32TrialWire {
  readonly mode = "SANDBOX" as const;
  private posted = false;
  private queried = false;
  constructor(private readonly resolveToken: () => Promise<string>,
    private readonly observe?: (observation: ReturnType<typeof e32SafeObservation>) => Promise<void>) {}
  async execute(input: E32WireRequest): Promise<E32WireResult> {
    const blocked = (): AlanubeTransportResult => ({ ok: false, errorCode: "CONFIGURATION_ERROR", safeMessage: "E32_SANDBOX_WIRE_BLOCKED", requestId: input.requestId });
    if (!isE32UatTarget() || process.env.APP_ENV !== "uat" || process.env.UAT_LOCAL_ONLY !== "true" || process.env.ALANUBE_ENV !== "sandbox" ||
      process.env.ALANUBE_BASE_URL !== E32_SANDBOX_URL || process.env.ALANUBE_ENABLE_REAL_CALLS !== "true" ||
      process.env.ECF_EMISSION_ENABLED !== "true" || process.env.ECF_ALANUBE_AUTH_TESTS_ENABLED === "true") return blocked();
    if (input.method === "POST") {
      if (this.posted || input.path !== "/invoices" || !input.body || !validateAlanubeRequestConformance("E32", input.body).ok) return blocked();
      this.posted = true;
    } else {
      if (this.queried || !/^\/invoices\/[0-7][0-9A-HJKMNP-TV-Z]{25}(?:\/idCompany\/[0-7][0-9A-HJKMNP-TV-Z]{25})?$/.test(input.path) || input.body !== undefined) return blocked();
      this.queried = true;
    }
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 10000);
    try {
      const token = await this.resolveToken();
      if (!token.trim() || /[\r\n]/.test(token)) return blocked();
      const response = await fetch(E32_SANDBOX_URL + input.path, { method: input.method, redirect: "manual", signal: controller.signal,
        headers: { authorization: `Bearer ${token}`, accept: "application/json", "content-type": "application/json" },
        ...(input.body !== undefined ? { body: JSON.stringify(input.body) } : {}) });
      if (response.status >= 300 && response.status < 400) return { ok: false, errorCode: "REDIRECT_BLOCKED", safeMessage: "E32_REDIRECT_BLOCKED", requestId: input.requestId };
      // Bound the stream before JSON parsing. No response headers or body logs.
      const reader = response.body?.getReader(); let size = 0; const chunks: Uint8Array[] = [];
      if (reader) { try {
        while (true) { const chunk = await reader.read(); if (chunk.done) break;
          size += chunk.value.length; if (size > 65536) { await reader.cancel(); throw Error("E32_RESPONSE_SIZE"); } chunks.push(chunk.value); }
      } finally { reader.releaseLock(); } }
      let body: unknown;
      const rawBody = Buffer.concat(chunks);
      try { body = JSON.parse(rawBody.toString("utf8")); } catch { body = null; }
      await this.observe?.(e32SafeObservation(input.method,response.status,body,rawBody));
      return { ok: true, rawBody, response: { statusCode: response.status, body, headers: {}, requestId: input.requestId } };
    } catch { return { ok: false, errorCode: controller.signal.aborted ? "TIMEOUT" : "NETWORK_ERROR", safeMessage: "E32_RESULT_UNKNOWN", requestId: input.requestId }; }
    finally { clearTimeout(timer); }
  }
}
