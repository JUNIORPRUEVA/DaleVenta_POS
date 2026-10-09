#!/usr/bin/env node
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = process.cwd();
const src = join(root, "apps", "api", "src");
const failOnCritical = process.argv.includes("--fail-on-critical");
const failOnOpen = process.argv.includes("--fail-on-open");
const markdown = process.argv.includes("--markdown");
const ignored = [
  ".spec.ts",
  ".e2e-spec.ts",
  "backup-extractor.ts",
  "seed",
];

function walk(dir) {
  const entries = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    const stat = statSync(path);
    if (stat.isDirectory()) {
      entries.push(...walk(path));
    } else if (name.endsWith(".ts") && !ignored.some((item) => path.includes(item))) {
      entries.push(path);
    }
  }
  return entries;
}

function lineNumber(source, index) {
  return source.slice(0, index).split(/\r?\n/).length;
}

function enclosingFunction(source, index) {
  const prefix = source.slice(0, index);
  const matches = [...prefix.matchAll(/(?:async\s+)?([A-Za-z0-9_]+)\s*\([^)]*\)\s*\{/g)];
  return matches.at(-1)?.[1] ?? "";
}

function classifyFinding(file, line, source, index) {
  const window = source.slice(index, index + 1200);
  const fn = enclosingFunction(source, index);
  const query = window.split(/\r?\n/).slice(0, 8).join(" ").replace(/\s+/g, " ").trim();
  const base = {
    module: file.split("/").at(-2) ?? "api",
    query,
    consumer: fn || "unknown",
    tenantScoped: /\bcompanyId\b|company_id/.test(window) ? "YES" : "NO/VERIFY",
    bounded: "NO",
    currentBound: "none",
    potentialCardinality: "unknown",
    relations: /\binclude\s*:/.test(window) ? "YES" : "NO",
    risk: "",
    classification: "LOW",
    action: "Document and add explicit bound when touched.",
    justification: "",
    status: "CLASSIFIED",
  };

  const set = (classification, risk, action, justification, extra = {}) => ({
    ...base,
    classification,
    risk,
    action,
    justification,
    ...extra,
  });

  if (file.includes("/reports/")) {
    return set(
      "CRITICAL",
      "Financial report reads large history and aggregates in Node.",
      "Migrate to DB aggregates/ranged pagination with equivalence tests.",
      "Reports are frequent financial surfaces; sales/items/cash/credit history can grow without bound.",
      { potentialCardinality: "high", relations: "YES" },
    );
  }
  if (file.includes("/cash/")) {
    if (fn === "buildSummaryForSessionLegacy") {
      return set(
        "SAFE_JUSTIFIED",
        "Legacy reference path contains unbounded reads but is bypassed by real Prisma clients.",
        "Keep only as test/mock fallback; production path uses groupBy/aggregate/raw grouped queries.",
        "Guard `canUseAggregatedCashSummary()` selects the aggregated path when Prisma exposes groupBy/aggregate/$queryRaw.",
        { potentialCardinality: "test fallback", status: "FIXED_AGGREGATED_PATH" },
      );
    }
    return set(
      "HIGH",
      "Cash screen/detail can grow with manual movements in a long shift.",
      "Add paginated/detail movement contract or cap detail movement list.",
      "Cash is operational, but movement cardinality is usually much lower than sales/items.",
      { potentialCardinality: "medium/high" },
    );
  }
  if (file.includes("/backups/")) {
    if (fn === "runAutomaticBackups") {
      return set(
        "HIGH",
        "Global job loads all active companies before work.",
        "Batch companies and add concurrency limits.",
        "100+ tenant readiness requires tenant batching for background jobs.",
        { tenantScoped: "GLOBAL", potentialCardinality: "tenants" },
      );
    }
    return set(
      "MEDIUM",
      "Retention reads all automatic backup rows for one tenant.",
      "Fetch max retention + overflow page or delete by cursor.",
      "Tenant scoped and backup rows are moderate, but still unbounded.",
      { potentialCardinality: "medium" },
    );
  }
  if (file.includes("/contabilidad/")) {
    if (/id:\s*\{\s*in:\s*uniqueIds|closeId:\s*id/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Lookup is bounded by request IDs or one close.",
        "No change.",
        "Upstream input controls the ID set; not a historical scan.",
        { bounded: "YES", currentBound: "request/id scoped", potentialCardinality: "low" },
      );
    }
    if (fn === "listDepositBanks") {
      return set(
        "SAFE_JUSTIFIED",
        "Active bank/account configuration is naturally small per tenant.",
        "No change unless tenants start storing large bank catalogs.",
        "Configuration table, tenant scoped, infrequent settings surface.",
        { potentialCardinality: "low" },
      );
    }
    return set(
      "HIGH",
      "Accounting/payables/fiscal collections can grow and affect financial screens.",
      "Paginate list endpoints and move summaries to DB aggregates.",
      "Tenant scoped but finance/history surfaces can become large.",
      { potentialCardinality: "high", relations: /\binclude\s*:/.test(window) ? "YES" : "NO" },
    );
  }
  if (file.includes("/inventory/")) {
    if (file.includes("zero-config-inventory") && /productId:\s*\{\s*in:\s*productIds/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "WarehouseStock lookup is bounded by the current product batch.",
        "No change.",
        "Zero-config now reads products in cursor batches; stock lookup uses only that page's product IDs.",
        { bounded: "YES", currentBound: "product batch", potentialCardinality: "batch-sized", status: "FIXED_BATCHED_BACKFILL" },
      );
    }
    if (/id:\s*\{\s*in:\s*idsFor/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Reference lookup is bounded by IDs from already paged movement rows.",
        "No change.",
        "The upstream movement query has skip/take; these relation lookups only hydrate visible rows.",
        { bounded: "YES", currentBound: "paged movement IDs", potentialCardinality: "page-sized" },
      );
    }
    return set(
      "CRITICAL",
      "Inventory reports can scan full product/stock history.",
      "Paginate/export stock reports and use DB aggregates for reconciliation.",
      "Inventory is operational and high-cardinality for large tenants.",
      { potentialCardinality: "high" },
    );
  }
  if (file.includes("/sales/")) {
    if (/id:\s*\{\s*in:\s*|refundedSaleItemId:\s*\{\s*in:/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Lookup is bounded by IDs from the current sale/request/page.",
        "No change.",
        "The ID set is produced upstream and not a tenant-wide list.",
        { bounded: "YES", currentBound: "ID set", potentialCardinality: "bounded" },
      );
    }
    return set(
      "HIGH",
      "Sales helper/report path reads historical sales for derived totals.",
      "Replace with groupBy/aggregate or enforce explicit date/page bounds.",
      "Sales are high-growth; some endpoints already fixed, remaining helpers need targeted redesign.",
      { potentialCardinality: "high", relations: /\binclude\s*:/.test(window) ? "YES" : "NO" },
    );
  }
  if (file.includes("/purchases/")) {
    if (/id:\s*\{\s*in:\s*|purchaseOrderId:\s*id|supplierId:\s*\{\s*in:\s*ids/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Lookup is bounded by current document/page IDs.",
        "No change.",
        "The query hydrates or validates a finite upstream set.",
        { bounded: "YES", currentBound: "ID set/current document", potentialCardinality: "bounded" },
      );
    }
    return set(
      "HIGH",
      "Purchase/product recommendations can scan catalog/order history.",
      "Paginate recommendations or compute with DB aggregates.",
      "Purchases and products are high-growth operational data.",
      { potentialCardinality: "high" },
    );
  }
  if (file.includes("/products/")) {
    if (file.includes("unitOfMeasure")) {
      return set(
        "SAFE_JUSTIFIED",
        "Unit configuration is naturally small.",
        "No change.",
        "Unit-of-measure rows are bounded configuration, not transactional history.",
        { potentialCardinality: "low" },
      );
    }
    return set(
      "HIGH",
      "Product identity/code checks can scan catalog.",
      "Add normalized indexed lookup or explicit bounded candidate strategy.",
      "Product catalogs can grow large; identity checks are operational.",
      { potentialCardinality: "high" },
    );
  }
  if (file.includes("/clients/") || file.includes("/cotizaciones/")) {
    if (/purge|limpiar|debug/i.test(source.slice(Math.max(0, index - 500), index + 500))) {
      if (/take:\s*DEBUG_PURGE_MAX_IDS\s*\+\s*1/.test(window)) {
        return set(
          "SAFE_JUSTIFIED",
          "Admin/debug purge path is explicitly bounded and fails closed above the debug limit.",
          "No change.",
          "Not an ordinary user screen; destructive debug flow now has an explicit max-ID guard before building ID arrays.",
          { bounded: "YES", currentBound: "DEBUG_PURGE_MAX_IDS + 1", potentialCardinality: "bounded debug" },
        );
      }
      return set(
        "LOW",
        "Admin/debug purge path can scan tenant data.",
        "If retained, chunk destructive debug paths and keep disabled from production usage.",
        "Not an ordinary user screen; still documented because tenant data can grow.",
        { potentialCardinality: "high", consumer: "admin/debug purge" },
      );
    }
    if (/id:\s*\{\s*in:\s*productIds/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Product lookup is bounded by quote line IDs.",
        "No change.",
        "Upstream quote payload limits the product ID set.",
        { bounded: "YES", currentBound: "request item IDs", potentialCardinality: "bounded" },
      );
    }
    return set(
      "MEDIUM",
      "Administrative knowledge/list path can grow moderately.",
      "Add take/search or page if manual entries grow.",
      "Tenant/owner scoped but not primary transactional history.",
      { potentialCardinality: "medium" },
    );
  }
  if (file.includes("/payroll/")) {
    if (/id:\s*\{\s*in:|take:\s*2/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Lookup is bounded by user identity or explicit small take.",
        "No change.",
        "Not a tenant-wide payroll scan.",
        { bounded: "YES", currentBound: "ID/small take", potentialCardinality: "low" },
      );
    }
    return set(
      "MEDIUM",
      "Payroll administrative lists can grow with employees/periods.",
      "Add pagination to payroll lists.",
      "Important but lower frequency than POS sales/cash.",
      { potentialCardinality: "medium" },
    );
  }
  if (file.includes("/users/")) {
    if (/take:\s*USERS_ADMIN_LIST_LIMIT|LIMIT\s*\$\{USERS_ADMIN_LIST_LIMIT\}/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Admin/support user lookup has an explicit result bound.",
        "No change.",
        "User administration is tenant scoped and lower-frequency; the list now has a fixed cap.",
        { bounded: "YES", currentBound: "USERS_ADMIN_LIST_LIMIT", potentialCardinality: "bounded admin" },
      );
    }
    return set(
      "LOW",
      "Admin/support lookup over users or settings-related data.",
      "Add explicit small bounds when touching this flow.",
      "Lower frequency than POS operations; still tenant/global growth aware.",
      { potentialCardinality: "medium", consumer: "admin/support" },
    );
  }
  if (file.includes("/work-scheduling/")) {
    if (/workEmployeeConfig|userId:\s*\{\s*in:\s*users\.map/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Work-scheduling config hydration is bounded by the already bounded employee page.",
        "No change.",
        "The upstream user query is capped by WORK_SCHEDULING_EMPLOYEE_LIMIT; this lookup only hydrates those IDs.",
        { bounded: "YES", currentBound: "employee page IDs", potentialCardinality: "page-sized" },
      );
    }
    if (/weekScheduleId|profileId:\s*\{\s*in|date:\s*\{\s*in|targetUserId|take:\s*50/.test(window)) {
      return set(
        "SAFE_JUSTIFIED",
        "Work-scheduling lookup is bounded by one generated week, IDs, or explicit top-N.",
        "No change.",
        "Weekly schedules are bounded by employees x seven days or prior grouped top-N.",
        { bounded: "YES", currentBound: "week/ID/top-N", potentialCardinality: "bounded" },
      );
    }
    return set(
      "MEDIUM",
      "Work scheduling admin list can grow with employees/exceptions.",
      "Paginate exception/audit employee lists if tenant scale requires it.",
      "Operational but lower frequency and naturally smaller than sales.",
      { potentialCardinality: "medium" },
    );
  }
  if (file.includes("/warehouses/") || file.includes("/locations/") || file.includes("/tax/")) {
    return set(
      "SAFE_JUSTIFIED",
      "Configuration/reference table is naturally small per tenant.",
      "No change.",
      "Warehouses, locations, taxes and NCF config are bounded setup data.",
      { potentialCardinality: "low" },
    );
  }
  if (file.includes("/warranty-configs/")) {
    return set(
      "MEDIUM",
      "Warranty configs may grow with catalog-specific rules.",
      "Add pagination/search if used as a full admin list.",
      "Owner scoped and administrative, but product-level configs can grow.",
      { potentialCardinality: "medium" },
    );
  }
  if (file.includes("/notifications/") || file.includes("/users/") || file.includes("/settings/")) {
    return set(
      "LOW",
      "Admin/support lookup over users or settings-related data.",
      "Add explicit small bounds when touching this flow.",
      "Lower frequency than POS operations; still tenant/global growth aware.",
      { potentialCardinality: "medium" },
    );
  }

  return set(
    "LOW",
    "Unbounded query with no immediate critical path identified.",
    "Review on next domain touch.",
    "Classified conservatively as low after no critical consumer matched.",
  );
}

const findings = [];
for (const file of walk(src)) {
  const source = readFileSync(file, "utf8");
  const regex = /\.findMany\s*\(/g;
  let match;
  while ((match = regex.exec(source))) {
    const window = source.slice(match.index, match.index + 1600);
    const context = source.slice(Math.max(0, match.index - 300), match.index + 1600);
    const hasLimiter = /\b(take|skip|cursor)\s*[:,]/.test(window);
    const hasSmallJustification =
      /unitOfMeasure|warehouse\.findMany|Role|tax\.findMany|ncfSequence/.test(context);
    if (!hasLimiter && !hasSmallJustification) {
      const line = lineNumber(source, match.index);
      const classification = classifyFinding(
        relative(root, file).replaceAll("\\", "/"),
        line,
        source,
        match.index,
      );
      findings.push({
        file: relative(root, file).replaceAll("\\", "/"),
        line,
        ...classification,
      });
    }
  }
}

if (markdown) {
  console.log("| ID | MODULE | FILE | LINE | QUERY | CONSUMER | TENANT_SCOPED | BOUNDED | CURRENT_BOUND | POTENTIAL_CARDINALITY | RELATIONS | RISK | CLASSIFICATION | ACTION | JUSTIFICATION | STATUS |");
  console.log("| --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
  findings.forEach((finding, index) => {
    const cells = [
      `LD-${String(index + 1).padStart(3, "0")}`,
      finding.module,
      finding.file,
      finding.line,
      finding.query,
      finding.consumer,
      finding.tenantScoped,
      finding.bounded,
      finding.currentBound,
      finding.potentialCardinality,
      finding.relations,
      finding.risk,
      finding.classification,
      finding.action,
      finding.justification,
      finding.status,
    ].map((cell) => String(cell).replaceAll("|", "\\|").replace(/\s+/g, " ").trim());
    console.log(`| ${cells.join(" | ")} |`);
  });
} else {
  for (const finding of findings) {
    console.log(`${finding.classification} ${finding.file}:${finding.line} ${finding.consumer} ${finding.risk}`);
  }
}

const counts = findings.reduce((acc, finding) => {
  acc[finding.classification] = (acc[finding.classification] ?? 0) + 1;
  return acc;
}, {});
const ordered = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "SAFE_JUSTIFIED"];
console.log(
  `large-dataset-query-audit findings=${findings.length} ` +
    ordered.map((key) => `${key}=${counts[key] ?? 0}`).join(" ") +
    " UNCLASSIFIED=0",
);
if (failOnCritical && (counts.CRITICAL ?? 0) > 0) {
  process.exit(1);
}
if (
  failOnOpen &&
  ["CRITICAL", "HIGH", "MEDIUM", "LOW"].some((key) => (counts[key] ?? 0) > 0)
) {
  process.exit(1);
}
