# PHASE 5 — FINAL PRE-CUTOVER READINESS
**Cafeteria la bomba · FullPOS Local (SQLite) → FullPOS Cloud (DaleVentas POS)**

Status: **PRODUCTION NOT TOUCHED — nothing executed**
Verdict: **FINAL CUTOVER READINESS: GO**

Generated: 2026-09-16 · Repository: `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\DaleVentas POS` · Branch: `production-main`

---

## 1. FINAL SOURCE

| Item | Value |
| --- | --- |
| Path | `C:\Users\pc\Documents\fullpods.db` |
| Access mode | read-only (`node:sqlite` `readOnly: true` + `PRAGMA query_only=1`) |
| SHA256 (frozen) | `A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA` |
| Integrity | `integrity_check = ok` |
| Foreign keys | `foreign_key_check = 0` violations |
| `user_version` | 36 |
| Confirmed by operator | YES — final snapshot, no further legacy activity |

The SHA is compared against the constant `EXPECTED_SOURCE_SHA256` on every run. **Any difference stops the process.**

## 2. SOURCE SHA

`A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA` (uppercase hex, 64 chars) — verified before and after every command in this phase.

## 3. FINAL MANIFEST

| Item | Value |
| --- | --- |
| Path | `apps/api/scripts/migration/fullpos-legacy/out/manifest-fullpos-legacy.json` |
| Size | 9,817,150 bytes |
| File SHA256 | `070469073EE9E49A59840AB2332242B64A0AB486DB1690359B01A32810980733` |
| **Content digest** (timestamps excluded, immutable) | `119D354FE6833D4AD3695BCAC548EC61C311A54E320EC6D02FC2FC4FE650CAA1` |
| `manifestVersion` | 1 |
| `migrationVersion` | `1.0.0` |
| `sourceSystem` | `FULLPOS_LOCAL_SQLITE` |
| Dry-run report | `out/dry-run-report.json` |
| Target snapshot (production, read-only) | `out/target-snapshot.json` SHA256 `730741E0A286C24CB57AD7D76CEE4AF3C79FB3BFA9C54E6660452384FEA5874E` |

The manifest **file** hash changes on every regeneration (`generatedAt`); the **content digest** is stable and is the identity to compare. Verified: two consecutive generations produced different file hashes (`33A50490…` / `07046907…`) and the *same* content digest `119D354F…`.

Deterministic id sets (equal-or-different check for the rollback identity set):

| Set | Count | Digest (SHA256 of sorted target ids) |
| --- | --- | --- |
| Product | 91 | `F3F006FCAC8118DF7A4336D61CF61F3468D5A52F35FE1FAE04646A7417645EE9` |
| WarehouseStock scope (active products) | 87 | `1AC4916C299CF721D4E082D7384C3B341563AB890C075C6AA8F66F7720C53891` |
| CashSession | 50 | `65CA9BA644151D729F1EADE0C95304E26567FE67C56FD59316E9E5048878CAB0` |
| Sale | 7,179 | `56950A1AB753B097C3C2D6DA334A562A896FA1B5AC7289443D68883A73EE2218` |
| SaleItem | 9,746 | `85F99611B583ADE5C78032996D85D26F4C206F2498FD8F32E9790D7CEAAF81F0` |

WarehouseStock rows have no deterministic id: their identity is `(companyId, warehouseId, productId)` for the 87 active products. The manifest lists every `legacyId → targetId` pair, which **is** the rollback identity set (the runtime equivalent is computed deterministically by `buildIdSets`).

## 4. TARGET IDs (LOCKED)

```
TARGET_COMPANY_ID     = f3651f62-be10-41aa-bde7-663cf990eae8   (Cafeteria la bomba)
TARGET_WAREHOUSE_ID   = ffc9ef9b-9157-418d-8aa1-94112278bb68   (Main Warehouse / MAIN)
TARGET_TERMINAL_ID    = 00931697-e152-48bc-9e44-02023e14d465   (Default Terminal / DEFAULT)
TARGET_OWNER_USER_ID  = adc4bf90-41b3-4e20-99eb-f37d398200f5   (edward@gmail.com, ADMIN, not blocked)
```

## 5. FINAL COUNTS (authoritative, reproduced exactly)

