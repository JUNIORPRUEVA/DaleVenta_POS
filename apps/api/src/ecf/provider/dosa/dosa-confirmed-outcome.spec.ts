import { PrismaService } from "../../../prisma/prisma.service";
import { recordDosaConfirmedOutcome } from "./dosa-confirmed-outcome";

describe("DOSA outcome environment admission", () => {
  const keys = ["DOSA_EMISSION_ENABLED", "DOSA_PRODUCTION_EMISSION_ENABLED", "DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED"];
  const previous = new Map(keys.map(key => [key, process.env[key]]));
  const companyId = "00000000-0000-4000-8000-000000000001";
  const user = { id: "00000000-0000-4000-8000-000000000002", companyId, role: "ADMIN" };
  const documentId = "00000000-0000-4000-8000-000000000003";
  const input = { receiptId: "receipt", attemptId: "attempt", httpStatus: 200, body: {} };

  beforeEach(() => { process.env.DOSA_EMISSION_ENABLED = "true";
    process.env.DOSA_PRODUCTION_EMISSION_ENABLED = "false";
    process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = "false"; });
  afterAll(() => { for (const [key, value] of previous) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  } });

  function fixture(environment = "SANDBOX", productionEnabled = false) {
    const receipt = jest.fn().mockResolvedValue(null);
    const tx = { $queryRaw: jest.fn(),
      ecfElectronicDocument: { findFirst: jest.fn().mockResolvedValue({ originalDocumentId: null }),
        findFirstOrThrow: jest.fn().mockResolvedValue({ environment }) },
      ecfCompanyConfiguration: { findUnique: jest.fn().mockResolvedValue({ enabled: true, provider: "DOSA",
        environment, certificationStatus: "PRODUCTION_READY", productionEnabled }) },
      ecfEvidenceReceipt: { findFirst: receipt }, ecfElectronicDocumentAttempt: { findFirst: jest.fn().mockResolvedValue(null) } };
    const transaction = jest.fn(async action => action(tx));
    return { db: { $transaction: transaction } as unknown as PrismaService, tx, transaction, receipt };
  }

  it("authorized TEST still requires a matching receipt before recording acceptance", async () => {
    const f = fixture();
    expect(await recordDosaConfirmedOutcome(f.db, user, documentId, input)).toBe(false);
    expect(f.receipt).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ companyId, documentId }) }));
  });

  it.each([[false, false], [true, false], [false, true]])(
    "production does not reach confirmation evidence without both flags (%s, %s)", async (emission, confirmation) => {
      process.env.DOSA_PRODUCTION_EMISSION_ENABLED = String(emission);
      process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = String(confirmation);
      const f = fixture("PRODUCTION", true);
      expect(await recordDosaConfirmedOutcome(f.db, user, documentId, input)).toBe(false);
      expect(f.receipt).not.toHaveBeenCalled();
    });

  it("a SANDBOX company marked production-enabled cannot record an outcome", async () => {
    const f = fixture("SANDBOX", true);
    expect(await recordDosaConfirmedOutcome(f.db, user, documentId, input)).toBe(false);
    expect(f.receipt).not.toHaveBeenCalled();
  });

  it("the emission kill switch stops confirmation too", async () => {
    process.env.DOSA_EMISSION_ENABLED = "false";
    const f = fixture();
    expect(await recordDosaConfirmedOutcome(f.db, user, documentId, input)).toBe(false);
    expect(f.transaction).not.toHaveBeenCalled();
  });

  it("a pending HTTP202 response cannot record acceptance", async () => {
    const f = fixture();
    expect(await recordDosaConfirmedOutcome(f.db, user, documentId, { ...input, httpStatus: 202 })).toBe(false);
    expect(f.transaction).not.toHaveBeenCalled();
  });

  it("a company/environment mismatch cannot consume another environment's evidence", async () => {
    const f = fixture();
    f.tx.ecfCompanyConfiguration.findUnique.mockResolvedValue({ enabled: true, provider: "DOSA",
      environment: "PRODUCTION", productionEnabled: true, certificationStatus: "PRODUCTION_READY" });
    expect(await recordDosaConfirmedOutcome(f.db, user, documentId, input)).toBe(false);
    expect(f.receipt).not.toHaveBeenCalled();
  });
});
