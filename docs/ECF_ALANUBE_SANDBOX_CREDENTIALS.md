# Alanube Sandbox credentials - local operator guide

This phase prepares local Sandbox configuration only. It does not enable fiscal
emission, does not authenticate against Alanube, and does not call Alanube or
DGII.

## Private file

Operator file:

```text
C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE\apps\api\.env.alanube.uat.local
```

Template:

```text
C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE\apps\api\.env.alanube.uat.local.example
```

The private file is ignored by Git. Do not paste the Alanube token, portal
password, private keys, certificates, or any real secret into chat, tickets,
docs, tests, or commits.

## Variables to complete

Keep these safety values exactly as shown until a later approved phase:

```text
ALANUBE_ENV=sandbox
ALANUBE_BASE_URL=https://sandbox.alanube.co/dom/v1
ALANUBE_ENABLE_REAL_CALLS=false
ECF_EMISSION_ENABLED=false
ECF_ALANUBE_AUTH_TESTS_ENABLED=false
```

Configure these locally:

```text
ALANUBE_TOKEN_SECRET_REF=
ALANUBE_RESELLER_ACCOUNT_REF=
ALANUBE_CREDENTIAL_SOURCE=
ALANUBE_TEST_RNC=
ALANUBE_TEST_SEQUENCE_PREFIX=
ALANUBE_TEST_SEQUENCE_FROM=
ALANUBE_TEST_SEQUENCE_TO=
ALANUBE_TEST_SEQUENCE_EXPIRES_ON=
```

For the Alanube Sandbox package received for this phase, the non-secret test
values are:

```text
ALANUBE_TEST_RNC=132109122
ALANUBE_TEST_SEQUENCE_FROM=9805001
ALANUBE_TEST_SEQUENCE_TO=9806000
ALANUBE_TEST_SEQUENCE_EXPIRES_ON=2028-12-31
```

`ALANUBE_TEST_SEQUENCE_PREFIX` is optional in this phase because Alanube
provided a numeric range, not a confirmed prefix. Do not invent one.

Accepted values for `ALANUBE_CREDENTIAL_SOURCE`:

```text
alanube-sandbox-attachment
operator-vault
windows-credential-manager
company-secret-manager
manual-pending
```

`ALANUBE_TOKEN_SECRET_REF` must be a reference such as
`env://ALANUBE_SANDBOX_TOKEN`, `vault://...`, `secret://...`, or `uat://...`.
It must not contain the raw token.

Important: there is no backend secret resolver implemented yet. In this phase,
the reference proves that the operator selected a storage location, but the API
does not read or use the token. A later implementation should add an
`EcfSecretResolverService` that supports `env://` for local Sandbox/UAT and a
managed secret provider for shared environments, with no secret values returned
by endpoints or logs.

Do not assume that the portal password is valid API authentication. Do not
assume that the received token is a Bearer token until the official Alanube
contract for authentication is verified in a later phase.

## Windows and VS Code procedure

1. In VS Code, open the worktree folder:

```powershell
code "C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE"
```

2. Open the private file only on the operator workstation:

```text
apps\api\.env.alanube.uat.local
```

3. If the file does not exist, create it from:

```text
apps\api\.env.alanube.uat.local.example
```

4. Place the actual token only in the chosen local secret store. In the private
file, write only the reference in `ALANUBE_TOKEN_SECRET_REF`.

Minimal local Sandbox procedure until the resolver is implemented:

1. Open Windows Credential Manager.
2. Add a Generic Credential named `FullPOS-Alanube-SandboxToken`.
3. Use an operator-owned username such as `alanube-sandbox`.
4. Paste the token only in the password field.
5. In the private env file, set `ALANUBE_TOKEN_SECRET_REF` to a reference such
   as `secret://windows/FullPOS-Alanube-SandboxToken`.

Do not run commands that echo the token. Do not place the raw token in
`ALANUBE_TOKEN_SECRET_REF`; that variable stores only a reference.

5. Verify that Git ignores the private file:

```powershell
git check-ignore -v -- apps/api/.env.alanube.uat.local
```

6. Run the local no-network validation:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/isolated-uat/verify-alanube-sandbox-config.ps1
```

The validation prints only `OK`, `PENDING`, `BLOCKED`, or `ABSENT` states. It
does not print tokens, RNC values, sequence values, passwords, or certificates.

## Multi-company boundaries

Keep these concepts separate:

- FULLTECH reseller integration credentials: used only as an integration
  reference until the Alanube contract is verified.
- Client company fiscal identity: configured per company/tenant, never shared
  globally.
- DGII authorization for each issuing company: required before production
  emission can be enabled for that company.
- Individual company credentials or certificates: use only references if
  Alanube requires them; never store plaintext secrets in PostgreSQL.

The reseller token must not be treated as automatic authorization to emit for
all client companies.

## Current safety posture

- Alanube client has no HTTP transport.
- Production calls are blocked.
- Emission remains disabled.
- `GET /ecf/provider/status` must expose readiness booleans only, not secrets or
  raw fiscal configuration.
