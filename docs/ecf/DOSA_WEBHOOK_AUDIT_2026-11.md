# Auditoría del webhook de DOSA — 07/11/2026

Revisión del camino completo de un evento entrante de DOSA, con **cada** punto
donde puede fallar y qué se observa en cada caso. El objetivo es que ningún fallo
llegue por sorpresa.

Sin cambios de contrato, sin datos tocados. Solo se añadió registro de rechazos
(ver §7).

> **Hallazgo de la conversación con el proveedor (07/11/2026):** el webhook ya
> está **encendido y funcionando en producción**. Llegaron eventos reales, la
> validación **HMAC pasó** y se respondió 200. Eso **resuelve P1 y P5 con
> evidencia real**, no por diseño. Ver §10.
>
> El bloqueo que queda es otro: la deduplicación desplegada ignora el contenido,
> así que el **reenvío corregido con la llave TEST se descartó como
> `duplicate: true`**. El arreglo existe en este árbol y **no está desplegado**.

## 1. Comportamiento por defecto: apagado (en producción ya está encendido)

Por defecto `POST /webhook/dosa` responde **503** con
`ECF_DOSA_WEBHOOK_DISABLED` mientras `DOSA_WEBHOOK_ENABLED` no sea exactamente
`true`. Ese interruptor sigue siendo el correcto como valor por defecto.

**En producción ya se encendió**, y el 06/11 se recibieron eventos reales con
respuesta 200 (§10.1). Consecuencia: el camino de recepción está probado en
realidad, no solo en tests.

## 2. Ruta correcta

| Dato | Valor |
| --- | --- |
| Ruta interna | `POST /webhook/dosa` |
| URL preferida | `https://fullposcloud.fulltechrd.com/api/webhook/dosa` |
| URL en uso por DOSA | `https://fullposcloud.fulltechrd.com/webhook/dosa` (también funciona) |
| `rawBody` | Se preserva para `/webhook/` **y** `/api/webhook/` |

Sondas de solo lectura del 2026-11-04:

```text
/api/health              -> 200 application/json
/api/webhook/dosa        -> 404 application/json   (NestJS alcanzado; GET no es su método)
/webhook/dosa            -> 200 text/html          (GET: lo sirve el PWA)
```

El `200 text/html` del GET hizo pensar que esa ruta no servía. **El tráfico real
del 06/11 demuestra lo contrario**: un `POST /webhook/dosa` sí llega a NestJS y
sí procesa el evento (§10.1). Ambas URLs son válidas; `/api/webhook/dosa` es la
preferida porque es explícita.

## 3. Verificación de firma

Contrato confirmado por DOSA el 2026-11-02:

```
Cabecera : X-Dosa-Signature
Formato  : t=<hora>,v1=<firma>
Firma    : HMAC-SHA256(webhookSecret, t + "." + rawBody)
```

Se calcula sobre los **bytes originales** recibidos, nunca sobre el JSON
re-serializado.

### Estrategias

| Estrategia | Comportamiento |
| --- | --- |
| `BLOCKED` (**por defecto**) | Ningún evento se considera auténtico |
| `HMAC_SHA256_TIMESTAMPED` | La real del contrato confirmado |
| `UNVERIFIED_PLAINTEXT_SECRET` | Solo laboratorio local; fuera de ahí degrada a `BLOCKED` |

Es decir: **con la configuración por defecto, todo evento se rechaza con 503
`STRATEGY_BLOCKED`** aunque la bandera esté encendida. Encender requiere las dos
cosas: `DOSA_WEBHOOK_ENABLED=true` **y**
`DOSA_WEBHOOK_SIGNATURE_STRATEGY=HMAC_SHA256_TIMESTAMPED` con
`DOSA_WEBHOOK_SECRET` configurado.

## 4. P1 y P5 — RESUELTOS POR DISEÑO (07/11/2026)

En el repositorio **no existe ninguna muestra real** de la cabecera ni del secreto,
y los eventos recibidos no guardaron el valor de `t`, así que la respuesta no
podía salir de la evidencia. Se resolvieron por diseño, sin relajar la seguridad:

| # | Duda | Cómo queda | Garantía |
| --- | --- | --- | --- |
| P1 | ¿`t` en segundos o milisegundos? | Se **deduce por magnitud**: `>= 1e11` → ms | Si el valor es ambiguo está a miles de años de «ahora» y la ventana de 300 s lo rechaza igual |
| P2 | ¿El digest en hex o base64? | Se aceptan **ambos** | La firma debe ser el HMAC exacto |
| P5 | ¿El secreto es texto o 32 bytes hex? | Se aceptan **las dos lecturas acotadas** del mismo secreto | Es el mismo HMAC exacto con una clave derivada del mismo secreto |
| — | ¿Hay rotación de secreto? ¿varios `v1`? | **Pendiente**: no soportado | Durante una rotación habrá rechazos |

Ajustes explícitos siguen disponibles y **mandan** sobre la deducción:
`DOSA_WEBHOOK_TIMESTAMP_UNIT=seconds|milliseconds` y
`DOSA_WEBHOOK_SECRET_ENCODING=utf8|hex`.

Además, cada evento autenticado deja en el log la interpretación que lo validó:

```
LOG [DosaWebhookService] Webhook DOSA autenticado: t=seconds, secreto=utf8
```

Eso convierte una duda en un hecho en la primera entrega real, sin preguntar a
nadie y sin registrar el secreto ni la firma.


## 5. Todos los códigos de rechazo

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `ECF_DOSA_WEBHOOK_DISABLED` | 503 | Bandera apagada |
| `ECF_DOSA_WEBHOOK_BLOCKED` / `STRATEGY_BLOCKED` | 503 | Estrategia sin configurar (defecto) |
| `ECF_DOSA_WEBHOOK_BLOCKED` / `SECRET_NOT_CONFIGURED` | 503 | Falta `DOSA_WEBHOOK_SECRET` |
| `ECF_DOSA_WEBHOOK_BLOCKED` / `CONFIG_INVALID` | 503 | Configuración ilegible |
| `ECF_DOSA_WEBHOOK_BLOCKED` / `SIGNATURE_HEADER_MISSING` | 401 | No vino la cabecera |
| `…` / `SIGNATURE_HEADER_MALFORMED` | 401 | Formato distinto de `t=…,v1=…` |
| `…` / `SIGNATURE_TIMESTAMP_INVALID` | 401 | `t` no es un número |
| `…` / `SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE` | 401 | Fuera de la ventana (300 s por defecto) |
| `…` / `SIGNATURE_ALGORITHM_UNSUPPORTED` | 401 | `v1` distinto de HMAC-SHA256 |
| `…` / `SIGNATURE_MISMATCH` | 401 | La firma no coincide |
| `ECF_DOSA_WEBHOOK_RAW_BODY_MISSING` | 400 | No se pudo leer el cuerpo crudo |
| `ECF_DOSA_WEBHOOK_INVALID_PAYLOAD` | 400 | Esquema inválido (campo en el motivo) |
| `ECF_DOSA_WEBHOOK_UNKNOWN_RNC` | 404 | El RNC no corresponde a ninguna empresa |
| `ECF_DOSA_WEBHOOK_ECF_DISABLED` | 409 | Empresa sin e-CF y sin inscripción |

Ninguno de estos deja fila en la base: **el evento se descarta**.

## 6. Camino cuando la firma SÍ es válida

```
firma válida
  → esquema válido
  → RNC conocido
  → e-CF habilitado o empresa inscrita
  → se guarda el evento y se ingiere la credencial CIFRADA
  → estado PENDING_CONFIRMATION
```

Estados de `ecf_dosa_webhook_events.processing_state`:

| Estado | Significado |
| --- | --- |
| `PENDING_CREDENTIALS` | Autenticado y guardado, pero las credenciales no se pudieron escribir |
| `COMPLETE` | Procesado por completo |
| `CONFLICT_PENDING_REVIEW` | Llegó una credencial que choca con la vigente: **no se sustituye** y pasa a revisión |

Una credencial `ACTIVE` **nunca** se reemplaza porque un webhook lo diga.

Incidencias que el barrido genera para lo anterior (visibles en
`GET /ecf/platform/dosa/incidents`):

