# Execution State

## Current work — consolidate deployed CRM licenses and PR45 (2026-11-15)

Owner authorized local consolidation after the deployed backend changed to
crm-license-daleventas:87316912. Own worktree C:/src/fullpos-license-fiscal-20261115,
branch agent/consolidate-license-fiscal-20261115. Base221d530c contains PR45 and
all approved design/fiscal work. Commit87316912 is merged without conflicts,
preserving its ancestry; only six license files are added/changed by that merge.
The original license worktree has uncommitted usage/activity work and is read-only;
none of those unfinished changes or migrations enter this consolidation.
Plan: preserve the deployed license implementation, verify HTTP authentication
and tenant-safe/idempotent commands, run license and fiscal PostgreSQL regression,
then review the final diff and create the reviewable checkpoint. No merge into
production-main, production migration/configuration change or deploy is authorized.
Dedicated local PostgreSQL56701 will contain separate disposable fiscal and CRM
fixture databases, with synthetic credentials and external emission disabled.
The CRM fixture guard admits that exact loopback port and name, rejecting URL
query/hash. Build PASS, CRM PostgreSQL12 PASS, HTTP boundary6 PASS, fiscal
atomic/readiness/returns PostgreSQL32 PASS. Docker lock756 packages PASS.
Full backend suite3353 PASS/101 skipped,280 suites PASS/13 skipped (300.688s).
Additional license/fiscal preservation regression1 PASS, executed separately.
Fiscal HTTP regression44 PASS/3 suites. Full built Nest application HTTP smoke
8 PASS with synthetic companies:bridge auth, legacy license endpoint, versioning,
deduplicated command and tenant-specific session revocation. Additional regression
typecheck PASS. Audit generators168 models/435 endpoints; CI YAML parse PASS.
Local consolidation validated; preserve both parent histories in its checkpoint.
GitHub checks for the review head are still a separate gate. No product UI,
schema/migration/lockfile/Dockerfile changes. Do not deploy the old221d530c API
over the live license backend. Owner retains main merge and deployment.
Original activity
writer changed two uncommitted activity files during this task; original HEAD
remains87316912 and no edits from this consolidation target that worktree.
Do not claim the original worktree is frozen. Deploy remains NO-GO.

## Current acceptance — PR45 (2026-11-14)

Owned worktree/branch below; PR45 targets production-main and remains owner-controlled.
Initial commits5bbc36b7/385df9f7 preserved. Four CI jobs passed at385df9f7.
Isolated real API/PWA acceptance found normal-sale Web PDF blocked by native
SQLite printer settings. Minimal fix returns browser defaults in getOrCreate,
preserving native storage and avoiding legacy cross-company receipt identity.
Browser regression and Chrome CI step added; no dependency/schema/runtime change.
Post-fix analysis PASS135.7s; settings/printing/PDF regression228 PASS,1 explicit
browser-only skip. Windows Chrome test harness blocked by SDK CanvasKit404;
new Linux CI Chrome test must be verified, not inferred from earlier CI success.
API17 checks, print projections5, returns6 PASS with fictional Alfa/Beta and
zero external emission attempts. Real E34 export/QR decode and transient offline
notice verified in isolated browser. Fiscal accepted statuses are synthetic.
Rebuilt combined UAT PWA PASS; actual history NORMAL PDF download PASS with
ITBIS18/total118 and zero fiscal print reads. E31 PDF download PASS with one
fiscal print read, fixture expiry and decoded QR. NORMAL/E31/E34 PDF rendering
and extraction PASS; both fiscal QR decode PASS. Offline recheck:0 fiscal POST.
Web filter segment text and fixture em-dash PDF glyph remain visual observations;
no cold deep-link, physical printer/device or service-worker acceptance claimed.
See docs/VISUAL_FISCAL_UAT_20261114.md for evidence, limitations and final gates.
No source worktree or production data/config changed; no merge/deploy authorized.

