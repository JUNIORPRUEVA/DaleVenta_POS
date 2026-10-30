import { canTransitionEcfDocument } from "./ecf-document-state-machine";

describe("ecf document state machine", () => {
  it("allows the local preparation path", () => {
    expect(canTransitionEcfDocument("LOCAL_DRAFT", "LOCAL_VALIDATED")).toEqual({
      ok: true,
    });
    expect(canTransitionEcfDocument("LOCAL_VALIDATED", "READY_TO_SEND")).toEqual({
      ok: true,
    });
  });

  it("blocks arbitrary fiscal acceptance without provider/DGII path", () => {
    expect(canTransitionEcfDocument("LOCAL_VALIDATED", "DGII_ACCEPTED")).toEqual(
      expect.objectContaining({
        ok: false,
        code: "ECF_INVALID_STATUS_TRANSITION",
      }),
    );
  });

  it("requires evidence for provider or DGII final states", () => {
    expect(canTransitionEcfDocument("SEND_IN_PROGRESS", "PROVIDER_ACCEPTED")).toEqual(
      expect.objectContaining({
        ok: false,
        code: "ECF_STATUS_EVIDENCE_REQUIRED",
      }),
    );
    expect(
      canTransitionEcfDocument("SEND_IN_PROGRESS", "PROVIDER_ACCEPTED", {
        hasEvidence: true,
      }),
    ).toEqual({ ok: true });
  });

  it("prevents changes after cancellation", () => {
    expect(canTransitionEcfDocument("CANCELLED", "LOCAL_DRAFT")).toEqual(
      expect.objectContaining({
        ok: false,
      }),
    );
  });

  it("never auto-promotes an unresolved or human-review document into fiscal acceptance", () => {
    for (const from of ["UNKNOWN_RESULT", "HUMAN_REVIEW_REQUIRED"] as const) {
      for (const to of ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] as const) {
        expect(canTransitionEcfDocument(from, to).ok).toBe(false);
      }
    }
    expect(canTransitionEcfDocument("UNKNOWN_RESULT", "DGII_ACCEPTED")).toEqual(
      expect.objectContaining({ code: "ECF_INVALID_STATUS_TRANSITION" }),
    );
    // A verified provider path still requires explicit evidence, never an implicit promotion.
    expect(canTransitionEcfDocument("UNKNOWN_RESULT", "PROVIDER_ACCEPTED", { hasEvidence: true })).toEqual({ ok: true });
    expect(canTransitionEcfDocument("HUMAN_REVIEW_REQUIRED", "CANCELLED")).toEqual({ ok: true });
  });
});
