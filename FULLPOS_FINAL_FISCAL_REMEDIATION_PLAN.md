# FULLPOS FINAL FISCAL REMEDIATION PLAN

Updated: 2026-08-18

Verdict basis: `B - ALMOST CLOSED, CODE REMEDIATED LOCALLY, STAGING BLOCKED`.

No production deploy, no production migration, no e-CF.

# CLOSED IN THIS REMEDIATION

| Item | Result | Proof |
|---|---|---|
| Remove quote legacy ITBIS toggle | CLOSED | `rg "_includeItbis|_itbisAmount|_setItbisEnabled|_toggleMobileItbis"` returns 0 matches |
| Quote fiscal preview from config | CLOSED | `cotizaciones_screen.dart` uses `ProductTaxPreviewCalculator` |
| Quote->invoice double conversion guard | CLOSED | `SalesService.create` returns existing invoice for same `sourceQuotationId` |
| Issuer/customer sale snapshots | CLOSED | Prisma fields + migration `20260818213000_add_sale_issuer_customer_snapshots` |
| PDF/ticket issuer snapshot usage | CLOSED | `SaleModel`, invoice PDF, letter PDF, ticket data/rendering updated |
| Refund copies historical issuer/customer | CLOSED | Refund create copies original sale snapshot fields |
| Fresh disposable DB migrate | CLOSED | `npx prisma migrate deploy` passed on `fullpos_fresh_migration_codex` |
| Local backend tests/build | CLOSED | 11 suites / 47 tests, build pass |
| Local Flutter tests/build | CLOSED | 130 tests, web build pass |

# REMAINING P1

## 1. Baseline/migrate real staging database

Status: `BLOCKED`

Problem:

- `fullpos_staging` is non-empty and not baselined for the current Prisma migration history.
- Fiscal validation failed because `Sale.source_quotation_id` is missing.

Evidence:

```text
P3005: The database schema is not empty.
The column `Sale.source_quotation_id` does not exist in the current database.
```

Required proof:

- Backup staging.
- Decide baseline strategy for current schema.
- Apply migrations with `prisma migrate deploy`.
- Rerun `npm run test:staging:fiscal` and archive output.

## 2. Add full authenticated fiscal HTTP DB E2E

Status: `PARTIAL`

Current proof:

- Controller E2E harness passes for `POST /sales` and `POST /sales/:id/return`.

Still required:

- Real auth/login.
- Real tenant/company context.
- Real DB fixtures.
- Product/tax/client/quote/sale/B01/B02/refund/report chain.
- Cross-tenant negative cases.
- NCF idempotency/concurrency over HTTP.

# REMAINING P2

## 3. Historical PDF immutability visual/content test

Add a test that emits a sale, mutates current company/client/product data, renders invoice PDF/ticket again, and asserts original issuer/customer/product/tax snapshots remain.

## 4. Report consistency fixtures

Add report tests for:

- Company A vs Company B isolation.
- Mixed taxable/exempt sale.
- Refund negative values.
- Commercial profit vs net-tax profit.

## 5. Refund fiscal expansion

Add full coverage for:

- Full refund included tax.
- Partial refund.
- Exempt refund.
- Mixed refund.
- Discount refund.
- Product edited after sale.

# REMAINING P3

## 6. Clean ts-jest deprecation warning

Move deprecated `ts-jest` isolated modules config into `tsconfig`.

# FINAL CLOSE CRITERIA

Move to `A - TECHNICALLY CLOSED` only when:

1. `fullpos_staging` migrates cleanly.
2. `npm run test:staging:fiscal` passes.
3. Full authenticated fiscal HTTP DB E2E passes.
4. Production cutover has backup, rollback, and read-only migration inventory.
5. Remaining work is only visual/device manual QA.

e-CF remains OUT OF SCOPE / FUTURE.