## Current work — integración visual/fiscal segura (2026-11-14)

Own worktree C:/src/fullpos-integration-20261114,
branch agent/integrate-visual-fiscal-20261114, base origin/production-main cbc3eceb.
Owner requested preserving all detalleVisuales and fiscal work before integrating
to production-main. Source snapshots/hashes complete; design72 modified+245 new,
fiscal55 modified+77 new, plus three raw-normalized generated files preserved.
Original checkout preserved separately; no source worktree cleaned or modified.
Two design conflict files resolved preserving fiscal badge/panel and visual drawer.
Fiscal patch applied cleanly afterward. API build PASS; final automated validation PASS.
Dedicated disposable PostgreSQL in loopback55500; no production DB/config touched.
Current report:docs/VISUAL_FISCAL_INTEGRATION_20261114.md.
Private evidence/scripts: C:/Users/pc/.codex/backups/fullpos-visual-fiscal-integration-20261114/.
API final3341 PASS/101 skipped; return PostgreSQL15 PASS; HTTP3 suites/44 PASS.
Full Flutter final2426 PASS/9 skipped/0 failures in about10min, after stale UI assertions,
reviewed references and bounded SQLite waits were corrected. Earlier failures
are documented in the report, not hidden. Focused fixes179 PASS; cash19 PASS.
Full web UAT build PASS156.9s; website12 tests/check/build PASS; full analysis
PASS278.4s and final10 modified helper/test files PASS48.1s.
Linux final42 visual tests PASS, without update mode; eleven Linux PNG references
copied back after inspection (seven logo/search plus four header border images).
Windows selected14 PASS; final full suite verifies Windows references normally.
Tenant inventory168 models/endpoint matrix431 rows generated successfully;
timestamp-only changes preserved privately and excluded from the candidate.
Final provenance449 source records:434 byte-identical,15 merged/reviewed,
no missing files, no changed originals, no high-confidence secret candidates.
Final candidate inventory472 paths in docs/VISUAL_FISCAL_INTEGRATION_FILES_20261114.md.
Integration test helper added at test/support/feedback_finders.dart. Preserve
semantic X close affordance; no tooltip reintroduced into approved design.
Generated notification screenshots copied privately and restored narrowly to HEAD;
Windows failure evidence moved safely into the task backup, excluded from Git.
App .env is synthetic/ignored. No schema/migration/lockfile/Docker diffs.
The later acceptance above adds a Chrome CI regression step.
Remote re-fetch confirms cbc3eceb; branch upstream removed to avoid an accidental
default push to production-main. Original worktrees remain untouched.
Owner subsequently authorized commit/push/PR of this exact integration candidate.
Only agent/integrate-visual-fiscal-20261114 may be published, targeting production-main.
Do not force-push, merge, deploy, restart or change production data/configuration.
NO-GO for release: PR CI and real UAT remain gates. Local evidence above is final;
consult the actual PR checks for publication status, not these frozen local results.
The previous task state below is retained as source history, not current status.

## Current work — paired fiscal design review (2026-11-14)

Owner requested a preview and joint screen-by-screen refinement before any deploy.
Owner selected Empresa and the fiscal module entry as the first review scope.
All previous self-service changes remain on the same owned isolated worktree and
branch below; no other worktree or production operation is authorized.

Current design iteration explicitly requested by owner:
- Owner resolved "screen20" as19 fiscal configuration. Updated only that
  layout and its numbering summary: responsive two-column panels on desktop,
  one column on mobile, rectangular6px buttons, compact existing consent switch,
  readable stacked numbering metadata, no empty document-types panel.
  Existing permission checks, confirmation text and repository writes preserved.
  Added desktop640px control-visibility/button-shape regression plus actual
  preview1280x760 E34-action visibility check.55 regression tests PASS before
  the final text-button border polish; scoped analysis4 files PASS (4.2s).
  Final14 preview tests PASS after final border polish. Final scoped analysis
  four files PASS (3.9s), git diff --check PASS. Preview compiled31.3s,
  session3652, HTTP200 at localhost4804. Desktop1280x760 and390px mobile
  widget captures inspected and archived at docs/ecf/config-compact-design-2026-11-14/.
  Logs:config-compact-tests-final.log, config-compact-preview-final.log,
  config-compact-analyze-final.log, config-compact-server.log.
  No browser/device interaction or production operation. Deployment NO-GO.
