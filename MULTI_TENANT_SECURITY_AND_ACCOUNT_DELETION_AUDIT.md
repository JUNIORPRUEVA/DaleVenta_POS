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
