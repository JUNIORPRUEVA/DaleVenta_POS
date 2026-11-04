# DOSA — estado técnico del webhook y de la emisión TEST

Auditoría realizada el **2026-11-04** en el worktree
`C:\src\fullpos-ecf-dosa-integration`, rama `agent/ecf-dosa-integration-20261104`,
HEAD base de la auditoría `98ce0244`; la preparación UAT y los commits
posteriores se documentan en `docs/ecf/DOSA_UAT_ENVIRONMENT.md`.

**No se modificó código, no se hizo commit, no se envió ninguna solicitud a DOSA
ni a la DGII y no se emitió ningún comprobante.** Este documento es el resultado
de la auditoría y de la ejecución de las pruebas existentes.

## Resumen ejecutivo

| Área | Estado |
| --- | --- |
| Receptor del webhook y ruta pública | **CONFIRMADO** |
| Preservación del cuerpo crudo (`rawBody`) | **CONFIRMADO** |
| Fórmula HMAC-SHA256 (`t + "." + rawBody`) | **CONFIRMADA**; unidad de `t` y encoding del secreto pendientes de evento real |
| Escenarios de firma (válida, inválida, replay, timestamp, sin secreto) | **CONFIRMADO** (probado) |
| Correlación del evento (RNC → empresa, `postulacion_id`) | **CONFIRMADO** |
| Aislamiento: un webhook no vincula credenciales a otra empresa | **CONFIRMADO** (probado) |
| Claves TEST y producción separadas y cifradas | **CONFIRMADO** |
| RNC TEST `133306001` vs RNC real `133080206` | **CONFIRMADO** (valores distintos y política explícita) |
| Adaptador fiscal y selección de credenciales por empresa/RNC/entorno | **CONFIRMADO** |
| Reintentos, respuestas inciertas, e-NCF y anti-duplicación | **CONFIRMADO** en lo implementado |
| Emisión TEST real | **BLOQUEADO** por el proveedor |

**Pruebas ejecutadas:** 10 suites, **197 pruebas en verde**, 8 omitidas
(integración con PostgreSQL, requiere base de datos).

```
npx jest --runInBand --testPathPatterns "webhook|emission-key-selection|dosa-emission.spec|dosa-credential.spec"
→ Test Suites: 1 skipped, 10 passed, 10 of 11 total
→ Tests:       8 skipped, 197 passed, 205 total
```

---

## 1. Receptor y ruta pública — CONFIRMADO

`apps/api/src/ecf/provider/dosa/dosa-webhook.controller.ts`

- L29-33: `@Controller()` + `@Post("webhook/dosa")`.
- La ruta interna es `/webhook/dosa`; el `/api` lo aporta el borde, así que la
  URL pública es **`POST /api/webhook/dosa`**. Coincide con la configurada.
- L19: documenta que usa el `rawBody` que `main.ts` preserva byte a byte.

## 2. HMAC-SHA256 sobre el cuerpo crudo — PARCIAL

`apps/api/src/ecf/provider/dosa/dosa-webhook-signature.policy.ts`

Implementado y probado:

- L10: `firma = HMAC-SHA256(webhookSecret, t + "." + rawRequestBody)`.
- L1: `createHmac` + `timingSafeEqual` (comparación en tiempo constante).
- L110: cabecera `x-dosa-signature`.
- L113: ventana anti-replay por defecto **300 s**.
- Acepta hexadecimal y base64; exige el cuerpo **original** (re-serializar no
  valida).

### Estado del contrato

La fórmula HMAC-SHA256, la cabecera `t=<hora>,v1=<firma>` y el mensaje
`t + "." + cuerpo` fueron confirmados por DOSA el 2026-11-04. Siguen sin
verificarse contra un evento real la unidad de `t` y la codificación del secreto.
`DOSA_WEBHOOK_TIMESTAMP_UNIT` y `DOSA_WEBHOOK_SECRET_ENCODING` permiten ajustarlo;
la estrategia `BLOCKED` (L30-32) mantiene el fallo cerrado hasta configurarlo.

`apps/api/src/main.ts` L106-110: el `verify` de cuerpo crudo cubre
`/webhook/` y `/api/webhook/`, y solo esas rutas.

## 3. Escenarios de firma — CONFIRMADO

`dosa-webhook-hmac.spec.ts` (20 pruebas) cubre exactamente lo pedido:

| Escenario solicitado | Prueba |
| --- | --- |
| Firma correcta | «acepta una firma correcta en hexadecimal» / «…en base64» |
| Firma inválida | «rechaza una firma hecha con otro secreto», «rechaza si el cuerpo se altera» |
| Replay | «protege contra replay: fuera de la ventana se rechaza» |
| Timestamp incorrecto | «rechaza un timestamp demasiado en el futuro», «rechaza una firma calculada con otro timestamp» |
| Secretos ausentes | «sin secreto configurado no verifica», «sin variable queda bloqueado» |

Además: «usa los BYTES originales: un cuerpo re-serializado NO valida» y «la
respuesta no filtra el secreto».

## 4. Correlación `empresa.conectada` — CONFIRMADO

`dosa-webhook.service.ts` y `dosa-webhook.dto.ts`

- El **RNC del evento es una pista**, nunca la identidad (dto L25, service L32).
- La empresa se resuelve **en el servidor** con `DosaCompanyResolver.resolveByRnc`
  (service L173), que consulta nuestras sesiones de certificación.
