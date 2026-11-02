# Webhook DOSA — contrato, topología y estado del bloqueo

Estado (2026-11-02, revalidado el mismo día con sondas `GET`): **FIRMA
CONFIRMADA E IMPLEMENTADA**. El proveedor confirmó
`X-Dosa-Signature: t=<hora>,v1=<firma>` con
`firma = HMAC-SHA256(webhookSecret, t + "." + rawRequestBody)`. La ruta
`POST /webhook/dosa` existe detrás de bandera y ningún evento puede activar
emisión.

Sigue **SIN CONFIRMAR** (no se inventa): la unidad de `t` (segundos o
milisegundos), la codificación del digest (hex o base64), la codificación del
secreto (texto literal UTF-8 o hexadecimal decodificado) y el nombre del campo
que identifica el tipo de evento. Ver `DOSA_WEBHOOK_PENDING_QUESTIONS` en
`apps/api/src/ecf/provider/dosa/dosa-webhook-signature.policy.ts`.

> **No se declara compatibilidad real con DOSA hasta recibir y verificar una
> firma auténtica del proveedor.** Todo lo verificado aquí es local (cuerpos
> sintéticos y firmas generadas por nosotros).

---

## 1. Topología verificada del dominio (sondas del 2 de noviembre de 2026)

`fullposcloud.fulltechrd.com` resuelve a **31.97.99.70** (mismo servidor que el
API). Lo sirve el contenedor nginx del PWA, **no** el backend NestJS.

Sondas ejecutadas (solo `GET`, sin credenciales, sin enviar datos, sin modificar
nginx):

| Ruta | Código | Content-Type | Qué es |
| --- | --- | --- | --- |
| `/api/health` | 200 | `application/json` | API NestJS |
| `/api/webhook/dosa` | **404** | **`application/json`** | **API NestJS**: la ruta existe, pero `GET` no es su método |
| `/webhook/dosa` | **200** | **`text/html`** | **Fallback SPA del PWA** (nginx) |

Conclusiones:

1. **La URL que sugirió DOSA (`https://fullposcloud.fulltechrd.com/webhook/dosa`)
   NO llega al API.** nginx responde `200 text/html` con la página del PWA. Es el
   peor escenario posible: el proveedor vería un 2xx y daría el evento por
   entregado sin que se haya procesado nada.
2. El prefijo `/api` sí se reenvía al API. `@Controller()` del backend no usa
   prefijo global, así que nginx **elimina** `/api` antes de reenviar (prueba:
   `GET /api/health` responde `{"status":"ok"}` del `HealthController`, cuya ruta
   real es `/health`).
3. `/api/webhook/dosa` responde JSON (no HTML) incluso con un método que no
   corresponde: la petición la atiende NestJS, no nginx. Ese es el discriminante
   que se puede comprobar sin escribir nada.
4. **URL correcta para el webhook:**
   `https://fullposcloud.fulltechrd.com/api/webhook/dosa`
   → llega al API como `POST /webhook/dosa`.

> Pendiente de confirmar con quien administra el proxy: si el bloque `/api` de
> nginx tiene límite de tamaño de cuerpo o algún filtro que afecte al `POST`, y si
> el `verify` de `express.json` recibe los bytes tal cual. No se modifica nginx
> sin autorización explícita.

### Qué queda para declarar la ruta operativa

- [x] La URL con `/api` alcanza NestJS (comprobado por `Content-Type`).
- [x] La firma se verifica sobre el cuerpo crudo (pruebas locales, 15 casos).
- [ ] Un `POST` real de DOSA con **su** firma. Hasta entonces no se puede
      afirmar que la unidad de `t`, la codificación del digest y la del secreto
      sean las correctas.

---

## 2. `rawBody` en NestJS — estado actual y diseño

Estado real de `apps/api/src/main.ts`:

- `NestFactory.create(AppModule, { bodyParser: false })`.
- `app.use(express.json({ limit: bodySizeLimit, verify }))` — **la captura del
  cuerpo crudo YA está aplicada**, con `verify` limitado por ruta a los prefijos
  `/webhook/` y `/api/webhook/`; fuera de ellos no se toca nada.
