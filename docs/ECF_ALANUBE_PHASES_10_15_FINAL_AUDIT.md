# ECF Alanube phases 10-15 final audit

Date: 2026-10-14.

## Initial state

- Worktree: `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE`.
- Branch: `feature/ecf-alanube`.
- Reference HEAD: `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.
- Alanube token: stored locally through DPAPI and resolvable by `env://ALANUBE_SANDBOX_TOKEN`.
- Alanube authentication: `NOT_TESTED`.
- Emission: `BLOCKED`.
- Traditional POS: not modified.

## Phase 10 - contracts

Implemented:

- Public contract matrix for Alanube DOM endpoints:
  - E31: `POST /fiscal-invoices`.
  - E32: `POST /invoices`.
  - E34: `POST /credit-notes`.
- Authentication contract recorded as JWT Bearer token in `Authorization`.
- Sandbox base URL recorded as `https://sandbox.alanube.co/dom/v1`.
- Production base URL documented only; not enabled.

Blocked:

- Full OpenAPI/JSON Schema was not available in this session.
- Exact response schemas, error schemas, idempotency support, rate limits,
  webhooks and document query contracts remain `BLOCKED_PENDING_SCHEMA`.

## Phase 11 - safe HTTP client

Implemented:

- `AlanubeSafeHttpClient`.
- Injectable transport interface.
- Simulated transport for tests.
- Sandbox URL validation.
- Production/runtime blocking.
- Authorization header redaction in simulated call logs.
- No public emission endpoint.
- No real network transport implementation.

Safety:

- Real calls remain blocked by default.
- Emission remains blocked independently from HTTP configuration.
- Token is resolved only internally and never returned.

## Phase 12 - persistence and idempotency

Implemented:

- Additive Prisma models for electronic documents:
  - `EcfElectronicDocument`.
  - `EcfElectronicDocumentAttempt`.
  - `EcfElectronicDocumentStatusLog`.
- Explicit statuses distinguishing local preparation, provider result, DGII
  result, unknown result, rejection and human review.
- Unique idempotency key by company.
- Unique payload fingerprint by company.
- Local document preparation service with transaction, attempt log and status
  history.

Migration:

- Created: `20261014143000_add_ecf_document_idempotency`.
- Applied: no.

## Phase 13 - DGII certification assistant

Implemented:

- Certification catalog with automation classification:
  - `MANUAL_REQUIRED`.
  - `PROVIDER_DEPENDENT`.
  - `DGII_DEPENDENT`.
  - `UNKNOWN`.
- Evidence and production-blocking flags per critical step.

Safety:

- No action is performed against DGII.
- No step declares official authorization without evidence.
- Existing onboarding is reused conceptually; no duplicate public flow added.

## Phase 14 - sales integration preparation

Implemented:

- Pure adapter from stable sale snapshot to internal `EcfFiscalDocument`.
- No import from sales services/controllers.
- No changes to sale creation, NCF, ITBIS, inventory, cash, printing or offline.

## Phase 15 - validation

Executed:

- e-CF Jest focused suite.
- Prisma schema validation.
- API build.
- Git inspection.

Not executed:

- UAT migration apply, because this session did not run the required backup and
  isolated container write checklist.
- Real Alanube authentication.
- Any fiscal emission.

## Security findings

- No production access.
- No authenticated external calls.
- No token printed.
- No token stored in PostgreSQL.
- No Flutter/POS traditional changes.
- `taxEnabled` and `ncfEnabled` untouched.
- Empresas sin e-CF remain unaffected by these backend-only additions.

## Risks

Critical:

- Do not emit until Alanube schemas, idempotency behavior and DGII workflow are
  verified in real Sandbox.

High:

- Migration must be applied only after UAT backup and isolation checks.
- Real HTTP transport must not be enabled without audited retry/idempotency
  policy and response parsing.

Medium:

- Contract matrix is partial because full official schemas were unavailable.
- Windows Credential Manager direct resolution remains unsupported; current
  working path is DPAPI local file loaded into process env.

Low:

- Tests cover local behavior and simulated transport, not provider behavior.

## GO / NO-GO

- GO for continued local development and UAT migration rehearsal.
- NO-GO for real authentication until the next phase explicitly enables one
  controlled Sandbox auth check.
- NO-GO for emission.
- NO-GO for production.
