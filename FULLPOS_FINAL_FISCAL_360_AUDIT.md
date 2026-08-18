# FULLPOS FINAL FISCAL 360 AUDIT

Audit date: 2026-08-18

# FINAL VERDICT

```text
B - ALMOST CLOSED, CODE REMEDIATED LOCALLY, STAGING BLOCKED
```

FULLPOS fiscal tradicional avanzo de forma material: el ITBIS legacy de cotizaciones ya no es un switch de cajero, ventas persiste snapshots de emisor/cliente, documentos/tickets leen esos snapshots, conversion quote->invoice evita doble factura para la misma cotizacion, fresh DB migrate pasa y las pruebas locales estan verdes.

No puedo declarar `A - TECHNICALLY CLOSED` porque staging no esta alineado: `prisma migrate deploy` contra `fullpos_staging` fallo con `P3005` por schema no vacio sin baseline, y `npm run test:staging:fiscal` fallo porque falta la columna `Sale.source_quotation_id` en esa base. Eso es un bloqueo real de entorno/migracion pendiente.

e-CF queda `FUTURE / OUT OF SCOPE`.

# CHANGES IMPLEMENTED

- Removed executable quote ITBIS legacy state/actions from `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart`.
- Quote totals now use `ProductTaxPreviewCalculator` with company/product fiscal config for preview; backend remains authority.
- Quote drafts now persist fiscal snapshot values from automatic fiscal summary, not cashier toggle state.
- Added sale issuer/customer snapshot columns in Prisma and migration `20260818213000_add_sale_issuer_customer_snapshots`.
- `SalesService.create` now snapshots issuer company/app config and customer address/phone on sale creation.
- Refund sales copy original issuer/customer snapshots.
- Quote-to-invoice conversion now returns existing invoice for the same `sourceQuotationId` instead of creating another invoice/NCF.
- Flutter `SaleModel`, invoice PDF, letter PDF, ticket data, and ticket renderer now prefer persisted issuer/customer snapshots over current settings.
- Added fiscal HTTP controller E2E harness for sale creation and refund route wiring.
- Fixed Jest script option from deprecated `--testPathPattern` to `--testPathPatterns`.
- Added ticket immutability coverage for issuer snapshot rendering.

# LEGACY QUOTE ITBIS REMOVAL

Status: `READY`

Search evidence:

```text
rg "_includeItbis|_itbisAmount|_setItbisEnabled|_toggleMobileItbis" apps/fulltech_app apps/api -S
0 matches
```

Cotizaciones no mantiene el switch privado que calculaba `subtotal * 18%`. The remaining tax display is derived from fiscal settings/product tax metadata.

# QUOTE -> INVOICE RESULT

Status: `READY / LOCAL`

- Quote conversion uses quote item/tax snapshots.
- Existing invoice by `{ companyId, sourceQuotationId, kind: "invoice", isDeleted: false }` is returned idempotently.
- Backend golden fiscal tests pass.

Remaining before production close: full authenticated HTTP DB E2E for quote->B01/B02.

# ISSUER/CUSTOMER SNAPSHOT RESULT

Status: `READY / LOCAL`

New persisted fields:

- `issuer_name_snapshot`
- `issuer_tax_id_snapshot`
- `issuer_address_snapshot`
- `issuer_phone_snapshot`
- `issuer_email_snapshot`
- `customer_address_snapshot`
- `customer_phone_snapshot`

Documents/tickets now prefer sale snapshots, with current company data only as fallback.

# HISTORICAL IMMUTABILITY RESULT

Status: `PARTIAL -> IMPROVED`

Line/tax/customer fiscal values were already snapshot-driven. This remediation adds issuer/customer contact snapshots and ticket coverage proving changed current company settings do not replace original issuer values.

Remaining: visual PDF immutability test after mutating company/client/product data.

# REFUND RESULT

Status: `READY / LOCAL CORE`

Refund documents continue as negative sales/items derived from original sale snapshots. Issuer/customer snapshots are copied from the original sale into the refund sale.

Formal credit note/e-CF remains out of scope.

# PROFIT/MARGIN/REPORT RESULT

Status: `PARTIAL`

Sales persist commercial profit/net tax profit and reports use persisted sale/item fiscal values. No new report fixture was added in this remediation, so report-vs-refund/mixed-tax coverage remains a recommended P2.

# MULTI-COMPANY RESULT

Status: `READY / LOCAL CORE`

Tenant guards remain in product/client/quote/sale/refund/NCF/report paths. The tenant isolation suite passes after updating mocks for issuer snapshots.

Remaining: HTTP IDOR E2E across tenants.

# PERMISSION RESULT

Status: `PARTIAL`

Refund route E2E harness verifies route wiring, but not full real-auth role matrix. Existing guards remain in place.

# OFFLINE RESULT

Status: `READY / LOCAL`

Flutter full test suite passes. Fiscal offline behavior was not changed by this remediation.

