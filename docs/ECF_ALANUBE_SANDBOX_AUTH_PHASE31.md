# ECF Alanube Sandbox auth - Phase 31

Date: 2026-10-14.

## Objective

Perform one authenticated, read-only Alanube Sandbox diagnostic request if and
only if an official safe endpoint is available.

## Official documentation used

- Authentication docs: `Authorization: Bearer <token>` over HTTPS.
- Official endpoint: `GET https://sandbox.alanube.co/dom/v1/company`.
- Endpoint purpose: consult company information associated with the token.

## Selected endpoint

```text
GET https://sandbox.alanube.co/dom/v1/company
```

Justification:

- Official Alanube DOM endpoint.
- Sandbox URL.
- GET method.
- No invoice creation.
- No credit note creation.
- No company registration.
- No fiscal document emission.
- No request body.
- Uses Bearer token and can reasonably validate authentication.

## Ephemeral authorization

The diagnostic script:

```text
scripts/isolated-uat/test-alanube-sandbox-auth.ps1
```

allows exactly:

- Method: `GET`.
- Host: `sandbox.alanube.co`.
- Path: `/dom/v1/company`.
- One authenticated request.

Global flags remain blocked:

- `ALANUBE_ENABLE_REAL_CALLS=false`.
- `ECF_EMISSION_ENABLED=false`.
- `ECF_ALANUBE_AUTH_TESTS_ENABLED=false`.

## Result

Executed once on 2026-10-14.

```text
ENVIRONMENT: SANDBOX
METHOD: GET
PATH: /dom/v1/company
HTTP_STATUS: 200
CLASSIFICATION: AUTH_CONFIRMED
REQUEST_COUNT: 1
TOKEN_EXPOSED: NO
DOCUMENTS_EMITTED: 0
DATA_MODIFIED: 0
ALANUBE_AUTHENTICATION: AUTH_CONFIRMED
```

Interpretation:

- Alanube Sandbox accepted the configured token for the documented company
  information endpoint.
- No fiscal document endpoint was called.
- No request body was sent.
- The response body was not printed, stored, or committed.
- Production remained blocked.

## Safety notes

- Token is loaded from the local DPAPI encrypted file into process memory only.
- Token is not printed.
- Authorization header is not printed.
- Response body is parsed only enough to classify the result and is not stored.
- No HAR or HTTP dump is created.

## GO / NO-GO

GO to prepare the next controlled phase: Sandbox authentication wiring inside
the backend behind explicit kill switches and without document emission.

NO-GO for fiscal emission, company registration, credit notes, invoice creation,
DGII submission, or production enablement.
