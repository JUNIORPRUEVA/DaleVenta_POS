# DOSA — evidencia técnica del webhook y emisión TEST

Fecha: 2026-11-04 · Rama: `agent/ecf-dosa-integration-20261104` · Worktree:
`C:\src\fullpos-ecf-dosa-integration`.

Estado: **PREPARADO TÉCNICAMENTE, NO EJECUTADO**. No se ha enviado ningún
comprobante a DOSA, no se ha usado la clave real y no se ha creado ninguna sesión
real. La preparación UAT local se documenta por separado en
`docs/ecf/DOSA_UAT_ENVIRONMENT.md`.

Clasificación de afirmaciones: **HECHO** = verificado en código/prueba;
**HIPÓTESIS** = plausible pero depende de despliegue/proveedor; **BLOQUEO** =
requiere una acción externa o autorización.

---

## 1. Ruta pública del webhook

| Comprobación | Resultado |
| --- | --- |
| Controlador | `@Controller()` + `@Post("webhook/dosa")` → `DosaWebhookController` |
| Prefijo global | **No** hay `setGlobalPrefix` en `main.ts` (**HECHO**) |
| Ruta interna real | `/webhook/dosa` (**HECHO**, verificada en `dosa-webhook.controller.spec.ts`) |
| Ruta pública prevista | `https://fullposcloud.fulltechrd.com/api/webhook/dosa` — el proxy retira `/api` (**HIPÓTESIS** de despliegue; el código documenta esta intención) |
| Raw body | `main.ts` preserva bytes crudos para prefijos `/webhook/` y `/api/webhook/` (**HECHO**) |
| Endpoint apagado | Responde `503` JSON `ECF_DOSA_WEBHOOK_DISABLED`, nunca HTML (**HECHO**, prueba nueva) |

Bandera: `DOSA_WEBHOOK_ENABLED=true`. Sin ella, la ruta responde 503 y no llama al
servicio.

## 2. HMAC-SHA256 sobre `t` + `.` + rawBody

Contrato confirmado por DOSA el 2026-11-04: `HMAC-SHA256(secreto, t + "." + cuerpo)`
con cabecera `t=<hora>,v1=<firma>`. Siguen sin verificar contra un evento real la
unidad de `t` y la codificación del secreto.

Implementación: `dosa-webhook-signature.policy.ts` — `HMAC_SHA256_TIMESTAMPED`.

- Firma sobre los **bytes exactos** (`createHmac(...).update(t + ".").update(rawBody)`).
- Comparación en tiempo constante (`timingSafeEqual`); acepta digest hex o base64.
- Anti-replay solo **después** de autenticar; ventana por defecto 300 s.
- `BLOCKED` por defecto; sin secreto o sin cuerpo falla cerrado.

Pruebas (`dosa-webhook-hmac.spec.ts`): firma correcta hex/base64, cuerpo
re-serializado rechazado, cuerpo alterado, otro secreto, otro timestamp, replay
fuera de ventana, timestamp futuro, justo dentro, unidad ms, sin rawBody, sin
secreto, estrategia bloqueada, sin cabecera, no filtra secreto, parseo estricto.

Pipeline (`dosa-webhook-hmac-pipeline.spec.ts`): sin firma válida **no** hay
consulta a base; firma alterada y replay no llegan a la base.

## 3. Firma correcta / inválida / replay / timestamp / secreto ausente

Cubierto por las pruebas anteriores. Códigos de rechazo estables:
`SIGNATURE_MISMATCH`, `SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE`,
`SIGNATURE_TIMESTAMP_INVALID`, `SECRET_NOT_CONFIGURED`, `RAW_BODY_UNAVAILABLE`,
`STRATEGY_BLOCKED`, `SIGNATURE_HEADER_MISSING/MALFORMED`,
`SIGNATURE_ALGORITHM_UNSUPPORTED`, `CONFIG_INVALID`.

## 4. Correlación de `empresa.conectada`

