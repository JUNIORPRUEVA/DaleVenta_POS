# FullPOS Cloud Offline UX and Error Surface Audit

Last updated: 2026-10-08.

## Objective

Make FullPOS behave professionally during network loss, backend downtime, timeouts, local-cache reads, queued offline writes, reconnect, and replay, without weakening financial/session hardening.

Production was not touched. No client database was modified.

## Current Architecture Found

| Layer | Evidence | Notes |
| --- | --- | --- |
| HTTP mapping | `core/api/api_error_mapper.dart` | Central mapper exists, but many repositories still create `ApiException` manually. |
| Customer-safe copy | `core/errors/user_facing_error.dart`, `user_safe_error_text.dart`, `app_error_policy.dart` | Central policy exists and now blocks more infrastructure markers. |
| Global error reporting | `core/debug/app_error_reporter.dart`, `app_error_overlay.dart` | Global overlay dedupes incidents, keeps diagnostics internal, and silences media/network noise in selected cases. |
| Offline store | `core/offline/offline_store.dart` | SQLite-backed local cache, offline sales, pending actions, and sync metadata. |
| Sync queue | `core/offline/sync_queue_service.dart` | Background replay, status counters, obsolete operation protection, retry/conflict handling. |
| Sync UX | `core/offline/sync_status_menu_button.dart` | Discreet status, customer labels for queued operations, technical sync detail sanitizer. |
| Local JSON cache | `core/cache/local_json_cache.dart` | Company-scoped cache backed by `OfflineStore`. |
| Cash hardening | `modules/cash/cash_repository.dart`, backend cash tests | Exact `sessionId` for close/movement; no current-open fallback. |
| Sales hardening | `modules/ventas/data/ventas_repository.dart`, backend sales tests | `clientRequestId`, `originCashSessionId`, terminal/device/warehouse snapshots, inventory snapshots. |

## Error Surface Inventory

Automated grep over `apps/fulltech_app/lib/**/*.dart` found many surfaces that need staged migration. High-signal categories:

| Area | Pattern | Risk | Status |
| --- | --- | --- | --- |
| Repositories | manual `ApiException(_message(e.response?.data...), e.response?.statusCode)` | Loses network/DNS/timeout classification; can end as `UNKNOWN`. | Partially fixed in Facturas; global migration pending. |
| Screens/snackbars | `SnackBar(content: Text(... error/message ...))` | Raw backend or raw exception text can reach user. | Some high-risk sales paths use safe helpers; global migration pending. |
| Auth screens | switch on `ApiErrorType` and display `error.message` for several cases | Business copy mostly structured, but new taxonomy cases must be kept safe. | Existing tests cover login mapping; review pending. |
| Settings/account | mixed local queued feedback and caught errors | Possible inconsistent wording; some queue success semantics already exist. | Needs staged migration. |
| Catalog/products | local-first controller exists but several snackbars catch raw errors | Product list is partially local-first; write errors need customer-safe wrappers. | Needs staged migration. |
| Contabilidad/reportes | many API-first repository calls | Many reports are server-authoritative; should be `ONLINE_REQUIRED` with safe states. | Audit documented; migration pending. |
| Nómina/compras/service orders | many catch/snackbar/dialog paths | Raw error exposure risk and unclear offline capability. | Pending. |
| Debug/diagnostic screens | technical text intentionally visible to admin/debug surfaces | Must stay restricted to diagnostics/admin, not customer workflow. | Allowed only in debug/admin context. |

## Technical Leak Markers

Customer-facing UI must not display:

- `ApiException`, `DioException`, `SocketException`, `TimeoutException`
- `UNKNOWN`, `Exception:`, `StackTrace`, `RequestOptions`, `validateStatus`
- `statusCode`, `status=`, raw HTTP codes as implementation detail
- `operationId`, `sessionId`, `cashSessionId`, `originCashSessionId`, `operationCashSessionId`
- storage paths, URLs, `/uploads/`, local DB paths
- Prisma/SQL/backend stack details

`user_safe_error_text.dart` now blocks these markers for callers using `userSafeErrorMessage`.

## Bugs Corrected In This Pass

| Bug | Cause | Fix |
| --- | --- | --- |
| Facturas showed `ApiException ... UNKNOWN` | UI used `e.toString()` and repository did not map Dio failures through central mapper. | `listInvoices` now uses `ApiErrorMapper`; UI uses `invoiceListErrorMessage`. |
| Facturas could replace cached list with full-screen refresh error | `_InvoiceListCard` checked `error != null` before considering visible local rows. | Blocking error only when no rows; cached rows remain visible with warning. |
| Customer-safe helper allowed some technical markers | Marker list missed `UNKNOWN`, IDs, DB and HTTP details. | Expanded technical marker list and tests. |

