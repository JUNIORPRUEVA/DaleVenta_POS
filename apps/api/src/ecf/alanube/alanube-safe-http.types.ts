export type AlanubeSafeRequest = {
  method: "POST" | "GET";
  url: string;
  headers: Record<string, string>;
  body?: unknown;
  timeoutMs: number;
  requestId: string;
};

export type AlanubeSafeResponse = {
  statusCode: number;
  headers: Record<string, string>;
  body: unknown;
  requestId: string;
};

export type AlanubeTransportResult =
  | { ok: true; response: AlanubeSafeResponse }
  | {
      ok: false;
      errorCode:
        | "REAL_CALLS_DISABLED"
        | "TIMEOUT"
        | "NETWORK_ERROR"
        | "INVALID_RESPONSE"
        | "PROVIDER_REJECTED"
        | "REDIRECT_BLOCKED"
        | "PRODUCTION_BLOCKED"
        | "CONFIGURATION_ERROR";
      safeMessage: string;
      requestId: string;
    };

export interface AlanubeHttpTransport {
  execute(request: AlanubeSafeRequest): Promise<AlanubeTransportResult>;
}
