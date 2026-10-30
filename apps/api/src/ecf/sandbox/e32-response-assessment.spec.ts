import { assessE32Response } from "./e32-response-assessment";
import { validateAlanubeOfficialResponse } from "../alanube/alanube-schema-validator";
import type { E32TrialManifest } from "./e32-sandbox.policy";

const manifest = { metadata: { encf: "E320000000001" }, sender: { taxId: "101000001" } } as E32TrialManifest;
const context = { manifest, remoteConflict: false };
const response = () => ({ id: "01FVJ1528AQRBC7D6K2TGVE5S5", documentNumber: manifest.metadata.encf,
  companyIdentification: manifest.sender.taxId, status: "REGISTERED", legalStatus: "ACCEPTED", sequenceConsumed: true });

describe("E32 strict provider observation, without fiscal authority", () => {
  it("permits REGISTERED and ACCEPTED together under the official schema and retains a consumed sequence", () => {
    expect(validateAlanubeOfficialResponse("E32", 201, response()).ok).toBe(true);
    expect(assessE32Response(201, response(), context)).toMatchObject({ correlated: true, providerOutcome: "ACCEPTED",
      sequenceConsumed: true, canRetryPost: false, canUpdateFiscalStatus: false, reasons: [] });
  });
  it("distinguishes observed identity from a validated association", () => {
    expect(assessE32Response(201, response())).toMatchObject({ remoteId: response().id, correlated: false,
      observedOutcome: "ACCEPTED", providerOutcome: "UNKNOWN", safeCode: "E32_CORRELATION_NOT_CHECKED" });
  });
  it.each([
    [{ id: "invalid-id" }, "REMOTE_ID"],
    [{ documentNumber: "E320000000002" }, "NUMBER_MATCH"],
    [{ companyIdentification: "101000002" }, "COMPANY_MATCH"],
    [{ companyIdentification: null }, "OFFICIAL_SCHEMA"],
    [{ sequenceConsumed: "true" }, "OFFICIAL_SCHEMA"],
    [{ stampDate: "not-a-date" }, "OFFICIAL_SCHEMA"],
    [{ sequenceConsumed: false }, "SEQUENCE_CONSISTENT"],
    [{ response: [{ code: "AEP2006", message: "Synthetic delayed transmission" }] }, "RESPONSE_CONSISTENT"],
  ])("rejects invalid or contradictory observations %j", (change, reason) => {
    const out = assessE32Response(201, { ...response(), ...change }, context);
    expect(out.correlated).toBe(false); expect(out.providerOutcome).toBe("UNKNOWN"); expect(out.reasons).toContain(reason);
  });
  it.each([{}, { id: response().id }, { ...response(), sequenceConsumed: undefined }, { ...response(), legalStatus: undefined }])(
    "does not accept incomplete schema-valid responses %j", body => {
      expect(assessE32Response(201, body, context)).toMatchObject({ correlated: false, providerOutcome: "UNKNOWN" });
    });
  it("requires the expected remote id and rejects an existing conflicting association", () => {
    for (const change of [{ remoteConflict: true }, { expectedRemoteId: "01FVJ1528AQRBC7D6K2TGVE5S6" }])
      expect(assessE32Response(201, response(), { ...context, ...change }).reasons).toContain("REMOTE_NOT_CONFLICTING");
  });
  it("records pending or rejected outcomes without inventing fiscal transitions or releasing sequences", () => {
    expect(assessE32Response(201, { ...response(), status: "WAITING_RESPONSE", legalStatus: undefined }, context))
      .toMatchObject({ providerOutcome: "PENDING", canRetryPost: false, sequenceConsumed: true });
    expect(assessE32Response(201, { ...response(), legalStatus: "REJECTED" }, context))
      .toMatchObject({ providerOutcome: "REJECTED", canUpdateFiscalStatus: false, canRetryPost: false });
  });
  it("does not infer acceptance from HTTP and exposes safe exact schema failure paths", () => {
    expect(assessE32Response(200, response(), context).providerOutcome).toBe("UNKNOWN");
    const out = assessE32Response(201, { ...response(), stampDate: null }, context);
    expect(out.schemaErrors).toContainEqual({ path: "/stampDate", keyword: "type" });
    expect(out.schemaSha256).toMatch(/^[a-f0-9]{64}$/);
  });
  it("treats an explicit provider rejection as an observation, never fiscal acceptance or a released sequence", () => {
    const rejected = { ...response(), legalStatus: "REJECTED" };
    expect(assessE32Response(201, rejected, context)).toMatchObject({ correlated: true, observedOutcome: "REJECTED",
      providerOutcome: "REJECTED", observedLegalStatus: "REJECTED", safeCode: "E32_OBSERVED_REJECTED",
      canUpdateFiscalStatus: false, canRetryPost: false, reasons: [] });
    // A rejection may arrive with the sequence unconsumed: it still correlates for human review, never for reissue.
    expect(assessE32Response(201, { ...rejected, sequenceConsumed: false }, context)).toMatchObject({ correlated: true,
      providerOutcome: "REJECTED", sequenceConsumed: false, canRetryPost: false });
    // HTTP status alone never rejects nor accepts.
    expect(assessE32Response(200, rejected, context).providerOutcome).toBe("UNKNOWN");
  });
  it.each([
    ["REGISTERED", "ACCEPTED", "ACCEPTED"],
    ["FINISHED", "ACCEPTED", "ACCEPTED"],
    ["WAITING_RESPONSE", "ACCEPTED", "ACCEPTED"],
    ["FINISHED", "ACCEPTED_WITH_OBSERVATIONS", "ACCEPTED"],
    ["REGISTERED", "REJECTED", "REJECTED"],
    ["TO_SEND", undefined, "PENDING"],
    ["WAITING_RESPONSE", undefined, "PENDING"],
    ["REGISTERED", undefined, "UNKNOWN"],
    ["TO_NOTIFY", undefined, "UNKNOWN"],
    ["FINISHED", undefined, "UNKNOWN"],
  ])("separates operational status %s from legal status %s as %s", (status, legalStatus, expected) => {
    const out = assessE32Response(201, { ...response(), status, legalStatus }, context);
    expect(out.providerOutcome).toBe(expected);
    expect(out.canUpdateFiscalStatus).toBe(false);
    expect(out.canRetryPost).toBe(false);
  });
  it("rejects an operational status outside the official enum instead of observing acceptance", () => {
    const out = assessE32Response(201, { ...response(), status: "INVENTED" }, context);
    expect(out.correlated).toBe(false);
    expect(out.reasons).toContain("OFFICIAL_SCHEMA");
  });
});
