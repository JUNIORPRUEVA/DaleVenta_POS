import { generateKeyPairSync, sign, verify } from "node:crypto";
import { digestEvidence, ECF_EVIDENCE_MAX_BYTES, EcfEvidenceAuthenticityVerifier, evidenceTrust, parseEvidence } from "./ecf-evidence.policy";
import { EcfBlockedAuthenticityVerifier } from "./ecf-evidence-authenticity.service";
import { validateAlanubeWebhookEnvelope } from "../alanube/alanube-webhook.contract";

describe("Evidence trust boundary (synthetic, not an Alanube authentication contract)", () => {
  it("hashes exact bytes, not parsed/reformatted JSON", () => {
    expect(digestEvidence(Buffer.from('{"a":1}'))).not.toBe(digestEvidence('{ "a":1 }'));
  });
  it.each(["null", "[]", "1", '"string"', "{"])("rejects nonobject/malformed payload %s", (raw) => {
    expect(() => parseEvidence(Buffer.from(raw))).toThrow();
  });
  it("checks size before parse", () => {
    expect(() => parseEvidence(Buffer.alloc(ECF_EVIDENCE_MAX_BYTES + 1))).toThrow("ECF_EVIDENCE_SIZE_INVALID");
  });
  it("detects payload/hash manipulation", () => {
    expect(() => parseEvidence(Buffer.from('{"a":2}'), digestEvidence('{"a":1}'))).toThrow("ECF_EVIDENCE_HASH_MISMATCH");
  });
  it("rejects invalid UTF8", () => {
    expect(() => parseEvidence(Buffer.from([123,34,97,34,58,34,255,34,125]))).toThrow("ECF_EVIDENCE_ENCODING_INVALID");
  });
  it("bounds nested input", () => {
    expect(() => parseEvidence(Buffer.from('{"a":'.repeat(34) + '{}' + '}'.repeat(34)))).toThrow("ECF_EVIDENCE_DEPTH_INVALID");
  });
  it("keeps unavailable authenticity blocked even with a remote identifier", async () => {
    const decision = await new EcfBlockedAuthenticityVerifier().verify(Buffer.from('{"id":"remote"}'), "PROVIDER_RESPONSE");
    expect(evidenceTrust("PROVIDER_RESPONSE", decision)).toEqual({ trustLevel: "PROVIDER_DECLARED", authenticity: "BLOCKED_PENDING_PROVIDER_CONTRACT" });
  });
  it("does not upgrade internal or synthetic evidence", () => {
    const decision = { authenticated: false, contractScope: "UNAVAILABLE" } as const;
    expect(evidenceTrust("SYNTHETIC", decision).trustLevel).toBe("SYNTHETIC");
    expect(evidenceTrust("INTERNAL", decision).trustLevel).toBe("INTERNAL");
  });
  it("exercises real signatures only under an explicitly synthetic test contract", async () => {
    const { privateKey, publicKey } = generateKeyPairSync("ed25519");
    const bytes = Buffer.from('{"test":true}'), signature = sign(null, bytes, privateKey);
    class TestVerifier extends EcfEvidenceAuthenticityVerifier {
      async verify(raw: Buffer) { return { authenticated: verify(null, raw, publicKey, signature), contractScope: "TEST_ONLY" as const }; }
    }
    const verifier = new TestVerifier();
    expect(evidenceTrust("SYNTHETIC", await verifier.verify(bytes))).toEqual({ trustLevel: "SYNTHETIC", authenticity: "TEST_ONLY_AUTHENTICATED" });
    expect((await verifier.verify(Buffer.from('{"test":false}'))).authenticated).toBe(false);
    expect(() => evidenceTrust("WEBHOOK", { authenticated: true, contractScope: "TEST_ONLY" })).toThrow("ECF_EVIDENCE_AUTH_CONTRACT_UNAVAILABLE");
  });
  const base = { provider: "ALANUBE", eventId: "evt-test", eventType: "document.updated", payload: {} };
  it.each([
    { ...base, eventId: "x" }, { ...base, eventType: "x" }, { ...base, payload: [] },
    { ...base, companyId: "forged" }, { ...base, documentExternalId: 123 },
    { ...base, occurredAt: "2026-02-30T00:00:00.000Z" }, { ...base, occurredAt: "bad" },
  ])("rejects malformed local webhook envelopes %#", (input) => {
    expect(validateAlanubeWebhookEnvelope(input).ok).toBe(false);
  });
  it("permits an old wellformed event as quarantined data, not a fiscal transition", () => {
    expect(validateAlanubeWebhookEnvelope({ ...base, occurredAt: "2020-01-01T00:00:00.000Z" }).ok).toBe(true);
  });
});
