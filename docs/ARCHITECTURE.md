# FullPOS Cloud Architecture

Last audited: 2026-09-02.

## High-Level Architecture

FullPOS Cloud contains the operational apps and a public static website:

- `apps/fulltech_app`: Flutter application for Android, iOS, Web/PWA, and Windows.
- `apps/api`: NestJS API using Prisma and PostgreSQL.
- `website`: Astro static public site, login and two-step business registration.
  `Dockerfile.public-web` publishes it alongside Flutter under the same origin.
  Astro serves public routes; Flutter retains operational URLs and `/home`
  through `pos.html`. `/api` keeps the existing backend proxy. Auth uses the
  existing API and a two-minute single-use handoff ticket; no separate user or
  tenant store is introduced. Registration creates account and company together
  only after step two. The form creates the handoff directly; `/preparando`
  remains for compatibility. Flutter opens the activation welcome and panel;
  company/fiscal setup remains available through its real configuration routes.
  The old questionnaire is retired from routing (`/onboarding` redirects to
  `/home`). Legacy status fields remain for old clients; the new progress is
  derived from activation data, not from an invented completion flag.

```text
Flutter app / PWA / Windows
  -> Dio API client, auth interceptors, route guards
  -> NestJS API
    -> Guards, controllers, services, modules
    -> Prisma Client
    -> PostgreSQL
    -> uploads volume and/or R2-compatible object storage
    -> optional Redis
    -> realtime Socket.IO catalog relay
```

## Repository Structure

### Electronic sales, connection and refund recovery

E31/E32 checkout persists its fiscal intent in `Sale.fiscalVoucherType` and the
E31 sequence expiry in `ncfExpirationDate` before preparation. Preparation checks
that type and uses the frozen expiry; a later client cannot substitute it. No
new sale or fiscal schema is introduced. Electronic operations require a real
read-only `/health` preflight with offline cache and retries disabled; interrupted POSTs produce an uncertain result,
never a new offline electronic invoice. Existing Windows durable sale attempts
retain their request identity for reconciliation.

New ordinary sales under the electronic module explicitly persist `NORMAL` in
the existing intent column, with null NCF/expiry. The sale adapter rejects fiscal
preparation for that intent. Printing bypasses the e-CF projection for Normal;
ordinary offline sale queues preserve the marker and existing authorization.
The POS draft stores its selected mode and whether it was chosen explicitly;
a new ticket independently defaults to Normal when the company permits it.
Legacy NULL intents retain their previous behavior without a data rewrite.

`GET /ecf/sales/fiscal?ids=...` projects up to 50 invoice IDs per request, scoped
to the authenticated company and sale owner/admin. It exposes fiscal intent,
reserved/issued e-NCF, environment, status and related E34 documents without
raw provider payloads. Historical reads retain document environments; preparation,
dispatch and print permissions keep their existing environment gates. Ambiguous
multiple originals are shown for review and automatic E34 preparation stops.

Electronic invoices cannot use ordinary sale cancellation. Financial returns
remain transactional; each return prepares its own exact E34 using a stable
refund-derived UUID. A partial return followed by returning the remainder never
relabels the last return as cancellation of the full original amount. Preparation
failure is returned as `ecfCreditPending`, not hidden behind financial success.
`POST /sales/:id/refunds/:refundId/fiscal` checks company, refund ownership relation
and refund permission, then retries only fiscal preparation. It never repeats
cash, inventory or accounting mutations. Automatic preparation beyond the fiscal
tax review window stops explicitly. A prepared note is reused on subsequent
recovery even after another return or passage of time.

Flutter's existing sales history presents these states and actions. Uncertain
fiscal actions require a read-only refresh before another action. Manual E34
preparation persists only its request UUID and payload hash, scoped to company,
user and original document, to prevent a changed request after a lost response.
Electronic sale PDFs require the persisted fiscal print projection. Existing
ticket transports and printer settings remain in use.

### ECF numbering environment boundary

