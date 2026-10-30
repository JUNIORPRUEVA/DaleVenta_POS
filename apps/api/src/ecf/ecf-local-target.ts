// Strict allowlist of LOCAL e-CF databases. Loopback host + exact (database name,
// port) are required, and query/hash are rejected, so a remote or production URL
// can never match. The historical UAT keeps the reconciled first E32 and stays
// operator-owned; the ephemeral test database is disposable and used only by
// automated PostgreSQL suites.
export type EcfLocalTargetKind = "HISTORICAL_UAT" | "EPHEMERAL_TEST";
export type EcfLocalTarget = { name: string; port: string; kind: EcfLocalTargetKind };

export const ECF_LOCAL_TARGETS: readonly EcfLocalTarget[] = [
  { name: "fullpos_alanube_uat", port: "56550", kind: "HISTORICAL_UAT" },
  { name: "fullpos_alanube_uat_test", port: "56551", kind: "EPHEMERAL_TEST" },
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