- **Consecuencia: el webhook sí conserva los bytes exactos** en `req.rawBody`, que
  es lo que consume `verifyDosaSignature`.

Código real (resumen de `apps/api/src/main.ts`):

```ts
// Cuerpo CRUDO solo para el webhook de DOSA: la firma se calcula sobre los
// bytes EXACTOS recibidos, sin normalizar.
const rawBodyPathPrefixes = ["/webhook/", "/api/webhook/"];

app.use(
  express.json({
    limit: bodySizeLimit,
    verify: (req: Request & { rawBody?: Buffer }, _res, buf) => {
      const url = req.originalUrl ?? req.url ?? "";
      if (rawBodyPathPrefixes.some((prefix) => url.startsWith(prefix))) {
        req.rawBody = Buffer.from(buf);
      }
    },
  }),
);
```

Motivos del diseño:

- El `verify` es **por ruta**: no cambia el parseo del resto de la API.
- Se guarda el `Buffer` tal cual, sin normalizar: una firma sobre bytes
  normalizados no valida sobre los bytes recibidos.
- No se usa `raw-body` ni se duplica el parseo: un segundo parser consumiría el
  stream y rompería el resto.

---

## 3. Qué falta del proveedor (no se inventa)

`DOSA_SIGNATURE_CONTRACT_PENDING` en
`apps/api/src/ecf/provider/dosa-webhook.contract.ts`:

1. Algoritmo exacto. **No se asume HMAC-SHA256 ni ninguna variante.**
2. Qué se firma: cuerpo crudo, normalizado, o un resumen (y de qué campos).
3. Si hay marca de tiempo, su formato y si entra en el cálculo.
4. Codificación del valor de `X-Dosa-Signature` (hex, base64, prefijo de versión).
5. Ventana de tolerancia anti-replay que acepta el proveedor.
6. Alcance del secreto: por empresa, por entorno o compartido por partner.

---

## 4. Qué está implementado y qué no

El paquete de traspaso del proveedor llegó el 2 de noviembre de 2026 (muestra
real del evento, secreto de 64 hex, API Key de TEST). Con esa evidencia se
sustituyó el bloqueo total por un endpoint **real, apagado por bandera y que
falla cerrado**.

Implementado:

| Archivo | Qué hace |
| --- | --- |
| `provider/dosa/dosa-webhook.dto.ts` | Validador estricto del payload real (`postulacion_id`, `rnc`, `razon_social`, `correo`, `ambiente`, `estado_certificacion`, `credenciales`, `credenciales_pendientes`, `disponibles_desde`). Devuelve los secretos por separado y una versión **redactada** para persistir. |
| `provider/dosa/dosa-webhook-signature.policy.ts` | Estrategia intercambiable. Por defecto `BLOCKED`; `UNVERIFIED_PLAINTEXT_SECRET` existe solo para pruebas sintéticas y está marcada como no verificada. Comparación con `timingSafeEqual`. |
| `provider/dosa/dosa-webhook.service.ts` | Pipeline firma → `rawBody` → esquema → RNC → opt-in e-CF → `INSERT … ON CONFLICT DO NOTHING`. **Nunca** activa emisión ni cambia el estado de la sesión. |
| `provider/dosa/dosa-company-resolver.service.ts` | Correlación `RNC → companyId` desde `ecf_dosa_certification_sessions` + `ecf_company_configurations`. Cero o más de una fila ⇒ no resuelve. |
| `provider/dosa/dosa-webhook.controller.ts` | `POST /webhook/dosa`. `DOSA_WEBHOOK_ENABLED` debe valer `true`. Todas las respuestas son JSON con código explícito; **nunca** 200 HTML. |
| `prisma/migrations/20261102180000_ecf_dosa_webhook_events` | Tabla `ecf_dosa_webhook_events` con índice único `(company_id, dedupe_key)`. |
| `provider/dosa/dosa-webhook.spec.ts` | 29 pruebas de falsificación, replay, duplicado, esquema, secretos cruzados, falta de firma, doble entrega y empresa sin e-CF. |
| `provider/dosa/dosa-webhook-postgres.integration-spec.ts` | 8 pruebas contra PostgreSQL real (doble entrega ⇒ una sola fila; credenciales ausentes de la fila; sesión intacta). |