The read-only `GET /ecf/sales/:saleId/print` projection checks sale ownership,
company and configured environment before exposing public fiscal print fields.
`GET /ecf/documents/:id/print` additionally serves standalone E34 representations
under `viewEcfDocuments`, always scoped to the authenticated company and current
environment. Its allowlisted projection includes frozen line amounts and credit
references; it exposes neither the provider response nor credential material.
The document detail uses the existing `UnifiedTicketPrinter.printTicket` and
shared PDF preview/actions. It creates no sale, opens no cash drawer, and emits
or allocates no fiscal number.
DOSA dispatch stores the public `printStamp` column only after a correlated response
and URL/identity/amount/environment validation. It is independent of the reserved
E34 payload and immutable once present; the reader retains legacy
`payloadSummary.printStamp` compatibility. It stores no credential material.
The default remains human review. The opt-in
`DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED=true` contract additionally records a
documented HTTP 200 accepted/conditionally accepted result, requiring the exact
server response receipt, attempt/request/document fingerprints, current company
and environment, consumed sequence, provider identity and validated stored QR.
An atomic transaction freezes the fiscal snapshot and records the receipt/hash
in the status log; an E34 applies its reservation under the existing balance and
original-document guards in that same transaction. The evidence authority is
`DOSA_REPORTED_DGII_RESULT` / `PROVIDER_DECLARED`, not an independently verified
DGII signature. Generic evidence quarantine and authenticity rules are unchanged.
Flutter shares the projection between
PDF and thermal renderers; printing and reprinting never emit or allocate numbers.

Numbering ranges, declared authorizations, allocation audit keys and document
external numbers are scoped by company and environment. Documents retain their
environment independently of subsequent company configuration changes. Database
triggers prevent reassignment of an existing document, range or authorization to
another environment. Numbering mutations hold a shared lock on the company ECF
configuration row; a stale client environment is rejected instead of redirected.

DOSA dispatch and pending-document selection resolve the environment from that
company's persisted fiscal configuration. The emission client, encrypted
credential lookup and cache use the same company/RNC/environment scope. The
legacy server environment selector does not redirect company documents; TEST
and authorized PRODUCTION dispatches can coexist. Production still requires
the server permission, company production opt-in and `PRODUCTION_READY`.
An unknown environment or a mismatch during authorization fails before opening
the credential vault. The explicit `POST /ecf/production/enable` transition uses
`manageEcfConfig`, a matching confirmed-company UUID, company configuration row lock, verified certification,
that company's active production credential and both production/confirmed-outcome
server flags. Unresolved TEST results block activation. It audits the transition
without emitting or allocating. Commercial preparation then requires the same
production readiness/gates and environment-scoped numbering. An environment edit
rechecks under lock and cannot silently reverse an activated company to TEST.

DOSA's live persisted dispatch may recover timeout, network or HTTP 5xx failures
with at most three HTTP calls total, preserving the original serialized bytes,
full URL/path (including E34 parameters), credential and e-NCF. Before calls two
and three it rechecks company authorization and credential fingerprint, locks
the company document and appends a hash-only recovery authorization to its status
log. The original `SEND_TO_PROVIDER` claim stays active; no new fiscal allocation
or logical attempt is created. Observed final fiscal results and HTTP 202 stop recovery.
Before initial transport a separate hash-only identity/lease is committed.
`POST /ecf/documents/:id/recover-dosa` permits a later identical POST for an
unknown, stale sending or DGII-pending result, under the existing preparation
permission. It validates every original identity hash and an expired lease while
holding the document lock and configuration shared lock. Each verification is
one HTTP call and a uniquely keyed `QUERY_PROVIDER` attempt; the original
`SEND_TO_PROVIDER` and number remain unique. Completion and unknown-result writes
check latest ownership under lock so a stale worker cannot overwrite recovery.
Historical documents without this proof stay blocked. No schema/dependency is
added by this continuation. See
[current recovery and Normal-sale evidence](ecf/ECF_NORMAL_PRODUCTION_RECOVERY_2026-11-13.md).

