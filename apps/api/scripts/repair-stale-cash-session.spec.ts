const { main } = require("./repair-stale-cash-session.cjs");

const companyId = "11111111-1111-4111-8111-111111111111";
const sessionId = "22222222-2222-4222-8222-222222222222";

type FakeOptions = {
  session?: Record<string, unknown> | null;
};

function baseSession(overrides: Record<string, unknown> = {}) {
  return {
    id: sessionId,
    companyId,
    openedByUserId: "33333333-3333-4333-8333-333333333333",
    userName: "Cajero",
    openedAt: "2026-10-08T10:00:00.000Z",
    initialAmount: "100.00",
    closingAmount: null,
    expectedAmount: null,
    difference: null,
    status: "OPEN",
    closedAt: null,
    closedByUserId: null,
    cashboxDailyId: "44444444-4444-4444-8444-444444444444",
    businessDate: "2026-10-08",
    requiresClosure: false,
    note: null,
    createdAt: "2026-10-08T10:00:00.000Z",
    updatedAt: "2026-10-08T10:00:00.000Z",
    ...overrides,
  };
}

function fakePgClient(options: FakeOptions = {}) {
  const session = options.session === undefined ? baseSession() : options.session;
  return class FakeClient {
    queries: string[] = [];

    async connect() {}

    async end() {}

    async query(sql: string) {
      this.queries.push(sql);
      if (sql.includes("BEGIN READ ONLY") || sql.includes("ROLLBACK")) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes("FROM cash_sessions cs")) {
        return session
          ? { rowCount: 1, rows: [session] }
          : { rowCount: 0, rows: [] };
      }
      if (sql.includes('COALESCE(kind, \'invoice\') <> \'refund\'')) {
        return {
          rowCount: 1,
          rows: [{ count: 2, totalSold: "420.00", cash: "420.00", transfer: "0.00" }],
        };
      }
      if (sql.includes('COALESCE(kind, \'invoice\') = \'refund\'')) {
        return {
          rowCount: 1,
          rows: [{ count: 4, totalSold: "-975.00", cash: "-975.00", transfer: "0.00" }],
        };
      }
      if (sql.includes("FROM cash_movements") && sql.includes("COUNT(*)")) {
        return {
          rowCount: 1,
          rows: [{ count: 0, cashIn: "0.00", cashOut: "0.00" }],
        };
      }
      if (sql.includes("FROM sale_credit_payments") && sql.includes("COUNT(*)")) {
        return {
          rowCount: 1,
          rows: [{ count: 0, amount: "0.00", cash: "0.00", transfer: "0.00" }],
        };
      }
      return { rowCount: 0, rows: [] };
    }
  };
}

async function runTool(
  args: string[],
  options: FakeOptions = {},
) {
  const output: string[] = [];
  const result = await main({
    argv: ["node", "repair-stale-cash-session.cjs", ...args],
    env: { DATABASE_URL: "postgresql://user:pass@localhost:5432/test" },
    PgClient: fakePgClient(options),
    stdout: (line: string) => output.push(line),
  });
  return { result, output };
}

describe("repair-stale-cash-session dry-run tool", () => {
  it("--apply is rejected before any database access", async () => {
    await expect(
      main({
        argv: ["node", "tool", "--apply", "--company-id", companyId, "--session-id", sessionId],
        env: { DATABASE_URL: "postgresql://user:pass@localhost:5432/test" },
        PgClient: fakePgClient(),
        stdout: jest.fn(),
      }),
    ).rejects.toThrow(/--apply is not implemented/);
  });

  it("wrong company/session aborts", async () => {
    await expect(
      runTool(["--dry-run", "--company-id", companyId, "--session-id", sessionId], {
        session: null,
      }),
    ).rejects.toThrow(/not found/);
  });

  it("status != OPEN returns fail-closed exit code", async () => {
    const { result } = await runTool(
      ["--dry-run", "--company-id", companyId, "--session-id", sessionId],
      { session: baseSession({ status: "CLOSED" }) },
    );

    expect(result.exitCode).toBe(3);
    expect(result.report.preconditions.statusOpen).toBe(false);
    expect(result.report.preconditions.canProceedInFutureWriteTool).toBe(false);
  });

  it("closedAt != null returns fail-closed exit code", async () => {
    const { result } = await runTool(
      ["--dry-run", "--company-id", companyId, "--session-id", sessionId],
      { session: baseSession({ closedAt: "2026-10-08T12:00:00.000Z" }) },
    );

    expect(result.exitCode).toBe(3);
    expect(result.report.preconditions.closedAtNull).toBe(false);
  });

  it("counts drift aborts through guardFailures", async () => {
    const { result } = await runTool([
      "--dry-run",
      "--company-id",
      companyId,
      "--session-id",
      sessionId,
      "--expected-sales-count",
      "99",
    ]);

    expect(result.exitCode).toBe(3);
    expect(result.report.preconditions.guardFailures).toEqual([
      { guard: "expected-sales-count", expected: 99, actual: 2 },
    ]);
  });

  it("digest mismatch aborts through guardFailures", async () => {
    const { result } = await runTool([
      "--dry-run",
      "--company-id",
      companyId,
      "--session-id",
      sessionId,
      "--expected-digest",
      "not-the-current-digest",
    ]);

    expect(result.exitCode).toBe(3);
    expect(result.report.preconditions.guardFailures).toEqual([
      expect.objectContaining({ guard: "expected-digest" }),
    ]);
  });

  it("valid stale session dry-run passes and reconstructs expected cash", async () => {
    const { result } = await runTool([
      "--dry-run",
      "--company-id",
      companyId,
      "--session-id",
      sessionId,
      "--expected-sales-count",
      "2",
      "--expected-refunds-count",
      "4",
      "--expected-movements-count",
      "0",
      "--expected-credit-payments-count",
      "0",
    ]);

    expect(result.exitCode).toBe(0);
    expect(result.report.writes).toBe(false);
    expect(result.report.expectedCash).toBe("-455.00");
    expect(result.report.preconditions.canProceedInFutureWriteTool).toBe(true);
  });
});