| Metric | Expected | Dry-run | UAT database |
| --- | --- | --- | --- |
| Products | 91 | 91 | 91 |
| Active / Archived | 87 / 4 | 87 / 4 | 87 / 4 |
| Operational stock | 1,557.00 | 1,557.00 | 1,557.00 |
| WarehouseStock rows | 87 | 87 | 87 |
| Historical shifts (newest 50 real CLOSED of 113) | 50 | 50 | 50 |
| Historical sales | 7,179 | 7,179 | 7,179 |
| Completed / Cancelled | 7,176 / 3 | 7,176 / 3 | 7,176 / 3 |
| SaleItems | 9,746 | 9,746 | 9,746 |
| Sales linked to imported shifts | 3,930 | 3,930 | 3,930 |
| Sales with `cashSessionId = NULL` | 3,249 | 3,249 | 3,249 |
| Revenue / Cost / Profit | 1,095,535.00 / 742,332.88 / 353,202.12 | identical | identical |
| ITBIS / NCF / Commission | 0.00 / 0 / 0 | identical | identical |
| Customers, legacy users, suppliers, purchases | 0 | 0 | 0 |
| CashMovements, CashboxDaily, legacy InventoryMovements | 0 | 0 | 0 |
| DEMO imported | 0 | 0 | 0 |

Documented exception: legacy product 54 (`049000551808`) had stock `-1.000000`; it is imported as operational stock `0.000000` (1 stock exception, recorded in the manifest).

## 6. UAT EVIDENCE (real writes, disposable local PostgreSQL 17.9)

Environment: `daleventa_uat_local` @ `127.0.0.1:55432`, 121 tables, 23 migrations, disposable.

| Cycle step | Result |
| --- | --- |
| Real import (one transaction, 17,153 rows) | `IMPORTED` · products 91 · stocks 87 · shifts 50 · sales 7,179 · items 9,746 · ~3.3 s |
| PostgreSQL reconciliation right after the write | `GO` (33 checks, 0 failures) |
| Independent SQL suite (`uat/verify-uat.sql`) | 12/12 blocks PASS |
| Idempotency (2nd run) | `ALREADY_APPLIED` · 0 rows inserted · `GO` |
| Read-only verify mode (`--verify`) | `GO`, 0 rows changed |
| Multi-tenant isolation (decoy tenant) | intact after import, idempotency, verify and rollback |
| Surgical rollback | deleted items 9,746 · sales 7,179 · shifts 50 · stocks 87 · products 91 → clean baseline |
| Reimport after rollback | `IMPORTED` · `GO` |
| Automated rehearsal suite | 6/6 tests PASS (`UAT_DATABASE_URL` set); skipped by default |

## 7. LICENSE STATUS (Step 4 gate)

| Item | Value (production, read-only) |
| --- | --- |
| Company status | ACTIVE |
| Plan | STANDARD |
| License status | **TRIAL** (no license key) |
| Trial started / ends | 2026-09-16 16:18:24 / **2026-09-23 16:18:24 (UTC)** |
| `licenseExpiresAt` | `NULL` |
| Blocked at | `NULL` |
| `isUsable` today | **TRUE** |
| Limits | maxUsers 2 · maxProducts 100 |
| Current usage | 1 user · 0 products (will become 87 active products = 87/100) |
| Tax flags | `taxEnabled=false`, `ncfEnabled=false`, `pricesIncludeTax=false`, `defaultTaxRate=0` |
| `productSource` | `NULL` (treated as LOCAL) |

**Login/API works immediately after cutover: YES.** Enforcement is `assertCompanyCanUseApp` (login, token refresh and every authenticated request via the JWT strategy). While `licenseStatus = TRIAL` and `trialEndsAt` is in the future, access is granted.

⚠️ **Hard time window:** at **2026-09-23 16:18:24 UTC** the trial expires → `effectiveStatus = EXPIRED` → `isUsable = false` → login and all authenticated calls return 401 `LICENSE_EXPIRED` (with support contact). The cutover + acceptance must therefore happen before that instant, **or** the operator must activate/extend the license. No license change was made in this phase.

## 8. PRODUCTION BASELINE (read-only preflight)

