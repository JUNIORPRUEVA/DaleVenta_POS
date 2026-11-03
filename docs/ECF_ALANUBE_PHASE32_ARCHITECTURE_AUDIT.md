# FullPOS Cloud - ECF Alanube Phase 32 Architecture Audit

Date: 2026-10-14.

Scope: local audit of the ECF module in
`C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE`.

Branch verified: `feature/ecf-alanube`.

HEAD verified: `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.

## Execution boundary

The request asked to execute phases 32 through 60 in one session. Repository
policy requires phased work to stop after the current phase and report before
advancing. This document completes Phase 32 only.

No production, main, offline, Mayoreo, Flutter, sales, NCF, ITBIS, cash,
inventory, sync, deploy, push, merge, commit, migration, Alanube request, DGII
request, or fiscal emission was performed in this phase.

## Entry points

Verified files:

- `apps/api/src/app.module.ts` imports `EcfModule`.
- `apps/api/src/ecf/ecf.module.ts` registers `EcfController`, `EcfService`,
  `EcfSecretReferenceService`, `EcfSecretResolverService`, `EcfAlanubeClient`,
  `AlanubeSafeHttpClient`, `AlanubeReconciliationService`, and
  `EcfDocumentIdempotencyService`.
- `apps/api/src/ecf/ecf.controller.ts` exposes only:
  - `GET /ecf/config`
  - `PATCH /ecf/config`
  - `GET /ecf/onboarding`
  - `PATCH /ecf/onboarding/steps/:stepKey`
  - `GET /ecf/onboarding/history`
  - `GET /ecf/provider/status`

All controller methods are protected by `AuthGuard("jwt")` and `RolesGuard`.
Method-level permissions are present.

## Dependency map

```text
AppModule
  -> EcfModule
    -> EcfController
      -> EcfService
        -> PrismaService
        -> EcfSecretReferenceService
      -> EcfAlanubeClient
        -> ConfigService
    -> AlanubeSafeHttpClient
      -> ConfigService
      -> EcfSecretResolverService
      -> AlanubeSimulatedTransport by default
    -> AlanubeReconciliationService
    -> EcfDocumentIdempotencyService
      -> PrismaService

Fiscal core
  -> EcfFiscalDocument types
  -> Ecf money helpers
  -> validateEcfDocument
  -> mapEcfToAlanubeDom
  -> Alanube DOM draft contract

Documents
  -> EcfDocumentIdempotencyService
  -> Ecf document state machine
  -> Prisma EcfElectronicDocument tables

POS adapter
  -> mapSaleSnapshotToEcfDocument
  -> not connected to SalesModule

Alanube
  -> contract matrix
  -> auth diagnostic policy
  -> safe HTTP client
  -> simulated transport
  -> real HTTP transport, not injected by EcfModule
  -> response interpreter
  -> reconciliation service
  -> webhook contract placeholder

UAT scripts
  -> isolated local PostgreSQL and Alanube Sandbox configuration checks
