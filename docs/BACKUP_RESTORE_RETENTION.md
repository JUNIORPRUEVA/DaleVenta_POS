# DaleVentas Backup, Restore, and Retention

Last updated: 2026-09-06.

## Ownership

Backups are owned by exactly one company. On Windows Release, the root is:

```text
C:\Program Files\DaleVentas POS\backups\<companyId>\
```

The folder name is not trusted as authority. The ZIP manifest must contain the
same `companyId` as the authenticated company before any restore workflow can
continue.

## Format

Each ZIP contains JSON module files and a versioned `manifest.json`.

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

Forbidden manifest contents:

- passwords
- access tokens
- refresh tokens
- API secrets
- database credentials
- private keys

## Validation

Validation verifies:

- ZIP is readable.
- `manifest.json` exists.
- `backupFormatVersion` is supported.
- `companyId` and `backupId` are present.
- required modules are listed.
- required module files exist.
- module statuses are valid.
- backup status is valid.
- active company matches manifest company when provided.

Results are:

- `VALID`
- `VALID WITH WARNINGS`
- `INVALID`

`PARTIAL` backups are not normal restore sources. They are blocked by default.

## Restore

The current backup is a local ZIP export of authenticated cloud/API modules plus
local company/printer settings. It is not a raw SQLite snapshot.

Cloud restore is a backend-only operation. The transactional restore API exists
and is validated in UAT, but production restore remains disabled by the
server-side `BACKUP_RESTORE_ENABLED=false` feature gate until separately
approved. The UI must not restore by replaying normal CRUD endpoints record by
record.

Before any future restore implementation:

1. Authenticate the user.
2. Verify administrative permission.
3. Validate the archive.
4. Verify `companyId`.
5. Verify format compatibility.
6. Require `COMPLETE` backup status.
7. Create and validate a `PRE_RESTORE_SAFETY` backup.
8. Restore transactionally.
9. Verify restored state.
10. Roll back or recover safely on failure.

## Automatic Backups

Default policy:

- Interval: every 2 days.
- Scope: per company.
- Backend scheduler runs only when `BACKUP_SCHEDULER_ENABLED=true`.
- Retention cleanup runs only after a new `COMPLETE` automatic backup is
  created and validated.

## Deferred After Current Release

- Android ACTION_SEND share-sheet runtime validation.
- Web runtime restore validation.
- iOS runtime validation.
- Emergency restore/recovery mode when normal login is unavailable.

## Retention

Automatic backups:

- Keep the newest 15 `COMPLETE` `AUTOMATIC` backups per company.
- Delete only ZIP files whose manifest identifies the same company and eligible
  automatic backup type.

Manual backups:

- Never auto-deleted by count.

Never delete automatically:

- manual backups
- another company's backups
- newest valid automatic backups within retention
- malformed/unknown files
- pre-restore safety backups
- staging folders for failed backups

## Temporary Staging

Backup creation writes module JSON files to a staging folder, compresses them,
validates the ZIP, then deletes the staging folder only after successful
validation. Failed staging folders may remain for diagnosis rather than risking
loss of evidence.
