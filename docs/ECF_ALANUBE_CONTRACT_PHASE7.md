# E-CF Alanube DOM contract research - Phase 7

Consulted on 2026-10-14.

## Official Sources

- Alanube Getting Started: `https://developer.alanube.co/docs/getting-started`
- Alanube E31 create: `https://developer.alanube.co/reference/createinvoicefiscals`
- Alanube E32 create: `https://developer.alanube.co/reference/createinvoices`
- Alanube E34 create: `https://developer.alanube.co/reference/createcreditnotes`
- Alanube E31 status: `https://developer.alanube.co/reference/checkinvoicefiscals`
- Alanube E32 status: `https://developer.alanube.co/reference/checkinvoices`
- Alanube E34 status: `https://developer.alanube.co/reference/checkcreditnotes`
- DGII portal: `https://dgii.gov.do/`

`llms.txt` and `.md` page variants were advertised by Alanube but were not
accessible through the available tools in this session. No authenticated docs,
tokens, Sandbox emissions, or DGII requests were used.

## Contract Summary

| Doc | Endpoint | Public evidence | Status |
| --- | --- | --- | --- |
| E31 | `POST /fiscal-invoices` | Alanube page lists body params and item schema | PARTIAL |
| E32 | `POST /invoices` | Alanube page lists body params, item schema, and 250,000 DOP behavior | PARTIAL |
| E34 | `POST /credit-notes` | Alanube page lists body params and item schema | PARTIAL |

## E31 Field Matrix

| JSON path | Type | Required | Rule | Internal field | Status |
| --- | --- | --- | --- | --- | --- |
| `idDoc` | object | yes | DGII `IdDoc` | `type`, `issueDate` candidate | PARTIAL |
| `sender` | object | yes | DGII `Emisor` | `sender` | PARTIAL |
| `buyer` | object | yes | DGII `Comprador` | `buyer` | CONFIRMED |
| `totals` | object | yes | DGII `Totales` | `totals` | PARTIAL |
| `itemDetails` | array | yes | 1..1000 | `lines` | CONFIRMED |
| `itemDetails[].lineNumber` | integer | yes | line number | `lineNumber` | CONFIRMED |
| `itemDetails[].billingIndicator` | integer enum | yes | 0,1,2,3,4 | `taxCategory` | CONFIRMED |
| `itemDetails[].itemName` | string | yes | length <= 80 | `name` | CONFIRMED |
| `itemDetails[].goodServiceIndicator` | integer enum | yes | 1 good, 2 service | `goodServiceIndicator` | CONFIRMED |
| `itemDetails[].itemDescription` | string | no | length <= 1000 | `description` | CONFIRMED |
| `itemDetails[].quantityItem` | number | yes | > 0 by local policy | `quantity` | CONFIRMED |
| `itemDetails[].unitMeasure` | integer | no | 1..62 when provided | pending | CONFIRMED/PENDING |
| `itemDetails[].unitPriceItem` | number | yes | non-negative | `unitPrice` | CONFIRMED |
| `itemDetails[].discountAmount` | number | conditional | when line discount exists | `discountAmount` | CONFIRMED |
| `itemDetails[].itemAmount` | number | yes | unit * qty - discount + surcharge | derived | CONFIRMED |

## E32 Field Matrix

E32 shares the confirmed line fields above. Differences confirmed publicly:

| JSON path | Type | Required | Rule | Internal field | Status |
| --- | --- | --- | --- | --- | --- |
| `buyer` | object | conditional | required when total >= DOP 250,000 | `buyer` | CONFIRMED |
| `itemDetails` | array | yes | up to 10,000 if total < 250,000; up to 1,000 if >= 250,000 | `lines` | CONFIRMED |
| response mode | response | n/a | synchronous below 250,000; asynchronous at/above 250,000 | future state model | CONFIRMED |

## E34 Field Matrix

E34 shares the confirmed line fields above.

| JSON path | Type | Required | Rule | Internal field | Status |
| --- | --- | --- | --- | --- | --- |
| `informationReference` | object | yes | reference information for credit note | `reference` | CONFIRMED |
| `buyer` | object | no/partial | page lists buyer object but not as required | `buyer` | PARTIAL |
| `itemDetails` | array | yes | 1..1000 | `lines` | CONFIRMED |

Nested fields inside `informationReference` were not fully visible as a public
schema in this session; current local names remain draft.

## Implemented Changes

- Added `alanube-dom.contract.ts` with typed partial contracts for confirmed
  public fields.
- Removed non-contract `config.fullposContractStatus` from the Alanube payload.
- Moved contract state to mapper metadata: `contractStatus`,
  `confirmedFields`, `pendingFields`, and `warnings`.
- Added local draft contract validation for required top-level objects,
  documented item enums, item limits, E31 buyer, and E34 reference.
- Kept mapper status as `BLOCKED_PENDING_SCHEMA`; no real compatibility claim is made.

## Responses and Errors

Confirmed publicly for E32:

- Below DOP 250,000, Alanube may answer synchronously.
- At or above DOP 250,000, Alanube indicates asynchronous DGII handling.
- If DGII communication fails during a synchronous response, Alanube may schedule
  automatic transmission and return a `response` array containing `message` and
  `code`.

Complete success, rejection, and validation response schemas remain pending.

## Limitations

- Public docs did not expose a complete OpenAPI/Swagger file through available tools.
- `.md` and `llms.txt` were inaccessible in this session.
- Header/totals/reference nested field names remain PARTIAL unless explicitly
  visible on the public HTML page.
- No HTTP transport was implemented.
- No fixtures were copied from authenticated examples.

## Next Phase

Before Sandbox transport, obtain a complete public or vendor-provided OpenAPI
schema or official sample payloads for E31, E32 and E34. Then replace draft
header/totals/reference mappings with schema-verified names and add schema tests.
