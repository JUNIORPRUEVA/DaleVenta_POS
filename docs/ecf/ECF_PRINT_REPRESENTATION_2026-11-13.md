# Representación impresa e-CF — 2026-11-13

## Alcance y estado

HECHO: implementación local de la proyección fiscal y QR al pie de factura A4 y tickets 58/80 mm, conectada a las rutas de impresión/reimpresión del POS y su historial. No hubo emisión externa, modificación de base compartida, migración ni despliegue en este ciclo. Los comprobantes externos E31/E34 de FULLTECH aceptados anteriormente conservan su evidencia independiente.

## Requisitos consultados

Fuente primaria consultada: [Informe Técnico e-CF de DGII, sección 18](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Informe%20y%20Descripci%C3%B3n%20T%C3%A9cnica/Informe%20T%C3%A9cnico%20e-CF%20v1.0.pdf), publicado en la [documentación oficial](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Paginas/documentacionSobreE-CF.aspx), y [modelos ilustrativos](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Informe%20y%20Descripci%C3%B3n%20T%C3%A9cnica/Representaci%C3%B3n%20Impresa%20(Modelos%20ilustrativos).pdf).

Se aplicaron: identificación de emisor/receptor y tipo de comprobante en encabezado; e-NCF y vencimiento cuando corresponde; cantidades, unidades en palabras, indicador E para exentos e impuestos; QR inferior izquierdo mínimo 22×22 mm, zona libre de 3 mm, inicio a 20 mm del borde izquierdo; código de seguridad debajo y fecha de firma. El código usa la URL oficial recibida, con composición distinta para consumo menor a RD$250.000. En A4 se repiten encabezado/verificación y se muestran subtotales de página cuando corresponde. Esto es una verificación técnica de las condiciones implementadas, no una certificación legal o aprobación de DGII de estas plantillas.

## Flujo y seguridad

1. El despacho valida la respuesta correlacionada y guarda solo qrUrl/securityCode/signedAt en printStamp del documento. Verifica HTTPS, host y ruta DGII exactos del ambiente, emisor, e-NCF, monto, fecha, comprador y código. Campos adicionales arbitrarios, credenciales en URL, duplicados, rechazo y datos incompletos se bloquean.
2. La consulta de impresión exige sesión y tenant. El cajero accede a su venta; los roles administrativos mantienen la política existente de ventas. Verifica propiedad antes de consultar el documento. Dos identidades fiscales en una venta se devuelven como revisión requerida.
3. El cliente consulta de nuevo al imprimir; no guarda un QR de otra empresa en estado global. No oculta fallos de conexión convirtiendo una consulta fallida en factura fiscal. Los identificadores locales offline no consultan la API fiscal.
4. Se conservan los snapshots del emisor/receptor; el total debe coincidir. La fecha de emisión y el subtotal fiscal proceden del documento. TEST se imprime sin validez fiscal; sin firma válida no se inventa QR. No cambia el estado fiscal de aceptación ni se reenvía un POST.
5. PDF térmico y rutas de respaldo usan una misma representación fiscal. Windows RAW/móvil usan QR rasterizado a 203 dpi con margen explícito y tamaño 176 puntos, más 24 puntos blancos por lado; el hardware real debe confirmar escala y escaneo. A4 obtiene los subtotales por página mediante el contexto público de paginación de Table del paquete pdf 3.11.3 instalado, sin estimarlos por longitud de texto.

## Evidencia automática y visual

Las muestras son técnicas, de datos sintéticos y ambiente TEST. El QR utilizado corresponde al e-NCF TEST previamente aceptado, para verificar reproducción/decodificación; no constituyen una nueva venta ni una representación comercial entregable. No se hicieron nuevos envíos a DOSA para generar muestras.

- [Factura A4](../design-research/2026-11-13/ecf-printing/factura-a4.pdf)
- [Ticket 80 mm](../design-research/2026-11-13/ecf-printing/ticket-80.pdf)
- [Ticket 58 mm](../design-research/2026-11-13/ecf-printing/ticket-58.pdf)
- [Factura de varias páginas](../design-research/2026-11-13/ecf-printing/factura-varias-paginas.pdf)

Renderización local con PyMuPDF, inspección de PNG y decodificación con OpenCV. Las páginas firmadas decodifican la URL exacta del QR; el documento pendiente no contiene QR. La prueba de 40 partidas verifica datos de identidad en cada página y compara subtotales contra la cantidad real de renglones extraídos del PDF. Se inspeccionaron primera/última página, muestras A4 y térmicas. La validación de navegador web no sustituye estas comprobaciones; no se usó Playwright en este ciclo.

## Validaciones y fallos corregidos

- npm run api:build: PASS en copia aislada de las fuentes, Prisma 5.22 y TypeScript. El primer build encontró un tipo decimal no convertido a string y se corrigió. Un intento posterior encontró DLL Prisma retenida por Jest (EPERM); el reintento limpio pasó.
- npm --workspace apps/api test: 272 suites / 3248 pruebas PASS; 13 suites / 101 omitidas. Log ecf-print-all-api-clean.log. El primer comando llevaba query schema en DATABASE_URL y las guardas locales lo rechazaron; se corrigió el comando, sin debilitar guardas.
- npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/ecf-documents-http.e2e-spec.ts: 3 suites / 29 PASS. Incluye endpoint de impresión pendiente y rechazo entre tenants. Log ecf-print-http-final.log.
- Repetición de la suite dosa-emission-dispatch-http.e2e-spec.ts con respuesta QR completa: 13 PASS. Comprueba persistencia de printStamp y recuperación de SIGNED por HTTP sin exposición de la clave. Log ecf-print-signed-http.log.
- La guarda estricta de QR se verifica con pruebas focalizadas de URL, ambiente, monto, identidad, campos secretos, rechazo y RFCE. Resultado final en el cierre de este documento.
- Flutter analyze y regresión final: resultados en el cierre.
- Pruebas focalizadas del renderer: 6 PASS, incluidos importes/paginación. Primera ejecución detectó datos de locale sin inicializar; se corrigió el fixture. La factura larga detectó la tabla no divisible y se corrigió. El extractor PDF separa palabras por saltos de línea: se normaliza whitespace en las aserciones, manteniendo la comprobación de importes.
- Las pruebas de ESC/POS inspeccionan el raster y su posición antes del corte; no acreditan salida física. El raster también se decodificó como PNG.

