# FullPOS Cloud - First Alanube Sandbox Issuance Plan

## Latest live-read checkpoint

One explicitly authorized Sandbox GET /company completed, HTTP 200, no POST.
RNC 132109122 is the token's main company, id 01M3T6Y4R9BH35XGJ5PP12KV0T.
Observed name FULLTECH/address address conflict with the expected identity and
meaningful address. Manifest records TOKEN_PRIMARY and observed name, preserves
RNC, omits company.id and leaves address null. BLOCKED until portal/support
clarifies the test profile and operator completes valid ADMIN UAT login. Local
login requires POST /auth/login; not executed under current no-POST condition.
Do not repeat GET under the consumed authorization or dispatch any invoice.
Current evidence and operator steps are in readiness/runbook. 35 E32 tests PASS.

## Latest E32 checkpoint following official-package clarification

User confirms official Sandbox RNC/range/expiry/token delivery. Do not request
production certification or repeat package authorization. Candidate format:
E320009805001, not dispatched/reserved. BLOCKED operationally on missing UAT
ADMIN JWT and sender name/address plus explicit primary/associated company
selection. Primary uses no company.id and GET /invoices/{id}; associated uses
verified ULID and company-scoped GET. Both are implemented/tested. Missing RNC
in response is permitted; contradictory RNC is rejected, fiscal state unknown.
35 focused / 88 PostgreSQL / 975 backend tests, build and Prisma PASS.
See current ECF_ALANUBE_E32_SANDBOX_READINESS.md and E32 runbook. No POST until
complete preflight, exact payload/hash review and user's separate explicit consent.

## Earlier checkpoint (historical where superseded)

## Current first E32 candidate checkpoint

BLOCKED on verified Sandbox company/identity and complete authorized E32 number,
then authenticated UAT operator/config and explicit per-manifest consent. Local
numeric profile is not authorization (user confirmed). Do not invent an e-NCF.
The E32-only CLI, single-use durable latch, dedicated wire, first-response binding,
official company-scoped GET validation and quarantine are implemented/tested.
31 E32 local, 232 e-CF, 87 PostgreSQL and 971 backend tests PASS.

E34 balance rules, public webhook authentication and production certification do
not gate this bounded E32 trial. No fiscal acceptance is inferred from HTTP/schema.
The general API transport remains blocked; the dedicated child-process command
requires separate consent and cannot issue twice, even after timeout/restart.
Read ECF_ALANUBE_E32_SANDBOX_READINESS.md and ECF_ALANUBE_FIRST_E32_SANDBOX_RUNBOOK.md.
All older checkpoints below are historical; none authorizes emission.

## Latest checkpoint — phases 91–100

NO-GO. Internal evidence quarantine is implemented and tested (201 e-CF,
68 PostgreSQL, 940 backend). Hash/schema/remote id do not establish authenticity
or DGII acceptance. Production verifier is blocked. TEST_ONLY remains synthetic.
Receipts cannot update fiscal status/snapshot/logs or release E34 reservations.
Remote reconciliation, public webhook and all fiscal POST remain blocked.

Before any future sender: obtain official authenticity/query/webhook guarantees,
verify fiscal semantics/E34 rules, design authenticated first-response identity
binding and artifact custody/retention, authorize endpoint/operations, and review
transactional orchestration. Existing receipts freeze correlated identifiers;
do not bypass them to assign a first remote id. No flags alone enable issuance.
See ECF_ALANUBE_PROVIDER_BLOCKERS.md and ECF_ALANUBE_EVIDENCE_TRUST_MATRIX.md.

Date: 2026-10-14.

This plan prepares a future first Sandbox issuance. It does not authorize or
execute emission.

## Update after phases 81–90 (current)

E34 now has a tenant-scoped local credit ledger, immutable fiscal evidence
snapshot, matching evidence history, conservative original validation and
transactional monetary reservations. Available balance subtracts applied,
reserved and unknown amounts. Unknown results do not expire or release money.
Definitive application/rejection needs matching fiscal evidence; tests use
explicitly fictitious UAT records, never evidence of actual DGII acceptance.

