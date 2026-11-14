# Execution State

## Current work — authorized image sources prepared (2026-11-14)

The owner explicitly authorized only updating backend/PWA Docker Image sources
to the verified PR42 artifacts and retained the Implementar/Deploy action.
PR42 is merged as ac729b16; its complete tree matches source 3217f0cd. All four
post-merge gates in 43609170065 passed. No further merge or deployment was run.

Using EasyPanel 2.37.0's installed/documented updateAppSourceImage operation,
both image sources are now the exact verified digests in
docs/ecf/ECF_IMAGES_3217f0cd.md. A fresh read-only plan preceded the authorized
application. Independent persisted readback passed: protected configuration
fingerprints and registry credentials are unchanged; automatic deploy is off.
The procedure only changes source and normalizes the already-null build field.

The running containers remain 57e59369cec2/a50049a489fb with their previous 8fa
images; the API is healthy. RUN_MIGRATIONS remains false, seed remains off and
both production fiscal flags remain blocked. FULLTECH remains SANDBOX with
productionEnabled=false, five existing documents and production sequence next
values E31=3, E32=3, E34=2. No business database writes or new external issuance.

Private receipts: source3217-authorized-before.json,
source3217-authorized-after.json and source3217-final-readback.json under
C:/Users/pc/.codex/backups/fullpos-ecf-test-close-20261114/.
The owner deploys backend first, checks health, then deploys PWA. Fresh deployed
image verification and the already-authorized TEST numbering/E31/E34 acceptance
remain pending. Do not activate production fiscal permissions or restart on the
owner's behalf. No application code changed in this preparation.

## Previous work — SANDBOX checkout and PDF closure (2026-11-14)

Mode: CONTINUOUS_CONTROLLED_EXECUTION. The owner approved completing TEST
numbering, verified DOSA outcomes, E31/E34 trials from the software where possible,
Normal-sale regression and the blank web PDF preview. Production emission remains
blocked; the owner retains merge and deployment. No production flag, credential,
historical fiscal status or production range may be changed by this task.

Isolated worktree C:/src/fullpos-ecf-test-close-20261114, branch
agent/ecf-test-close-20261114, based on deployed merge8fa5eba6. Other worktrees
contain unrelated edits and are untouched. Local synthetic PostgreSQL is
fullpos_ecf_test_close_20261114, loopback port55503; never use a restored live DB.

Audit: FULLTECH has its own active TEST credential and SANDBOX configuration,
but no SANDBOX authorization/range. Legacy reviewed TEST numbers stay consumed
(E31 frontier3, E34 frontier2). DOSA's accepted historical E31/E34 remain visible
in official TEST queries; their internal review state is not rewritten. Web PDF
download has valid fiscal fields/QR; the Syncfusion web renderer lacks PDF.js.

Plan: retain all identity/receipt/fingerprint/QR checks; authorize confirmed
outcomes only for valid SANDBOX dispatches without opening production gates;
restore the documented web renderer; validate real local HTTP/database chains,
tenant boundaries, connectivity, Normal intent and printing before publication.
Shared TEST setup/issuance is restricted to FULLTECH and confirmed provider
metadata. New code is not deployed by this checkpoint.

Implementation: confirmed outcomes are now environment-gated, with all receipt
checks retained. Completed onboarding uses real POS readiness and preserves
numbering and the existing company activation. Range saves retain the original
authorization and cancel the second write after an unmount/environment change.
Local PDF.js/worker and bounded bootstrap restore the web renderer; failed
previews retain download actions. No schema, credentials or production flags
changed.

Validation: API build/schema PASS;3328 backend tests PASS/101 gated skips,
26 real-local-HTTP scenarios PASS,53 PostgreSQL fiscal regressions PASS,8 new
outcome-gate tests PASS. Final Flutter analysis/web build PASS,828 broad tests
PASS,71 final context/numbering/activation tests PASS. Local browser PDF
engine1280/390 and Nginx config PASS. Runtime npm audit reports0;11 full-tree
development advisories remain outside runtime. Final diff reviewed; publication,
CI and owner-controlled deployment remain before live FULLTECH TEST acceptance.
Evidence: docs/ecf/ECF_TEST_CLOSURE_2026-11-14.md.

