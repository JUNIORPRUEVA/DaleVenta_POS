# DOSA — API de emisión e-CF: contrato real y correspondencia con FullPOS

Investigación realizada el **2026-11-04** sobre la documentación oficial vigente.
No se envió ninguna solicitud a la API, no se usaron credenciales y no se emitió
ningún comprobante.

## Fuentes utilizadas (y exactitud de cada una)

| # | Fuente | Cómo se obtuvo | Fecha del contenido |
| --- | --- | --- | --- |
| **F1** | `https://dosasystem.com/dosainvoicecloud/developers` — pestaña **Descripción General** | Navegador real (Playwright), texto extraído del DOM | vigente 2026-11-04 |
| **F2** | misma página — pestaña **Documentación API** | Navegador real, texto extraído del DOM (5 623 caracteres) | vigente 2026-11-04 |
| **F3** | misma página — pestaña **Ejemplos** | Navegador real, acordeones abiertos uno a uno | vigente 2026-11-04 |
| **F4** | `https://github.com/alapaix13/DosaInvoicecloud-Documentation` → `README.md` | Descargado de `raw.githubusercontent.com` (78 883 bytes, 2 600+ líneas) | incluye sección **«Correcciones para quien ya integró (noviembre 2026)»** |
| **F5** | mismo repo → `NOTAS_CREDITO_DESDE_FACTURA.md` | Descargado (9 488 bytes) | vigente |
| **F6** | Código de este repositorio | Lectura directa (`apps/api/src/ecf/provider/dosa/*`) | commit `e703d988` |

Nota: la pestaña Descripción General cita cinco documentos
(`EJEMPLOS_JSON_DGII.md`, `CAMBIOS_JSON_DGII_RESUMEN.md`,
`FACTURACION_MODULO_COMPLETADO.md`, `CHECKLIST_VALIDACION_JSON_DGII.md`,
`GUIA_USO_API_FACTURAS.md`). **Ninguno existe en el repositorio público**, que
solo contiene `README.md` y `NOTAS_CREDITO_DESDE_FACTURA.md` (verificado contra
`api.github.com/repos/.../contents/`). El enlace «Descargar Guía PDF» apunta a
`#`: no hay PDF.

---

## 1. Endpoints

| Endpoint | Método | Estado | Fuente |
| --- | --- | --- | --- |
| `https://dosasystem.com/fe/api/emision/ecf/EnviarFactura` | `POST` | **CONFIRMADO** | F2, F4 L53 |
| `https://dosasystem.com/fe/api/emision/ecf/NotaDesdeFactura` | `POST` | **CONFIRMADO** | F5 (documento aparte) |
| `https://dosasystem.com/fe/api/emision/ecf/ValidarDatos` | `POST` | **PARCIAL** — URL, método, cabecera y cuerpo de ejemplo confirmados en F3; esquema completo de respuesta no publicado | F3 |
| `https://dosasystem.com/fe/api/emision/ecf/ObtenerFactura/{id}` | `GET` | **PARCIAL** — URL, método y campos de ejemplo (`_id`, `eNCF`, `estado`, `borrador`/`enviada`) confirmados en F3; catálogo de estados y errores no publicado | F3 |
| Anulación de comprobante | — | **PENDIENTE DEL PROVEEDOR** | F1 la menciona («anular»), pero no publica ruta, cuerpo ni respuesta |
| Descarga PDF / XML | — | **PENDIENTE DEL PROVEEDOR** | F1 la menciona; sin ruta documentada |
| Estadísticas | — | **PENDIENTE DEL PROVEEDOR** | F1 la menciona; sin ruta documentada |
| Webhook de estado | — | **PENDIENTE DEL PROVEEDOR** (firma) | `docs/ECF_DOSA_WEBHOOK_CONTRACT.md` |

**Corrección a nuestra documentación interna:** `docs/ECF_DOSA_EMISSION_CONTRACT_VERIFIED.md` §8 afirma
«Endpoint de consulta de estado: no documentado; por eso `querySupported: false`».
Eso ya **no es cierto**: `ObtenerFactura/{id}` está publicado en la pestaña
Ejemplos (F3). El flag `querySupported: false` del adaptador debe revisarse.