**HECHO importante:** la muestra oficial de DOSA **no incluye un campo de tipo de
evento**. Por eso el sistema no inventa `empresa.conectada`: persiste el evento
como `PENDING_CLASSIFICATION` y correlaciona por **datos de servidor**:

1. `resolver.resolveByRnc(payload.rnc)` → `ecf_dosa_certification_sessions` +
   `ecf_company_configurations` (nunca por el RNC del evento por sí solo).
2. `bindProviderPostulation({ companyId, rnc, postulacionId })` → vincula el
   `postulacion_id` al intento ACTIVO de esa empresa y ese RNC.
3. `recordEventHint` solo escribe `last_event_type`/`last_event_at` (best-effort).

Prueba: `dosa-webhook-hmac-pipeline.spec.ts` › «un evento autenticado deja la
pista y vincula el postulacion_id».

## 5. Un webhook no vincula credenciales a otra empresa

- La resolución empresa↔RNC es server-side y exige coincidencia única.
- `bindProviderPostulation` exige `company_id`, `rnc` y `active_key` del intento
  y rechaza un `postulacion_id` que ya pertenezca a otra empresa.
- La bóveda cifra con AAD `<companyId>:<rnc>:<environment>`: un criptograma
  movido a otra empresa **no se descifra**.

Pruebas: `dosa-credential.spec.ts` › «un criptograma movido a otra empresa NO se
descifra» y `dosa-webhook-hmac-pipeline.spec.ts` › «un RNC de otra empresa escribe
en ESA empresa y en ninguna otra».

## 6. API Keys TEST y producción: separadas y cifradas

- `readDosaEmissionConfig` toma `DOSA_TEST_API_KEY` o `DOSA_PRODUCTION_API_KEY`
  según `DOSA_EMISSION_ENVIRONMENT`; **no hay sustitución cruzada**.
- En `PRODUCTION` exige además `DOSA_PRODUCTION_EMISSION_ENABLED=true` y que la
  clave sea de producción (`DOSA_KEY_ENVIRONMENT_MISMATCH` si no).
- `DosaEmissionService.emit` abre solo la credencial del entorno pedido y bloquea
  con `ECF_DOSA_CREDENTIALS_MISSING_FOR_ENVIRONMENT:<ENV>` si falta.
- En reposo: AES-256-GCM con HKDF-SHA256 y AAD por empresa/RNC/entorno; la tabla
  guarda solo criptograma, IV, authTag, huella y presencia.

Pruebas: `dosa-emission-key-selection.spec.ts`, `dosa-credential.spec.ts`.

## 7. RNC TEST `133306001` vs RNC real `133080206`

`verifyFiscalIdentity` (usada por la compuerta) en `TEST` exige que el emisor sea
exactamente `DOSA_TEST_RNC`; en `PRODUCTION` no aplica esa restricción de prueba.

Pruebas: `dosa-ecf.spec.ts` (`TEST_RNC_NOT_CONFIGURED`, `TEST_RNC_MISMATCH`,
`SENDER_RNC_MISSING`) y `dosa-integration-journey.spec.ts` › el recorrido bloquea
con `TEST_RNC_MISMATCH` cuando el emisor no es el RNC de prueba.

## 8. Adaptador fiscal y selección de credenciales

Orden de `DosaEmissionService.emit`: barrera del documento → configuración fiscal
del servidor → `assessDosaEmissionGate` → apertura de credencial de ESA
empresa/RNC/entorno → cliente con clave de **ese** entorno.

Pruebas: `dosa-emission.spec.ts`, `dosa-emission.barrier.spec.ts`,
`dosa-emission-key-selection.spec.ts`, `dosa-ecf.fiscal-catalogues.spec.ts`,
`dosa-contract-alignment.spec.ts`.

## 9. Reintentos, respuestas inciertas, e-NCF y duplicación

- `DOSA_RETRY_POLICY`: una tentativa por documento; **sin reintento automático**
  en desconocido, timeout ni rechazo; `requiresHumanReconciliationOnUnknown`.
