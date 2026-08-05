# Multi-Tenant Security And Account Deletion Audit

Date: 2026-08-05

## Architecture Discovered

- Monorepo with a NestJS API in `apps/api`.
- PostgreSQL database modeled with Prisma in `apps/api/prisma/schema.prisma`.
- Flutter mobile/web/desktop app in `apps/fulltech_app`.
- Authentication uses JWT access tokens and refresh tokens through `AuthService` and `JwtStrategy`.
- Tenant identity is represented by `Company`, `CompanyMember`, and legacy `User.companyId`.
- Main business modules include users, settings, products, clients, sales, purchases, cash, reports, payroll, accounting, work scheduling, service orders, storage, marketing, notifications, AI assistant, and company manual.
- Storage uses tenant-prefixed upload helpers and R2/local fallback paths.
- Offline/mobile cache uses SQLite/shared-preferences fallback through `OfflineStore`.

## Modules Audited In This Pass

- Authentication and JWT tenant context.
- Account settings Flutter screens.
- Users controller/service.
- Offline cache clearing.
- Product inventory test layout.
- Storage helpers and media paths by inspection.
- Products, clients, sales, purchases, reports, settings, and storage tenant-filtering by targeted search.

## Vulnerabilities Found

- No backend-backed "Delete my account" flow existed.
- Flutter settings had no destructive account deletion workflow.
- Admin user endpoints could read, update, block, delete, edit contract data, and generate birthday greetings by user ID without verifying that the target user belonged to the active tenant.
- New users created by admins received `User.companyId` but did not receive a corresponding `CompanyMember`, weakening the membership-based tenant model.
- Several Prisma models still have optional `companyId`; this remains a data-model hardening risk until migrations backfill and enforce `NOT NULL`.
- Some uniqueness remains global by design or legacy compatibility, notably user `email` and `cedula`; business-record uniqueness must be reviewed table by table before changing production constraints.

## Changes Implemented

- Added backend endpoints:
  - `GET /auth/account/deletion-preview`
  - `DELETE /auth/account`
- Added secure account deletion service behavior:
  - Requires authenticated JWT.
  - Requires current password.
  - Detects active company membership.
  - Detects sole-owner company risk.
  - Requires exact phrase `DELETE MY COMPANY` for sole-owner company deletion attempts.
  - Blocks deletion when the user is sole owner of other companies.
  - Removes active memberships.
  - Blocks and anonymizes the user record so deleted users cannot log in again.
  - Returns a deletion receipt ID.
- Added conservative company-owned data deletion attempt for sole-owner deletion:
  - Runs in a transaction.
  - Deletes rows from tables that expose a `company_id` column.
  - Deletes company memberships and company record afterward.
  - Fails transactionally if database dependencies prevent a safe full deletion.
- Hardened user admin endpoints:
  - Target user must belong to the request tenant by `companyId` or active `CompanyMember`.
  - User reads, updates, permission changes, blocks, deletes, birthday greeting, and AI contract edits now go through tenant validation.
- User creation now creates a matching `CompanyMember`.
- Flutter settings now shows `Eliminar mi cuenta`.
- Flutter deletion flow:
  - Fetches deletion preview from backend.
  - Shows destructive warning.
  - Requires password.
  - Requires confirmation phrase when company deletion is involved.
  - Disables double submission.
  - Does not clear local data until backend confirms success.
  - Clears tokens, image cache, offline cache entries, and pending sync queue.
  - Navigates to login after success.
- Fixed a mobile inventory dropdown overflow that was failing the full Flutter test suite.

## Files Changed

- `apps/api/src/auth/auth.controller.ts`
- `apps/api/src/auth/auth.service.ts`
- `apps/api/src/users/users.controller.ts`
- `apps/api/src/users/users.service.ts`
- `apps/fulltech_app/lib/core/api/api_routes.dart`
- `apps/fulltech_app/lib/core/auth/auth_provider.dart`
- `apps/fulltech_app/lib/core/auth/auth_repository.dart`
- `apps/fulltech_app/lib/core/offline/offline_store.dart`
- `apps/fulltech_app/lib/features/account/account_menu_screens.dart`
- `apps/fulltech_app/lib/features/products/ui/inventory_module_pages.dart`
- `MULTI_TENANT_SECURITY_AND_ACCOUNT_DELETION_AUDIT.md`

## Migrations Created

No database migration was created in this pass.

Reason: the schema contains many nullable tenant columns and legacy ownership patterns. A safe production migration requires a real database backup, data ownership backfill report, ambiguity handling, and staged `NOT NULL`/foreign-key enforcement. Blindly enforcing those constraints from schema text alone would risk production data loss or failed deploys.

## Tenant Ownership Rules

- Backend must derive active company from authenticated user/membership.
- Frontend-sent company ownership fields must not be trusted.
- Business queries must include `companyId` or validate ownership through a parent relation.
- Admin user operations now validate target-user tenant ownership.
- Storage keys should remain under `uploads/companies/{companyId}/...`.

## Account Deletion Behavior

