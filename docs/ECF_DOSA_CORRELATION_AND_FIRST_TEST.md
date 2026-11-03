# DOSA — correlación del asistente directo y primera emisión TEST

Estado: cierre de Fase F. Todo lo de aquí es interno; **no se ha enviado nada
fuera**.

---

## 1. ¿El modo `publishable-key` + `base-url` correlaciona empresa y postulación?

**No. Y por eso no se asigna ni se activa nada automáticamente.**

### Qué hace el modo directo (verificado con el script y el paquete oficiales)

El componente se monta así, sin `session-url`:

```html
<dosa-cert-wizard publishable-key="[clave pública]" base-url="https://dosasystem.com"></dosa-cert-wizard>
```

Los atributos observados son exactamente cinco: `session-url`,
`publishable-key`, `base-url`, `theme`, `height`. **No existe un atributo de
estado, token opaco ni metadata** que FullPOS pueda inyectar y que el proveedor
devuelva después.

### Consecuencia técnica

1. La postulación nace **en el navegador del cliente**, dentro del contexto de
   DOSA. FullPOS no crea ninguna fila en `ecf_dosa_certification_sessions`,
   porque no hay llamada nuestra que la origine.
2. El webhook que llega después trae `postulacion_id`, `rnc` y credenciales,
   pero **ningún identificador nuestro**.
3. El RNC que llega en el evento es una **pista que aporta un tercero**. La
   política del proyecto lo trata como dato no confiable: el vínculo
   RNC↔empresa solo se acepta si hay una sesión de servidor que lo respalde.

Resultado observable, y es el comportamiento correcto:

- Sin sesión de servidor ⇒ `404 ECF_DOSA_WEBHOOK_UNKNOWN_RNC`. No se crea
  empresa, no se guardan credenciales, no se activa nada.
- Con sesión de servidor (modo `session-url` o postulación iniciada por
  FullPOS) ⇒ el evento se registra y las credenciales quedan cifradas en
  `PENDING_CONFIRMATION`.

### Qué prueba exacta falta para habilitar la vinculación

Una de estas dos, y ninguna está disponible hoy:

- **A. Prueba criptográfica del origen.** Que DOSA documente el algoritmo de
  `X-Dosa-Signature` (HMAC-SHA256 del cuerpo, cabecera de timestamp y ventana de
  tolerancia). Con firma verificable, el evento es auténtico; aun así seguiría
  faltando el vínculo con la empresa, que resolvería B.
- **B. Token de correlación de ida y vuelta.** Que el componente acepte un
  atributo opaco generado por FullPOS (por ejemplo `state` o `metadata`) y que
  el webhook lo devuelva en el payload. Entonces el vínculo sería verificable:
  nuestro token firmado + su eco en el evento.

**Prueba mínima que yo ejecutaría cuando exista B:** montar el componente con un
`state` firmado (HMAC del `companyId` + nonce, caducidad 30 min), provocar un
evento de prueba y comprobar que el `state` recibido verifica y que su nonce
coincide con el emitido. Sin ese eco, cualquier vinculación por RNC es una
suposición.

---

## 2. Procedimiento de la primera emisión E31 en TEST

**No ejecutado.** Requiere autorización explícita. Este es el guion exacto para
cuando la des, y todo lo que hay que confirmar **antes** de cualquier POST
externo.

### 2.1 Precondiciones que deben cumplirse (si alguna falla, no se envía)