Two versioned migrations were applied only in isolated UAT after verified backups.
Composite tenant foreign keys and per-company e-NCF uniqueness protect original
identity. Service locks and PostgreSQL triggers prevent over-reservation even
for concurrent direct inserts. Histories cannot be edited/deleted; synthetic UAT
fixtures are retained rather than adding a deletion bypass. No fiscal sequence
was allocated, reserved or consumed: the reservations are monetary only.

E34 issuance has an additional unconditional pre-emission block until official
evidence ingestion, conditional fiscal semantics and sender/reconciliation
orchestration are verified. A claimed complete mapping cannot bypass this.
No external call, company registration, emission or production operation occurred.

Local checks: 180 e-CF tests, 40 PostgreSQL tests, 919 backend tests PASS;
build/tsc/Prisma validate/status and diff check PASS. This does not authorize any
first Sandbox attempt. See the 81–90 audit for backups, limitations and next work.

## Update after phases 71–80 (supersedes older implementation notes)

E31/E32/E34 now map the supported DOP subset to documented names and validate
against pinned public OpenAPI 3.0.3 request schemas via Ajv. Fiscal metadata is
explicit; no sequence is allocated or consumed. Required metadata is never
invented. Requests without it remain blocked. Responses are schema-checked by
type/status before safe processing observations; none creates fiscal acceptance.

The mapper, metadata DTO and schema checks resolve the earlier structural gaps
for the tested subset. They do not prove conditional legal validity, actual
provider acceptance, a credit note's original-document balance, or certification.
See the phase71–74 field matrix for unsupported/conditional fields.

The guard now additionally requires authenticated/document company agreement,
company RNC and explicit provider company.id matching trusted tenant configuration,
permission, explicit authorization, Sandbox, certification, state,
stable operation key, matching internal and payload fingerprints, current payload
validation and fully approved registry. Registry remains partial. Future sender
must persist and obtain this evidence internally, never from client assertions.
POST remains disabled in the safe client and real transport, regardless of flags.

Local evidence: 161 e-CF tests, 12 PostgreSQL tests, 900 backend tests PASS;
build/Prisma/tsc and compiled-code smoke PASS. No new migrations in 71–80.
No authenticated Alanube requests, DGII requests or fiscal emission occurred.

Next prerequisites: verify original E34 evidence/remaining balance and complete
conditional semantics; confirm DOM idempotency, response variants, reconciliation,
webhook authenticity, rates, reseller and Sandbox numbering with provider.
Any future single fictitious Sandbox emission still needs specific authorization
and a separately reviewed sender. This task did not authorize that operation.

## Update after phases 61–70 (2026-10-14)

- Stable v2 operation identities now separate operation from content; same-key
  divergent payload conflicts, independent identical operations coexist.
- Migration `20261014160000_ecf_stable_operation_identity` applied only to local
  Alanube UAT after verified backup. PostgreSQL tests cover concurrency and
  legacy-key conversion/conflict rollback. Production was not migrated.
- Public E31/E32/E34 OpenAPI snapshots were recovered from embedded public
  documentation, with hashes in `ECF_ALANUBE_CONTRACT_RESEARCH_PHASE65.md`.
  The historical statement below that schemas were unavailable is superseded.
- Local mapper remains a draft: confirmed official required metadata is missing.
  Presence validation is not complete schema or fiscal/legal validation.
- Fiscal POSTs are blocked in both safe client and real transport. Emission
  retries remain blocked even if local idempotence is asserted.
- Unknown outcomes persist atomically with history and never reset on replay.
- HTTP 2xx alone is classified as unknown, not provider or DGII acceptance.
- GET status endpoints are publicly confirmed; reconciliation remains disconnected.
- Provider DOM idempotency, webhook authenticity/replay, rate limits, reseller,
  client activation and Sandbox numbering remain pending provider confirmation.

Before a future attempt, implement and test full request/response conformance
against the recovered official schemas, resolve provider questions, review the
eventual sender separately, then obtain specific authorization for one emission.
Existing flags alone cannot enable the now-blocked POST path.
The historical checklist below is planning context, not executable authorization.