---

## 2. Autenticación — dos mundos distintos

| Producto | Cabecera | Ámbito | Estado |
| --- | --- | --- | --- |
| **Emisión** (DosaInvoice Cloud) | `X-API-KEY` | Emitir, validar RNC, consultar factura | **CONFIRMADO** (F2, F3, F4 L55-59) |
| **Certificación** (asistente DOSA) | *secret key* del partner vía `session-url` | Crear sesión de postulación | **PENDIENTE DEL PROVEEDOR** (contrato de sesiones sin publicar) |

`X-Dosa-Secret-Key` aparece **0 veces** en F4; es una cabecera de **nuestra**
implementación de consultas (`dosa-api.client.ts`), no del contrato de emisión.
No son intercambiables: son dos credenciales distintas, de dos productos
distintos, con dos ciclos de vida distintos.

Además, F2 exige para emitir:

> «El campo `RNCEmisor` del bloque `Emisor` es obligatorio y debe ser el RNC de la
> empresa dueña del API Key.»

y en las notas finales:

> «`RNCEmisor` … Debe ser el RNC de la empresa dueña del API Key (la del
> certificado digital con que se firma)».

Consecuencia: **API Key, RNC del emisor y certificado son la misma identidad
fiscal**. Una API Key no puede emitir en nombre de otra empresa. Estado:
**CONFIRMADO** en la documentación; **no verificado en runtime** (no se enviaron
solicitudes).

---

## 3. Esquema de entrada — confirmado contra F2/F4

### 3.1 Estructura general

```
{
  encabezado: { version, idDoc, emisor, comprador, totales },
  detallesItems: { items: [ … ] },
  Subtotales: {},
  descuentosORecargos: { descuentoORecargo: [] },
  paginacion: {},
  informacionReferencia: {}
}
```

El ejemplo de F2 usa **camelCase** (`encabezado`, `detallesItems`,
`idDoc`). Los ejemplos de `NotaDesdeFactura` (F5) usan **PascalCase**
(`Encabezado`, `DetallesItems.Items`, `Referencia`). FullPOS emite camelCase, que
es la forma del ejemplo del endpoint de envío. Brecha declarada, sin resolver.

### 3.2 Bloques y campos verificados

| Bloque | Campos leídos en el ejemplo | Notas |
| --- | --- | --- |
| `idDoc` | `tipoeCF` (String: `"31"`…), `encf`, `indicadorEnvioDiferido`, `indicadorMontoGravado`, `tipoIngresos`, `tipoPago`, `fechaLimitePago`, `terminoPago`, `fechavencimientosecuencia`, `tablaFormasPago.formaDePago[]` | `tipoeCF` es **String**, no número |
| `emisor` | `rncEmisor`, `razonSocialEmisor`, `nombreComercial`, `direccionEmisor`, `numeroFacturaInterna`, `zonaVenta`, `fechaEmision` | `fechaEmision` en `DD-MM-YYYY` |
| `comprador` | `RNCComprador`, `razonSocialComprador`, `correoComprador`, `direccionComprador`, `codigoInternoComprador` | |
| `totales` | `MontoGravadoTotal`, `MontoGravadoI1/I2/I3`, `MontoExento`, `ITBIS1/2/3` (número), `TotalITBIS`, `TotalITBIS1/2/3`, `MontoImpuestoAdicional`, `MontoDescuento`, `MontoRecargo`, `MontoTotal` | montos como **string con 2 decimales** |
| `items[]` | `numeroLinea`, `indicadorFacturacion`, `nombreItem`, `indicadorBienoServicio`, `cantidadItem`, `unidadMedida`, `precioUnitarioItem`, `montoItem`, `tablaImpuestoAdicional` | |

**Reglas de formato — CONFIRMADO (F2, «Notas Importantes»):**

- Fechas `DD-MM-YYYY` (error `1003` si no).
- Montos como **string** con exactamente 2 decimales (`"100000.00"`).
- `ITBIS1/2/3` van como **número** (18/16/0), no como string.

---

## 4. ⚠️ Cambio de códigos: el adaptador actual usa los códigos ANTERIORES