## Pendientes para producción y límites

- Ejecutar impresión y escaneo sobre impresoras reales de 58/80 mm. No hubo prueba física de QR ni de caja/gaveta en este ciclo.
- Clasificar documentos/rangos históricos y coordinar la migración por ambiente, antes de desplegar. Los documentos antiguos sin ambiente/printStamp no se reconstruyen ni se reemiten para conseguir un QR.
- Validar el recorrido normal del POS desplegado contra TEST antes de activar producción. Esta tarea no habilita emisión productiva.
- La primera ruta consulta documentos asociados a SALE. La impresión independiente de notas E34 manuales se completó posteriormente: ver [cierre E34](ECF_E34_PRINT_COMPLETION_2026-11-13.md). La vinculación desde el documento comercial de devolución, los XML antiguos sin evidencia suficiente, impuestos adicionales y casos de contingencia siguen fuera de la cobertura nueva declarada. No se atribuye soporte nuevo a tipos distintos de los existentes E31/E32/E34.
- El almacenamiento/entrega de PDF preserva una copia digital; la durabilidad física depende del papel y la impresora. No se garantiza por una prueba automatizada.

## Archivos de este ciclo

- apps/api/src/ecf/documents/ecf-document-query.service.ts
- apps/api/src/ecf/documents/ecf-emission.service.ts
- apps/api/src/ecf/documents/ecf-print-view.ts
- apps/api/src/ecf/ecf-documents.controller.ts
- apps/api/src/ecf/ecf-documents-http.e2e-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-print-stamp.ts
- apps/api/src/ecf/provider/dosa/dosa-print-stamp.spec.ts
- apps/fulltech_app/lib/features/ecf/ecf_print_document.dart
- apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart
- apps/fulltech_app/lib/core/printing/ecf_print_footer.dart
- apps/fulltech_app/lib/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart
- apps/fulltech_app/lib/core/printing/esc_pos/thermal_printer_profile.dart
- apps/fulltech_app/lib/core/printing/esc_pos/thermal_receipt_view_model.dart
- apps/fulltech_app/lib/core/printing/html/html_thermal_receipt_renderer.dart
- apps/fulltech_app/lib/core/printing/html/html_thermal_receipt_pdf_renderer.dart
- apps/fulltech_app/lib/core/printing/models/ticket_builder.dart
- apps/fulltech_app/lib/core/printing/models/ticket_data.dart
- apps/fulltech_app/lib/core/printing/models/ticket_renderer.dart
- apps/fulltech_app/lib/core/printing/unified_ticket_printer.dart
- apps/fulltech_app/lib/modules/ventas/utils/sales_pdf_service.dart
- apps/fulltech_app/lib/modules/ventas/tpv_sales_history_screen.dart
- apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
- apps/fulltech_app/test/core/printing/ecf_print_representation_test.dart
- apps/fulltech_app/test/features/ecf/ecf_repository_test.dart
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/ecf/ECF_PRINT_REPRESENTATION_2026-11-13.md
- docs/design-research/2026-11-13/ecf-printing/ (muestras y verificación)

## Cierre de validación

- Flutter analyze final: PASS, sin incidencias (ecf-print-static-closed.log).
- flutter test test/core/printing test/modules/ventas/sales_pdf_labels_test.dart test/features/ecf/ecf_repository_test.dart test/modules/documentos/pdf_fiscal_templates_test.dart --reporter expanded: 242 PASS (ecf-print-final-tests-clean.log). Después del ajuste final de altura del pie 58 mm, la suite específica ecf_print_representation_test.dart repitió 6 PASS (ecf-print-footer-final.log), comprobando que el código de seguridad y la fecha siguen dentro de la página.
- Guarda QR final: 12 PASS (ecf-print-final-stamp-tests.log), incluida ruta RFCE diferenciada. La ejecución completa de 3248 precedió a este caso adicional; no se suman artificialmente los contadores de ejecuciones distintas.
- Build API limpio: PASS, código 0 (ecf-print-build-clean.log).
- Decodificación final: 7 páginas firmadas de las muestras, todas con QR legible y código de seguridad presente. La muestra pendiente carece de QR. Ver verification.json junto a los PDF.
- La inspección detectó que el nuevo bloque 58 mm desplazaba el pie fuera de página: se aumentó su reserva de altura y se añadieron aserciones de contenido final. Se volvió a renderizar y decodificar; resultado PASS. No se entrega la muestra intermedia defectuosa.
- Los avisos preexistentes de fuentes Helvetica sin soporte Unicode y cierre tardío de Jest se conservan en los logs; las muestras españolas inspeccionadas son legibles.

Se preservan las ediciones previas de la misma rama y los archivos ajenos. No hubo commit/push. La base desechable local se detiene al terminar las comprobaciones, sin borrarla.

GO de las verificaciones locales descritas; NO-GO para declarar terminado y activar todo el módulo productivo mientras falten los pendientes indicados arriba.

Verificación final tras el mensaje de bloqueo por importe inconsistente: flutter analyze PASS sin incidencias (ecf-print-final-analysis-closed.log) y git -c core.safecrlf=false diff --check PASS.
