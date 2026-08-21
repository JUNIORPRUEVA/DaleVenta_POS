export function normalizeTaxId(input?: string | null): string {
  const raw = (input ?? '').trim();
  if (!raw) return '';
  // RNC / Cédula: keep digits only for consistent matching/dedup.
  return raw.replace(/\D/g, '');
}

export function isLikelyTaxIdSearch(input: string): boolean {
  return normalizeTaxId(input).length >= 6;
}