| Item | Value |
| --- | --- |
| Database | `daleventa` (container `daleventapos_database.1.*`, PostgreSQL 17.11) |
| HBA/user | `daleventa_user` (used inside the container only; no credential printed) |
| Companies total | 27 |
| Users of target tenant | 1 |
| Target tenant footprint | Product 0 · WarehouseStock 0 · Sale 0 · SaleItem 0 · CashSession 0 · CashMovement 0 · CashboxDaily 0 · InventoryMovement 0 · Client 0 · Supplier 0 · PurchaseOrder 0 · Tax 0 · NcfSequence 0 · SaleCreditPayment 0 |
| Identity check | warehouse → company ✔ · terminal → company ✔ · terminal default warehouse ✔ · owner → company ✔ · membership OWNER/ACTIVE ✔ |
| Other tenants (products) | 8 tenants: 110 / 100 / 85 / 29 / 1 / 1 / 1 / 1 → 328 products outside the target |
| Global totals (reference) | products 328 · sales 1,223 · UoM `UNIT` present · 163 applied migrations |
| Backup tooling | `pg_dump` + `pg_restore` present in the container; PGDATA 320 MB; host free space 13 GB; `/root/daleventas-backups` **missing** (must be created by the backup script) |

## 9. BACKUP PLAN (prepared, **NOT executed**)

Artifact: `apps/api/scripts/migration/fullpos-legacy/production/production-backup-plan.sh` (syntax-verified with `bash -n`, never run).

```bash
# on the production host (copy the script to /root first)
bash /root/fullpos-cutover-backup.sh dump
#   -> pg_dump -Fc inside the container
#   -> docker cp out of the container into /root/daleventas-backups/
#   -> chmod 600 + sha256sum -> <file>.sha256
#   -> daleventa_before_cafeteria_labomba_YYYYMMDD_HHMMSS.dump
bash /root/fullpos-cutover-backup.sh verify   # pg_restore --list (parses, does not restore)
bash /root/fullpos-cutover-backup.sh list
```

Commands the script uses (credentials come from the container environment, never from the command line):

```bash
docker exec "$CID" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f /tmp/<dump>'
docker cp "$CID:/tmp/<dump>" /root/daleventas-backups/<dump>
sha256sum /root/daleventas-backups/<dump> | tee /root/daleventas-backups/<dump>.sha256
docker exec "$CID" sh -c 'pg_restore --list /tmp/verify.dump | wc -l'
```

Recommended naming: `daleventa_before_cafeteria_labomba_YYYYMMDD_HHMMSS.dump` (UTC). Storage: outside the database container (host filesystem). Verification: non-zero entry count from `pg_restore --list` + stored SHA256. **No password is printed or stored.**

## 10. FINAL CUTOVER COMMAND — ⚠️ NOT EXECUTED

Prepared for the authorized cutover window (do not run without explicit authorization):

```bash
cd apps/api

# 1) pre-cutover backup (section 9), then:
npx ts-node -P tsconfig.scripts.json --transpile-only scripts/migrate-fullpos-legacy.ts \
  --execute \
  --environment=production \
  --database-url="postgresql://<production-user>:<password>@31.97.99.70:5432/daleventa" \
  --target-company-id=f3651f62-be10-41aa-bde7-663cf990eae8 \
  --target-warehouse-id=ffc9ef9b-9157-418d-8aa1-94112278bb68 \
  --source="C:\Users\pc\Documents\fullpods.db" \
  --source-sha256=A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA \
  --confirm-company-name="Cafeteria la bomba" \
  --confirm-production-cutover="CUTOVER:f3651f62-be10-41aa-bde7-663cf990eae8:A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA" \
  --confirm-write
```

**NOT EXECUTED.** No production command was run in this phase.

Guards that must all pass before a single row is written:

1. `--execute` + `--environment=production` + the explicit cutover token (derived from the locked company id and the frozen SHA — `--environment=production` alone is never enough).
2. Pre-connection URL gate: database must be exactly `daleventa` **and** the host must be known production infrastructure (`31.97.99.70` / `easypanel` / `gcdndd`); otherwise no socket is opened.
3. Locked target company + warehouse ids, confirmed company name, `--confirm-write`.
4. Frozen source SHA in the CLI and re-verified on the opened SQLite file.
5. Dry-run inside the execute path must be `GO` (45 checks) or execution is cancelled.
6. Live connection metadata: `current_database()` must be `daleventa`, port must match the URL.
7. Live tenant identity + no foreign rows (`clients`, `suppliers`, `purchaseOrders`, `cashMovements`, `cashboxDaily`, `taxes`, `ncfSequences`, `inventoryMovements`, open shifts must all be 0).
8. Destination classification must be `FRESH` (or `ALREADY_APPLIED` → clean no-op). A partial/foreign state aborts with **zero writes**.
9. One single transaction for all 17,153 rows; post-write PostgreSQL reconciliation must be `GO`, otherwise a NO-GO is raised.

