Legacy Prisma migration history archived during Phase 6.

These migrations were applied or resolved in the existing production database, but
the chain is not reproducible from an empty PostgreSQL database. In particular,
`20260210000001_add_punch` references `"User"` after
`20260209090000_cloud_sync_init` has replaced the legacy `"User"` table with
`users`.

Do not edit or reapply these files as a production strategy. They are preserved
for forensic comparison, checksum review, and rollback planning only.

The active migration history starts at:

`../migrations/20260818190000_phase6_baseline`

Existing production databases must not run that baseline as SQL against live
tables. During a controlled deployment, mark it as applied after backups and
schema verification:

`npx prisma migrate resolve --applied 20260818190000_phase6_baseline`
