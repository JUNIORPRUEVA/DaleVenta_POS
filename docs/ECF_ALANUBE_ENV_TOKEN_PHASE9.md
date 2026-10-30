# Alanube Sandbox token via env:// - Phase 9

## Scope

This phase prepares the API to resolve the Alanube Sandbox token through the
existing `env://` provider. It does not authenticate with Alanube, does not call
DGII, and does not enable electronic fiscal emission.

## Private locations

Configuration file:

```text
C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE\apps\api\.env.alanube.uat.local
```

Encrypted local token file:

```text
C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE\apps\api\.secrets\alanube-sandbox-token.securestring.xml
```

Both paths are local-only and ignored by Git. The encrypted token file is a
Windows DPAPI-protected `SecureString` exported for the current Windows user.
It is not portable to another user or machine.
If the encrypted file already exists, the setup script preserves it unless the
operator types `YES` in the local PowerShell window.

## Reference

Use:

```text
ALANUBE_TOKEN_SECRET_REF=env://ALANUBE_SANDBOX_TOKEN
```

The token value itself must never be written in `.env.alanube.uat.local`, any
`.example` file, docs, tests, Prisma, Flutter, command arguments, logs, or chat.

## Operator procedure

1. Open the Alanube attachment locally and copy the token from `FULLTECH.txt`.
   Do not paste it in chat.

2. Store it with the local secure prompt:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/isolated-uat/set-alanube-sandbox-token.ps1
```

The prompt uses `Read-Host -AsSecureString`; the token is not displayed.

3. Confirm the private paths are ignored:

```powershell
git check-ignore -v -- apps/api/.env.alanube.uat.local apps/api/.secrets/alanube-sandbox-token.securestring.xml
```

4. Verify local configuration without contacting Alanube:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/isolated-uat/verify-alanube-sandbox-config.ps1 -LoadLocalSecret
```

Expected safe states:

```text
ALANUBE_TOKEN_SECRET_REF: OK
ALANUBE_TOKEN_CREDENTIAL_FOUND: OK
ALANUBE_TOKEN_ACCESSIBLE_BY_PROCESS: OK
ALANUBE_TOKEN_RESOLUTION_SUPPORTED: OK
ALANUBE_TOKEN_VALID_WITH_PROVIDER: NOT_TESTED
```

5. Start the isolated UAT API with the token loaded only into that process:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/isolated-uat/start-api-with-alanube-env.ps1
```

The launcher rejects non-Sandbox configuration, keeps real Alanube calls
disabled, and clears `ALANUBE_SANDBOX_TOKEN` from the launcher process when the
API stops.

## Safety guarantees

- `ALANUBE_ENV` must stay `sandbox`.
- `ALANUBE_BASE_URL` must stay `https://sandbox.alanube.co/dom/v1`.
- `ALANUBE_ENABLE_REAL_CALLS` must stay `false`.
- `ECF_EMISSION_ENABLED` must stay `false`.
- `ECF_ALANUBE_AUTH_TESTS_ENABLED` must stay `false`.
- The token is loaded only as process environment for isolated UAT.
- The token is not placed in global Windows environment variables.
- The token is not sent to Alanube in this phase.

## Pending

Token validity with Alanube remains `NOT_TESTED` until a later phase explicitly
authorizes Sandbox authentication.
