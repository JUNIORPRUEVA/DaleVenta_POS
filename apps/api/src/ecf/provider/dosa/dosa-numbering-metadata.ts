/** Untrusted provider evidence only. This never declares/allocates a range. */
export type DosaNumberingMetadata = Record<string, unknown>;

const containers = new Set(["secuencias", "secuencias_test", "secuencias_produccion", "sequences", "numeracion", "rangos", "ranges", "test", "sandbox", "produccion", "production"]);
const fields = new Set(["tipo", "tipo_ecf", "tipoecf", "documenttype", "document_type", "desde", "hasta", "inicio", "fin", "from", "to", "range_from", "range_to", "start", "end", "cantidad", "quantity", "vencimiento", "fecha_vencimiento", "fechavencimientosecuencia", "expires_at", "expiresat", "ambiente", "environment"]);

function leaf(value: unknown): string | number | null {
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) return value;
  if (typeof value !== "string") return null;
  const text = value.trim();
  // Closed scalar grammar excludes arbitrary text and credential material.
  return /^(?:E?(?:31|32|33|34|41|43|44|45|46|47)|\d{1,10}|\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z)?|\d{2}[-/]\d{2}[-/]\d{4}|test|sandbox|produccion|production)$/i.test(text) ? text : null;
}

function project(value: unknown, depth: number): unknown {
  if (depth > 5) return undefined;
  if (Array.isArray(value)) return value.slice(0, 30).map(item => project(item, depth + 1)).filter(item => item !== undefined);
  if (!value || typeof value !== "object") return undefined;
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value).slice(0, 80)) {
    const normalized = key.toLowerCase();
    if (containers.has(normalized) || /^e(?:31|32|33|34|41|43|44|45|46|47)$/i.test(key)) {
      const nested = project(item, depth + 1);
      if (nested !== undefined) out[key] = nested;
    } else if (fields.has(normalized)) {
      const safe = leaf(item);
      if (safe !== null) out[key] = safe;
    }
  }
  return Object.keys(out).length ? out : undefined;
}

export function extractDosaNumberingMetadata(input: unknown): DosaNumberingMetadata | undefined {
  if (!input || typeof input !== "object" || Array.isArray(input)) return undefined;
  const source = input as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(source)) {
    if (!containers.has(key.toLowerCase())) continue;
    const safe = project(value, 0);
    if (safe !== undefined) out[key] = safe;
  }
  return Object.keys(out).length ? out : undefined;
}
