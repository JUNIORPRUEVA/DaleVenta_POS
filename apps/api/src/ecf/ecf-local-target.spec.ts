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

describe("strict local e-CF database allowlist", () => {
  it("classifies exactly the two authorized local targets", () => {
    expect(ECF_LOCAL_TARGETS).toHaveLength(2);
    expect(matchEcfLocalTarget(HISTORICAL)).toMatchObject({ kind: "HISTORICAL_UAT", name: "fullpos_alanube_uat", port: "56550" });
    expect(matchEcfLocalTarget(EPHEMERAL)).toMatchObject({ kind: "EPHEMERAL_TEST", name: "fullpos_alanube_uat_test", port: "56551" });
    expect(isEcfHistoricalTarget(HISTORICAL)).toBe(true);
    expect(isEcfEphemeralTestTarget(EPHEMERAL)).toBe(true);
    expect(isEcfLocalTarget(EPHEMERAL)).toBe(true);
    // Cross-checks: each predicate must not accept the other target's kind.
    expect(isEcfEphemeralTestTarget(HISTORICAL)).toBe(false);
    expect(isEcfHistoricalTarget(EPHEMERAL)).toBe(false);
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