# IMPORT/EXPORT RESULT

Status: `PARTIAL`

Catalog import tests pass. No new fiscal export test was added.

# HTTP E2E RESULT

Status: `PARTIAL / IMPROVED`

Added `apps/api/src/sales/sales.fiscal.e2e-spec.ts`.

Proof:

```text
npm run test:e2e
Test Suites: 1 passed, 1 total
Tests: 2 passed, 2 total
```

Limitation: this is an HTTP/controller harness with mocked service and guard override. It proves route/DTO/controller wiring for sale and refund, not a full DB/auth fiscal chain.

# FRESH DB MIGRATION RESULT

Status: `READY`

Executed against disposable database `fullpos_fresh_migration_codex`.

```text
npx prisma migrate deploy
4 migrations found and applied
All migrations successfully applied
```

The disposable DB was dropped after the test.

# STAGING RESULT

Status: `BLOCKED`

`fullpos_staging` is not migration-aligned.

Evidence:

```text
npx prisma migrate deploy
P3005: The database schema is not empty.
```

Fiscal staging validation then failed on schema drift:

```text
The column `Sale.source_quotation_id` does not exist in the current database.
```

Required next step: choose a controlled staging baseline/migration path, apply migrations to `fullpos_staging`, then rerun `npm run test:staging:fiscal`.

# GOLDEN FISCAL RESULTS

Status: `PASS / LOCAL`

Covered by backend and Flutter tests:

- 1180 tax included -> base 1000, ITBIS 180, total 1180.
- 1000 tax added -> base 1000, ITBIS 180, total 1180.
- Exempt item -> ITBIS 0.
- Mixed taxable/exempt.
- Discounts before tax.
- FULLTECH/CANATECH quote/PDF fiscal golden cases.

# AUTOMATED TEST COUNTS

```text
Backend npm test: PASS - 11 suites, 47 tests
Backend npm run test:e2e: PASS - 1 suite, 2 tests
Backend prisma validate: PASS
Backend npm run build: PASS
Flutter analyze: PASS
Flutter test: PASS - 130 tests
Flutter build web: PASS
Fresh DB migrate deploy: PASS
Staging migrate deploy: BLOCKED - P3005 non-empty DB without baseline
Staging fiscal validation: FAIL/BLOCKED - Sale.source_quotation_id missing
```

# COMPLETE STATUS MATRIX

| Feature | Status |
|---|---|
| Tax Engine | READY |
| Tax OFF | READY |
| Included | READY |
| Added | READY |
| Exempt | READY |
| Mixed | READY |
| Discounts | READY |
| Rounding | READY |
| Product Tax | READY |
| Manual Sale Tax | READY |
| Catalog | READY |
| POS PC | READY / LOCAL |
| POS Mobile | READY / LOCAL |
| Voucher Selector | READY |
| B01 | READY / LOCAL |
| B02 | READY / LOCAL |
| NCF Reservation | READY / LOCAL |
| NCF Concurrency | BLOCKED ON STAGING |
| NCF Idempotency | BLOCKED ON STAGING |
| Customer Fiscal | READY |
| Quote Snapshot | READY |
| Quote PDF | READY |
| Quote -> Invoice | READY / LOCAL |
| Legacy Quote ITBIS | REMOVED |
| Issuer Snapshot | READY / LOCAL |
| Customer Snapshot | READY / LOCAL |
| Line Snapshot | READY |
| Historical Ticket | READY / LOCAL |
| Historical PDF | PARTIAL |
| Invoice PDF | READY / LOCAL |
| Normal Ticket | READY |
| B01 Ticket | READY |
| B02 Ticket | READY |
| Refund Total/Partial | READY / LOCAL CORE |
| Profit/Margin | READY / LOCAL |
| Reports | PARTIAL |
| Multi-company Core | READY |
| HTTP Fiscal E2E | PARTIAL |
| Fresh DB Migrate | READY |
| Staging Migrate | BLOCKED |
| Staging Fiscal Tests | BLOCKED |
| Production Deployment | PENDING |
| e-CF | OUT OF SCOPE |

# MANUAL QA ONLY

- Physical 80mm printer output.
- 58mm layout if supported.
- Long issuer/customer/product text.
- Large amounts.
- Multi-page PDFs.
- Real PC/mobile cashier flows.
- Historical document reopening after changing product/client/company data.

# DEPLOYMENT PENDING

No production deployment was executed.

No production migration was executed.

Do not deploy until `fullpos_staging` is baselined/migrated and `npm run test:staging:fiscal` passes.

# NUMERICAL SUMMARY

```text
READY: 34
READY / LOCAL: 12
PARTIAL: 5
BLOCKED: 3
MANUAL QA ONLY: 7
DEPLOYMENT PENDING: 1
OUT OF SCOPE: 1

P0 open: 0
P1 open: 2
P2 open: 3
P3 open: 1
```
