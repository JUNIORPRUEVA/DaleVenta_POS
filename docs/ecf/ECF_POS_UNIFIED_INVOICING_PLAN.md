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
- **Retiro físico del resto del módulo B01/B02**: **hecho**. El selector, las
  secuencias NCF y el proveedor se retiraron en `f6bfbaca`/`bf870d59`; el
  2026-11-08 se limpiaron el último texto de ayuda y los comentarios obsoletos (ver §7).

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
El resto de la rama legada dentro de la pantalla de venta (selector B01/B02, selector de
secuencias NCF, aviso de cliente B01 y su proveedor `posNcfSequencesProvider`) se retiró
en `f6bfbaca` y `bf870d59`. Revisión posterior (2026-11-08): no queda ninguna superficie
B01/B02 en el POS; solo persistían un texto de ayuda («Opcional para B01») y comentarios
que afirmaban que el talón seguía existiendo para empresas sin e-CF, ya corregidos. Las
únicas referencias restantes son las etiquetas del **histórico** (`fiscal_voucher_options.dart`),
la impresión/PDF de ventas antiguas y los enlaces de compatibilidad de §2.

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




## 11. E34 en devoluciones: integrado y probado

La devolución (`POST /sales/:id/return`) ya prepara su **nota de crédito E34** cuando la venta
original conserva un comprobante E31/E32 **aceptado por la DGII**. Si no lo tiene, la devolución
se comporta exactamente como antes y no se reserva numeración ni se crea documento alguno.

Reglas implementadas en `SalesService.prepareRefundCreditNote`:

- **Tipo**: `TOTAL` cuando la suma de cantidades devueltas (incluida la recién creada) cubre todo
  el original; `PARTIAL` en cualquier otro caso.
- **Líneas**: salen del original, no de la petición. El `lineNumber` se calcula con el **mismo
  orden que el adaptador fiscal** (`sale.items.createdAt asc`), así la acreditación parcial apunta
  a la línea real del comprobante.
- **Idempotencia**: el módulo e-CF exige un UUID como identificador de operación, así que se deriva
  uno determinista (UUID v5 SHA-1) del id de la devolución. Repetir la devolución devuelve la misma
  nota y no consume otro e-NCF.
- **Fallo fiscal no rompe la devolución**: ya está confirmada. Se registra
  `ECF_E34_CREDIT_NOT_PREPARED` / `ECF_E34_CREDIT_PREPARATION_FAILED` con su código y stack, y el
  documento queda para revisión supervisada.
- **Despacho**: no hay envío inmediato. La nota queda en `LOCAL_VALIDATED` y el barrido
  `POST /ecf/documents/dispatch-pending` la recoge; `DOSA_GATE_SUPPORTED_TYPES` incluye `E34`.

Evidencia: `apps/api/src/sales/sales-return-ecf-credit-postgres.integration-spec.ts` (5 pruebas
contra la base efímera): parcial con reserva `59.00`, dos parciales con notas distintas, total con
reserva `177.00`, reintento sin duplicar y venta sin comprobante electrónico sin nota.

En el cliente, `returnSale` devuelve la venta **y** su nota (`SaleReturnResult`), y las pantallas
de devolución (Mis Ventas y TPV) muestran el e-NCF en el aviso de éxito. E34 nunca aparece como
comprobante de una venta nueva.

## 12. Validación del histórico NCF y del barrido E34 (2026-11-08)

Rama `agent/ecf-pos-unified-invoicing`. Sin push, sin despliegue y sin escritura en producción:
todas las suites de escritura corrieron sobre la base efímera desechable.

### Histórico NCF (HECHO, verificado)

- El comprobante retirado sigue siendo **legible**: `Sale.fiscalVoucherType`, `Sale.ncf` y
  `Sale.ncfExpirationDate` se conservan, `GET /sales` los devuelve y el cliente los muestra en el
  histórico del TPV y en los tickets/PDF (ESC/POS, HTML y PDF).
- Una venta **nueva** que pida `fiscalVoucherType` (B01/B02) se rechaza con
  `ECF_LEGACY_NCF_RETIRED`: no se crea la venta sin el comprobante que el usuario esperaba y no se
  escribe ninguna fila `ecf_*`.
- **Defecto corregido:** `legacy-pos-compatibility-http.e2e-spec.ts` seguía creando una serie con
  `POST /ncf/sequences` (endpoint retirado, hoy 404) y esperaba 201. La suite estaba en rojo. Ahora
  siembra el histórico directamente en base y fija el contrato real: histórico legible por la API y
  venta nueva rechazada. Evidencia: **10/10 PASS**.

### Barrido de pendientes E34 (HECHO, verificado)

