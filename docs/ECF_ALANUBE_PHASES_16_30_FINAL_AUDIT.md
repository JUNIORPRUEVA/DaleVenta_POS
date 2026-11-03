# ECF Alanube phases 16-30 final audit

Date: 2026-10-14.

## Initial state

- Worktree: `FULLPOS-ECF-ALANUBE`.
- Branch: `feature/ecf-alanube`.
- Reference HEAD: `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.
- Token Sandbox: stored locally through DPAPI and available through
  `env://ALANUBE_SANDBOX_TOKEN`.
- Emission: blocked.
- Real Alanube/DGII calls: not executed.

## Implemented changes

- Reconciled e-CF local code and preserved existing work.
- Strengthened document persistence schema with additive migration
  `20261014143000_add_ecf_document_idempotency`.
- Added document state machine with explicit transition matrix.
- Added safe response interpreter for HTTP/provider outcomes.
- Added real HTTP transport class that is inert unless injected and invoked;
  tests use mocked `fetch` only.
- Added reconciliation planner blocked until official query contract is
  available.
- Added webhook envelope placeholder blocked until official signature/auth
  contract is available.
- Preserved pure POS adapter without modifying sales/offline modules.

## PostgreSQL UAT

Migration application status: applied to isolated UAT only.

Backup created before migration:

```text
artifacts/uat-backups/fullpos_alanube_uat_before_ecf_docs_20261014-092300.dump
```

Backup size verified: 565953 bytes.

Target when authorized by checklist:

```text
Host: 127.0.0.1
Port: 56550
Database: fullpos_alanube_uat
Container: fullpos_alanube_uat_postgres
```

Applied migration:

```text
20261014143000_add_ecf_document_idempotency
```

Verification:

- Tables created:
  - `ecf_electronic_documents`.
  - `ecf_electronic_document_attempts`.
  - `ecf_electronic_document_status_logs`.
- Default document status: `LOCAL_DRAFT`.
- Synthetic PostgreSQL UAT test passed inside a transaction with rollback:
  - Inserted synthetic companies.
  - Inserted synthetic e-CF document.
  - Inserted attempt and status log.
  - Verified duplicate idempotency key is blocked.
  - Verified cross-company count isolation.
  - Rolled back all synthetic rows.

## Alanube contracts

Confirmed public:

- Sandbox base URL: `https://sandbox.alanube.co/dom/v1`.
- Auth header: `Authorization: Bearer <token>`.
- E31: `POST /fiscal-invoices`.
- E32: `POST /invoices`.
- E34: `POST /credit-notes`.

Still unknown or partial:

- Full OpenAPI/JSON Schema.
- Exact success responses.
- Exact error bodies/codes.
- Idempotency support from provider.
- Query/document reconciliation endpoints.
- Webhook signature/replay contract.
- Rate limits.

## Security

- No production access.
- No production migration.
- No external authenticated requests.
- No emission.
- No token exposure.
- No Flutter changes.
- No sales, NCF, ITBIS, cash, inventory, offline or sync changes.
- No public endpoint for document emission.

## UAT manual guide

Manual UAT is not executed in this report. Recommended steps:

1. Start isolated PostgreSQL UAT.
2. Verify database identity and port.
3. Create a UAT backup and confirm non-zero size.
4. Apply migration `20261014143000_add_ecf_document_idempotency`.
5. Run Prisma validate and e-CF Jest suite.
6. Create synthetic company/users only.
7. Prepare local e-CF document through service-level tests.
8. Verify company isolation, unique idempotency and status logs.
9. Confirm no Alanube/DGII network traffic.

## GO / NO-GO

- GO for local development and migration rehearsal.
- NO-GO for real authentication until a dedicated, explicitly authorized
  Sandbox auth phase.
- NO-GO for emission.
- NO-GO for production.
