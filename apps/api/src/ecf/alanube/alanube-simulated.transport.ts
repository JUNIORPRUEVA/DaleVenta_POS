import type {
  AlanubeHttpTransport,
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "./alanube-safe-http.types";

export class AlanubeSimulatedTransport implements AlanubeHttpTransport {
  readonly calls: AlanubeSafeRequest[] = [];

  constructor(
    private readonly response: AlanubeTransportResult = {
      ok: false,
      errorCode: "REAL_CALLS_DISABLED",
      safeMessage: "Las llamadas reales a Alanube están deshabilitadas.",
      requestId: "simulated",
    },
  ) {}

  async execute(request: AlanubeSafeRequest): Promise<AlanubeTransportResult> {
    this.calls.push({
      ...request,
      headers: redactHeaders(request.headers),
      body: "[REDACTED]",
    });
    if (!this.response.ok) {
      return { ...this.response, requestId: request.requestId };
    }
    return {
      ok: true,
      response: { ...this.response.response, requestId: request.requestId },
    };
  }
}

function redactHeaders(headers: Record<string, string>) {
  const copy = { ...headers };
  for (const key of Object.keys(copy)) {
    if (key.toLowerCase() === "authorization") {
      copy[key] = "[REDACTED]";
    }
  }
  return copy;
}