Validated RFCE E32 responses can bind a deterministic local receipt reference
without TrackId. The confirmed-outcome recorder may consume a receipt from an
authorized query attempt only with its persisted identity trace. HTTP202 with a
validated complete stamp and provider legend projects `CONTINGENCY`, not fiscal
acceptance. Subsequent acceptance preserves the immutable QR/security/signature;
the old pending legend is no longer displayed once accepted.

Migration `20261113040000_ecf_numbering_environment` conservatively keeps legacy
ranges in production and leaves legacy documents unclassified. It does not copy
TEST ranges or rewind counters. Legacy classification and coordinated API/client
rollout require a reviewed migration plan before any shared deployment; normal
updates cannot classify a NULL document because of the immutability trigger.
See [local validation and deployment limits](ecf/ECF_ENVIRONMENT_NUMBERING_2026-11-13.md).

- `apps/api`: backend API, Prisma schema/migrations/scripts, Dockerfile.
- `apps/fulltech_app`: Flutter app, platform folders, tests, integration tests, PWA Dockerfile.
- `docs`: operational docs, audits, visual evidence, UAT evidence.
- `scripts/uat`: local UAT database and app helper scripts.
- `tools`: local audit/validation helper scripts.
- Root audit/report Markdown files: historical implementation and validation reports.
- `codemagic.yaml`: iOS build/TestFlight workflows.

## Flutter Architecture

The Flutter app is organized around:

- `lib/core`: shared API, auth, routing, theme, widgets, offline/cache/sync, printing, PDF, license, company, app update, network, storage, startup, realtime.
- `lib/features`: feature-oriented screens/data/controllers such as auth, account, catalogo, contabilidad, products, reports, settings, splash, user, ventas, warehouses.
- `lib/modules`: larger business modules such as cash, clientes, compras, cotizaciones, nomina, ventas.

State management uses Riverpod (`flutter_riverpod`). API calls use Dio. Navigation uses GoRouter.

## Routing and Navigation

- Route constants live in `apps/fulltech_app/lib/core/routing/routes.dart`.
- GoRouter setup lives in `apps/fulltech_app/lib/core/routing/app_router.dart`.
- Route access and default-home logic live in `route_access.dart`.
- Auth, bootstrap, company setting, permission, and admin authorization state can redirect users.
- Shared navigation shell/drawer components live in `lib/core/widgets/`.

## Backend Architecture

The API is NestJS. `apps/api/src/app.module.ts` imports modules for auth, users, products, license, telemetry, clients, contabilidad, sales, payroll, cotizaciones, locations, work scheduling, AI assistant, notifications, storage, warranties, cash, reports, purchases, settings, tax, inventory, and warehouses.

`apps/api/src/main.ts` configures:

- UAT safety assertion.
- Request logging.
- Compression.
- Body size limits.
- Global exception filter.
- Static `/uploads` serving.
- Validation pipe with whitelist and non-whitelisted rejection.
- CORS.
- Realtime catalog relay.

## API Communication

Flutter API routes are centralized in `apps/fulltech_app/lib/core/api/api_routes.dart`. Auth/session handling is in `lib/core/auth`, with token storage, interceptors, and session hydration.

## Database and Prisma

Prisma schema is `apps/api/prisma/schema.prisma`. Migrations are under `apps/api/prisma/migrations`; legacy migrations are preserved under `migrations_legacy_pre_phase6`.

The schema includes tenant, user, inventory, warehouse, sale, cash, fiscal, purchase, service-order, payroll, marketing, WhatsApp, CRM, and AI assistant data models.

Important root models/enums include `Company`, `User`, `CompanyMember`, `AuthSession`, `Product`, `Warehouse`, `WarehouseStock`, `Terminal`, `InventoryMovement`, `WarehouseTransfer`, `Sale`, `CashSession`, `NcfSequence`, `Tax`, `PurchaseOrder`, `Client`, `Cotizacion`, `ServiceOrder`, and `AiAssistantConversationTurn`.

