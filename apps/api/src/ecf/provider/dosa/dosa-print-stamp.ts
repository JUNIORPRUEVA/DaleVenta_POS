import { classifyDosaResponse } from "./dosa-response.mapper";

/** Public RI fields only. Never expose the provider response or credentials. */
export function dosaPrintStamp(body: unknown, expected: {
  encf: string; rnc: string; environment: "SANDBOX" | "PRODUCTION";
  total: string; buyerRnc?: string; issueDate: string;
  allowContingency?: boolean;
}) {
  const result = classifyDosaResponse(body);
  const qr = result.qr;
  const data = body && typeof body === "object" ? body as Record<string, unknown> : {};
  const legend = typeof data.leyendaContingencia === "string" ? data.leyendaContingencia.trim().replace(/\s+/g, " ") : "";
  const contingency = expected.allowContingency === true && result.outcome === "IN_PROCESS" && legend.length > 0 && legend.length <= 240;
  if ((!contingency && !["ACCEPTED", "CONDITIONALLY_ACCEPTED"].includes(result.outcome)) || result.secuenciaUtilizada !== true ||
      !qr?.complete || qr.encf !== expected.encf || qr.rnc !== expected.rnc ||
      !qr.consultaUrl || !qr.codigoSeguridad || !qr.fechaFirma ||
      !/^[A-Za-z0-9+/]{6}$/.test(qr.codigoSeguridad) ||
      !/^\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}$/.test(qr.fechaFirma)) return null;
  try {
    const url = new URL(qr.consultaUrl);
    const query = new Map([...url.searchParams].map(([key, value]) => [key.toLowerCase(), value]));
    const consumer = expected.encf.startsWith("E32") && Number(expected.total) < 250000;
    const path = `/${expected.environment === "SANDBOX" ? "testecf" : "ecf"}/${consumer ? "consultatimbrefc" : "consultatimbre"}`;
    if (url.protocol !== "https:" || url.username || url.password || url.port || url.hash ||
        url.hostname !== (consumer ? "fc.dgii.gov.do" : "ecf.dgii.gov.do") ||
        url.pathname.toLowerCase() !== path ||
        query.get("rncemisor") !== expected.rnc || query.get("encf") !== expected.encf ||
        query.get("codigoseguridad") !== qr.codigoSeguridad ||
        !query.has("montototal") || !Number.isFinite(Number(query.get("montototal"))) ||
        Number(query.get("montototal")) !== Number(expected.total)) return null;
    const [year, month, day] = expected.issueDate.slice(0, 10).split("-");
    // Real DOSA RFCE URLs may also include these two dates. They are optional
    // for RFCE, but when supplied they must match the frozen fiscal identity.
    if ((!consumer || query.has("fechafirma")) && query.get("fechafirma") !== qr.fechaFirma) return null;
    if ((!consumer || query.has("fechaemision")) && query.get("fechaemision") !== `${day}-${month}-${year}`) return null;
    if (!consumer && expected.buyerRnc && query.get("rnccomprador") !== expected.buyerRnc) return null;
    const allowed = new Set(["rncemisor", "encf", "montototal", "codigoseguridad", "fechaemision", "fechafirma", ...(!consumer ? ["rnccomprador"] : [])]);
    if ([...query.keys()].some(key => !allowed.has(key)) || query.size !== [...url.searchParams].length) return null;
    return { qrUrl: url.toString(), securityCode: qr.codigoSeguridad, signedAt: qr.fechaFirma,
      ...(contingency ? { contingencyLegend: legend } : {}) };
  } catch { return null; }
}
