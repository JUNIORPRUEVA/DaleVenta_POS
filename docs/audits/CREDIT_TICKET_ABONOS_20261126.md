# Crédito, abonos y ticket de la factura

Fecha: 2026-11-26. Rama `agent/credito-ticket-abonos-20261126`, base
`e4e2f826`. Implementación aislada; sin publicación ni cambios productivos.

Actualización vigente: **se retira la aceptación anterior del contenido
impreso**. La foto posterior del usuario demuestra que el papel terminaba en
TOTAL y omitía el estado de cuenta. Se corrigió el recorte de la ruta real de
Windows; la nueva aceptación física queda pendiente de la prueba manual.
Véase la última sección. La salida de papel anterior no valida su contenido.

## Solicitud y comportamiento

Una venta de RD$2,500 con RD$1,000 recibidos imprime la compra original,
RD$1,000 abonados y RD$1,500 pendientes. Desde Créditos se puede abonar o
saldar con los controles existentes. Tras la confirmación se abre el PDF
actualizado de esa misma factura: mismos productos y total. La impresión
térmica comparte el ticket existente; consultar PDF, guardar y compartir usan
la misma factura A4 de Facturación e Historial, adaptada al crédito.
Reimprimir no crea una venta ni dispara la apertura automática de la gaveta.

`Abonado` es el acumulado confirmado, incluido el inicial; no es únicamente
el último pago. `creditAmount` representa la financiación inicial pendiente
después del inicial y no equivale al total de la compra. El ticket muestra
`totalSold`, `creditPaidAmount` y `creditBalance` del servidor. Nunca vuelve
a sumar el ledger de abonos al acumulado de la venta.

## Hallazgos y correcciones

1. El modelo del ticket omitía los importes del crédito. Se incorporó una
   proyección compartida para texto, ESC/POS, HTML, PDF térmico y factura carta.
   Una nota fiscal E34 no se convierte en una deuda de cliente.
2. La descripción podía mostrar solo efectivo/transferencia y ocultar que era
   crédito. Se conserva esa condición al describir el pago.
3. Créditos usaba un PDF independiente. La primera etapa unificó el ticket
   térmico; la segunda revisión detectó que consultar PDF aún abría el formato
   térmico y no el A4 de Facturación. Ahora los tres puntos de entrada usan
   `UnifiedTicketPrinter.buildSaleInvoicePdf`, que delega en el generador A4
   existente. La lectura previa obtiene el saldo vigente. Se conservan los
   controles fiscales de consulta y coincidencia del total. Cada formato
   mantiene su numeración histórica; no se renumeran documentos.
4. La pantalla descartaba el resultado del abono y anunciaba éxito incluso
   para una respuesta local pendiente. Aplica la respuesta confirmada y abre
   el ticket; un pendiente informa que aún debe confirmarse y no lo imprime
   como pago completado.
5. Dos abonos concurrentes podían sobrescribir el mismo saldo. La actualización
   compara atómicamente empresa, estado e importes anteriores dentro de la
   transacción. Un conflicto revierte también el evento de pago insertado.
6. El replay solo comprobaba `operationId`. Ahora comprueba también factura,
   usuario, caja, efectivo, transferencia y fecha originales.
7. Un cierre de la aplicación entre POST y encolado podía perder la identidad
   del intento. Se guarda antes del envío, con una espera acotada para evitar
   competir con la petición en curso. Al reiniciar se recupera la misma
   identidad. Una operación incierta de esa factura bloquea otro abono, no las
   ventas ni otros créditos independientes.
8. El cliente valida la identidad y los importes de la respuesta antes de
   retirar el intento local. Respuestas contradictorias quedan para revisión.
   Los rechazos definitivos se conservan archivados, sin replay financiero.
   Los errores de autenticación/red y Retry-After usan la política existente
   del motor de sincronización.
9. El importe total podía recortarse en PDF térmico de 58 mm. La columna de
   valores se ajusta al ancho y los rótulos de crédito ESC/POS usan el ancho
   disponible. Los PDF de ejemplo se renderizaron y revisaron visualmente.
10. La prueba nativa reprodujo un 404 al consultar `/sales/:id`: existía el
    cliente `getById`, pero faltaba la ruta del backend. Se agregó lectura
    autenticada, aislada por empresa, con los detalles y la identidad fiscal
    usados por las consultas existentes. Se probó el rechazo de otra empresa.
11. La ficha llamaba «Nota de crédito» a la deuda y mostraba un código distinto
    del ticket. Ahora indica «Factura a crédito» y usa el mismo número que la
    impresión. Se revisaron las referencias visuales de Windows y Linux.

## Archivos principales

- `apps/api/src/sales/sales.service.ts`: replay y actualización atómica.
- `apps/api/src/sales/sales.controller.ts`: lectura de la factura por ID.
- `apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart`:
  identidad, persistencia previa y respuesta confirmada.
- `apps/fulltech_app/lib/modules/ventas/sales_credit_screen.dart`:
  abonar/saldar, estado pendiente y ticket compartido.
- `apps/fulltech_app/lib/core/printing/models/ticket_data.dart` y los
  renderizadores de `core/printing/`: datos y presentación compartidos.
- `apps/fulltech_app/lib/core/printing/unified_ticket_printer.dart`:
  generación del PDF de la misma factura.

## Verificación ejecutada

- Backend: **99 pruebas PASS, 7 suites** de crédito, identidad, aislamiento,
  caja, reportes e inventario opcional. `.uat/credit-backend-regression.log`.
- Flutter: **221 pruebas PASS**, impresión, gaveta, persistencia de intentos
  de venta y las 8 regresiones nuevas de abonos.
  `.uat/credit-printing-regression.log`.
- Repetición final tras ajustar las columnas monetarias: **222 PASS**, las
  mismas 221 y una comprobación adicional del PDF con los datos SQL/HTTP reales.
  `.uat/credit-final-printing-regression.log`.
- Repetición focalizada tras el último ajuste: **17 PASS**, impresión de
  crédito y durabilidad del abono. `.uat/credit-final-focused.log`. No se suman
  a las 221 como pruebas diferentes.
- Pantalla de créditos: **9 PASS en Windows y 9 PASS en Linux**. Son los mismos
  escenarios por plataforma: filtros, vacío, selección y anchos 390/1024/1920/2560.
  `.uat/credit-screen-regression.log` y `.uat/credit-linux-visual-verified.log`.
  Cuatro referencias por plataforma actualizadas intencionalmente por el número
  de factura y el rótulo corregidos, con revisión visual.
