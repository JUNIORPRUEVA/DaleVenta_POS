import type {
  DosaCredentialBundle,
  DosaCredentialEnvironment,
} from "./dosa-credential-vault.service";

/**
 * Reparto de un paquete de credenciales del proveedor por **ambiente real**.
 *
 * Problema que resuelve
 * ---------------------
 * DOSA entrega las dos claves en un único evento cuyo campo `ambiente` describe
 * la **certificación** de la empresa (p. ej. `Produccion`), no el ambiente de
 * cada clave. Guardar el paquete completo bajo ese `ambiente` dejaba la clave
 * TEST dentro de la fila `production`: la compuerta de emisión en `test` no
 * encontraba fila y la clave quedaba inservible.
 *
 * Regla
 * -----
 * La ubicación de cada clave la decide **su propio nombre**, no el evento:
 *
 * * `apiKeyProduccion` → fila `production`
 * * `apiKeyTest` → fila `test`
 * * `apiSecret` → **una sola fila**, la que declare el evento (o la única que
 *   exista si el evento no declara ninguna). No se copia a los dos ambientes:
 *   compartir un secreto entre entornos es una decisión de contrato del
 *   proveedor que todavía no está validada, y duplicarlo sin necesidad amplía
 *   la superficie de exposición.
 *
 * Un ambiente solo se escribe si trae **su clave identificadora**. Así un
 * evento que solo aporte, por ejemplo, `apiSecret` no puede dejar una fila a
 * medias ni borrar una clave existente: simplemente no toca esa fila.
 *
 * Esta función es pura: no cifra, no accede a base de datos y no registra nada.
 */
export type DosaEnvironmentBundle = {
  environment: DosaCredentialEnvironment;
  bundle: DosaCredentialBundle;
};

/** Motivo por el que un ambiente no se escribió (solo metadatos, sin valores). */
export type DosaSkippedEnvironment = {
  environment: DosaCredentialEnvironment;
  reason: "DEFINING_KEY_ABSENT";
};

export type DosaCredentialSplit = {
  targets: DosaEnvironmentBundle[];
  skipped: DosaSkippedEnvironment[];
};

/**
 * Clave que identifica cada ambiente. Si falta, ese ambiente no se escribe.
 */
const DEFINING_KEY: Record<
  DosaCredentialEnvironment,
  keyof DosaCredentialBundle
> = {
  production: "apiKeyProduccion",
  test: "apiKeyTest",
};

const ENVIRONMENTS: DosaCredentialEnvironment[] = ["production", "test"];

function hasValue(value: string | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * Reparte el paquete. Nunca inventa claves y nunca descarta una que venga con
 * valor: cada una acaba en su fila.
 *
 * @param declaredEnvironment Ambiente que declaró el evento. Solo se usa para
 *   decidir en qué fila única se guarda `apiSecret`.
 */
export function splitCredentialsByEnvironment(
  bundle: DosaCredentialBundle,
  declaredEnvironment?: DosaCredentialEnvironment,
): DosaCredentialSplit {
  const targets: DosaEnvironmentBundle[] = [];
  const skipped: DosaSkippedEnvironment[] = [];

  for (const environment of ENVIRONMENTS) {
    const definingKey = DEFINING_KEY[environment];
    if (!hasValue(bundle[definingKey])) {
      skipped.push({ environment, reason: "DEFINING_KEY_ABSENT" });
      continue;
    }

    targets.push({
      environment,
      bundle: { [definingKey]: bundle[definingKey]?.trim() },
    });
  }

  // El secreto va a UNA sola fila: la que declaró el evento si existe entre los
  // destinos; si no, la única disponible. Nunca a las dos.
  if (hasValue(bundle.apiSecret) && targets.length > 0) {
    const preferred =
      targets.find((target) => target.environment === declaredEnvironment) ??
      targets[0];
    preferred.bundle.apiSecret = bundle.apiSecret?.trim();
  }

  return { targets, skipped };
}