| Tipo | Severidad |
| --- | --- |
| `EVENT_CREDENTIALS_NOT_STORED` | ALTA |
| `CREDENTIAL_CONFLICT_REVIEW` | ALTA |
| `CREDENTIAL_AWAITING_CONFIRMATION` | MEDIA |
| `POSTULATION_NOT_BOUND` | BAJA |
| `EVENT_TYPE_UNKNOWN` | BAJA |

## 7. Hueco encontrado y CORREGIDO en esta auditoría

El servicio **no registraba nada** cuando rechazaba un evento: ni fila, ni log,
ni incidencia. Un webhook mal configurado fallaba en silencio absoluto; el único
síntoma era un cliente esperando credenciales que nunca llegaban.

Ahora cada rechazo deja una línea `WARN` con el código y el motivo:

```
WARN [DosaWebhookService] Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_BLOCKED / STRATEGY_BLOCKED (estrategia BLOCKED)
WARN [DosaWebhookService] Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_UNKNOWN_RNC / rnc=133306001
WARN [DosaWebhookService] Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_INVALID_PAYLOAD / MISSING_FIELD:rnc
WARN [DosaWebhookService] Webhook DOSA rechazado: ECF_DOSA_WEBHOOK_ECF_DISABLED / company=…
```

Se registran **solo** código y motivo: nunca el cuerpo, ni cabeceras, ni el
secreto, ni el valor de la firma.

## 8. Verificación

```
npx jest --runInBand --testPathPatterns "dosa-webhook"  → 7 suites · 127 PASS
```

Cubren: firma válida e inválida, cabecera ausente y mal formada, fuera de
tolerancia, algoritmo no soportado, cuerpo crudo ausente, esquema, RNC
desconocido, empresa sin e-CF, idempotencia, conflicto de credenciales y
atomicidad.

## 9. Pendientes que no son código

1. **Desplegar el arreglo de deduplicación** (ver §10.4). Sin eso, cualquier
   reenvío corregido de DOSA se sigue descartando como duplicado.
2. **Confirmar la rotación** con el proveedor (P1 y P5 ya no son bloqueantes:
   resueltos con evidencia real, ver §10.2).

## 10. Evidencia real de la conversación con el proveedor

Revisión de los exports de WhatsApp con el contacto de DOSA y de los archivos
adjuntos. Lo importante aquí es que hay **tráfico real** de por medio, no
suposiciones.

### 10.1 La URL registrada en DOSA funciona: `/webhook/dosa` (sin `/api`)

El 05/11 el proveedor reportó **HTTP 405 en 4 intentos** contra
`https://fullposcloud.fulltechrd.com/webhook/dosa`. Ese dato hizo pensar que la
ruta era incorrecta.

**El tráfico del 06/11 lo desmiente.** Ese mismo día llegaron eventos reales a
esa misma URL y el backend los procesó:

| Hora (RD) | Respuesta | Código | Origen |
| --- | --- | --- | --- |
| 17:13:14 | HTTP 400 | `ECF_DOSA_WEBHOOK_INVALID_PAYLOAD` / `MISSING_FIELD:postulacion_id` | nuestro |
| 17:13:15 | HTTP 400 | `ECF_DOSA_WEBHOOK_INVALID_PAYLOAD` / `MISSING_FIELD:estado_certificacion` | nuestro |
| 19:27 | **HTTP 200** | credenciales aceptadas | nuestro |

`ECF_DOSA_WEBHOOK_INVALID_PAYLOAD` es un código **nuestro**: si aparece, la
petición atravesó nginx y llegó a NestJS. Por tanto:

- `/webhook/dosa` **sin `/api` es alcanzable y funciona**. El 405 del 05/11 fue
  un estado transitorio (despliegue anterior o configuración intermedia), no un
  error de ruta permanente.
- No hace falta cambiar nada en el panel de DOSA por este motivo.
- Conclusion: la URL no era la causa final. La causa fue el **contrato del
  payload**, que el proveedor corrigió el 06/11 a las 16:52 («era un campo que
  faltaba, se lo agregué al webhook»).

### 10.2 P1 y P5 quedan resueltos con evidencia real

El proveedor recibió y comentó nuestros códigos de error, y el mensaje de
respuesta aclara el punto decisivo:

> «Ambas solicitudes **pasaron la validación HMAC**, pero nuestro sistema no
> encontró esos campos en el nivel principal del JSON.»

