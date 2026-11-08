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
> la bandera activa «Normal» venía preseleccionado. Se cambió a propósito: preseleccionar
> la excepción convertiría en camino por defecto la venta **sin** comprobante, justo lo
> contrario de «el POS genera automáticamente el comprobante correspondiente». La opción
> sigue disponible, pero hay que elegirla y justificarla.

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
  (RNC + nombre → E31; sin receptor → E32; nunca E34; «Normal» solo con la bandera).
- `EcfPosFiscalSelector` sustituye visualmente al selector B01/B02 cuando la empresa
  factura electrónicamente; B01/B02 siguen existiendo para las demás empresas.
- El cierre de venta envía `fiscalVoucherType: null` con e-CF activo, pide el motivo
  antes de cobrar cuando es «Normal», y prepara el comprobante después de guardar. Un
  fallo de preparación **no** degrada la venta: se informa y se resuelve en Mis Ventas.
- Cobertura: 15 pruebas de la regla de selección.

### Pendiente de una autorización explícita
- **Emission real**: E32 ya numera y se prepara, pero enviar al proveedor sigue
  gobernado por las banderas de certificación de cada empresa.
- **Retiro físico del código B01/B02**: se retiró del flujo de venta de las empresas con
  e-CF, pero el módulo legado (`/ncf`, `fiscal_voucher_options.dart`, impresión con
  `ncf`) sigue vivo porque hay empresas que todavía facturan con NCF tradicionales.
  Borrarlo exige migrar esos talonarios primero; hacerlo ahora rompería su facturación.

## 6. Riesgo conocido y su remedio (HIPÓTESIS no verificada en producción)

El POS decide si usa e-CF leyendo `GET /ecf/capabilities`, que exige el permiso
`viewEcfDocuments`. Si un vendedor **no** tiene ese permiso, o la llamada falla, el POS
no puede saber que su empresa factura electrónicamente y cae al selector legado.

Remedio recomendado (**RECOMENDACIÓN**, no implementado aquí porque cambia la
permisología del módulo): exponer una proyección mínima para el POS
(`enabled`, `allowSalesWithoutEcf`, aviso y tipos) bajo el permiso que el cajero ya
necesita para vender, en lugar de reutilizar el endpoint de administración. Mientras
tanto, el backend sigue siendo la última barrera: rechaza un talón si `ncfEnabled` está
apagado y rechaza la excepción si la bandera está apagada.


