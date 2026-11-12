# DOSA — estado REAL del contrato (verificado el 2026-11-07)

Este documento separa lo que está **demostrado** de lo que sigue **sin
confirmar**. La regla es simple: si algo no está respaldado por una muestra del
proveedor, por su confirmación escrita o por una prueba reproducible, aquí se
declara **NO VERIFICADO**. No se rellena con suposiciones.

## 1. Lo que está confirmado

| Elemento | Estado | Evidencia |
| --- | --- | --- |
| Cabecera de firma `X-Dosa-Signature` | CONFIRMADO | `dosa-webhook-signature.policy.ts` + `dosa-webhook-hmac.spec.ts` (20 casos) |
| Formato `t=<hora>,v1=<firma>` | CONFIRMADO (proveedor, 2026-11-04) | `docs/ecf/research/DOSA_WEBHOOK_AND_TEST_EMISSION_STATUS.md` §2 |
| `firma = HMAC-SHA256(secreto, t + "." + cuerpoCrudo)` | CONFIRMADO (proveedor, 2026-11-04) | Igual + prueba de que un cuerpo re-serializado NO valida |
| Estructura de `credenciales` | CONFIRMADO por muestra real | `03_WEBHOOK_EJEMPLO_SANITIZADO.json` → `dosa-webhook.dto.ts` |
| `credenciales` = `{ api_key_produccion, api_key_test, api_secret }` | CONFIRMADO por muestra real | El DTO los lee con esos nombres exactos |
| Endpoint de sesiones de certificación | CONFIRMADO | `DOSA_SESSION_DEFAULT_BASE_URL = https://dosasystem.com` |
| Endpoint de emisión (`EnviarFactura`) | CONFIRMADO | `dosa-emission.client.ts` (`emissionPathFor`) |
| `postulacion_id` y `estado_certificacion` pueden llegar en `null` | CONFIRMADO (proveedor, 2026-11-06) | `dosa-webhook.dto.ts` (`nullableText`) + `dosa-webhook-connection-event.spec.ts` (18 casos) |

### Estructura de `empresa.credenciales` (la muestra real)

```json
{
  "postulacion_id": "…",
  "rnc": "…",
  "razon_social": "…",
  "correo": "…",
  "ambiente": "Produccion",
  "estado_certificacion": "finalizado",
  "credenciales": {
    "api_key_produccion": "…",
    "api_key_test": "…",
    "api_secret": "…"
  },
  "credenciales_pendientes": false,
  "disponibles_desde": "2026-11-01T22:50:12Z"
}
```

Consecuencias que ya están en el código:

- **Las dos API Keys llegan juntas** en el mismo evento, cada una con su
  ambiente implícito. Por eso la fila de credenciales se parte por clave
  (`dosa-credential-environments.ts`) y no por el `ambiente` del evento.
- **Un solo `api_secret`** para los dos ambientes. Si DOSA emitiera secretos
  distintos, el modelo actual no podría representarlo (ver §3).

### Estructura de `empresa.conectada` y `webhook.prueba`

Confirmado por el proveedor el 2026-11-06:

> «Solo les pedimos que su receptor acepte `postulacion_id` y
> `estado_certificacion` en `null` en el primer evento de conexión
> (`empresa.conectada`) y en el de prueba de firma (`webhook.prueba`), porque en
> ese momento todavía no existe el proceso de certificación.»

```json
{
  "postulacion_id": null,
  "rnc": "…",
  "razon_social": "…",
  "correo": "…",
  "ambiente": "Produccion",
  "estado_certificacion": null
}
```

Y, según el mismo mensaje, **solo los eventos de llaves traen
`disponibles_desde`** («los de llaves traen además `disponibles_desde`»).

Regla del receptor, ya implementada:

| Campo | Ausente / `null` | Presente con tipo válido | Presente con tipo inválido |
| --- | --- | --- | --- |
| `postulacion_id` | Aceptado (`null`) | Aceptado | Rechazado (400) |
| `estado_certificacion` | Aceptado (`null`) | Aceptado | Rechazado (400) |
| `disponibles_desde` | Aceptado (`null`) | Aceptado si es fecha | Rechazado (400) |
| `credenciales_pendientes` | Aceptado (`false`) | Aceptado si es booleano | Rechazado (400) |
| `rnc` | **Rechazado (400)** | Aceptado | Rechazado (400) |
| `razon_social` | **Rechazado (400)** | Aceptado | Rechazado (400) |

