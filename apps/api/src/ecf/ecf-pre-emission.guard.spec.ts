import { assertEcfPreEmissionReady, type EcfPreEmissionInput } from "./ecf-pre-emission.guard";
import { ALANUBE_CONTRACT_FIXTURES } from "./alanube/alanube-contract.fixtures";
import { mapEcfToAlanubeDom } from "./fiscal-core/alanube-dom.mapper";
import { fingerprint } from "./documents/ecf-document-idempotency.service";

const companyId = "00000000-0000-4000-8000-000000000001";
function input(): EcfPreEmissionInput {
  const fixture = ALANUBE_CONTRACT_FIXTURES[0];
  const configuredProviderCompanyId = "01FVJ1528AQRBC7D6K2TGVE5S5";
  const mapping = mapEcfToAlanubeDom(fixture.document, { ...fixture.metadata, alanubeCompanyId: configuredProviderCompanyId });
  return { companyId, authenticatedCompanyId: companyId, documentCompanyId: companyId,
    companyTaxId: fixture.document.sender.taxId, configuredProviderCompanyId, userHasPermission: true,
    authorizationGranted: true, environment: "SANDBOX", canEmit: true,
    certificationStatus: "AUTHORIZED_SANDBOX", documentStatus: "READY_TO_SEND",
    document: fixture.document, expectedFingerprint: fingerprint(fixture.document),
    expectedPayloadFingerprint: fingerprint(mapping.payload),
    idempotencyKey: `ecf:v2:${companyId}:E31:REQUEST:00000000-0000-4000-8000-000000000123`, mapping };
}

describe("assertEcfPreEmissionReady", () => {
  it("blocks global emission disabled", () => {
    expect(assertEcfPreEmissionReady({ ...input(), canEmit: false })).toMatchObject({ ok: false, code: "ECF_EMISSION_DISABLED" });
  });

  it.each(["BLOCKED_PENDING_SCHEMA", "CONFIRMED_PARTIAL", "CONFIRMED_OFFICIAL"] as const)("never trusts mapping label %s without registry approval", (contractStatus) => {
    const request = input();
    expect(assertEcfPreEmissionReady({ ...request, mapping: { ...request.mapping, contractStatus } }))
      .toMatchObject({ ok: false, code: "ECF_CONTRACT_BLOCKED" });
  });

  it.each([
    ["environment", "PRODUCTION", "ECF_ENVIRONMENT_BLOCKED"],
    ["environment", undefined, "ECF_ENVIRONMENT_BLOCKED"],
    ["authenticatedCompanyId", "other-company", "ECF_TENANT_MISMATCH"],
    ["documentCompanyId", "other-company", "ECF_TENANT_MISMATCH"],
    ["companyTaxId", "000000000", "ECF_TENANT_MISMATCH"],
    ["configuredProviderCompanyId", undefined, "ECF_TENANT_MISMATCH"],
    ["userHasPermission", false, "ECF_AUTHORIZATION_REQUIRED"],
    ["authorizationGranted", false, "ECF_AUTHORIZATION_REQUIRED"],
    ["certificationStatus", "NOT_STARTED", "ECF_CERTIFICATION_REQUIRED"],
    ["documentStatus", "UNKNOWN_RESULT", "ECF_DOCUMENT_NOT_READY"],
    ["idempotencyKey", "legacy-key", "ECF_OPERATION_IDENTITY_MISMATCH"],
    ["expectedFingerprint", "changed", "ECF_OPERATION_IDENTITY_MISMATCH"],
    ["expectedPayloadFingerprint", "changed", "ECF_OPERATION_IDENTITY_MISMATCH"],
  ])("rejects unverified %s", (field, value, code) => {
    expect(assertEcfPreEmissionReady({ ...input(), [field as string]: value })).toMatchObject({ ok: false, code });
  });

  it("revalidates payload rather than trusting a previous validation object", () => {
    const request = input();
    request.mapping.payload.idDoc.encf = "invalid";
    request.expectedPayloadFingerprint = fingerprint(request.mapping.payload);
    expect(request.mapping.schemaValidation?.ok).toBe(true);
    expect(assertEcfPreEmissionReady(request)).toMatchObject({ ok: false, code: "ECF_PAYLOAD_INVALID" });
  });

  it("rejects document type mismatch", () => {
    const request = input();
    request.mapping.kind = "invoices";
    expect(assertEcfPreEmissionReady(request)).toMatchObject({ ok: false, code: "ECF_DOCUMENT_TYPE_MISMATCH" });
  });

  it("keeps E34 issuance blocked independently of a claimed complete mapping", () => {
    const fixture = ALANUBE_CONTRACT_FIXTURES[4];
    const mapping = mapEcfToAlanubeDom(fixture.document, fixture.metadata);
    mapping.contractStatus = "CONFIRMED_OFFICIAL";
    expect(assertEcfPreEmissionReady({ ...input(), document: fixture.document, mapping }))
      .toMatchObject({ ok: false, code: "ECF_E34_ISSUANCE_BLOCKED" });
  });
});