- `postulacion_id` es obligatorio en el DTO (L79-81) y se vincula con
  `bindProviderPostulation` (service L51), «la única puerta por la que un evento
  autenticado puede tocar identificadores».
- RNC desconocido → `ECF_DOSA_WEBHOOK_UNKNOWN_RNC`, sin atribuir a nadie.

Pruebas: «un evento autenticado deja la pista y vincula el postulacion_id»,
«un RNC desconocido no se atribuye a ninguna empresa».

## 5. Un webhook no puede vincular credenciales a otra empresa — CONFIRMADO

Tres barreras independientes, las tres probadas:

1. **Resolución server-side**: la empresa sale de nuestras sesiones, no del
   payload. «un RNC de otra empresa escribe en ESA empresa y en ninguna otra».
2. **Nada se activa desde el webhook**: lo recibido queda en
   `PENDING_CONFIRMATION`; pasar a `ACTIVE` es un acto humano
   (`dosa-credential-vault.service.ts` L24-25). Prueba: «un evento sin tipo
   confirmado NO activa nada: no se promueve la credencial».
3. **Fallo cerrado**: «sin firma válida NO se ejecuta ninguna consulta», «una
   firma alterada no llega a la base».

## 6. Claves TEST y producción: separadas y cifradas — CONFIRMADO

`dosa-emission.client.ts` y `dosa-credential-vault.service.ts`

- Variables **distintas**: `DOSA_TEST_API_KEY` y `DOSA_PRODUCTION_API_KEY`
  (client L95-96), con `DOSA_EMISSION_ENVIRONMENT` y `DOSA_TEST_RNC`.
- Guarda explícita `DOSA_KEY_ENVIRONMENT_MISMATCH`: «una clave de TEST nunca
  puede apuntar al host de producción» (client L35-37).
- Producción exige además `DOSA_PRODUCTION_EMISSION_ENABLED=true`.
- Almacenamiento por empresa: **AES-256-GCM** con clave derivada por
  **HKDF-SHA256** de `DOSA_CREDENTIALS_MASTER_KEY` (vault L9-11). Sin clave
  maestra, `seal` y `open` fallan cerrados.

## 7. RNC TEST `133306001` vs RNC real `133080206` — CONFIRMADO

Son valores distintos y se usan en ámbitos distintos:

- `133306001` aparece en las pruebas y en la política de identidad de TEST
  (`dosa-certification-intent.spec.ts`, `dosa-certification-intent.controller.spec.ts`).
- `133080206` es el RNC real de FULLTECH, SRL, usado en las pruebas del cliente
  de sesiones.
- En emisión, el RNC de prueba se inyecta con `DOSA_TEST_RNC` y se contrasta con
  la identidad del emisor antes de enviar (`verifyFiscalIdentity`).

Ninguna prueba confunde ambos valores: no hay ninguna constante compartida que
pueda filtrar el RNC real a un entorno de pruebas.

## 8. Adaptador fiscal y selección de credenciales — CONFIRMADO

`dosa-emission-key-selection.spec.ts` cubre la selección por empresa, RNC y
entorno; `dosa-emission.spec.ts` cubre el flujo completo con transporte
simulado. El adaptador emite con el catálogo DGII corregido (ver
`docs/ecf/research/DOSA_EMISSION_API_2026-11.md`).

## 9. Reintentos, respuestas inciertas, e-NCF y anti-duplicación — CONFIRMADO

- El e-NCF es la llave de idempotencia del proveedor; el reintento con el mismo
  JSON es seguro salvo rechazo con número gastado.
- Timeout y 5xx se tratan como **inciertos**: no se reintenta a ciegas ni se
  genera un e-NCF nuevo automáticamente.
- La barrera bloquea el envío si el cuerpo no es coherente (totales, indicadores,
  unidad fuera de catálogo).
- `dosa-webhook-atomicity.spec.ts` cubre la repetición de eventos:
  «repetir un evento autenticado responde duplicate sin reprocesar».

## 10. Evidencia para la futura prueba de emisión TEST

Todo lo necesario para ejecutarla está simulado y probado **sin red**. Para la
prueba autorizada faltará:

1. `DOSA_TEST_API_KEY` válida y `DOSA_TEST_RNC=133306001`.
2. Confirmación del proveedor de que una clave TEST produce comprobantes de
   `testecf`.
3. `DOSA_EMISSION_ENVIRONMENT=TEST` y `DOSA_EMISSION_ENABLED` encendido solo
   durante la ventana.
4. Un `eNCF` de prueba asignado a mano (no consumir la secuencia real).

## 11. Bloqueos restantes

| # | Bloqueo | Quién lo desbloquea |
| --- | --- | --- |
| B1 | **Fórmula HMAC** | **RESUELTA** por DOSA el 2026-11-04 |
| B2 | Unidad del timestamp (`s` o `ms`) y encoding del secreto | DOSA / primer evento real |
| B3 | Clave de emisión TEST real por empresa | Ya entregada para RNC `133306001`; configurar en UAT |
| B4 | Confirmación de que una clave TEST emite contra `testecf` | DOSA |
| B5 | `formaPago` de la DGII no existe en el modelo fiscal | Producto |
| B6 | E43, E44 y E46 fuera del modelo de dominio | Producto |

**Ninguno de estos bloqueos se resolvió improvisando**: en todos los casos el
sistema falla cerrado y lo declara.
