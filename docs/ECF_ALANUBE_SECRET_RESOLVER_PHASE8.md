# ECF Alanube secret resolver - Phase 8

## Scope

Phase 8 adds an internal secret-resolution architecture for Alanube Sandbox.
It does not add HTTP authentication, does not call Alanube or DGII, and does not
enable fiscal emission.

## Architecture

Backend code now separates:

- Secret references: safe identifiers such as `env://...`,
  `secret://windows/...`, and `secret://docker/...`.
- Secret resolution: internal service `EcfSecretResolverService`.
- Providers: concrete implementations for local environment variables,
  Docker secret files, and Windows Credential Manager availability checks.
- Public responses: no controller returns resolved secret values.

The resolver requires a context with environment and optional allowed
references. If an allow-list is supplied, a reference outside that list is
rejected before any provider is called. This is the guardrail for company-level
isolation when per-company credentials are introduced.

## Providers

### `env://NAME`

Supported for Sandbox/UAT. The resolver reads the named process environment
variable through Nest `ConfigService` or `process.env`. This is useful for local
and CI-style injection, but the environment variable itself is not a vault.
Operators must avoid printing it and must not commit it.

### `secret://docker/NAME`

Prepared for Linux/Docker. The provider reads `/run/secrets/NAME` by default, or
`ECF_DOCKER_SECRETS_DIR` when explicitly configured. Secret files must be
mounted read-only with restricted permissions. No production container or VPS
was accessed in this phase.

### `secret://windows/TARGET`

Prepared for Windows Credential Manager. The verifier can check whether the
target exists under the current Windows user with `cmdkey /list:<target>`, but
that command cannot retrieve the password. Microsoft documents `CredReadW` in
`Advapi32` as the native API for reading credentials; this repository does not
yet include a maintained native binding for it.

Therefore, Windows Credential Manager resolution is intentionally blocked with a
redacted `RESOLUTION_UNSUPPORTED` error. This avoids unsafe PowerShell bridges,
temporary files, command-line secrets, or dependencies introduced without audit.

## References

Current Sandbox reference examples:

```text
env://ALANUBE_SANDBOX_TOKEN
secret://windows/FullPOS-Alanube-SandboxToken
secret://docker/alanube_sandbox_token
```

`ALANUBE_TOKEN_SECRET_REF` must contain one of these references, not the raw
token.

## Multi-company safety

The resolver does not grant permission to emit. It only resolves a configured
reference after the caller supplies an authorized context. Future per-company
flows must pass the authenticated company id and the exact references stored for
that company; client DTO values must never be used directly as arbitrary
references.

Keep separate:

- FULLTECH reseller credentials.
- Each company fiscal identity.
- DGII authorization per issuing company.
- Company certificates or credentials if Alanube requires them.

## Errors

Resolver errors use safe codes and messages:

- `EMPTY_REFERENCE`
- `INVALID_REFERENCE`
- `UNSUPPORTED_PROVIDER`
- `REFERENCE_NOT_ALLOWED`
- `PRODUCTION_BLOCKED`
- `SECRET_NOT_FOUND`
- `ACCESS_DENIED`
- `RESOLUTION_UNSUPPORTED`
- `INCONSISTENT_CONFIGURATION`

Errors do not include token values, environment variable values, secret file
contents, or credential payloads.

## Local verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/isolated-uat/verify-alanube-sandbox-config.ps1
```

The script reports:

- Reference configured.
- Credential found.
- Credential accessible by the current process.
- Resolution support.
- Alanube provider validity.

This phase can prove the first three conditions for supported mechanisms. It
does not prove that Alanube accepts the token, because no network call is
authorized.

## Rotation

Rotation should replace the underlying value while keeping the reference stable
where possible. If the reference changes, update the company configuration or
local env file and rerun local verification. Never place old or new token values
in Git, logs, tickets, docs, screenshots, or HTTP responses.

## Limitations

- Windows Credential Manager read access is blocked until a native, reviewed
  `CredReadW` adapter is implemented.
- No authentication request to Alanube has been implemented or executed.
- Production secret resolution remains blocked unless a future phase explicitly
  enables it with environment and tenant safeguards.
- The traditional POS, sales, NCF, ITBIS, cash, inventory, Flutter and offline
  flows are unchanged.
