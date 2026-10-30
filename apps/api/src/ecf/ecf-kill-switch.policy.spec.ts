import {
  assertEcfCanEmit,
  assertEcfCanPrepareProviderCall,
  assertEcfCanRunDiagnostic,
  type EcfKillSwitchInput,
} from "./ecf-kill-switch.policy";

const allowed: EcfKillSwitchInput = {
  environment: "SANDBOX",
  providerTransportEnabled: true,
  realCallsEnabled: true,
  diagnosticEnabled: true,
  emissionEnabled: true,
  companyEcfEnabled: true,
  certificationStatus: "AUTHORIZED_SANDBOX",
  userHasPermission: true,
  contractApproved: true,
};

describe("ECF kill switches", () => {
  it("fails closed for provider calls", () => {
    expect(assertEcfCanPrepareProviderCall({ ...allowed, realCallsEnabled: false })).toEqual(
      expect.objectContaining({ ok: false, code: "ECF_REAL_CALLS_DISABLED" }),
    );
    expect(assertEcfCanPrepareProviderCall({ ...allowed, contractApproved: false })).toEqual(
      expect.objectContaining({ ok: false, code: "ECF_CONTRACT_NOT_APPROVED" }),
    );
  });

  it("requires explicit emission and certification", () => {
    expect(assertEcfCanEmit({ ...allowed, emissionEnabled: false })).toEqual(
      expect.objectContaining({ ok: false, code: "ECF_EMISSION_DISABLED" }),
    );
    expect(assertEcfCanEmit({ ...allowed, certificationStatus: "IN_PROGRESS" })).toEqual(
      expect.objectContaining({ ok: false, code: "ECF_CERTIFICATION_REQUIRED" }),
    );
  });

  it("keeps diagnostics independent from emission", () => {
    expect(assertEcfCanRunDiagnostic({ ...allowed, diagnosticEnabled: false })).toEqual(
      expect.objectContaining({ ok: false, code: "ECF_DIAGNOSTIC_DISABLED" }),
    );
    expect(assertEcfCanRunDiagnostic({ ...allowed, emissionEnabled: false })).toEqual({ ok: true });
  });
});
