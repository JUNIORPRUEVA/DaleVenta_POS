# Backup And Deletion Retention Policy

Date: 2026-08-05

## Application Deletion

User deletion anonymizes personal account fields and revokes active sessions while preserving historical foreign-key references.

Company deletion removes company-owned rows where the database exposes direct `company_id` ownership and deletes tenant-prefixed storage objects.

## Backup Scope

Application code does not delete:

- PostgreSQL backups.
- Point-in-time recovery WAL archives.
- R2/object-storage version history, if bucket versioning is enabled.
- Third-party exports, logs, analytics, or support dumps.

## Production Policy To Enforce Outside Code

- Define the maximum retention window for PostgreSQL backups.
- Document whether legal/tax records are retained after account or company deletion.
- Ensure restore procedures re-run tombstone/deletion checks before exposing restored data.
- If irreversible company deletion is required, use backup expiration or tenant-key destruction. Do not claim immediate erasure from historical backups.

## Operational Minimum

Before marking deletion production-ready, the owner should approve:

- Backup retention days.
- R2 versioning behavior.
- Legal/tax retention categories.
- Support/export deletion responsibilities.
- Restore-time verification checklist.