- Owner requested compact tracking (4–6), a single centered pending-close card
  (15), rectangular tray filters/search and finer rows (16–18). Implemented in
  existing widgets only: tracking max-width700/neutral subtitle, embedded
  numbering in a single pending EcfSurface,6px tray controls/row borders and a
  compact neutral connection-error row. Selected-filter text contrast corrected.
  The optional embedded flag defaults false, preserving other EcfSection callers.
  Gallery fixtures now use actual known pending reason and AUTHORIZED_SANDBOX
  for the certified example; previous demo values caused raw/fallback messages.
  Pending-close fixture uses fictional PRODUCTION numbering for customer copy.
  Regression82 tests PASS across preview/tray/completion/numbering/flow/activation.
  Final preview13 tests PASS after fixture adjustment; scoped analysis9 files
  PASS (66.8s). Preview compiled40.3s, session35363, localhost4804 HTTP200.
  Desktop/mobile captures inspected for tracking, close15, tray16 and error18;
  fourteen captures archived at docs/ecf/compact-fiscal-design-2026-11-14/.
  Final diff reviewed and git diff --check PASS. No production changes.
  Logs:compact-fiscal-tests.log, compact-fiscal-preview-final.log,
  compact-fiscal-analyze.log and compact-fiscal-server.log.
  Owner also mentioned screen20, but gallery has only4–19: async clarification
  asks whether this means19 configuration or the E34 dialog; no reply yet.
  Do not claim that unidentified screen completed.
- Owner requested multiple remaining screens for joint review. Added local-only
  EcfDesignGallery (test/preview) with16 scenarios numbered4–19: request/tests/
  certification/network failure, unsigned/signed authorization, production
  action, new/active/expired numbering, ready/incomplete closure, documents
  populated/empty/error, and fiscal configuration. All mount real widgets;
  no production UI or fiscal behavior changed in this iteration.
  Numbering/configuration use synthetic PRODUCTION data to review the actual
  customer labels; no credential or real authorization is used. Other examples
  remain synthetic SANDBOX. HTTP stays blocked by the existing adapter.
  Inventory:docs/ecf/FISCAL_DESIGN_REVIEW_2026-11-14.md lists what is present
  and all identified auxiliary/admin/dialog/printing areas still to review.
  Initial gallery tests found Riverpod nested-scope dependencies; explicit
  local provider overrides and a local Navigator fixed the fixture. A subsequent
  page/list return-type compile error in that override was corrected.
  Final13 tests PASS across390/1280px, exercising all16 gallery scenarios plus
  existing Empresa/welcome/preparation regressions. Final scoped analysis of
  three preview files PASS (3.7s); git diff --check PASS.
  Generated32 gallery captures; inspected mobile documents/authorization and
  desktop production-numbering. Evidence:docs/ecf/gallery-design-2026-11-14/.
  Logs:gallery-tests-final.log, gallery-analyze-final.log, gallery-server.log.
  Browser interaction and physical devices remain unverified. Deployment NO-GO.
