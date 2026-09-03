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

iOS:

- Codemagic workflows in `codemagic.yaml`.
- TestFlight workflow builds IPA and can publish through App Store Connect integration.

Android/Windows:

- Flutter platform folders exist. OWNER VALIDATION REQUIRED for the current official production packaging path.

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
