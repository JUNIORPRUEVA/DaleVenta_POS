# FullPOS Cloud - ECF Alanube Phases 33-60 Final Audit

Date: 2026-10-14.

Worktree: `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE`.

Branch: `feature/ecf-alanube`.

HEAD: `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.

## Safety result

- Production touched: NO.
- Deploy/push/merge/commit: NO.
- New authenticated Alanube calls: NO.
- DGII calls: NO.
- Fiscal emission: NO.
- Sandbox document emission: NO.
- Token exposed: NO.
- POS traditional modified: NO.
- Flutter modified: NO.
- Offline/Mayoreo/main touched: NO.

## AGENTS.md update

The phase-continuity rule was changed only to permit autonomous multi-phase work
when the user expressly requests it. Safety, production, migration, data,
secret, tenant, test, and fiscal restrictions remain in force.

## Architecture final

```text
EcfController
  -> EcfService
    -> PrismaService
    -> EcfSecretReferenceService
  -> EcfAlanubeClient

AlanubeSafeHttpClient
  -> EcfSecretResolverService
  -> ALANUBE_HTTP_TRANSPORT
      -> AlanubeSimulatedTransport by default
      -> AlanubeRealHttpTransport only when:
         ALANUBE_HTTP_TRANSPORT_ENABLED=true
         ALANUBE_ENABLE_REAL_CALLS=true
         ALANUBE_ENV=sandbox

Fiscal core
  -> validateEcfDocument
  -> mapEcfToAlanubeDom
  -> ECF_ALANUBE_CONTRACT_REGISTRY
  -> pre-emission guard

Documents
  -> EcfDocumentIdempotencyService
  -> Ecf document state machine
  -> retry, queue, reconciliation, webhook, error and audit policies
```

## Phase table

| Phase | Status | Implementation | Tests | Blockers / risk |
| --- | --- | --- | --- | --- |
| 33 Transport HTTP NestJS | PASS | Added DI token/factory for Alanube transport. Real transport wired but blocked by default. | `alanube-transport.provider.spec.ts` | Real calls still disabled. |
| 34 Kill switches | PASS | Added independent fail-closed policy for environment, transport, real calls, diagnostics, emission, company, certification, permission and contract. | `ecf-kill-switch.policy.spec.ts` | Must be integrated into future emission worker before use. |
| 35 Backend diagnostic | PARTIAL | Provider status is now tenant-aware and uses authenticated user context. | ECF tests/build | No real diagnostic endpoint added; external calls remain blocked. |
| 36 Request audit | PASS | Added provider audit sanitizer for correlation/result/error metadata without payloads or secrets. | `ecf-provider-audit.service.spec.ts` | Persistence hook should be added when send/query flows exist. |
| 37 Alanube contracts | PARTIAL | Public docs verified for HTTPS REST, JWT/Bearer, Sandbox URL, E31/E32/E34 endpoints and core item fields. | Contract registry tests | Complete OpenAPI/JSON Schema, response schemas, webhooks, idempotency still pending. |
| 38 Contract versioning | PASS | Added `ECF_ALANUBE_CONTRACT_REGISTRY` with source/version/status/pending fields. Emission remains blocked while status is partial. | `ecf-contract-registry.spec.ts` | No contract marked ready for emission. |
| 39 Fiscal validation | PARTIAL | Existing validation covers E31/E32/E34 basics, ITBIS, exentos, discounts, totals, references. | Existing fiscal tests | Exact DGII/Alanube conditional rules pending official schema. |
| 40 Alanube serialization | PARTIAL | Mapper separates internal DTO from Alanube payload and keeps metadata out. | Existing mapper tests | Payload remains `BLOCKED_PENDING_SCHEMA`. |
| 41 Pre-emission barrier | PASS | Added `assertEcfPreEmissionReady`. Blocks emission unless company, certification, state, idempotency and approved contract are valid. | `ecf-pre-emission.guard.spec.ts` | Not connected to a sender because sender is not enabled. |
| 42 Document states | PASS | Existing state machine blocks invalid transitions and requires evidence for accepted/rejected states. | Existing state-machine tests | Future send worker must call it on every transition. |
| 43 Idempotency | PARTIAL | Existing key uses company/type/source/fingerprint. Audit flags `(companyId,payloadFingerprint)` as too strict for identical independent sales. | Existing idempotency tests | Migration required before emission to relax unique fingerprint safely. |
| 44 Persistence | PARTIAL | Existing transactions create document, attempt, status log atomically. | Existing tests + UAT verify | No new migration created; fingerprint index remains pending. |
| 45 Error engine | PASS | Added Alanube error classifier for auth, authorization, validation, timeout, network, rate limit, provider and unknown outcome. | `alanube-error-classifier.spec.ts` | Provider-specific response codes pending official schema. |
| 46 Retries | PASS | Added retry policy that blocks non-idempotent emission retries and retries safe transient operations with bounded attempts. | `alanube-retry.policy.spec.ts` | Not wired to workers because emission workers are disabled. |
| 47 Reconciliation | PARTIAL | Existing reconciliation service remains mock/policy level. | Existing reconciliation tests | Official query endpoints and response schema pending. |
| 48 Webhooks | PARTIAL | Existing webhook contract placeholder blocks pending official signature contract. | Existing webhook tests | No public receiver exposed. Signature algorithm pending. |
| 49 Queue | PASS | Added queue policy that refuses enqueue while emission is disabled or pre-emission fails. | `ecf-processing-queue.policy.spec.ts` | No worker enabled. |
| 50 Recovery | PARTIAL | Retry/error/idempotency/state policies cover timeout, unknown outcome and duplicates conceptually. | Unit tests | Full crash/restart simulations require future worker and DB test harness. |
| 51 DGII onboarding | PARTIAL | Existing certification catalog distinguishes manual/provider/DGII steps and evidence. | Existing DGII catalog tests | No DGII official process automation performed. |
| 52 Reseller | BLOCKED | No registration, payments or legal acceptance performed. | N/A | Alanube reseller onboarding details require provider/legal confirmation. |
| 53 POS adapter | PARTIAL | Existing pure sale snapshot adapter remains isolated and not connected to `sales.create`. | Existing adapter tests | No POS flow connection by design. |
| 54 Multiempresa | PASS | `/ecf/provider/status` now uses authenticated tenant context and company config. | ECF tests/build | Future diagnostics must keep this tenant boundary. |
| 55 Offline | PARTIAL | Offline untouched. Policy remains: no electronic emission offline without legal/technical evidence. | N/A | Offline emission requirements pending official evidence. |
| 56 Security | PASS | JWT/role guards remain, tenant context used, secrets redacted, SSRF URL restrictions remain in real transport. | ECF tests/build/secret scan | Rate limiting for future emission endpoints pending. |
| 57 Observability | PASS | Added tenant-scoped metric descriptor helper. | Build | No metrics exporter wired yet. |
| 58 UAT PostgreSQL | PASS | Isolated UAT verification executed against `127.0.0.1:56550/fullpos_alanube_uat`. | `scripts/isolated-uat/verify.ps1` PASS | No new migrations applied. |
| 59 Regression | PASS | ECF Jest, Prisma validate, API build, diff check and secret scan executed. | 25 suites / 81 tests PASS | Flutter not tested because no Flutter changes. |
| 60 Final audit/plan | PASS | This report and first Sandbox issuance plan were created. | Docs reviewed by build-independent checks | Emission remains NO-GO. |

## Official contracts confirmed

Public Alanube documentation confirms:

- API communicates over HTTPS REST.
- Sandbox base URL is `https://sandbox.alanube.co/dom/v1`.
- JWT/Bearer token is required for API tests.
- E31 endpoint: `POST /fiscal-invoices`.
- E32 endpoint: `POST /invoices`.
- E34 endpoint: `POST /credit-notes`.
- `GET /company` is a read-only company information endpoint.
- E31/E32/E34 require `idDoc`, `sender`, `totals`, and `itemDetails`; E31 also
  requires `buyer`.
