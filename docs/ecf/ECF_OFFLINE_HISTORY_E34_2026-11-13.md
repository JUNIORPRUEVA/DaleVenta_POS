# Conexión, historial fiscal y devoluciones E34 — 13/11/2026

## Alcance y evidencia

HECHO: implementación local autorizada en la rama agent/ecf-offline-history-20261113 del checkout finalesdaleventas. Se conserva el trabajo fiscal anterior. No hay despliegue, migración compartida, cambio de credenciales ni emisión externa en esta tarea. El asistente DOSA y los transportes de impresora existentes se conservan.

## Comportamiento implementado

- E31/E32 exige una comprobación HTTP real antes de guardar/cobrar. El aviso breve de conexión aparece arriba a la derecha durante cuatro segundos. Se distingue ausencia de conexión, indisponibilidad del servicio y respuesta incierta.
- La comprobación de conexión desactiva caché offline y reintentos. Las lecturas que desbloquean acciones fiscales también desactivan caché offline: un estado antiguo nunca sirve como comprobación nueva.
- El tipo E31/E32 se guarda con la venta y su vencimiento E31 queda congelado. La preparación verifica el tipo y utiliza ese vencimiento. Las ventas normales no adquieren identidad electrónica por usar impuestos.
- La pérdida de respuesta no genera una factura electrónica offline. En Windows se conserva el intento durable y su identidad; una respuesta incierta bloquea repetir el mismo cobro. Las operaciones fiscales mantienen las barreras del servidor.
- El historial muestra tipo, e-NCF reservado/emitido y estado; el detalle reúne original y notas E34, aceptación condicional y ambiente TEST. Las acciones respetan permisos. Los casos con varios originales requieren revisión.
- Se bloquea la cancelación ordinaria de una venta electrónica. La devolución financiera y la preparación/emisión fiscal son resultados distintos. La falta de numeración o confirmación del original se informa como pendiente.
- Cada devolución tiene una E34 estable. Una devolución parcial y la devolución posterior del remanente acreditan sus importes exactos; no se vuelve a anular el importe total original. La recuperación fiscal no repite caja, inventario ni contabilidad.
- La preparación automática que supera el plazo de revisión fiscal se detiene con un motivo explícito. No se deduce un tratamiento de ITBIS.
- La preparación manual E34 conserva UUID y hash de solicitud por empresa, usuario y original ante una respuesta perdida. Cambiar la solicitud pendiente se bloquea.
- Un PDF electrónico exige la proyección fiscal persistida. Ticket y PDF reutilizan los datos fiscales y QR ya implementados. No se fabrica QR para pendientes o rechazados ni se altera la configuración de impresoras.

## Archivos de esta intervención

- docs/ecf/ECF_OFFLINE_HISTORY_E34_2026-11-13.md
- apps/api/src/sales/sales.service.ts
- apps/api/src/sales/sales.controller.ts
- apps/api/src/sales/dto/create-sale.dto.ts
- apps/api/src/sales/sales-return-ecf-credit-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-document-query.service.ts
- apps/api/src/ecf/ecf-documents.controller.ts
- apps/api/src/ecf/dto/ecf-documents.dto.ts
- apps/api/src/ecf/documents/ecf-refund-identity.ts
- apps/api/src/sales/sales.service.inventory-optional.spec.ts
- apps/api/src/sales/sales.service.quick-sale.spec.ts
- apps/api/src/sales/sales.service.tenant.spec.ts
- apps/api/src/ecf/pos/ecf-sale-fiscal.adapter.ts
- apps/api/src/ecf/documents/ecf-preparation.service.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
- apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart
- apps/fulltech_app/lib/modules/ventas/sales_models.dart
- apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
- apps/fulltech_app/lib/modules/ventas/tpv_sales_history_screen.dart
- apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_dosa_dispatch_action.dart
- apps/fulltech_app/lib/core/printing/unified_ticket_printer.dart
- apps/fulltech_app/lib/features/ecf/data/ecf_connection_guard.dart
- apps/fulltech_app/lib/features/ecf/data/ecf_pending_credit_request.dart
- apps/fulltech_app/lib/features/ecf/ecf_sale_fiscal.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_sale_history_panel.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_credit_note_action.dart
- apps/fulltech_app/lib/modules/ventas/utils/sales_pdf_service.dart
- apps/fulltech_app/test/features/ecf/ecf_connection_guard_test.dart
- apps/fulltech_app/test/features/ecf/ecf_pending_credit_request_test.dart
- apps/fulltech_app/test/features/ecf/ecf_sale_history_panel_test.dart
- apps/fulltech_app/test/features/ecf/ecf_repository_test.dart
- apps/fulltech_app/test/features/ecf/ecf_prepare_action_test.dart
- apps/fulltech_app/test/features/ecf/ecf_credit_note_action_test.dart
- apps/fulltech_app/test/features/ecf/ecf_dosa_dispatch_action_test.dart
- apps/fulltech_app/test/features/ventas/ventas_controller_dispose_test.dart
- apps/fulltech_app/test/core/printing/ecf_print_representation_test.dart
- apps/fulltech_app/test/modules/ventas/sale_attempt_durability_test.dart
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/EXECUTION_STATE.md

