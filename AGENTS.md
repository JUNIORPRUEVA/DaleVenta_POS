# FullPOS Cloud Codex Instructions

## Project

This repository is FullPOS Cloud, a Flutter/PWA/desktop POS product with a NestJS API and Prisma/PostgreSQL backend.

Always preserve existing architecture, tenant isolation, licensing behavior, and business behavior unless the current task explicitly requires a change.

## Documentation Routing

Before work:

- Business behavior: read `docs/PRODUCT_SPEC.md`
- Architecture, data, backend, Prisma: read `docs/ARCHITECTURE.md`
- Environment, server, database, deployment target: read `docs/ENVIRONMENTS.md`
- UI/UX: read `docs/DESIGN_SYSTEM.md`
- Testing and validation: read `docs/TESTING.md`
- Release: read `docs/RELEASE.md`
- Development process: read `docs/WORKFLOW.md`

For UI tasks:

- Always read `docs/DESIGN_SYSTEM.md` before creating or modifying screens, widgets, navigation, layout, typography, colors, spacing, icons, dialogs, empty states, loading states, responsive behavior, or visual assets.
- Read `docs/PRODUCT_SPEC.md` when the UI displays, edits, filters, hides, validates, or labels business concepts such as products, inventory, warehouses, sales, cash, fiscal/tax, licenses, users, roles, tenants, clients, purchases, service orders, or accounting.
- Read `docs/ARCHITECTURE.md` when the UI depends on routing, state management, API contracts, offline/cache/sync behavior, auth/authorization, tenant boundaries, storage, printing/PDF, or backend data flow.
- Read `docs/ENVIRONMENTS.md` when the UI task involves API targets, runtime config, `.env` files, local/UAT/staging/production behavior, seeded data, uploaded media, external services, or any database-adjacent validation.
- Always read `docs/TESTING.md` before deciding validation, test commands, functional QA, visual QA, regression scope, or GO/NO-GO.
- Read `docs/WORKFLOW.md` for every substantial UI feature, bug fix, UX change, or phased implementation so scope, acceptance criteria, validation, and checkpoint rules are explicit.

Use existing historical reports and evidence in `docs/`, root audit reports, and visual evidence folders as supporting context when relevant. Do not duplicate or contradict the canonical docs without updating them.

## Permanent Safety Rules

- Production is protected by default.
- No production seed.
- No destructive production database operation.
- No unapproved production migration.
- No accidental tenant/company data mixing.
- Preserve multi-tenant isolation.
- Never expose secrets.
- Do not invent business rules.
- Do not silently change architecture.
- Do not perform broad refactors during unrelated tasks.
- Keep changes within requested scope.
- Do not advance automatically to another phase.
- Prefer minimal, reversible changes.
- Use backups/checkpoints where the documented workflow requires them.

## Explicit Authorization Required

Get explicit authorization in the current task before running or changing any of these:

- Seeds, data purge scripts, destructive scripts, or data repair scripts.
- Prisma migrations against any shared, staging, UAT server, or production database.
- Production deployment or production configuration changes.
- Changes to credentials, secrets, `.env` values, license enforcement, tenant ownership, inventory, sales, cash, fiscal, payroll, or accounting behavior.

## UI Rule

Before creating or modifying UI, inspect `docs/DESIGN_SYSTEM.md` and existing reusable components. Do not invent a separate visual language for a new screen.

## Validation Rule

Do not declare a task complete simply because it compiles. Run the applicable validation from `docs/TESTING.md`.

Visual or user-facing behavior must be tested visually/functionally when available. A critical failed validation means NO-GO.

## Final Report

Every substantial task should report:

- Scope completed.
- Files changed.
- Tests executed.
- Functional verification.
- Visual verification where applicable.
- Regression checks.
- Risks or unresolved issues.
- Final proposed status: GO or NO-GO.
