# Company Deletion Data Map

Date: 2026-08-05

## Implemented Behavior

Company deletion is only attempted from `AuthService.deleteAccount` when the authenticated user is the sole active owner of the active company and submits the exact confirmation phrase.

The API deletes in this order:

1. Revoke the deleting user's active sessions.
2. Delete external R2 objects under `uploads/companies/{companyId}/`.
3. Delete local upload files under the same tenant folder when local storage is enabled.
4. Delete rows from physical database tables that expose a direct `company_id` column.
5. Revoke all remaining sessions for the company.
6. Delete company memberships.
7. Delete the company row.

The database work is transactional. If a restrictive foreign key or ownership ambiguity prevents completion, the transaction fails instead of silently leaving a partial database deletion.

## Covered Directly By Dynamic Database Deletion

The deletion routine introspects PostgreSQL for tables with a `company_id` column and deletes those rows dynamically. Current schema inventory is generated in:

- `apps/api/docs/TENANT_DATA_MODEL_INVENTORY.md`
- `apps/api/docs/tenant-data-model-inventory.json`

## Covered By Storage Prefix

R2 cleanup is limited to keys under:

```text
uploads/companies/{companyId}/
```

Local cleanup uses the equivalent folder under `UPLOAD_DIR`, `LOCAL_UPLOADS_DIR`, or `/uploads`.

## Known Gaps

- Child tables without direct `company_id` rely on database cascades or will block deletion.
- Audit, legal, tax, notification, and immutable history rows may intentionally survive if they do not expose direct tenant ownership.
- Backups and point-in-time restore snapshots are not erased by application code.
- Public/share-link artifacts must be reviewed endpoint by endpoint before promising complete tenant erasure.

## Required Staging Validation

Run these commands against a restored staging clone before enabling company deletion for production users:

```bash
npm run prisma:migrate:deploy
npm run audit:tenant-ownership
npm run audit:unsafe-tenant-queries
npm test
npm run build
```

The current environment could not complete `audit:tenant-ownership` because the configured database host was unreachable.
