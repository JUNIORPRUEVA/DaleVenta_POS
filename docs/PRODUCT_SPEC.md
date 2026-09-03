# FullPOS Cloud Product Spec

Last audited: 2026-09-02.

This document describes confirmed product behavior from repository evidence only. Business rules not directly evidenced here are marked for owner validation.

## Product Purpose

FullPOS Cloud is a cloud-connected point-of-sale and business operations product for companies that need sales, inventory, clients, cash, purchasing, accounting/fiscal documents, staff, and operational workflows in one system.

Evidence: `apps/fulltech_app/README.md`, `apps/fulltech_app/lib/core/routing/routes.dart`, `apps/api/src/app.module.ts`, and `apps/api/prisma/schema.prisma`.

## Supported Platforms

- Flutter mobile: Android and iOS.
- Flutter Web/PWA.
- Flutter Windows desktop.
- Backend API: NestJS service intended for Docker/EasyPanel deployment.

Evidence: Flutter platform folders under `apps/fulltech_app/`, PWA Dockerfile, Windows runner files, Codemagic iOS workflows, and app README.

## Main User Types and Roles

Confirmed roles exist in Flutter and Prisma:

- `ADMIN`
- `CAJERO`
- `ASISTENTE`
- `VENDEDOR`
- `MARKETING`
- `TECNICO`

Role permissions are centralized on the Flutter side in `apps/fulltech_app/lib/core/auth/app_permissions.dart`. Backend role checks use JWT user context, `RolesGuard`, and Prisma role values.

## Main Modules

Confirmed application/API modules include:

- Authentication, registration, session restore, password recovery, account deletion.
- Users, profile, permissions, payroll, punch/time tracking.
- Catalog/products, product images, categories, inventory count, stock, Kardex.
- Warehouses, terminals, warehouse stock, transfers.
- POS sales, sales history, credits, reports.
- Cash box, sessions, movements, expenses, turn history.
- Clients, client detail, map/location features, CRM/commercial features.
- Quotations/cotizaciones and quotation PDFs.
- Purchases, suppliers, purchase orders, invoices, receipts, purchase PDFs.
- Accounting/contabilidad, daily closes, bank deposits, fiscal invoices, pending payments.
- Tax/NCF fiscal behavior for Dominican invoicing.
- Licenses and usage telemetry.
- Internal manual/company manual.
- AI assistant.
- Notifications.
- Storage/uploads/media gallery, including R2 presigned upload support.
- Service orders, technical operations, warranties, technical network, work scheduling.
- Marketing/publicidad, WhatsApp CRM, website-related modules.
- App updates and release download support.

## Core Business Capabilities

Confirmed capabilities:

- Tenant-scoped product/catalog, sale, purchase, cash, warehouse, and reporting operations.
- Product creation/update with stock and warehouse stock support.
- Product creation/editing can reuse the normal category creation dialog from the product form, preserving entered product data and selecting the newly created category.
- Inventory movements and Kardex-style history.
- When measurement units are enabled for the company, quick/manual sale items can carry a configured unit-of-measure snapshot such as Unidad, Yarda, or Libra through sale creation.
- Multi-warehouse feature flag and terminal warehouse assignment.
- Cash session/movement workflows and close ticket printing.
- Cash drawer / money drawer support through a compatible thermal ESC/POS printer: a centralized cash-drawer service sends only the standard `ESC p` kick pulse through the configured receipt printer (Windows RAW spooler; mobile Bluetooth/LAN ESC/POS path). Includes a "Probar apertura de caja" action and optional automatic opening after eligible cash-sale prints (OFF by default).
- Sales fiscal payloads, tax calculation, NCF sequences and audit logs.
- Quotation and purchase document PDF generation.
- Product image upload and storage through API uploads and/or external object storage.
- Role and permission-based navigation/action access.
- Offline/cache/sync behavior for some frontend flows.

## Multi-Company Behavior

The data model uses `Company` as the tenant root. Many backend services require a `companyId` from the authenticated user via `requireTenant`. Services and tests show tenant-specific querying and protection, especially products, clients, sales, tax, users, warehouses, and cotizaciones.

Important invariant: tenant/company data must not mix across authenticated contexts.