F4 abre con una sección titulada **«Correcciones para quien ya integró
(noviembre 2026)»** que dice literalmente:

> «Versiones anteriores de este documento tenían códigos que no son los de la
> DGII. Si su integración se hizo con ellas, revise estos puntos:»

Esta es la tabla oficial de correcciones (F4, líneas 11-20), contrastada con
nuestro código (F6):

| Campo | Lo que hace FullPOS hoy | Lo correcto según DGII | Veredicto |
| --- | --- | --- | --- |
| `indicadorFacturacion` | `1` producto / `2` servicio (`dosa-ecf.mapper.ts` L58, L71) | **1 = ITBIS 18 %**, 2 = ITBIS 16 %, 3 = ITBIS 0 %, 4 = exento, 0 = no facturable. «No dice si es producto o servicio» | **INCORRECTO** |
| `indicadorBienoServicio` | `1` Servicio / `2` Bien (L76, L81) | **1 = bien, 2 = servicio** | **INVERTIDO** |
| `unidadMedida` | catálogo de 20 códigos (L90-118) | Tabla de 57 códigos de la DGII; **43 = Unidad**, 1 = barril. **Opcional** | **INCORRECTO** |
| `formaPago` | 3 transferencia, 4 tarjeta crédito, 5 tarjeta débito, 8 bonos, 9 otras | **2** cheque/transferencia/depósito, **3** tarjeta débito/crédito, **4** venta a crédito, **5** bonos, **8** otras | **INCORRECTO** |
| Secuencia del e-NCF | «11 dígitos» (`ECF_DOSA_EMISSION_CONTRACT_VERIFIED.md` §6) | **10 dígitos → 13 caracteres en total** | **INCORRECTO** |
| Rechazo | `codigo === "0"` como rechazo en un ejemplo | `codigo` **2**; «lo más seguro es decidir por el texto de `estado`» | **CORREGIDO en F4**, pendiente en nuestro código |
| Código de secuencia usada | `1002` (§6 del doc interno) | **`1209`** (F4 L2135). `1002` no aparece en la documentación | **INCORRECTO** |
| Reintentos | «el cliente no reintenta solo» | Hasta **3 reintentos** con espera 1 s / 3 s / 5 s, **solo** sin respuesta o 5xx | **DESACTUALIZADO** |

### 4.1 Tabla de unidades corregida (F4, «Catálogo de Unidades de Medida»)

| Unidad | Código viejo (el nuestro) | Código correcto |
| --- | --- | --- |
| Unidad | 1 | **43** |
| Caja | 2 | **6** |
| Kilogramo | 3 | **21** |
| Gramo | 4 | **17** |
| Libra | 5 | **23** |
| Metro | 7 | **26** |
| Centímetro | 8 | **8** (no cambia) |
| Pulgada | 9 | **55** |
| Pie | 10 | **33** |
| Yarda | 11 | **41** |
| Litro | 12 | **24** |
| Galón | 14 | **15** |
| Docena | 15 | **13** |
| Paquete | 16 | **31** |
| Hora | 18 | **19** |
| Día | 19 | **12** |

Además, la corrección advierte: **onza, mililitro, servicio y mes no existen en la
tabla de la DGII**. FullPOS mapea hoy `OUNCE` y `MILLILITER`; esas dos líneas
dejarían de poder enviarse con esa unidad (habría que elegir otra o no enviar el
campo, que ahora es **opcional**).

### 4.2 Otros cambios del README que nos afectan

- **E46 va a tasa 0 % (`MontoGravadoI3`)**: «su XSD no admite `MontoExento`».
- Se corrigieron los ejemplos de E32 (con compra), E41, E43, E44, E45 y E46
  porque «el indicador de la línea no cuadraba con los totales».
- `unidadMedida` es **opcional**; antes lo tratábamos como requerido.

**Conclusión operativa:** el mapeador actual (`dosa-ecf.mapper.ts`) implementa el
contrato **anterior**. Mientras no se corrijan esos cinco puntos, cualquier
emisión produciría comprobantes con indicadores fiscales equivocados. La emisión
está apagada por bandera, así que no hay riesgo actual, pero **el adaptador no es
apto para UAT de emisión en su estado actual**.

