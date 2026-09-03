# FullPOS Cloud Testing

Last audited: 2026-09-02.

CODE PASS is not automatically FUNCTIONAL PASS.

## Test Locations

- Flutter tests: `apps/fulltech_app/test`
- Flutter integration tests: `apps/fulltech_app/integration_test`
- Flutter test driver: `apps/fulltech_app/test_driver`
- Backend tests: colocated in `apps/api/src` as `.spec.ts`, `.tenant.spec.ts`, `.e2e-spec.ts`, and related files.
- Backend manual notes: for example `apps/api/src/sales/manual-tests.md`.
- Visual evidence: `docs/*visual-evidence*` and `docs/final-production-uat`.

No `apps/api/test` directory was found.

## Flutter Commands

Run from `apps/fulltech_app` unless noted:

- Static analysis: `flutter analyze`
- All Flutter tests: `flutter test`
- One Flutter test: `flutter test test/path/to_test.dart`
- Integration test: `flutter test integration_test/path_to_test.dart`
- Web build verification: `flutter build web --release`
- Android build verification: `flutter build apk --release`
- iOS release build without codesign is configured in `codemagic.yaml`.

## Backend Commands

Run from repository root:

- API dev server: `npm run api:dev`
- API build: `npm run api:build`
- API smoke: `npm run api:smoke`
- API migrate dev: `npm run api:migrate:dev`
- API migrate deploy: `npm run api:migrate:deploy`
- API seed: `npm run api:seed`

Run from root with workspace command:

- All backend non-e2e Jest tests: `npm --workspace apps/api test`
- Unit specs: `npm --workspace apps/api run test:unit`
- Integration specs: `npm --workspace apps/api run test:integration`
- E2E specs: `npm --workspace apps/api run test:e2e`
- Security specs: `npm --workspace apps/api run test:security`
- Tenant specs: `npm --workspace apps/api run test:tenant`
- Deletion specs: `npm --workspace apps/api run test:deletion`
- Staging fiscal validation: `npm --workspace apps/api run test:staging:fiscal`
- UAT DB verification: `npm --workspace apps/api run uat:verify-db`

Dangerous or restricted commands:

- `npm run api:seed` / `npm --workspace apps/api run prisma:seed` require explicit authorization.
- `npm run api:migrate:deploy` requires environment verification and explicit authorization outside local/dev.
- Purge, repair, fix, backfill, and `--apply` scripts require explicit authorization.

## CI / Build Validation

`codemagic.yaml` contains:

- iOS release build without codesign.
- iOS TestFlight workflow.
- Flutter pub get.
- Flutter analyze.
- A focused unit/widget test for account settings navigation in TestFlight workflow.
- IPA build and artifact publication.

## Validation Policy

Use this sequence where applicable:

```text
IMPLEMENTATION
-> STATIC ANALYSIS
-> AUTOMATED TESTS
-> FUNCTIONAL VALIDATION
-> VISUAL VALIDATION
-> REGRESSION
-> GO / NO-GO
```

## Definitions

PASS:

- A specific check completed successfully with expected results.

FAIL:

- A specific check did not complete or produced unexpected results.

GO:

- Required static analysis, automated tests, functional validation, visual validation when applicable, and regression checks passed for the task scope.

NO-GO:

- A critical validation failed, required validation could not be executed, environment safety is uncertain, or production/tenant/data risk remains unresolved.

## Functional and Visual QA

User-facing features require functional validation. UI/UX changes require visual validation on relevant form factors when tooling allows it. Use existing visual evidence conventions when extending validated workflows.

## Regression Guidance

- Tenant/auth changes: run affected backend tenant/security tests and Flutter route/access tests.
- Inventory/warehouse changes: run products, inventory, warehouse, UOM, purchase/sale stock tests as applicable.
- Fiscal/sales/tax changes: run sales fiscal, tax, NCF, PDF, and related Flutter tests.
- Cash changes: run cash backend and Flutter cash tests.
- UI shell/navigation changes: run routing/navigation/account tests plus visual validation.
- Release changes: run build verification and release checklist.

## Physical Hardware QA (cash drawer / money drawer)

Automated tests are NOT sufficient for a GO on cash-drawer capability. A real
hardware test is required when compatible equipment is available:

1. Connect a standard cash drawer to a compatible thermal receipt printer.
2. Configure that printer in FullPOS (Impresora y tickets).
3. Tap "Probar apertura de caja": the drawer physically opens without printing a
   receipt.
4. Enable "Abrir caja automáticamente" and print an eligible cash sale: the
   receipt prints and the drawer opens exactly once.
5. Disable automatic opening and print again: the receipt prints and the drawer
   stays closed.
6. Verify a non-cash or administrative print (or a reprint) does NOT open the
   drawer unexpectedly.

Without compatible hardware the implementation is CODE COMPLETE but remains
`NO-GO — HARDWARE QA PENDING`; hardware results must never be faked.

