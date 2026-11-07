import { existsSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Localiza la CLI de Prisma para las pruebas que crean su propia base de datos.
 *
 * Por qué existe: las suites E2E resolvían la CLI como
 * `process.cwd()/node_modules/prisma/build/index.js`, asumiendo que el paquete
 * vive dentro de `apps/api/node_modules`. Este repositorio es un **monorepo con
 * npm workspaces** y `prisma` se eleva a `node_modules` de la raíz, así que con
 * la instalación real (`npm ci` en la raíz, la misma que usa CI) esa ruta no
 * existe y **toda la capa E2E** fallaba con
 * `Cannot find module …prisma/build/index.js`, sin que hubiera nada roto en el
 * producto.
 *
 * Orden de búsqueda: ubicación hoisteada (raíz del monorepo) y luego la local
 * del workspace. Si no aparece, se falla con un código explícito en vez de
 * ejecutar un `migrate` contra una base con una CLI desconocida.
 */
export function resolvePrismaCliPath(cwd: string = process.cwd()): string {
  const candidates = [
    resolve(cwd, "..", "..", "node_modules", "prisma", "build", "index.js"),
    resolve(cwd, "node_modules", "prisma", "build", "index.js"),
  ];
  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) throw new Error("PRISMA_CLI_NOT_FOUND");
  return found;
}
