# PHASE 4 — UAT rehearsal with REAL writes (disposable local PostgreSQL)

Verdict: **PHASE 4: UAT PASS — READY FOR FINAL CUTOVER PREPARATION**

Date: 2026-09-16 · Target: disposable local PostgreSQL 17.9 (`daleventa_uat_local`, 127.0.0.1:55432)
Legacy source: `C:\Users\pc\Documents\fullpods.db` · SHA256 `A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA` (unchanged before/after)
Production: **NOT touched** (read-only probe: 27 companies; migration tenant 0 rows in every table)

---

## 1. Objective / scope

Prove that the FullPOS Local → FullPOS Cloud migration can be written into the CURRENT Cloud
PostgreSQL schema without FK failures, constraint failures, Decimal errors, cross-tenant
contamination, stock reconciliation errors, reporting errors, shift-history errors or
accidental operational side effects.

## 2. UAT environment

| Item | Value |
| --- | --- |
| Cluster | `initdb` cluster, data dir `%LOCALAPPDATA%\daleventa_uat\pgdata` |
| Version | PostgreSQL 17.9 (`inet_server_addr()` = 127.0.0.1/32, port 55432) |
| Database | `daleventa_uat_local` (superuser `daleventa_uat_user`, trust auth, local only) |
| Schema | 23 Prisma migrations applied (`prisma migrate deploy`), 121 tables |
| Start command | `pg_ctl -D %LOCALAPPDATA%\daleventa_uat\pgdata -l <log> -o "-h 127.0.0.1 -p 55432" start` |
| Foundation seed | `scripts/seed-uat-foundation.ts` (locked company/warehouse/terminal/owner) + decoy tenant |
| Isolation canary | decoy company `1b2c3d4e-…-334455667788` with its own product/stock/shift/sale/item |

## 3. Safety guards (three layers, all mandatory)

1. `assertExecuteConfirmations` — `--execute`, `--environment=uat`, locked `--target-*` ids,
   `--source-sha256`, `--confirm-company-name`, `--confirm-write`.
2. `assertUrlIsLocalUat` — runs BEFORE any socket is opened: protected DB names
   (`daleventa`, `daleventa_pos`), known production infrastructure (`31.97.99.70`, `easypanel`,
   `gcdndd`, `hostinger`), loopback-only, database name must look like UAT.
3. `assertUatEnvironment` — after connecting: the sanctioned project gate
   (`src/common/uat-safety.ts`) plus live PostgreSQL metadata (`current_database()`,
   `inet_server_addr()`, `inet_server_port()`), protecting against "the URL says the same but
   the connection goes elsewhere".

`--environment=production` aborts (`ENVIRONMENT_NOT_UAT`); a production-looking URL aborts with
`PRODUCTION_FORBIDDEN` without ever opening a connection.

## 4. Real import (execute)

```
EJECUCIÓN UAT (escritura real en base desechable no productiva)
Veredicto : IMPORTED
Entorno   : uat · daleventa_uat_user@127.0.0.1:55432/daleventa_uat_local
Servidor  : 127.0.0.1/32:55432 · base daleventa_uat_local
Insertado : products 91 · warehouseStocks 87 · shifts 50 · sales 7179 · saleItems 9746
Duración  : 3293 ms
Reconciliación DB: GO (33 checks, 0 fallos)
```

One single transaction for all 17,153 rows; insert order products → warehouseStocks →
cashSessions → sales → saleItems; batches of 500 rows.

## 5. Reconciliation read straight from PostgreSQL

`reconcileFromDatabase` (33 checks) + independent `psql` suite (`uat/verify-uat.sql`, 12 blocks):

| Check | Expected | Actual |
| --- | --- | --- |
| products / active / archived | 91 / 87 / 4 | 91 / 87 / 4 |
| warehouseStocks | 87 | 87 |
| shifts (all CLOSED, closedAt not null, 0 OPEN) | 50 | 50 |
| sales | 7,179 | 7,179 |
| saleItems | 9,746 | 9,746 |
| revenue / cost / profit | 1,095,535.00 / 742,332.88 / 353,202.12 | identical |
| ITBIS / commission / NCF | 0.00 / 0.00 / 0 | 0.00 / 0.00 / 0 |
| cancelled sales | 3 | 3 |
| linked / unlinked sales | 3,930 / 3,249 | 3,930 / 3,249 |
| `Product.stock` = `SUM(WarehouseStock.quantity)` | 0 mismatches | 0 |
| negative stock | 0 | 0 |
| orphans (items without sale, stock without product, sale without user) | 0 | 0 |
| clients/suppliers/purchases/cashMovements/cashboxDaily/inventoryMovements/taxes/ncfSequences | 0 | 0 |
| DEMO products | 0 | 0 |
| UTF-8 accents (4 products with `Ñ`) | preserved | preserved |