---

## 5. Respuesta del proveedor

### 5.1 Respuesta conformes (F2, F4)

```json
{
  "trackId": "4cdc9917-8008-4564-a85c-c3f13a4e0ec8",
  "codigo": "4",
  "estado": "Aceptado Condicional",
  "rnc": "101742186",
  "encf": "E320000000004",
  "url": "https://ecf.dgii.gov.do/testecf/consulta...",
  "codigoSeguridad": "EAkbyR",
  "fechaFirma": "15-11-2025 14:46:41",
  "secuenciaUtilizada": true,
  "fechaRecepcion": "2025-11-15T10:46:42",
  "mensajes": [{ "valor": "El campo MontoGravadoI1 …", "codigo": 1934 }]
}
```

- Plana (no envuelta en `data`). **CONFIRMADO**.
- `codigo` llega como **texto** (`"4"`) aunque se describa como numérico.
- No hay campo `qr`: se compone con `url` + `codigoSeguridad` + `fechaFirma` + `encf` + `rnc`.
- `mensajes[]` es un array de `{ valor, codigo }`.

### 5.2 Estados DGII (F2 y F4, idénticos)

| Código | Estado | Descripción |
| --- | --- | --- |
| 0 | No encontrado | La DGII no tiene registro del eCF consultado |
| 1 | Aceptado | Aceptado sin observaciones |
| 2 | Rechazado | Rechazado; motivo en `mensajes` |
| 3 | En Proceso | La DGII todavía lo valida |
| 4 | Aceptado Condicional | Aceptado con observaciones |

La corrección de F4 resuelve la contradicción del `0`: «`codigo` 2. Lo más seguro
es decidir por el texto de `estado`». **Decisión de FullPOS:** clasificar por
`estado`, no por `codigo`.

### 5.3 Estados de transporte (nuevos, F4 §2)

| HTTP | `estado` / `error` | Significado |
| --- | --- | --- |
| 200 | `Aceptado` / `Aceptado Condicional` | Válido. No reemitir. |
| 200 | `Rechazado`, `secuenciaUtilizada: false` | Inválido, número libre → corregir y reenviar **mismo** e-NCF |
| 200 | `Rechazado`, `secuenciaUtilizada: true` o ausente | Inválido, número gastado → **e-NCF nuevo** |
| 202 | `Pendiente DGII` | Firmado y guardado; DOSA lo enviará solo. Imprimir con ese QR y `leyendaContingencia`. No reemplazar. |
| 400 | texto | Validación previa («El campo RNCEmisor en Emisor es obligatorio.») |
| 409 | `e-NCF pendiente de la DGII con otro contenido` | Ya firmado con otros datos; no se puede cambiar |
| 502 | `Error de envío` | (E32 < RD$250 000) La DGII no recibió nada → reenviar mismo JSON |
| 5xx / sin respuesta | — | Estado desconocido |

Los estados **202** y **409** no estaban en nuestra documentación interna.
**CONFIRMADO** (F4 L2238-2241).

---

## 6. Idempotencia y reintentos — el e-NCF es la llave

Texto literal de F4 (L2252):

> «**El e-NCF es la llave.** El API no tiene una llave de idempotencia aparte:
> identifica el comprobante por e-NCF, RNC del emisor y ambiente. Reenviar un
> e-NCF aceptado devuelve el mismo comprobante sin firmarlo ni enviarlo otra vez;
> reenviar uno pendiente devuelve el mismo QR.»

Reglas confirmadas:

1. **Identidad** = e-NCF + RNC emisor + ambiente. No hay cabecera de idempotencia.
2. **Reenviar es seguro** con el mismo e-NCF y el mismo JSON; es la forma
   documentada de averiguar cómo quedó.
3. **Un número nuevo solo** cuando la DGII rechazó y el número quedó gastado.
4. **Riesgo crítico documentado:** «El API **no compara el contenido**: si reenvía
   otros datos con ese número, responde HTTP 200 con el comprobante original,
   **sin avisar**». Es decir: un e-NCF ya usado con datos distintos devuelve el
   original en silencio. FullPOS debe guardar el JSON exacto enviado y no
   reconstruirlo en un reintento.
