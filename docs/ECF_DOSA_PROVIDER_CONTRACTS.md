# DOSA — contratos exactos que necesitamos del proveedor

Documento de petición. **No contiene suposiciones**: cada punto indica qué
necesitamos, para qué lo usamos y qué pasa mientras no lo tengamos.

Estado actual tras la Fase 5:

| Área | Estado |
| --- | --- |
| Montaje del componente Web (`<dosa-cert-wizard>`) | **Verificado en navegador real** con el script oficial |
| Atributos y eventos del componente | **Confirmados** por el código del script |
| Modelo de sesiones y control de duplicados | **Verificado contra PostgreSQL real** |
| Creación/consulta de sesiones en DOSA | **Contrato entregado (2026-11-04) e implementado**; activación operativa pendiente |
| Webhook (`X-Dosa-Signature`) | **Bloqueado**: falta la fórmula |
| Emisión fiscal (E31/E32/E34) | **Borrador**: falta cerrar el contrato |

---

## 1. Crear sesiones — `POST /api/certificacion/sesiones`

El script oficial dice textualmente que el enlace de sesión lo crea «el backend
del partner con `POST /api/certificacion/sesiones` y su secret key». DOSA entregó
el contrato el 2026-11-04 y está implementado en
`dosa-certification-session.client.ts` y `dosa-certification-session.service.ts`.

Confirmado en la implementación:

- URL base de pruebas/producción, ruta `/api/certificacion/sesiones`.
- Cabecera `X-Dosa-Secret-Key` con clave `sk_...`.
- Cuerpo `{ rnc_emisor, correo, return_url? }`.
- Respuesta `201` con `url`, `path`, `token`, `expires_at`, `postulacion_id` y
  `prueba`.
- Validación de HTTPS, host de la URL de sesión y caducidad.

Pendiente de confirmación operativa con DOSA:

1. **Idempotencia**: qué ocurre al repetir la petición para el mismo RNC, con y
   sin clave de idempotencia.
2. **Límite de sesiones activas** por empresa/RNC.
3. **Vigencia exacta** y si la URL es de un solo uso.
4. **Alcance de `postulacion_id`**: único por empresa o global.
5. **Códigos de error** completos y cuáles son reintentables.
6. **Allowlist de IPs de origen** y rotación de la secret key.
7. **Fórmula de `X-Dosa-Signature`** para webhooks.

La implementación falla cerrado sin `DOSA_CERTIFICATION_SESSIONS_ENABLED=true`
o sin `DOSA_SECRET_KEY`; en ese caso el cliente usa el portal existente como
fallback. La apertura automática solo se activa cuando la configuración y la
respuesta del proveedor son válidas.

---

## 2. Autenticación desde nuestro backend

1. **Secret key**: formato, longitud, si es por partner o por empresa, y cómo se
   rota sin cortar el servicio.
2. **IPs de origen**: ¿hay allowlist? Necesitamos las IPs de salida que debemos
   declarar (nuestro servidor actual está en `31.97.99.70`).
3. **Entornos**: ¿existe un entorno de pruebas separado? ¿Con qué URL base y qué
   credenciales?
4. **Protección de la publishable key**: ¿está atada a dominios registrados?
   El script menciona «Dominios permitidos para iframe», pero no si la clave
   también se valida por dominio.

Aclaración importante: la `publishable-key` que ya tenemos **no** es un secreto
(viaja en la URL del wizard). El secreto es la *secret key*, y esa nunca saldrá
de nuestro backend.

---

## 3. Recuperar y consultar sesiones

1. **Endpoint** de consulta por sesión y por empresa/RNC.
2. **Autenticación** de la consulta (¿la misma secret key?).
3. **Respuesta**: identificador de sesión, estado, fechas y datos de
   postulación.
4. **Paginación** si devuelve historial.
5. **Política de retención**: cuánto tiempo conservan las sesiones.

Uso previsto: reconciliación. Un evento del navegador solo pide *recargar*; la
verdad la da esta consulta desde el backend.

---

## 4. Estado oficial de la certificación

1. **Enumeración de estados** con su significado operativo.
2. **Cuál es autoritativo**: ¿el estado de la sesión, un campo aparte, o ambos?
3. **Correspondencia con los códigos DGII `0/1/2/3/4`** de la emisión.
4. **Transiciones válidas**: qué estados son terminales y cuáles permiten
   reintento.
