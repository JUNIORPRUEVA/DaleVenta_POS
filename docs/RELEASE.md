# FullPOS Cloud Release

Last audited: 2026-09-02.

Do not deploy during ordinary development tasks. Production is protected by default.

## Pre-Release Checkpoint

- Confirm release scope and owner approval.
- Confirm target environment: QA/UAT/staging/production.
- Run `git status --short`.
- Review current branch and pending changes.
- Confirm no unrelated or accidental business logic changes.
- Confirm no secrets are being committed or printed.
- Confirm database target and environment variables at a safe descriptive level.

## Validation Before Release

Minimum release validation should include:

- Flutter static analysis: `flutter analyze` from `apps/fulltech_app`.
- Relevant Flutter tests: `flutter test` or scoped tests.
- Backend build: `npm run api:build`.
- Relevant backend tests: `npm --workspace apps/api test` or scoped scripts.
- Functional QA for affected workflows.
- Visual QA for user-facing UI.
- Regression checks for tenant, auth, license, inventory, sales, cash, fiscal, and migration-sensitive areas as applicable.

## Build Procedures

API:

- Build: `npm run api:build`
- Docker image: `apps/api/Dockerfile`
- Runtime command: `sh scripts/start-prod.sh`
- Healthcheck: `/health`

Flutter PWA:

- Build locally from `apps/fulltech_app`: `flutter build web --release`
- Docker image: `apps/fulltech_app/Dockerfile`
- Nginx runtime env injection through `/env.js`.

Public Astro website + Flutter POS (FullPOS Cloud):

- Canonical combined recipe: `Dockerfile.public-web`, build context **repository
  root**. Its dedicated `.dockerignore` only admits public build inputs, not
  real environment files, backend code, backups or desktop/mobile artifacts.
- EasyPanel `daleventapos/pwa`: GitHub `JUNIORPRUEVA/DaleVenta_POS`,
  ref `production-main`, source path `/`, Dockerfile `Dockerfile.public-web`.
  Preserve existing runtime environment and build arguments, especially the
  actual DOSA publishable key. Never deploy the local test-key validation image.
- Build uses the existing Flutter release procedure plus an Astro static stage.
  The Flutter shell is preserved as `pos.html`; Astro overwrites public pages.
  Compressed siblings of overwritten files are removed so Brotli cannot return
  old HTML. Large Flutter assets retain Brotli.
- `/home` remains the app entry; PWA identity is unchanged and its launch URL
  opens `/home`. Astro auth pages use `/api` and hand off to `/home`.
- Static Nginx configuration and the runtime proxy template must implement
  the same public routes. Preserve API/uploads/webhook and certification paths.
- Before publication, record the current PWA image ID and EasyPanel source/build
  settings. Verify the combined image locally with an isolated API using
  `PUBLIC_WEB_TEST_URL=http://127.0.0.1:4016 node website/tests/public-web-smoke.mjs`.
- Test registration in two steps, existing login, duplicate/invalid credentials,
  ticket reuse/concurrency, expiry, recovery and POS refresh. Complete
  desktop/mobile visual QA. Do not create test business data in production.
- This integration adds no database migration, seed or fiscal behavior change.
- Rollback: redeploy the saved previous PWA image; restore source path
  `/apps/fulltech_app` and Dockerfile `Dockerfile` for later legacy builds.
  Keep the current API and database; database restore is not part of UI rollback.

iOS:

- Workflows in `codemagic.yaml`:
  - `ios-release-no-codesign`: builds the iOS release and publishes an unsigned IPA
    plus `Runner.app` as artifacts (no store upload).
  - `ios-testflight`: signs with the App Store profile, builds the IPA from
    `apps/fulltech_app/ios/ExportOptions.plist` and uploads it to App Store Connect.
- Requirements before running `ios-testflight`:
  - Codemagic App Store Connect integration named `CodemagicKey`.
  - `ios_signing` distribution profile for `com.fulltechrd.fullposcloud` and team `M4WNZDXN2U`.
  - Manual signing expects the provisioning profile named `fullposcloud_app_store`
    (`ExportOptions.plist`). If the profile is renamed in Apple, update the plist.
  - An App Store Connect app record must exist for `com.fulltechrd.fullposcloud`.
- Build numbers: the workflow computes `$PROJECT_BUILD_NUMBER + 100` (Codemagic counter) and stops
  when it is not higher than what was already uploaded, so TestFlight never receives a duplicate.
  The marketing version comes from `version:` in `apps/fulltech_app/pubspec.yaml`.
