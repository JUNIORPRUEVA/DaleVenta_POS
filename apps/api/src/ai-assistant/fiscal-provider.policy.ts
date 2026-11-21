export const FISCAL_PROVIDER_SUPPORT_REPLY = 'Para consultar esa información al equipo de soporte, escribe «Quiero hablar con soporte humano» aquí. Puedo ayudarte con el uso de la facturación electrónica en FullPOS.';

const fold = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

/** Internal integration details are not customer-facing product knowledge. DGII guidance remains allowed. */
export function asksFiscalProvider(text: string): boolean {
  const value = fold(text);
  if (containsFiscalProvider(value)) return true;
  const subject = /proveedor.{0,60}(?:factur|fiscal|electronic|e.?cf|comprobante)|(?:factur|fiscal|e.?cf).{0,60}proveedor/.test(value);
  return subject && /quien|cual|que proveedor|nombre|usan|utiliza|integra|contrata|con que|detras|trabajan|proveedor fiscal\s*\??$/.test(value);
}

export function containsFiscalProvider(text: string): boolean {
  return /\bdosa\b|\bdosainvoice\b|\balanube\b|dosasystem\./i.test(text);
}
