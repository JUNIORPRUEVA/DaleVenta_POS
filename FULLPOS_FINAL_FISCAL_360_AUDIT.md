# FINAL VERDICT

```text
B — ALMOST CLOSED, SPECIFIC FIXES REQUIRED
```

FULLPOS traditional fiscal module is not technically closed yet. The core backend tax/NCF path is strong and locally verified, but the module still has missing HTTP E2E/staging evidence and a legacy ITBIS toggle/calculation path in `cotizaciones_screen.dart`.

e-CF = FUTURE / OUT OF SCOPE.

# EXECUTIVE SUMMARY

1. Backend is the fiscal authority for sales: `SalesService.create` recalculates taxes or uses stored quote snapshots, then persists sale/item snapshots.
2. NCF reservation is backend/database sourced via `NcfService.reserveNextNcf` with `FOR UPDATE` inside the sale transaction.
3. POS sale screen now separates tax calculation from voucher selection; B01/B02 selection does not reserve NCF.
4. Flutter POS preview uses a duplicated tax preview calculator, but backend remains final authority.
5. Product tax validation rejects taxable product rates not active in the authenticated tenant.
6. Quote snapshots exist and quote-to-sale conversion uses stored quote tax snapshots instead of current product prices.
7. Ticket/PDF code paths read sale/quote snapshots, not live products, for fiscal values.
8. Refunds are implemented as negative sales/items using original sale item snapshots.
9. Multi-tenant filters are present in audited product/client/sale/quote/NCF/report paths.
10. Local backend gate passed: Prisma validate/generate, build, and 44 Jest tests.
11. Local Flutter gate passed previously after the POS voucher work: analyze, 129 tests, web build.
12. Staging fiscal script exists but did not execute here because guard refused local DB `daleventa_pos`; staging remains unverified in this run.
13. No HTTP fiscal E2E suite was found for login→tenant→tax→product→quote→sale→B01/B02→refund→report.
14. `cotizaciones_screen.dart` still contains legacy `_includeItbis`, `_itbisAmount = subtotal * rate`, and UI switches labelled ITBIS.
15. Production cutover is pending and must not be declared deployed or production-ready without backup, migration plan, and staging execution.

# ARCHITECTURE FOUND

Flow found:

```text
Company settings
  -> Product tax treatment/rate/price mode
  -> Flutter preview/catalog/POS
  -> Backend TaxCalculationService
  -> Sale/Cotizacion snapshots
  -> Optional backend NCF reservation
  -> PDF/Ticket from snapshots
  -> Reports from persisted sale/item values
```

Key files:

- Backend tax engine: `apps/api/src/tax/tax-calculation.service.ts`
- Backend tax settings/NCF: `apps/api/src/tax/tax.service.ts`, `apps/api/src/tax/ncf.service.ts`
- Backend sale write path: `apps/api/src/sales/sales.service.ts`
- Backend quote write path: `apps/api/src/cotizaciones/cotizaciones.service.ts`
- Backend reports: `apps/api/src/reports/reports.service.ts`
- Prisma schema: `apps/api/prisma/schema.prisma`
- POS sale UI: `apps/fulltech_app/lib/modules/ventas/registrar_venta_screen.dart`
- POS voucher helper: `apps/fulltech_app/lib/modules/ventas/fiscal_voucher_options.dart`
- Flutter preview calculator: `apps/fulltech_app/lib/core/tax/product_tax_preview_calculator.dart`
- Quote UI legacy path: `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart`
- Quote PDF: `apps/fulltech_app/lib/modules/cotizaciones/utils/cotizacion_pdf_service.dart`
- Invoice PDF: `apps/fulltech_app/lib/modules/ventas/utils/sales_pdf_service.dart`
- Ticket data/rendering: `apps/fulltech_app/lib/core/printing/models/ticket_data.dart`, `ticket_renderer.dart`, `ticket_builder.dart`

# P0 FINDINGS

