import type { EcfDocumentType } from "../fiscal-core/ecf-fiscal-document";
import { ALANUBE_DOM_SCHEMAS } from "./contracts/alanube-dom-schemas.generated";

// Confirmed 2026-10-14 in document.api.schema embedded by the public DOM docs.
// This checks required-field presence only, NOT full JSON Schema/conditional rules.
export const ALANUBE_OFFICIAL_REQUIRED_FIELDS: Record<EcfDocumentType, readonly string[]> = {
  E31: requiredFields(ALANUBE_DOM_SCHEMAS.E31.request),
  E32: requiredFields(ALANUBE_DOM_SCHEMAS.E32.request),
  E34: requiredFields(ALANUBE_DOM_SCHEMAS.E34.request),
};

function requiredFields(schema: Record<string, unknown>, prefix = ""): string[] {
  const properties = schema.properties as Record<string, Record<string, unknown>> | undefined;
  return ((schema.required ?? []) as string[]).flatMap((name) => {
    const field = prefix ? `${prefix}.${name}` : name;
    const child = properties?.[name];
    return child?.type === "object" ? requiredFields(child, field) : [field];
  });
}

export function missingAlanubeOfficialRequiredFields(type: EcfDocumentType, payload: unknown): string[] {
  return ALANUBE_OFFICIAL_REQUIRED_FIELDS[type].filter((path) => {
    const value = path.split(".").reduce<unknown>((node, key) =>
      node && typeof node === "object" ? (node as Record<string, unknown>)[key] : undefined, payload);
    return value === undefined || value === null || value === "" || (Array.isArray(value) && value.length === 0);
  });
}
