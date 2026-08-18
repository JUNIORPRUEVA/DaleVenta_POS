# FULLPOS FINAL FISCAL REMEDIATION PLAN

Verdict basis: `B — ALMOST CLOSED, SPECIFIC FIXES REQUIRED`.

No production deploy, no production migration, no e-CF.

# P0

No confirmed P0 code defect in this audit.

P0-risk controls still required before production:

| Item | Effort | Required proof |
|---|---|---|
| Run controlled staging fiscal validation on `fullpos_staging` | small | `npm run test:staging:fiscal` JSON output with concurrency20, concurrency100, idempotency, exhausted, sequenceRules, quotes all passing |
| Production migration read-only inventory | small | Export of production `_prisma_migrations`, current DB name, backup timestamp, and planned baseline/cutover decision |
| Fresh disposable DB migrate deploy | small | `npx prisma migrate deploy` against empty disposable DB plus API boot |

# P1

## 1. Remove or quarantine legacy ITBIS toggle in cotizaciones UI

Severity: P1  
Effort: medium  
Files:

- `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart`
- `apps/fulltech_app/lib/modules/cotizaciones/cotizacion_models.dart`
- `apps/api/src/cotizaciones/dto/create-cotizacion.dto.ts`
- `apps/api/src/cotizaciones/dto/update-cotizacion.dto.ts`

Problem:

- `_includeItbis`, `_itbisAmount`, `_setItbisEnabled`, `_toggleMobileItbis`, and UI switches labelled `ITBIS` remain.
- Backend recalculates fiscal snapshots, but UI still looks like cashier-controlled tax behavior.

Fix:

- Replace runtime ITBIS switch with config-driven, read-only tax summary.
- If a draft-only flag must remain for legacy non-fiscal quotes, rename it and stop presenting it as fiscal authority.
- Ensure quote UI does not alter tax mode independently of company/product tax config.

Tests:

- Widget: tax off hides fiscal controls.
- Widget: tax on included displays correct summary without toggle.
- Widget: tax on added displays final total.
- Widget: selecting/saving quote does not depend on manual ITBIS switch.
- Backend: malicious `includeItbis` cannot override backend snapshots.

## 2. Add fiscal HTTP E2E suite

Severity: P1  
Effort: large  
Files:

- New script or Jest E2E under `apps/api/scripts/` or `apps/api/src/**/*.e2e-spec.ts`.

Required flows:

- login
- tenant/company context
- create tax settings
- create active 18% tax
- create product inherit/taxable/exempt
- create fiscal client
- create quote
- quote PDF endpoint if available
- create sale no voucher
- create sale B01
- create sale B02
- refund full/partial
- report summary
- NCF sequence list/admin permissions
- cross-tenant negative tests

Tests:

- Must use real HTTP calls and auth headers.
- Must prove backend rejects malicious body `companyId`.
- Must prove UI-hidden controls are not required for fiscal enforcement.

## 3. Execute staging fiscal script on real staging DB

Severity: P1  
Effort: small  
Files:

- `apps/api/scripts/fiscal-staging-validation.cjs`

Fix:

- Point `DATABASE_URL` to disposable/staging DB named `fullpos_staging`.
- Run `npm run test:staging:fiscal`.
- Store JSON output in `FULLPOS_TAX_PHASE5_STAGING_VALIDATION.md` or a new dated evidence file.

Expected proof:

- schema tables/indexes present.
- duplicate NCF blocked same company.
- same NCF allowed across companies.
- concurrency20 passes.
- concurrency100 passes.
- idempotency 20 same key creates one sale/one NCF.
- sequence 14-15 exhausts and blocks third.
- one active sequence per type.
- overlapping sequence blocked.
- 100 quotes consume 0 NCF.

## 4. Complete migration/cutover proof

Severity: P1  
Effort: medium  
Files:

- `apps/api/prisma/migrations/*`
- `apps/api/scripts/start-prod.sh`
- deployment docs

Fix:

- Run fresh DB migration test.
- Run staging migration deploy.
- Inspect production `_prisma_migrations` read-only.
- Document backup and rollback.
- Keep `PRISMA_SYNC_MODE=push` blocked in production.

Tests:

- `npx prisma validate`
- `npx prisma generate`
- `npx prisma migrate deploy` on empty disposable DB
- `npm run build`
- API startup smoke after migrate

# P2

## 5. Expand refund fiscal tests

Severity: P2  
Effort: medium  
Files:

- `apps/api/src/sales/sales.service.fiscal-final.spec.ts`

Add tests:

- Full refund of 1180 included => base -1000, tax -180, total -1180.
- Partial refund 1 of 2 units.
- Exempt refund.
- Mixed refund.
- Discount refund.
- Product edited after sale does not affect refund snapshot.

## 6. Add historical immutability tests

Severity: P2  
Effort: medium  
Files:

- `apps/api/src/sales/sales.service.fiscal-final.spec.ts`
- Flutter document/ticket tests

Add tests:

- Emit sale from product/client/company snapshots.
- Mutate current product/client/company data.
- Reopen sale and render PDF/ticket.
- Assert historical document still uses original customer, line, tax, total, NCF, and date values.

Important:

- If issuer/company snapshot is not persisted, decide whether to add fields or formally mark issuer as current-company rendering.

## 7. Add report consistency fixtures

Severity: P2  
Effort: medium  
Files:

- `apps/api/src/reports/reports.service.spec.ts` or new report fiscal spec

Add tests:

- Company A sales 10,000, Company B sales 20,000.
- Report A returns only A.
- Report B returns only B.
- Mixed tax sale report equals sale item snapshots.
- Refund reduces net metrics correctly.
- Profit commercial and net tax profit are separated.

## 8. Add POS no-NCF-before-sale UI test

Severity: P2  
Effort: small  
Files:

- `apps/fulltech_app/test/modules/ventas/`

Add tests:

- Tax off: no voucher selector.
- Tax on / NCF off: tax summary shown, no voucher selector.
- Tax on / NCF on: selector shows configured B01/B02.
- Selecting B01 without RNC blocks with exact message.
- Selecting B01/B02 does not display NCF.
- Changing company resets voucher/cart/client.

## 9. Shared monetary golden matrix

Severity: P2  
Effort: medium  
Files:

- backend tax tests
- Flutter preview tests

Add matrix:

Prices:

```text
0.01, 0.05, 0.99, 9.99, 99.99, 129.95, 333.33, 999.99
```

Quantities:

```text
1, 2, 3, 7, 11
```

Modes:

```text
tax off, included, added, exempt, mixed, line discount, global discount
```

Required:

- Backend Decimal result is source of truth.
- Flutter preview matches for display cases or explicitly labels approximation.

# P3

## 10. Clean ts-jest deprecation warning

Severity: P3  
Effort: small  
Fix:

- Move deprecated `ts-jest` isolated modules setting to `tsconfig`.

Proof:

- `npm test` passes without config warning.

# FINAL CLOSE CRITERIA

The module can move from `B — ALMOST CLOSED` to `A — TECHNICALLY CLOSED` only when:

1. Cotizaciones legacy ITBIS switch is removed/quarantined.
2. Fiscal HTTP E2E suite passes.
3. Staging fiscal script passes on `fullpos_staging`.
4. Fresh DB migration deploy passes.
5. Production cutover plan has backup/rollback and read-only migration inventory.
6. Refund/report/historical immutability tests cover the listed critical cases.
7. Remaining work is only manual visual/device QA.

e-CF remains OUT OF SCOPE / FUTURE.