## 6. Idempotency

Second run: `ALREADY_APPLIED`, inserted `0/0/0/0/0`, DB reconciliation `GO`, 472 ms. No upsert,
no overwrite: a partial or foreign state aborts with `TARGET_STATE_UNEXPECTED` and zero writes.

## 7. Multi-tenant isolation

- Decoy tenant rows unchanged after import, after idempotency run and after rollback
  (1 product, 1 stock, 1 shift, 1 sale, 1 item).
- 0 rows shared between the two tenants; only 2 distinct `company_id` values per migrated table.
- All writes/deletes always constrained by the locked `companyId` + deterministic id sets
  (never `deleteMany({ companyId })`).

## 8. Surgical rollback

```
Borrado : saleItems 9746 · sales 7179 · shifts 50 · warehouseStocks 87 · products 91
Después : todas las entidades del alcance a 0 (base limpia original)
Duración: 562 ms
```
Foundation rows (company/warehouse/terminal/owner/member) and the decoy tenant survive.

## 9. Reimport + repeatability

Reimport after rollback: `IMPORTED`, reconciliation `GO`, identical totals. The full cycle
(import → idempotency → isolation → rollback → reimport) is automated in
`uat/uat-rehearsal.integration-spec.ts` and passes end to end.

## 10. Referential integrity / constraints / Decimals

0 FK violations, 0 unique violations, 0 `Decimal` errors. All money values are written as
decimal strings derived from integer cents/micro (bigint) — no floating point arithmetic in the
write path. `Sale.@@unique([companyId, ncf])` is safe because every `ncf` is NULL and
`@@unique([companyId, clientRequestId])` uses the legacy code as `clientRequestId`.

## 11. Shift history

The 50 imported shifts are the newest 50 real CLOSED legacy sessions (out of 113; 63 older ones
intentionally omitted with reason `OLDER_THAN_MIGRATION_SHIFT_WINDOW`). All have a real
`closedAt`; the Cloud shift-history query (`closedAt DESC`, `take: 60`) returns exactly 50 rows.
`src/cash/cash.service.ts` was **not modified** (verified by `shift-window.spec.ts`).
Sales of omitted shifts are still imported with `cashSessionId = NULL` (3,249 sales, no data loss).

## 12. Reporting

Aggregations computed from PostgreSQL match the plan: revenue/cost/profit per period, top-5
products by qty and amount, 3 cancelled sales flagged (`status = CANCELLED`,
`cancellationReason` set, `inventoryRestoredAt` NULL because no stock was ever touched).

## 13. Operational side effects

Zero. No cash movements, no cashbox daily rows, no inventory movements, no credit rows, no
fiscal/ITBIS/NCF objects, no commission, no customers/suppliers/purchases, no DEMO data.
All sale items are written with `inventoryTrackedSnapshot = false` and `productSource = LOCAL`
so cancelling/returning imported history can never mutate stock.

## 14. Production and source safety

- Production (`daleventa` / `daleventa_pos` on 31.97.99.70 / easypanel) never received a write:
  the execute path refuses it before opening a connection, and a read-only probe confirmed the
  migration tenant still has 0 rows there (27 companies unchanged).
- The legacy SQLite source hash is identical before and after every run (read-only access via
  `node:sqlite` with `query_only`).
- Working tree: only new untracked files; `git diff --check` clean; no commit, no push, no deploy.

## 15. Automated validation

| Command | Result |
| --- | --- |
| `npx tsc -p tsconfig.scripts.json --noEmit --types node,jest` | clean |
| `npx jest --testPathPatterns="scripts/migration/fullpos-legacy"` | 132 passed (rehearsal suite skipped without `UAT_DATABASE_URL`) |
| `npx jest --testPathPatterns="scripts/migration/fullpos-legacy/uat"` with `UAT_DATABASE_URL` | 5 passed (real import, idempotency, isolation, rollback, reimport) |
| `npx prisma validate` | schema valid |
| `psql -f uat/verify-uat.sql` | 12/12 blocks pass |

**PHASE 4: UAT PASS — READY FOR FINAL CUTOVER PREPARATION**