- `itemDetails` includes confirmed fields such as `lineNumber`,
  `billingIndicator`, `itemName`, `goodServiceIndicator`, `quantityItem`,
  `unitPriceItem`, and `itemAmount`.

Sources:

- https://developer.alanube.co/docs/getting-started
- https://developer.alanube.co/reference/createinvoicefiscals
- https://developer.alanube.co/reference/createinvoices
- https://developer.alanube.co/reference/createcreditnotes
- https://developer.alanube.co/docs/autenticaci%C3%B3n
- https://developer.alanube.co/reference/getcompany-1

## Contracts pending

- Complete request JSON schema for every nested object.
- Success response schema.
- Error response schema and provider-specific codes.
- Idempotency header/key support from Alanube, if any.
- Query/reconciliation endpoints for all document types.
- Webhook authenticity/signature contract.
- Rate limits.
- Reseller/company onboarding contract.
- DGII certification automation boundaries.

## UAT

Verified:

```text
DATABASE: fullpos_alanube_uat
DATABASE_HOST: 127.0.0.1
DATABASE_PORT: 56550
CONTAINER: fullpos_alanube_uat_postgres
ALANUBE: SANDBOX CONFIGURED, REAL CALLS DISABLED
PRODUCTION: NOT CONNECTED
```

Controlled write/read probe passed.

No new migration was created or applied in phases 33-60.

## Token

- Token storage remains local and private.
- Token was not read, printed, logged, copied to docs, or sent externally.
- Phase 31 authentication remains the latest real Alanube call.
- No new authenticated Alanube call was made.

## Transport

- Real transport exists.
- Real transport is now injectable through DI.
- Default transport remains simulated.
- Real transport requires all three switches:
  - `ALANUBE_HTTP_TRANSPORT_ENABLED=true`
  - `ALANUBE_ENABLE_REAL_CALLS=true`
  - `ALANUBE_ENV=sandbox`
- No controller or worker emits documents.

## POS traditional

No changes were made to:

- sales
- traditional NCF
- ITBIS
- cash
- shifts
- inventory
- purchases
- quotes
- printing
- offline
- sync
- licenses
- Flutter

## GO / NO-GO

GO:

- Continue local hardening.
- Prepare a controlled first Sandbox emission dry-run using mocks only.
- Prepare a migration plan to relax payload fingerprint uniqueness.
- Request/obtain complete Alanube contract schemas.

NO-GO:

- First real Sandbox emission.
- Production enablement.
- DGII submission.
- Company registration.
- Offline electronic emission.
- Public webhook receiver.