**Sigue sin implementarse a propósito:**

- Verificación criptográfica real de la firma. `DOSA_WEBHOOK_SIGNATURE_STRATEGY`
  queda en `BLOCKED` hasta que el proveedor documente el algoritmo.
- Persistencia de las credenciales que llegan en el evento. Se validan, se
  redactan y se descartan; escribirlas en el gestor de secretos es un acto
  humano posterior.
- Cualquier llamada saliente a DOSA.

Garantías que ya se prueban automáticamente:

- Sin cabecera de firma, con estrategia `BLOCKED` o con firma falsificada ⇒ 503
  y cero filas escritas.
- Payload fuera de esquema ⇒ 400. RNC desconocido ⇒ 404. Empresa sin e-CF ⇒ 409.
- La segunda entrega del mismo evento devuelve `duplicate: true` y no reprocesa.
- El valor de `api_key_produccion`, `api_key_test`, `api_secret` y del secreto
  del webhook no aparece ni en la fila persistida ni en la respuesta.
- Un evento con `estado_certificacion=finalizado` y firma válida **no** emite el
  SQL que tocaría la sesión ni la configuración de la empresa.

---

## 5. Reglas de vinculación multiempresa

`FullPOS Empresa → RNC propio → Postulación DOSA → Credenciales (referencia)`

- La vinculación se almacena en el servidor. El evento **nunca** aporta
  `companyId`.
- RNC desconocido ⇒ `UNKNOWN_RNC`. **No hay empresa por defecto.**
- Dos vinculaciones con el mismo RNC ⇒ `AMBIGUOUS_RNC` (no se elige la primera).
- `providerRnc` distinto de `companyTaxId` ⇒ `IDENTITY_MISMATCH`. Esto es lo que
  impide que la cuenta Partner de FULLTECH sustituya la identidad del cliente.
- Entornos separados: una vinculación `test` no resuelve en `production`.
- Deduplicación con clave `dosa:<companyId>:<eventId>` e índice único
  `(companyId, eventId)` cuando exista la tabla.
- Los secretos viven solo en el backend, por referencia
  (`ecf-secret-resolver.service.ts`); nunca viajan al cliente ni a los logs.

> **No se asume** que la API Key de TEST sirva para facturar bajo cualquier RNC.
> La clave de TEST que entregó DOSA es de una empresa de pruebas, no de FULLTECH
> SRL, y la resolución de arriba lo hace explícito.

---

## 6. Cómo se enciende (y qué falta para hacerlo)

La ruta existe pero está apagada. Para activarla en TEST:

1. `DOSA_WEBHOOK_ENABLED=true` en el entorno del API (variable, no commit).
2. `DOSA_WEBHOOK_SECRET` con el secreto entregado, por referencia.
3. `DOSA_WEBHOOK_SIGNATURE_STRATEGY` **sigue en `BLOCKED`** hasta que el
   proveedor documente el algoritmo. Sin ese documento, encender la bandera deja
   el endpoint en 503 para todo evento real: es el comportamiento correcto.
4. La URL a registrar en DOSA es
   `https://fullposcloud.fulltechrd.com/api/webhook/dosa` (el proxy elimina
   `/api`). La URL sugerida por el proveedor, `/webhook/dosa`, hoy devuelve la
   SPA y **no** debe usarse tal cual. No se toca nginx de producción para esto.
5. Tras el primer evento real: comprobar la fila en `ecf_dosa_webhook_events`,
   que `payload_summary` solo contenga `[REDACTED]`, y que
   `ecf_dosa_certification_sessions` siga en su estado anterior.
6. El evento entra como **evidencia**, nunca como autorización de emisión. La
   activación sigue siendo un acto humano con comprobaciones fiscales.