## Previous correction — PR41 critical findings (2026-11-13)

Explicit E31/E32 checkout now shares admission with POS capabilities and commits
sale, stock, number allocation and local fiscal preparation atomically. Ordinary
ITBIS printing no longer triggers electronic queries; historical electronic
links use an additive tenant-scoped read flag. API Docker/CI pin Node22.23.4 LTS.
No schema, production configuration, deployment or external emission change.

Local validation:3320 backend tests,1119 broad Flutter tests,13 dedicated real
PostgreSQL regressions,63 tests inside the Node22 Linux image; API build, Prisma
validate, Flutter analyze/web build,30 HTTP tests and runtime dependency audit
passed. Publication and
the final CI result must be checked on the corrected PR HEAD. Details:
[critical findings correction](ecf/ECF_PR41_CRITICAL_FIXES_2026-11-13.md).

## Previous checkpoint — audited manual ECF migration and release candidate (2026-11-13)

HECHO: the explicitly authorized production migrations0400/0500/0600 were
applied manually, rehearsed against a restored backup, and recorded with their
original checksums. All223 previous migration rows remain; the ledger has226.
Five reviewed FULLTECH engineering trials are Sandbox; none is unclassified.
Their fiscal status, identity and original sequence counters were preserved.
The API container/image, disabled automatic migrations and company configuration
were unchanged. No application deployment, restart or external fiscal send.

The candidate lives at C:/src/fullpos-ecf-predeploy-20261113 on
agent/ecf-predeploy-20261113, based on current production-main cada11f8.
Only the prior working-tree delta was ported; the old branch's divergent commits
were not merged. The original218 files, Git history bundle, database backups and
running API/PWA images are retained with verified hashes outside the repository.

Audit fixes close reviewed terminal TEST trials without granting fiscal
acceptance, block unclassified documents on activation, and enforce the original
TEST numbering frontier. Compatible API dependency patches and the explicitly
approved Astro7.4.12 update are included. Docker uses the generated API lock
from the authoritative root lock; the website stage pins Node22.23.4.

Validation: API build;3300 broad tests;30 HTTP tests;48 PostgreSQL tests;
Flutter analyze;1117 broad Flutter tests;14 visual widget checks; Flutter web
validation build; Linux API, Astro and complete combined Docker builds passed.
The combined image passed17 read-only routes/6 assets/PWA/portal checks.
Astro browser QA passed8 desktop/mobile views with0 page errors. Both Linux runtime audits
reported zero advisories. No hardware or deployed-client acceptance is claimed.

The owner authorized commits, branch publication and a PR. Implementation commit
50617f39a7d744d2a528c30fa51b33e8d11b131e is published in
[PR41](https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/41), targeting
production-main. GitHub confirmed no merge conflicts. The owner retains merge
and Deploy; neither was executed by the agent. CI must pass before integration.
Both server production gates remain disabled. autoDeploy=false on API and PWA.
The public DOSA assistant key is already configured; it was not printed/changed.
Full evidence, current file inventory and manual deployment sequence:
[predeployment audit](ecf/ECF_PREDEPLOY_AUDIT_2026-11-13.md).
The 246-file inventory is the implementation checkpoint at50617f39; subsequent
publication documentation is identified separately in the
[operator guide](ecf/ECF_RELEASE_OPERATOR_2026-11-13.md).

## Previous local closure — Normal sales and DOSA recovery (historical)


Checkout finalesdaleventas, branch agent/ecf-offline-history-20261113.
Normal is explicit, internal and the default for every new ticket when allowed.
No e-NCF/expiry, fiscal preparation, sequence consumption or DOSA/DGII dispatch
is possible for that intent. Ordinary ITBIS and existing offline permissions remain.
Ticket drafts retain their own manual fiscal selection without changing the next
ticket's default. Ordinary ticket/PDF bypass the electronic projection.

Added persisted hash/lease recovery after interruption/restart, serialized queries
and stale-worker fencing; validated RFCE E32 no-TrackId receipt references;
HTTP202 contingency printing with pending status and provider legend; explicit
per-company production activation/commercial preparation with certification,
own credentials, server gates and unresolved-TEST guards. The existing assistant
is retained. None of these source changes enables a deployed environment.

