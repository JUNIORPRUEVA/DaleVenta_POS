# FullPOS Cloud Offline Capability Matrix

Last updated: 2026-10-08.

Scope: Flutter app (`apps/fulltech_app`) and backend contracts evidenced in this repository. This matrix is a product and engineering contract for offline UX; it does not authorize production data changes.

## Capability Levels

| Level | Meaning | UX contract |
| --- | --- | --- |
| `OFFLINE_FULL` | The operation can commit locally, preserve identity/context, queue sync, and continue safely. | Show success/normal flow after local commit. Sync state is pending/discreet, never an operation failure. |
| `OFFLINE_READ_ONLY` | Existing local/cache data can be displayed without server. | Render local data first. Remote refresh failures are non-blocking. |
| `OFFLINE_PARTIAL` | Some parts work locally, but critical paths require backend. | Show what is available locally and clearly mark server-required actions. |
| `ONLINE_REQUIRED` | No safe local source/queue exists or backend authority is mandatory. | Show a friendly connection-required state, not raw exceptions. |

## Reads

| Area | Function | Local data source | Remote source | Capability | Expected UX |
| --- | --- | --- | --- | --- | --- |
| Auth/session | App bootstrap with cached authenticated session | `TokenStorage`, local user snapshot | `/auth/me` and guarded API calls | `OFFLINE_PARTIAL` | Restore local shell when valid local session exists; server-only validation may remain pending. Do not invent offline login. |
| Login/register | New login/register | none sufficient for new auth | Auth API | `ONLINE_REQUIRED` | Friendly connection/auth error. No `ApiException`, status code, or stack text. |
| Products/catalog | Product list for POS/catalog | `OfflineStore`/catalog cache via repository/controller | Products API | `OFFLINE_READ_ONLY` | Render cached products first; failed refresh must not blank the list. |
| POS products | Sale product picker | cached products | Products API | `OFFLINE_READ_ONLY` | Cached catalog usable for supported offline sales. |
| Facturas | Invoice list/history | `LocalJsonCache` sales invoice cache | `/sales/invoices` | `OFFLINE_READ_ONLY` | Render cached invoices first. If refresh fails, keep list and show non-blocking warning. If no cache, show safe offline/no-data state. |
| Ventas recientes/report panels | Recent sales | `LocalJsonCache` sales cache | Sales API | `OFFLINE_READ_ONLY` | Render cached sales when present. Remote failure should not replace valid rows. |
| Créditos/abonos | Credit list | `LocalJsonCache` credits cache | Sales credit API | `OFFLINE_READ_ONLY` | Cached credits may be shown; writes require the operational matrix below. |
| Turno actual | Cash state | `LocalJsonCache` active cash session | Cash state API | `OFFLINE_PARTIAL` | Distinguish operative state (`OPEN/CLOSED`) from sync verification (`SYNCED/PENDING/FAILED/UNVERIFIED`). |
| Sync status | Queue state | `OfflineStore.pending_actions`, offline sales | none required for local summary | `OFFLINE_READ_ONLY` | Discreet sync status. Technical queue/backend details are mapped through friendly labels. |
| Reports consolidated | Sales/accounting reports | partial caches in some controllers | server reports endpoints | `ONLINE_REQUIRED` or `OFFLINE_PARTIAL` by screen | If no local report source exists, show connection-required state. Do not show empty data as if no business data exists. |
| Warehouses/inventory visible | Terminals and some stock/product caches | `LocalJsonCache` in warehouse/catalog repositories | Warehouse/inventory APIs | `OFFLINE_PARTIAL` | Show cached warehouse/product metadata when available; inventory mutations remain guarded. |
| Settings/company | Company settings | `LocalJsonCache` settings | Company settings API | `OFFLINE_PARTIAL` | Read cached settings; settings writes may queue only where repository explicitly supports it. |
| App update | Update check/download | no authoritative local update source | update API/download | `ONLINE_REQUIRED` | Connection-required or retryable update message. |
| Web/PWA | Browser app reads | browser cache/service worker where configured, no SQLite path | API | `OFFLINE_PARTIAL` | Same customer-safe errors; do not promise Windows/mobile SQLite behavior. |

## Writes

