import {
  ECF_LOCAL_TARGETS,
  isEcfEphemeralTestTarget,
  isEcfHistoricalTarget,
  isEcfLocalTarget,
  matchEcfLocalTarget,
} from "./ecf-local-target";

// The historical UAT and the ephemeral test database are the ONLY authorized
// local targets. Everything else (remote, production-like, wrong port/name,
// query/hash, wrong protocol) must be refused, because this allowlist is the
// barrier that keeps automated and manual e-CF work off production.
const HISTORICAL = "postgresql://user:secret@127.0.0.1:56550/fullpos_alanube_uat";
const EPHEMERAL = "postgresql://user:secret@127.0.0.1:56551/fullpos_alanube_uat_test";
const DISPOSABLE = "postgresql://user:secret@127.0.0.1:56701/fullpos_ecf_ephemeral_test";
// El mismo destino desechable en un puerto alternativo: Windows/Hyper-V reserva
// rangos dinámicos y a veces deja el 56701 inutilizable.
const DISPOSABLE_ALT = "postgresql://user:secret@127.0.0.1:55500/fullpos_ecf_ephemeral_test";

describe("strict local e-CF database allowlist", () => {
  it("classifies exactly the authorized local targets", () => {
    expect(ECF_LOCAL_TARGETS).toHaveLength(4);
    expect(matchEcfLocalTarget(HISTORICAL)).toMatchObject({ kind: "HISTORICAL_UAT", name: "fullpos_alanube_uat", port: "56550" });
    expect(matchEcfLocalTarget(EPHEMERAL)).toMatchObject({ kind: "EPHEMERAL_TEST", name: "fullpos_alanube_uat_test", port: "56551" });
    expect(matchEcfLocalTarget(DISPOSABLE)).toMatchObject({ kind: "EPHEMERAL_TEST", name: "fullpos_ecf_ephemeral_test", port: "56701" });
    expect(matchEcfLocalTarget(DISPOSABLE_ALT)).toMatchObject({ kind: "EPHEMERAL_TEST", name: "fullpos_ecf_ephemeral_test", port: "55500" });
    expect(isEcfHistoricalTarget(HISTORICAL)).toBe(true);
    expect(isEcfEphemeralTestTarget(EPHEMERAL)).toBe(true);
    expect(isEcfLocalTarget(EPHEMERAL)).toBe(true);
    expect(isEcfEphemeralTestTarget(DISPOSABLE)).toBe(true);
    expect(isEcfLocalTarget(DISPOSABLE)).toBe(true);
    expect(isEcfEphemeralTestTarget(DISPOSABLE_ALT)).toBe(true);
    expect(isEcfLocalTarget(DISPOSABLE_ALT)).toBe(true);
    // Cross-checks: each predicate must not accept the other target's kind.
    expect(isEcfEphemeralTestTarget(HISTORICAL)).toBe(false);
    expect(isEcfHistoricalTarget(EPHEMERAL)).toBe(false);
    expect(isEcfHistoricalTarget(DISPOSABLE)).toBe(false);
    expect(isEcfHistoricalTarget(DISPOSABLE_ALT)).toBe(false);
  });

  it("el destino desechable NO se acepta con otro nombre ni otro puerto", () => {
    // La regla es exacta: nombre y puerto van juntos. Un destino nuevo no puede
    // convertirse en comodín para bases parecidas.
    expect(isEcfLocalTarget("postgresql://user:secret@127.0.0.1:56551/fullpos_ecf_ephemeral_test")).toBe(false);
    expect(isEcfLocalTarget("postgresql://user:secret@127.0.0.1:56701/fullpos_alanube_uat_test")).toBe(false);
    expect(isEcfLocalTarget("postgresql://user:secret@127.0.0.1:55500/fullpos_alanube_uat_test")).toBe(false);
    expect(isEcfLocalTarget("postgresql://user:secret@127.0.0.1:56701/fullpos_ecf_ephemeral_test?schema=public")).toBe(false);
  });

  it.each([
    "postgresql://user:secret@production.example.com:56550/fullpos_alanube_uat",
    "postgresql://user:secret@31.97.99.70:56550/fullpos_alanube_uat",
    "postgresql://user:secret@10.0.0.5:5432/daleventa",
    "postgresql://user:secret@127.0.0.1:5432/fullpos_alanube_uat",
    "postgresql://user:secret@127.0.0.1:56550/daleventa_pos",
    "postgresql://user:secret@127.0.0.1:56551/fullpos_alanube_uat",
    "postgresql://user:secret@localhost:56551/fullpos_alanube_uat_test",
    "postgresql://user:secret@127.0.0.1:56550/fullpos_alanube_uat?host=remote",
    "postgresql://user:secret@127.0.0.1:56550/fullpos_alanube_uat#fragment",
    "postgresql://user:secret@127.0.0.1:56550/fullpos_alanube_uat_test",
    "postgresql://user:secret@127.0.0.1:56701/fullpos_ecf_ephemeral_test?schema=public",
    "postgresql://user:secret@127.0.0.1:56700/dosa_validation",
    "postgresql://user:secret@127.0.0.1:56701/postgres",
    "mysql://user:secret@127.0.0.1:56550/fullpos_alanube_uat",
    "",
    "not-a-url",
    "127.0.0.1:56550",
  ])("refuses unauthorized target %s", (value) => {
    expect(matchEcfLocalTarget(value)).toBeNull();
    expect(isEcfLocalTarget(value)).toBe(false);
    expect(isEcfHistoricalTarget(value)).toBe(false);
    expect(isEcfEphemeralTestTarget(value)).toBe(false);
  });
});