5. **Nunca en paralelo** el mismo e-NCF: bloqueo por documento.
6. **Reintentos automáticos**: solo sin respuesta o 5xx, máximo 3, espera 1/3/5 s;
   luego dejar pendiente y reintentar más tarde con el mismo e-NCF.

Esto **contradice** la decisión registrada en nuestro doc interno («el cliente no
reintenta solo»). La recomendación del proveedor es más precisa y hay que
adoptarla con el matiz: reintento automático solo en el caso inseguro-por-red,
nunca ante un `Rechazado`.

### 6.1 Catálogo de errores (F2, «Códigos de Error Comunes»)

| Código | Descripción | Acción |
| --- | --- | --- |
| 1001 | RNC del emisor inválido | Verificar el RNC registrado |
| 1209 | Este número de secuencia ya ha sido utilizado | Número gastado → e-NCF **nuevo** |
| 1003 | Formato de fecha inválido | `DD-MM-YYYY` |
| 1004 | Monto total no coincide | Revisar totales |
| 1005 | ITBIS calculado incorrectamente | Recalcular por tasa |
| 1934 | `MontoGravadoI1` no coincide | Suma de ítems gravados I1 |
| 1964 | `MontoExento` no coincide | Suma de ítems exentos |
| 2001 | RNC del comprador inválido | Verificar en DGII |
| 2002 | Identificador extranjero requerido | Añadir identificador |
| 3001 | Referencia a eCF inexistente | Verificar e-CF referenciado (NC/ND) |
| 3002 | Monto de NC excede el original | Revisar nota de crédito |

---

## 7. E32 pequeño (RFCE) — confirmado palabra por palabra

De F2 y F4 L2123-2126:

- E32 **menor a RD$250 000** se envía como **Resumen de Factura de Consumo (RFCE)**.
- La respuesta trae el estado real de la DGII (`Aceptado`, `Aceptado Condicional`,
  `Rechazado`) con `codigo`, `mensajes` y `secuenciaUtilizada`, **sin `trackId`**.
- Si el resumen no llega a la DGII: **HTTP 502** con `estado: "Error de envío"` y el
  motivo en `mensaje`. La DGII no recibió nada → **reintentar con el mismo eNCF**.
- Ya no existe el estado «Enviado Resumen».

Es el **único** caso en que reutilizar el mismo e-NCF tras un fallo es seguro y
está indicado por el proveedor. Coincide con lo ya codificado en
`safeToRetrySameEncf`.

---

## 8. Matriz FullPOS → DOSA

Leyenda: **OK** = disponible y con correspondencia directa · **FALTA** = no existe
en FullPOS · **CAMBIA** = existe pero el código/valor debe corregirse ·
**DEFINIR** = requiere decisión de producto o fiscal.

### 8.1 Encabezado

| Campo DOSA | Origen FullPOS | Estado |
| --- | --- | --- |
| `idDoc.tipoeCF` | tipo de comprobante de la venta (`31`/`32`/`34`) | OK (String) |
| `idDoc.encf` | secuencia e-NCF asignada al documento | CAMBIA (10 dígitos, no 11) |
| `idDoc.fechaLimitePago` | — | **FALTA** (condición de pago) |
| `idDoc.terminoPago` | — | **FALTA** (texto libre) |
| `idDoc.fechavencimientosecuencia` | vigencia de la secuencia | OK si la secuencia tiene `validUntil` |
| `idDoc.tablaFormasPago[].formaPago` | forma de pago de la venta | CAMBIA (2/3/4/5/8) |
| `idDoc.tablaFormasPago[].montoPago` | monto por forma de pago | PARCIAL: depende de que la venta registre el desglose |
| `emisor.rncEmisor` | RNC de la empresa (`AppConfig.rnc` / `Company`) | OK |
| `emisor.razonSocialEmisor` | razón social de la empresa | OK |
| `emisor.nombreComercial` | nombre comercial | OK |
| `emisor.direccionEmisor` | dirección | OK |
| `emisor.numeroFacturaInterna` | número interno de la venta | OK |
| `emisor.zonaVenta` | — | **FALTA** |
| `emisor.fechaEmision` | fecha de la venta | OK (formatear `DD-MM-YYYY`) |
| `comprador.RNCComprador` | RNC del cliente | OK (obligatorio en E31/E41) |
| `comprador.razonSocialComprador` | nombre del cliente | OK |
| `comprador.correoComprador` | correo del cliente | **FALTA / PARCIAL**: el formulario de cliente no lo pide hoy |
| `comprador.direccionComprador` | dirección del cliente | OK |
| `comprador.codigoInternoComprador` | id del cliente | OK |

