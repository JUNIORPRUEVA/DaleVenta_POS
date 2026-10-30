import { AlanubeReconciliationService } from "./alanube-reconciliation.service";

describe("AlanubeReconciliationService", () => {
  it("blocks provider queries until an official query contract exists", () => {
    const service = new AlanubeReconciliationService();

    expect(
      service.planFor({
        status: "UNKNOWN_RESULT",
        externalProviderId: "provider-id",
      }),
    ).toEqual(
      expect.objectContaining({
        canQueryProvider: false,
        canUpdateFiscalStatus: false,
        nextAction: "WAIT_FOR_OFFICIAL_QUERY_CONTRACT",
      }),
    );
  });
});