None confirmed in local source/tests.

P0 risk not fully discharged: HTTP/staging concurrency and production migration cutover are unverified in this run, so duplicate NCF / deployment divergence remain unproven rather than disproven.

# P1 FINDINGS

## FISCAL-360-001

Severity: P1 HIGH  
Area: Cotizaciones UI / legacy ITBIS  
Current status: PARTIAL  
Expected: Comprobante/ITBIS control must be automatic/config-driven and documentary selection must not alter tax.  
Actual: `cotizaciones_screen.dart` still has `_includeItbis`, `_itbisAmount => _includeItbis ? (_subtotal * _itbisRate) : 0`, `_setItbisEnabled`, `_toggleMobileItbis`, and PC/mobile switches labelled `ITBIS`.  
Evidence: `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart` around `_itbisAmount`, `_buildCheckoutSaleItems`, `_setItbisEnabled`, and the `Switch.adaptive`/`_DesktopPanelSwitchAction(label: 'ITBIS')` blocks.  
Function/Class: `_CotizacionesScreenState`, `_DesktopPanelSwitchAction`.  
Why it matters: UI can show/calculates fiscal totals differently from the backend and presents a cashier-controlled tax switch.  
Tenant impact: Low direct tenant impact.  
Fiscal impact: High UX/fiscal consistency risk.  
Data-loss risk: Low.  
Suggested fix: Replace `_includeItbis` runtime tax switch with config-driven preview and documentary controls, or clearly scope it to non-fiscal draft display.  
Tests required: Widget tests for tax off/tax on included/added/exempt/mixed in cotizaciones PC/mobile; backend request tests proving UI totals are ignored.

## FISCAL-360-002

Severity: P1 HIGH  
Area: HTTP E2E fiscal coverage  
Current status: PARTIAL  
Expected: Authenticated HTTP E2E for login, tenant selection, product, client, tax, quote, sale, B01, B02, refund, report, NCF.  
Actual: No fiscal HTTP E2E suite found. Existing fiscal coverage is service/unit and DB-level staging script.  
Evidence: `rg` found HTTP smoke scripts for generic sales/service-orders, but no fiscal B01/B02/NCF authenticated HTTP E2E.  
Files: `apps/api/scripts/smoke-sales.ts`, `apps/api/scripts/fiscal-staging-validation.cjs`.  
Why it matters: Guards, DTO validation, pipes, auth, tenant middleware, and route wiring are not proven end-to-end.  
Tenant impact: Medium until HTTP IDOR tests exist.  
Fiscal impact: High for release confidence.  
Data-loss risk: Medium for untested retry/concurrency behavior over HTTP.  
Suggested fix: Add fiscal HTTP E2E suite against disposable DB.  
Tests required: login→create settings/taxes/products/client/cash session→quote→sale B01/B02→refund→report plus cross-tenant negative cases.

## FISCAL-360-003

Severity: P1 HIGH  
Area: Staging validation  
Current status: BLOCKED  
Expected: `npm run test:staging:fiscal` runs on `fullpos_staging`.  
Actual: Script refused to run because current DB is `daleventa_pos`.  
Evidence: command output: `Refusing to run outside fullpos_staging; current database is daleventa_pos`.  
Files: `apps/api/scripts/fiscal-staging-validation.cjs`.  
Why it matters: The script contains important DB-level tests for 20/100 NCF concurrency, idempotency, exhaustion, sequence rules, and 100 quotes without NCF, but none executed here.  
Tenant impact: Medium until staging passes.  
Fiscal impact: High.  
Data-loss risk: Low in this run; guard protected local DB.  
Suggested fix: Run against disposable/staging DB named `fullpos_staging`.  
Tests required: capture JSON output and archive in validation doc.

## FISCAL-360-004