```

## Services and components

### Connected to NestJS runtime

- `EcfController`
- `EcfService`
- `EcfSecretReferenceService`
- `EcfSecretResolverService`
- `EcfAlanubeClient`
- `AlanubeSafeHttpClient`
- `AlanubeReconciliationService`
- `EcfDocumentIdempotencyService`

### Pure/local libraries

- `fiscal-core/ecf-validator.ts`
- `fiscal-core/ecf-money.ts`
- `fiscal-core/alanube-dom.mapper.ts`
- `fiscal-core/alanube-dom.contract.ts`
- `documents/ecf-document-state-machine.ts`
- `pos/ecf-sale-adapter.ts`
- `alanube/alanube-response-interpreter.ts`
- `alanube/alanube-contract-matrix.ts`
- `alanube/alanube-webhook.contract.ts`
- `alanube/alanube-auth-diagnostic.policy.ts`

### Prepared but intentionally disconnected

- `AlanubeRealHttpTransport` exists and has tests, but is not registered in
  `EcfModule`.
- `AlanubeSafeHttpClient` defaults to `AlanubeSimulatedTransport`.
- Fiscal document preparation exists, but no controller route emits or sends an
  ECF document.
- POS sale adapter exists, but is not called by `SalesModule`.

This disconnected state is safe for Phase 32 and required before Phase 33 can
wire the real transport behind explicit kill switches.

## Prisma model audit

ECF onboarding/configuration models:

- `EcfCompanyConfiguration`
- `EcfOnboardingStep`
- `EcfCertificationAttempt`
- `EcfEvidence`
- `EcfAuditLog`

ECF document models:

- `EcfElectronicDocument`
- `EcfElectronicDocumentAttempt`
- `EcfElectronicDocumentStatusLog`

Tenant isolation fields:

- Every ECF model includes `companyId`.
- Primary runtime service methods derive `companyId` with `requireTenant(user)`.
- Queries in `EcfService` are scoped by authenticated `companyId`.
- Evidence lookup uses `findFirst({ where: { id, companyId } })`.
- Document idempotency keys are unique per `(companyId, idempotencyKey)`.

Sensitive fields:

- `credentialsSecretRef`, `certificateSecretRef`, and `webhookSecretRef` store
  references, not secret values.
- API responses expose boolean secret status only.
- Audit snapshots redact keys containing secret, token, password, and
  storageRef.

Known model risk:

- `EcfElectronicDocument` has a unique `(companyId, payloadFingerprint)`. This
  prevents duplicate payloads per company, but can also block legitimate repeated
  same-content documents if future business rules allow them. This is safe for
  pre-emission phases and should be reviewed before live emission.

## Security audit

Confirmed controls:

- `PATCH /ecf/config` blocks `EcfEnvironment.PRODUCTION`.
- DTO restricts provider to `ALANUBE` and environment to `SANDBOX`.
- `toIssuanceState()` returns `canEmit: false` and
  `productionEmissionEnabled: false`.
- `GET /ecf/provider/status` returns runtime booleans and does not expose token
  values.
- Secret resolver blocks production secret resolution unless explicitly allowed.
- Secret reference validator rejects multiline material and common token/key
  value hints.
- Auth diagnostic policy allows only Sandbox `GET /dom/v1/company`.

Risks for later phases:

- `GET /ecf/provider/status` is global runtime state, not company-specific. It
  is guarded by `viewEcfConfig` and does not expose secrets, but a future
  company-specific provider status should use authenticated tenant context.
- `AlanubeSafeHttpClient.prepareFiscalPost()` can build POST requests, but real
  calls are blocked unless `ALANUBE_ENABLE_REAL_CALLS=true`; Phase 33/34 must
  add stronger DI and independent kill switches before any controller or worker
  can use it.
- `AlanubeRealHttpTransport` uses `fetch`; it must remain unregistered until a
  safe runtime policy decides when it can be injected.

## Fiscal core audit

Confirmed:

- Supported internal types are `E31`, `E32`, and `E34`.
- Basic RNC/cedula format validation exists.
- E31 requires identified buyer.
- E32 high-value threshold requires buyer.
- E34 requires original e-NCF reference and modification reason.
- Line amounts, discounts, ITBIS, exempt amount, taxable base, subtotal, and
  total are validated locally.
- Mapper returns `contractStatus: "BLOCKED_PENDING_SCHEMA"`.

Pending:

- Exact Alanube field schema remains partial.
- Exact Alanube success/error response schemas remain pending.
- DGII certification and legal evidence rules are not automated.

## Alanube integration audit

Confirmed:

- Authentication contract is documented as Bearer token.
- Sandbox base URL is fixed as `https://sandbox.alanube.co/dom/v1`.
- Production base URL constant exists but is not used by runtime status as an
  allowed environment.
- Phase 31 confirmed one authenticated Sandbox `GET /company` diagnostic with
  `HTTP_STATUS: 200` and `AUTH_CONFIRMED`.

Blocked by design:

- No new authenticated Alanube call was made in Phase 32.
- No emission endpoint was called.
- No Alanube company registration was attempted.
- No DGII endpoint was contacted.

## Tests inventory

ECF test suites found under `apps/api/src/ecf` cover:

- controller guard and permission metadata
- company config/onboarding service behavior
- secret references and providers
- Alanube runtime status
- fiscal validation and mapping
- POS snapshot adapter
- document idempotency
- document state machine
- DGII certification catalog
- Alanube contract matrix
- auth diagnostic policy
- response interpreter
- safe HTTP client
- real HTTP transport unit behavior
- reconciliation service
- webhook contract placeholder

## Findings

### HECHO - Runtime module is isolated

`EcfModule` is imported by `AppModule`, but no route writes sales, inventory,
cash, NCF, ITBIS, Flutter, offline, or sync data.

### HECHO - Emission remains blocked

`EcfService.toIssuanceState()` returns `canEmit: false`, and the Alanube runtime
status returns `externalCallsBlocked: true`.

### HECHO - Real transport is not wired

`AlanubeRealHttpTransport` exists, but `EcfModule` does not register it and
`AlanubeSafeHttpClient` defaults to `AlanubeSimulatedTransport`.

### HECHO - Contracts are intentionally partial

`mapEcfToAlanubeDom()` returns `BLOCKED_PENDING_SCHEMA` and lists pending schema
fields. This prevents claiming emission readiness.

### HECHO - Multi-company boundaries are implemented in current endpoints

`EcfService` derives `companyId` from `requireTenant(user)` and scopes all
configuration, onboarding, evidence, and audit queries by that company.

### RIESGO - Provider status is not tenant-specific

The provider status endpoint returns process-level configuration rather than a
company-specific status. It does not expose secrets, but should be refined
before tenant-facing UI depends on it.

### RIESGO - Document fingerprint uniqueness may be too strict later

The unique `(companyId, payloadFingerprint)` constraint is strong protection
against duplicates, but may reject a legitimate repeated document with identical
content. This should be revisited before Sandbox emission.

### RIESGO - Real HTTP transport exists in source

The transport is currently disconnected. Phase 33/34 must keep it behind DI,
policy checks, and kill switches. It must not be reachable from controllers or
workers by a single environment variable.

## Phase 32 verdict

PASS for architecture audit.

GO to Phase 33 only for internal DI design and tests with mocks.

NO-GO for fiscal emission, Alanube document POSTs, DGII submission, production
configuration, Flutter integration, POS sale integration, or automatic workers.
