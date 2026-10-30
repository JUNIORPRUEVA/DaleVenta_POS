import { ALANUBE_DOM_ENDPOINTS } from "./alanube/alanube-contract-matrix";
import { ALANUBE_OFFICIAL_REQUIRED_FIELDS } from "./alanube/alanube-official-required-fields";
import { ALANUBE_DOM_SCHEMAS } from "./alanube/contracts/alanube-dom-schemas.generated";

export type EcfContractApprovalStatus =
  | "CONFIRMED_OFFICIAL"
  | "PARTIAL_OFFICIAL"
  | "UNVERIFIED"
  | "BLOCKED_PENDING_PROVIDER";

export type EcfContractRegistryEntry = {
  provider: "ALANUBE";
  country: "DO";
  version: string;
  schemaSha256: string;
  documentType: "E31" | "E32" | "E34";
  source: string;
  verifiedOn: string;
  endpoint: string;
  queryEndpoint: string;
  fieldEvidence: Array<{ field: string; status: EcfContractApprovalStatus; source: string }>;
  confirmedFields: string[];
  pendingFields: string[];
  status: EcfContractApprovalStatus;
};

const VERIFIED_ON = "2026-10-14";

export const ECF_ALANUBE_CONTRACT_REGISTRY: EcfContractRegistryEntry[] =
  ALANUBE_DOM_ENDPOINTS.map((endpoint) => ({
    provider: "ALANUBE",
    country: "DO",
    version: "public-embedded-openapi-3.0.3-2026-10-14",
    schemaSha256: ALANUBE_DOM_SCHEMAS[endpoint.documentType].schemaSha256,
    documentType: endpoint.documentType,
    source: `https://developer.alanube.co/reference/${sourceSlug(endpoint.documentType)}`,
    verifiedOn: VERIFIED_ON,
    endpoint: endpoint.alanubePath,
    queryEndpoint: `${endpoint.alanubePath}/{id}`,
    fieldEvidence: [
      ...["idDoc", "sender", "totals", "itemDetails", "itemDetails.lineNumber",
        "itemDetails.billingIndicator", "itemDetails.itemName", "itemDetails.goodServiceIndicator",
        "itemDetails.quantityItem", "itemDetails.unitPriceItem", "itemDetails.itemAmount"].map((field) => ({
          field, status: "CONFIRMED_OFFICIAL" as const,
          source: `https://developer.alanube.co/reference/${sourceSlug(endpoint.documentType)}`,
        })),
      { field: "buyer", status: "PARTIAL_OFFICIAL", source: `https://developer.alanube.co/reference/${sourceSlug(endpoint.documentType)}` },
      ...ALANUBE_OFFICIAL_REQUIRED_FIELDS[endpoint.documentType].map((field) => ({ field,
        status: "CONFIRMED_OFFICIAL" as const, source: `https://developer.alanube.co/reference/${sourceSlug(endpoint.documentType)}` })),
      ...["idDoc.type", "sender.legalName", "sender.taxId", "buyer.taxId",
        "informationReference.originalENcf"].map((field) => ({ field, status: "UNVERIFIED" as const, source: "removed legacy aliases; not serialized by current mapper" })),
      ...["providerIdempotency", "webhookSignature", "responseStatusMapping"].map((field) => ({
        field, status: "BLOCKED_PENDING_PROVIDER" as const, source: "provider confirmation required",
      })),
    ],
    confirmedFields: [
      "idDoc",
      "sender",
      "buyer",
      "totals",
      "itemDetails",
      "itemDetails.lineNumber",
      "itemDetails.billingIndicator",
      "itemDetails.itemName",
      "itemDetails.goodServiceIndicator",
      "itemDetails.quantityItem",
      "itemDetails.unitPriceItem",
      "itemDetails.itemAmount",
    ],
    pendingFields: [
      "conditional fiscal semantics beyond supported DOP subset and original-document balance evidence",
      "provider/DGII state interpretation and reconciliation guarantees",
      "provider idempotency contract",
      "webhook signature contract",
      "official certification flow contract",
    ],
    status: "PARTIAL_OFFICIAL",
  }));

export function contractAllowsEmission(documentType: "E31" | "E32" | "E34") {
  const entry = ECF_ALANUBE_CONTRACT_REGISTRY.find((item) => item.documentType === documentType);
  return entry?.status === "CONFIRMED_OFFICIAL";
}

function sourceSlug(type: "E31" | "E32" | "E34") {
  if (type === "E31") return "createinvoicefiscals";
  if (type === "E32") return "createinvoices";
  return "createcreditnotes";
}