- Preparation follow-up: owner requested neutral FullPOS-facing assistant copy
  and optional managed setup advertising for US$150 paid once. Removed DOSA
  from the preparation card description only; provider integration is unchanged.
  New EcfManagedSetupOffer below the primary card reuses SupportConfig (the same
  contact used by features/assistant/data/assistant_whatsapp_service.dart).
  Opens WhatsApp with a prepared inquiry; no automatic message/payment/session.
  A brief fade/slide entrance respects reduced-motion/accessibility preferences.
  No perpetual animation, popup or change to primary postulation action.
  Local regression:59 tests PASS (offer, preview, fiscal steps, DOSA section).
  Tested URI target/message, 320/700px with1.4x text, reduced motion and CTA.
  Desktop/320px rendered captures inspected; three preparation captures archived
  at docs/ecf/managed-setup-design-2026-11-14/. No real WhatsApp message sent.
  Scoped static analysis PASS:five files, no issues (122.5s).
  Preview compiled in45.3s, session43077, HTTP200 at localhost4804.
  Logs:managed-setup-tests.log, managed-setup-analyze.log,
  managed-setup-server.log. Final diff reviewed; git diff --check PASS.
  Browser/physical-device interaction remains unverified; native widget renders
  and navigation were checked. Production remains NO-GO until owner approval.
- Welcome follow-up: owner requested only refinement of the video and text
  columns, then access to the next screen. Balanced desktop columns, aligned
  video padding and readable14px step descriptions preserve the existing flow.
  The missing-video state remains explicit, without a disabled duplicate action;
  its caption no longer incorrectly references three DGII prerequisites.
  Preview now exposes `3. Preparación` directly; Comenzar still navigates there.
  Fixed its incomplete fixture: the real DosaAssistantSection now receives local
  eligibility and intent responses. Previously the fixture lacked dosaEntry and
  displayed a permission notice instead of the postulation card. Registration
  is overridden to reject locally, with no real provider/session request.
  Regression asserts the real card/button, the blocked action and return route.
  No video uploaded, no provider/session opened and no production touched.
  Validation:44 preview/fiscal-flow/certificate tests PASS. Initial run failed
  only on an assertion of the replaced introduction; updated to the intended
  copy, then all44 passed, including the final complete preparation fixture.
  Final scoped analysis of six files PASS (4.8s).
  Screenshots at320/390/1280 plus compact desktop generated; desktop and320
  inspected; the final real preparation card was also visually inspected.
  Browser interaction remains unavailable; these are widget renders.
  Evidence logs:welcome-design-tests-final.log, welcome-design-analyze-final.log.
  Updated preview compiled in40.3s, session43386, HTTP200 on localhost4804.
  Captures archived at docs/ecf/welcome-design-2026-11-14/.
  Deployment remains NO-GO pending explicit owner authorization.
- Owner approved the compact company design, then requested visible optional logo
  upload and a cleaner mobile appbar, and explicitly authorized advancing to the
  next screen after those corrections. Logo upload/change now appears in the data
  header using the existing picker/normalization/save flow. Only Empresa opts
  into a plain mobile AppBar (title/back/sync), avoiding web-session window pills
  in that narrow header. Other screens retain their existing bars.
- Next joint screen: fiscal welcome. Corrected its inaccurate "sin salir de
  FullPOS" copy to explain browser handoff and return. No external session is
  opened by the local preview. Remaining welcome design is for owner review.
- Follow-up regression95 tests PASS (preview, account, fiscal flow). Scoped
  analysis PASS with no issues (40.5s); final preview9 tests PASS after the upload
  label adjustment. Logs: company-logo-appbar-tests.log,
  company-logo-appbar-analyze.log and company-logo-preview-final.log.
  Follow-up files: account_menu_screens.dart, ecf_welcome_step.dart,
  ecf_design_preview_test.dart, PRODUCT_SPEC.md, EXECUTION_STATE.md and the three
  existing company-design screenshots. No global appbar behavior was changed.
  Preview server session13420 compiled in21.3s and serves HTTP200 at
  http://127.0.0.1:4804/ for the next joint review. Final screenshots refreshed.
- Default company fields: name, optional RNC, phone/address; optional legal
  representative name/ID remain visible. Header disclosure "Ver más" contains
  logo, fiscal email, other contacts, extra representative fields and banking.
