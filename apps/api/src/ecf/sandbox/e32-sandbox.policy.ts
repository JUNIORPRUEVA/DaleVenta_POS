import { Prisma } from "@prisma/client";
import type { EcfParty, EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";
import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";
import { fingerprint } from "../documents/ecf-document-idempotency.service";
import type { AlanubeDomPayloadDraft } from "../fiscal-core/alanube-dom.contract";
import { isEcfLocalTarget } from "../ecf-local-target";

export const E32_SANDBOX_URL = "https://sandbox.alanube.co/dom/v1";
export const E32_SYNTHETIC_ADDRESS = "CALLE PRUEBA 123, HIGUEY, LA ALTAGRACIA, REPUBLICA DOMINICANA";
export function e32FirstTrialTaxConsistent(payload: AlanubeDomPayloadDraft) {
  try {
    const items=payload.itemDetails;
    if(items.length!==2 || items[0].billingIndicator!==1 || items[1].billingIndicator!==4) return false;
    for(const line of items) {
      if(!new Prisma.Decimal(line.quantityItem).eq(1) || !new Prisma.Decimal(line.quantityItem).mul(line.unitPriceItem).toDecimalPlaces(2,Prisma.Decimal.ROUND_HALF_UP).eq(line.itemAmount))return false;
    }
    const taxed=new Prisma.Decimal(items[0].itemAmount),exempt=new Prisma.Decimal(items[1].itemAmount);
    const tax=taxed.mul("0.18").toDecimalPlaces(2,Prisma.Decimal.ROUND_HALF_UP),t=payload.totals;
    return taxed.eq(100)&&exempt.eq(50)&&tax.eq(18)&&new Prisma.Decimal(t.itbisTotal!).eq(tax)&&
      new Prisma.Decimal(t.itbis1Total!).eq(tax)&&new Prisma.Decimal(t.totalTaxedAmount!).eq(taxed)&&
      new Prisma.Decimal(t.i1AmountTaxed!).eq(taxed)&&new Prisma.Decimal(t.itbisS1!).eq(18)&&
      new Prisma.Decimal(t.exemptAmount!).eq(exempt)&&new Prisma.Decimal(t.totalAmount).eq(taxed.plus(exempt).plus(tax));
  } catch {return false;}
}
export function isE32UatTarget(value = process.env.DATABASE_URL ?? "") {
  // Local-only gate: historical UAT or the ephemeral automated-test database.
  // Loopback and exact (name, port) are required, so production/remote can never
  // pass. See ecf-local-target.ts for the strict allowlist.
  return isEcfLocalTarget(value);
}
export type E32TrialManifest = {
  version: 1; mode: "SANDBOX" | "MOCK_ONLY"; clientRequestId: string;
  sender: EcfParty; issueDate: string; metadata: EcfIssuanceMetadata;
  companyTarget?: "TOKEN_PRIMARY" | "ASSOCIATED";
  companyAuthorizationRef: string;
  syntheticAddressTest?: { purpose: "SYNTHETIC_SANDBOX_ONLY"; tenantCompanyId: string; authorizationRef: string; providerVerified: false };
  numbering: { from: string; to: string; validUntil: string; authorizationRef: string };
};
export function requiresSyntheticAddressScope(manifest: E32TrialManifest) {
  return manifest.syntheticAddressTest !== undefined || manifest.sender.address === E32_SYNTHETIC_ADDRESS;
}
export function e32SyntheticAddressAllowed(manifest: E32TrialManifest,
  tenant: {id: string; slug: string; name: string} | null,
  runtime: Record<string, string | undefined>) {
  const selection = manifest.syntheticAddressTest;
  return Boolean(selection && Object.keys(selection).every(k => ["purpose","tenantCompanyId","authorizationRef","providerVerified"].includes(k)) &&
    selection.purpose === "SYNTHETIC_SANDBOX_ONLY" && selection.providerVerified === false &&
    selection.authorizationRef?.trim() && selection.authorizationRef.length <= 256 &&
    tenant?.id === selection.tenantCompanyId && tenant?.slug === "fullpos-alanube-uat-access" &&
    tenant?.name === "SYNTHETIC Fullpos Alanube UAT Access" && manifest.mode === "SANDBOX" &&
    manifest.sender.address === E32_SYNTHETIC_ADDRESS && manifest.sender.taxId === "132109122" &&
    manifest.sender.legalName === "FULLTECH" && manifest.companyTarget === "TOKEN_PRIMARY" &&
    runtime.APP_ENV === "uat" && runtime.UAT_LOCAL_ONLY === "true" && runtime.ALANUBE_ENV === "sandbox" &&
    isE32UatTarget(runtime.DATABASE_URL));
}
// Omission remains associated-company mode for existing manifests. Primary
// company selection must be explicit and must never silently discard an id.
export function e32CompanyTargetValid(manifest: E32TrialManifest) {
  return manifest.companyTarget === "TOKEN_PRIMARY"
    ? manifest.metadata.alanubeCompanyId === undefined
    : (manifest.companyTarget === undefined || manifest.companyTarget === "ASSOCIATED") &&
      typeof manifest.metadata.alanubeCompanyId === "string" && /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(manifest.metadata.alanubeCompanyId);
}
export function e32SandboxCompanyPrepared(config: {
  environment: string; enabled: boolean; productionEnabled: boolean; certificationStatus: string;
  alanubeCompanyId: string | null; allowedTypes: unknown;
} | null, manifest: E32TrialManifest | null) {
  // Preparation for an explicitly consented Sandbox trial is not certification.
  // A blocked onboarding or enabled emitter must not be bypassed by this CLI.
  return Boolean(config && manifest && config.environment === "SANDBOX" && !config.enabled && !config.productionEnabled &&
    ["NOT_STARTED","IN_PROGRESS","AUTHORIZED_SANDBOX"].includes(config.certificationStatus) &&
    e32CompanyTargetValid(manifest) &&
    (manifest.companyTarget === "TOKEN_PRIMARY" ? config.alanubeCompanyId === null : config.alanubeCompanyId === manifest.metadata.alanubeCompanyId) &&
    Array.isArray(config.allowedTypes) && config.allowedTypes.includes("E32"));
}
export function e32ResponseIdentityMatches(value: Record<string, unknown>, manifest: E32TrialManifest) {
  // Official responses may omit companyIdentification. A present contradictory
  // identity is rejected; absence does not authenticate a fiscal status.
  return value.documentNumber === manifest.metadata.encf &&
    (value.companyIdentification === undefined || value.companyIdentification === manifest.sender.taxId);
}
export type E32TrialFacts = {
  worktree: boolean; database: boolean; schema: boolean; company: boolean;
  secretProtected: boolean; secretRefConfigured: boolean; transport: boolean;
  environment: string; baseUrl: string; allSwitchesOff: boolean;
  noPreviousTrial: boolean; noNumberCollision: boolean; actorAuthorized: boolean;
  syntheticAddressAllowed?: boolean;
};

export function firstE32Document(sender: EcfParty, issueDate: string): EcfFiscalDocument {
  return { type: "E32", issueDate, currency: "DOP", sender,
    lines: [
      { lineNumber: 1, name: "ARTICULO SINTETICO PRUEBA SANDBOX", goodServiceIndicator: "GOOD", quantity: "1", unitPrice: "100.00", taxCategory: "ITBIS_18", taxRate: "0.18" },
      { lineNumber: 2, name: "SERVICIO SINTETICO EXENTO SANDBOX", goodServiceIndicator: "SERVICE", quantity: "1", unitPrice: "50.00", taxCategory: "EXEMPT", taxRate: "0" },
    ], totals: { subtotal: "150.00", taxableBase: "100.00", exemptAmount: "50.00", discountAmount: "0.00", itbisAmount: "18.00", total: "168.00" } };
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const encf = /^E32\d{10}$/;
function validDay(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d\d-\d\d$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0,10) === value;
}

// This report NEVER authorizes sending. The external references must be reviewed
// by the operator; their presence is attestation, not provider authentication.
export function e32Preflight(manifest: E32TrialManifest | null, facts: E32TrialFacts, today = new Date().toISOString().slice(0,10)) {
  const checks: Record<string, boolean> = {
    WORKTREE: facts.worktree, UAT_DATABASE: facts.database, PERSISTENCE_SCHEMA: facts.schema,
    SANDBOX_ENVIRONMENT: facts.environment === "sandbox" && facts.baseUrl === E32_SANDBOX_URL,
    SWITCHES_DISABLED: facts.allSwitchesOff, TEST_COMPANY_CONFIRMED: facts.company,
    OPERATOR_CONTEXT: facts.actorAuthorized, SECRET_PROTECTED: facts.secretProtected,
    SECRET_REFERENCE: facts.secretRefConfigured, TRANSPORT_PREPARED: facts.transport,
    SINGLE_TRIAL_UNUSED: facts.noPreviousTrial, NUMBER_UNUSED_LOCALLY: facts.noNumberCollision,
    E32_QUERY_CONTRACT: true, QUARANTINE_EVIDENCE: true, FISCAL_TRANSITIONS_BLOCKED: true,
    USER_AUTHORIZATION_PENDING: true, E32_MANIFEST: false, E32_PAYLOAD: false,
    NUMBERING_AUTHORIZATION: false, OPERATION_IDENTITY: false,
    SYNTHETIC_ADDRESS_SCOPE: !manifest || !requiresSyntheticAddressScope(manifest) || facts.syntheticAddressAllowed === true,
  };
  let mapping: ReturnType<typeof mapEcfToAlanubeDom> | undefined;
  try {
    if (manifest) {
      checks.E32_MANIFEST = manifest.version === 1 && ["SANDBOX", "MOCK_ONLY"].includes(manifest.mode) &&
        validDay(manifest.issueDate) && manifest.issueDate === today && Boolean(manifest.companyAuthorizationRef?.trim());
      const only = (value: object, keys: string[]) => Object.keys(value).every(key => keys.includes(key));
      checks.E32_MANIFEST &&= only(manifest, ["version","mode","clientRequestId","sender","issueDate","metadata","companyTarget","companyAuthorizationRef","numbering","syntheticAddressTest"]) &&
        e32CompanyTargetValid(manifest) &&
        only(manifest.sender, ["legalName","taxId","address","tradeName"]) &&
        only(manifest.metadata, ["alanubeCompanyId","encf","paymentType","incomeType"]) &&
        only(manifest.numbering, ["from","to","validUntil","authorizationRef"]) &&
        manifest.companyAuthorizationRef.length <= 256 && manifest.numbering.authorizationRef.length <= 256;
      checks.OPERATION_IDENTITY = uuid.test(manifest.clientRequestId);
      checks.NUMBERING_AUTHORIZATION = encf.test(manifest.metadata.encf) && encf.test(manifest.numbering.from) && encf.test(manifest.numbering.to) &&
        manifest.metadata.encf >= manifest.numbering.from && manifest.metadata.encf <= manifest.numbering.to &&
        validDay(manifest.numbering.validUntil) && manifest.numbering.validUntil >= today && Boolean(manifest.numbering.authorizationRef?.trim());
      mapping = mapEcfToAlanubeDom(firstE32Document(manifest.sender, manifest.issueDate), manifest.metadata);
      checks.E32_PAYLOAD = mapping.schemaValidation?.ok === true && mapping.kind === "invoices" &&
        e32FirstTrialTaxConsistent(mapping.payload) &&
        typeof manifest.sender.address === "string" && Boolean(manifest.sender.address.trim()) && manifest.sender.address.trim().toLowerCase() !== "address" &&
        manifest.metadata.paymentType === 1 && e32CompanyTargetValid(manifest) &&
        new Prisma.Decimal(mapping.payload.totals.totalAmount).eq("168.00");
    }
  } catch { checks.E32_PAYLOAD = false; }
  return { result: Object.values(checks).every(Boolean) ? "READY_FOR_AUTHORIZATION" as const : "BLOCKED" as const,
    checks, blockers: Object.keys(checks).filter(key => !checks[key]),
    manifestFingerprint: manifest ? fingerprint(manifest) : null,
    payloadFingerprint: mapping ? fingerprint(mapping.payload) : null,
    payload: mapping?.payload ?? null, authorizationGranted: false, authenticatedRequests: 0 };
}
