# FullPOS Cloud Architecture

Last audited: 2026-09-02.

## High-Level Architecture

FullPOS Cloud is a two-app workspace:

- `apps/fulltech_app`: Flutter application for Android, iOS, Web/PWA, and Windows.
- `apps/api`: NestJS API using Prisma and PostgreSQL.

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

## Authentication

Backend authentication uses JWT/passport strategy and auth services/controllers. Flutter stores tokens locally through `TokenStorage` and hydrates sessions on app start. Password recovery and account deletion are present.

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

## Offline, Cache, and Sync

Flutter contains `core/offline`, `core/cache`, sync queue services, pending sync actions, offline store, network reachability, and sync status UI. Existing docs include `OFFLINE_SYNC_ARCHITECTURE.md` and `OFFLINE_CAPABILITY_MATRIX.md`.

OWNER VALIDATION REQUIRED for the complete supported offline guarantee per module.

## File, PDF, and Printing Architecture

- API serves local uploads under `/uploads`.
- Storage module supports presigned object uploads and confirmation.
- Flutter contains `core/pdf`, `core/printing`, PDF services in sales/cotizaciones/compras/contabilidad, and printer settings.
- Receipt/ticket rendering and platform printer transports are covered by tests.

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
