# Facturación unificada del POS sobre e-CF — decisión y plan

Fecha: 2026-11-08 · Estado: **implementado en rama `agent/ecf-pos-unified-invoicing`; sin push ni despliegue**
Rama de trabajo: `agent/ecf-pos-unified-invoicing` (apilada sobre el release pendiente)

## 1. Decisión del propietario (HECHO)

Se sustituye el selector fiscal antiguo **B01/B02** por el sistema **E31/E32** dentro del
proceso de venta. Un solo flujo de facturación visible. B01/B02 se retiran de la
interfaz de venta **solo** para empresas que ya operan con e-CF; las empresas que aún
deban operar con NCF tradicionales conservan su flujo y **no se interrumpe** nada.

Dos modos por empresa:

| `allowSalesWithoutEcf` | Comportamiento del POS |
| --- | --- |
| `false` (por defecto) | El tipo se selecciona **automáticamente** (E31 o E32). Se muestra antes de cobrar y solo se corrige entre tipos permitidos. **«Normal» no existe** como opción |
| `true` | Aparecen **Normal**, E31 y E32. La preselección sigue siendo **E31/E32**; **Normal** nunca se preselecciona y exige **motivo**, que queda registrado |

> **Corrección sobre el borrador inicial.** El primer borrador de esta tabla decía que con
> la bandera activa «Normal» venía preseleccionado. Se implementó primero lo contrario y el
> propietario lo corrigió: **con la excepción habilitada, Normal es la opción preseleccionada**
> en cada venta nueva, sujeta a las reglas fiscales aplicables (cambio manual a E31/E32,
> motivo obligatorio y validación del servidor). Con la excepción apagada, el comprobante se
> elige solo. Implementado en `defaultEcfPosFiscalMode` con cobertura de ambos modos.

Regla automática acordada: **cliente con RNC → E31**; **sin RNC → E32**; si el cliente
pide consumo teniendo RNC, se permite E32 entre los tipos habilitados. Si falta un dato
o no hay rango disponible, **se bloquea**; nunca se degrada a Normal en silencio.

## 2. Estado del código (HECHO, verificado)

- El POS ya tiene un selector fiscal: `modules/ventas/fiscal_voucher_options.dart`,
  con **B01** y **B02**, visible si `taxEnabled && ncfEnabled`, alimentado por
  `/ncf/sequences`.
- La e-CF vive **fuera** del POS: `EcfPrepareAction` en Mis Ventas.
- La preparación de **consumo (E32)** devuelve `encf: null`
  (`ecf-preparation.service.ts`): el e-NCF lo aporta solo el flujo de certificación.
- `EcfSequenceService` solo admite `E31` y `E34`; el patrón de e-NCF es `E(31|34)`.
- `DosaEmissionDispatchService` rechaza cualquier tipo distinto de E31/E34.

Conclusión: **no es un interruptor**, es integrar dos sistemas que hoy no se hablan.

## 3. Fases (cada una con sus pruebas y su commit)

### Fase 1 — Cerrar la numeración de E32 (condición previa)
- `E32` pasa a ser tipo asignable: `EcfSequenceService`, patrón `E(31|32|34)`, DTOs.
- La preparación de consumo **asigna el e-NCF del rango autorizado** y lo persiste, en
  lugar de dejar `null`.
- El despacho DOSA acepta E32 (la compuerta ya lo soporta).
- Pruebas: rango autorizado, agotamiento, idempotencia y **no duplicar** al reintentar.
- **No se habilita nada visible** hasta que esta fase esté verde.

### Fase 2 — Configuración por empresa
- `allowSalesWithoutEcf` en `ecf_company_configurations` (default `false`) con auditoría
  del cambio (`CONFIG_UPDATED` ya guarda antes/después).
- Validación **en backend**: una venta marcada «Normal» con la bandera apagada se
  rechaza con código propio. Sin degradación automática.