Final API build and Prisma validation PASS. Full non-e2e:275 suites /3,293 tests
PASS,101 opt-in tests skipped. PostgreSQL replay/returns:22 PASS. HTTP:26 PASS
against localhost; forceExit remains a documented test-harness limitation.
Flutter final analysis: no issues. Broad regression:1,041 PASS; focused:115 PASS;
last UI recovery/POS checks:11 PASS. Final company-context guards:39 API /52 Flutter PASS;
API build and analysis rerun after those changes. Widget screenshots were visually inspected
at320/1280; the POS screenshot shows Normal on the new ticket. No new hardware
or browser-device acceptance is claimed.

All32 isolated API files match the checkout byte-for-byte. The owned disposable
PostgreSQL was identity-checked and stopped, retaining data. No production access,
external fiscal send, commit/push/deploy, credential edit or shared migration.

Production remains NO-GO pending reviewed shared rollout of prior fiscal
migrations/classification, coordinated API/client and verified runtime activation.
Old documents without replay proof and late fiscal returns still require review.
Current report and exact52-file inventory:
docs/ecf/ECF_NORMAL_PRODUCTION_RECOVERY_2026-11-13.md.

## Previous checkpoint — connection, sales history and E34 (historical)

Checkout finalesdaleventas, branch agent/ecf-offline-history-20261113.
The authorized implementation is locally complete and validated; nothing was
committed, pushed, deployed, migrated on a shared database or sent to DOSA/DGII.
Earlier dirty fiscal work is preserved. The existing DOSA assistant and printer
transports are unchanged.

Implemented: real HTTP connection checks without offline cache; four-second
upper-right notices; E31/E32 intent and frozen E31 expiry persisted before fiscal
preparation; bounded company/owner history projection with reserved e-NCF and
original/E34 states; fiscal-only recovery without another financial refund;
partial/remnant quantity correction; original-bound refund idempotency; ordinary
electronic cancellation blocked; electronic print/PDF guards; stable unresolved
manual E34 request identity. No schema change or new dependency in this task.

Final API: build and Prisma validation PASS; 275 suites / 3,289 tests PASS,
101 opt-in tests skipped. PostgreSQL returns 15 PASS. Local HTTP 25 PASS with
forceExit: the two HTTP suites leave the runner alive without it, including under
detectOpenHandles; this harness limitation remains documented.
Flutter analyze PASS after the last source edit; directed regression 99 PASS,
final repository/print guard 32 PASS. Broad regression 1,145 PASS / 3 SKIP /
1 failed source-text assertion; ordinary confirmation text restored and the failed
suite passed in the final directed regression. Actual widget screenshots at320/1280
and existing synthetic fiscal print images were visually inspected. No new paper
or browser-device acceptance is claimed.

The owned disposable PostgreSQL fullpos_ecf_finish_20261112 was identity-checked
and stopped, retaining its database. No unrelated process was stopped. Isolated
API sources matched all14 current API files byte-for-byte.

The pending implementation list at this checkpoint was superseded by the current
closure above. Shared fiscal rollout and late-return tax review remain pending.

Report and exact file inventory:
docs/ecf/ECF_OFFLINE_HISTORY_E34_2026-11-13.md.

Historical entries below are not authorization for this task.

## Completed — Installed144 startup regression / reference141 review