Severity: P1 HIGH  
Area: Production migration cutover  
Current status: PARTIAL  
Expected: Fresh DB migrate is clean and production cutover has verified backup/rollback/drift status.  
Actual: Local schema validates/builds, but production/staging migration deployment not executed in this audit. Current repo has only 3 active migrations plus legacy migrations moved to `migrations_legacy_pre_phase6`.  
Evidence: active migrations: `20260818190000_phase6_baseline`, `20260818193000_quote_tax_snapshots`, `20260818203000_sales_quote_refund_snapshots`; many legacy migrations are deleted from active folder and moved under `apps/api/prisma/migrations_legacy_pre_phase6`.  
Files: `apps/api/prisma/migrations`, `apps/api/prisma/migrations_legacy_pre_phase6`, `apps/api/scripts/start-prod.sh`.  
Why it matters: A database with old `_prisma_migrations` can diverge from the new baseline if cutover is not controlled.  
Tenant impact: High if deployed incorrectly.  
Fiscal impact: High.  
Data-loss risk: High if migration strategy is mishandled.  
Suggested fix: Execute documented staging cutover with backup and inspect production `_prisma_migrations` read-only before deploy.  
Tests required: `prisma migrate deploy` on fresh disposable DB; staging migration deploy; production read-only migration inventory.

# P2/P3 FINDINGS

## FISCAL-360-005

Severity: P2 MEDIUM  
Area: NCF visual leakage in admin UI  
Current status: PARTIAL  
Expected: POS UI must not preview/reserve next NCF. Admin sequence UI may show next number only for administration.  
Actual: Flutter `NcfSequenceModel.possibleNextNcf` builds next NCF string for contabilidad admin UI. Not used in POS voucher selector.  
Evidence: `apps/fulltech_app/lib/features/contabilidad/data/contabilidad_repository.dart`, `factura_fiscal_screen.dart`.  
Why it matters: Acceptable for admin sequence management, but must not leak into cashier POS.  
Suggested fix: Keep it out of POS; optionally label admin preview as administrative only.  
Tests required: POS test asserting no NCF text appears before sale response.

## FISCAL-360-006

Severity: P2 MEDIUM  
Area: Monetary precision duplication  
Current status: PARTIAL  
Expected: Backend Decimal is authoritative; previews should match but be marked previews.  
Actual: Backend uses `Prisma.Decimal`; Flutter uses `double` in preview/PDF/ticket model values.  
Evidence: `TaxCalculationService` uses `Prisma.Decimal`; Flutter `ProductTaxPreviewCalculator` and models use `double`.  
Why it matters: UI may show cent differences on edge values if not covered.  
Suggested fix: Keep backend authority and expand golden preview-vs-backend fixtures for edge cases.  
Tests required: shared JSON golden matrix for 0.01, 0.05, 0.99, 9.99, 99.99, 129.95, 333.33, 999.99 with quantities 1/2/3/7/11 and discounts.

## FISCAL-360-007

Severity: P2 MEDIUM  
Area: Physical PDF/ticket QA  
Current status: MANUAL QA ONLY for visual layout; code path/test content is PARTIAL/READY depending case.  
Expected: 80mm/58mm, long text, huge amounts, multipage PDFs visually verified.  
Actual: Automated PDF/ticket tests build bytes and assert content/snapshots, but no visual render/printer evidence in this run.  
Suggested fix: Run manual QA checklist in staging with real 80mm printer and PDF samples.

## FISCAL-360-008

Severity: P3 LOW  
Area: ts-jest config  
Current status: PARTIAL  
Expected: No deprecation warnings in quality gate.  
Actual: Jest warns `isolatedModules` config option is deprecated.  
Suggested fix: Move to `isolatedModules: true` in `tsconfig`.  
Tests required: `npm test` clean warning check.

# FALSE READY ITEMS