## Important Business Rules Evidenced

- Users must be authenticated for tenant operations and must have an assigned company.
- `ADMIN` has broad backend access in `RolesGuard` and broad Flutter permissions.
- Non-admin access is controlled by role defaults and optional `userPermissions` overrides.
- UAT startup refuses protected production-like database names and remote hosts unless server UAT mode is explicitly configured.
- Products can be protected from hard deletion when business history exists; archival/idempotent behavior is tested in product service tenant tests.
- Measurement Units can be disabled only when no ACTIVE product uses a unit of measure other than the canonical `UNIT`. An active product is one whose `archivedAt` is null (state "activo"); an archived product (`archivedAt` set, state "archivado") never blocks disabling and keeps its historical UoM, sales/quotation/purchase snapshots, and inventory history unchanged. The disable validation is strictly company-scoped.
- Product source can be `LOCAL` or an external FullPOS integration source.
- Cash drawer automatic opening is OFF by default (`autoOpenCashDrawer` for Windows/desktop). On Windows it opens only after a successful print of a NEW sale that involves cash (cash amount > 0 or method `cash`/`mixed`) and never on reprints (`isCopy`). On mobile (Android/iOS) automatic opening is governed by the existing mobile "Abrir gaveta" toggle (`openCashDrawer`) embedded in the ESC/POS print. A drawer failure never rolls back or corrupts a completed sale; it only surfaces a professional, non-blocking hardware warning.
- Multi-warehouse access is gated in routing by company settings.
- API Docker startup can run migrations; seeds are controlled by `RUN_SEED`.
- Receipt payment section (EFECTIVO RECIBIDO / DEVUELTA): every sale can
  persist two distinct cash concepts alongside the net cash: `cashReceived`
  (cash the customer actually tendered) and `changeAmount` (DEVUELTA returned).
  `paymentCashAmount` ALWAYS keeps its accounting meaning of NET cash retained
  by the sale (`cashReceived - changeAmount == paymentCashAmount`). Both fields
  are nullable: legacy/historical sales whose tender was never stored keep
  `NULL`, and tickets for those sales must NOT fabricate EFECTIVO RECIBIDO or
  DEVUELTA rows. New cash sales (including exact tender) print
  `EFECTIVO RECIBIDO` and `DEVUELTA` (RD$ 0.00 for exact) from the persisted
  values; transfer/card-only and credit-without-cash transactions do not print
  cash rows. Reprints use the persisted tender so the reprint matches the
  original checkout. Cash sessions, shift closing, cash reports, and cash
  drawer eligibility all continue to use the NET `paymentCashAmount`.

## Integrations

Confirmed or configured integrations:

- PostgreSQL through Prisma.
- Redis optional cache/infrastructure.
- Cloudflare R2-compatible object storage through S3 SDK/presigned uploads.
- EasyPanel/Docker deployment.
- Codemagic iOS workflows.
- External FullPOS product integration via `FULLPOS_INTEGRATION_*`.
- Appyra usage telemetry settings.
- Email/password reset configuration using `RESEND_API_KEY` and mail sender variables.
- Maps/location packages on Flutter.
- Socket.IO realtime catalog relay.

## Current Important Limitations

- Root `README.md` is minimal and does not describe the current project.
- Existing documentation is extensive but scattered across root audit reports, phase reports, and `docs/`.
- Secret-bearing `.env` files exist in the local workspace and must not be exposed.
- Some modules appear broad and may contain legacy behavior; owner validation is required before changing fiscal, inventory, license, tenant, or production workflows.
- Cash drawer automatic opening is supported for POS/cash sale prints only. The web/PWA browser cannot issue low-level drawer commands; the drawer is a Windows or mobile Bluetooth/LAN hardware action. Manual drawer opening from other cash interfaces and drawer behavior on shift-close prints are pending owner decisions (see CASH-DRAWER-01 report).

## Unfinished or Experimental Areas

OWNER VALIDATION REQUIRED:

- Which marketing, WhatsApp CRM, technical network, AI assistant, and website features are production-ready versus experimental.
- Which visual evidence folders represent current accepted UI versus historical validation.
- Exact paid plan/license commercial limits beyond the code-level license service behavior.