### 8.2 Totales

| Campo DOSA | Origen FullPOS | Estado |
| --- | --- | --- |
| `MontoGravadoI1` | base a 18 % | OK si el cálculo de impuestos lo separa por tasa |
| `MontoGravadoI2` | base a 16 % | OK |
| `MontoGravadoI3` | base a 0 % | OK |
| `MontoExento` | base exenta | OK (no usar en E46) |
| `ITBIS1/2/3` | tasas | OK (números) |
| `TotalITBIS`, `TotalITBIS1/2/3` | ITBIS calculado | OK |
| `MontoDescuento` | descuentos | PARCIAL: depende de que la venta conserve el descuento a nivel de documento |
| `MontoRecargo` | recargos | **FALTA** |
| `MontoImpuestoAdicional` | impuestos adicionales | PARCIAL (existe el campo; verificar si se calcula) |
| `MontoTotal` | total de la venta | OK |

### 8.3 Líneas

| Campo DOSA | Origen FullPOS | Estado |
| --- | --- | --- |
| `numeroLinea` | índice de línea | OK |
| `indicadorFacturacion` | **tasa de ITBIS de la línea** | CAMBIA (1/2/3/4 por tasa, no por naturaleza) |
| `nombreItem` | descripción del producto | OK |
| `indicadorBienoServicio` | naturaleza del ítem | CAMBIA (invertido: 1 bien, 2 servicio) |
| `cantidadItem` | cantidad | OK |
| `unidadMedida` | unidad de medida | CAMBIA (tabla nueva; opcional) |
| `precioUnitarioItem` | precio unitario | OK |
| `montoItem` | cantidad × precio | OK |

### 8.4 Incompatibilidades que bloquean una emisión correcta

1. **`indicadorFacturacion` depende de la tasa**, no del tipo de ítem. FullPOS
   guarda la naturaleza del ítem y la tasa por separado; el mapeador debe leer la
   **tasa efectiva de la línea** (18/16/0/exento) y traducirla a 1/2/3/4. Hoy
   lee la naturaleza. **Cambio de diseño obligatorio.**
2. **`unidadMedida`**: FullPOS tiene `OUNCE` y `MILLILITER`, que la DGII no admite.
   Hay que decidir qué se envía para esas líneas o no enviar el campo.
3. **`correoComprador`**: el alta de cliente no lo captura. Sin correo, las
   facturas electrónicas no pueden entregarse al comprador.
4. **`zonaVenta`, `terminoPago`, `fechaLimitePago`, `MontoRecargo`**: no existen en
   el modelo. O se capturan, o se omite el campo si el proveedor lo permite.
5. **`formaPago`**: hay que verificar qué códigos produce hoy la venta y remapear.

---

## 9. Certificación vs. emisión — dos productos, dos identidades

| Aspecto | Certificación (asistente DOSA) | Emisión (DosaInvoice Cloud) |
| --- | --- | --- |
| Credencial | ticket de portal → `session-url` | `X-API-KEY` |
| Secreto | secret key del partner (sin contrato) | API Key de la empresa |
| Quién captura el certificado | El asistente DOSA | Ya debe existir |
| Quién firma el e-CF | — | **DOSA**, con el certificado registrado |
| Transporte | iframe del proveedor en nuestro portal | HTTP JSON desde nuestro backend |
| Estado en FullPOS | Implementado (reconciliación hecha) | Adaptador existe, **apagado y con códigos obsoletos** |

