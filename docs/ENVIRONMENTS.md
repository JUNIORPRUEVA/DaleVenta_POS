# FullPOS Cloud Environments

Last audited: 2026-09-02.

Do not store secrets in this document. Secret-bearing files exist locally; report only their paths and purpose, never their values.

## Environment Files Observed

- Root `.env`: present locally, contains real backend/service configuration and secrets.
- `apps/api/.env`: present locally, ignored, contains API configuration.
- `apps/api/.env.docker`: present locally, ignored, used by API Docker Compose.
- `apps/api/.env.uat.local`: present locally, ignored, used by local UAT scripts.
- `apps/api/.env.example`, `.env.docker.example`, `.env.staging.example`, `.env.uat.local.example`: templates.
- `apps/fulltech_app/.env`: present locally, app runtime/build configuration.
- `apps/fulltech_app/.env.example` and `apps/fulltech_app/assets/.env.example`: templates/fallback examples.
- Codemagic workflow creates app `.env` during CI from environment variables.

## Local / Development

Purpose:

- Developer implementation and local validation.

Identification:

- Local shell, Flutter runs, API `start:dev`, local `.env` files.
- API default port is `4000`.

Backend/API target:

- Depends on `.env`; must be verified before running commands.

Database target:

- `DATABASE_URL` controls target. Treat any remote host or production-like database name as protected.

Allowed operations:

- Static analysis and tests.
- Local Flutter run/build.
- Local API dev server.
- Local-only migrations only after confirming the database is disposable/development.

Forbidden operations:

- Seeds, purges, destructive repairs, or migrations against production/shared DB without explicit authorization.
- Printing env values or secrets.

Migration policy:

- `npm run api:migrate:dev` may create/apply migrations; verify database target first.

Seed policy:

- `npm run api:seed` is forbidden unless explicitly authorized and target is confirmed non-production.

## Local UAT

Purpose:

- Controlled local acceptance testing with a separate local PostgreSQL database.

Identification:

- `APP_ENV=uat`
- `UAT_LOCAL_ONLY=true`
- Expected DB name: `daleventa_uat_local`
- Scripts under `scripts/uat`.

Backend/API target:

- `http://127.0.0.1:4000` by default.

Database target:

- Local Docker PostgreSQL bound to localhost, default port `55432`, database `daleventa_uat_local`.

Allowed operations:

- UAT startup through scripts after safety checks.
- Local UAT data setup if explicitly part of UAT workflow.

Forbidden operations:

- Connecting local UAT scripts to remote production infrastructure.
- Using protected database names.

Migration policy:

- Use only the local UAT migration/sync approach documented in scripts and examples.

Seed policy:

- Default `RUN_SEED=false`. UAT seeding requires explicit task authorization.

Safety controls:

- `apps/api/src/common/uat-safety.ts` refuses protected database names, wrong DB names, and remote hosts in local UAT mode.

## QA / UAT / Staging

Purpose:

- Shared validation before production.

Identification:

- `apps/api/.env.staging.example` shows `NODE_ENV=staging` and a staging database pattern.
- Server UAT mode is supported in safety code with `UAT_SERVER_MODE=true`.

Backend/API target:

- OWNER VALIDATION REQUIRED for the current shared staging/UAT URLs.

Database target:

- Staging/UAT database only; never production. Documented example uses a staging database name pattern.

Allowed operations:

- Smoke tests, functional QA, visual QA, non-destructive validation.

Forbidden operations:

- Destructive data changes unless the environment is disposable and explicitly approved.
- Production seeds/migrations through staging commands.

Migration policy:

- Shared staging/UAT migrations require explicit authorization and backup/checkpoint policy.

Seed policy:

- No automatic seed unless explicitly approved for that environment.

## Production

Purpose:

- Real customers, companies, inventory, sales, fiscal, cash, payroll, service, and media data.

Identification:

- Production Docker/EasyPanel configs, `NODE_ENV=production`, production API domains, production database URLs, Codemagic production app env creation.

Backend/API target:

- Production API/domain as configured in deployment platform and CI variables.

Database target:

- Production PostgreSQL. Described only at a high level; secrets must remain in environment managers.

Allowed operations:

- Read-only inspection of code/config templates.
- Deployment only when explicitly requested and after release checklist.
- Non-destructive production smoke tests only when explicitly authorized.

Forbidden operations:

- No production seed.
- No destructive production database operation.
- No unapproved production migration.
- No production data deletion.
- No destructive business-data testing.
- No production config or credential changes without explicit authorization.

Migration policy:

- Protected by default. `prisma migrate deploy` may run during API production startup, so release work must verify flags and migration state before deployment.

Seed policy:

- Production seed is forbidden by default. `RUN_SEED=true` must not be enabled casually.

Deployment policy:

- Do not deploy during ordinary development tasks. Follow `docs/RELEASE.md`.

## Data Safety Rules

- Always identify the active environment before database, seed, migration, purge, repair, or deployment work.
- Treat unknown environment as production-risk until proven otherwise.
- Do not expose secrets in logs, docs, reports, screenshots, or final answers.
- Preserve tenant isolation and company ownership.
- Back up or checkpoint before approved shared-environment changes.