También se conservan siete capturas de widgets reales en docs/design-research/2026-11-13/ecf-history-implementation. No son capturas de producción. Los PDF y raster fiscales inspeccionados pertenecen a las muestras sintéticas de impresión previas, cuyos renderers no se rediseñaron aquí.

## Validaciones

HECHO: base de datos desechable local, sin llamadas a DOSA/DGII. La copia de validación del API coincide byte por byte con los 14 archivos API de esta intervención.

- npm --workspace apps/api test: 275 suites PASS, 3,289 pruebas PASS; 13 suites / 101 pruebas opt-in omitidas por sus propias condiciones. Salida 0.
- npm --workspace apps/api run test:integration -- --runTestsByPath src/sales/sales-return-ecf-credit-postgres.integration-spec.ts: 15 PASS. Cubre E31/E32, parciales/remanente, concurrencia, reintento, recuperación, cancelación bloqueada, aislamiento y revisión fiscal.
- npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/ecf-documents-http.e2e-spec.ts --forceExit: 25 PASS. HTTP real exclusivamente contra localhost y empresas sintéticas. Salida 0.
- La misma ejecución HTTP sin forceExit y con detectOpenHandles también completó 25/25 aserciones, pero el proceso quedó abierto sin diagnóstico útil. Se detuvieron únicamente los workers propios ya completados. No se afirma resuelto ese recurso del harness; el cierre forzado no omite aserciones.
- Primera regresión completa API: 3,277 PASS / 10 FAIL por dobles de pruebas que no incluían el nuevo lookup fiscal ni referencias de devolución; se completaron los fixtures y la regresión final anterior pasó.
- Flutter broad regression: 1,145 PASS / 3 SKIP / 1 FAIL. El fallo era la guarda de texto de la confirmación de devolución normal. Se restauró el texto original. La repetición final dirigida pasó: 99/99, incluida esa suite y las pruebas de conexión, caché, E34 e impresión.
- Capturas reales de widgets a 320/1280 px inspeccionadas: aviso breve arriba a la derecha, sin modal, desaparece automáticamente; historial completo, venta ordinaria y detalle electrónico legibles sin overflow.
- Se inspeccionaron las representaciones sintéticas ya renderizadas de factura A4, ticket 58/80 mm y nota E34 A4. Los tests de impresión generan el contenido mediante los renderers reales; no hay prueba física nueva.

- npm run api:build: PASS (Prisma 5.22 generate y tsc); npm --workspace apps/api exec prisma validate: PASS. Ejecutados después de las últimas modificaciones API.
- flutter analyze: PASS sin incidencias tras la última guarda adicional del ticket (4.2 s).
- flutter test con las once suites dirigidas de conexión, solicitud E34, historial completo, repositorio, preparación, despacho, identidad durable, devoluciones y documentos: 99 PASS, salida 0.
- flutter test test/features/ecf/ecf_repository_test.dart: 32 PASS después de la guarda adicional de identificadores locales, salida 0.
- Los errores y trazas de falta de conexión y secuencia agotada en los logs corresponden a escenarios inyectados que verifican la respuesta pendiente. No son emisiones reales ni fallos ocultos.
- git diff --check en los archivos propios, respetando CRLF: PASS. Revisión adicional de los 41 archivos fuente/documentación: sin espacios finales ni marcadores de conflicto. La comprobación inicial con core.autocrlf=false marcó CRLF como espacios; fue una configuración incorrecta de la comprobación, sin modificar fuentes.
- Contenedor propio fullpos_ecf_finish_20261112: detenido tras verificar POSTGRES_DB=fullpos_ecf_ephemeral_test; datos locales conservados.

Los resultados no representan una aceptación DGII nueva ni un despliegue.

## Límites y pendientes de producción

- Las barreras previas de transición pública a PRODUCTION y preparación comercial permanecen cerradas. Este cambio no habilita producción.
- La recuperación DOSA existente conserva la solicitud y permite hasta tres llamadas durante una ejecución; el resultado incierto tras reinicio o agotamiento sigue requiriendo revisión. HTTP 202/contingencia y RFCE E32 sin trackId no se convierten automáticamente en aceptación.
- Las migraciones fiscales anteriores, clasificación histórica y despliegue coordinado siguen requiriendo revisión antes de cualquier base compartida.
- Las devoluciones fuera del plazo automático requieren revisión fiscal. No se afirma soporte automático completo para ese caso.
- No se realizó impresión física ni se emitieron nuevos comprobantes reales. Se reutiliza la impresión que el propietario confirmó operativa; las pruebas de transporte son dobles y no certifican hardware.
- No hay Context7, Figma o Playwright ejecutados en esta intervención. La validación visual usa capturas de Flutter a 320 y 1280 px y las muestras de documentos fiscales existentes.

## Estado

Implementación local validada. NO-GO para producción por los límites anteriores; no equivale a un módulo desplegado o a una aceptación externa nueva.
