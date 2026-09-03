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
- Inventory movements and Kardex-style history.
- Multi-warehouse feature flag and terminal warehouse assignment.
- Cash session/movement workflows and close ticket printing.
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
- Product source can be `LOCAL` or an external FullPOS integration source.
- Multi-warehouse access is gated in routing by company settings.
- API Docker startup can run migrations; seeds are controlled by `RUN_SEED`.

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

## Unfinished or Experimental Areas

OWNER VALIDATION REQUIRED:

- Which marketing, WhatsApp CRM, technical network, AI assistant, and website features are production-ready versus experimental.
- Which visual evidence folders represent current accepted UI versus historical validation.
- Exact paid plan/license commercial limits beyond the code-level license service behavior.
