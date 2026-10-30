import { assessAlanubeDomE32Compatibility as assess, prepareE32CompatibilityReconciliationPlan as plan, type E32CompatibilityContext } from "./alanube-dom-e32-compatibility";

// Sanitized GET fixture: the three real wire variants, with synthetic identity.
const context: E32CompatibilityContext = { provider:"ALANUBE_DOM", environment:"SANDBOX", endpoint:"GET_E32_TOKEN_PRIMARY",
  companyId:"synthetic-a", verifiedCompanyId:"synthetic-a", operationId:"synthetic-operation", remoteId:"01FVJ1528AQRBC7D6K2TGVE5S5",
  encf:"E320000000001",rnc:"101000001",issueDate:"2026-10-14",totalAmount:168,expectedLegalStatus:"ACCEPTED",expectedSequenceConsumed:true };
const observed = () => ({ id:context.remoteId,documentNumber:context.encf,companyIdentification:context.rnc,status:"FINISHED",legalStatus:"ACCEPTED",sequenceConsumed:true,
  stampDate:"2026-10-14T00:00:00.000Z",trackId:null,signatureDate:"14-10-2026 16:59:42" });
describe("explicit Alanube DOM Sandbox E32 compatibility",()=>{
  it("preserves the real observed variants, original failure and an unzoned signature without mutating the response",()=>{
    const body=observed(),before=JSON.stringify(body),a=assess(200,body,context);
    expect(a.publishedContract.ok).toBe(false);expect(a.compatibility.ok).toBe(true);
    expect(a.compatibility.rules.map(x=>x.field)).toEqual(["stampDate","signatureDate","trackId"]);
    expect(a.representation).toMatchObject({fiscalIssueDate:"2026-10-14",trackIdAvailable:false,signature:{value:"2026-10-14T16:59:42",timeZone:null,instant:null}});
    expect(JSON.stringify(body)).toBe(before);expect(a.canUpdateFiscalStatus).toBe(false);
  });
  it("accepts the published form without compatibility rules or timezone conversion",()=>{
    const body={...observed(),stampDate:"2026-10-14",trackId:"5dc4ca02-43ea-40aa-a0d1-ebdf1386fedd",signatureDate:"2026-10-14T16:59:42-04:00"};
    const a=assess(200,body,context);expect(a.publishedContract.ok).toBe(true);expect(a.compatibility).toMatchObject({ok:true,rules:[]});
    expect(a.representation.signature?.value).toBe(body.signatureDate);
  });
  it.each([
    {stampDate:"2026-02-30T00:00:00.000Z"},{stampDate:"2025-02-29"},{stampDate:"2026-10-14T01:00:00.000Z"},
    {stampDate:"2026-10-14T00:00:00.000-04:00"},{signatureDate:"31-04-2026 12:00:00"},{signatureDate:"14-10-2026 24:00:00"},
    {signatureDate:"10/11/2026 12:00:00"},{signatureDate:"14-10-2026 16:59"},{signatureDate:"2026-02-30T10:00:00Z"},
    {trackId:"not-a-uuid"},{pdf:null},{id:"01FVJ1528AQRBC7D6K2TGVE5S6"},{documentNumber:"E320000000002"},
    {companyIdentification:"101000002"},{legalStatus:"REJECTED"},{sequenceConsumed:false},{sequenceConsumed:undefined},
    {companyIdentification:undefined},{id:undefined},{stampDate:undefined},{response:[{code:"AEP2006"}]},
  ])("rejects impossible, ambiguous, incomplete or contradictory values %j",change=>{
    expect(assess(200,{...observed(),...change},context).compatibility.ok).toBe(false);
  });
  it("validates Gregorian leap days and rejects invalid seconds",()=>{
    expect(assess(200,{...observed(),stampDate:"2024-02-29T00:00:00.000Z",signatureDate:"29-02-2024 12:00:00"},{...context,issueDate:"2024-02-29"}).compatibility.ok).toBe(true);
    expect(assess(200,{...observed(),signatureDate:"14-10-2026 12:00:60"},context).compatibility.ok).toBe(false);
  });
  it.each([{environment:"PRODUCTION"},{endpoint:"POST_E32"},{verifiedCompanyId:"synthetic-b"},{totalAmount:250000}])("refuses widening operational scope %j",change=>{
    expect(assess(200,observed(),{...context,...change} as E32CompatibilityContext).compatibility.ok).toBe(false);
  });
  it("does not infer acceptance from HTTP",()=>{expect(assess(201,observed(),context).compatibility.ok).toBe(false);expect(assess(200,{},context).compatibility.ok).toBe(false);});
  const input=()=>({companyId:context.companyId,operationId:context.operationId,documentId:"synthetic-document",trialId:"synthetic-trial",remoteId:context.remoteId,encf:context.encf,
    responseSha256:"a".repeat(64),postResponseSha256:"b".repeat(64),manifestFingerprint:"c".repeat(64),payloadFingerprint:"d".repeat(64),documentStatus:"UNKNOWN_RESULT",trialState:"UNKNOWN_RESULT",
    externalProviderId:null,externalDocumentNumber:null,postAttempts:1,dbQueryAttempts:0,evidenceChainVerified:true,encryptedArchiveVerified:true,noConflictingReference:true,assessment:assess(200,observed(),context)});
  it("prepares an idempotent, non-executable review proposal with original contract failures retained",()=>{
    const first=plan(input());expect(first).toEqual(plan(input()));expect(first.result).toBe("READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION");
    expect(first).toMatchObject({canApply:false,canGrantDgiiAcceptance:false,canReleaseSequence:false,proposed:{documentStatus:"HUMAN_REVIEW_REQUIRED",publishedValidation:"OFFICIAL_SCHEMA_INVALID"}});
    expect(first.idempotencyKey).not.toBe(plan({...input(),responseSha256:"e".repeat(64)}).idempotencyKey);
  });
  it.each([{companyId:"synthetic-b"},{operationId:"other-operation"},{evidenceChainVerified:false},{encryptedArchiveVerified:false},{noConflictingReference:false},{postAttempts:2},{trialState:"PREPARED"},{externalProviderId:context.remoteId}])("blocks unsafe plan %j",change=>{
    expect(plan({...input(),...change}).result).toBe("BLOCKED");
  });
});