La identidad y la correlación siguen siendo obligatorias; solo se relajan los
campos que el proveedor no puede rellenar antes de que exista postulación.
Ninguno de los relajados autoriza nada: la empresa sale del RNC (server-side), la
firma se verifica antes y las credenciales viajan solo en los eventos de llaves.

## 2. Lo que NO está verificado

| # | Pregunta | Por qué importa | Estado (2026-11-07) |
| --- | --- | --- | --- |
| P1 | ¿`t` está en segundos o milisegundos? | Elegir mal rechaza TODOS los eventos | **RESUELTO por diseño**: se deduce por magnitud (`>= 1e11` → ms). El ajuste explícito sigue disponible |
| P2 | ¿El secreto de 64 hex se usa como texto literal o como 32 bytes decodificados? | Elegir mal rechaza TODAS las firmas | **RESUELTO por compatibilidad acotada**: se aceptan las dos lecturas del mismo secreto |
| P3 | ¿Existe un **identificador único de entrega**? | Hoy la deduplicación usa `sha256(postulación + estado + disponibles_desde + hash del cuerpo)` | No hay campo; se deduce del contenido |
| P4 | ¿Existe un campo que diga el **tipo de evento**? | Hoy `event_type` se guarda como `PENDING_CLASSIFICATION` | La muestra no lo trae |
| P5 | ¿Hay más tipos de evento además de la entrega de credenciales? | Condiciona el contrato del receptor | **CONFIRMADO por el proveedor (2026-11-06)**: existen al menos `empresa.conectada` (conexión), `webhook.prueba` (prueba de firma) y `empresa.credenciales` (llaves). Los dos primeros llegan con `postulacion_id` y `estado_certificacion` en `null` |
| P6 | ¿`api_secret` es único por empresa o distinto por ambiente? | Si es distinto, C2 del informe es un riesgo real | Un solo secreto en la muestra |
| P7 | Política de reintento: ¿cuántos, cada cuánto, re-firando? | Un reintento con `t` viejo siempre falla (ver §4) | Observado ≈5 min; no confirmado |
| P8 | ¿Hay reenvío manual (*replay*) desde el panel? | Define cómo se recupera un evento perdido | No documentado |
| P9 | Procedimiento autorizado de rotación y revocación | Rotar sin guía puede dejar la empresa sin emitir | No documentado |
| P10 | ¿TEST y PRODUCCIÓN comparten host? | Hoy solo existe `DOSA_BASE_URL` | Un único host configurable |
| P11 | Condiciones exactas de activación de una credencial | Ninguna empresa recibe credenciales nuevas sin esto | No documentado por el proveedor |

### Cómo se resolvieron P1 y P2 sin confirmación del proveedor

Ninguna de las dos admitía una respuesta por evidencia: en el repositorio no
existe **ninguna muestra real** de la cabecera `X-Dosa-Signature` ni del secreto,
y los eventos que llegaron no dejaron guardado el valor de `t`. Se resolvieron por
**diseño**, sin relajar la seguridad:

- **P1**: un epoch en segundos del siglo XXI tiene 10 dígitos (~1.7e9) y uno en
  milisegundos 13 (~1.7e12). El umbral `1e11` cae en una zona donde ninguna fecha
  es plausible, así que la deducción es aritmética, no una suposición. Y si el
  valor fuera ambiguo, estaría a miles de años de «ahora»: la ventana de 300 s lo
  rechaza igual. La unidad solo cambia el **motivo** del rechazo, nunca si un
  evento caducado se acepta.
- **P2**: el secreto hex admite exactamente dos lecturas (los 64 caracteres o los
  32 bytes que codifican). Se aceptan las dos, igual que ya se aceptaba el digest
  en hex o base64. La firma sigue teniendo que ser el HMAC-SHA256 exacto del
  cuerpo exacto: el atacante necesita el mismo secreto en cualquier caso.