- "Activación de módulos" is a flat responsive set of columns, with compact
  rectangular switches beside their labels; existing confirmations and permissions
  remain. Inventory and sales share columns in phone widths where they fit.
- Same controllers/save contract preserve hidden values. A save regression
  exposed existing loss of additional bank accounts; retaining the existing tail
  fixes it without changing the primary-account editing contract.
- Local widget regression93 PASS: company save with hidden data and empty
  optional identity fields, disclosure persistence, consent/permissions/tenant
  navigation, keyboard/disabled semantics, desktop1264x681 without scrolling,
  Android/iPhone-sized mock views. This is layout simulation, not device QA.
- First analysis found two deprecated test semantics calls; updated to current
  flagsCollection API. Final whole Flutter analysis PASS (96.5s). Early test issues
  (semantics handle cleanup, old title assertions and a generic dropdown finder)
  were corrected; no failing assertion was disabled.
- Desktop, Android-sized and iPhone-sized screenshots rendered with real widgets
  were inspected and retained in docs/ecf/company-design-2026-11-14/.
- Only generated unrelated notification PNGs from this run were restored to HEAD.
  Other worktrees, production data/config and the previous fiscal work are intact.
Validation commands actually executed from apps/fulltech_app:
`flutter analyze --no-pub`: PASS, no issues.
`flutter test --no-pub test/core/widgets/compact_square_switch_test.dart test/preview/ecf_design_preview_test.dart test/features/account test/features/ecf/ecf_sales_without_document_section_test.dart`:
93 PASS. Evidence in company-design-analyze-final.log and
company-design-regression-final.log under the private backups folder.
Final diff review/check PASS; unrelated generated notification images restored.
Preview was stopped only for sequential validation, recompiled successfully in
21.8s and serves HTTP200 on127.0.0.1:4804 (server session65713).
No commit/push/merge/deploy is authorized here.
Owner review of this company screen is next, before moving to another screen.

Files in this company design iteration:
apps/fulltech_app/lib/features/account/account_menu_screens.dart;
apps/fulltech_app/lib/features/ecf/ui/ecf_config_page.dart;
apps/fulltech_app/lib/core/widgets/compact_square_switch.dart;
apps/fulltech_app/test/core/widgets/compact_square_switch_test.dart;
apps/fulltech_app/test/features/account/account_settings_navigation_test.dart;
apps/fulltech_app/test/features/account/ecf_company_toggle_drawer_test.dart;
apps/fulltech_app/test/features/account/settings_notifications_visual_qa_test.dart;
apps/fulltech_app/test/features/ecf/ecf_sales_without_document_section_test.dart;
apps/fulltech_app/test/preview/ecf_design_preview_test.dart;
docs/DESIGN_SYSTEM.md; docs/PRODUCT_SPEC.md; docs/EXECUTION_STATE.md;
docs/ecf/company-design-2026-11-14/empresa-escritorio-compacta.png;
docs/ecf/company-design-2026-11-14/empresa-android.png;
docs/ecf/company-design-2026-11-14/empresa-iphone.png.

New test-only entry point: apps/fulltech_app/test/preview/ecf_design_preview.dart.
Uses AccountCompanySettingsScreen, EcfWelcomeStep and EcfPreparationStep directly,
with synthetic in-memory repositories, simulated auth and an HTTP adapter that
rejects every network request. No deployment .env values are loaded. The UI lets
the owner navigate Empresa/entry, change desktop/Android/iPhone/tablet layout
sizes, test the fiscal switches and reset demo state. Layout simulation is NOT
physical-device QA. External postulation is not opened from the preparation CTA.
The baseline preview is now updated by the company design iteration above.
Welcome and later fiscal screens await the next joint review; the welcome copy
promising "sin salir de FullPOS" despite native external-browser handoff remains
an identified item for that screen, outside this company-only iteration.

