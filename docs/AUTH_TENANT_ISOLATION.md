# DaleVentas Auth And Tenant Isolation

Last updated: 2026-09-06.

## Product Separation

DaleVentas / FullPOS Cloud and FullPOS Owner are separate systems.

| Product | EasyPanel project | Backend | Database/service |
| --- | --- | --- | --- |
| DaleVentas / FullPOS Cloud | `daleventapos` | `https://daleventapos-backend.gcdndd.easypanel.host` | `daleventa` |
| FullPOS Owner | `ventas` | `https://ventas-fullpos-backend.gcdndd.easypanel.host` | FullPOS Owner infrastructure |

DaleVentas clients must never target the FullPOS Owner backend. FullPOS Owner
clients must never target the DaleVentas backend.

## API Configuration Order

The Flutter client resolves API configuration in this order:

| Source | Example | Priority | Used by | Safety |
| --- | --- | --- | --- | --- |
| `--dart-define=API_BASE_URL=...` | Windows/iOS/Android builds | 1 | Debug and Release | Explicit, but guarded |
| Web runtime `env.js` | EasyPanel PWA container | 2 | Web/PWA | Explicit, guarded |
| `apps/fulltech_app/.env` asset | Local desktop/mobile fallback | 3 | Debug and local builds | Guarded |
| `ProductConfig.productionApiBaseUrl` | DaleVentas production backend | 4 | Fallback | Safe default |

`ventas-fullpos-backend.gcdndd.easypanel.host` is a forbidden DaleVentas host.
Official production builds also require
`daleventapos-backend.gcdndd.easypanel.host`.

## Official Windows Release Build

Use the controlled script:

```powershell
.\scripts\release\build_windows_release.ps1
```

The script:

- sets `FULLPOS_PRODUCTION_BUILD=true`
- sets the DaleVentas API and app URLs
- rejects FullPOS Owner backend hosts
- builds Windows Release
- inspects the generated Flutter kernel for the expected backend
- fails if the forbidden backend is present

Do not publish a Windows installer from a manually compiled Release folder.

## Session Bootstrap Rules

Session identity is limited to:

- `accessToken`
- `refreshToken`
- `authUserSnapshot`

On bootstrap, the client must validate the access token before rendering an
authenticated tenant. A token is rejected if it is expired, missing `sub`,
missing `companyId`, or inconsistent with the cached user snapshot.

If validation fails, session-bound identity is cleared and the app returns to
login. The app must not render dashboard data using only a stale local snapshot.

## Login And Logout Rules

Login always starts by clearing old session-bound identity before saving the new
server session. The new session is authoritative:

```text
server user == local auth user == UI user
server company == local auth company == UI company
```

Logout clears session identity but must preserve legitimate offline business
data and device configuration unless a separate destructive action is explicitly
approved.

## Remembered Credentials

The app may remember the email/user for convenience. It must not persist the
plaintext password. Existing remembered password values are removed when the
login screen loads or persists remembered user state.