- `pending()` no filtraba por tipo, pero **ninguna prueba lo demostraba para E34**. Nuevo caso en
  `dosa-dispatch-pending-postgres.integration-spec.ts`: la nota preparada aparece como pendiente con
  su tipo real, el barrido la intenta y, sin autorización fiscal, no abre la red ni deja intento
  `SEND_TO_PROVIDER` (sigue pendiente y reintentable). Evidencia: **6/6 PASS**.
- **E34 desde un original E32:** la venta por defecto del POS (cliente sin RNC) es E32, pero la
  suite de devoluciones solo cubría originales E31. Caso nuevo en
  `sales-return-ecf-credit-postgres.integration-spec.ts`: la nota referencia `originalType: E32`
  con el e-NCF del original y reserva el total. Evidencia: **8/8 PASS**.

### Limpieza (HECHO, verificado)

- `registrar_venta_screen.dart` escribía `[SALE PRINT] … ncf=…` en cada venta
  (introducido en `4dce5daf`). Retirado: era un log de depuración en código de producción.
  `flutter analyze` limpio y 69 pruebas de POS en verde.
- `ecf-local-target.spec.ts` seguía exigiendo **3** destinos locales; el puerto alternativo 55500
  añadido en `334b8ea6` hacía fallar la suite completa del backend. Actualizado a 4 destinos y a la
  regla exacta (el 55500 con otro nombre se rechaza).
- `dosa-emission-dispatch.e2e-spec.ts` y `dosa-emission-dispatch-http.e2e-spec.ts` todavía creaban una
  serie con `POST /ncf/sequences` y pedían `fiscalVoucherType: "B01"`; ambos flujos ya no existen.
  Alineados con el contrato e-CF: venta sin talón y preparación con numeración autorizada.
- **Retiro B01/B02 del POS completado:** no quedaba selector ni proveedor de secuencias; persistían un
  texto de ayuda («Opcional para B01») y comentarios que afirmaban que el talón seguía existiendo para
  empresas sin e-CF. Corregidos. `flutter analyze` limpio y 69 pruebas de POS en verde.

### Comandos ejecutados

| Comando | Resultado |
| --- | --- |
| `npx prisma validate` | schema válido |
| `npx tsc -p tsconfig.build.json --noEmit` | 0 errores |
| `npx jest --runInBand --testPathPatterns "src/sales/.*\.spec\.ts$"` | 10 suites / 124 pruebas PASS |
| `npm --workspace apps/api test` (suite completa del backend) | 224 suites / 2721 pruebas PASS, 508 omitidas (opt-in PostgreSQL) |
| `npm --workspace apps/api run build` (prisma generate + tsc) | PASS |
| `npm run audit:tenant-inventory` / `audit:endpoints` | 166 modelos / 412 endpoints, PASS |
| `npm run audit:unsafe-tenant-queries:warn` | exit 0; 401 avisos y 14 errores **preexistentes** (CI usa modo warn) |
| `npx jest --runInBand --testPathPatterns "sales-return-ecf-credit-postgres\|ecf-e34"` | 4 suites / 67 pruebas PASS |
| `npx jest --runInBand --testPathPatterns "dosa-emission-dispatch"` (e2e DOSA) | 2 suites / 25 pruebas PASS |
| `npx jest --runInBand --testPathPatterns "legacy-pos-compatibility-http"` | 10/10 PASS |
| `npx jest --runInBand --testPathPatterns "dosa-dispatch-pending-postgres"` | 6/6 PASS |
| `flutter analyze` | No issues found |
| `flutter test` (suite completa del cliente) | 1994 PASS, 9 omitidas, 0 fallos |
| `flutter test` (etiquetas fiscales, E31/E34 UI, tickets y PDF con NCF) | 62 + 106 pruebas PASS |
| `flutter test` (POS, selector fiscal y acciones de venta) | 69 pruebas PASS |

### Sigue pendiente (sin autorización)

- Emisión real E31/E34 al proveedor y certificación DGII: requieren banderas de certificación y
  ejecución humana; no se ejecutaron.
- Un POS de escritorio antiguo con NCF activo recibirá `ECF_LEGACY_NCF_RETIRED`. Según la evidencia de
  producción de §7 (1 empresa con `ncf_enabled`, 0 rangos, 0 ventas con comprobante) ninguna operación
  real depende de ese camino.
- `audit:unsafe-tenant-queries` deja 14 hallazgos `id-only` **preexistentes** (app-updates, cash,
  guardian, un spec e-CF y `ecf-sequence.service.ts:220`, que actualiza dentro de una transacción con la
  fila ya bloqueada y acotada por empresa). CI los trata como aviso (`:warn`); no se modificaron.