- Normal member/account deletion removes memberships, blocks login, anonymizes personal fields, and clears local app state after backend success.
- Sole owner deletion requires password plus `DELETE MY COMPANY`.
- Multi-company users who are the only owner of another company are blocked from personal deletion until ownership is transferred or that company is separately deleted.

## Company Deletion Behavior

- Company deletion is attempted only for an authenticated sole owner with explicit phrase confirmation.
- The operation is transactional and conservative.
- Tables with `company_id` are deleted dynamically.
- If child tables without `company_id` or restrictive foreign keys prevent deletion, the transaction fails instead of leaving partial deletion.

## Data Retention And Backups

- Current implementation anonymizes deleted user records to preserve historical foreign-key references.
- Company deletion does not remove external backup copies.
- Production deployment must define backup expiration, restore-time tombstone checks, or tenant-key destruction before claiming full irreversible deletion from all backups.
- No legal/tax retention rules were invented or encoded.

## Remaining Risks

- Full schema hardening still needs migrations to make company-owned `companyId` fields required and foreign-keyed.
- Refresh tokens are stateless JWTs; blocking the user prevents refresh after deletion, but there is no token/session table for per-session revocation or device-level audit.
- Dynamic company deletion only covers tables with `company_id`; child tables without direct tenant fields depend on cascades or will make deletion fail.
- External R2 object deletion is not fully implemented for company deletion; metadata rows may be removed before objects unless a follow-up object listing/deletion job is added.
- No Redis/cache tenant invalidation was added beyond Flutter local cache clearing.
- No row-level security policies were added.
- No backend integration tests were added because the API package has no configured test script.

## Verification Commands

- `npm run build` in `apps/api`: passed.
- `flutter analyze` in `apps/fulltech_app`: passed.
- `flutter test test/features/account/account_settings_navigation_test.dart` in `apps/fulltech_app`: passed.
- `flutter test` in `apps/fulltech_app`: passed, 67 tests.

## Deployment Checklist

- Back up production database before deployment.
- Deploy API first so the Flutter app has the deletion-preview and delete endpoints.
- Deploy Flutter/mobile/web clients after API.
- Verify `JWT_SECRET`, `DATABASE_URL`, storage/R2 variables, and public API base URL.
- Run `prisma migrate deploy` as usual; no new migration is required for this change.
- Smoke test login, user admin CRUD, settings, deletion preview, wrong-password deletion, normal deletion, and sole-owner phrase rejection.
- Test company deletion in a staging database clone before enabling it for production users.

## Production Readiness Verdict

The implemented changes close the immediate missing account-deletion flow and a concrete user-admin IDOR risk, and the code passes the available build/analyze/test commands.

The broader SaaS hardening requested is not fully complete until the database is migrated to required tenant ownership, backend integration tests cover cross-tenant IDOR for every endpoint, external file deletion is wired into company deletion, and backup/retention policy is enforced operationally.

## Production Hardening Phase 2

Date: 2026-08-05

### Implemented In Phase 2

- Added an `AuthSession` Prisma model and migration in `apps/api/prisma/migrations/20260805030000_add_auth_sessions`.
- Login now creates a server-side refresh session and embeds `sessionId` in access/refresh JWTs.
- Refresh now verifies the stored refresh-token hash, rotates sessions, and revokes the token family on replay detection.
- JWT validation now rejects missing, revoked, expired, or inactive-company sessions.
- Account and company deletion now revoke relevant sessions transactionally.
- Company deletion now deletes R2 objects under `uploads/companies/{companyId}/` before database deletion.
- Local tenant upload cleanup was added for local-storage deployments.
- Backend Jest infrastructure was added.
- Focused backend tests were added for account deletion safeguards and user tenant validation.
- Generated tenant data inventory and endpoint security matrix artifacts under `apps/api/docs`.
- Added tenant ownership audit/backfill scripts and an unsafe Prisma query scanner.
- Added CI workflow `.github/workflows/multi-tenant-security.yml`.
- Added production docs:
  - `apps/api/docs/TENANT_DATA_MODEL_INVENTORY.md`
  - `apps/api/docs/ENDPOINT_TENANT_SECURITY_MATRIX.md`
  - `apps/api/docs/UNSAFE_TENANT_QUERY_AUDIT.md`
  - `apps/api/docs/COMPANY_DELETION_DATA_MAP.md`
  - `apps/api/docs/BACKUP_AND_DELETION_RETENTION_POLICY.md`
  - `apps/api/docs/PRODUCTION_MULTI_TENANT_DEPLOYMENT_RUNBOOK.md`

### Phase 2 Migration Notes

- `auth_sessions` is additive and safe to deploy with `prisma migrate deploy`.
- Existing access and refresh tokens do not contain `sessionId`; after this deployment users must log in again.
- No broad `NOT NULL company_id` migration was added because the live ownership audit could not be completed and several models still need deterministic backfill decisions.

### Phase 2 Verification

