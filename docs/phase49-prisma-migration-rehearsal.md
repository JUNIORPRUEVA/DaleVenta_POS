# Phase 4.9 - Prisma Drift Reconciliation And Production-Like Migration Rehearsal

Date: 2026-08-31

Production safety: production was not deployed, migrated, restarted, seeded, or edited. Production access was limited to read-only metadata queries and `pg_dump`.

## Repository

- Path: `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\DaleVentas POS`
- Branch: `main`
- HEAD: `ff1934fb`
- Working tree: dirty with existing UoM/UAT/warehouse work; no reset, clean, or discard was performed.

## Production Read-Only Inventory

- Production database verified: `daleventa`
- Production backend env, sanitized: `PRODUCTS_SOURCE=LOCAL`, `RUN_MIGRATIONS=false`, `RUN_SEED=false`, backend port `4000`
- Production migration records before rehearsal: 149 total, 147 successful, 2 historical rolled-back entries
- Latest successful production migration: `20260827090000_add_password_reset_tokens`

Historical rolled-back entries are bookkeeping only:

- `20260814232000_open_sales_ticket_states`
- `20260818190000_phase6_baseline`

## Fresh Backup And Clone

- Backup: `/root/daleventa-phase49/daleventa_phase49_20260831T052756Z.dump`
- Size: `1540539` bytes
- SHA256: `63c641cc78fdcd4efe0a84888f877115cb82676c3530dd2d007b2423d3f8835f`
- Backup readability: PASS via `pg_restore -l`
- Restore clone: `daleventa_phase49_20260831T052756Z_clone`
- Restore duration: 2 seconds

## Production Vs Clone Counts Before Migration

| Table | Production | Clone |
| --- | ---: | ---: |
| Company | 24 | 24 |
| User | 33 | 33 |
| CompanyMember | 28 | 28 |
| Product | 209 | 209 |
| Sale | 64 | 64 |
| SaleItem | 97 | 97 |
| Cotizacion | 9 | 9 |
| CotizacionItem | 50 | 50 |
| PurchaseOrder | 2 | 2 |
| PurchaseOrderItem | 6 | 6 |
| PurchaseReceipt | 0 | 0 |
| PurchaseReceiptItem | 0 | 0 |
| app_config | 24 | 24 |

FULLTECH baseline: `FULLTECH, SRL` has 104 products and stock total `2485.00` in both production and clone.

## Drift Classification

| Area | Classification | Finding | Root cause | Blocking before rehearsal |
| --- | --- | --- | --- | --- |
| `unit_of_measures` | G - genuine missing structural migration | Table/type/global UoMs absent in production | UoM migrations not yet applied | Yes |
| `companies` | G | Missing `measurement_units_enabled`, `product_source`, `fullpos_company_id` | Pending UoM/product-source migrations | Yes |
| `Product` | G/E | Missing `unit_of_measure_id`; `stock` still `numeric(12,2)` lineage instead of `numeric(18,6)` | Pending UoM migration | Yes |
| `SaleItem` | G/E | Missing UoM snapshots, product identity, warehouse snapshots; `qty` was `numeric(12,3)` | Pending UoM, identity, and warehouse migrations | Yes |
| `CotizacionItem` | G/E | Missing UoM snapshots and product identity; `qty` was `numeric(12,3)` | Pending UoM and identity migrations | Yes |
| `purchase_order_items` | G/E | Missing UoM snapshots and product identity; quantity columns were `numeric(12,3)` | Pending UoM and identity migrations | Yes |
| `purchase_receipt_items` | G/E | Missing UoM snapshots, product identity, destination warehouse | Pending UoM, identity, and receiving migrations | Yes |
| `service_execution_changes` | E | `quantity` was `numeric(12,3)` | Pending UoM migration | Yes |
| `warehouses`, `warehouse_stocks`, `terminals`, inventory tables | G | Tables absent | Pending warehouse/inventory migrations | Yes |
| `warehouse_transfers`, `warehouse_transfer_items` snapshots | G | W10 snapshot columns absent before W10 | Pending W10 migration in current repo | Yes |
| `password_reset_*` | None after inspection | Tables/indexes/FKs present | Already applied migration | No |
| `technical_visits` | None after inspection | Table/indexes/FKs present | Existing production schema matches current mapping | No |
| `_prisma_migrations` rolled-back rows | H - historical migration bookkeeping | Two old rolled-back entries remain | Historical failed attempts later resolved | No |

