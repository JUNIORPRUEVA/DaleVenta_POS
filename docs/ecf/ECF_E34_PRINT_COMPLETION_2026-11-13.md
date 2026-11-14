# Cierre local de representación fiscal E34 — 13/11/2026

## Solicitud y alcance

El propietario aclaró que la impresión comercial ya funciona y pidió adaptar
únicamente la información fiscal, conservando las impresoras y su configuración.
Se completó la impresión independiente de E34, pendiente del ciclo anterior de
E31/E32. No se cambiaron drivers, selección de impresora, transportes ni
configuración de dispositivos en este ciclo.

HECHO: la adaptación está implementada y verificada localmente. No se publicó,
no se activó producción y no se hicieron nuevas emisiones a DOSA/DGII. Estas
pruebas no equivalen a certificación normativa ni a un ensayo físico.

## Flujo implementado

1. Detalle del comprobante → **Imprimir ticket** / **Ver PDF fiscal**.
2. Consulta nueva `GET /ecf/documents/:id/print`, con JWT, permiso
   `viewEcfDocuments`, UUID, empresa autenticada y ambiente configurado.
3. Proyección pública explícita de los datos fiscales persistidos: identidad,
   cantidades, precios, descuento, bases e ITBIS. No devuelve respuestas crudas,
   credenciales ni resúmenes internos del proveedor.
4. El ticket utiliza `UnifiedTicketPrinter.printTicket`, la misma ruta existente
   de impresión. No crea una venta, no prepara ni emite un comprobante, no consume
   secuencias y no llama a la apertura automática de caja de una venta nueva.
5. El E34 muestra su propio e-NCF y sus artículos/importes acreditados, e-NCF y
   fecha del original, texto de modificación y motivo. No incluye vencimiento
   de secuencia de E31. QR, código y firma proceden del sello persistido; un
   documento pendiente o rechazado no recibe un QR inventado.
6. El PDF independiente utiliza los controles compartidos de vista previa,
   impresión, descarga y compartir. Repite identidad y verificación en cada
   página; los subtotales intermedios corresponden a las filas dibujadas por el
   contexto público de paginación de `Table` de pdf 3.11.3.

El servicio no clasifica documentos antiguos por inferencia. Si carecen de
ambiente/documento fiscal reconstruible, la nueva consulta no los presenta como
un comprobante imprimible firmado. Se conservan huellas, idempotencia y datos
persistidos; no se modificó la preparación fiscal para añadir campos nuevos.