Rejected automatically: wrong database, wrong company, wrong warehouse, wrong source, missing confirmation, production host not recognized, live DB mismatch.

## 11. POST-CUTOVER RECONCILIATION (read-only)

Two independent paths, both prepared:

```bash
# A) executable verification (read-only, same guards incl. production token)
npx ts-node -P tsconfig.scripts.json --transpile-only scripts/migrate-fullpos-legacy.ts \
  --verify --environment=production \
  --database-url="postgresql://<user>:<password>@31.97.99.70:5432/daleventa" \
  --target-company-id=f3651f62-be10-41aa-bde7-663cf990eae8 \
  --target-warehouse-id=ffc9ef9b-9157-418d-8aa1-94112278bb68 \
  --source="C:\Users\pc\Documents\fullpods.db" \
  --source-sha256=A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA \
  --confirm-company-name="Cafeteria la bomba" \
  --confirm-production-cutover="CUTOVER:f3651f62-be10-41aa-bde7-663cf990eae8:A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA" \
  --confirm-write
# writes out/destination-verification.json, prints GO/NO-GO

# B) SQL inside the database container
docker cp production/production-reconciliation.sql <CONTAINER>:/tmp/reconciliation.sql
docker exec -i <CONTAINER> sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/reconciliation.sql'
```

The SQL prints PASS/FAIL for: 91/87/4 products, 87 stocks, stock total 1,557.00 with 0 mismatches and 0 negatives, 50 CLOSED shifts (0 OPEN, 0 null `closedAt`), 7,179 sales (7,176/3, 3,930 linked / 3,249 NULL), 9,746 items, revenue/cost/profit `1095535.00 / 742332.88 / 353202.12`, ITBIS 0, NCF 0, commission 0, 0 customers/suppliers/purchases/cash movements/cashbox daily/inventory movements, 0 DEMO, and **other tenants unchanged** (27 companies, 419 products / 8,402 sales globally, 328 / 1,223 outside the tenant) plus the imported items' operational neutrality (`inventory_tracked_snapshot = 0`, `product_source <> LOCAL = 0`).

**Pre-validated:** the SQL was executed against production during this phase (read-only): 0 SQL errors and the expected pre-cutover verdicts (tenant empty → FAIL, out-of-scope 0 → PASS, other-tenant reference 328/1,223 → exact match).

## 12. MANUAL ACCEPTANCE CHECKLIST (post-cutover, 23 items)

| # | Check |
| --- | --- |
| 1 | Login Cafeteria la bomba |
| 2 | Products page opens |
| 3 | 87 active products visible as expected |
| 4 | Archived products not shown as active |
| 5 | Stock values correct |
| 6 | Total stock reconciles to 1,557 |
| 7 | Sales history opens |
| 8 | An old sale opens |
| 9 | Product / qty / price correct in the historical sale |
| 10 | Profit report works |
| 11 | Historical revenue / cost / profit match the migration totals |
| 12 | Shift history opens |
| 13 | 50 migrated historical shifts available |
| 14 | Shift detail opens |
| 15 | Linked historical sales appear in the shift |
| 16 | Older historical sales without a shift still appear in normal sales history |
| 17 | No imported shift is OPEN |
| 18 | No customer records were created |
| 19 | NCF / fiscal remains disabled |
| 20 | A NEW test sale can be created after the migration |
| 21 | The new sale correctly changes current stock |
| 22 | The new sale does NOT alter historical cost/profit snapshots |
| 23 | Logout / login works |

Not executed in this phase (no production test sale).

## 13. SURGICAL ROLLBACK COMMAND (LEVEL A)

Deterministic ids of this migration profile only:

