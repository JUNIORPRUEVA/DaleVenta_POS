# FULLPOS FINAL FISCAL REMEDIATION PLAN

Updated: 2026-08-18

Verdict basis: `A - TECHNICALLY CLOSED`.

No production deploy, no production migration, no e-CF.

# REMEDIATION CLOSED

| Previous item | Final status | Evidence |
|---|---|---|
| Historical PDF immutability | CLOSED | Sale issuer/customer/product/tax snapshots persisted; PDF/ticket consume snapshots; automated PDF/ticket tests pass |
| Profit/Margin/Reports | CLOSED | Real HTTP E2E report isolation A=10000, B=20000; backend tests green |
| Permissions | CLOSED | Real HTTP E2E admin allow/cashier deny for fiscal settings and NCF admin |
| Import/Export | CLOSED | Legacy import test, fiscal import test, fiscal export columns |
| HTTP E2E | CLOSED | AppModule/JWT/guards/DB E2E: 4 tests passing |
| Staging migrations | CLOSED | `prisma migrate deploy` and `migrate status` pass on `fullpos_staging` |
| Staging fiscal validation | CLOSED | `npm run test:staging:fiscal` passes |
| Staging NCF concurrency | CLOSED | 20 and 100 sale validations pass with unique NCF |
| Staging idempotency | CLOSED | 20 same `clientRequestId` -> 1 sale / 1 NCF |

# REMAINING WORK

Only non-code release tasks remain:

- Manual human QA on PC/mobile flows.
- Manual visual PDF/ticket QA.
- Physical printer QA.
- Production backup.
- Production migration inventory.
- Controlled deployment and rollback plan.

# PRODUCTION GUARDRAILS

- Do not use `prisma db push` for production.
- Do not run destructive commands against `daleventa_pos`.
- Use `prisma migrate deploy` only after backup and cutover approval.
- e-CF remains future scope.