No direct production drift fix was performed. Reconciliation path is the repository migration chain.

## Clone Migration Rehearsal

Command rehearsed against clone only: `prisma migrate deploy`.

Applied migrations:

- `20260830120000_uom_decimal_foundation`
- `20260830153000_company_product_source`
- `20260830161000_transaction_product_identity`
- `20260830170000_multi_warehouse_database_foundation`
- `20260831021000_w3_zero_config_inventory_state`
- `20260831024500_w5_sales_warehouse_cancellation`
- `20260831031500_w6_purchase_receiving_warehouse`
- `20260831043000_w8_terminal_operational_resolution`
- `20260831054500_w10_warehouse_transfer_snapshots`

Duration:

- First 8 pending migrations: 3 seconds
- W10 migration, after syncing the current local migration to the rehearsal source: 2 seconds
- Total rehearsed migration time: about 5 seconds

Idempotency: PASS. A second `prisma migrate deploy` against the fully migrated clone reported no pending migrations.

Final schema diff: PASS. `prisma migrate diff --from-url <clone> --to-schema-datamodel prisma/schema.prisma --script` returned an empty migration.

## Post-Migration Checks

- `unit_of_measures`: 12 rows
- Legacy companies with `measurement_units_enabled=false`: 24
- Legacy companies with `measurement_units_enabled=true`: 0
- Products total: 209
- Products with `unit_of_measure_id='UNIT'`: 209
- Companies with `product_source` null or `LOCAL`: 24
- Quantity columns intended for stock/item quantities are `numeric(18,6)`
- Money columns inspected remained monetary precision such as `numeric(12,2)`
- W10 snapshots exist and required warehouse transfer snapshot columns are NOT NULL

Post-migration counts for critical business tables matched production exactly.

Exact decimal checks inside a rolled-back transaction:

- `20 - 5.5 = 14.500000`
- `10 - 2.375 = 7.625000`
- `1 - 0.125 = 0.875000`
- `21 - 0.125 = 20.875000`
- `50.5 - 20.25 = 30.250000`

Application unit validation against the clone:

- UNIT `1`, `2`, `10`: accepted
- UNIT `0.5`: rejected
- YARD `5.5`, YARD `0.125`, POUND `2.375`: accepted

## Impact Estimate

Largest affected tables in the clone:

| Table | Rows | Total size |
| --- | ---: | ---: |
| Product | 209 | 312 kB |
| SaleItem | 97 | 200 kB |
| CotizacionItem | 50 | 128 kB |
| companies | 24 | 128 kB |
| purchase_order_items | 6 | 96 kB |

The rehearsal completed quickly on the production-sized clone. Expected production DB migration duration is about 5 seconds plus operational overhead. Lock risk exists during `ALTER TABLE` operations and numeric type changes, but affected tables are small in the current production dataset. Recommended downtime window: short maintenance window with API writes paused/rejected during `migrate deploy`.

## Rollback Plan

Prisma `migrate deploy` has no automatic down migrations.

Production rollback readiness depends on:

- verified pre-deploy backup created immediately before migration
- exact application image/commit rollback target ready
- production API stopped or put in maintenance mode before migration
- if migration fails before app deploy, stop and inspect without manual production edits
- if migrated schema causes incompatible production failure, restore the verified backup into production only after explicit operator approval

Do not attempt ad hoc `ALTER TABLE` reversions in production.

## Validation

- `npx prisma validate`: PASS
- `npm run build`: PASS
- `npm test -- --runInBand`: PASS, 33 suites / 191 tests
- `flutter analyze`: PASS
- `flutter test --reporter compact`: PASS, 553 tests

## Decision

Database migration rehearsal: GO

Production migration readiness: GO for a controlled migration window, backup-first and stop-before-deploy. This report does not execute or authorize deployment by itself.
