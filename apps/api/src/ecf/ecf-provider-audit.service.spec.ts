import { EcfProviderAuditService } from "./ecf-provider-audit.service";

describe("EcfProviderAuditService", () => {
  it("redacts secrets, authorization and payload-like fields", () => {
    const service = new EcfProviderAuditService();
    const sanitized = service.sanitize({
      companyId: "company-a",
      operation: "SEND_TO_PROVIDER",
      environment: "SANDBOX",
      correlationId: "corr-1",
      result: "BLOCKED",
      authorizationState: "BLOCKED",
      metadata: {
        Authorization: "Bearer secret",
        token: "secret",
        requestPayload: { customer: "Cliente" },
        safe: "ok",
      },
    });
    expect(sanitized.metadata).toEqual({
      Authorization: "[REDACTED]",
      token: "[REDACTED]",
      requestPayload: "[REDACTED]",
      safe: "ok",
    });
  });
});
