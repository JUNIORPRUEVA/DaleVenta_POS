import { ConflictException } from "@nestjs/common";
import { createHash } from "node:crypto";

export const ECF_EVIDENCE_MAX_BYTES = 64 * 1024; // Local intake policy, not an Alanube limit.
export const ECF_EVIDENCE_SOURCES = ["SYNTHETIC", "INTERNAL", "PROVIDER_RESPONSE", "WEBHOOK"] as const;
export type EvidenceSource = typeof ECF_EVIDENCE_SOURCES[number];
export const digestEvidence = (bytes: Buffer | string) => createHash("sha256").update(bytes).digest("hex");
export function evidenceConflict(code: string): never { throw new ConflictException(code); }

export function parseEvidence(bytes: Buffer, expectedHash?: string): Record<string, unknown> {
  if (!Buffer.isBuffer(bytes) || !bytes.length || bytes.length > ECF_EVIDENCE_MAX_BYTES) evidenceConflict("ECF_EVIDENCE_SIZE_INVALID");
  if (expectedHash !== undefined && expectedHash !== digestEvidence(bytes)) evidenceConflict("ECF_EVIDENCE_HASH_MISMATCH");
  if (!Buffer.from(bytes.toString("utf8"), "utf8").equals(bytes)) evidenceConflict("ECF_EVIDENCE_ENCODING_INVALID");
  let parsed: unknown;
  try { parsed = JSON.parse(bytes.toString("utf8")); } catch { evidenceConflict("ECF_EVIDENCE_JSON_INVALID"); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) evidenceConflict("ECF_EVIDENCE_OBJECT_REQUIRED");
  const stack: Array<[unknown, number]> = [[parsed, 0]];
  while (stack.length) {
    const [node, depth] = stack.pop()!;
    if (depth > 32) evidenceConflict("ECF_EVIDENCE_DEPTH_INVALID");
    if (node && typeof node === "object") {
      for (const child of Object.values(node)) stack.push([child, depth + 1]);
    }
  }
  return parsed as Record<string, unknown>;
}

export type AuthenticityDecision = {
  authenticated: boolean;
  contractScope: "UNAVAILABLE" | "TEST_ONLY";
};
// Future official implementations require a separately reviewed contract/version.
// TEST_ONLY can exercise the seam but can never create real fiscal trust.
export abstract class EcfEvidenceAuthenticityVerifier {
  abstract verify(bytes: Buffer, source: EvidenceSource): Promise<AuthenticityDecision>;
}

export function evidenceTrust(source: EvidenceSource, result: AuthenticityDecision) {
  if (result.authenticated && (result.contractScope !== "TEST_ONLY" || source !== "SYNTHETIC")) {
    evidenceConflict("ECF_EVIDENCE_AUTH_CONTRACT_UNAVAILABLE");
  }
  return {
    trustLevel: source === "SYNTHETIC" ? "SYNTHETIC" : source === "INTERNAL" ? "INTERNAL" : "PROVIDER_DECLARED",
    authenticity: result.authenticated ? "TEST_ONLY_AUTHENTICATED" : "BLOCKED_PENDING_PROVIDER_CONTRACT",
  };
}