| # | Condición | Dónde se verifica |
| --- | --- | --- |
| 1 | Empresa con `ecf_company_configurations.enabled = true` y `provider = 'DOSA'` | base de datos |
| 2 | Sesión `ecf_dosa_certification_sessions` que vincula el RNC de prueba | base de datos |
| 3 | Evento del proveedor autenticado con `estado_certificacion = 'finalizado'` | `ecf_dosa_webhook_events` |
| 4 | Habilitación DGII `APPROVED` con `authorization_source = 'DGII_OFFICIAL_RECORD'` | `ecf_dgii_habilitations` |
| 5 | Autorización administrativa auditada `DGII_AUTHORIZATION_RECORDED` con actor, no revocada | `ecf_audit_logs` |
| 6 | Credencial en estado `ACTIVE` (solo se llega con 2–5) | `ecf_dosa_company_credentials` |
| 7 | `DOSA_EMISSION_ENABLED=true` | entorno |
| 8 | `DOSA_BASE_URL=https://dosasystem.com` | entorno |
| 9 | `DOSA_TEST_API_KEY` presente, **nunca** en Git | entorno |
| 10 | `DOSA_TEST_RNC=133306001` | entorno |
| 11 | e-NCF dentro del rango `113500`–`115500` | configuración de rangos |
| 12 | `DOSA_EMISSION_ENVIRONMENT=TEST` | entorno |

Todo esto lo evalúa `assessDosaEmissionGate` y `DosaActivationService`; si falta
una sola, no hay petición. No hace falta confiar en el operador.

### 2.2 Confirmaciones que faltan antes del primer POST externo

1. **Que la API Key de TEST opera contra el mismo endpoint único.** La
   documentación oficial no describe separación de ambientes para la API de
   DOSA: solo lista URLs de la DGII. Sin esta confirmación, la separación
   TEST/producción **no está verificada** y el sistema la mantiene bloqueada.
2. **Que el RNC de la API Key es `133306001`.** El proveedor rechaza la petición
   si el RNC del cuerpo no coincide con el de la clave.
3. **Que el rango `113500`–`115500` sigue vigente** para el RNC de prueba y
   vence el `31/12/2028`.
4. **Autorización explícita y por escrito** para consumir **una** secuencia.

### 2.3 Secuencia a ejecutar (un solo comprobante)

```
1. Snapshot previo: contar documentos E31 de la empresa y guardar el último
   e-NCF usado, para poder demostrar qué consumió la prueba.
2. POST único a /fe/api/emision/ecf/EnviarFactura con:
   - cabecera X-API-KEY (desde el entorno)
   - encabezado.idDoc.tipoeCF = "31"
   - encabezado.idDoc.eNCF = <siguiente del rango>
   - encabezado.emisor.RNCEmisor = "133306001"
   - totales con dos decimales, incluidos los ceros
3. Registrar la respuesta CRUDA como evidencia, con su hash.
4. Clasificar con classifyDosaResponse.
5. NO reintentar aunque el resultado sea incierto: 1 intento, 1 secuencia.
   La única excepción documentada es HTTP 502 con estado "Error de envío",
   donde el proveedor afirma que la DGII no recibió nada.
6. Snapshot posterior: comprobar que se consumió exactamente una secuencia
   y que no se creó un segundo comprobante.
```

### 2.4 Recuperación ante fallo

| Resultado | Acción |
| --- | --- |
| `Aceptado` (1) | Registrar `trackId`, `codigoSeguridad`, `url`. Cotejar con el QR de la DGII. |
| `Aceptado Condicional` (4) | Igual, y revisar `mensajes`. El proveedor lo cuenta como aprobado; FullPOS **no** lo marca como aceptación fiscal. |
| `Rechazado` (2) | Leer `mensajes`. No reenviar el mismo e-NCF: corregir y usar una secuencia nueva. |
| `codigo 0` | **Sin resolver.** No se asume aceptado ni rechazado. Reconciliación humana. |
| Timeout / 5xx sin cuerpo | **Incierto.** No reintentar. Reconciliar con evidencia. |
| 502 `"Error de envío"` | Único caso reenviable con el mismo e-NCF, porque la DGII no recibió nada. |

### 2.5 Lo que este procedimiento NO hace

- No certifica ante la DGII.
- No habilita producción.
- No cambia el proveedor de ninguna empresa existente.
- No toca Alanube.
