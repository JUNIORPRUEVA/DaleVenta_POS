export type EcfQueueDecision =
  | { enqueue: true; reason: string }
  | { enqueue: false; reason: string };

export function decideEcfQueue(input: {
  emissionEnabled: boolean;
  canEmit: boolean;
  status: string;
}): EcfQueueDecision {
  if (!input.emissionEnabled) return { enqueue: false, reason: "EMISSION_DISABLED" };
  if (!input.canEmit) return { enqueue: false, reason: "PRE_EMISSION_BLOCKED" };
  if (input.status !== "READY_TO_SEND") return { enqueue: false, reason: "DOCUMENT_NOT_READY" };
  return { enqueue: true, reason: "READY" };
}