1. Cotizaciones fiscal UI: snapshots exist, but `_includeItbis` and ITBIS switches remain.
2. Staging fiscal validation: script exists, but did not run in this audit.
3. NCF concurrency: DB-level script exists for 20/100, but no successful local/staging evidence here and no HTTP concurrency evidence.
4. HTTP E2E fiscal: generic HTTP smoke scripts exist; fiscal chain does not.
5. Production readiness: start script has safety guards, but production migration divergence/cutover is not verified.
6. Visual PDF/ticket: automated byte/content checks exist, but visual/printer QA remains manual.

# MULTI-TENANT AUDIT

Evidence READY/PARTIAL:

- Sales create filters quote, client, product by `companyId` in `SalesService.create`.
- Sale refunds load original sale with `{ id, companyId }`.
- Reports use `companyId` in sale/refund/product/movement queries.
- NCF list/update uses authenticated `companyId`.
- Product taxable rate validation looks up active `Tax` with `{ companyId, isActive, rate }`.
- Quote find/create product/client paths use `companyId`.
- Prisma has tenant unique constraints for sale `clientRequestId` and `ncf`: `@@unique([companyId, clientRequestId])`, `@@unique([companyId, ncf])`.

Remaining gap:

- HTTP IDOR tests for product/client/tax/quote/sale/refund/NCF/report/PDF/ticket are missing.

# FISCAL MATH AUDIT

Backend authority:

- `TaxCalculationService.calculate` uses `Prisma.Decimal`, clamps global discounts to subtotal, computes included/added/exempt, then allocates included-tax rounding remainder by rate bucket.
- Sales and quotes call backend calculator before persistence except quote-to-invoice, which uses quote snapshots.
- Flutter preview duplicates calculation with `double`; acceptable as preview only.

Golden results from automated tests:

| Case | Status | Evidence |
|---|---:|---|
| 1180 Included = base 1000, ITBIS 180, total 1180 | PASS | `tax-calculation.service.spec.ts`, `product_tax_preview_calculator_test.dart` |
| 1000 Added = base 1000, ITBIS 180, total 1180 | PASS | backend + Flutter preview tests |
| 500 Exempt = exempt 500, ITBIS 0, total 500 | PASS | backend + Flutter preview tests |
| Mixed 1180 included + 500 exempt = total 1680 | PASS | backend test |
| FULLTECH/CANATECH base 21779.66, ITBIS 3920.34, total 25700 | PASS | backend tax test; quote/PDF/ticket model tests |

# NCF AUDIT

READY code evidence:

- Source of truth is backend/database, not Flutter POS.
- `NcfService.reserveNextNcf` selects active sequence by company/type and locks rows `FOR UPDATE`.
- Reservation and sale creation happen in one Prisma transaction in `SalesService.create`.
- `markIssued` writes audit log inside same transaction after sale creation.
- Same NCF text allowed across companies by schema, blocked within same company by `@@unique([companyId, ncf])`.
- UI POS voucher selector does not show or reserve NCF.

PARTIAL evidence:

- 20/100 concurrency and idempotency are present in `fiscal-staging-validation.cjs`, but not executed here.
- No HTTP concurrency test exists.

# QUOTE → INVOICE AUDIT

READY code evidence:

- `SalesService.create` loads `sourceQuotationId` by `{ id, companyId }`.
- When source quote exists, `normalizedItems` are built from quote item snapshots.
- Tax totals use `sourceQuotation.total`, `taxableBase`, `taxAmount`, `exemptAmount`, `discountAmount`.
- Backend test proves quote conversion does not call calculator and reserves one B01 NCF.

PARTIAL gaps:

- Double conversion prevention is not proven. Schema has `sourceQuotationId` index, but no unique constraint preventing multiple sales from same quote.
- HTTP E2E quote→B01 same total is missing.

# HISTORICAL SNAPSHOT AUDIT

READY code evidence:

- Sale stores item snapshots: product name/image, unit price, cost, gross, discount, taxable base, tax rate, tax amount, exempt amount, line total.
- Quote stores item snapshots similarly.
- PDF/ticket models read stored sale/quote model fields.