- Registro de excepciones: empresa, venta, usuario, fecha, motivo y tipo esperado.
- Ajustes → e-CF: interruptor **«Permitir ventas normales sin e-CF»** con el aviso rojo
  aprobado y confirmación explícita.

### Fase 3 — POS
- Selector compacto con el tipo preseleccionado; «Normal» solo si la bandera está activa.
- Integración de la preparación/emisión dentro del cierre de venta, reutilizando el motor
  DOSA, la numeración, la caja, los pagos y el inventario existentes.
- B01/B02 ocultos únicamente para empresas con e-CF activo.
- Pruebas: ambos modos, cambio de configuración en caliente, ventas consecutivas, dos
  empresas aisladas, y que un fallo de emisión **no** convierta la venta en Normal.

## 4. Reglas que no se relajan

- Nunca cambiar a Normal por un error de emisión: se bloquea o queda pendiente.
- E34 no se ofrece como factura de venta.
- Sin emisión duplicada: se reutiliza la idempotencia existente.
- Permisos, rangos e-NCF, estado de certificación y aislamiento multiempresa intactos.

## 5. Estado de implementación (HECHO)

Rama `agent/ecf-pos-unified-invoicing`, apilada sobre el release pendiente porque la
numeración necesita la autorización DGII declarada de la rama anterior.

### Fase 1 — cerrada
- `EcfSequenceService` numera `E31`, `E32` y `E34`; patrón `E(31|32|34)`.
- `prepareConsumoFromSale` reutiliza el orquestador de emisión: asigna el e-NCF del
  rango autorizado, lo persiste y es idempotente por venta (un reintento reutiliza el
  número, no quema otro). Si no hay e-NCF, falla en cerrado.
- `DosaEmissionDispatchService` acepta los mismos tipos que su compuerta fiscal, sin
  repetir la lista.
- `allocatable` se deriva del motor real en lugar de estar cableado.
- Cobertura nueva: rango propio de E32, idempotencia, rechazo sin autorización DGII y
  bandeja mostrando el e-NCF. Suites Postgres: 47/47 en secuencias, consumo,
  preparación y consulta.

### Fase 2 — cerrada
- Migración aditiva `20261108180000_ecf_allow_sales_without_document`:
  `allow_sales_without_ecf` (default `false`) y tabla `ecf_sales_without_document`.
- `EcfSalesWithoutDocumentService` rechaza registrar cuando la empresa no habilitó la
  excepción o cuando la venta ya tiene comprobante (NCF legado o e-CF preparado), y es
  idempotente por venta.
- El aviso fiscal vive en el servidor y viaja en las capacidades.
- Interfaz: interruptor con el aviso completo en rojo y confirmación explícita.
- Cobertura: 9 pruebas de política + 9 de integración Postgres + 8 de widget.

### Fase 3 — cerrada en lo verificable sin emisión real
- `modules/ventas/ecf_pos_fiscal.dart` decide qué se ofrece y qué se preselecciona
  (con la excepción habilitada, «Normal» por defecto; sin ella, RNC + nombre → E31 y sin
  receptor → E32; E34 nunca).
- `EcfPosFiscalSelector` sustituye visualmente al selector B01/B02 cuando la empresa
  factura electrónicamente; B01/B02 siguen existiendo para las demás empresas.
- El cierre de venta envía `fiscalVoucherType: null` con e-CF activo, pide el motivo
  antes de cobrar cuando es «Normal», y prepara el comprobante después de guardar. Un
  fallo de preparación **no** degrada la venta: se informa y se resuelve en Mis Ventas.
- Cobertura: 17 pruebas de la regla de selección.

### Pendiente de una autorización explícita
- **Emission real**: la cadena ya está completa (preparar → despachar → registrar
  resultado → recuperar pendientes), pero que salga un comprobante real depende de las
  banderas de certificación de cada empresa. En producción esas banderas siguen apagadas.