Inventory optionality fields are default-preserving and active in sales:
`Company.inventoryEnabled` defaults to enabled, `Product.itemType` defaults to
`PRODUCT`, `Product.trackInventory` defaults to true, and
`SaleItem.inventoryTrackedSnapshot` records whether a sale line physically
affected inventory. Sales, cancellation, and refund restoration use the
persisted sale-item snapshot for historical safety.

## Authentication

Backend authentication uses JWT/passport strategy and auth services/controllers. Flutter stores tokens locally through `TokenStorage` and hydrates sessions on app start. Password recovery and account deletion are present.

DaleVentas client builds are guarded by `ProductConfig`: the production default
API host is `daleventapos-backend.gcdndd.easypanel.host`, and known
wrong-product hosts such as `ventas-fullpos-backend.gcdndd.easypanel.host` are
rejected before API requests proceed. Session bootstrap validates token user and
company identity against the cached user snapshot before rendering an
authenticated tenant.

## Authorization and Permissions

Backend authorization uses `RolesGuard`, role decorators, permission decorators, JWT payload context, `userPermissions`, and optional admin-authorization tokens.

Flutter authorization uses `AppRole`, `AppPermission`, `rolePermissions`, route access checks, and UI-level permission checks.

## Multi-Tenancy

`Company` is the tenant boundary. Backend services commonly call `requireTenant(user)` to obtain `companyId` and scope database queries. Tenant-specific tests exist for products, users, clients, sales, tax, cotizaciones, and related behavior.

Invariant: every tenant-owned read/write must be scoped by authenticated `companyId`, or by a documented global/system ownership rule.

## Licensing

Backend has a `license` module and Prisma license-related enums/models such as `LicenseStatus` and `CompanyLicenseAuditLog`. Products service calls license checks such as product creation limits. Flutter has `core/license` and account license routes.

OWNER VALIDATION REQUIRED for commercial plan limits and current production license policy.

## Inventory and Warehouse Architecture

Inventory is represented through products, warehouse stock, inventory movements, transfers, terminals, and zero-config state. Relevant modules:

- Backend: `products`, `inventory`, `warehouses`, `terminals`, `purchases`, `sales`.
- Flutter: `features/products`, `features/warehouses`, `core/uom`, `core/offline`.

Multi-warehouse is gated by company settings on the frontend and has backend services/tests.

Sales inventory mutation is gated per line by the effective rule:
`company.inventoryEnabled && product.itemType == PRODUCT &&
product.trackInventory`, limited to supported local catalog products. Flutter
captures this decision in the sale item payload before offline storage, and sync
replay sends the original snapshot so company/product config drift does not
change the physical semantics of an offline sale. Cancellation and refund
restoration never use current product/company config when a sale-item snapshot
exists.

The same effective physical-inventory rule gates purchase receipts with
`updateInventory=true`, product stock adjustments/recounts, and warehouse
transfers. Purchase orders and receipts remain commercial documents for
services and non-inventory products; those lines do not create `WarehouseStock`,
`Product.stock`, or `InventoryMovement` changes. Physical stock reports and
zero-config warehouse stock rows include only tracked `PRODUCT` items, while
Kardex/movement history remains readable for historical audit.

## Offline, Cache, and Sync

Flutter contains `core/offline`, `core/cache`, sync queue services, pending sync actions, offline store, network reachability, and sync status UI. Existing docs include `OFFLINE_SYNC_ARCHITECTURE.md` and `OFFLINE_CAPABILITY_MATRIX.md`.

OWNER VALIDATION REQUIRED for the complete supported offline guarantee per module.

## File, PDF, and Printing Architecture

- API serves local uploads under `/uploads`.
- Storage module supports presigned object uploads and confirmation.
- Flutter contains `core/pdf`, `core/printing`, PDF services in sales/cotizaciones/compras/contabilidad, and printer settings.
- Receipt/ticket rendering and platform printer transports are covered by tests.

## Cash Drawer (Hardware) Integration

Cash-drawer control is a hardware side effect of the POS printing stack, kept
logically separate from documents, sales, inventory, and fiscal records.