Initial preview analysis/four widget tests passed before this design iteration;
current final counts are recorded above. Existing company/portal/assistant
baseline61 tests had passed. Six initial screenshots were rendered before the
company redesign; current design screenshots are listed above.
Local preview includes the startup correction and new company design; current
server session65713 runs on127.0.0.1:4804 with HTTP200 for joint review. Older
sessions15120/25488 were stopped only for local correction/validation.
Do not stop the current preview while the owner reviews it.
Interactive browser rendering is owner review, not an automated browser PASS.
Private logs/screenshots remain under
.codex/backups/fullpos-ecf-selfservice-20261114/design-preview*.
Company UI redesign was explicitly requested and implemented in this iteration.
No backend edit, commit, push, merge or deployment was performed in this design
step. Await owner feedback, then iterate together; do not advance through the
remaining screens without that review.
Production/new deployment stays NO-GO. Previous browser/device QA limits remain.

Preview startup follow-up: owner reported an indefinite loading cover. Root cause
confirmed in source: web/index.html keeps #app-loader until the existing
fullposCompleteWebStartup hook is called, and the new preview omitted that hook.
Preview now calls the shared completeWebStartup helper after its first rendered
frame. Production startup/shell code is unchanged. A new lifecycle regression
checks that completion happens after content exists and only once across
navigation/reset; all5 native preview tests PASS, analysis of all3 preview/test
files PASS. A browser-only regression was added, but its Chrome
runner stalled at loading before executing assertions and was aborted. Browser
access MCP also remains unavailable; no browser functional PASS is claimed.
Only the verified old local preview and owned stalled test process tree were
stopped; no user browser or production service was stopped. Preview recompiled
successfully and serves HTTP200 on the same127.0.0.1:4804 URL. Owner should reload
to receive the fixed entry point; actual browser confirmation remains pending.
Private evidence: design-preview-startup-{analyze,tests,red}.log. The "red" log
contains an interrupted browser startup, NOT an executed RED assertion.

## Previous work — self-service e-CF hardening (2026-11-14)

Owner explicitly authorized local investigation, fixes and full simulated QA for
all-company self-service. New isolated worktree C:/src/fullpos-ecf-selfservice-20261114,
branch agent/ecf-selfservice-hardening-20261114, based on merged PR44/cbc3eceb.
Original dirty workspace and all other worktrees are preserved. No production
access or mutation is needed; FULLTECH's previously verified activation remains.
No deploy/restart/configuration/migration or real invoice is authorized here.
Deployment stays NO-GO pending a new explicit owner authorization.

Confirmed root cause: form authorization expiry is not passed to the operational
range; POS asks for the E31 expiry on checkout and the sale trusts that input.
Plan: use own company/environment authorization as the server source, retain old
contracts/data/counters, remove repeated date entry, prove new-company self-service
and security on a fresh local PostgreSQL database with localhost external mocks.
Implementation derives E31 expiry on server/new ranges, projects it to POS,
validates dates and own authorizations, scopes fiscal providers to session/company
and hides unnecessary TEST numbering before production opt-in. Customer-route
HTTP case completes two synthetic onboarding/certification/production/E31 cycles
with signed localhost-mocked outcomes and separate credentials/dates/QR.
Audit also reproduced revoked/expired auto-enrollment being replaced and a
standalone preparation race between expiry resolution and allocation. Both have
RED-to-GREEN regressions and minimal locking/recheck fixes. Old E31 test fixtures
now include consistent synthetic expiry; no production range/history was rewritten.

Final PASS: API build; strict types for four principal specs; general backend
240 suites/2887 tests (555 opt-in skipped); ECF PostgreSQL160 suites/2054 tests;
atomic/readiness/sequence/environment PostgreSQL4 suites/39 tests; HTTP3 suites/44
tests; Flutter analyze; full Flutter2266 tests (9 skipped before two new scope
regressions); final focused Flutter128 tests including those new regressions;
release web JS build with loopback API target. Static inventories:168 models,
431 endpoints; unsafe query heuristic audit0 errors/298 warnings, reviewed in
changed scope without suppressing warnings. Diff reviewed/check passes.

