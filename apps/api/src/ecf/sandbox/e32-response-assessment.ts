import { assessEcfProviderResponse, type EcfProviderObservation } from "../documents/ecf-provider-response";
import type { E32TrialManifest } from "./e32-sandbox.policy";

// E32 wrapper over the generic provider observation assessment. Provider
// observations and fiscal authority are separate: this never grants DGII status
// or permission to send/retry a document.
export function assessE32Response(httpStatus: number, body: unknown,
  context?: { manifest: E32TrialManifest; remoteConflict: boolean; expectedRemoteId?: string }): EcfProviderObservation {
  const observation = assessEcfProviderResponse(httpStatus, body, context ? {
    documentType: "E32",
    expectedEncf: context.manifest.metadata.encf,
    expectedTaxId: context.manifest.sender.taxId,
    remoteConflict: context.remoteConflict,
    expectedRemoteId: context.expectedRemoteId,
  } : undefined);
  return { ...observation, safeCode: observation.safeCode.replace(/^ECF_/, "E32_") };
}