| Operation | Local transaction | Queue | Stable identity/context | Capability | Expected UX |
| --- | --- | --- | --- | --- | --- |
| Sale without fiscal NCF | `OfflineStore.saveOfflineSaleAtomically` | `sales.create` | `clientRequestId`, `originCashSessionId`, terminal/warehouse/device snapshot, item inventory snapshot | `OFFLINE_FULL` when local session/company/user are reliable | Local commit success returns optimistic sale and prints from local model. UI says sale saved, sync pending via status. |
| Fiscal sale requiring NCF | no local NCF authority | none for fiscal issuance | backend must assign fiscal sequence | `ONLINE_REQUIRED` | Keep cart; explain fiscal invoice needs connection. |
| Cash open | active session cached | `cash.open` | `clientSessionId` | `OFFLINE_FULL` for opening identity | Local open may be `OPEN + SYNC_PENDING`; UI must not treat this as invalid by itself. |
| Cash close | cached active session cleared only when matching | `cash.close` | exact `sessionId` required | `OFFLINE_FULL` when sessionId is present | Closing old queued session must never close current open session. Legacy missing session is obsolete, not replayed. |
| Cash movement | pending movement cache | `cash.movement` | exact `sessionId`, `operationId` | `OFFLINE_FULL` when sessionId is present | If local commit succeeds, show saved/pending. If no reliable sessionId, block safely. |
| Refund/return | no full local document commit evidenced for all cases | queued action path exists for network failures in sales repository | original sale context + operation session | `OFFLINE_PARTIAL` | Preserve original context. Do not fallback to current open shift. |
| Credit payment | queue path exists | pending sales action | operation id + operation cash session | `OFFLINE_PARTIAL` | Must preserve operational cash session and idempotency. |
| Company settings/name/PIN | cached update for supported settings | settings queue | operation payload | `OFFLINE_PARTIAL` | "Guardado localmente y pendiente de sincronizar" where repository returns queued. |
| Product/inventory write | not globally proven offline-safe | varies by repository/controller | inventory context required | `ONLINE_REQUIRED` unless a local queue is explicitly evidenced | Do not fake inventory mutations offline. |
| Quote | repository has offline queue patterns but full matrix requires focused audit | quotation queue where implemented | client request identity where implemented | `OFFLINE_PARTIAL` | Treat as partial until focused quote tests confirm local commit/replay. |

## Cash Session Matrix

| Operative state | Sync state | Sale | Cash movement | Refund | Credit payment | Cash close |
| --- | --- | --- | --- | --- | --- | --- |
| `OPEN` | `SYNCED` | `ALLOW` | `ALLOW` | `ALLOW` if original sale context valid | `ALLOW` | `ALLOW` |
| `OPEN` | `SYNC_PENDING` | `QUEUE` when `originCashSessionId` is stable | `QUEUE` when exact `sessionId` exists | `QUEUE/BLOCK` depending on original sale context | `QUEUE` with operation session | `QUEUE` exact `sessionId` |
| `OPEN` | `SYNC_FAILED` | `QUEUE` only if local identity remains reliable | `QUEUE` only if exact `sessionId` exists | `BLOCK` if conflict/session mismatch | `QUEUE/BLOCK` by domain conflict | `QUEUE` exact `sessionId`, or review if conflict |
| `CLOSED` | `SYNC_PENDING` | `BLOCK` until an open operative session exists | `BLOCK` | `QUEUE/BLOCK` by operation session rules | `BLOCK` unless an operation session is open | pending close must replay against original `sessionId` |
| `CLOSED` | `SYNCED` | `BLOCK` | `BLOCK` | `BLOCK` unless a new open session is selected | `BLOCK` | no-op |

Rules:

- Never use "current open shift" as replay fallback.
- Every queued financial operation must carry the original operational identity it was born with.
- `OPEN + SYNC_PENDING` is not automatically invalid; it is an open local operative state with remote confirmation pending.

## Customer-Safe Error Policy

| Case | UI policy |
| --- | --- |
| Local commit success + remote fail | Success/normal flow plus sync pending indicator. No operation failure. |
| Local read exists + remote fail | Keep local data visible. Show discreet refresh warning only if useful. |
| No local data + network fail | Friendly offline/no-data state with safe retry. |
| Online-only feature offline | "Esta función necesita conexión para continuar." |
| Business validation/conflict | Show safe domain message; do not classify as "sin Internet". |
| Unknown/internal/storage failure | Generic safe message; technical detail goes to logs/diagnostics. |

## Platform Notes

- Windows: persistent SQLite path is resolved through product-specific app data directories and legacy migration copies DB sidecars (`.db`, `-wal`, `-shm`, `-journal`) when needed.
- Android/iOS: shared Flutter offline store path uses platform database directories; printer/drawer behavior differs by platform.
- Web/PWA: `resolveLocalDatabasePath` is unsupported. Treat as customer-safe error/partial offline unless a browser storage path is explicitly implemented.

## Known Gaps

- Real Asadero and La Bomba root causes still require client evidence.
- Full module-by-module UI migration away from raw `ApiException` messages is incomplete.
- UAT disconnect/reconnect on real Windows and mobile devices is still required before rollout GO.
