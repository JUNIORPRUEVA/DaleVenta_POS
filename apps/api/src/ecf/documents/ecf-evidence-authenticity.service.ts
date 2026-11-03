import { Injectable } from "@nestjs/common";
import { EcfEvidenceAuthenticityVerifier, type AuthenticityDecision, type EvidenceSource } from "./ecf-evidence.policy";

@Injectable()
export class EcfBlockedAuthenticityVerifier extends EcfEvidenceAuthenticityVerifier {
  async verify(_bytes: Buffer, _source: EvidenceSource): Promise<AuthenticityDecision> {
    // No official signature algorithm, headers or query guarantees are assumed.
    return { authenticated: false, contractScope: "UNAVAILABLE" };
  }
}