La referencia E34 y su vencimiento se contrastaron con la
[documentación primaria de DOSA](https://github.com/alapaix13/DosaInvoicecloud-Documentation/blob/main/NOTAS_CREDITO_DESDE_FACTURA.md).
Las condiciones de QR corresponden a las fuentes oficiales DGII citadas en el
[informe de representación previo](ECF_PRINT_REPRESENTATION_2026-11-13.md).

## Validación ejecutada

API: copia de verificación aislada en
`C:/Users/pc/AppData/Local/Temp/fullpos-ecf-verify-20261112`, sincronizada con los
archivos API actuales. Únicamente PostgreSQL efímero local de la tarea, llamadas
externas y emisión productiva desactivadas. No se usó la base compartida.
Los logs mencionados se encuentran en `%TEMP%`.

```text
npm run api:build
PASS (ecf-e34-build-final.log), Prisma generate + TypeScript.

npm --workspace apps/api run test:unit -- --runTestsByPath src/ecf/documents/ecf-print-view.spec.ts src/ecf/provider/dosa/dosa-print-stamp.spec.ts
PASS: 2 suites, 14 pruebas (ecf-e34-final-unit.log).

npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/ecf-documents-http.e2e-spec.ts src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
PASS: 2 suites, 17 pruebas (ecf-e34-final-http.log).

flutter analyze
PASS, sin incidencias (ecf-e34-analysis-final-closed.log).

flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:3001
PASS, código 0, build/web (ecf-e34-web-build-final.log). Artefacto local de validación,
sin publicación. El dry-run WASM avisa sobre dependencias dart:html/interop;
el build JavaScript solicitado termina correctamente. No se afirma soporte WASM.

flutter test test/features/ecf/ecf_document_print_test.dart test/core/printing test/modules/ventas/sales_pdf_labels_test.dart test/features/ecf/ecf_repository_test.dart test/modules/documentos/pdf_fiscal_templates_test.dart --reporter expanded
PASS: 247 pruebas (ecf-e34-regression.log).

flutter test test/features/ecf/ecf_document_print_test.dart --reporter expanded
PASS: 7 pruebas tras el cierre del E34 y la validación de pantalla estrecha
(ecf-e34-final-render.log), incluido el ajuste final de alineación numérica A4.

git -c core.safecrlf=false diff --check
PASS.
```

Los contadores pertenecen a ejecuciones distintas y no se suman. La regresión de
247 precedió al ajuste final de columnas del nuevo PDF E34, al caso de pantalla
estrecha y al caso de descuento; la suite específica se repitió después. Las pruebas de venta
y PDF anteriores siguen cubriendo las rutas comerciales existentes.

El HTTP verifica la impresión de una nota parcial por su propio ID, importe y
cantidades, referencia original y ausencia de vencimiento/QR pendiente. Verifica
404 para otro tenant y otro ambiente. El HTTP DOSA usa un servidor local
sintético: verifica persistencia y consulta del sello, sin representar una
aceptación real de DGII. No se afirma una nueva prueba externa del POS completo.

La suite unitaria se ejecutó inicialmente con dos filtros que Jest combinó:
235 suites / 2830 pruebas PASS (`ecf-e34-unit.log`). El intento equivalente de
E2E amplio se interrumpió para limitar el alcance; no se declara resultado de
ese intento (`ecf-e34-http.log`). Se ejecutaron después las dos suites HTTP
específicas indicadas arriba, con resultado PASS.

Incidencias corregidas: llaves exigidas por el analizador; captura visual del
widget trasladada a `tester.runAsync` para evitar bloqueo del reloj de prueba;
fuentes reales Manrope/MaterialIcons para inspeccionar texto legible. No se
debilitaron aserciones ni guardas. Los logs conservan los avisos existentes de
ts-jest, fuentes PDF Helvetica y cierre tardío de Jest; los procesos finales
terminaron con código 0.

La revisión final también comprobó que el subtotal fiscal ya es neto: el nuevo
adaptador de ticket lo presenta antes del descuento cuando el renderer existente
muestra una fila negativa separada. Una prueba verifica que una base de 100,
descuento 10 e ITBIS 16.20 produce total 106.20 sin descontar dos veces. No se
modificaron los importes persistidos ni el adaptador de tickets comerciales.

## Evidencia visual

Las muestras son sintéticas y se identifican TEST sin validez fiscal. El QR E34
utiliza un código de seguridad ficticio para probar reproducción y decodificación;
no es evidencia nueva de aceptación ni se debe entregar como documento comercial.

- [Nota A4](../design-research/2026-11-13/ecf-e34-printing/nota-credito-a4.pdf)
- [Ticket 58 mm](../design-research/2026-11-13/ecf-e34-printing/nota-credito-58.pdf)
- [Ticket 80 mm](../design-research/2026-11-13/ecf-e34-printing/nota-credito-80.pdf)
- [Acciones en pantalla estrecha](../design-research/2026-11-13/ecf-e34-printing/acciones-fiscales-mobile.png)
- [Decodificación](../design-research/2026-11-13/ecf-e34-printing/verification.json)

HECHO: las tres páginas decodifican el e-NCF E34 correcto; contienen código de
seguridad, e-NCF original y fecha del original. Se renderizaron mediante PyMuPDF
y se decodificaron con OpenCV. Se inspeccionaron las imágenes A4/térmicas y la
captura de acciones con fuentes de la aplicación; sin recortes de QR ni del pie.
La prueba de varias páginas verifica identidad/referencia/sello repetidos.

## Archivos de este ciclo

- apps/api/src/ecf/documents/ecf-document-query.service.ts
- apps/api/src/ecf/documents/ecf-print-view.ts
- apps/api/src/ecf/documents/ecf-print-view.spec.ts
- apps/api/src/ecf/ecf-documents.controller.ts
- apps/api/src/ecf/ecf-documents-http.e2e-spec.ts
- apps/fulltech_app/lib/features/ecf/ecf_print_document.dart
- apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_documents_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_document_print_action.dart
- apps/fulltech_app/lib/core/printing/models/ticket_data.dart
- apps/fulltech_app/lib/core/printing/ecf_document_pdf.dart
- apps/fulltech_app/lib/core/printing/html/html_thermal_receipt_pdf_renderer.dart
- apps/fulltech_app/test/features/ecf/ecf_document_print_test.dart
- docs/ARCHITECTURE.md
- docs/PRODUCT_SPEC.md
- docs/ecf/ECF_PRINT_REPRESENTATION_2026-11-13.md
- docs/ecf/ECF_E34_PRINT_COMPLETION_2026-11-13.md
- docs/design-research/2026-11-13/ecf-e34-printing/ (muestras, imágenes y verificación)

Se preservaron las ediciones anteriores de la rama; no se atribuyen a este ciclo.
No hubo commit, push, despliegue ni migración compartida.
El contenedor PostgreSQL efímero de la tarea se detuvo al terminar las pruebas,
sin eliminarlo.

## Límite de cierre

HECHO: la adaptación fiscal local del E34 ya utiliza el sistema de impresión
existente. No se requiere rediseñar la configuración de impresoras para este
cambio. Escaneo sobre papel y compatibilidad física no se deducen de un PDF.

NO-GO para declarar todo el módulo publicado y listo en producción: sigue
pendiente resolver explícitamente la clasificación histórica TEST/PRODUCTION
antes de desplegar la migración por ambiente y verificar el recorrido normal
del POS desplegado contra TEST. La vinculación imprimible desde el documento
comercial de devolución y los casos no cubiertos (XML antiguos sin evidencia,
impuestos adicionales y contingencia) no se dan por completados por esta tarea.
No falta solicitar nuevos rangos a Alejandro para las pruebas ya documentadas.