- TypeScript: `npm --workspace apps/api exec -- tsc -p tsconfig.build.json`
  PASS. Análisis focalizado Flutter sin incidencias;
  `.uat/credit-final-analyze.log`.
- **16 PDF de prueba**: dos anchos, cuatro estados del crédito y dos
  renderizadores. Una página, filas presentes; imágenes de 58/80 mm
  inspeccionadas. `.uat/credit-ticket/`.
- HTTP real + PostgreSQL exclusivo: **5 escenarios PASS** sobre el código
  compilado de este worktree: inicial, abono/replay, identidades/empresa,
  liquidación/sobrepago y liquidaciones simultáneas. Se conservan las filas
  completas antes/después en `.uat/credit-ticket/evidence.json`.

El laboratorio usa exclusivamente API `127.0.0.1:14627` y PostgreSQL
`127.0.0.1:14626`, contenedor `fullpos_credit_ticket_20261126`, base
`fullpos_credit_ticket_20261126`. Las migraciones existentes se aplicaron solo
a esta base nueva. No se creó una migración para esta corrección. No se borraron
fixtures al terminar. Credenciales sintéticas y artefactos quedan ignorados.
Al cerrar se detuvieron únicamente la API y el contenedor de este laboratorio;
sus datos quedaron persistidos. Para reproducir, iniciar primero el contenedor.

Reproducción: compilar API, preparar el contenedor local y ejecutar
`node scripts/uat/credit-ticket-flow.cjs --init --serve`. El script rechaza
archivos backend `.env`, un puerto ocupado y cualquier destino alternativo.

## Aceptación nativa y límites

La prueba está en
`apps/fulltech_app/integration_test/credit_ticket_native_test.dart`.
El primer intento compiló pero Flutter buscó el ejecutable UAT mientras CMake
había generado el normal; no ejecutó escenarios. Se conserva
`.uat/credit-native-windows.log`. La repetición usa el canal existente
`FULLPOS_WINDOWS_CHANNEL=uat-mayoreo` y el prefijo de instalación local del
cache CMake. No se modificó la identidad del producto en código.

**Aceptación Windows PASS:** `.uat/credit-native-windows-final-acceptance.log`
y `.uat/credit-ticket/native-result.json`. Sobre una empresa nueva, la pantalla
real registra RD$500, abre el ticket de la misma factura y salda los RD$1,000
restantes mediante el menú existente. Dos POST, dos abonos distintos, factura
original de RD$2,500, pagado RD$2,500 y saldo cero. Se observó el PDF renderizado
en la pantalla, con el mismo número que la ficha y estado Saldado.

Verificación SQL independiente: `native-sql-before.json` y
`native-sql-after.json` en `.uat/credit-ticket/`. Conserva exactamente los
campos no financieros de la venta, sus artículos, el producto, existencias por
almacén y movimientos de inventario; una sola factura y dos eventos de cobro.

Los intentos nativos fallidos se conservan: identidad CMake, la ruta GET ausente
corregida, selectores/esperas del arnés, cierre de la notificación en vez del
panel y arranque de API bajo presión de memoria. No se forzó una confirmación
ni se relajó una protección para superarlos. Las empresas de cada intento
quedaron conservadas; cada repetición completa usó otra empresa sintética.

La revisión final del PDF detectó además el recorte del precio unitario; los
importes del renglón y los totales ahora se ajustan sin truncar cifras. Este
último cambio es solo de presentación. Se vuelve a comprobar con el payload
real de la misma factura, sin POST ni más abonos, en
`.uat/render_credit_test.dart`; se generan las versiones inicial/saldada de
58/80 mm `verified-*.pdf`. Las regresiones completas de impresión se repiten
en `.uat/credit-final-printing-regression.log`.

No se ha validado impresora física ni ejecutado aceptación nativa Android/iPhone
en esta tarea. Las pruebas no certifican hardware ni una versión ya publicada.

No se cambiaron reglas fiscales, precios de planes, inventario o permisos.
La integración con otras ramas y la publicación requieren una versión coherente
y su aceptación. Este informe no declara riesgo cero.

Dictamen: GO para el recorrido local validado y revisión del cambio. NO-GO para
afirmar publicación o aceptación de impresora física. Cambios en el worktree
aislado; no se hizo commit, merge, push o despliegue como parte de esta tarea.

## Segunda revisión: unificación A4 y contabilidad del crédito

### Documento único por formato

Facturación, Historial y Créditos llaman al mismo generador A4. El bloque
«Estado de cuenta» reutiliza la proyección compartida del ticket: compra a
crédito, abonado y saldo pendiente. Tras abonar o saldar, Créditos consulta la
factura vigente antes de generar el PDF. Guardar y compartir usan esos mismos
bytes. Reimprimir mantiene el canal térmico existente; no crea otra factura.

Se compararon los textos completos y las dimensiones A4 de ambas rutas para
cuatro estados: sin inicial, inicial de RD$1,000, abono acumulado RD$1,500 y
saldado RD$2,500. Coinciden por estado. Artefactos `a4-shared-*.pdf`,
`a4-invoice-*.pdf` y `a4-unification.json` en `.uat/credit-ticket/`.

### Hallazgos financieros corregidos

- Una devolución confundía financiación inicial (`creditAmount`) con total
  comprado. Se reprodujeron cinco regresiones antes de corregirlo. Ejemplo:
  compra RD$2,500, inicial RD$1,000 y devolución RD$500; debe conservar
  RD$1,000 abonados y RD$1,000 pendientes. El cálculo anterior podía saldar
  indebidamente la deuda. Ahora se reduce primero la cuenta por cobrar y solo
  se reembolsa dinero cuando la devolución supera el saldo pendiente.
- El reparto proporcional de reembolso mixto podía redondear ambos canales
  independientemente. Transferencia recibe ahora el residuo exacto del importe
  reembolsable después del efectivo, conservando los centavos.
- Reportes rotulaba «Costo neto» pero podía mostrar costo antes de devoluciones.
  Se agregan `netCost` y `grossProfit` y la pantalla usa el costo neto con
  compatibilidad para servidores anteriores. `totalCost` y `totalProfit`
  históricos se conservan; no se redefine silenciosamente su contrato.