Six screenshots rendered with real Flutter widgets and AppTheme.light were
generated; mobile/desktop PNGs inspected. Interactive browser QA remains pending:
browser access host unavailable, native CUA blocked on URL confidence, stopped
and completed. Do NOT retry or bypass CUA this turn. Synthetic preview on4803
was stopped. Only two owned task-labelled local PG containers were used on
55500/55501, both verified and stopped (Exited0) at closeout; no allowlist was
relaxed, no production access occurred. Temporary
native DLL contention and a Supertest auto-close race were corrected/revalidated;
final evidence and exact commands are in the report/private logs.

No commit/push/merge/production action occurred. Changes remain on the isolated
branch for review. Browser QA and explicit owner authorization are required before
any new deployment. See docs/ecf/ECF_SELF_SERVICE_HARDENING_2026-11-14.md.

## Previous work — commercial E31/refund/E34 closeout (2026-11-14)

Mode: CONTINUOUS_CONTROLLED_EXECUTION. Owner asked to finish the remaining fiscal
work before a later design phase. Existing user-controlled merge/deploy and
separate production activation gates remain. No live commercial QA data writes.

Fresh worktree C:/src/fullpos-ecf-commercial-closeout-20261114, branch
agent/ecf-commercial-closeout-20261114, starts at merged PR43/38142fce. Other
worktrees, the immutable PR43 source and preparation branch remain untouched.
The owner-deployed PWA d56a9c97 and healthy API4e6fb33c were already verified;
actual accepted TEST E31/E34 PDFs now pass preview, download, fields and QR checks.

Audit found separate HTTP tests for sale/emission/manual E34 and PostgreSQL
tests for financial refunds, but no single HTTP checkout -> financial return ->
E34 acceptance regression. Added three synthetic end-to-end cases to the existing
CI suite: normal response, lost provider response, and missing E34 range followed
by fiscal-only recovery. Initial focused run:3 PASS/26 intentionally filtered.
Each asserts one financial refund/stock return, net cash0, ITBIS18, one E34
allocation/applied credit, unchanged financial state on replay and cross-tenant
denial. All provider traffic is loopback; no real DOSA/DGII calls.

Full API build PASS. Existing regressions PASS:3 HTTP suites/43 tests,
5 PostgreSQL suites/48 tests,240 unit/general suites/2882 tests.52 opt-in suites
and547 tests are intentionally skipped by the general run. An extra strict
TypeScript check found two old fixtures missing encf; explicit empty values
preserve server allocation and the changed suite now typechecks. Final HTTP
revalidation after those two fixture corrections:3 suites/43 PASS. Tests ran
on a fresh owned local postgres:16-alpine container fullpos_ecf_closeout_20261114,
loopback55500, label fullpos.task=ecf-commercial-closeout-20261114. No restored
customer data, shared database or external credential is used.

Fresh tenant-scoped live read-only audit confirms FULLTECH has own ACTIVE keys
for both environments, certification PRODUCTION_READY and no unresolved TEST
results (four reviewed legacy trials remain unchanged). Stored production
authorizations/ranges are E31=1–150/next3, E32=1–1000/next3, E34=1–50/next2.
E31 authorization expires2027-12-31 but all operational range expiries are null;
E32/E34 authorization expiries are null. The two persisted authenticated webhook
summaries contain no numbering metadata. The owner confirmed he registered the
FULLTECH database values and requested using them; preserve those declarations,
not the generic email range. No further numbering information request is pending.
The concrete E31 operational renewal proposal is start/next3,end150,expiry matching
its existing2027-12-31 authorization; preserve E32/E34 and all consumed counters.
Do not invent dates for null declarations. Production changes remain unexecuted.

