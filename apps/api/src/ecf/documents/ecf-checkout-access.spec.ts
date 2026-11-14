import { ecfCheckoutAccess } from "./ecf-checkout-access";

describe("electronic checkout admission", () => {
  const saved = { ...process.env };
  const user = { id: "cashier", companyId: "tenant-a", role: "CAJERO", userPermissions: { prepareEcfDocuments: true } };
  let db: any;
  let config: any;
  beforeEach(() => {
    process.env.DOSA_EMISSION_ENABLED = "true";
    process.env.DOSA_PRODUCTION_EMISSION_ENABLED = "true";
    process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = "true";
    config = { enabled: true, provider: "DOSA", environment: "PRODUCTION", productionEnabled: true, certificationStatus: "PRODUCTION_READY" };
    db = { appConfig: { findFirst: jest.fn().mockResolvedValue({ rnc: "101000001" }) },
      ecfDosaCompanyCredential: { findFirst: jest.fn().mockResolvedValue({ present: { apiKeyProduccion: true } }) },
      user: { findFirst: jest.fn().mockResolvedValue(null) } };
  });
  afterAll(() => { process.env = saved; });
  it.each(["DOSA_EMISSION_ENABLED", "DOSA_PRODUCTION_EMISSION_ENABLED", "DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED"])("blocks checkout when %s is off", async key => {
    process.env[key] = "false";
    expect((await ecfCheckoutAccess(db, user, config)).allowed).toBe(false);
    expect(db.ecfDosaCompanyCredential.findFirst).not.toHaveBeenCalled();
  });
  it("blocks certified companies that have not explicitly enabled production", async () => {
    config.productionEnabled = false;
    expect(await ecfCheckoutAccess(db, user, config)).toMatchObject({ allowed: false, code: "ECF_PRODUCTION_BLOCKED" });
  });
  it("never treats permission for another action as fiscal authorization", async () => {
    expect(await ecfCheckoutAccess(db, { ...user, userPermissions: {}, adminAuthorized: true, authorizedPermissions: ["chargeSales"] }, config))
      .toMatchObject({ allowed: false, code: "ECF_PREPARATION_PERMISSION_REQUIRED" });
  });
  it("checks only the authenticated company's own issuer and production credential", async () => {
    expect((await ecfCheckoutAccess(db, user, config)).allowed).toBe(true);
    expect(db.appConfig.findFirst).toHaveBeenCalledWith({ where: { companyId: "tenant-a" }, select: { rnc: true } });
    expect(db.ecfDosaCompanyCredential.findFirst).toHaveBeenCalledWith({ where: { companyId: "tenant-a", rnc: "101000001", environment: "production", status: "ACTIVE" }, select: { present: true } });
    db.ecfDosaCompanyCredential.findFirst.mockResolvedValue({ present: { apiKeyTest: true } });
    expect((await ecfCheckoutAccess(db, user, config)).allowed).toBe(false);
  });
  it("requires TEST credentials and certification independently in Sandbox", async () => {
    config.environment = "SANDBOX"; config.productionEnabled = false; config.certificationStatus = "AUTHORIZED_SANDBOX";
    expect((await ecfCheckoutAccess(db, user, config)).allowed).toBe(false);
    db.ecfDosaCompanyCredential.findFirst.mockResolvedValue({ present: { apiKeyTest: true } });
    expect((await ecfCheckoutAccess(db, user, config)).allowed).toBe(true);
    config.certificationStatus = "NOT_STARTED";
    expect((await ecfCheckoutAccess(db, user, config)).allowed).toBe(false);
  });
});