**Lo que confirma la documentación (F2):** el emisor debe ser el RNC «dueño del
API Key (la del certificado digital con que se firma)». Por tanto **FullPOS no
necesita el P12 para emitir**: DOSA firma. Eso cierra la pregunta de la
«firma gestionada por DOSA»: **CONFIRMADO en la documentación, no verificado en
runtime**.

**Lo que NO confirma:** que la API Key emitida tras la certificación quede
automáticamente vinculada al certificado de esa empresa; ni si una API Key de
pruebas produce comprobantes de `testecf`. Eso sigue **PENDIENTE DEL PROVEEDOR**.

---

## 10. Bloqueos técnicos pendientes

| # | Bloqueo | Estado | Impacto |
| --- | --- | --- | --- |
| B1 | API Key por empresa y su vínculo con RNC + certificado | PENDIENTE DEL PROVEEDOR | No se puede emitir hasta tener clave y confirmación |
| B2 | Separación test/producción (la doc solo dice «usar diferentes keys») | PENDIENTE DEL PROVEEDOR | Riesgo de emitir en real creyendo que es prueba |
| B3 | Contrato de `session-url` para autorrellenar RNC/correo | PENDIENTE DEL PROVEEDOR | El cliente sigue escribiendo sus datos en el asistente |
| B4 | Firma del webhook (`X-Dosa-Signature`) | PENDIENTE DEL PROVEEDOR | Sin webhooks verificables no hay estado asíncrono fiable |
| B5 | Endpoints de anular / PDF / XML / estadísticas | PENDIENTE DEL PROVEEDOR | Sin ellos no hay descarga de representación impresa ni anulación desde FullPOS |
| B6 | Esquema completo de `ValidarDatos` y `ObtenerFactura` | PARCIAL | Se puede usar lo confirmado; el resto, no |
| B7 | Catálogos DGII corregidos en `dosa-ecf.mapper.ts` | **TRABAJO NUESTRO** | Bloquea la UAT de emisión |
| B8 | `correoComprador`, `zonaVenta`, `terminoPago`, `MontoRecargo` | **TRABAJO NUESTRO** | Campos ausentes en el modelo |

---

## 11. Qué podemos implementar ya, sin inventar nada

Con contrato **confirmado** y sin tocar producción:

1. **Corregir los catálogos del mapeador** a los valores oficiales: unidades (57
   códigos, `43` = Unidad, campo opcional), formas de pago (1-8), e indicadores
   (`indicadorFacturacion` por tasa, `indicadorBienoServicio` corregido). Todo con
   pruebas sintéticas: es una traducción de tabla, no requiere red.
2. **Validar el formato del e-NCF**: 13 caracteres, `E` + tipo (2) + 10 dígitos,
   con rechazo de los antiguos de 11 dígitos.
3. **Clasificar la respuesta por `estado`** y modelar los ocho casos de la §5.3,
   incluyendo 202 y 409.
4. **Aplicar la tabla de reintentos** del proveedor (mismo e-NCF salvo rechazo
   con número gastado; 3 intentos automáticos solo en 5xx/timeout).
5. **Guardar el JSON exacto enviado** por documento, junto al e-NCF, para no
   reconstruirlo en un reintento (el proveedor no compara contenido).
6. **Implementar `ValidarDatos`** como precondición opcional de emisión (RNC del
   comprador y del emisor), usando el contrato confirmado en F3.

**No implementable todavía:** emitir de verdad, anular, descargar PDF/XML,
consultar estadísticas, recibir webhooks verificables y precargar el asistente.

---

## 12. Recomendación

1. **No habilitar emisión** hasta corregir B7 y B8.
2. **Pedir por escrito al proveedor** B1, B2, B4 y B5 con la misma lista de
   preguntas que ya está en `docs/ECF_DOSA_PROVIDER_CONTRACTS.md`.
3. Tratar el README como **vigente y cambiante**: incorpora correcciones en
   octubre y noviembre de 2026. Cualquier catálogo copiado debe quedar fechado y
   con su fuente.
4. La corrección de catálogos (#1) es un cambio **acotado y revisable** que no
   depende del proveedor: es el siguiente paso natural.
