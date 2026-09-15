---
description: "Use when editing the NestJS API in apps/api (controllers, services, DTOs, guards, Prisma access, sockets, PDF, media) or its Jest specs. Covers tenant scoping, contract safety, real build/test commands, and authorization-restricted scripts."
applyTo: "apps/api/**"
---

# Backend API rules (`apps/api`)

Stack: NestJS 11, TypeScript 5.6, Prisma 5.22 (`prisma-client-js`), PostgreSQL, Jest 30 (ts-jest, supertest), socket.io, ioredis, pdfkit, sharp, AWS S3 SDK (Cloudflare R2 media).

Layout: one folder per domain under `src/` (`auth`, `sales`, `cash`, `inventory`, `products`, `clients`, `purchases`, `tax`, `warehouses`, `license`, `users`, `reports`, `contabilidad`, `notifications`, `storage`, `order-document-flow`, ...). Specs are colocated: `*.spec.ts`, `*.tenant.spec.ts`, `*.integration-spec.ts`, `*.e2e-spec.ts`.

## Non-negotiable rules

- **Tenant isolation**: every query and mutation stays scoped to the authenticated tenant/company. Never add a query that can read another tenant's data — not even in scripts, reports, or audits.
- **Contracts**: preserve existing response shapes unless the task explicitly changes the contract; when it changes, update the Flutter mapping in the same task and keep backward compatibility for existing clients/caches.
- **Validation**: reuse the existing DTO / class-validator patterns; never weaken validation or guards to make a test pass.
- **Transactions & idempotency**: follow the existing patterns for sales, cash, inventory, purchases, and sync flows; do not introduce non-transactional multi-write sequences.
- **Errors**: log with stack traces and return meaningful messages. Never fail silently.
- **No leftovers**: no debug logs, no temporary `TODO`s, no commented-out code, no hardcoded test values.

## Commands

From the repository root:

- Install: `npm ci`
- Build / typecheck: `npm run api:build` (`prisma generate` + `tsc`)
- All non-e2e tests: `npm --workspace apps/api test`
- Scoped suites: `npm --workspace apps/api run test:unit | test:integration | test:e2e | test:security | test:tenant | test:deletion`
- Local dev / smoke: `npm run api:dev`, `npm run api:smoke`
- Schema validation: `npx prisma validate` from `apps/api`

## Restricted without explicit authorization in the current task

Seeds and data scripts: `npm run api:seed` / `prisma:seed`, `db:purge:*`, `integrity:fix`, `audit:tenant-ownership:apply`, `backfill:tenant-ownership`, `whatsapp:inbox:repair:execute`, `whatsapp:media:repair`, `media:migrate:r2`, `reset-whatsapp-inbox-data`, `auth:reset-password`. Migrations: `api:migrate:dev`, `api:migrate:deploy`. Never run these against shared, staging, UAT, or production databases (see `docs/ENVIRONMENTS.md` and `docs/RELEASE.md`).

Never print or log secrets, tokens, credentials, or `.env` values — including in error output during debugging.
