# E-CF fiscal core - Phase 6

Consulted on 2026-10-14:

- https://developer.alanube.co/docs/getting-started
- https://developer.alanube.co/reference/createinvoicefiscals
- https://developer.alanube.co/reference/createinvoices
- https://developer.alanube.co/reference/createcreditnotes
- https://developer.alanube.co/reference/checkinvoicefiscals
- https://developer.alanube.co/reference/checkinvoices
- https://developer.alanube.co/reference/checkcreditnotes
- https://dgii.gov.do/

## Architecture

The local fiscal core lives under `apps/api/src/ecf/fiscal-core`.
It is pure TypeScript and has no HTTP, database, Flutter, sale-service, queue,
credential, or Alanube client dependency.

Implemented parts:

- Internal fiscal document model for E31, E32 and E34.
- Decimal money helpers using Prisma Decimal with 2-decimal ROUND_HALF_UP policy.
- Structured validation errors.
- Draft Alanube DOM mapper for confirmed top-level sections and confirmed line fields.
- Local fixtures for valid and invalid cases.

## Confirmed Alanube DOM contracts

- E31 emission endpoint: `POST /fiscal-invoices`.
- E32 emission endpoint: `POST /invoices`.
- E34 emission endpoint: `POST /credit-notes`.
- Status endpoints exist for each type using `GET /{resource}/{id}`.
- E31 requires `idDoc`, `sender`, `buyer`, `totals`, and `itemDetails`.
- E32 requires `idDoc`, `sender`, `totals`, and `itemDetails`; buyer is required
  when total is greater than or equal to DOP 250,000.
- E34 requires `idDoc`, `sender`, `totals`, `itemDetails`, and
  `informationReference`.
- Confirmed item fields include `lineNumber`, `billingIndicator`, `itemName`,
  `goodServiceIndicator`, `quantityItem`, `unitPriceItem`, `discountAmount`,
  and `itemAmount`.

## Limitations

Alanube documentation visible in this environment did not expose every nested
property for `idDoc`, `sender`, `buyer`, and main `totals`. Therefore the mapper
marks payloads as `DRAFT_LOCAL_ONLY`. It is intentionally not declared ready for
real Alanube contract tests.

No e-NCF generation, no DGII request, no Alanube request, no document persistence,
no sale integration, no offline integration, and no Flutter UI changes exist in
this phase.

## Security

- No external HTTP transport is implemented.
- `EcfAlanubeClient` remains passive and exposes only safe runtime state.
- No credentials or tokens are read, logged, returned, or stored by this core.
- e-CF remains optional per company; traditional POS behavior is untouched.

## Future work

- Confirm complete Alanube OpenAPI schema for DOM E31/E32/E34.
- Add contract tests against Sandbox only after secure credential resolution.
- Persist document lifecycle/idempotency only after migration review.
- Integrate sale-to-fiscal mapping after proving fiscal compatibility.
- Add certified numbering/e-NCF controls only with DGII/Alanube evidence.
