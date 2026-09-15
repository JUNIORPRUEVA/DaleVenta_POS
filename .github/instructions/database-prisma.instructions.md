---
description: "Use when editing the Prisma schema, migrations, seed, or data scripts in apps/api/prisma (models, relations, indexes, drift, backfill). Covers migration safety, multi-tenant scoping, and backward-compatibility requirements."
applyTo: "apps/api/prisma/**"
---

# Database rules (`apps/api/prisma`)

`schema.prisma` uses provider `postgresql` with `prisma-client-js`; the seed is `prisma/seed.cjs` (wired through the `prisma.seed` entry in `apps/api/package.json`).

## Required before changing the schema

1. Read `docs/ARCHITECTURE.md` (data model, tenant boundaries) and, for anything release-related, `docs/RELEASE.md`.
2. Check the API code that reads/writes the affected models, and the Flutter models that consume those responses.
3. Confirm the change is backward compatible: new columns need defaults or nullable handling so existing companies, users, products, sales, and cached Flutter payloads keep working.
4. Confirm tenant/company scoping is preserved, and that new unique constraints cannot collide across tenants.

## Migration safety

- Validate the schema with `npx prisma validate` from `apps/api`.
- Never edit an already-applied migration in a shared, staging, UAT, or production database. Add a new migration instead.
- Never run `prisma migrate dev` or `prisma migrate deploy` against shared, staging, UAT, or production databases without explicit authorization in the current task.
- Never delete a database, drop or truncate tables, or run mass `DELETE`/`UPDATE` to resolve drift. Diagnose and report first; `apps/api/README.md` and `docs/RELEASE.md` describe the safe path for P3009 / drift.
- Back up before any approved migration work.

## Restricted without explicit authorization in the current task

- `npm run api:seed`, `npm --workspace apps/api run prisma:seed`
- `npm run api:migrate:dev`, `npm run api:migrate:deploy`
- `prisma/scripts/fix_integrity.ts` (`integrity:fix`), purge scripts, repair scripts, and backfill scripts with `--apply`

If reality (database state, migration history, drift reports) disagrees with the documentation, report the discrepancy instead of silently rewriting history.