Architecture (see `CASH-DRAWER-01` report):

```text
POS cash sale / test button
  -> Printer settings (autoOpenCashDrawer, cashDrawerChannel, printer name)
  -> UnifiedTicketPrinter (sale receipt; success point reached)
  -> CashDrawerService (lib/core/printing/cash_drawer/cash_drawer_service.dart)
  -> CashDrawerCommand.pulseBytesForChannel()  (standard ESC/POS `ESC p`,
     channel Automatic/Pin 2 default; Pin 5 optional)
  -> WindowsRawPrinterTransport (WinSpool RAW) on Windows
     |  MobilePrintService.sendDrawerPulse() on Android/iOS (Bluetooth/LAN)
     -> thermal printer -> RJ11/RJ12 drawer pulse
```

- Centralized: only `CashDrawerService` emits drawer bytes; no screen writes raw
  kick commands. `cash_drawer_command.dart` is the single command source
  (standard `ESC p`, capability-based, no per-brand adapters). The physical
  output channel is modeled explicitly as `CashDrawerChannel`
  (`automatic` / `pin2` / `pin5`) instead of brand branches, because RJ11/RJ12
  pinout differs between printers and drawers. `automatic` resolves to Pin 2,
  which is the historical FullPOS pulse and keeps existing installations
  working unchanged.
- Windows: drawer pulses are sent as a RAW WinSpool job to the configured
  receipt printer regardless of `windowsPrinterMode`, so the normal PDF/driver
  receipt stack is untouched. Because the pulse is a 5-byte device command, the
  drawer transport is created with `checkQueueBeforeWrite: false`: a
  driver-reported queue state (paused/offline/error) is logged as diagnostics
  but never blocks the pulse. Document RAW printing keeps the blocking check.
  Reprints never open the drawer.
- Mobile (Android/iOS): the "Abrir gaveta" toggle embeds the pulse in the
  existing ESC/POS Bluetooth/LAN path; the test action uses
  `MobilePrintService.sendDrawerPulse()` (drawer only, no receipt).
- Web/PWA: no raw drawer commands from the browser; reported as unsupported.
- Failure isolation: a drawer failure never rolls back or corrupts a completed
  sale/print; it returns a non-blocking `PrintTicketResult.warning`.
- Settings: desktop `PrinterSettingsModel.autoOpenCashDrawer` and
  `PrinterSettingsModel.cashDrawerChannel` (local per-device sqflite columns,
  auto-migrated, OFF / `automatic` defaults); mobile `openCashDrawer`.
  Diagnostics: the settings test action accepts a channel override so support
  can try Drawer 2 (Pin 5) without altering saved configuration; the service
  logs printer, channel, pin, byte count, bytes written and Win32 error, and
  returns a `technicalDetail` string (log/report only, never client UI).
- Transport result semantics: `RawPrintStage`
  (`PRINTER_NOT_FOUND` / `OPEN_PRINTER_FAILED` / `START_DOCUMENT_FAILED` /
  `START_PAGE_FAILED` / `RAW_WRITE_FAILED` / `PARTIAL_WRITE` /
  `RAW_WRITE_SUCCEEDED`) distinguishes where the job failed. Partial writes are
  failures. `RAW_WRITE_SUCCEEDED` means **command sent to the spooler**, not
  that the drawer physically opened — FullPOS never claims hardware
  confirmation. The WinSpool path emits a step trace
  (`OpenPrinterW → StartDocPrinterW → StartPagePrinter → WritePrinter →
  EndPagePrinter → EndDocPrinter → ClosePrinter`) to internal logs.
- Command profile is generic `EPSON_ESC_POS` (CR-330K is an Epson-standard
  drawer, SEWOO SLK-TS100 is ESC/POS); no per-brand code branches. The
  real-time `DLE DC4` pulse is intentionally not implemented (no explicit vendor
  evidence); `ESC p` remains the only pulse command.
