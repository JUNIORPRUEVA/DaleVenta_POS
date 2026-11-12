// Strict allowlist of LOCAL e-CF databases. Loopback host + exact (database name,
// port) are required, and query/hash are rejected, so a remote or production URL
// can never match. The historical UAT keeps the reconciled first E32 and stays
// operator-owned.
//
// Sobre los destinos de prueba:
//
// * `fullpos_alanube_uat_test` (56551) es el destino histórico de pruebas, pero
//   **no es desechable**: contiene miles de empresas de ensayos anteriores. Las
//   suites que escriben datos no deben apuntar ahí sin querer.
// * `fullpos_ecf_ephemeral_test` (56701) es un contenedor DEDICADO, creado para
//   las suites automáticas: puerto exclusivo en loopback, base recién migrada y
//   destruible sin afectar a nadie. Es el destino recomendado para ejecutar las
//   suites e-CF que escriben datos.
//
// La regla sigue siendo exacta (nombre + puerto): añadir este destino no relaja
// ninguna de las comprobaciones anteriores.
export type EcfLocalTargetKind = "HISTORICAL_UAT" | "EPHEMERAL_TEST";
export type EcfLocalTarget = { name: string; port: string; kind: EcfLocalTargetKind };

export const ECF_LOCAL_TARGETS: readonly EcfLocalTarget[] = [
  { name: "fullpos_alanube_uat", port: "56550", kind: "HISTORICAL_UAT" },
  { name: "fullpos_alanube_uat_test", port: "56551", kind: "EPHEMERAL_TEST" },
  // Destino exclusivamente desechable para las suites automáticas.
  { name: "fullpos_ecf_ephemeral_test", port: "56701", kind: "EPHEMERAL_TEST" },
  // Mismo destino efímero en un puerto alternativo: Windows/Hyper-V reserva
  // rangos dinámicos y a veces deja el 56701 inutilizable (`bind: access
  // permissions`). Sigue siendo una regla EXACTA (loopback + nombre + puerto),
  // así que no relaja ninguna comprobación: la base es la misma y desechable.
  { name: "fullpos_ecf_ephemeral_test", port: "55500", kind: "EPHEMERAL_TEST" },
];

export function matchEcfLocalTarget(value = process.env.DATABASE_URL ?? ""): EcfLocalTarget | null {
  let url: URL;
  try { url = new URL(value); } catch { return null; }
  if (!["postgres:", "postgresql:"].includes(url.protocol)) return null;
  if (url.search || url.hash) return null;
  if (url.hostname !== "127.0.0.1") return null;
  const name = url.pathname.replace(/^\//, "");
  return ECF_LOCAL_TARGETS.find((target) => target.name === name && target.port === url.port) ?? null;
}

export const isEcfLocalTarget = (value?: string) => matchEcfLocalTarget(value) !== null;
export const isEcfHistoricalTarget = (value?: string) => matchEcfLocalTarget(value)?.kind === "HISTORICAL_UAT";
export const isEcfEphemeralTestTarget = (value?: string) => matchEcfLocalTarget(value)?.kind === "EPHEMERAL_TEST";
