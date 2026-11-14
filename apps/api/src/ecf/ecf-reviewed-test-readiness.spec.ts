import { isClosedReviewedLegacyTest } from "./ecf-reviewed-test-readiness";

const document = () => ({ status: "HUMAN_REVIEW_REQUIRED", sourceType: "MANUAL", sourceId: null,
  payloadFingerprint: "a".repeat(64),
  payloadSummary: { controlledTest: { environment: "TEST", correlated: true, outcome: "ACCEPTED",
    responseSha256: "b".repeat(64), plan: "COMPANY_TEST_REVIEW" } },
  statusLogs: [{ metadata: { environment: "SANDBOX", documentFingerprint: "a".repeat(64),
    evidenceSha256: "b".repeat(64), evidencePlan: "COMPANY_TEST_REVIEW", manifestHash: "c".repeat(64), reviewer: "authorized-review" } }],
});

describe("reviewed legacy TEST production readiness", () => {
  it.each(["ACCEPTED", "CONDITIONALLY_ACCEPTED", "REJECTED"])("recognizes a reviewed terminal %s trial without changing its fiscal status", outcome => {
    const row = document(); row.payloadSummary.controlledTest.outcome = outcome;
    expect(isClosedReviewedLegacyTest(row)).toBe(true);
    expect(row.status).toBe("HUMAN_REVIEW_REQUIRED");
  });
  it("keeps commercial sales and unreviewed/manual pending results blocked", () => {
    expect(isClosedReviewedLegacyTest({ ...document(), sourceType: "SALE" })).toBe(false);
    expect(isClosedReviewedLegacyTest({ ...document(), sourceId: "some-commercial-operation" })).toBe(false);
    expect(isClosedReviewedLegacyTest({ ...document(), statusLogs: [] })).toBe(false);
    for (const status of ["SEND_IN_PROGRESS", "UNKNOWN_RESULT", "DGII_STATUS_PENDING"]) {
      expect(isClosedReviewedLegacyTest({ ...document(), status })).toBe(false);
    }
    const pending = document(); pending.payloadSummary.controlledTest.outcome = "IN_PROCESS";
    expect(isClosedReviewedLegacyTest(pending)).toBe(false);
  });
  it("rejects a review for another fingerprint, response, environment or plan", () => {
    for (const change of [{ documentFingerprint: "d".repeat(64) }, { evidenceSha256: "d".repeat(64) },
      { environment: "PRODUCTION" }, { evidencePlan: "OTHER" }, { manifestHash: "invalid" }, { reviewer: " " }]) {
      const row = document(); Object.assign(row.statusLogs[0].metadata, change);
      expect(isClosedReviewedLegacyTest(row)).toBe(false);
    }
  });
});
