# DaleVentas Backup Architecture

Last updated: 2026-10-08.

This document is the canonical backup and restore contract for DaleVentas POS /
FullPOS Cloud. Backups are a **server-side / FULLTECH responsibility only**.

## Authority Boundary

The backend is the sole authority for backup creation, retention, validation,
download and restore.

The POS client does **not** create, inspect, download, upload, open, import or
restore enterprise backups. The former client-side local export/restore flow was
**removed** from Flutter, Android, iOS and Windows: local ZIP export, per-module
capture, versioned manifest, tenant ownership validation, required-module
validation, automatic backup interval, canonical upload/import/restore and the
`.dvbackup`/`.zip` platform file association no longer exist in the client.

Clients must not connect to PostgreSQL directly, manipulate database files,
replay a full tenant restore through ordinary CRUD calls, or decide cross-tenant
ownership from local paths.

Removing the client backup feature does **not** affect the operational local data
layer: the on-device SQLite database, offline mode, the sync queue, pending cash
close, `operationId`/`sessionId`, local caches and device settings are preserved.

A client that needs a restore or a backup must request it from FULLTECH.
Automatic server-side backup with retention and separate storage is a future
phase and will be implemented on the server, not in the client.

## Client-Side Backup (removed)

The Windows local backup exporter and the client restore flow were **removed**.
The following no longer exist in the client:

- local `.dvbackup`/ZIP generation and per-module capture
- the versioned client manifest and required-module validation
- module status/checksum reporting from the client
- the automatic backup interval and client-side retention policy
- canonical upload/import and the client restore screen
- the `.dvbackup`/`.zip` file association and open-intent handling

The canonical backup engine continues to live in the backend (see below).

## Current Phase B State

The backend exposes the canonical backup engine:

- `POST /backups`: create a manual canonical backup for the authenticated
  company only.
- `GET /backups`: list backup metadata for the authenticated company only.
- `GET /backups/:id/download`: download an owned complete backup by id.
- `DELETE /backups/:id`: delete an owned manual backup by id.

The backend stores canonical archives through the backup storage abstraction
under the configurable `BACKUP_STORAGE_PREFIX` namespace. The production default
is `backups`, producing `backups/companies/<companyId>/...`; UAT must use an
isolated prefix such as `backups/uat`. The default driver is R2/S3-compatible
storage. UAT can opt into a mounted durable filesystem volume with
`BACKUP_STORAGE_DRIVER=local` and `BACKUP_STORAGE_LOCAL_DIR=/app/backups-uat`
when R2/S3 backup credentials are not safely available. It persists metadata in
`backup_records`, validates archives before promotion to `COMPLETE`, records
SHA-256 payload checksums, and applies automatic backup retention only after a
new complete automatic backup succeeds.

Automatic scheduling is controlled by `BACKUP_SCHEDULER_ENABLED`. It defaults
to disabled and runs only when explicitly enabled. UAT validation keeps it
disabled and creates only controlled manual backups.

The model inventory for Phase B is documented in
`docs/BACKUP_MODEL_INVENTORY.md`.

## Target Cloud Backup Location

Canonical cloud backup files should be written only by the backend to durable
server-controlled storage, under tenant-scoped keys such as:

```text
backups/companies/<companyId>/manual/<backupId>.dvbackup
backups/companies/<companyId>/automatic/<backupId>.dvbackup
backups/companies/<companyId>/pre_restore/<backupId>.dvbackup
```

The storage prefix must be distinct from product images, receipts, vouchers, and
other media. A backup object's tenant ownership must be verified from the
manifest and authenticated company context, not from the object key alone.

## File Format

The canonical extension is `.dvbackup`. The format is a ZIP-compatible archive
containing JSON module files and `manifest.json`.

Required manifest fields:

- `backupFormatVersion`
- `appVersion`
- `createdAt`
- `companyId`
- `companyName`
- `backupId`
- `backupType`: `MANUAL`, `AUTOMATIC`, or `PRE_RESTORE_SAFETY`
- `sourceEnvironment`
- `modules`
- `moduleStatus`
- `recordCounts`
- `checksums`
- `backupStatus`: `COMPLETE`, `PARTIAL`, or `FAILED`

Forbidden manifest and archive contents:

- plaintext passwords
- access tokens
- refresh tokens
- API secrets
- database credentials
- private keys

## Backup Completeness

A normal restore source must be `COMPLETE`. `PARTIAL` and `FAILED` archives may
be retained for diagnosis but are blocked by default for restore.

Each required module must have:

- a module file
- a valid module status
- a record count
- a checksum

The backend Phase B implementation must define the authoritative module list
from the Prisma schema and business ownership rules, including fiscal, cash,
inventory, payroll, purchases, sales, users, settings, local-device metadata
where appropriate, and tenant-scoped media references.

## Restore Engine

Restore is a backend-only operation. A valid restore request must:

1. Authenticate the user.
2. Verify administrative permission for the target company.
3. Validate the archive and manifest.
4. Verify manifest `companyId` equals the target company.
5. Verify format and app compatibility.
6. Require `COMPLETE` status.
7. Create and validate a `PRE_RESTORE_SAFETY` backup.
8. Restore inside a server-side transaction or equivalent staged rollback plan.
9. Apply tables in dependency order.
10. Verify post-restore counts and referential integrity.
11. Commit only after verification.
12. Roll back or leave recoverable state on failure.

The Windows, Android, iOS, and Web clients must not bypass this engine.

## Retention

Automatic backups:

- default interval: every 2 days
- keep newest 15 complete automatic backups per company
- delete only backend-verified automatic backups for the same company

Manual backups and pre-restore safety backups are not deleted by automatic count
retention.

Malformed, unknown, cross-tenant, partial, or failed files are not deleted by
automatic retention.

## Platform Responsibilities

All platforms (Windows, Android, iOS and Web):

- do **not** create, export, download, open, import or restore enterprise backups
- do **not** associate `.dvbackup`/`.zip` files or handle backup open intents
- must not perform database restore logic locally

Enterprise backup creation, validation, download and restore are performed from
the server side (FULLTECH) only. Clients must not bypass the backend engine.

## Production Gate

The backend restore engine is implemented and validated in UAT, but production
restore remains disabled by the server-side `BACKUP_RESTORE_ENABLED` feature
gate. The production rollout default is `BACKUP_RESTORE_ENABLED=false`.
Canonical backup creation, listing, download, validation, import, and scheduler
configuration are separate from destructive restore.

Production automatic backup scheduling is also gated by
`BACKUP_SCHEDULER_ENABLED` and defaults to disabled until storage and a manual
canary backup are validated.

## Deferred After Current Release

- Server-side automatic backup with retention and separate storage.
- Server-side restore/recovery validation.
- Emergency restore/recovery mode when normal login is unavailable.

These items are future server-side work and must not be reported as PASS in the
current release.