- **Retiro físico del resto del módulo B01/B02**: ver §7.

## 7. Evidencia de producción sobre B01/B02 (HECHO, solo lectura, 2026-11-08)

Consultas `SELECT` sobre la base de producción, sin escribir nada:

| Dato | Valor |
| --- | --- |
| Empresas totales | 37 |
| Empresas con `ncf_enabled = true` | **1** (`little-party` / CORITO DOMINO, ACTIVA) |
| Ventas de esa empresa | 22, **0 con comprobante**, **0 rangos NCF registrados** |
| Ventas B02 en 90 días | **0** |
| Ventas B01 en 90 días | **3**, todas de `daleventa-pos` (FULLTECH) en agosto |
| Histórico total con NCF | **3 ventas** (21-22 ago 2026) |
| Empresas con e-CF activa | 1 (FULLTECH) |
| Solape e-CF + NCF | ninguno |

Conclusión: **ninguna empresa depende de B01/B02 para operar**. La única con NCF
encendido nunca registró un talonario ni emitió. Los 3 comprobantes históricos viven en
`Sale.fiscal_voucher_type` y no dependen del módulo, así que se conservan aunque el
selector desaparezca.

Lo que **sí** se retiró: el POS de las empresas con e-CF ya no ofrece B01/B02 (Fase 3).
Lo que **falta** retirar es el resto de la rama legada dentro de la pantalla de venta
(selector B01/B02, selector de secuencias NCF, aviso de cliente B01 y su proveedor
`posNcfSequencesProvider`): ~20 puntos en un archivo de 4.000 líneas. Es un borrado
mecánico pero de alto riesgo que merece su propio commit y su propia corrida de
regresión completa; hacerlo junto con el resto de cambios de esta tanda habría mezclado
una sustitución de comportamiento con una limpieza estructural.

## 8. Emisión automática y recuperación (HECHO)

- Tras preparar, el POS **despacha** al proveedor si la empresa tiene la emisión
  autorizada (`emissionPathAvailable`). El resultado se muestra al vendedor y el backend
  registra estado e intento.
- `GET /ecf/documents/pending-dispatch`: comprobantes preparados que nunca salieron.
- `POST /ecf/documents/dispatch-pending`: reintenta esos envíos. **No puede duplicar**:
  `dispatchOnce` exige cero intentos `SEND_TO_PROVIDER`, reclama el documento de forma
  atómica y registra el intento antes de la red. Un documento con intento previo no entra
  en la lista: su conciliación es un acto humano.
- Cobertura: 5 pruebas Postgres que demuestran que un documento ya intentado no se
  vuelve a enviar y que un bloqueo fiscal no crea intentos nuevos.

## 9. Las dos suites Postgres rojas: causa y solución (HECHO)

No estaban rotas. `E32SandboxService.tenant()` y `E32ReconciliationExecutor.reconcile()`
comprueban **tres** condiciones: `APP_ENV=uat`, `UAT_LOCAL_ONLY=true` y `DATABASE_URL` en
la allowlist local. El comando de pruebas documentado solo fijaba la tercera. Con las tres,
las dos suites pasan **41/41** contra la base efímera. Corregido en la nota operativa de
entorno de pruebas.

## 10. Riesgo de permisos del POS: cerrado

El POS decidía si usaba e-CF leyendo `GET /ecf/capabilities`, que exige el permiso
`viewEcfDocuments`. Un vendedor sin ese permiso (o una llamada fallida) dejaba al POS sin
saber que su empresa factura electrónicamente y lo hacía caer al selector legado.

**Corregido:** el POS decide con `CompanySettings.ecfEnabled`, que ya viaja en los ajustes
de empresa que la pantalla carga, y usa las capacidades solo para construir las opciones
(tipos, bandera y aviso). Si las capacidades no cargan, no hay opciones y el cobro se
bloquea con un mensaje explícito: falla en cerrado en vez de emitir un talón por error.