- Before publishing, `codemagic.yaml` runs `scripts/build/verify_ios_ipa.py` on the generated IPA:
  it reads `Payload/Runner.app/Info.plist` and aborts (no upload) when `CFBundleShortVersionString`
  differs from `pubspec.yaml`, when `CFBundleVersion` is below the workflow floor
  (`IOS_MIN_BUILD_NUMBER`), or when the bundle id is not `com.fulltechrd.fullposcloud`. It then
  verifies the signature with `codesign` and logs the identity and entitlements.
  The same script runs manually on any IPA: `python3 scripts/build/verify_ios_ipa.py <ipa>`.
  Never archive from Xcode without a prior Flutter build: `ios/Flutter/Generated.xcconfig` is
  generated and Xcode reads it, so a stale file ships a stale version.
- Runtime configuration: the workflow writes `apps/fulltech_app/.env` from `API_BASE_URL`
  (defaults to the DaleVentas production backend), optional `APP_BASE_URL`, `API_TIMEOUT_MS`,
  `RELEASES_API_BASE_URL` and `RELEASES_API_KEY`. Keep those in Codemagic, never in the repository.
- Icons: `ios/Runner/Assets.xcassets/AppIcon.appiconset` is generated by
  `scripts/branding/generate_app_icons.py`; the PNGs must stay opaque (App Store rejects alpha in icons).
- `Info.plist`: keep a usage description for every permission the plugins request, and list custom
  schemes used with `canLaunchUrl` under `LSApplicationQueriesSchemes`.
- `submit_to_testflight` is `false`: the IPA is uploaded and must be submitted from App Store Connect,
  or set the flag to `true` to let Codemagic submit it.
- The IPA cannot be built on Windows; the first real iOS build happens on Codemagic (macOS/Xcode).

Android:

- Flutter platform folder exists. Package with the approved store or sideload workflow for the target release.

Windows:

- Official DaleVentas Windows Release builds must be created with
  `scripts/build/build_windows_release.ps1`. The script fixes the DaleVentas
  API host, rejects FullPOS Owner hosts, sets `FULLPOS_PRODUCTION_BUILD=true`,
  and verifies the generated runtime artifact before installer packaging.
- While Windows releases are temporarily unsigned, the official build script
  injects `ALLOW_UNSIGNED_UPDATES_FOR_PRODUCTION` and
  `UPDATE_DOWNLOAD_ALLOWED_HOSTS` via `--dart-define`. This is a bridge policy
  only: clients must not edit `.env`, and a future signed build must set the
  production unsigned flag back to `false`.
- Run Windows builds from a real short Git worktree, for example
  `C:\src\fullpos-release`. Do not rely on `subst` for release builds: Flutter,
  CMake and MSBuild can mix physical and mapped paths in generated files, and
  native plugin targets can exceed the Windows 260-character path limit when the
  checkout is under a deep path.
- The Flutter app declares `.env` as a bundled asset. The Windows release script
  creates a temporary non-secret `.env` with the DaleVentas API host when the
  file is missing, so a clean short worktree can build without copying local
  secrets.
- Package with `installer/setup.iss` through `installer/find_and_build_inno.ps1`.
- Official install root is `C:\Program Files\DaleVentas POS`.
- The user-visible product name is `FullPOS` (`MyAppName`), but the install root
  stays `C:\Program Files\DaleVentas POS` (`MyAppFolderName`) because the client
  resolves its databases, backups, media cache, logs and config there. Do not
  rename the folder or the `AppId`; `installer/README.md` explains the details.
- Application icons are generated by `scripts/branding/generate_app_icons.py`
  (multi-resolution Windows `.ico` plus the Android launcher master).
- Runtime files are installed under `app`; mutable local folders are `databases`, `backups`, `media_cache`, `logs`, `config`, and `updates`.
- Verify installer ACLs allow a standard Windows user to write `databases`, `backups`, `media_cache`, `logs`, `config`, and `updates`, while preserving those folders on uninstall.

## Migration Safeguards

- Never run production migrations without explicit authorization.
- Review Prisma migration files and production migration history before deploy.
- Do not edit already-applied migrations in shared/prod databases.
- For Prisma P3009 or drift, follow safe diagnosis in `apps/api/README.md`; do not delete the DB.
- Back up production before approved migration work.
- Verify startup flags such as `RUN_MIGRATIONS`, `PRISMA_SYNC_MODE`, and `MIGRATION_STRICT`.

## Seed Policy

- Production seed is forbidden by default.
- `RUN_SEED=true` and `npm run api:seed` require explicit authorization and verified non-production target unless a production owner explicitly approves.

## Deployment Procedure

High-level supported paths:

- API: Docker/EasyPanel using `apps/api/Dockerfile`.
- PWA: Docker/EasyPanel using `apps/fulltech_app/Dockerfile`.
- iOS: Codemagic workflow.

