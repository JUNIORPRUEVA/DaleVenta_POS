import { readFileSync } from 'node:fs';

/**
 * Lectura de credenciales con soporte de Docker Secrets.
 *
 * Prioridad (documentada y sin ambigüedad):
 *
 * 1. `NAME`        — variable de entorno directa. Gana siempre que traiga un
 *                    valor utilizable. Es el mecanismo histórico y por eso
 *                    mantiene compatibilidad total con la configuración previa.
 * 2. `NAME_FILE`   — ruta a un archivo legible (por ejemplo `/run/secrets/x`).
 *                    Se usa solo si `NAME` está ausente o vacío.
 * 3. Nada          — `source = 'missing'`. Los consumidores ya son fail-closed,
 *                    así que el servicio no arranca capacidades a medias.
 *
 * Reglas de seguridad:
 * - El valor NUNCA se registra ni se incluye en mensajes de error.
 * - Un archivo ilegible o vacío se trata como credencial ausente (nunca como
 *   cadena vacía válida), y se informa el problema sin exponer el contenido.
 * - Se recorta el salto de línea final que Docker añade al montar secretos.
 *
 * Esta función es pura respecto al entorno recibido (`env`), lo que permite
 * probarla con procesos y archivos temporales sin tocar `process.env` global.
 */

export const GUARDIAN_SECRET_FILE_SUFFIX = '_FILE';

/** Origen efectivo del valor: variable, archivo o ausente. */
export type GuardianSecretSource = 'env' | 'file' | 'missing';

export type GuardianSecretResult = {
  /** Valor recortado; cadena vacía cuando la credencial no está disponible. */
  value: string;
  source: GuardianSecretSource;
  /** Motivo del fallo, sin contenido sensible. `null` si no hay problema. */
  problem: string | null;
  /** Ruta del archivo consultada, si se llegó a usar `NAME_FILE`. */
  filePath: string | null;
};

function clean(raw: unknown): string {
  return String(raw ?? '').trim();
}

/**
 * Resuelve una credencial aplicando la prioridad `NAME` → `NAME_FILE`.
 *
 * @param env  Entorno a consultar (permite pruebas con un objeto propio).
 * @param name Nombre base de la credencial, sin el sufijo `_FILE`.
 */
export function resolveGuardianSecret(
  env: NodeJS.ProcessEnv = process.env,
  name: string,
): GuardianSecretResult {
  const direct = clean(env[name]);
  if (direct) {
    return { value: direct, source: 'env', problem: null, filePath: null };
  }

  const filePath = clean(env[`${name}${GUARDIAN_SECRET_FILE_SUFFIX}`]);
  if (!filePath) {
    return {
      value: '',
      source: 'missing',
      problem: `${name} no está definida (tampoco ${name}${GUARDIAN_SECRET_FILE_SUFFIX})`,
      filePath: null,
    };
  }

  try {
    const fromFile = readFileSync(filePath, 'utf8').trim();
    if (!fromFile) {
      return {
        value: '',
        source: 'missing',
        problem: `${name}${GUARDIAN_SECRET_FILE_SUFFIX} apunta a un archivo vacío`,
        filePath,
      };
    }
    return { value: fromFile, source: 'file', problem: null, filePath };
  } catch {
    // No se propaga el error del sistema: su mensaje puede incluir la ruta y,
    // en algunos sistemas de archivos, detalles del contenido.
    return {
      value: '',
      source: 'missing',
      problem: `${name}${GUARDIAN_SECRET_FILE_SUFFIX} no se pudo leer`,
      filePath,
    };
  }
}

/** Atajo: solo el valor resuelto (cadena vacía si falta). */
export function guardianSecretValue(
  env: NodeJS.ProcessEnv = process.env,
  name: string,
): string {
  return resolveGuardianSecret(env, name).value;
}

/** Atajo: true si la credencial está disponible por cualquiera de las dos vías. */
export function guardianSecretPresent(
  env: NodeJS.ProcessEnv = process.env,
  name: string,
): boolean {
  return resolveGuardianSecret(env, name).value.length > 0;
}