Es decir: con la configuración que estaba en producción, la firma real de DOSA
**verificó correctamente**. Un evento real, firmado por el proveedor, fue
validado. Entonces:

- **P1 (unidad de `t`) — RESUELTO.** Si `t` viniera en la unidad equivocada
  habría saltado `TIMESTAMP_OUT_OF_TOLERANCE` o la firma no habría coincidido.
  No ocurrió. La unidad que llega es la que el verificador acepta.
- **P5 (lectura del secreto) — RESUELTO.** Si la lectura fuera la incorrecta
  habría fallado el HMAC con `MISMATCH`. No ocurrió.
- La detección automática (§4) queda como red de seguridad para otra empresa u
  otro formato, pero **ya no hace falta esperar ninguna confirmación escrita**.

No hay que cambiar `DOSA_WEBHOOK_TIMESTAMP_UNIT` ni `DOSA_WEBHOOK_SECRET_ENCODING`.

### 10.3 Confirmaciones de contrato

- `X-Dosa-Signature` **no** contiene el secreto: es un HMAC-SHA256 con formato
  `t=<hora>,v1=<firma>` sobre `t + "." + cuerpo` (02/11 y 05/11).
- El digest de `v1` va **en hex** («HMAC-SHA256 en hex de `t.cuerpo`», 05/11).
  Nuestro verificador ya aceptaba hex y base64.
- El payload real lleva `postulacion_id`, `rnc`, `razon_social`, `correo`,
  `ambiente`, `estado_certificacion`, `credenciales` (`api_key_produccion`,
  `api_key_test`, `api_secret`), `credenciales_pendientes`, `disponibles_desde`.
  **No trae campo de tipo de evento**: por eso existe `classifyDosaEventType`.
- El 06/11 el proveedor pidió aceptar `postulacion_id` y `estado_certificacion`
  en `null` en el primer evento de conexión (`empresa.conectada`).
- Requisito operativo del 05/11: responder 200 en **menos de 8 segundos**.

### 10.4 El bloqueo real: la deduplicación descarta el reenvío corregido

El 07/11 a las 09:52 el proveedor generó la llave TEST que faltaba y reenvió el
evento:

> «Ya la activamos y les reenviamos el webhook `empresa.credenciales` con las dos
> llaves (producción y test). Su receptor respondió 200, pero lo marcó como
> `duplicate: true`, así que es posible que no haya guardado la llave nueva.»

**Ese diagnóstico del proveedor es correcto, y la causa está verificada en el
código desplegado.** La versión que corre en producción compone la clave de
idempotencia así:

```ts
`${payload.postulacionId}|${payload.estadoCertificacion}|${payload.disponiblesDesde}`
```

El reenvío corregido trae el **mismo** `postulacion_id`, el **mismo**
`estado_certificacion` y el **mismo** `disponibles_desde`; solo cambia el
contenido de `credenciales`. La clave resultante es idéntica, el `ON CONFLICT DO
NOTHING` no inserta nada y la respuesta es `duplicate: true`. **La llave TEST
nunca se guardó.**

Este árbol ya lo corrige: la clave incluye además el hash del cuerpo exacto
(`rawBodySha256`), de modo que un reenvío idéntico sigue siendo duplicado pero un
reenvío con **contenido distinto** se procesa como evento propio.

```ts
`${payload.postulacionId}|${payload.estadoCertificacion}|${payload.disponiblesDesde}|${rawBodySha256}`
```

Verificado: el arreglo está en el commit `497636c9` y **solo existe en esta rama
local**. `integration/ecf-into-production`, `ultimos-trabajos` y
`feature/ecf-alanube` conservan la versión sin el hash. Por eso el reenvío se
perdió.

**Para cerrar:** desplegar un build con `497636c9`, pedir a DOSA que reenvíe
`empresa.credenciales`, y luego activar la llave TEST (llega como
`PENDING_CONFIRMATION`, no activa).

### 10.5 Seguridad

En el export aparece un archivo con el secreto del webhook. No se copió al
repositorio y su valor no se imprimió en ningún momento; solo se verificó su
forma (64 caracteres hex). Está en una carpeta de Descargas sin cifrar: conviene
retirarlo de ahí y de cualquier archivo compartido.


