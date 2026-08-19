# FullPOS Cloud - Offline Sync Architecture

Estado de esta fase: ventas no fiscales offline endurecidas en base local nativa. Cloud sigue siendo source of truth.

## Read Path

```text
UI
  -> repository GET
  -> backend OK
  -> tenant-aware HTTP/cache snapshot update
  -> UI uses server data

UI
  -> repository GET
  -> network/server unavailable
  -> tenant-aware cache lookup
  -> UI uses cached read-only snapshot
```

Cache no autoriza acciones. La autorizacion offline usa el ultimo snapshot de sesion solo para UX; el backend revalida al sincronizar.

## Offline Non-Fiscal Sale Write Path

```text
cashier creates non-fiscal sale
  -> backend POST /sales
  -> network/5xx failure
  -> reject if fiscal/NCF requested
  -> require local companyId + userId
  -> SQLite transaction:
       offline_sales header
       offline_sale_items snapshots
       offline_sale_payments
       offline_inventory_intents
       pending_actions outbox row
  -> optimistic sale returned as pending
```

If the SQLite transaction fails, no local sale/outbox partial record should remain.

## Sync Path

```text
trigger: timer/app start/manual/future connectivity trigger
  -> SyncQueueService single-flight mutex
  -> resolve active companyId/userId
  -> SELECT pending_actions for same companyId/userId and due next_attempt_at
  -> run registered handler
  -> backend validates tenant/auth/permissions/stock/cash session
  -> success:
       mark local offline sale synced
       mark inventory intents synced
       remove outbox row
  -> retryable failure:
       status=error, attempts++, next_attempt_at with backoff+jitter
  -> permanent/conflict/auth failure:
       status=failed/conflict/auth_blocked
       preserve local record and outbox metadata
```

## Idempotency

```text
clientRequestId generated once for a sale attempt
local outbox unique: company_id + idempotency_key
backend unique: Sale(company_id, client_request_id)
backend create:
  find existing by companyId + clientRequestId
  if found, return existing sale
  transaction creates sale/items/payment fields/stock decrement
  P2002 fallback re-reads and returns existing sale
```

The critical response-loss retry path returns the existing sale instead of creating a second sale.

## Conflict Path

```text
409 -> conflict
400/404/422 -> failed
401/403 after AuthInterceptor refresh attempt -> auth_blocked
5xx/network/timeout -> retry with backoff+jitter
```

No pending sale is deleted merely because the backend rejects it.

## Tenant Isolation

```text
cache key = http-cache:v2:company:<companyId>:user:<userId>:METHOD:URI
outbox row = company_id + user_id + idempotency_key
sync query = WHERE company_id = activeCompany AND user_id = activeUser
offline sale query = WHERE company_id = activeCompany
```

Company B credentials never process Company A pending actions. Legacy unscoped actions are not included in automatic sync.

## Stock

Local stock is not authoritative. Offline sale stores inventory intents as append-only local intent rows. Backend applies real product stock decrement inside the sale transaction and exactly once through sale idempotency. If stock is insufficient when syncing, the operation remains visible as failed/conflict according to backend response.

## Customers

Current safe policy: existing cached customer IDs can be referenced. New customer offline dependency graph is not implemented in this phase; if a future flow allows offline customer creation, sale sync must depend on customer sync and map local customer ID to server ID before sale submission.

## Images

Native mobile/desktop product images use `FulltechImageCacheManager` with normalized/versioned keys. Company object paths and image versions prevent same product IDs across companies from colliding. Web/PWA still depends primarily on browser/Flutter caching; no custom tenant-aware service worker API cache is implemented.

## Fiscal/NCF

Fiscal sales remain online-only. NCF sequence reservation is server-side and must not be faked locally.

## Remaining Gaps

- No full sync dashboard UI yet.
- No local customer dependency graph yet.
- No service-worker-controlled API/image cache for Web.
- No automated full Flutter app + API process E2E in this phase; local restart and backend idempotency are verified separately.
- Offline cash shift reconciliation remains backend-authoritative.

## Verified Scenarios

```text
local offline sale transaction
  -> header/items/payment/inventory intents/outbox persisted
  -> close and reopen OfflineStore
  -> same aggregate and pending action are present

backend response loss retry
  -> POST /sales with clientRequestId
  -> backend commits
  -> second POST with same companyId + clientRequestId
  -> same sale id returned
  -> one Sale row
  -> one SaleItem row
  -> payment fields unchanged from first request
  -> product stock decremented once
  -> price snapshot unchanged

tenant switch
  -> Company A pending action
  -> SyncQueueService scoped as Company B
  -> action is not processed
  -> SyncQueueService scoped as Company A
  -> action may process
```