Ambas quedan registradas como evidencia en el log de cada evento autenticado
(`t=seconds|milliseconds, secreto=utf8|hex`), así que la primera entrega real
dirá cuál usa DOSA sin necesidad de preguntarlo.

### Discrepancia documental detectada (se reporta, no se resuelve)

`docs/ecf/DOSA_UAT_PENDING.md` §3 afirma que «ya están confirmados … el payload de
`empresa.conectada`». El código, en cambio, **no** puede clasificar el tipo de
evento: la muestra real no trae campo de tipo y `classifyDosaEventType` devuelve
`PENDING_CLASSIFICATION` a propósito. Lo confirmado es la **estructura del
payload**; lo que no existe es un campo de **tipo de evento**. Ambas cosas se
habían mezclado en la redacción. Prevalece el código, que es lo que se ejecuta.

## 3. Decisión sobre el secreto único (P6)

El modelo actual guarda **un** `api_secret` por empresa, asignado a un solo
ambiente (`dosa-credential-environments.ts`). Es la lectura literal de la
muestra real. Si DOSA confirma que emite secretos distintos por ambiente, hay que
ampliar el bundle y la tabla; hasta entonces **no se inventa** una separación que
el proveedor no ha declarado.

## 4. Códigos HTTP del webhook (cambio de esta fase)

Antes, **todo** rechazo de firma respondía `503`. Un `5xx` significa «problema
del servidor, reintenta», así que el receptor estaba pidiendo al proveedor
exactamente lo contrario de lo que ocurría: un evento con la firma caducada no se
aceptaría por mucho que se repitiera, y cada reintento llegaba **aún más
caducado**. Encaja con lo observado en producción: 28 de 112 entregas rechazadas
eran reintentos fuera de la ventana.

| Rechazo | Antes | Ahora | Razón |
| --- | --- | --- | --- |
| `SIGNATURE_HEADER_MISSING` | 503 | **401** | No autenticado: repetir igual no funciona |
| `SIGNATURE_HEADER_MALFORMED` | 503 | **401** | Ídem |
| `SIGNATURE_TIMESTAMP_INVALID` | 503 | **401** | Ídem |
| `SIGNATURE_ALGORITHM_UNSUPPORTED` | 503 | **401** | Ídem |
| `SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE` | 503 | **401** | Replay: la misma cabecera nunca valdrá |
| `SIGNATURE_MISMATCH` | 503 | **401** | Secreto distinto: reintentar no lo arregla |
| `STRATEGY_BLOCKED` | 503 | **503** | Configuración del receptor: sí es transitorio |
| `SECRET_NOT_CONFIGURED` | 503 | **503** | Ídem |
| `CONFIG_INVALID` | 503 | **503** | Ídem |
| `RAW_BODY_UNAVAILABLE` | 503 | **500** | Fallo propio, no del emisor |

La seguridad **no cambia**: el evento se rechaza en todos los casos, no se
ejecuta ninguna consulta y no se modifica ningún estado. Solo cambia lo que el
emisor entiende. La ventana anti-replay sigue en **300 s** y no se amplía.

## 5. Preguntas que hay que enviar a DOSA (mínimas)

1. Unidad de `t` en `X-Dosa-Signature` (segundos o milisegundos).
2. `api_secret`: ¿texto literal de 64 caracteres o 32 bytes decodificados de hex?
3. ¿Existe un identificador único de entrega? Si no, ¿cómo distinguen ustedes dos
   eventos del mismo día con el mismo estado?
4. ¿Existe un campo de tipo de evento y cuál es su catálogo?
5. ¿`api_secret` es único por empresa o hay uno por ambiente?
6. Política de reintento: número de intentos, intervalo y si **re-firman** con un
   `t` nuevo en cada intento.
7. ¿Ofrecen reenvío manual de una entrega? ¿Bajo qué autorización?
8. Procedimiento escrito de rotación y de revocación de credenciales.
9. ¿TEST y PRODUCCIÓN comparten host y ruta?
10. Condiciones que ustedes exigen para considerar una credencial activa.

No se ha realizado ninguna llamada real con credenciales de producción y no se ha
emitido ningún comprobante.