## False Failure Patterns Found

| Pattern | Evidence | Risk | Status |
| --- | --- | --- | --- |
| Sale local commit + remote network failure | `createSale` catches network failure, saves offline atomically, returns optimistic sale. | Correct: UI should show success. | Existing behavior preserved. |
| Print failure after saved sale | `UserFacingError.printing` and smoke tests | Correct: print warning must not mark sale failed. | Covered by existing tests. |
| Facturas local cache + remote failure | `TpvSalesHistoryScreen._load` and `_InvoiceListCard` | Previously false screen failure. | Fixed. |
| Settings queued save | `company_settings_feedback.dart` | Correct queued semantics already exist. | Preserved. |
| Manual repository exceptions after response loss | Several repositories create manual `ApiException` instead of mapping/retry/queue. | Potential false failures remain outside audited high-risk sales/cash paths. | Pending staged migration. |

## Local-First Screens Found

| Screen/flow | Current local-first evidence |
| --- | --- |
| Facturas | Reads `cachedInvoices` before API and keeps rows visible after failed refresh. |
| POS product picker | Loads cached products before remote refresh. |
| Catalog/products | Controller reads cached products and keeps previous items on refresh errors. |
| Credits | Reads cached credits before remote. |
| Cash state | Falls back to cached active session with `fromCache`/unverified state. |
| Company settings | Reads cached settings and queues supported writes. |
| Tax options | Reads cached tax options with TTL. |

## API-First / Online-Required Areas

| Area | Why |
| --- | --- |
| Login/register/password recovery | Server authority required for new authentication. |
| Fiscal NCF sale issuance | Backend must assign fiscal sequence. |
| Consolidated reports/accounting summaries | Server aggregates authoritative financial/accounting data unless specific cache exists. |
| App update download/check | Server/package availability required. |
| Product/inventory mutations | Offline safety not globally evidenced; must not fake stock writes. |
| Web/PWA SQLite-backed workflows | `resolveLocalDatabasePath` is unsupported on web. |

## Open vs Sync State Model

Operational state and sync state are separate:

- `OPEN + SYNCED`: normal online shift.
- `OPEN + SYNC_PENDING`: local shift open, remote confirmation pending. Safe operations may queue only if they carry stable origin identity.
- `OPEN + SYNC_FAILED`: local shift open, sync needs attention. Queue only operations that preserve exact context.
- `CLOSED + SYNC_PENDING`: local close captured; replay must target exact `sessionId`.
- `CLOSED + SYNCED`: no operational shift.

The UI must not present `OPEN + SYNC_PENDING` as "invalid turn"; it should present "turno abierto, sincronización pendiente/no verificada".

## Reconnect and Retry Policy

- Read retry is safe.
- Write retry must reuse the same operation identity when applicable.
- Sync queue replay owns write retry; UI should not encourage manually repeating committed offline writes.
- Reconnect should update sync state discreetly, not flood snackbars.

## Platform Notes

- Windows: persistent SQLite and logs are available; support script can collect metadata/read-only snapshots.
- Android/iOS: shared Flutter code applies, but printer/storage paths differ. Device/emulator UAT still required.
- Web/PWA: customer-safe errors apply, but full SQLite/offline sale guarantees are not promised.

## Forensic Observability

Added `scripts/support/collect_fullpos_diagnostics.ps1`:

- read-only;
- locates known FullPOS/DaleVentas Windows app data folders;
- collects recent logs;
- records DB/WAL/SHM metadata and checksums by default;
- copies DB/WAL/SHM only when explicitly run with `-IncludeBusinessDatabase`;
- writes manifest and ZIP;
- does not sync, open/close shifts, delete queue, or modify data.

## Remaining Work

- Migrate repositories to `ApiErrorMapper.fromDio` in staged groups.
- Migrate screen-level snackbars/dialogs to customer-safe copy objects.
- Add behavior/widget tests for catalog, clients, cash state, settings, reports, and online-only screens.
- Run full `flutter test` and full backend `npm --workspace apps/api test` after staged migrations.
- Perform local UAT with backend disconnected on Windows and mobile emulator/device.
- Collect real Asadero/La Bomba evidence before declaring real root cause found.