Worktree C:/src/fullpos-144-fix, agent/release144-regression-audit.
Owner reference:1.0.6-141 from original installer/output. Exact SHA8CB439B0...
matched retained141 build and selectively extracted runner/AOT. Login Widget
build matches candidate after ignoring whitespace/trailing commas only.
Installed runner/AOT match144. No proof of an accidentally published old binary.
Confirmed packaging regression:144 updater uses ProgramFiles/updates; installer
does not provision it. Installed logs show PathAccessException after silent check.
Fix8dd67542 provisions updates with users-modify, preserves it on uninstall,
leaves binary ACLs and all app logic untouched. Candidate145 compiled PASS;
40258303 bytes, SHA FA66972E49B6E99BEE80BDA7E906ECB2C044E158E174FC7A8FFD2C6113F4201E.
Before-fix contract FAIL; after-fix67 storage/updater tests PASS/1 skipped,
flutter analyze clean; local Inno packaging check PASS. Standard-user install
145 passed: installed runtime hash matched candidate, `updates` ACL allowed a
non-admin write, updater saved UP_TO_DATE without PathAccessException, and the
app restored the existing Facturacion session. Owner authorized unsigned
publication only after acceptance; release145 is now published as
ff5a78cc-0f1b-4535-8bec-ec19404a0539 with retention dry-run. Public check maps
144 to145 and145 to current; stable download is302/no-store then200, PE header,
40,258,303 bytes and approved SHA. Releases142/144 remain published with their
objects present. No API/PWA redeploy or migration was required. Login screen
was not visually inspected because the existing session restored directly to
Facturacion; source comparison shows login widget in141 and145 unchanged.
Review:docs/RELEASE144_REGRESSION_REVIEW.md. Earlier deployment history follows;
it is not the current verdict.

## Active task — Offline48h + Mayoreo production integration

Worktree C:/src/fullpos-offline-prod; branch agent/offline-mayoreo-integration-20261018.
Owner authorizes combining the offline worktree, production-main integration,
deployment and a new Windows installer. Continuous controlled execution.
Production now API/PWA144 and Windows144 published; Windows142 preserved.
Source snapshot 8c19bbac; merge 1c2c7a61 preserves production base 2f33df45.
Seven conflicts resolved preserving Mayoreo and offline identity/storage behavior.
SQLite3.52.0 was officially withdrawn; candidate uses sqlite3 Dart3.3.2 / SQLite3.53.1.
API build and766 tests PASS; Flutter analyze PASS; first full suite1368 PASS/6 skips.
Real dedicated clone fullpos_offline_mayoreo144_uat on localhost56549, API46554.
Both additive migrations rehearsed. HTTP concurrent product/stock/sale retries PASS.
Combined Flutter SQLite/reopen/real HTTP wholesale sale test PASS. Sync handler
now preserves manual price-list and source-quotation fields; final regression pending.
Final regression1369 Flutter/766 API PASS, analysis PASS; immutable144 artifacts
built and verified. Owner explicitly authorizes both production migrations and
unsigned Windows144 publication (SHA8F645A04...), followed by repeated continua.
Both authorized production migrations applied; Swarm API/PWA completed,
health ok, protected endpoints401, runtime errors0, config/mounts/ports preserved.
Windows144 published1efef881-4c3f-4dd4-8794-fd64058a8660, retention dry-run,
Windows142 remains published with artifact intact. Final public verification
PASS:142->144,144 up-to-date, full external download exact SHA/size/MZ and
stable download302/no-store. GO for agreed deployment/publication scope.
Full record: docs/OFFLINE_MAYOREO_PRODUCTION_INTEGRATION.md.
Historical task state below is not the current target or authorization.

## Active task — Offline Safe48H Phase17 (2026-10-14)

Worktree `C:\src\fullpos-offline-safe-48h`, branch `feature/offline-safe-48h`.
Scope: Windows candidate and historical installer/updater acceptance, UAT only.
Production/push/merge/deploy/customer updates remain prohibited. The state below
is historical evidence from another worktree, not authorization or the active
environment. Current API46548/clone46552, PostgreSQL56548; manual SQLite preserved.
Phase16 source manifest:24/24 hashes matched before starting;1135 source files
hashed in `.uat/evidence/phase17-baseline.json`; consistent manual backup created.
Hyper-V inventory still permission-blocked; no bypass. No code-signing certificate.
Cached-policy/build/disabled-update handoff guards fixed and tested. New native
helper binds target to PE ProductVersion and locks/revalidates final package.
Final local UAT candidate17002 packaged/hashed;3 interrupted replacements preserve
open DB/WAL/SHM and8 fixture pending actions;9 native and6 real HTTPS tests PASS.
Flutter1335 PASS/5 skipped;Jest752 PASS/8 skipped;analyze/API build/Prisma PASS.
Candidate opened in `.uat/phase17-visual`, title[UAT], cloneAPI46552; owner confirms
POS visible without startup error and Updates shows no pending update/no error.
Candidate left open; no further manual screen repetition requested. No historical GUI, elevated signed chain or physical
hardware result asserted. Next external steps: authorized Windows isolation and
safe historical API routing, signed positive updater UAT, then explicit pilot
approval. Motor GO within proven UAT; integral acceptance/pilot/publication NO-GO.
Final decisions belong in
`docs/offline-safe-48h-phase-17-final-windows-acceptance-2026-10-14.md`.