```bash
npx ts-node -P tsconfig.scripts.json --transpile-only scripts/migrate-fullpos-legacy.ts \
  --rollback --environment=production \
  --database-url="postgresql://<user>:<password>@31.97.99.70:5432/daleventa" \
  --target-company-id=f3651f62-be10-41aa-bde7-663cf990eae8 \
  --target-warehouse-id=ffc9ef9b-9157-418d-8aa1-94112278bb68 \
  --source="C:\Users\pc\Documents\fullpods.db" \
  --source-sha256=A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA \
  --confirm-company-name="Cafeteria la bomba" \
  --confirm-production-cutover="CUTOVER:f3651f62-be10-41aa-bde7-663cf990eae8:A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA" \
  --confirm-write
```

Deletes in reverse dependency order: SaleItem → Sale → CashSession → WarehouseStock (by `companyId + warehouseId + productId ∈ 87 active set`) → Product. Only deterministic ids of this profile, always scoped to the locked company; never `deleteMany({ companyId })`, never another tenant, never unrelated rows. Verified in UAT: baseline restored exactly (0/0/0/0/0) with the decoy tenant untouched.

## 14. FULL RESTORE PROCEDURE (LEVEL B)

```bash
# 0) backup taken pre-cutover: /root/daleventas-backups/daleventa_before_cafeteria_labomba_<ts>.dump
# 1) stop the API so no writer is connected (EasyPanel: scale backend to 0)
# 2) restore
docker cp /root/daleventas-backups/<dump> <CONTAINER>:/tmp/restore.dump
docker exec -i <CONTAINER> sh -c \
  'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner /tmp/restore.dump'
docker exec <CONTAINER> rm -f /tmp/restore.dump
# 3) start the API again and re-run section 11
```
`production-backup-plan.sh restore` intentionally refuses to run the restore itself (destructive; requires `CONFIRM=yes` and manual supervision).

## 15. KNOWN PENDING ITEM — PRODUCT IMAGES

**IMAGE STATUS: PENDING.** 87 products reference a legacy image path; no physical image files were provided, so no image object, URL or storage key was created or fabricated. Images do **not** block products, stock, sales, profit or shifts, and are not part of the migration transaction.

Second pending item (product/licensing, not migration): the tenant trial expires **2026-09-23 16:18:24 UTC** (section 7). Recommended third item: raise `maxProducts` if the business needs more than 100 products (87 will be used right after cutover).

## Appendix A — COMMANDS USED / TESTS

```text
npx tsc -p tsconfig.scripts.json --noEmit --types node,jest        -> clean
npx jest --testPathPatterns="scripts/migration/fullpos-legacy"      -> 154 passed (1 suite skipped: rehearsal needs UAT_DATABASE_URL)
npx jest ... + UAT_DATABASE_URL (live UAT)                          -> 6/6 passed (import, idempotency, verify, isolation, rollback, reimport)
npx prisma validate                                                 -> schema valid
npx ts-node ... (dry-run, frozen source + fresh production snapshot) -> RECONCILIATION GO (45 checks, 0 failures), 0 writes
psql -f uat/verify-uat.sql                                          -> 12/12 blocks PASS
psql -f production/production-reconciliation.sql (production, read-only) -> 0 SQL errors, pre-cutover verdicts as expected
bash -n production-backup-plan.sh                                   -> syntax OK (never executed)
git diff --check                                                    -> clean
git status                                                          -> only new untracked files; no tracked file modified
```

## 16. PRODUCTION SAFETY

| Item | Value |
| --- | --- |
| PRODUCTION DATA WRITES | **0** |
| PRODUCTION MIGRATION EXECUTIONS | **0** |
| PRODUCTION DEPLOYS | **0** |
| Commits / pushes | **0** (nothing committed, nothing pushed) |
| Secrets committed or printed | **0** |
| Productions operations performed | read-only SQL inside the DB container (`SELECT`), `docker ps`, `docker cp` of read-only `.sql` helpers into container `/tmp` (later removed), SSH auth with the existing key (key content never printed) |

## FINAL VERDICT

**FINAL CUTOVER READINESS: GO**

Conditions attached to the GO (all non-blocking today):
1. Execute the cutover **before 2026-09-23 16:18:24 UTC** or activate/extend the tenant license (section 7).
2. Take the pre-cutover backup (section 9) and keep it outside the database container.
3. Re-verify the frozen source SHA immediately before execution (any difference = NO-GO).
4. Product images remain PENDING and are explicitly out of the cutover scope.