- `mayRetryAutomatically` devuelve siempre `allowed: false` (probado para todos
  los desenlaces en `dosa-ecf.spec.ts`).
- Timeout / 5xx → `unconfirmed: true`; la única excepción es HTTP 502
  `Error de envío`, marcado `safeToRetrySameEncf` (la DGII no recibió el eCF).
- `classifyDosaResponse`: `codigo 0` → `UNRESOLVED` (dos fuentes del proveedor se
  contradicen); código desconocido → `UNRESOLVED`; nunca `isDgiiApproval = true`.
- Idempotencia del cliente: misma clave no se envía dos veces; cortacircuitos tras
  N fallos.

Pruebas: `dosa-emission.spec.ts`, `dosa-response.mapper` (vía
`dosa-contract-alignment.spec.ts`), `dosa-webhook-atomicity.spec.ts`.

## 10. Pruebas con respuestas DOSA simuladas

Ejecutado en este trabajo (sin red, sin base real):

```
npm run api:build
npx jest --runInBand --testPathPatterns="ecf/provider/dosa"
```

Resultado: **29 suites / 530 pruebas aprobadas**, 11 suites y 92 pruebas
**skipped** (las `*.integration-spec.ts` / `*.pg.integration-spec.ts` requieren
PostgreSQL local dedicado; no se ejecutaron aquí — ver bloqueo B3).

Se añadió `dosa-webhook.controller.spec.ts` (7 pruebas) que fija la ruta interna
`webhook/dosa`, el 503 JSON con la bandera apagada, el paso de `rawBody` y la no
conversión de rechazos en 200.

## 11. Evidencia para la futura prueba de emisión TEST autorizada

Procedimiento: `docs/ECF_DOSA_PRIMERA_EMISION_TEST.md` (dry-run → envío único con
token de autorización → lectura de la respuesta). Probador aislado:
`dosa-test-emission.probe.ts` (+ `.cli.ts`, `.spec.ts`), que no importa Prisma y
no puede alterar la facturación de ninguna empresa.

Evidencia que deja cada intento (`DosaProbeEvidence`): `attemptId`, `at`, `encf`,
`senderRnc`, `environment`, `baseUrl`, `apiKeyLength` (nunca el valor),
`outcome`, `httpStatus`, `classification`, `responseSha256`,
`safeToRetrySameEncf`.

Precondiciones para ejecutarla: autorización expresa con el `eNCF` exacto,
`DOSA_EMISSION_ENVIRONMENT=TEST`, `DOSA_BASE_URL=https://dosasystem.com`,
`DOSA_TEST_API_KEY`, `DOSA_TEST_RNC=133306001`, rango de secuencia autorizado y
unidad de medida del catálogo.

---

## Bloqueos restantes (no resueltos en este trabajo)

- **B1 — Unidad de `t` y encoding del secreto no verificados.** La fórmula
  HMAC-SHA256 sí está confirmada; falta un evento real para fijar si `t` es
  segundos/milisegundos y si el secreto hex es texto o 32 bytes. Todo es
  configurable y falla cerrado.
- **B2 — Tipo de evento no confirmado.** El proveedor no envía un campo de tipo
  de evento; los eventos quedan `PENDING_CLASSIFICATION`. No hay `empresa.conectada`
  tipado por el proveedor.
- **B3 — Pruebas PostgreSQL no ejecutadas aquí.** Las `*.pg.integration-spec.ts`
  (92 pruebas) requieren una base desechable de loopback. Deben correr antes del
  cierre definitivo.
- **B4 — Enum y migración de DOSA.** El schema actual ya incluye `DOSA` en
  `EcfProvider`; falta confirmar que la migración esté aplicada en el entorno
  donde se hará la primera emisión real.
- **B5 — Ruta pública `/api/webhook/dosa`.** Depende de que el proxy retire `/api`
  y reenvíe a `/webhook/dosa`; debe verificarse en el entorno desplegado.
- **B6 — Primera emisión TEST real.** Pendiente de autorización expresa; no se
  ejecutó ninguna llamada a DOSA.
