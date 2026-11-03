import { readFile, realpath, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { PrismaService } from "../../prisma/prisma.service";
import { e32Preflight, e32SandboxCompanyPrepared, e32SyntheticAddressAllowed, firstE32Document, isE32UatTarget, type E32TrialManifest, type E32TrialFacts } from "./e32-sandbox.policy";
import { fingerprint } from "../documents/ecf-document-idempotency.service";
import { authenticateE32Operator } from "./e32-sandbox-operator";
import { ConfigService } from "@nestjs/config";
import { JwtStrategy } from "../../auth/jwt.strategy";
import { LicenseService } from "../../license/license.service";
import { CatalogRealtimeRelayService } from "../../products/catalog-realtime-relay.service";
import { E32SandboxService, type E32TrialAuthorization } from "./e32-sandbox.service";
import { E32SandboxOneShotWire } from "./e32-sandbox.wire";

// Dedicated CLI only. Does not boot Nest, read .env, decrypt DPAPI or call auth APIs.
async function main() {
  const args = process.argv.slice(2), options: Record<string,string> = {};
  let execute = false, recover = false;
  for (let i=0; i<args.length; i++) {
    if (args[i] === "--execute-once") { execute = true; continue; }
    if (args[i] === "--recover-only") { recover = true; continue; }
    if (!["--manifest","--actor","--authorization"].includes(args[i]) || !args[i+1] || args[i+1].startsWith("--")) throw Error("E32_CLI_OPTION_INVALID");
    if (options[args[i]]) throw Error("E32_CLI_DUPLICATE_OPTION"); options[args[i]] = args[++i];
  }
  if (execute && recover) throw Error("E32_CLI_CONFLICTING_MODES");
  const root = process.cwd(), directory = path.resolve(root, "artifacts/e32-first-trial");
  async function localJson(file: string) {
    const canonical = await realpath(path.resolve(file));
    if (!canonical.startsWith(directory + path.sep) || (await stat(canonical)).size > 65536) throw Error("E32_LOCAL_INPUT_REFUSED");
    return JSON.parse(await readFile(canonical, "utf8"));
  }
  let manifest: E32TrialManifest | null = null;
  try { manifest = await localJson(options["--manifest"] ?? path.join(directory,"manifest.json")); }
  catch { if (execute) throw Error("E32_MANIFEST_REQUIRED"); }
  const facts: E32TrialFacts = { worktree: false, database: false, schema: false, company: false, secretProtected: false,
    secretRefConfigured: false, transport: true, environment: process.env.ALANUBE_ENV ?? "", baseUrl: process.env.ALANUBE_BASE_URL ?? "",
    allSwitchesOff: ["ALANUBE_ENABLE_REAL_CALLS","ECF_EMISSION_ENABLED","ECF_ALANUBE_AUTH_TESTS_ENABLED","ALANUBE_HTTP_TRANSPORT_ENABLED"].every(key => (process.env[key] ?? "false") === "false"),
    noPreviousTrial: false, noNumberCollision: false, actorAuthorized: false };
  try {
    facts.worktree = path.basename(root).toUpperCase() === "FULLPOS-ECF-ALANUBE" &&
      execFileSync("git",["rev-parse","--show-toplevel"],{encoding:"utf8",windowsHide:true}).trim().replace(/\\/g,"/").toLowerCase() === root.replace(/\\/g,"/").toLowerCase() &&
      execFileSync("git",["branch","--show-current"],{encoding:"utf8",windowsHide:true}).trim() === "feature/ecf-alanube";
    facts.secretProtected = (await stat(path.join(root,"apps/api/.secrets/alanube-sandbox-token.securestring.xml"))).isFile();
  } catch { /* Report booleans only; do not echo commands/configuration/errors. */ }
  let containerVerified=false;
  try { containerVerified=execFileSync("docker",["port","fullpos_alanube_uat_postgres","5432/tcp"],{encoding:"utf8",windowsHide:true}).trim()==="127.0.0.1:56550"; }
  catch { /* Closed when Docker isolation cannot be demonstrated. */ }
  if (!facts.worktree || !containerVerified || !isE32UatTarget() || process.env.APP_ENV !== "uat" || process.env.UAT_LOCAL_ONLY !== "true") {
    console.log(JSON.stringify(e32Preflight(manifest,facts), (key,value) => key === "payload" ? undefined : value, 2)); process.exitCode=2; return;
  }
  const prisma = new PrismaService();
  try {
    await prisma.$connect();
    facts.database = (await prisma.$queryRaw<Array<{ name: string }>>`SELECT current_database() AS name`)[0]?.name === "fullpos_alanube_uat";
    const schema = await prisma.$queryRaw<Array<{ present: boolean }>>`SELECT to_regclass('public.ecf_sandbox_e32_trials') IS NOT NULL AND to_regclass('public.ecf_evidence_receipts') IS NOT NULL AS present`;
    facts.schema = schema[0]?.present === true;
    const occupied = facts.schema ? await prisma.ecfSandboxE32Trial.count({where:{slot:"FIRST_E32_SANDBOX"}}) : 1;
    facts.noPreviousTrial = occupied === 0;
    const actor = await authenticateE32Operator(process.env.ECF_SANDBOX_OPERATOR_JWT,options["--actor"],process.env.JWT_SECRET,async payload => {
      const config = new ConfigService();
      // Constructors do not connect a socket or start the application. The
      // existing validator checks session, membership, blocked user and license.
      const licenses = new LicenseService(prisma,config,new CatalogRealtimeRelayService(config));
      return new JwtStrategy(config,prisma,licenses).validate(payload);
    });
    facts.actorAuthorized = Boolean(actor?.companyId && actor.role === "ADMIN");
    if (facts.actorAuthorized && actor?.companyId) {
      const tenant = await prisma.company.findUnique({where:{id:actor.companyId},select:{id:true,slug:true,name:true}});
      facts.syntheticAddressAllowed = Boolean(manifest && e32SyntheticAddressAllowed(manifest,tenant,process.env));
      const config = await prisma.ecfCompanyConfiguration.findUnique({ where:{companyId:actor.companyId} });
      facts.company = e32SandboxCompanyPrepared(config, manifest);
      facts.secretRefConfigured = config?.credentialsSecretRef === "env://ALANUBE_SANDBOX_TOKEN" && process.env.ALANUBE_TOKEN_SECRET_REF === config.credentialsSecretRef;
      if (facts.schema) {
        const trial = await prisma.ecfSandboxE32Trial.findFirst({ where:{companyId:actor.companyId,slot:"FIRST_E32_SANDBOX"} });
        facts.noPreviousTrial = occupied === 0 || (trial?.state === "PREPARED" && trial.manifestFingerprint === fingerprint(manifest));
        if (recover) {
          if (!trial) throw Error("E32_TRIAL_NOT_FOUND");
          console.log(JSON.stringify(await new E32SandboxService(prisma).recoverClaimed({id:actor.id,companyId:actor.companyId,role:actor.role},trial.id)));
          return;
        }
        if (manifest?.clientRequestId && manifest.sender && manifest.issueDate) {
          const existing = await prisma.ecfElectronicDocument.findUnique({where:{companyId_idempotencyKey:{companyId:actor.companyId,idempotencyKey:`ecf:v2:${actor.companyId}:E32:REQUEST:${manifest.clientRequestId}`}}});
          facts.noPreviousTrial &&= !existing || (!existing.externalProviderId && ["LOCAL_VALIDATED","READY_TO_SEND"].includes(existing.status) &&
            existing.payloadFingerprint === fingerprint(firstE32Document(manifest.sender,manifest.issueDate)));
        }
      }
      facts.noNumberCollision = Boolean(manifest?.metadata?.encf) && await prisma.ecfElectronicDocument.count({where:{companyId:actor.companyId,externalDocumentNumber:manifest!.metadata.encf}}) === 0;
    }
    const report = e32Preflight(manifest,facts);
    if (manifest?.mode !== "SANDBOX") { report.result="BLOCKED"; report.blockers.push("SANDBOX_MANIFEST_REQUIRED"); }
    console.log(JSON.stringify(report, (key,value) => key === "payload" ? undefined : value, 2));
    if (report.result !== "READY_FOR_AUTHORIZATION" || !manifest || !actor?.companyId) { process.exitCode=2; return; }
    const grant = options["--authorization"] ? await localJson(options["--authorization"]) as E32TrialAuthorization : null;
    if (grant && (grant.manifestFingerprint !== report.manifestFingerprint || grant.actorId !== actor.id ||
      grant.maxPosts !== 1 || grant.maxQueries !== 1 || !grant.approvalReference?.trim() ||
      !Number.isFinite(Date.parse(grant.expiresAt)) || Date.parse(grant.expiresAt) <= Date.now() ||
      Date.parse(grant.expiresAt) > Date.now()+30*60*1000)) throw Error("E32_AUTHORIZATION_MISMATCH");
    await writeFile(path.join(directory,"payload.json"),JSON.stringify(report.payload,null,2));
    if (!execute) return;
    if (!grant) throw Error("E32_SEPARATE_AUTHORIZATION_REQUIRED");
    for (const file of ["real-post-observation.json","real-get-observation.json","real-trial-result.json"]) {
      try { await stat(path.join(directory,file)); }
      catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") continue; throw error; }
      throw Error("E32_EXISTING_REAL_EVIDENCE_DO_NOT_RETRY");
    }
    const user = {id:actor.id,companyId:actor.companyId,role:actor.role};
    const service = new E32SandboxService(prisma), trial = await service.prepare(user,manifest,facts);
    // Only this explicit authorized CLI path changes child-process flags. No
    // .env/config row is updated; the process exits after one POST and ≤1 GET.
    process.env.ALANUBE_ENABLE_REAL_CALLS="true"; process.env.ECF_EMISSION_ENABLED="true";
    const wire = new E32SandboxOneShotWire(async () => {
      const token = process.env.ALANUBE_SANDBOX_TOKEN;
      if (!token) throw Error("E32_TOKEN_UNAVAILABLE"); return token;
    },async observation => {
      await writeFile(path.join(directory,observation.method === "POST" ? "real-post-observation.json" : "real-get-observation.json"),
        JSON.stringify({...observation,trialId:trial.id,clientRequestId:manifest!.clientRequestId,manifestFingerprint:report.manifestFingerprint,
          payloadFingerprint:report.payloadFingerprint},null,2),{flag:"wx"});
    });
    const outcome = await service.runOnce(user,trial.id,grant,facts,wire);
    await writeFile(path.join(directory,"real-trial-result.json"),JSON.stringify(outcome,null,2),{flag:"wx"});
    console.log(JSON.stringify(outcome));
  } finally {
    process.env.ALANUBE_ENABLE_REAL_CALLS="false"; process.env.ECF_EMISSION_ENABLED="false";
    delete process.env.ALANUBE_SANDBOX_TOKEN; delete process.env.ECF_SANDBOX_OPERATOR_JWT; await prisma.$disconnect();
  }
}
main().catch(() => { console.error("BLOCKED: E32_CLI_FAILURE_REVIEW_REQUIRED; no automatic retry."); process.exitCode=2; });
