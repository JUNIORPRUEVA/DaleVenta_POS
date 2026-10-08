#!/usr/bin/env node

const crypto = require("node:crypto");
const { Client } = require("pg");

function usage() {
  console.log(`Usage:
  node apps/api/scripts/repair-stale-cash-session.cjs --dry-run --company-id <uuid> --session-id <uuid> [guards]

Required:
  --dry-run              Read-only analysis. This version never writes.
  --company-id <uuid>    Exact tenant/company id.
  --session-id <uuid>    Exact cash session id.

Optional drift guards:
  --expected-sales-count <n>
  --expected-refunds-count <n>
  --expected-movements-count <n>
  --expected-credit-payments-count <n>
  --expected-updated-at <iso>
  --expected-digest <sha256>

Safety:
  --apply is intentionally rejected. Production repair requires a future,
  explicitly authorized write-capable version.`);
}

function parseArgs(argv) {
  const args = { guards: {} };
  for (let i = 2; i < argv.length; i += 1) {
    const key = argv[i];
    if (key === "--help" || key === "-h") {
      args.help = true;
      continue;
    }
    if (key === "--dry-run") {
      args.dryRun = true;
      continue;
    }
    if (key === "--apply") {
      args.apply = true;
      continue;
    }
    const value = argv[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${key}`);
    }
    i += 1;
    switch (key) {
      case "--company-id":
        args.companyId = value.trim();
        break;
      case "--session-id":
        args.sessionId = value.trim();
        break;
      case "--expected-sales-count":
      case "--expected-refunds-count":
      case "--expected-movements-count":
      case "--expected-credit-payments-count":
        args.guards[key.slice(2)] = Number.parseInt(value, 10);
        break;
      case "--expected-updated-at":
      case "--expected-digest":
        args.guards[key.slice(2)] = value.trim();
        break;
      default:
        throw new Error(`Unknown argument ${key}`);
    }
  }
  return args;
}

function assertUuid(name, value) {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value || "",
    )
  ) {
    throw new Error(`${name} must be a UUID`);
  }
}

function decimal(value) {
  if (value == null) return "0.00";
  const number = Number(value);
  if (!Number.isFinite(number)) return value.toString();
  return number.toFixed(2);
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.keys(value)
      .sort()
      .reduce((acc, key) => {
        acc[key] = canonical(value[key]);
        return acc;
      }, {});
  }
  return value;
}

function digest(value) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(canonical(value)))
    .digest("hex");
}

function compareGuard(guards, key, actual, failures) {
  if (guards[key] === undefined) return;
  if (guards[key] !== actual) {
    failures.push({ guard: key, expected: guards[key], actual });
  }
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    usage();
    return;
  }
  if (args.apply) {
    throw new Error("--apply is not implemented in this dry-run-only tool");
  }
  if (!args.dryRun) throw new Error("--dry-run is required");
  assertUuid("--company-id", args.companyId);
  assertUuid("--session-id", args.sessionId);
  if (!process.env.DATABASE_URL) {
    throw new Error("DATABASE_URL is required");
  }

  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await client.query("BEGIN READ ONLY");

    const sessionResult = await client.query(
      `
        SELECT
          cs.id,
          cs.company_id AS "companyId",
          cs."openedByUserId",
          cs."userName",
          cs."openedAt",
          cs."initialAmount",
          cs."closingAmount",
          cs."expectedAmount",
          cs."difference",
          cs.status,
          cs."closedAt",
          cs."closedByUserId",
          cs."cashboxDailyId",
          cs."businessDate",
          cs."requiresClosure",
          cs.note,
          cs."createdAt",
          cs."updatedAt"
        FROM cash_sessions cs
        WHERE cs.company_id = $1::uuid AND cs.id = $2::uuid
      `,
      [args.companyId, args.sessionId],
    );
    if (sessionResult.rowCount !== 1) {
      throw new Error("Cash session not found for exact company/session");
    }
    const session = sessionResult.rows[0];

    const sales = await client.query(
      `
            SELECT
              COUNT(*)::int AS count,
              COALESCE(SUM("totalSold"), 0)::text AS "totalSold",
              COALESCE(SUM("paymentCashAmount"), 0)::text AS "cash",
              COALESCE(SUM("paymentTransferAmount"), 0)::text AS "transfer"
            FROM "Sale"
            WHERE company_id = $1::uuid
              AND "cashSessionId" = $2::uuid
              AND COALESCE(kind, 'invoice') <> 'refund'
          `,
      [args.companyId, args.sessionId],
    );
    const refunds = await client.query(
      `
            SELECT
              COUNT(*)::int AS count,
              COALESCE(SUM("totalSold"), 0)::text AS "totalSold",
              COALESCE(SUM("paymentCashAmount"), 0)::text AS "cash",
              COALESCE(SUM("paymentTransferAmount"), 0)::text AS "transfer"
            FROM "Sale"
            WHERE company_id = $1::uuid
              AND "cashSessionId" = $2::uuid
              AND COALESCE(kind, 'invoice') = 'refund'
          `,
      [args.companyId, args.sessionId],
    );
    const movements = await client.query(
      `
            SELECT
              COUNT(*)::int AS count,
              COALESCE(SUM(CASE WHEN type = 'IN' THEN amount ELSE 0 END), 0)::text AS "cashIn",
              COALESCE(SUM(CASE WHEN type = 'OUT' THEN amount ELSE 0 END), 0)::text AS "cashOut"
            FROM cash_movements
            WHERE company_id = $1::uuid AND "sessionId" = $2::uuid
          `,
      [args.companyId, args.sessionId],
    );
    const creditPayments = await client.query(
      `
            SELECT
              COUNT(*)::int AS count,
              COALESCE(SUM(amount), 0)::text AS amount,
              COALESCE(SUM("cashAmount"), 0)::text AS cash,
              COALESCE(SUM("transferAmount"), 0)::text AS transfer
            FROM sale_credit_payments
            WHERE company_id = $1::uuid AND "cashSessionId" = $2::uuid
          `,
      [args.companyId, args.sessionId],
    );
    const relatedOps = await client.query(
      `
            SELECT 'sale' AS type, id::text, "saleDate" AS at, kind, "totalSold"::text AS amount
            FROM "Sale"
            WHERE company_id = $1::uuid AND "cashSessionId" = $2::uuid
            UNION ALL
            SELECT 'movement' AS type, id::text, "createdAt" AS at, type AS kind, amount::text
            FROM cash_movements
            WHERE company_id = $1::uuid AND "sessionId" = $2::uuid
            UNION ALL
            SELECT 'credit_payment' AS type, id::text, "paidAt" AS at, 'credit_payment' AS kind, amount::text
            FROM sale_credit_payments
            WHERE company_id = $1::uuid AND "cashSessionId" = $2::uuid
            ORDER BY at ASC
          `,
      [args.companyId, args.sessionId],
    );

    const aggregate = {
      sales: {
        count: sales.rows[0].count,
        totalSold: decimal(sales.rows[0].totalSold),
        cash: decimal(sales.rows[0].cash),
        transfer: decimal(sales.rows[0].transfer),
      },
      refunds: {
        count: refunds.rows[0].count,
        totalSold: decimal(refunds.rows[0].totalSold),
        cash: decimal(refunds.rows[0].cash),
        transfer: decimal(refunds.rows[0].transfer),
      },
      movements: {
        count: movements.rows[0].count,
        cashIn: decimal(movements.rows[0].cashIn),
        cashOut: decimal(movements.rows[0].cashOut),
      },
      creditPayments: {
        count: creditPayments.rows[0].count,
        amount: decimal(creditPayments.rows[0].amount),
        cash: decimal(creditPayments.rows[0].cash),
        transfer: decimal(creditPayments.rows[0].transfer),
      },
    };

    const expectedCash =
      Number(session.initialAmount || 0) +
      Number(aggregate.sales.cash) +
      // Refund rows are stored as negative amounts in the current schema.
      Number(aggregate.refunds.cash) +
      Number(aggregate.movements.cashIn) -
      Number(aggregate.movements.cashOut) +
      Number(aggregate.creditPayments.cash);

    const snapshot = {
      session,
      aggregate,
      expectedCash: expectedCash.toFixed(2),
    };
    const snapshotDigest = digest(snapshot);
    const guardFailures = [];
    compareGuard(args.guards, "expected-sales-count", aggregate.sales.count, guardFailures);
    compareGuard(args.guards, "expected-refunds-count", aggregate.refunds.count, guardFailures);
    compareGuard(
      args.guards,
      "expected-movements-count",
      aggregate.movements.count,
      guardFailures,
    );
    compareGuard(
      args.guards,
      "expected-credit-payments-count",
      aggregate.creditPayments.count,
      guardFailures,
    );
    compareGuard(
      args.guards,
      "expected-updated-at",
      new Date(session.updatedAt).toISOString(),
      guardFailures,
    );
    compareGuard(args.guards, "expected-digest", snapshotDigest, guardFailures);

    const preconditions = {
      exactCompany: session.companyId === args.companyId,
      exactSession: session.id === args.sessionId,
      statusOpen: session.status === "OPEN",
      closedAtNull: session.closedAt == null,
      guardFailures,
      canProceedInFutureWriteTool:
        session.status === "OPEN" &&
        session.closedAt == null &&
        guardFailures.length === 0,
    };

    const report = {
      mode: "DRY_RUN_ONLY",
      writes: false,
      repairImplemented: false,
      target: { companyId: args.companyId, sessionId: args.sessionId },
      preconditions,
      snapshotDigest,
      before: session,
      financialReconstruction: aggregate,
      expectedCash: expectedCash.toFixed(2),
      relatedOperations: relatedOps.rows,
      proposedTransition: {
        status: "CLOSED",
        closingAmount: null,
        difference: null,
        note:
          "Administrative legacy reconciliation requires an explicit business decision for counted cash. This dry-run does not invent closingAmount.",
      },
      postconditionsForFutureWrite: [
        "same company/session",
        "status was OPEN",
        "closedAt was null",
        "all expected counts matched",
        "updatedAt or digest guard matched when provided",
      ],
    };

    console.log(JSON.stringify(report, null, 2));
    await client.query("ROLLBACK");
    if (guardFailures.length > 0) process.exitCode = 3;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    throw error;
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error(`ERROR: ${error.message}`);
  process.exit(1);
});
