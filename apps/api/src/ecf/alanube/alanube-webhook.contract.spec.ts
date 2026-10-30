import {
  ALANUBE_WEBHOOK_CONTRACT_STATUS,
  validateAlanubeWebhookEnvelope,
} from "./alanube-webhook.contract";

describe("Alanube webhook contract placeholder", () => {
  it("keeps public webhook processing blocked until signature contract is official", () => {
    expect(ALANUBE_WEBHOOK_CONTRACT_STATUS).toBe(
      "BLOCKED_PENDING_OFFICIAL_SIGNATURE_CONTRACT",
    );
  });

  it("validates mock envelopes without trusting them as authenticated events", () => {
    expect(
      validateAlanubeWebhookEnvelope({
        provider: "ALANUBE",
        eventId: "evt-1",
        eventType: "document.updated",
        payload: {},
      }),
    ).toEqual(expect.objectContaining({ ok: true }));
  });
});