---

Last updated: 2026-10-07 12:35 local.

## Objective

Implement safe Windows release retention automation for FullPOS Cloud:
prepare/publish separation plus Windows/STABLE current+previous artifact
retention.

## Mode

`CONTINUOUS_CONTROLLED_EXECUTION`

## Environment

- Repository worktree: `C:\src\fullpos-update`
- Branch: `agent/windows-autoupdate-phase6b-build`
- Production authorization: not granted
- Production deployment: blocked
- Production Authenticode certificate: not available
- UAT unsigned update exception: enabled only for local UAT
- UAT API: `http://127.0.0.1:4000`
- UAT DB: `127.0.0.1:55432/daleventa_uat_local`
- UAT HTTPS artifact storage: `https://localhost:9443`
- Windows release retention target: keep current + previous, archive older
  Windows/STABLE artifacts only after publish verification.

## Final Builds

- Installed build N: `1.0.6+130`
- Installed update build N+1: `1.0.6+131`
- Final N+1 UAT installer SHA-256 used in the successful upgrade:
  `265EFDAB1A2CF27EE4E51DC8839B954AF5A1CDCCBBAA9B643737976613685D61`
- Final N+1 UAT installer size: `40167704`
- Authenticode status: unsigned, accepted only by the explicit local UAT policy.

## Completed

- Audited current AppRelease API and confirmed existing statuses were
  `DRAFT`, `PUBLISHED`, `REVOKED`; `REVOKED` is not reused for retention.
- Added AppRelease retention metadata:
  - `ARCHIVED` status.
  - exact `storageKey`.
  - `storageDeletedAt`.
- Implemented Windows/STABLE retention after publish:
  - keeps newest published build.
  - keeps immediate previous published build.
  - skips DRAFT, other platform, other channel, current, previous, unsafe keys,
    and missing keys.
  - deletes only an exact `storageKey` through the release storage adapter.
  - uses R2 by default and local exact-file deletion only for explicit local UAT.
  - marks deleted historical rows `ARCHIVED` and preserves DB history.
  - reports partial cleanup without reverting a successful publish.
- Added admin retention dry-run endpoint:
  `POST /api/app-updates/releases/retention/windows-stable`.
- Updated public update check to ignore releases whose artifact has been
  removed.
- Created release scripts:
  - `scripts/release/prepare_windows_release.ps1`
  - `scripts/release/publish_windows_release.ps1`
- Added surgical `.gitignore` exceptions so the release scripts are tracked
  without unignoring release artifact output directories.
- Updated `docs/WINDOWS_RELEASE_PROCESS.md` with prepare/publish/retention
  workflow.
- Resolved local Prisma `EPERM` by stopping the repo-local backend dev process
  that held the Prisma Windows query engine DLL.
- Applied migration `20261007130000_app_release_retention` to local UAT only
  after verifying DB identity and creating a logical UAT backup.
- Executed real local-UAT retention rotation:
  - `131/132 -> publish 133`: kept `133` and `132`, archived `131`, physically
    deleted artifact `131`, and update checks for builds `130`, `131`, `132`
    offered `133`; build `133` was up to date.
  - `132/133 -> publish 134`: kept `134` and `133`, archived `132`, physically
    deleted artifact `132`, and update checks for builds `132`, `133` offered
    `134`; build `134` was up to date.
- Verified controlled retention failure behavior in local UAT:
  - storage delete failure reports `PARTIAL`;
  - newly published current and previous remain `PUBLISHED`;
  - publish failure does not run cleanup;
  - DRAFT, other channels/platforms, and shared storage keys are preserved.

