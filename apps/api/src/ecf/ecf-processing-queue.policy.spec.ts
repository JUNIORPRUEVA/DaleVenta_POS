import { decideEcfQueue } from "./ecf-processing-queue.policy";

describe("decideEcfQueue", () => {
  it("does not enqueue when emission is disabled", () => {
    expect(decideEcfQueue({ emissionEnabled: false, canEmit: true, status: "READY_TO_SEND" })).toEqual({
      enqueue: false,
      reason: "EMISSION_DISABLED",
    });
  });
});
