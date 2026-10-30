import { createHash } from "node:crypto";
import { assessE32Response } from "./e32-response-assessment";

// Persist only bounded status/error observations, never XML, URLs, headers or secrets.
function safeText(value: unknown): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  return String(value).slice(0,2000)
    .replace(/Bearer\s+\S+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/gi,"[REDACTED]")
    .replace(/https?:\/\/[^\s"<>]+/gi,"[URL_REDACTED]")
    .replace(/(?:token|password|secret|authorization|api.?key)\s*[:=]\s*[^\s,;}]+/gi,"[CREDENTIAL_REDACTED]")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g,"");
}
function errors(value: unknown, depth=0): unknown {
  if (depth>5 || value == null) return null;
  if (Array.isArray(value)) return value.slice(0,30).map(v=>errors(v,depth+1));
  if (typeof value !== "object") return safeText(value);
  const out: Record<string,unknown>={};
  for (const [k,v] of Object.entries(value)) {
    if (["code","message","codigo","valor","error","statusCode","field","path"].includes(k)) out[k]=safeText(v);
    else if (["value","errors","response","details"].includes(k)) out[k]=errors(v,depth+1);
  }
  return out;
}
export function e32SafeObservation(method: "POST"|"GET", httpStatus: number, body: unknown, raw: Buffer) {
  const r=body && typeof body==="object" && !Array.isArray(body)?body as Record<string,unknown>:{};
  return { observedAtUtc:new Date().toISOString(),method,httpStatus,responseSha256:createHash("sha256").update(raw).digest("hex"),responseBytes:raw.length,
    ...(method === "POST" ? { responseAssessment: assessE32Response(httpStatus, body) } : {}),
    remoteId:typeof r.id==="string" && /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(r.id)?r.id:null,
    providerStatus:safeText(r.status),legalStatus:safeText(r.legalStatus),
    sequenceConsumed:typeof r.sequenceConsumed==="boolean"?r.sequenceConsumed:null,
    documentNumber:typeof r.documentNumber==="string" && /^E32\d{10}$/.test(r.documentNumber)?r.documentNumber:null,
    governmentResponse:errors(r.governmentResponse),response:errors(r.response),errors:errors(r.errors),
    code:safeText(r.code),message:errors(r.message),error:safeText(r.error),errorMessage:safeText(r.errorMessage) };
}
