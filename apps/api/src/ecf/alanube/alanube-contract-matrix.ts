export type AlanubeContractConfidence =
  | "CONFIRMED_PUBLIC_DOC"
  | "PARTIAL_PUBLIC_DOC"
  | "BLOCKED_PENDING_SCHEMA";

export type AlanubeContractEndpoint = {
  documentType: "E31" | "E32" | "E34";
  alanubePath: "/fiscal-invoices" | "/invoices" | "/credit-notes";
  method: "POST";
  authentication: "JWT_BEARER_TOKEN";
  confidence: AlanubeContractConfidence;
  notes: string[];
};

export const ALANUBE_DOM_SANDBOX_BASE_URL =
  "https://sandbox.alanube.co/dom/v1";

export const ALANUBE_DOM_PRODUCTION_BASE_URL =
  "https://api.alanube.co/dom/v1";

export const ALANUBE_AUTH_CONTRACT = {
  scheme: "JWT_BEARER_TOKEN",
  header: "Authorization",
  valueFormat: "Bearer <token>",
  tokenSource: "ALANUBE_TOKEN_SECRET_REF",
  confidence: "CONFIRMED_PUBLIC_DOC" as const,
  warning:
    "No se ejecuta autenticación real en esta fase; el token no debe registrarse ni exponerse.",
};

export const ALANUBE_DOM_ENDPOINTS: AlanubeContractEndpoint[] = [
  {
    documentType: "E31",
    alanubePath: "/fiscal-invoices",
    method: "POST",
    authentication: "JWT_BEARER_TOKEN",
    confidence: "CONFIRMED_PUBLIC_DOC",
    notes: ["Factura fiscal electrónica E31."],
  },
  {
    documentType: "E32",
    alanubePath: "/invoices",
    method: "POST",
    authentication: "JWT_BEARER_TOKEN",
    confidence: "CONFIRMED_PUBLIC_DOC",
    notes: ["Factura de consumo electrónica E32."],
  },
  {
    documentType: "E34",
    alanubePath: "/credit-notes",
    method: "POST",
    authentication: "JWT_BEARER_TOKEN",
    confidence: "CONFIRMED_PUBLIC_DOC",
    notes: ["Nota de crédito electrónica E34."],
  },
];

export const ALANUBE_CONTRACT_BLOCKERS = [
  "OpenAPI/JSON Schema DOM fijado por hash; semántica fiscal condicional completa pendiente.",
  "Interpretación fiscal de estados y conciliación pendientes de evidencia completa.",
  "Soporte de idempotencia proveedor pendiente de confirmación.",
  "Firma/replay webhook, límites de tasa y garantías de consulta/conciliación pendientes.",
];