5. **Diferencia entre**: «el asistente terminó», «la postulación fue aceptada» y
   «la DGII certificó». Hoy tratamos `cert:complete` como *el asistente terminó*,
   nunca como aprobación.

Necesario porque tenemos `COMPLETED` como estado terminal local y **no** lo
interpretamos como aprobación fiscal: si la DGII puede rechazar después, hace
falta un estado distinto.

---

## 5. Vinculación sesión ↔ cuenta Partner ↔ RNC del cliente

1. **Cómo se declara el RNC** al crear la sesión y si debe coincidir con el de
   la cuenta de DOSA.
2. **Si una cuenta Partner puede operar varios RNC** y cómo se distinguen.
3. **Qué pasa si el mismo RNC se vincula dos veces** desde integradores
   distintos o desde dos empresas nuestras.
4. **Cómo se evita una postulación duplicada** del lado de DOSA (no solo del
   nuestro).
5. **Qué identificador estable** podemos guardar para reconciliar (¿`id` de
   sesión?, ¿id de postulación?).

Nuestro lado ya garantiza: una sola sesión **en curso** por empresa+RNC, y
numeración de intentos que conserva el historial. Falta la garantía del lado
del proveedor.

---

## 6. `X-Dosa-Signature` (webhook)

Seguimos sin poder implementar la verificación. Necesitamos, por escrito:

1. **Algoritmo** exacto (no asumimos HMAC-SHA256 ni ninguna variante).
2. **Qué bytes se firman**: cuerpo crudo tal cual, cuerpo normalizado, o un
   resumen (y de qué campos).
3. **Marca de tiempo**: si entra en el cálculo, formato y dónde viaja.
4. **Codificación** del valor de la cabecera (hex, base64, prefijo de versión).
5. **Ventana de tolerancia** anti-replay.
6. **Alcance del secreto**: por empresa, por entorno o compartido por partner.
7. **Formato del cuerpo del evento**: campos, tipos y si hay un `eventId` estable
   para deduplicar.
8. **Reintentos**: política y ventana, para no responder 2xx antes de persistir.

Mientras no lo tengamos, el webhook **no tiene ruta HTTP**: el receptor existe,
falla cerrado y rechaza todo con `503 ECF_DOSA_WEBHOOK_BLOCKED`.

Además hay que **corregir la URL sugerida**: `https://fullposcloud.fulltechrd.com/webhook/dosa`
devuelve `200 text/html` (fallback del PWA) y nunca llega al API. La correcta es
`https://fullposcloud.fulltechrd.com/api/webhook/dosa`.

---

## 7. Estados y respuestas de emisión fiscal

1. **Significado operativo de `codigo 0`**: la tabla oficial dice «No encontrado»
   y su propio ejemplo lo trata como «Rechazado». Es la contradicción más grave
   porque cambia el estado fiscal de un comprobante.
2. **Tipo de dato de `codigo`**: texto (`"4"`) en unos ejemplos, entero en la tabla.
3. **`trackId`**: ¿existe siempre? En facturas de consumo (E32 < RD$250.000) se
   envía como RFCE y **no** lo devuelven, así que no sirve como clave de
   idempotencia universal.
4. **`secuenciaUtilizada`**: si es `false`, ¿la secuencia se consumió o no?
5. **Reintento tras HTTP 502**: la guía dice «nunca reutilizar una secuencia» y a
   la vez recomienda «reintentar con el mismo eNCF». Necesitamos la regla exacta
   y cómo saber si la DGII recibió el comprobante.
6. **Formato de fecha** en `idDoc.fechaEmision` (la documentación muestra
   `dd-MM-yyyy`; falta confirmación).
7. **`indicadorFacturacion`** por categoría de impuesto.
8. **Si `paginacion` es obligatoria** o solo para comprobantes largos.
9. **`codigoModificacion`** válidos para notas de crédito (E34).
10. **Alcance de la API Key de TEST**: ¿una empresa de prueba o varias bajo el
    mismo partner?

---

## 8. Configuración de integrador pendiente

1. Registrar `fullposcloud.fulltechrd.com` en **«Dominios permitidos para iframe»**.
   Sin esto el navegador bloquea el iframe y el componente emite `cert:blocked`
   (ya verificado en navegador: muestra aviso y ofrece abrir en pestaña nueva).
2. Confirmar que aceptan el prefijo `/api` en la URL del webhook.
3. Comunicar los **eventos** que emite el wizard cuando el contrato de sesión
   esté publicado (ya conocemos los del componente en el cliente).
