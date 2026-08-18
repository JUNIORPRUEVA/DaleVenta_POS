# FullPOS Tax Phase 6 Production Readiness

Date: 2026-08-18

## Scope Guard

Phase 6 does not implement e-CF. It closes traditional NCF readiness blockers
for controlled deployment. Production data must not be modified by this phase.

Production database: `daleventa` / `daleventa_pos` lineage.

Disposable validation databases:

- `fullpos_staging`
- `fullpos_migration_test`

## P0 Prisma Migration Finding

Fresh database migration was broken before Phase 6:

```text
npx prisma migrate deploy
Migration: 20260210000001_add_punch
Error: relation "User" does not exist
```

Root cause:

- `20260206001945_init` created legacy `"User"`.
- `20260209090000_cloud_sync_init` dropped `"User"` and created lowercase `users`.
- `20260210000001_add_punch` still created FK `"Punch"."userId" -> "User"."id"`.
- Therefore the historical chain was not designed to be replayed from an empty
  database after the cloud-sync table rewrite.

Production read-only inspection:

- `_prisma_migrations` contains 141 rows.
- Relevant legacy migrations are recorded as applied in production.
- Production has `users`, `Punch`, `Sale`, `SaleItem`, `companies`,
  `company_members`, `auth_sessions`, `ncf_sequences`, and `taxes`.
- Production does not have a live `"User"` table.

Because production already stores checksums for the legacy migrations, Phase 6
does not rewrite historical SQL in place.

## Baseline Strategy

Active Prisma migrations were squashed to:

```text
apps/api/prisma/migrations/20260818190000_phase6_baseline
```

Legacy migration files were archived to:

```text
apps/api/prisma/migrations_legacy_pre_phase6
```

Controlled production deployment plan:

1. Take a database backup.
2. Verify production schema matches `schema.prisma` or document drift.
3. Do not run the baseline SQL against production tables.
4. Mark the baseline as applied:

```bash
npx prisma migrate resolve --applied 20260818190000_phase6_baseline
```

5. Run:

```bash
npx prisma migrate deploy
```

6. Keep future schema changes as normal incremental migrations after the
   baseline.

`prisma db push --accept-data-loss` is not an allowed production deployment
strategy.

## Evidence

Fresh DB test:

```text
Database: fullpos_migration_test
Migration history: baseline only
npx prisma migrate deploy = PASS
```

Staging fiscal validation after recreating `fullpos_staging` from the baseline:

```text
20 concurrent NCF = 20 sales / 20 unique NCF / nextNumber 21
100 concurrent NCF = 100 sales / 100 unique NCF / nextNumber 101
same clientRequestId x20 = 1 sale / 1 NCF / nextNumber 2
same NCF same company = blocked
same NCF cross-company = allowed
range 14-15 exhausted = blocked on third request
second active B01 sequence = blocked
overlapping B01 range = blocked
100 quotes = 0 NCF consumed
FULLTECH quote = Base 21,779.66 / ITBIS 3,920.34 / Total 25,700.00
taxEnabled=false = no fiscal behavior
```

Baseline drift check:

```text
prisma migrate diff = only non-destructive JSONB default formatting difference
technical_visits.estimated_products: [] vs '[]'::jsonb
technical_visits.photos: [] vs '[]'::jsonb
technical_visits.videos: [] vs '[]'::jsonb
```

Production startup hardening:

```text
NODE_ENV=production + PRISMA_SYNC_MODE=push now exits unless
ALLOW_PRODUCTION_DB_PUSH=true is explicitly set.
```

Local/CI checks run after the baseline change:

```text
npx prisma validate = PASS
npx prisma generate = PASS
npm run build = PASS
npm test = PASS, 29 tests
flutter analyze = PASS
flutter test = PASS, 103 tests
flutter build web = PASS with existing Wasm dry-run warnings
```

`npx prisma migrate status` against the current production URL reports expected
history divergence until controlled deployment marks
`20260818190000_phase6_baseline` as applied. This is not resolved automatically
in Phase 6 because production must not be modified.

## Phase 6 Matrix

```text
Prisma Migration History          PARTIAL
Fresh DB migrate deploy           READY
Existing DB upgrade safety        PARTIAL

Postgres NCF Constraints          READY
NCF Prisma Concurrency            READY
NCF HTTP Concurrency              PARTIAL
HTTP Idempotency                  PARTIAL

Tax Engine                        READY
Product Tax UI                    PARTIAL
POS Tax UI                        PARTIAL

Quotes                            PARTIAL
Quote Fiscal Snapshot             BLOCKED

B01                               PARTIAL
B02                               PARTIAL

Issuer Snapshot                   BLOCKED
Customer Snapshot                 BLOCKED
Line Snapshot                     PARTIAL

Refunds                           PARTIAL
Credit Note Fiscal Document       NOT IMPLEMENTED/PREPARED

B01 PDF                           PARTIAL
B02 PDF                           PARTIAL
80mm                              PARTIAL

Reports                           PARTIAL

Multi-company API Isolation       PARTIAL
Permissions                       PARTIAL

Traditional NCF Production Ready  NO
e-CF                              NOT IMPLEMENTED
```

## Remaining Blockers

- Add authenticated HTTP E2E coverage for B01/B02, cross-company reads/writes,
  cashier permissions, idempotency, and 20 concurrent B01 emissions.
- Implement immutable fiscal snapshots for issuer, customer, document, and all
  line-level tax fields.
- Implement fiscal refund movement domain without mutating the original sale.
- Add DGII traditional invoice field checklist from official DGII sources.
- QA generated PDF and 80mm ticket output from snapshot data.
- Complete Flutter fiscal UX and tests.