- Tests: `test/core/printing/cash_drawer/*` cover command bytes, service
  policy/transports, and `printSaleTicket` wiring; widget test covers the
  settings UI section. Physical hardware QA is required before GO.

## External Services

Configured integrations include PostgreSQL, optional Redis, R2-compatible storage, FullPOS product source, Appyra usage telemetry, email/password reset provider variables, EasyPanel, Docker, and Codemagic.

## Deployment Infrastructure

- API Dockerfile builds Node/Nest service and runs `scripts/start-prod.sh`.
- Flutter PWA Dockerfile builds Flutter web and serves with Nginx.
- Codemagic builds iOS artifacts/TestFlight workflows.
- UAT scripts support local Dockerized PostgreSQL and guarded UAT startup.

## Data Ownership Boundaries

- Tenant data belongs to a `Company`.
- Authenticated user context determines active company.
- Some reference/config data may be global or company-specific; code must check schema/service behavior before changing it.
- Storage objects/evidence must be associated back to authenticated service/company records where applicable.

## Observed Risks / Technical Debt

- Documentation is fragmented across many audit and phase reports.
- Root `.env` and app/API `.env` files exist locally with sensitive values; future work must avoid printing them.
- Root `package.json` references an `apps/web` workspace script, but no `apps/web` directory was found.
- `.gitignore` currently lists the observed root/API/UAT/Flutter env files, including `apps/fulltech_app/.env`; any new env-bearing path must be added before it can be considered safe.
- Some API startup paths can run migrations automatically; release work must review environment flags before deployment.
- Root contains temporary/test helper files from previous work that are not part of canonical governance.

### Manual production ECF migration checkpoint —2026-11-13

The reviewed0400/0500/0600 SQL was executed in one bounded transaction after
restoring a verified production backup locally. Prisma5.22 migrate resolve
recorded each original checksum; all223 prior migration rows were retained.
The live API container/image and automatic-migration disablement are unchanged.
Five manifest-bound FULLTECH engineering trials were classified Sandbox with
status/fiscal identity preserved. The candidate separates reviewed terminal
trials from unresolved operational results for production activation and checks
their original numbering frontier on Sandbox declaration/renewal/allocation.
See ecf/ECF_PREDEPLOY_AUDIT_2026-11-13.md for backups, gates and publication state.

### Reproducible API and website build inputs

The root package-lock.json remains the API dependency authority.
scripts/release/sync_api_docker_lock.mjs projects its reachable API graph into
a generated apps/api/package-lock.json for EasyPanel's standalone /apps/api
context. Docker uses npm ci; CI verifies the generated lock with --check.
The script does not resolve new versions. The API Docker builder/runner and
backend CI now pin Node22.23.4 LTS; Nest11 and Prisma5.22 stay on their locked
versions. The static Astro7.4.12 stage pins Node22.23.4-alpine;
no public-page source or API/auth contract was changed by that upgrade.
The final API/PWA stages expose the supplied GIT_SHA as their image revision.

### Electronic sale admission and atomic local preparation

Explicit E31/E32 checkout shares a read-only admission policy with POS
capabilities: fiscal preparation permission, enabled DOSA company, certified
environment, explicit company production activation when applicable, server
gates, own issuer/ACTIVE environment credential metadata and available range.
The sale transaction rechecks admission while holding the company configuration
lock. Financial sale, stock mutations, sequence allocation and local fiscal
draft commit together. A local fiscal validation/mapping failure rolls them all
back. Standalone preparation retains its existing idempotency and committed
numbering semantics.

External dispatch remains after commit. A timeout after sending is an uncertain
fiscal outcome, handled by the existing persisted recovery/idempotency path;
it never justifies deleting the sale or sending a different fiscal identity.

Ordinary ITBIS is not electronic identity. The sale read model adds
hasElectronicFiscalDocument for historical NULL intents linked to E31/E32,
scoped to the active company. New typed E31/E32 are explicit; NORMAL overrides
any fiscal link. Ticket/PDF callers use this identity instead of taxEnabled.
Absent additive fields remain compatible with old ordinary sale responses.