- `npm test` in `apps/api`: passed, 5 tests.
- `npm run build` in `apps/api`: passed.
- `npx prisma validate` in `apps/api`: passed.
- `npm run audit:tenant-inventory` in `apps/api`: passed, 101 model rows generated.
- `npm run audit:endpoints` in `apps/api`: passed, 191 endpoint rows generated.
- `npm run audit:unsafe-tenant-queries` in `apps/api`: failed as intended with 33 strict errors and additional warnings that require remediation before a production-ready IDOR claim.
- `npm run audit:tenant-ownership` in `apps/api`: blocked because the configured database host `gcdndd.easypanel.host:5432` was unreachable.
- `npm audit --omit=dev --audit-level=moderate` at repo root: failed with 20 production dependency advisories; several fixes require breaking major upgrades.

### Remaining Phase 2 Risks

- Strict unsafe-query remediation is incomplete. Current findings are recorded in `apps/api/docs/UNSAFE_TENANT_QUERY_AUDIT.md`.
- Live tenant ownership/backfill validation is incomplete until a reachable staging or production clone is available.
- Row-level security was not enabled. The application does not yet set a trusted tenant context for every query/transaction, so enabling RLS now would risk breaking production behavior.
- Cache invalidation beyond database session revocation and Flutter local cleanup still needs a Redis/socket/job-cache inventory.
- Backup and legal/tax retention enforcement remains operational, not fully encoded in application code.
- Production dependency advisories remain open and need a separate framework/dependency upgrade pass.

### Updated Production Readiness Verdict

Phase 2 materially improves account deletion, session revocation, storage cleanup, auditability, tests, and CI visibility. It does not make the system fully production-hardened for multi-tenant isolation yet.

The platform should not be marketed or signed off as fully multi-tenant secure until strict unsafe-query errors are fixed, tenant ownership audit/backfill passes against real data, tenant constraints are staged into migrations, and backup/retention policy is approved.

## Production Hardening Continuation

Date: 2026-08-05

### Implemented In This Continuation

- Fixed the strict unsafe-tenant-query audit errors in:
  - `clients/clients.service.ts`
  - `contabilidad/contabilidad.service.ts`
  - `cotizaciones/cotizaciones.service.ts`
  - `products/products.service.ts`
  - `storage/media.controller.ts`
  - `users/users.service.ts`
  - `warranty-configs/warranty-configs.service.ts`
  - `work-scheduling/work-scheduling.service.ts`
- Replaced dangerous id-only mutations with scoped `updateMany`/`deleteMany` or scoped `findFirst` checks.
- Added missing tenant assignment on newly created accounting deposit orders, fiscal invoices, payable services, payable payments, and quotations.
- Enforced active company scope in selected accounting close/deposit/fiscal/payable operations.
- Enforced company scope in quotation read/update/delete/PDF/WhatsApp paths.
- Enforced membership/company scope in selected work-scheduling exception and manual day-off operations.
- Upgraded production dependencies to remove critical/high npm advisories.
- Removed unused `file-type` production dependency.

### Verification From This Continuation

- `npm run audit:unsafe-tenant-queries` in `apps/api`: passed with 0 errors and 128 warnings.
- `npm run build` in `apps/api`: passed.
- `npm test` in `apps/api`: passed, 5 tests.
- `npx prisma validate` in `apps/api`: passed.
- `npx prisma format --check` in `apps/api`: passed.
- `npm audit --omit=dev` at repo root: passed with 0 vulnerabilities.
- `npm run audit:tenant-inventory` in `apps/api`: passed, 101 model rows regenerated.
- `npm run audit:endpoints` in `apps/api`: passed, 191 endpoint rows regenerated.

### Deployment Diagnostics

- `https://daleventapos-backend.gcdndd.easypanel.host/health`: timed out from this workstation.
- `https://daleventapos-backend.gcdndd.easypanel.host/`: timed out from this workstation.
- `Test-NetConnection gcdndd.easypanel.host -Port 5432`: TCP succeeded.
- `npm run audit:tenant-ownership`: still failed from local because Prisma could not reach the database server at `gcdndd.easypanel.host:5432`.
- SSH to `root@31.97.99.70` reached the OpenSSH banner with the native client, but non-interactive password-based execution could not be established from this environment. `ssh2` and `plink` attempts timed out; an `SSH_ASKPASS` fallback was blocked by local policy because it would write a temporary secret helper.

### Remaining Risks After This Continuation

- The 128 unsafe-query warnings still need module-by-module review or scanner improvements for proven false positives.
- The tenant ownership audit still has not completed against real staging/production-clone data from this workstation.
- Full NOT NULL/FK/index tenant migrations are still blocked until ownership audit/backfill passes.
- Backend cross-tenant coverage is still limited to focused tests, not every tenant-owned endpoint.
- Direct server deployment was not completed because non-interactive SSH execution was unavailable in this environment.

### Current Readiness Verdict

The strict unsafe-query blocker and production dependency vulnerability blocker are improved: strict unsafe-query errors are now 0, and npm production audit reports 0 vulnerabilities.

The system must still not be declared production-ready until the real tenant ownership audit completes, ambiguous/cross-company rows are proven 0 from database data, tenant migrations are applied and verified, warning findings are reviewed, and server deployment is successfully diagnosed/restarted.