## Current verdict

NO-GO for real Sandbox issuance today.

Reasons:

- Alanube request/response schemas are still partial.
- Provider idempotency contract is not confirmed.
- Query/reconciliation endpoints are not fully verified.
- Webhook authenticity contract is missing.
- `(companyId, payloadFingerprint)` may block legitimate identical independent
  sales and requires a migration plan before emission.
- Emission kill switches are intentionally disabled.

## Prerequisites

1. Obtain complete official Alanube OpenAPI/JSON Schema or equivalent contract
   for E31/E32/E34.
2. Confirm whether Alanube supports idempotency keys or request identifiers.
3. Confirm response fields for accepted, rejected, pending and unknown outcomes.
4. Confirm document query/status endpoints and interpretation.
5. Confirm webhook signature/authenticity rules, if webhooks are used.
6. Verify the test company/RNC and sequence range are valid for Sandbox only.
7. Keep production disabled.
8. Keep `taxEnabled` and `ncfEnabled` unchanged.
9. Create a fresh UAT backup before any schema migration.
10. Relax payload fingerprint uniqueness safely if required.

## Recommended first document

Recommended type: E31 fiscal credit invoice, only after full schema
confirmation.

Reason:

- It exercises identified buyer, ITBIS, totals and fiscal receiver data.
- It is stricter than E32 and therefore better for contract validation.

Use fully fictitious Sandbox data only.

## Required switches for the future run

All must be explicit and temporary:

- `ALANUBE_ENV=sandbox`
- `ALANUBE_HTTP_TRANSPORT_ENABLED=true`
- `ALANUBE_ENABLE_REAL_CALLS=true`
- future emission flag enabled only for the selected test company
- company e-CF enabled
- company certification status set only with evidence
- contract registry status promoted only after official schema confirmation

No single variable may enable emission by itself.

## Execution procedure for future phase

1. Verify worktree, branch, HEAD and git status.
2. Verify UAT database host/port/name/container.
3. Create and verify UAT backup.
4. Run Prisma validate and ECF tests.
5. Use one synthetic company only.
6. Build immutable fiscal snapshot.
7. Validate fiscal document locally.
8. Validate Alanube payload against official schema.
9. Create local electronic document with idempotency key.
10. Confirm state is `READY_TO_SEND`.
11. Execute exactly one emission request.
12. Persist request fingerprint, provider correlation id, status and safe result.
13. Do not log token, payload body or sensitive response content.
14. If timeout occurs, mark `UNKNOWN_RESULT` and stop emission.
15. Reconcile using official query endpoint before retrying.
16. Save evidence references only, not raw secrets or complete sensitive payloads.

## Timeout and unknown outcome

If the provider request times out or returns an ambiguous response:

- Do not retry emission automatically.
- Mark local document as `UNKNOWN_RESULT`.
- Block further sends for the same idempotency key.
- Attempt read-only reconciliation only with official endpoint.
- Escalate to human review if reconciliation is unavailable.

## Suspension criteria

Stop immediately if:

- Any response suggests production environment.
- Any token or Authorization header appears in logs.
- Any payload is sent to an unexpected host.
- Any status cannot be interpreted safely.
- Duplicate document risk appears.
- UAT database identity is uncertain.
- Contract schema mismatch appears.
- Alanube returns an authentication/authorization error.

## Evidence to retain

- UAT backup path and size.
- Git HEAD and diff summary.
- Test results.
- Request id/correlation id.
- Document idempotency key.
- Payload fingerprint.
- Provider safe status.
- Redacted audit row.
- Reconciliation result.

## Final GO criteria

Future Sandbox emission can proceed only when:

- Complete official contract is verified.
- Migration/idempotency issue is resolved.
- Pre-emission barrier passes.
- Emission switches are enabled only for one test company.
- UAT backup exists and is verified.
- Tests pass.
- Operator explicitly authorizes the single Sandbox emission attempt.

Until then, status remains NO-GO.
