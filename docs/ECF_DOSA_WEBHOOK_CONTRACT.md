# Webhook DOSA — contrato, topología y estado del bloqueo

Estado: **BLOQUEADO POR CONTRATO**. No existe ruta HTTP, no se autentica ningún
evento y ningún evento puede activar emisión.

---

## 1. Topología verificada del dominio (1 de noviembre de 2026)

`fullposcloud.fulltechrd.com` resuelve a **31.97.99.70** (mismo servidor que el
API). Lo sirve el contenedor nginx del PWA, **no** el backend NestJS.

Sondas ejecutadas (solo `GET`, sin credenciales, sin enviar datos):

| Ruta | Código | Content-Type | Qué es |
| --- | --- | --- | --- |
| `/` | 200 | `text/html` | PWA (nginx) |
| `/webhook/dosa` | **200** | **`text/html`** | **Fallback SPA del PWA** |
| `/health` | 200 | `text/html` | Fallback SPA del PWA |
| `/api/health` | **200** | **`application/json`** | **API NestJS** |
| `/api/webhook/dosa` | 404 | `application/json` | API NestJS (ruta inexistente aún) |
| `/api/ecf` | 404 | `application/json` | API NestJS |

Conclusiones:

1. **La URL que sugirió DOSA (`https://fullposcloud.fulltechrd.com/webhook/dosa`)
   NO llega al API.** nginx responde `200 text/html` con la página del PWA. Es el
   peor escenario posible: el proveedor vería un 2xx y daría el evento por
   entregado sin que se haya procesado nada.
2. El prefijo `/api` sí se reenvía al API. `@Controller()` del backend no usa
   prefijo global, así que nginx **elimina** `/api` antes de reenviar (prueba:
   `GET /api/health` responde `{"status":"ok"}` del `HealthController`, cuya ruta
   real es `/health`).
3. **URL correcta para el webhook:**
   `https://fullposcloud.fulltechrd.com/api/webhook/dosa`
   → llega al API como `POST /webhook/dosa`.

> Pendiente de confirmar con quien administra el proxy: si el bloque `/api` de
> nginx tiene límite de tamaño de cuerpo o algún filtro que afecte al `POST`.
> El código de esta fase no depende de ello.

---

## 2. `rawBody` en NestJS — estado actual y diseño

Estado real de `apps/api/src/main.ts`:

- `NestFactory.create(AppModule, { bodyParser: false })`.
- `app.use(express.json({ limit: bodySizeLimit }))` — **sin** opción `verify`.
- **Consecuencia: hoy no se conserva el cuerpo crudo.** No es posible verificar
  ninguna firma sobre los bytes exactos recibidos.

Diseño previsto (no aplicado todavía, porque no hay contrato que verificar):

```ts
// main.ts — captura del cuerpo crudo SOLO para la ruta del webhook
app.use(
  express.json({
    limit: bodySizeLimit,
    verify: (req, _res, buf) => {
      if (req.url?.startsWith("/webhook/")) {
        (req as express.Request & { rawBody?: Buffer }).rawBody = Buffer.from(buf);
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

Implementado (aislado, sin superficie HTTP):

| Archivo | Qué hace |
| --- | --- |
| `provider/dosa-webhook.contract.ts` | Estado del contrato y lectura **estructural** del sobre. No autentica. |
| `provider/dosa-webhook.verification.ts` | Verificación de `X-Dosa-Signature` que **falla siempre cerrado**. Sin algoritmo, sin criptografía. |
| `provider/dosa-webhook-receiver.service.ts` | Receptor que **nunca acepta** (503 + `ECF_DOSA_WEBHOOK_BLOCKED`). No persiste, no escribe, no llama a nadie. |
| `provider/dosa-company-linking.policy.ts` | Resolución empresa ↔ RNC con rechazo de RNC desconocido, ambiguo o identidad no coincidente. |
| `provider/dosa-webhook.spec.ts` | 19 pruebas de seguridad del bloqueo y del aislamiento multiempresa. |

**No implementado a propósito:**

- Ninguna ruta HTTP (`@Post("webhook/dosa")`). Añadirla sin firma verificable
  sería abrir un endpoint público que responde a cualquiera.
- Ninguna tabla ni migración. La deduplicación se diseñó (`eventDedupeKey`) pero
  no se persiste: sin contrato no se sabe qué campos son estables.
- Ninguna llamada a DOSA.

Garantías que ya se prueban automáticamente:

- Cualquier valor de `X-Dosa-Signature` produce rechazo.
- Una petición con cuerpo válido y firma plausible sigue rechazándose (503).
- La respuesta no contiene el valor de la firma ni el cuerpo.
- Un evento nunca activa emisión: el receptor no escribe estado.

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

## 6. Siguiente cambio, cuando DOSA responda

1. Guardar la fórmula de firma en `dosa-webhook.verification.ts` y cambiar
   `DOSA_WEBHOOK_CONTRACT_STATUS` a `READY`.
2. Añadir el `verify` de `rawBody` en `main.ts` (sección 2).
3. Crear la tabla de eventos con índice único `(companyId, eventId)` y la
   migración aditiva.
4. Registrar `POST /webhook/dosa` con: límite de tamaño, verificación de firma,
   deduplicación, y respuesta 2xx **solo después** de persistir.
5. El evento entra como **evidencia**, nunca como autorización de emisión. La
   activación sigue siendo un acto humano con comprobaciones fiscales.
6. Ejecutar las pruebas de seguridad con eventos firmados reales de TEST y con
   firma manipulada, repetida y obsoleta.
