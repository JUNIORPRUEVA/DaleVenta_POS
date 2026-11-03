# Capacidades verificadas del proveedor Alanube — FullPOS Cloud

> Todo lo de este documento sale de los **contratos OpenAPI públicos** guardados
> en `artifacts/alanube-public-contracts/` y de la evidencia de sandbox en
> `artifacts/e32-first-trial/`. Nada está inferido de memoria ni de supuestos.
> El contrato se titula **«API FE DOM» versión 1.0.0**.

## 1. Contratos disponibles (HECHO)

| Archivo | Métodos y rutas declarados |
| --- | --- |
| `createinvoices.json` | `POST /company`, `POST /invoices` (E32) |
| `createinvoicefiscals.json` | `POST /fiscal-invoices`, `POST /purchases` (E31) |
| `createcreditnotes.json` | `POST /credit-notes`, `POST /purchases` (E34) |
| `checkinvoices.json` | `GET /invoices/{id}` |
| `checkinvoicesbycompany.json` | `GET /invoices/{id}/idCompany/{idCompany}` |
| `checkpurchases.json` | `GET /purchases/{id}` |

**Autenticación declarada:** `BearerAuth` — esquema `http`, bearer (`Authorization:
Bearer <token>`). No hay OAuth ni firma de petición en el contrato.

## 2. Lo que está confirmado con evidencia real (HECHO)

Ejecutado contra el **sandbox** del proveedor, con `ALANUBE_ENABLE_REAL_CALLS`
apagado por defecto y autorización explícita para esa prueba puntual:

- `POST /invoices` (E32) respondió **HTTP 201** con `remoteId`
  `01M4Y3DEPXXG27G8BNQGMNQ04B`.
- El documento quedó en `REGISTERED` / `ACCEPTED` **del proveedor** con
  `sequenceConsumed = true` y eNCF `E320009805001`.
- **`ACCEPTED` del proveedor NO es aceptación de la DGII.** El producto no
  declara `DGII_ACCEPTED` por esta respuesta.

Ese eNCF (`E320009805001`) está **consumido** y no se reutiliza en ninguna
prueba. La evidencia está en `artifacts/e32-first-trial/`.

## 3. Discrepancia de esquema en la lectura (HECHO)

La recuperación por `GET /invoices/{id}` respondió **HTTP 200**, pero los datos
recibidos **no cumplen el esquema que declara el propio contrato**:

| Campo | Problema detectado |
| --- | --- |
| `stampDate` | formato distinto al declarado |
| `trackId` | tipo distinto al declarado |
| `signatureDate` | formato distinto al declarado |

Consecuencias registradas:

- `OFFICIAL_GET_SCHEMA = false`
- `sufficientForProviderReview = false`
- La conciliación propuesta quedó con `canApply = false` y **nunca se aplicó**
  (`real-trial-result.json`, `STOPPED_REVIEW_REQUIRED`, `canRetryPost = false`).

Interpretación (HIPÓTESIS): o el sandbox devuelve una forma antigua, o el
contrato publicado no refleja el entorno real. Es una pregunta abierta al
proveedor, no un hecho resuelto.

## 4. Lo que el producto hace hoy con esto (HECHO)

| Capacidad | Estado real |
| --- | --- |
| Preparar borradores locales (E31, E32, E34) | Implementado |
| Despacho **simulado** correlacionable | Implementado, solo perfil UAT |
| Envío real de comprobantes | **NO implementado** (`PRODUCTION_EMISSION_IMPLEMENTED = false`) |
| Reintento automático del POST | **NO**; una respuesta correlacionada dudosa cae siempre en `HUMAN_REVIEW_REQUIRED` |
| Reutilización de secuencia consumida | **Nunca** |
| Declarar aceptación de la DGII | **Imposible por diseño**: solo `DGII_ACCEPTED` cuenta, y no se deriva del proveedor |

## 5. Capacidades NO verificadas (PENDIENTE)

| # | Capacidad | Estado |
| --- | --- | --- |
| N1 | Notificación (webhook o sondeo) de la aceptación **de la DGII** | No confirmado en el contrato público |
| N2 | Anulación / reverso de un comprobante ya aceptado | No presente en el contrato público |
| N3 | Consulta de estado por rango de fechas o por RNC | No presente |
| N4 | Límites de tasa (rate limit) y códigos de error documentados | No publicados en el contrato recuperado |
| N5 | Idempotencia del `POST` (clave de idempotencia) | No declarada |
| N6 | Comportamiento ante `5xx` y reintentos seguros | No documentado |
| N7 | Formato exacto de `stampDate`, `trackId`, `signatureDate` reales | Contradice el contrato (ver §3) |
| N8 | Endpoint de «company» y su efecto real sobre la habilitación | Declarado en el contrato, no ejercitado |

Nada de lo pendiente se implementa a ciegas. Se pregunta primero (ver
`ECF_ALANUBE_PROVIDER_QUESTIONS.md`).