Local implementation and validation are complete. Publish only the new
test/documentation branch and require green GitHub controls on its final head
before merging; then present the concrete production operation
in docs/ecf/ECF_COMMERCIAL_CLOSEOUT_2026-11-14.md for separate owner authorization.
Global production flags, company production opt-in, migrations and seed stay off.
Production activation requires the separate owner gate; no real invoice is a
smoke test. Private tools/evidence: C:/Users/pc/.codex/backups/
fullpos-ecf-commercial-closeout-20261114/.

## Previous work — deployed TEST acceptance and numbering access (2026-11-14)

The owner deployed both final PR42 images. Read-only inspection confirms API
4e6fb33c and PWA542cc3d8, from3217f0cd; merged ac729b16 has the identical tree.
API is healthy on Node22.23.4. Production fiscal flags, company production
activation, automatic migrations and seed remain off. Owner retains merge/deploy.

Authorized FULLTECH SANDBOX acceptance is successful: E310000000003 and its
total E34 E340000000002 were each dispatched once from the actual PWA and are
DGII_ACCEPTED. Each has a bound HTTP200 receipt, immutable fiscal snapshot and
official TEST QR query showing Aceptado. E34 credit118.00 is APPLIED once.
Drafts use existing services, the real verified operator and MANUAL source,
without a commercial sale. Confirmed TEST authorizations are1–10000000, expiry
2028-12-31; operational starts preserve historical frontiers E31=3/E34=2.

Whole-row fingerprints/counts for FULLTECH sales, cash sessions/movements and
inventory movements match the pretrial checkpoint. Five legacy document row
fingerprints, production ranges/counters and production authorization
fingerprint also match. No historical promotion, production issuance, new
migration, restart or deployment was performed by the agent.

New live finding: completed onboarding hides its numbering form as soon as E31
makes POS ready; configuration had only a read-only range overview. Minimal
fix reuses EcfSequenceRangeSection in configuration for enabled companies with
manageEcfSequences, keyed by company/user/environment to cancel stale forms.
Fresh isolated branch agent/ecf-numbering-access-20261114 at
C:/src/fullpos-ecf-numbering-access-20261114 is based on merged ac729b16.
The merged PR42/release preparation branches and unrelated worktrees are intact.

Six new widget regressions pass; full Flutter analysis passes;661 tests pass
in e-CF/printing plus a temporary read-only print projection probe (removed).
390/1280 widget screenshots inspected. Web release compilation passes;
publication/CI is pending. No backend/schema/dependency change.

E31 PDF opens/downloads from the deployed PWA. Both actual TEST backend print
projections generate valid A4 and58/80mm representations with matching decoded
QR and fiscal fields. Physical hardware was not exercised. E34 deployed preview
could not be completed because the browser moved to the public site on two
attempts; cause unconfirmed. User asked to leave the PWA on fiscal documents.
Do not claim that preview passed or repeat an accepted fiscal send.

Private receipts/helpers/rendered evidence are under
C:/Users/pc/.codex/backups/fullpos-ecf-test-close-20261114/.
See docs/ecf/ECF_LIVE_TEST_ACCEPTANCE_2026-11-14.md. Next:
review/publish the small UI fix, verify CI and close deployed E34 preview if the
user leaves the PWA available. Production emission remains NO-GO pending the
separate operator readiness/activation gate; do not change global permissions.

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

Publication checkpoint: PR42, sourcea1885097, passed all four GitHub gates
(43605208442):2247 Flutter tests PASS/16 gated skips, backend/security,
public website and Windows updater PASS. The final runtime review then found
the proxy-generated Nginx template lacked the PDF module rule. That template
is now corrected as well; local before/after HTTP proved octet-stream/HTML200
becomes JavaScript/versioned cache/404. Combined-image smoke now covers these
assets. Sourcea188 images are superseded and must not be deployed; the final
commit needs its own CI and immutable images. No deployment occurred.

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
