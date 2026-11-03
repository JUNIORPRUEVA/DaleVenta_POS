/**
 * Vinculación multiempresa FullPOS → RNC → postulación DOSA → credenciales.
 *
 * Reglas que este módulo hace cumplir, y que son las que impiden que una empresa
 * facture con la identidad de otra:
 *
 * 1. **La vinculación vive en el servidor.** El emparejamiento RNC ↔ empresa se
 *    guarda en base de datos; aquí solo se resuelve. Nunca se acepta un
 *    `companyId` que venga del cliente ni del cuerpo del evento.
 * 2. **Sin coincidencia no hay empresa.** Un RNC desconocido NO cae en una
 *    empresa "por defecto": devuelve `UNKNOWN_RNC`.
 * 3. **Sin ambigüedad.** Dos empresas con el mismo RNC bloquean la resolución en
 *    lugar de elegir una.
 * 4. **La cuenta Partner no sustituye la identidad fiscal del cliente.** El RNC
 *    del partner (FULLTECH) no es la identidad de facturación de ninguna
 *    empresa; por eso la resolución exige el RNC propio de la empresa.
 * 5. **Entornos separados.** Una vinculación de pruebas no puede operar con
 *    credenciales de producción ni al revés.
 *
 * Nada de esto lee secretos: las credenciales se resuelven por referencia en el
 * backend (`ecf-secret-resolver.service.ts`) y nunca viajan al cliente.
 */

export type DosaEnvironment = "test" | "production";

/** Vinculación tal como debe estar almacenada server-side. */
export type DosaCompanyBinding = {
  companyId: string;
  /** RNC propio de la EMPRESA (identidad fiscal del cliente). */
  companyTaxId: string;
  /** RNC con el que el proveedor identificó a esta empresa. */
  providerRnc: string | null;
  environment: DosaEnvironment;
};

export type DosaLinkRejectionCode =
  | "MISSING_RNC"
  | "UNKNOWN_RNC"
  | "AMBIGUOUS_RNC"
  | "IDENTITY_MISMATCH"
  | "ENVIRONMENT_MISMATCH";

export type DosaLinkResult =
  | { ok: true; companyId: string }
  | { ok: false; reason: DosaLinkRejectionCode };

/**
 * Normaliza un RNC para comparar. Solo quita separadores y espacios: no inventa
 * reglas de formato ni completa dígitos.
 */
export function normalizeRnc(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
  return cleaned.length > 0 ? cleaned : null;
}

/**
 * Resuelve la empresa dueña de un evento a partir del RNC del evento.
 *
 * `bindings` es la lista de vinculaciones YA almacenadas en el servidor para el
 * entorno en curso. El evento nunca aporta `companyId`.
 */
export function resolveLinkedCompany(
  bindings: readonly DosaCompanyBinding[],
  eventRnc: string | null | undefined,
  environment: DosaEnvironment,
): DosaLinkResult {
  const rnc = normalizeRnc(eventRnc);
  if (!rnc) return { ok: false, reason: "MISSING_RNC" };

  const matches = bindings.filter((binding) => {
    if (binding.environment !== environment) return false;
    const providerRnc = normalizeRnc(binding.providerRnc);
    return providerRnc !== null && providerRnc === rnc;
  });

  if (matches.length === 0) return { ok: false, reason: "UNKNOWN_RNC" };
  // Dos vinculaciones activas con el mismo RNC es un error de datos, no algo
  // que deba resolverse "eligiendo la primera".
  if (matches.length > 1) return { ok: false, reason: "AMBIGUOUS_RNC" };

  const binding = matches[0];
  const companyTaxId = normalizeRnc(binding.companyTaxId);
  if (companyTaxId === null || companyTaxId !== rnc) {
    // La vinculación dice ser de un RNC que no es el fiscal de la empresa:
    // se bloquea antes de emitir nada con una identidad equivocada.
    return { ok: false, reason: "IDENTITY_MISMATCH" };
  }

  return { ok: true, companyId: binding.companyId };
}

/**
 * Comprueba que la credencial y el entorno coinciden.
 *
 * Impide reutilizar una clave de TEST para un flujo de producción (y al revés),
 * que es la forma más sencilla de acabar facturando con datos de prueba.
 */
export function assertEnvironmentIsolation(
  binding: DosaCompanyBinding,
  credentialEnvironment: DosaEnvironment,
): { ok: true } | { ok: false; reason: DosaLinkRejectionCode } {
  if (binding.environment !== credentialEnvironment) {
    return { ok: false, reason: "ENVIRONMENT_MISMATCH" };
  }
  return { ok: true };
}

/**
 * Clave de deduplicación de un evento.
 *
 * Se compone SIEMPRE con el `companyId`, de modo que un `eventId` repetido
 * enviado a otra empresa no puede "colisionar" ni bloquear el evento legítimo de
 * esa otra empresa. La unicidad real se impone en base de datos con un índice
 * único `(companyId, eventId)` cuando exista la tabla.
 */
export function eventDedupeKey(companyId: string, eventId: string): string {
  return `dosa:${companyId}:${eventId}`;
}
