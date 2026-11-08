# Auditoría del webhook de DOSA — 07/11/2026

Revisión del camino completo de un evento entrante de DOSA, con **cada** punto
donde puede fallar y qué se observa en cada caso. El objetivo es que ningún fallo
llegue por sorpresa.

Sin cambios de contrato, sin datos tocados. Solo se añadió registro de rechazos
(ver §7).

## 1. Estado actual: el webhook está APAGADO

`POST /webhook/dosa` responde **503** con `ECF_DOSA_WEBHOOK_DISABLED` mientras
`DOSA_WEBHOOK_ENABLED` no sea exactamente `true`.

Consecuencia si se queda así: **ninguna credencial nueva entra al sistema**. El
cliente completa el asistente, DOSA intenta avisar, y el sistema lo rechaza sin
guardar nada. El estado del cliente se queda en «DOSA aún no ha confirmado».

## 2. Ruta correcta — DEMOSTRADA

| Dato | Valor |
| --- | --- |
| Ruta interna | `POST /webhook/dosa` |
| URL pública | `https://fullposcloud.fulltechrd.com/api/webhook/dosa` |
| `rawBody` | Se preserva para `/webhook/` **y** `/api/webhook/` |

No es una suposición: son sondas de solo lectura ejecutadas el 2026-11-04 contra
el dominio público.

```text
/api/health              -> 200 application/json
/api/webhook/dosa        -> 404 application/json   (NestJS alcanzado; GET no es su método)
/webhook/dosa            -> 200 text/html          (PWA: no usar)
```

La ruta que sugirió el proveedor (`/webhook/dosa`, sin `/api`) la sirve el PWA y el
evento nunca llega al backend. **La ruta no se cambia**: ya está demostrado cuál
funciona.

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

1. **Encender el webhook** en el ambiente: `DOSA_WEBHOOK_ENABLED=true` +
   `DOSA_WEBHOOK_SIGNATURE_STRATEGY=HMAC_SHA256_TIMESTAMPED` +
   `DOSA_WEBHOOK_SECRET`.
2. **Confirmar P1, P5 y la rotación** con el proveedor. Mientras no se confirmen,
   el primer evento real será la prueba: si llega `MISMATCH`, cambiar
   `DOSA_WEBHOOK_SECRET_ENCODING`; si llega `TIMESTAMP_OUT_OF_TOLERANCE`, cambiar
   `DOSA_WEBHOOK_TIMESTAMP_UNIT`.
3. **Registrar la URL pública correcta** (`/api/webhook/dosa`) en el panel de
   DOSA, no la que sugirieron.
