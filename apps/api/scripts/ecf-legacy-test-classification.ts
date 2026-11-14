import { readFile, writeFile } from "node:fs/promises";
import { PrismaClient } from "@prisma/client";
import { isEcfEphemeralTestTarget } from "../src/ecf/ecf-local-target";
import { applyLegacyTestClassification, planLegacyTestClassification, LegacyTestReview } from "../src/ecf/documents/ecf-legacy-test-classification";

// No .env loader, fallback target, provider call or credential output.
async function main() {
  const argv = process.argv.slice(2);
  const flags = new Map<string, string>();
  const booleans = new Set<string>();
  const values = new Set(["--company-id", "--rnc", "--documents", "--out", "--manifest", "--approved-sha256", "--reviewer"]);
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    if (["--apply", "--allow-shared-reviewed"].includes(key)) {
      if (booleans.has(key)) throw Error("ECF_LEGACY_REVIEW_DUPLICATE_ARGUMENT");
      booleans.add(key);
    } else if (values.has(key) && argv[i + 1] && !argv[i + 1].startsWith("--")) {
      if (flags.has(key)) throw Error("ECF_LEGACY_REVIEW_DUPLICATE_ARGUMENT");
      flags.set(key, argv[++i]);
    } else throw Error("ECF_LEGACY_REVIEW_INVALID_ARGUMENT");
  }
  if (!process.env.DATABASE_URL) throw Error("ECF_LEGACY_REVIEW_EXPLICIT_DATABASE_REQUIRED");
  const db = new PrismaClient();
  try {
    if (booleans.has("--apply")) {
      if (!isEcfEphemeralTestTarget() && !booleans.has("--allow-shared-reviewed")) throw Error("ECF_LEGACY_REVIEW_SHARED_APPLY_REQUIRES_APPROVAL");
      if (!flags.get("--manifest") || !flags.get("--company-id")) throw Error("ECF_LEGACY_REVIEW_MANIFEST_REQUIRED");
      const review = JSON.parse(await readFile(flags.get("--manifest")!, "utf8")) as LegacyTestReview;
      if (review.scope.companyId !== flags.get("--company-id")) throw Error("ECF_LEGACY_REVIEW_COMPANY_MISMATCH");
      const result = await applyLegacyTestClassification(db, review, flags.get("--approved-sha256") ?? "", flags.get("--reviewer") ?? "");
      console.log(JSON.stringify({ mode: "APPLIED_REVIEWED_TEST_CLASSIFICATION", ...result }));
    } else {
      if (booleans.has("--allow-shared-reviewed") || !flags.get("--out")) throw Error("ECF_LEGACY_REVIEW_OUTPUT_REQUIRED");
      const plan = await planLegacyTestClassification(db, { companyId: flags.get("--company-id") ?? "", issuerRnc: flags.get("--rnc") ?? "",
        documentIds: (flags.get("--documents") ?? "").split(",").filter(Boolean) });
      await writeFile(flags.get("--out")!, JSON.stringify(plan, null, 2) + "\n", { flag: "wx" });
      console.log(JSON.stringify({ mode: "READ_ONLY_PLAN", companyId: plan.scope.companyId, documents: plan.documents.length,
        manifestHash: plan.manifestHash, minimumTestNext: plan.minimumTestNext }));
    }
  } finally { await db.$disconnect(); }
}
main().catch(error => {
  const code = error instanceof Error && /^ECF_LEGACY_REVIEW_[A-Z_]+$/.test(error.message) ? error.message : "ECF_LEGACY_REVIEW_FAILED_CHECK_TARGET_SCHEMA_OR_EVIDENCE";
  console.error(code); process.exitCode = 1;
});
