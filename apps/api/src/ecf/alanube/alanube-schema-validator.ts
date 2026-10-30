import Ajv, { type ValidateFunction } from "ajv";
import addFormats from "ajv-formats";
import type { EcfDocumentType } from "../fiscal-core/ecf-fiscal-document";
import { ALANUBE_DOM_SCHEMAS } from "./contracts/alanube-dom-schemas.generated";
import { ALANUBE_E32_QUERY } from "./contracts/alanube-e32-query.generated";

export type AlanubeSchemaResult = {
  ok: boolean;
  schemaSha256: string;
  errors: Array<{ path: string; keyword: string }>;
};

// OpenAPI 3.0 uses maxLength on numbers in these public schemas. JSON Schema
// correctly applies it to strings only; strictTypes=false tolerates that source.
// No type coercion, default insertion, property removal or remote schema loading.
const ajv = new Ajv({ allErrors: true, strictSchema: false, strictTypes: false,
  coerceTypes: false, useDefaults: false, removeAdditional: false, multipleOfPrecision: 8 });
addFormats(ajv);
ajv.addFormat("ulid", /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/);
const compiled = new Map<string, ValidateFunction>();

export function validateAlanubeOfficialRequest(type: EcfDocumentType, payload: unknown): AlanubeSchemaResult {
  return validate(type, "request", payload);
}

export function validateAlanubeOfficialResponse(type: EcfDocumentType, status: number, body: unknown): AlanubeSchemaResult {
  return validate(type, String(status), body);
}

export function validateAlanubeE32QueryResponse(status: number, body: unknown): AlanubeSchemaResult {
  const contract = ALANUBE_E32_QUERY.checkinvoicesbycompany;
  const schema = contract.responses[String(status)];
  if (!schema) return { ok: false, schemaSha256: contract.schemaSha256, errors: [{ path: "", keyword: "undocumentedQueryResponse" }] };
  const key = `E32:GET:${status}`;
  let validator = compiled.get(key);
  if (!validator) { validator = ajv.compile(schema); compiled.set(key, validator); }
  const ok = validator(body) as boolean;
  return { ok, schemaSha256: contract.schemaSha256, errors: (validator.errors ?? []).map(error => ({ path: error.instancePath, keyword: error.keyword })) };
}

function validate(type: EcfDocumentType, operation: string, payload: unknown): AlanubeSchemaResult {
  const contract = ALANUBE_DOM_SCHEMAS[type];
  if (!contract) return { ok: false, schemaSha256: "", errors: [{ path: "", keyword: "unknownDocumentType" }] };
  const schema = operation === "request" ? contract.request : contract.responses[operation];
  if (!schema) return { ok: false, schemaSha256: contract.schemaSha256, errors: [{ path: "", keyword: "undocumentedResponse" }] };
  const key = `${type}:${operation}`;
  let validator = compiled.get(key);
  if (!validator) {
    validator = ajv.compile((operation === "request" ? closeRequestObjects(schema) : schema) as Record<string, unknown>);
    compiled.set(key, validator);
  }
  const ok = validator(payload) as boolean;
  return { ok, schemaSha256: contract.schemaSha256, errors: (validator.errors ?? []).map((error) => ({
    path: error.instancePath + (error.keyword === "required" ? `/${error.params.missingProperty}` : ""),
    keyword: error.keyword,
  })) };
}

// Local safety overlay: only documented properties may appear in outgoing data.
// The published source itself is preserved; responses allow provider extensions.
function closeRequestObjects(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(closeRequestObjects);
  if (!value || typeof value !== "object") return value;
  const schema = value as Record<string, unknown>;
  const result = Object.fromEntries(Object.entries(schema).map(([key, node]) => [key, closeRequestObjects(node)]));
  if (schema.type === "object" && schema.properties) result.additionalProperties = false;
  return result;
}
