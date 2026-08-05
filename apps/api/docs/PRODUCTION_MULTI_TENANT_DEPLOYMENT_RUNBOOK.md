# Production Multi-Tenant Deployment Runbook

Date: 2026-08-05

## Pre-Deploy

1. Take a database backup and verify restore access.
2. Deploy to staging with production-like data.
3. Run:

```bash
npm ci
cd apps/api
npx prisma validate
npm run audit:tenant-inventory
npm run audit:endpoints
npm run audit:unsafe-tenant-queries
npm test
npm run build
npm run audit:tenant-ownership
```

4. Resolve every `audit:unsafe-tenant-queries` error before claiming full IDOR coverage.
5. Resolve every unsafe row from `audit:tenant-ownership` before enforcing stricter tenant constraints.

## Deploy

```bash
cd apps/api
npm run prisma:migrate:deploy
npm run build
```

The new auth-session migration creates `auth_sessions`. After deployment, old access/refresh tokens without `sessionId` are intentionally rejected, so users must log in again.

## Post-Deploy Smoke Tests

- Login succeeds and creates a session row.
- Refresh rotates the session and revokes the previous refresh token.
- Reusing an old refresh token fails and revokes the token family.
- `GET /auth/me` rejects revoked sessions.
- Account deletion rejects wrong password.
- Account deletion rejects sole-owner company deletion without the exact phrase.
- Normal account deletion revokes sessions and anonymizes the user.
- Sole-owner company deletion deletes tenant-prefixed storage objects.

## Current Blockers

- The tenant ownership audit could not connect to the configured database host during this hardening pass.
- The strict unsafe-query audit currently reports remaining errors in multiple modules.
- Row-level security was not enabled because the application does not yet set tenant context on every transaction.

Do not label the platform production-hardened for multi-tenant isolation until those blockers are closed.
