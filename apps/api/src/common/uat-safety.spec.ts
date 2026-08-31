import { assertSafeUatEnvironment, buildSafeUatBanner } from "./uat-safety";

describe("UAT safety", () => {
  const baseEnv = {
    APP_ENV: "uat",
    UAT_LOCAL_ONLY: "true",
    DATABASE_URL:
      "postgresql://daleventa_uat_user:secret@127.0.0.1:55432/daleventa_uat_local",
    PORT: "4000",
    PRODUCTS_SOURCE: "LOCAL",
  };

  it("allows explicit local UAT database", () => {
    expect(() => assertSafeUatEnvironment(baseEnv)).not.toThrow();
  });

  it("allows explicit server UAT database only in server UAT mode", () => {
    expect(() =>
      assertSafeUatEnvironment({
        APP_ENV: "uat",
        UAT_SERVER_MODE: "true",
        DATABASE_URL:
          "postgresql://daleventa_uat_user:secret@database:5432/daleventa_uat",
        PORT: "4001",
        PRODUCTS_SOURCE: "LOCAL",
      }),
    ).not.toThrow();
  });

  it("refuses protected production database names", () => {
    expect(() =>
      assertSafeUatEnvironment({
        ...baseEnv,
        DATABASE_URL: "postgresql://user:secret@127.0.0.1:55432/daleventa",
      }),
    ).toThrow(/protected database/);
  });

  it("refuses production database name even in server UAT mode", () => {
    expect(() =>
      assertSafeUatEnvironment({
        APP_ENV: "uat",
        UAT_SERVER_MODE: "true",
        DATABASE_URL: "postgresql://user:secret@database:5432/daleventa",
      }),
    ).toThrow(/protected database/);
  });

  it("refuses remote hosts in UAT mode", () => {
    expect(() =>
      assertSafeUatEnvironment({
        ...baseEnv,
        DATABASE_URL:
          "postgresql://user:secret@gcdndd.easypanel.host:5432/daleventa_uat_local",
      }),
    ).toThrow(/host must be localhost/);
  });

  it("does not expose credentials in the banner", () => {
    const banner = buildSafeUatBanner(baseEnv);
    expect(banner).toContain("DATABASE: daleventa_uat_local");
    expect(banner).toContain("PRODUCTION: NOT CONNECTED");
    expect(banner).not.toContain("secret");
    expect(banner).not.toContain("daleventa_uat_user:");
  });
});