Before production deployment:

- Confirm backups/checkpoints.
- Confirm release notes and affected modules.
- Confirm migration plan and rollback considerations.
- Confirm smoke test plan.
- Confirm monitoring/log access.

## Smoke Tests

At minimum, verify:

- API `/health`.
- Login/session restore.
- Company/tenant context.
- Product/catalog load.
- POS/sales path if affected.
- Inventory/warehouse path if affected.
- Fiscal/tax/NCF path if affected.
- Cash/session path if affected.
- Media/upload path if affected.
- PWA runtime `API_BASE_URL`/proxy behavior if web release.

## Rollback Considerations

- Keep previous deploy artifact/image/build available.
- Database migrations may not be trivially reversible; plan rollback before applying.
- For app/PWA releases, verify runtime env and service-worker/cache behavior.
- For iOS/TestFlight, rollback may require promoting a previous build or shipping a new build.

## GO / NO-GO

Release is GO only when required tests, functional QA, visual QA, data safety checks, and rollback readiness pass.

Release is NO-GO when a critical validation fails, environment identity is uncertain, secrets are exposed, tenant isolation risk exists, migration state is unclear, or rollback is not acceptable.

## ECF manual predeployment checkpoint — 2026-11-13

HECHO: the three reviewed ECF migrations0400/0500/0600 are already applied
on daleventapos/database. Their original SQL/checksums and all previous ledger
rows are preserved. Do not rerun SQL manually, reset, db push, seed, rewind a
counter or restore an old database over current sales. Evidence and backups:
[ECF predeployment audit](ecf/ECF_PREDEPLOY_AUDIT_2026-11-13.md).

The candidate is based on production-main cada11f8 and carries only the reviewed
working-tree delta from the older fiscal checkout. Keep both EasyPanel services'
autoDeploy disabled. Commit, push and integration require explicit authorization.
No deploy was executed by the agent.

API dependency authority is the root package-lock.json. After an intentional API
dependency update, run node scripts/release/sync_api_docker_lock.mjs and review
the generated apps/api/package-lock.json. CI runs the same script with --check;
apps/api Docker uses npm ci. Never edit the generated API lock independently.
The Astro stage uses Astro7.4.12 and Node22.23.4-alpine. The two final Docker
stages accept GIT_SHA for org.opencontainers.image.revision. Build outside
production; local QA images contain a synthetic assistant key and are not release
artifacts. Preserve the existing EasyPanel public assistant key/environment.

The API builder/runner and API CI also pin Node22.23.4 LTS. PR41's admission,
atomic fiscal preparation and ordinary-printing corrections add no schema
change. Keep production gates disabled during review; merge readiness does not
authorize activating them or deploying. Recheck the final PR head and all CI
jobs, including the isolated PostgreSQL atomic-checkout regression.

Manual operator order after the candidate is committed, reviewed and integrated:

1. Verify the expected commit and CI result. Run
   scripts/release/verify_ecf_server_predeploy.ps1 from PowerShell7. This read-only
   checker returns2 while the production gates are not prepared; this is a block,
   not permission to bypass it. Review backup freshness before the actual rollout.
2. Prepare backend DOSA_PRODUCTION_EMISSION_ENABLED=true and
   DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED=true in EasyPanel, under owner control.
   Preserve RUN_MIGRATIONS=false, disabled seed, credentials, mounts and all other
   existing settings. Saving configuration is not an instruction to restart.
   These global permissions alone never activate a company or emit an invoice.
3. Build immutable images outside the production host and record commit/digests.
   The user deploys the API first. Verify /health, authentication/company context,
   own-environment credentials, Normal intent and readiness before any new client.
4. The user deploys the combined PWA only after the compatible API is healthy.
   Preserve the current repository-root context and Dockerfile.public-web. Verify
   public/auth/POS routes, runtime API/proxy and DOSA assistant configuration.
5. Each company independently completes the existing assistant/certification,
   explicitly enables production and registers its own DGII authorizations/ranges.
   A company without available ranges does not gain the POS fiscal selector.
   Never copy FULLTECH credentials, TEST metadata or counters to another company.
6. Record post-deploy health, expected revision and acceptance evidence. A live
   fiscal invoice is a separate business operation, never a smoke-test sale.

Rollback: retain the new additive schema. Before clients with the new Normal
intent are released, the saved prior API image can be restored under an approved
rollback procedure. Once new clients are active, keep a compatible API or fix
forward; the old API does not understand the new Normal marker. A PWA rollback
must retain the compatible API and database. Do not drop columns or restore the
whole historical database over intervening sales. Database restore needs its own
maintenance/reconciliation plan and owner authorization.