- Verified elevated agent privileges: `IsAdministrator=True`.
- Verified local UAT API, DB, and HTTPS storage.
- Built and installed build `1.0.6+130`.
- Published UAT AppRelease for build `1.0.6+131`.
- Verified update check returned build `131`.
- Verified silent download, size validation, SHA-256 validation, and `READY_TO_INSTALL`.
- Verified dismiss persistence: `dismissedBuild=131` persisted and did not delete the prepared package.
- Verified menu access from the real Windows topbar company menu: `Actualizaciones` is visible and navigates to the update screen.
- Verified UAC cancel path:
  - `installer_result.json` wrote `UAC_CANCELLED`.
  - exit code was `1223` (`ERROR_CANCELLED`).
  - installed build remained `1.0.6+130`.
  - package remained ready.
  - state returned to `READY_TO_INSTALL`.
  - no updater loop remained.
- Verified and corrected installer handoff bugs found during UAT:
  - local UAT official build URL validation needed an explicit localhost UAT exception.
  - same-build ready artifacts must not be cleared by a re-check.
  - Windows account menu needed an `Actualizaciones` entry in the real POS topbar.
  - native updater must materialize `.exe.ready` to `.exe` before invoking UAC.
  - Flutter must stage `FullposUpdater.exe` outside `Program Files` before launching so Inno can replace the installed updater.
- Verified upgrade path:
  - Inno installer exited `0`.
  - updater log recorded `INSTALLER_SUCCESS`.
  - app relaunched.
  - Windows registry reports `FullPOS 1.0.6 (build 131)`.
  - update state reconciled to `IDLE` / `UP_TO_DATE`.
  - prepared build directory was cleaned.
- Verified data preservation:
  - same cash session remained `OPEN`.
  - same business date remained `2026-10-07`.
  - company/user/product fixture remained scoped to the UAT tenant.
  - local app DB files remained present.
- Executed post-update UAT sale:
  - sale id `5815a377-8c0a-4d46-b59e-cd5761ac020b`.
  - product stock moved from `19` to `18`.
  - warehouse stock moved from `19` to `18`.
- Verified financial regression after update:
  - sales count moved from `3` to `4`.
  - net total sold moved from `100` to `150`.
  - total cost moved from `40` to `60`.
  - total profit moved from `60` to `90`.
  - commission total moved from `12` to `15`.

## Validation

- `npx prisma validate` with dummy local-safe `DATABASE_URL`: PASS.
- `npx prisma generate`: PASS after stopping the repo-local backend dev process
  that held the Prisma engine DLL.
- `npm run api:build`: PASS after Prisma DLL lock was released.
- `npm --workspace apps/api test -- app-updates`: PASS.
- `npm --workspace apps/api exec -- tsc -p tsconfig.build.json`: PASS.
- PowerShell parser validation for release scripts: PASS.
- `git check-ignore` for release scripts: PASS; scripts are no longer ignored.
- `prisma migrate deploy` against local UAT: PASS.
- `prisma migrate status` against local UAT: PASS.
- Real local-UAT retention rotation and failure scenarios: PASS.
- `flutter analyze`: PASS.
- Focused Flutter regression:
  `flutter test test\core\app_update\app_update_controller_test.dart test\core\config\product_config_test.dart test\modules\cotizaciones\company_account_menu_navigation_test.dart`: PASS.
- `npx prisma validate` with local UAT `DATABASE_URL`: PASS.
- Physical Windows UAT N -> N+1: PASS in local UAT with unsigned exception.

## Findings

- Production remains blocked because a production Authenticode certificate is not available.
- No production deployment, production database, customer data, or bridge changes were performed.
- The successful UAT used local-only unsigned policy; production must require trusted signing.
- Retention is code/test validated and real local-UAT rotation was executed
  against an isolated local storage root. Production storage was not touched.

## Next Action

Sign production Windows artifacts and execute signed final release UAT before
production rollout. Production remains NO-GO until signing and owner approval
exist.

## Status

READY_FOR_WINDOWS_RELEASE_AUTOMATION. Production NO-GO until Authenticode
certificate and explicit production approval exist.
