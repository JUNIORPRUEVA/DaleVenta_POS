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
 * * `apiSecret` → acompaña a ambas (es el mismo secreto de firma del proveedor)
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
 */
export function splitCredentialsByEnvironment(
  bundle: DosaCredentialBundle,
): DosaCredentialSplit {
  const targets: DosaEnvironmentBundle[] = [];
  const skipped: DosaSkippedEnvironment[] = [];

  for (const environment of ENVIRONMENTS) {
    const definingKey = DEFINING_KEY[environment];
    if (!hasValue(bundle[definingKey])) {
      skipped.push({ environment, reason: "DEFINING_KEY_ABSENT" });
      continue;
    }

    const slice: DosaCredentialBundle = {
      [definingKey]: bundle[definingKey]?.trim(),
    };
    // El secreto compartido acompaña a cada ambiente que tenga su clave.
    if (hasValue(bundle.apiSecret)) slice.apiSecret = bundle.apiSecret?.trim();

    targets.push({ environment, bundle: slice });
  }

  return { targets, skipped };
}