PARTIAL gaps:

- No automated immutability test that emits sale, mutates company/client/product, then reopens PDF/ticket/history and compares original snapshots.
- Issuer snapshot fields are not clearly persisted on sale; PDFs still appear to use current company settings for issuer data. That is PARTIAL for strict historical issuer immutability.

# PDF/TICKET AUDIT

PDF:

- Quote PDF fiscal detail columns: `Descripción`, `Cant.`, `Base`, `ITBIS`, `Total`.
- Invoice PDF fiscal detail columns follow the same fiscal snapshot pattern.
- Tax-off PDF tests ensure clean legacy invoice.
- B01/B02 invoice PDF tests build bytes and assert fiscal snapshot values.

Ticket:

- Normal ticket remains clean without fiscal block when no voucher/NCF.
- B01 ticket adds compact fiscal block: voucher label, NCF, customer, RNC, then snapshot totals.
- B02 ticket prints voucher/NCF without requiring RNC.
- Ticket data maps from `SaleModel` snapshot values.

Manual QA:

- 80mm physical output, 58mm if supported, long text, huge amounts, and multipage PDFs still require manual visual QA.

# REFUND AUDIT

READY/PARTIAL:

- Total and partial refund implemented as `Sale.kind = "refund"` with negative amounts derived from original item snapshots.
- Refund blocks quantity above remaining original quantity.
- Refund stock increment uses original item product/company.
- Fiscal formal credit-note document is OUT OF CURRENT SCOPE.

Gaps:

- Automated coverage confirms only “partial above remaining quantity rejects”.
- Refund total/exempt/mixed/discount/product-edited-after-sale need additional tests.

# REPORT/PROFIT/MARGIN AUDIT

READY/PARTIAL:

- Reports are tenant-scoped and use sale/item persisted values.
- Reports aggregate taxableBase/taxAmount/exemptAmount/discountAmount from sale items.
- Sales store commercialProfit/netTaxProfit and margins.
- Refund documents are included as negative/returned rows.

Gaps:

- No dedicated automated report fixture proving A=10000/B=20000 isolation.
- No full report-vs-sale consistency test for refunds/mixed tax/discounts.
- Commission historical behavior not exhaustively tested against fiscal changes.

# MIGRATION AUDIT

Local evidence:

- `npx prisma validate`: PASS.
- `npx prisma generate`: PASS.
- `npm run build`: PASS.

Schema evidence:

- Current active migration folder has phase baseline and two fiscal snapshot migrations.
- Legacy migrations are moved to `apps/api/prisma/migrations_legacy_pre_phase6`.
- `start-prod.sh` blocks `PRISMA_SYNC_MODE=push` in production unless explicit emergency env is set.
- `start-prod.sh` still allows `db push --accept-data-loss` outside production or with explicit override; acceptable only as non-production/emergency and must stay documented.

Gaps:

- Fresh DB migrate deploy was not executed in this audit.
- Staging migrate deploy was not executed.
- Production `_prisma_migrations` was not inspected read-only.

# AUTOMATED TEST EVIDENCE

Backend local:

```text
npx prisma validate: PASS
npx prisma generate: PASS
npm run build: PASS
npm test: 10/10 suites, 44/44 tests PASS
```

Flutter local from current working session:

```text
flutter analyze: PASS
flutter test: 129/129 tests PASS
flutter build web: PASS
```

Staging fiscal:

```text
npm run test:staging:fiscal: BLOCKED
Reason: script refused non-staging DB. Current database: daleventa_pos. Required: fullpos_staging.
```

HTTP E2E:

```text
Fiscal HTTP E2E: NOT FOUND / PARTIAL
Generic smoke scripts exist; fiscal B01/B02/NCF chain does not.
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
| Quantity | READY |
| Rounding | READY |
| Company Tax Settings | READY |
| Product Tax | READY |
| Service Tax | PARTIAL |
| Catalog | READY |
| Manual Product | READY |
| POS PC | PARTIAL |
| POS Mobile | PARTIAL |
| Voucher Selector | READY |
| B01 | PARTIAL |
| B02 | PARTIAL |
| NCF | PARTIAL |
| NCF Concurrency | BLOCKED |
| NCF Idempotency | BLOCKED |
| NCF Audit | READY |
| Customer Fiscal | READY |
| Quotes | PARTIAL |
| Quote Snapshot | READY |
| Quote PDF | READY |
| Quote → Invoice | PARTIAL |
| Issuer Snapshot | PARTIAL |
| Customer Snapshot | READY |
| Line Snapshot | READY |
| Historical Sale | READY |
| Historical PDF | PARTIAL |
| Historical Ticket | PARTIAL |
| Invoice PDF | READY |
| B01 PDF | READY |
| B02 PDF | READY |
| Normal Ticket | READY |
| B01 Ticket | READY |
| B02 Ticket | READY |
| Reprint | PARTIAL |
| Refund Total | PARTIAL |
| Refund Partial | PARTIAL |
| Refund Exempt | PARTIAL |
| Refund Mixed | PARTIAL |
| Profit Commercial | READY |
| Profit Net Tax | READY |
| Margin | READY |
| Reports | PARTIAL |
| Cash | PARTIAL |
| Shift Close | PARTIAL |
| Commissions | PARTIAL |
| Product Tenant Isolation | READY |
| Tax Tenant Isolation | READY |
| Client Tenant Isolation | READY |
| Quote Tenant Isolation | READY |
| Sale Tenant Isolation | READY |
| Refund Tenant Isolation | READY |
| NCF Tenant Isolation | READY |
| Report Tenant Isolation | PARTIAL |
| PDF Tenant Isolation | PARTIAL |
| Company Switch Product | READY |
| Company Switch Client | READY |
| Company Switch Cart | READY |
| Company Switch Voucher | READY |
| Company Switch Quote | PARTIAL |
| Provider Invalidation | READY |
| Permissions | PARTIAL |
| Offline Normal | READY |
| Offline Fiscal | READY |
| Import | READY |
| Export | PARTIAL |
| Prisma Schema | READY |
| Fresh DB Migrate | PARTIAL |
| Staging Migrate | BLOCKED |
| Production Cutover Plan | PARTIAL |
| Backend Tests | READY |
| Flutter Tests | READY |
| HTTP E2E | PARTIAL |
| Staging Fiscal Tests | BLOCKED |
| e-CF | OUT OF SCOPE |

# EXACT REMEDIATION PLAN

See `FULLPOS_FINAL_FISCAL_REMEDIATION_PLAN.md`.

# MANUAL QA ONLY

PC:

- Tax OFF sale.
- Included sale.
- Added sale.
- Exempt sale.
- Mixed sale.
- B01 with fiscal client.
- B02 final consumer.
- Quote create/edit.
- Quote→invoice.
- PDF invoice/quote.
- Ticket and reprint.
- Company switch A/B.

Mobile:

- Same applicable POS and quote cases at 360/390/430 widths.

Printer:

- 80mm real device.
- Long product names.
- Long customer/issuer names.
- NCF full width.
- Large amount RD$9,999,999.99.

Historical:

- Emit document, then edit company/client/product/tax data, reopen history/PDF/ticket and compare snapshots.

Multiempresa:

- Company A and B with same NCF text allowed across tenants but blocked within same tenant.

NCF:

- Use only staging/test sequence. Do not treat `B0100000014` as fiscally authorized unless the company has that real range.

# NUMERIC SUMMARY

```text
READY: 39
PARTIAL: 30
BLOCKED: 4
MANUAL QA ONLY: 1
OUT OF SCOPE: 1

P0: 0
P1: 4
P2: 3
P3: 1
```

FULLPOS traditional fiscal module is not technically closed for controlled staging validation.