No se aplicó reparación de saldos antiguos ni actualizaciones masivas. Si
producción tuvo devoluciones de créditos con inicial, sus registros requieren
un diagnóstico separado antes de cualquier corrección histórica.

### Qué contabiliza y qué no

El recorrido operativo validado registra la venta y su costo/utilidad una sola
vez. El inicial aumenta el dinero recibido y deja la diferencia por cobrar.
Los cobros posteriores reducen esa deuda y entran en su fecha/turno de cobro;
no vuelven a registrar venta, utilidad ni salida de inventario. Se contrastó
este criterio de reconocimiento con la referencia primaria
[IFRS 15](https://www.ifrs.org/issued-standards/list-of-standards/ifrs-15-revenue-from-contracts-with-customers/),
que reconoce el ingreso al transferir los bienes o servicios. Esta comprobación
del software no constituye certificación fiscal o contable.

El módulo llamado **Contabilidad** no crea actualmente un asiento automático
de partida doble desde cada `Sale`/`SaleCreditPayment`: administra cierres
declarados, depósitos y documentos. Por tanto, sí se verificaron las cuentas
por cobrar operativas, caja, abonos y reportes; no se declara implementado un
libro mayor automático. Incorporar ese libro es un alcance adicional, con
cuentas y políticas que deben definirse explícitamente.

### Evidencia adicional ejecutada

- Backend: **148 PASS, 10 suites**, incluida matriz de devoluciones, replay,
  concurrencia, límite de crédito, empresas, caja e informes. Registro
  `.uat/credit-accounting-final-backend.log`. Sustituye el recuento anterior
  de 99 para esta batería; no se suman resultados solapados.
- Compilación TypeScript: PASS después de los cambios de contabilidad.
- Análisis final Flutter de los nueve archivos de unificación, pantalla,
  reportes y prueba nativa: sin incidencias,
  `.uat/credit-unification-final-analyze.log`.
- A4 y plantillas fiscales/descuentos: **40 PASS** en
  `.uat/credit-a4-regression.log`.
- Reportes Flutter y compatibilidad de KPI: **11 PASS** en
  `.uat/credit-report-ui.log`.
- Repetición de toda la carpeta de impresión y durabilidad de abonos:
  **212 PASS**, `.uat/credit-unified-final-printing.log`. Es una selección
  diferente de la batería anterior de 222; no sustituye ni suma esos casos.
- **5 escenarios contables HTTP/PostgreSQL PASS**:
  `scripts/uat/credit-accounting-flow.cjs`,
  `.uat/credit-accounting-http-verified.log` y
  `.uat/credit-ticket/accounting-evidence.json`. Incluyen devolución sin
  reembolso, abono por transferencia y replay, devolución superior a la deuda,
  devolución total sucesiva y cobro actual de factura de otro período/turno.
  Se guardan snapshots de factura, pagos, stock, cliente, caja y reportes.
- En el caso histórico: venta anterior RD$2,500/utilidad RD$1,500 sin
  repetirse; hoy venta/utilidad cero y cobro RD$500 en la caja actual. El saldo
  del cliente pasa a RD$1,000; un único evento para el POST repetido.
- **Windows nativo PASS** con el PDF A4 final:
  `.uat/credit-a4-native-windows.log`. Se usaron los controles reales de
  abonar y saldar, dos POST confirmados, misma factura y saldo final cero.
  `windows-real-invoice.pdf` se extrajo y renderizó: una página A4 con compra
  RD$2,500, acumulado RD$1,500 y pendiente RD$1,000 tras el primer abono.
  La pantalla renderizó también la factura saldada. No se imprimió físicamente.

Dictamen actualizado: **GO para el flujo operativo y documental local
validado**. La contabilidad general automática, los posibles saldos históricos
afectados y la aceptación de hardware/plataformas no ejecutadas no se consideran
cerrados por estas pruebas. Sin producción, despliegue ni commit en esta tarea.

## Aceptación física de la impresora térmica

El usuario autorizó probar primero `2C-POS80-01-V8 Printer(2)` / USB003 y,
si era necesario, `2C-POS80-01-V8 Printer` / USB001. No se usó ni cambió la
SEWOO predeterminada, que tenía 17 trabajos previos. No se cambió la impresora
predeterminada ni la configuración de producción.

El arnés nativo permite imprimir exclusivamente mediante la opción explícita
`CREDIT_PHYSICAL_PRINTER`; sin ella mantiene su comportamiento sin papel.
Se usa `UnifiedTicketPrinter.reprintSale`, una copia por estado, con el modo
automático y el transporte real de Windows, sin mocks de impresión ni pulso
de gaveta. Empresa/configuración visual son de laboratorio; ventas y abonos
usan API real y PostgreSQL local aislado. Los PDF `physical-*.pdf` son
exportaciones térmicas auxiliares; no son capturas del papel ni los bytes del
transporte HTML/PDF usado por el controlador.

### USB003: impresión parcial de la secuencia

Se enviaron los tickets inicial y de abono. El usuario confirmó:
«Sí, salieron dos tickets». Windows seguía mostrando ambos trabajos en cola,
con `WorkOffline` y estado nativo desconocido; esa cola no prueba ausencia de
papel. El proceso nativo no completó la prueba y se conserva el fallo en
`.uat/credit-physical-usb003.log`. No se atribuye una causa no demostrada.
El arnés invocaba la segunda impresión con el visor PDF abierto; la repetición
cierra el visor antes de imprimir, como ocurre al usar el botón de la ficha.
No se modificó código de producción para ocultar el fallo.

Solo se cancelaron los trabajos propios 2 y 3, identificados por sus nombres
`Ticket 13558625_*`, para evitar una salida posterior repetida. El abono ya
confirmado se conservó: acumulado RD$1,500, deuda RD$1,000 y un evento. La
siguiente ejecución usó otra empresa/factura sintética, sin borrar la anterior.
USB003 no recibe aceptación de la secuencia completa.

### USB001: secuencia completa PASS

Comando desde `apps/fulltech_app` con
`FULLPOS_WINDOWS_CHANNEL=uat-mayoreo`:

```powershell
flutter test --no-pub integration_test/credit_ticket_native_test.dart -d windows --dart-define=CREDIT_TICKET_LAB_DIR=C:/t/fp-credit-20261126/.uat/credit-ticket '--dart-define=CREDIT_PHYSICAL_PRINTER=2C-POS80-01-V8 Printer'
```

Compilación Windows y prueba nativa: **PASS**,
`.uat/credit-physical-usb001.log`. Se imprimieron los tres estados de la misma
factura de RD$2,500:

| Estado | Abonado | Pendiente |
| --- | ---: | ---: |
| Inicial | RD$1,000 | RD$1,500 |
| Tras abonar RD$500 | RD$1,500 | RD$1,000 |
| Tras saldar RD$1,000 | RD$2,500 | RD$0 |

El usuario confirmó: **«Sí, los tres salieron completos»**, en respuesta a la
pregunta que incluía los tres pares de importes y ausencia de recortes. Las
dos colas 2C quedaron sin trabajos. No se presupone una inspección por cámara:
la aceptación del papel procede de la confirmación directa del usuario.

SQL independiente: una factura, dos eventos de cobro por RD$1,500 posteriores
al inicial, pagado RD$2,500, deuda cero y stock 19 de las 20 unidades iniciales.
Abonar/reimprimir no creó ventas ni descontó más unidades. El snapshot
`hardware-usb001-sql-after-first-payment.json` se tomó durante la ejecución,
tras el primer abono; no se presenta como un snapshot anterior a la venta.

Evidencias ignoradas en `.uat/credit-ticket/`: `physical-acceptance.json`,
`physical-usb001-submissions.json`, `physical-usb003-submissions.json`,
`hardware-usb001-sql-after.json` y `hardware-usb003-sql-after.json`.
Se conservan todos los datos de ambas ejecuciones. La API y el contenedor
propios se detuvieron al terminar, sin eliminar sus datos.

**GO para el recorrido de crédito y la impresión térmica física USB001
validada**. Esto no despliega cambios, no certifica otros dispositivos y no
cierra la ejecución incompleta de USB003 ni el libro mayor automático pendiente.

## Rectificación tras la foto: recorte real del estado de cuenta

El usuario informó después que los tickets eran iguales y aportó una foto:
el papel finalizaba en TOTAL, sin abono ni saldo. Esa evidencia invalida el GO
anterior del contenido del papel, aunque Windows aceptase los trabajos y el
usuario hubiera confirmado inicialmente que salieron completos. El proceso de
validación anterior fue insuficiente: los PDF auxiliares `physical-*.pdf`
procedían de `TicketBuilder`, no del renderizador utilizado por la impresora.

**Causa reproducida:** `HtmlThermalReceiptPdfRenderer` limitaba el PDF a una
altura estimada. No medía todos los saltos del nombre largo, encabezado,
cliente, efectivo y saldo. Con los mismos campos de la foto, el PDF real de
Windows quedaba truncado justo después de TOTAL. Las seis nuevas regresiones
(58/80 mm, inicial/abono/saldado) fallaron con ausencia de ABONADO antes del
arreglo: `.uat/credit-clipped-exact-before.log`.

**Corrección:** ese renderizador usa la altura automática ya soportada por
`pdf`, medida a partir de la columna completa, en vez del cálculo aproximado.
No cambia importes, documentos, autorización ni datos persistidos. El PDF
80 mm reproducido pasó de 100 mm a aproximadamente 125.46 mm; se extrajo su
texto y se revisó la imagen completa con ABONADO y SALDO PENDIENTE visibles.

Las regresiones ahora comprueban el texto del PDF de esa ruta, los importes
esperados por etapa, la presencia del pie y los límites verticales del texto;
no basta con que el archivo tenga bytes. Artefactos `windows-layout-*.pdf`
y `windows-layout-fixed.png`. Batería de impresión y durabilidad: **218 PASS**,
`.uat/credit-clipping-regression.log`; análisis focalizado sin incidencias,
`.uat/credit-clipping-analyze.log`.

Para la prueba solicitada se abre la aplicación Windows completa contra
`127.0.0.1:14627`, base PostgreSQL aislada existente y raíz local exclusiva
`.uat/credit-manual-app`. El lanzador ignorado
`apps/fulltech_app/.uat/credit_manual_main.dart` prepara la sesión sintética
mediante el login real; después se ejecuta el `lib/main.dart` normal. No sustituye ventas,
créditos, permisos, licencia, backend ni transporte de impresión. Configura
solo la impresora local de esta raíz UAT: USB001, 80 mm, una copia y sin gaveta.
Se preparan un cliente y un producto de RD$2,500 con 50 unidades; el usuario
creará la venta desde Facturación. No se crean ventas para esa empresa durante
la preparación ni se modifica producción.

**Estado vigente:** corrección local y regresiones PASS; **pendiente aceptar
de nuevo el contenido del papel** mediante la venta manual. No se declara
cerrada la impresión física corregida antes de observar esa nueva evidencia.

La app completa se dejó abierta en Facturación, sin bienvenida modal, con el
artículo de RD$2,500/50 unidades y turno cerrado para que lo abra el usuario.
Se verificó la ventana real con la habilidad de control de Windows. El primer
lanzador temporal provocó un aviso de zona de Flutter al preparar la sesión
antes de llamar a `main`; se separó esa preparación del arranque normal. La
ventana final ejecuta `lib/main.dart` sin ese aviso. Registro
`.uat/credit-manual-final.log`; API local y PostgreSQL permanecen activos para
la prueba manual solicitada. La batería focalizada final pasa **15 pruebas**
con los importes de cada estado y el pie completos; análisis final sin
incidencias en `.uat/credit-clipping-final-analyze.log`.

## Presentación de «Monto exento» con impuestos desactivados

El usuario observó el rótulo en la nueva prueba manual. La consulta de solo
lectura de esa empresa local confirmó `fiscalTaxEnabled=false`, impuesto cero,
base gravada cero e importe exento interno RD$2,500. El servidor conserva ese
desglose aun cuando el cálculo de impuestos está desactivado. El error era
mostrar el importe exento como información fiscal solo por ser mayor que cero.

Se corrige exclusivamente la presentación en HTML, PDF térmico de Windows,
ESC/POS, texto y PDF térmico tradicional. El importe exento interno no activa
por sí solo el desglose. Se conserva cuando la venta tiene impuestos activos,
un documento electrónico o valores gravados/impuestos históricos positivos.
Se utiliza el estado guardado de la venta, no la configuración actual de la
empresa para reinterpretar una factura antigua. El PDF A4 ya respetaba el
indicador y no precisó cambios. No se alteran datos, impuestos ni saldos.

Dos regresiones (58/80 mm, impuestos desactivados) fallaron antes del arreglo;
los casos con impuestos activos conservan el rótulo y los importes. La batería
posterior pasa **222 pruebas**, `.uat/credit-tax-presentation-regression.log`.
Análisis de los siete archivos afectados: PASS,
`.uat/credit-tax-presentation-analyze.log`.

Se actualizó mediante `flutter attach` / hot reload la misma app local abierta,
conservando la sesión para que el usuario reimprima su factura. Evidencia
`.uat/credit-tax-hot-reload.log`; sin nueva venta, cobro o impresión automática.
La comprobación de ese nuevo papel queda a cargo de la siguiente reimpresión.

## Verificación profunda del ejecutable y del PDF enviado

El usuario volvió a observar «Monto exento». Se retiró también la afirmación
anterior de que el hot reload hubiera aplicado el ajuste: el registro exacto
decía `Reloaded 0 libraries`. Un código cero del comando no demuestra que se
haya actualizado la versión cargada. El ayudante local ahora rechaza ese
resultado vacío. La app se cerró tras comprobar que el ticket en edición
estaba vacío, y se recompiló por completo; no se cambiaron datos para ocultar
el rótulo.

Consulta de las dos facturas manuales: impuestos desactivados, impuesto y base
gravada cero. Se autenticó de nuevo la cuenta sintética por la API al caducar
su token, sin cambiar permisos ni saldos. Se obtuvo `/sales/:id` de la factura
actual: total RD$5,000, abonado RD$2,900 y pendiente RD$2,100.

La nueva regresión nativa
`integration_test/credit_exact_print_payload_test.dart` ejecuta el generador
compartido de impresión con esa respuesta real y la configuración local de
la impresora. Intercepta el callback de `ThermalPrinterService` solo para
guardar y examinar los bytes; después delega en `Printing.directPrintPdf`
real con **los mismos bytes**, una copia y la USB001. No sustituye el resultado
de impresión ni usa el PDF térmico alternativo como prueba del controlador.
Solo el encabezado de la empresa se identifica como laboratorio.

**PASS:** compilación Windows, prueba nativa y análisis de ese archivo.
Registros `.uat/credit-exact-native-print.log` y
`.uat/credit-exact-print-analyze.log`. El PDF exacto
`.uat/credit-ticket/exact-windows-sent.pdf` no contiene EXENTO, GRAVADO ni ITBIS;
contiene el abono RD$2,900, el saldo RD$2,100 y el pie dentro de la página.
Se extrajo también con una herramienta independiente y se revisó la imagen.
Una sola copia enviada, sin POST financieros. Los snapshots SQL completos
`exact-print-sql-before.json` y `exact-print-sql-after.json` coinciden en venta,
artículos, importes y eventos de pago.

Después se vuelve a ejecutar `flutter run -d windows` con `lib/main.dart`,
las mismas banderas UAT y la raíz exclusiva de datos. Registro de compilación
nueva `.uat/credit-manual-rebuilt.log`. La aceptación del papel de esa copia
exacta se solicita al usuario; no se infiere del estado de la cola.

Verificación adicional desde la interfaz real: se abrió Historial de créditos
en la app recompilada, se seleccionó la factura visible **62793923** (RD$5,000,
abonado RD$2,900, pendiente RD$2,100) y se pulsó **Imprimir**. Se observó
«Trabajo enviado a la cola de Windows» y el registro del transporte HTML/PDF
de Windows por USB001, 80 mm, una copia. Esta segunda impresión usa el
encabezado normal de la empresa de prueba; la primera copia nativa tenía el
encabezado de laboratorio. No se registraron ventas ni abonos en estas acciones.
La app quedó abierta en esa factura para continuar la comprobación del papel.

## Refinamiento del historial de créditos

Cambios solicitados por el propietario en `sales_credit_screen.dart`:

- Filtro cuadrado de36px, igual al buscador. Resumen de selección y contador a
  la derecha de esa misma barra; el contador respeta búsqueda y filtros.
- Se retiran el contador del appbar, el encabezado repetido de lista y «Crear
  nuevo crédito», también del vacío. La creación sigue en Facturación.
- Detalle más alto, estado pendiente naranja con contraste y un único total
  abonado. Se conservan los importes por canal y las notas del cliente; se oculta
  únicamente la nota automática exacta «Pago: Crédito». No se muestra una sección
  vacía de pagos si una venta antigua no tiene detalle de canales.
- Solo Registrar abono, Saldar y Eliminar crédito en el detalle, tanto PC como
  móvil. Los botones se ajustan en varias filas para seguir visibles a menor
  ancho; no se relegan soluciones a un menú de más opciones. Eliminar conserva
  su restricción de administrador, confirmación y llamada existentes. Abonar y
  Saldar se deshabilitan cuando no queda deuda. No se cambiaron repositorios,
  endpoints, cálculos, validaciones o reglas financieras en este refinamiento.
- Imprimir y PDF quedan en la lista. La antigua acción de abonar en fila abre
  ahora la factura PDF compartida. Se eliminan los accesos directos de compartir
  del detalle; las capacidades del visor PDF existente se conservan.
- La búsqueda reconoce el número de factura impreso. Cuando una búsqueda oculta
  la selección anterior, la fila seleccionada y el detalle coinciden con un
  resultado visible. Los nombres del cajero no usan UUID como sustituto visible.

Regresiones: **34 PASS en Windows** (26 pruebas de historial/crédito/cotización
y8 de durabilidad de abonos), `.uat/credit-layout-final-tests.log`;
**14 PASS en Linux**, `.uat/credit-layout-linux-final.log`. Se compararon las
referencias visuales en390/1024/1920/2560px y el detalle móvil. Se actualizaron
solo las referencias de créditos afectadas. Análisis de pantalla y pruebas sin
incidencias, `.uat/credit-layout-verified-analyze.log`. Se documentó el estilo
en `docs/DESIGN_SYSTEM.md`.

El primer test del detalle móvil necesitó habilitar los tickers del arnés para
que la animación modal concluyera; el caso inicialmente fallido se conserva en
`.uat/credit-layout-all-first.log`. No se suprimieron aserciones ni se cambió el
comportamiento del producto para superarlo. La repetición completa pasó y se
inspeccionaron las imágenes del detalle móvil y los anchos de escritorio.

La app Windows se recompila por completo sobre la misma API y datos locales,
registro `.uat/credit-layout-windows-app.log`, para comprobación funcional de
los botones. Las pruebas visuales no ejecutan eliminaciones ni cobros reales.

**Aceptación funcional Windows del refinamiento:** se observó la pantalla
recompilada maximizada con los dos créditos locales. PDF desde la fila abrió y
renderizó la factura A4 de RD$5,000, abonado RD$2,900 y pendiente RD$2,100.
Registrar abono abrió su formulario; Saldar precargó RD$2,100; Eliminar crédito
abrió la confirmación existente. Los tres formularios se cancelaron y se dejó
el historial visible, sin modales. Los snapshots completos
`credit-layout-sql-before.json` y `credit-layout-sql-after.json` confirman las
dos facturas, artículos y abonos sin cambios; stock47, igual al observado antes.
La comprobación de permisos y del estado saldado se cubre además en regresiones.
**GO local para el refinamiento del historial**, sin publicación ni commit.

### Segunda distribución del detalle para ventanas pequeñas

Se prioriza el ancho del detalle (mínimo420px en la vista de dos columnas),
con12px de margen de página, separación de10px y menor margen vertical en
ventanas menores de1360px. Cliente/teléfono y cajero/estado usan dos columnas;
la factura y fecha permanecen una sola vez en el encabezado. Efectivo y
transferencia se reparten horizontalmente y los tres totales ocupan una fila.
Se reduce el relleno de las tarjetas de producto y su separación vertical.

Las acciones dejan de envolver: se mantienen en una fila de tres botones,
con los nombres Abonar/Saldar/Eliminar cuando falta ancho y tooltips completos.
Se reservan los importes íntegros en las filas estrechas de créditos para no
recortar cifras al ampliar el detalle; el nuevo parámetro de
`HistoryDocumentRow` es optativo y mantiene el comportamiento de los demás
historiales. El appbar ubica Turno antes de Actualizar.

Validación: **38 PASS Windows** (30 del historial y8 de durabilidad),
`.uat/credit-compact-final-tests.log`; **18 PASS Linux**,
`.uat/credit-compact-linux-final.log`. Incluye cuatro comprobaciones nuevas de
alineación, columnas y acciones en860/1266px con escala de texto1/1.35, además
de las vistas390/1024/1920/2560px. Análisis de los tres archivos sin incidencias,
`.uat/credit-compact-verified-analyze.log`. Se inspeccionaron las referencias
compactas860/1266 y el detalle móvil; todos los importes y los tres botones
permanecen dentro de su área. La app Windows se recompila por completo con
los mismos datos locales en `.uat/credit-compact-windows-app.log`.

Se observó la app recién compilada en la ventana normal1266px, con la factura
62793923: cliente/teléfono/cajero/estado completos, ambos canales de pago y la
tarjeta de producto visibles; totales y tres botones en una sola línea cada
uno, sin saltos. Actualizar quedó después del turno. Los snapshots completos
`compact-detail-sql-before.json` y `compact-detail-sql-after.json` confirman
ambas facturas y sus abonos sin modificaciones. Se deja abierta esa pantalla.
**GO local del detalle compacto**, sin cambios en producción ni commit.

### Rediseño térmico de 80 mm: primera prueba física, ajustes pendientes

Alcance: exclusivamente presentación del PDF térmico utilizado por el motor
real de impresión; no se cambian importes, contratos, pagos ni reglas fiscales.
El HTML de demostración no es el renderizador utilizado por la app y no se
utiliza como evidencia de la salida Windows.

La consulta GDI de la impresora 2C-POS80-01-V8 Printer / USB001 reporta
203 dpi, HORZRES576 y ancho imprimible72.07mm, con offset horizontal0.
El plugin `printing` renderiza a escala física y no reduce automáticamente
la página de80mm a ese ancho: ampliar el contenido hasta los80mm lo recortaría.
Se conserva contenido de71.5mm, con0.25mm de margen dentro del área imprimible;
los bloques de totales y pagos pasan de50mm a71.5mm. No se modifica el driver.
Evidencia: `.uat/credit-ticket/thermal-80-device-caps.json`.

Se elimina el recuadro y espacio de LOGO cuando no hay imagen en la empresa;
se conserva la imagen configurada. Fuente Manrope Medium/Bold incrustada,
sin descarga en tiempo de impresión, para mantener caracteres españoles.
Artículos e importes usan una sola línea ajustada al ancho; los nombres
extremadamente largos reducen su tamaño para conservar el texto completo,
sin elipsis. Los descuentos y detalles tributarios asociados se conservan.
También permanecen empresa, cliente, NCF/vencimiento, e-CF/QR, cajero,
fecha/hora, notas, garantías, efectivo, devuelta, abonos y saldo cuando aplican.
El formato58mm conserva su distribución anterior.

Se detectaron y corrigieron dos fallos durante el trabajo: carga concurrente
de assets con futuros síncronos en el arnés de pruebas, y expansión vertical
de `FittedBox` al recibir ancho mínimo obligatorio. La carga es secuencial y
las líneas tienen altura acotada. Los fallos iniciales permanecen registrados
en `.uat/thermal80-first-tests.log` y `.uat/thermal80-layout-tests.log`
(este último contiene la última ejecución del caso corregido).

Validación: **217 PASS** en toda la carpeta de pruebas de impresión,
`.uat/thermal80-all-printing-tests.log`; análisis de los tres archivos de
renderizador/pruebas sin incidencias, `.uat/thermal80-analyze.log`.
Las regresiones nuevas comprueban texto íntegro, caracteres españoles,
ausencia de LOGO y exento con impuestos desactivados, ancho útil, alturas,
artículo en una línea, totales alineados, importes grandes, logo real,
descuentos, cliente, NCF, notas y garantía. Se revisaron los PDFs rasterizados.

**PASS nativo Windows**: `.uat/thermal80-native-print.log`. Una sola copia
de la factura local87689455, total2500/abonado520/pendiente1980, enviada a
USB001 por `UnifiedTicketPrinter` y el plugin Windows reales. Se inspeccionan
y conservan exactamente los mismos bytes enviados, no un PDF alternativo:
`.uat/credit-ticket/exact-windows-sent.pdf` y `thermal80-exact-windows.png`.
La respuesta GET completa de la venta persistida es idéntica antes/después,
`thermal80-sale-before.json` / `thermal80-sale-after.json`; no se registró
venta ni abono nuevo. No se tocó producción ni otra cola de impresora.

El usuario confirmó que salió papel, pero indicó **«necesita ajustes»**.
Pendiente su detalle de los ajustes: no se concede aceptación física final
ni GO visual del ticket. La app se recompila en frío sobre el laboratorio
existente, `.uat/thermal80-windows-app.log`, para continuar las pruebas.

Investigación primaria de referencia (el modelo local no se identifica como
Epson): guía oficial TM-T20III, área72mm/576puntos para rollo80mm,
<https://download4.epson.biz/sec_pubs/bs/pdf/TM-T20III_trg_en_revF.pdf>.
El límite usado procede de la consulta local de la impresora 2C.

### Ajuste solicitado tras revisar el papel: artículos y totales compactos

Se amplía la descripción de34.5mm a39.5mm, reduciendo la columna de cantidad
a6mm y las de precio/importe a13mm. El margen interno horizontal del nombre
baja de1.4pt a0.5pt y el nombre utiliza Manrope Bold (peso700) en una línea.
No se amplía el ancho físico de impresión ni se truncan nombres o cifras.

Los totales y pagos ocupan un bloque de53mm pegado a la derecha; etiquetas
e importes se alinean a la derecha en columnas consistentes, con separación
de2mm y columna de importe21mm. Se eliminan los bordes del total, se reduce
el espacio vertical de sus filas y se dejan3mm entre artículos y totales.
Las etiquetas de80mm pasan a TOTAL COMPRA / ABONADO / PENDIENTE / EFECTIVO /
DEVUELTA. La abreviación no modifica el significado ni el origen de los
importes. El resto de la información y el formato58mm se conservan.

Regresión:217 PASS, `.uat/thermal80-compact-printing-tests.log`; tras ajustar
la columna de importe a21mm,22 PASS de los casos afectados,
`.uat/thermal80-compact-final-focused.log`. Se comprueba además que las
etiquetas terminen en la misma coordenada horizontal. Análisis de cuatro
archivos sin incidencias, `.uat/thermal80-compact-analyze.log`. Se inspeccionó
la rasterización a203dpi en `thermal80-compact-preview.png`. Aceptación del
nuevo papel pendiente; se prepara otra única reimpresión local.

Reimpresión ejecutada: **PASS nativo Windows**, una copia en USB001,
`.uat/thermal80-compact-native-print.log`. Bytes exactos conservados en
`exact-windows-sent.pdf`, rasterizados a203dpi en
`thermal80-compact-exact-windows.png`: compra2500, abonado520, pendiente1980.
La app se recompila en frío en `.uat/thermal80-compact-windows-app.log`.
No se considera aprobada la legibilidad física hasta respuesta del usuario.

El usuario respondió **«Todavía necesita ajustes»** a esta segunda copia.
Se solicita el detalle concreto antes de otro cambio de diseño. Sigue sin
GO visual. La app principal compiló e inició contra14627; su log contiene
una advertencia del framework RawKeyboard por un evento Alt Left, ajena al
renderizador del ticket. No se modifica el manejo de teclado en esta tarea.
`thermal80-compact-sale-after.json` confirma la venta persistida íntegra
sin cambios tras esta segunda reimpresión.

### Normalización tipográfica solicitada después de la segunda copia

El usuario aprobó la distribución y pidió uniformidad de letra y tamaño,
sin negrita generalizada. El ticket80mm utiliza ahora Roboto Condensed Regular
a9pt como base para empresa, factura, cliente, etiquetas, artículos, títulos
de columnas, notas y pie. Los totales destacados utilizan Medium500 del mismo
tamaño, en lugar de Bold700. El formato58mm permanece independiente.
Las cadenas que excedan el ancho todavía pueden reducirse para conservar
su contenido en una línea; no se promete tamaño fijo para longitud ilimitada.

Se reserva8mm para CANT y37.5mm para el nombre: todos los textos del ejemplo
comercial, incluidos CANT/ITEM/PRECIO/TOTAL y cliente/valor, se comprobaron
a9pt mediante extracción del PDF. Se conserva el resto de la distribución.
El pie e-CF admite un estilo opcional para que este ticket use la misma
tipografía; no cambia el contenido fiscal ni la geometría del QR, ni los
otros consumidores del pie compartido.

Fuentes oficiales y licencia SIL OFL1.1 conservada en
`assets/fonts/RobotoCondensed-OFL.txt`. Origen:
<https://github.com/google/fonts/tree/main/ofl/robotocondensed>.
Variable original `RobotoCondensed[wght].ttf`, SHA256
`dace262afcee68a5276f200d8026c57221735c0118ab5fda8c2c0d3dc409a8d0`.
Se generan instancias estáticas400/500 con
`fontTools.varLib.instancer.instantiateVariableFont`, `updateFontNames=True`;
ambas se incluyen como assets y se incrustan sin conexión durante la impresión.

Las regresiones verifican familia, tamaño9pt en cada palabra del ejemplo,
ausencia de negrita en cliente/artículos/encabezados y alineación, además de
conservar las comprobaciones fiscales y financieras anteriores. El primer
intento confundía el nombre de familia devuelto por Syncfusion con el nombre
PostScript: se corrigió esa aserción; PyMuPDF confirma por separado las caras
Regular/Medium realmente incrustadas. No se cambió el producto para superar
esa diferencia de los extractores.

Validación final tipográfica: **217 PASS**, registro
`.uat/thermal80-type-final-printing-tests.log`; análisis de tres archivos sin
incidencias, `.uat/thermal80-type-analyze.log`. **PASS nativo Windows**, una
copia por USB001, `.uat/thermal80-type-native-print.log`. Los bytes realmente
enviados (`exact-windows-sent.pdf`) se examinaron con PyMuPDF:35 fragmentos,
todos9pt, fuentes RobotoCondensed-Regular/Medium, sin sustitución de fuente.
Se conservan `thermal80-type-evidence.json` y la rasterización203dpi
`thermal80-type-exact-windows.png`. Se solicita la aceptación del papel;
permanece pendiente, sin afirmar GO visual. La app se recompila en frío,
`.uat/thermal80-type-windows-app.log`.

### Totales mínimos sin importes repetidos — 2026-11-27

El usuario aprobó tipografía/distribución y señaló repeticiones en la factura
local14925698. Causa: `_paymentDescription` ya aporta método e importe;
el renderizador añadía nuevamente el total a su derecha, luego efectivo
recibido y la nota automática de pago. SUBTOTAL también aparecía siempre.

Solo para el PDF80mm: una venta sencilla muestra TOTAL y DEVUELTA, incluso0.
SUBTOTAL aparece con descuentos, desglose fiscal, e-CF o cuando su importe
difiere del total. Se conservan los impuestos/exentos que correspondan.
Crédito muestra TOTAL, ABONADO, PENDIENTE y DEVUELTA; se evita TOTAL COMPRA
cuando repite TOTAL, pero se conserva si su importe es distinto. Transferencia
conserva el método sin duplicar el monto total; mixto muestra cada asignación
una sola vez y sin recalcular cantidades. No se imprime efectivo recibido.

Se retiran únicamente líneas de nota que coinciden exactamente con metadatos
automáticos conocidos de checkout (`Pago: Efectivo/Crédito/Transferencia/
Mixto/Tarjeta`). No se elimina por prefijo genérico: `Pago: pendiente de
entrega` y cualquier otra nota genuina permanecen. El view model conserva
adicionalmente `originalNote`, ya que la versión normalizada aplanaba los
saltos de línea e impedía distinguir metadatos de notas del cliente. Los
otros renderizadores conservan su campo anterior, y58mm su comportamiento.

Regresiones: **227 PASS** en toda la carpeta de impresión,
`.uat/thermal80-minimal-printing-tests.log`. Incluye diez casos nuevos:
efectivo exacto/con devuelta, crédito sin abono/parcial/saldado, transferencia,
mixto, descuentos/ITBIS, notas genuinas frente a metadatos y compatibilidad58mm.
El primer fallo detectó la pérdida de saltos de línea de las notas y quedó
registrado en `.uat/thermal80-minimal-first.log`; el caso corregido pasa.
Se revisó a203dpi `thermal80-minimal-preview.png`: solo TOTAL y DEVUELTA0.
No cambian estilos aprobados, datos persistidos ni cálculos financieros.

Se añadieron y ejecutaron dos comprobaciones adicionales: crédito mixto con
abono/reparto y un importe legado de compra distinto del total, que debe
conservarse. **12 PASS** de casos mínimos (incluidos los diez ya comprendidos
en la ejecución completa), `.uat/thermal80-minimal-final-cases.log`; no se
suman como pruebas distintas las ejecuciones solapadas. Análisis final de
cinco archivos sin incidencias, `.uat/thermal80-minimal-final-analyze.log`.

**PASS nativo Windows** de la misma factura14925698 de la fotografía, una
copia en2C/USB001, `.uat/thermal80-minimal-native-print.log`. Se conservaron
los bytes exactos enviados en `exact-windows-sent.pdf` y la rasterización
`thermal80-minimal-exact-windows.png`: solo TOTAL2500 y DEVUELTA0 después de
los artículos, sin SUBTOTAL, PAGO, EFECTIVO ni NOTA automática. Comparación
íntegra GET antes/después idéntica (`thermal80-minimal-sale-before.json` /
`thermal80-minimal-sale-after.json`). No se creó ni modificó operación alguna.
Aceptación del papel solicitada y pendiente. App principal recompilada en
frío en `.uat/thermal80-minimal-windows-app.log`, contra la misma API local.

### Restauración de NOTA y verificación fiscal — 2026-11-27

El usuario confirma correctos los importes mínimos y solicita restaurar la
línea bajo los totales, NOTA y `Pago: Efectivo`, antes del agradecimiento.
Se restaura esa sección para80mm, deduplicando sus metadatos para que el
método aparezca una sola vez, sin otro monto. La nota se genera también
cuando no existe una nota automática guardada. Las notas genuinas permanecen.
Transferencia y otros métodos se identifican en NOTA, evitando duplicarlos
en los totales; las asignaciones de un pago mixto conservan sus importes.
Crédito se identifica como Crédito y mantiene abonado/pendiente. Tipografía,
distribución, cálculos, datos y58mm no cambian.

Verificación de233 pruebas de impresión sin fallos en
`.uat/thermal80-restored-all-tests.log`; análisis de cuatro archivos sin
incidencias, `.uat/thermal80-restored-analyze.log`. Se añaden además dos casos
explícitos B01/B02: los seis escenarios fiscales pasan en
`.uat/thermal80-restored-final-fiscal.log` (incluye cuatro ya comprendidos en
la ejecución general, no se suman las ejecuciones solapadas).

Para B01/B02 se comprueban NCF, RNC, vencimiento y nota de pago. Para e-CF
firmado/contingencia se comprueban e-NCF, emisor/receptor, vencimiento, montos,
ITBIS, código de seguridad, fecha de firma y QR; pendiente/rechazado conservan
avisos y no reciben un timbre inventado. Las imágenes de los PDF se revisan
y los QR de los dos primeros estados se decodifican a203dpi con OpenCV,
recortando solo la región QR sin remuestreo: el contenido coincide exactamente
con el URL de consulta de la proyección fiscal sintética. La detección inicial
de página completa no era fiable; la lectura de la región QR sí lo fue.
Evidencia: `restored-fiscal-qr-evidence.json` y PDFs/PNG `restored-fiscal-*`.
No se emite ni valida un documento fiscal real ante DGII en estas pruebas.

Referencia primaria consultada: preguntas técnicas e-CF de DGII, preguntas14/15,
<https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Preguntas%20frecuentes/T%C3%A9cnicas/Preguntas%20T%C3%A9cnicas%20e-CF.pdf>.
El QR utiliza el timbre electrónico proporcionado; no se construye un QR
fiscal artificial para un NCF tradicional ni para una venta normal.

**PASS nativo Windows**, una reimpresión de14925698 a2C/USB001,
`.uat/thermal80-restored-native-print.log`. Los mismos bytes enviados muestran
TOTAL2500, DEVUELTA0, línea, NOTA, Pago:Efectivo y agradecimiento, en ese orden
y sin repetir método o montos. Evidencia `thermal80-restored-exact-windows.png`
y `exact-windows-sent.pdf`. La consulta antes/después conserva íntegra la
venta (`thermal80-restored-sale-after.json`); el token local expirado se
renovó por el login normal antes de esa comprobación. No se cambió seguridad.
La app se recompila en frío en `.uat/thermal80-restored-windows-app.log`.
El usuario había aprobado tipografía y totales mínimos; la salida restaurada
se envió para su revisión física, sin afirmar aceptación del nuevo papel.
