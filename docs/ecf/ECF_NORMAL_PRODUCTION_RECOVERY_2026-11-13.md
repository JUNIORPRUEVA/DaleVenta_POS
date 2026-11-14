# Venta Normal, recuperación DOSA y activación por empresa — 13/11/2026

## Resultado y alcance

HECHO: continuación implementada y validada localmente en finalesdaleventas,
rama agent/ecf-offline-history-20261113. La petición principal queda cubierta:
con «Vender sin comprobante» habilitado, cada ticket nuevo propone Normal;
una venta Normal es una venta interna sin e-NCF y sin envío DOSA/DGII.
Se conserva el trabajo anterior, el asistente DOSA y los transportes de impresión.
No se hizo commit, push, despliegue, cambio de credenciales, migración compartida
ni emisión externa. Esta continuación no añade esquema, migración o dependencia.

## Criterios y plan aplicado

Auditar el recorrido POS → repositorio → venta API → preparación → despacho →
impresión; separar el intento Normal en el dato existente; conservarlo en drafts y
offline; cerrar recuperación persistida con idempotencia y aislamiento; tratar
RFCE/202 sin inventar aceptación; completar la activación productiva protegida;
validar datos, HTTP, interfaz, regresión y diff. Los cambios previos ajenos a esta
continuación no se atribuyen como nuevos.

## Comportamiento comprobado

- Normal persiste como fiscalVoucherType=NORMAL; NCF y vencimiento son nulos.
  Si el módulo está habilitado y la empresa no permite Normal, el servidor lo
  rechaza con ECF_NORMAL_SALES_DISABLED. E31/E32 conservan sus controles.
- Normal no prepara E31/E32, no crea documento electrónico, no consume rango y
  no llama al proveedor. Su ticket/PDF no consulta ni incorpora un QR fiscal.
  Los impuestos aplicables siguen calculándose; ITBIS no convierte una venta en e-CF.
- La selección explícita se guarda por ticket; otro ticket vuelve a Normal.
  El marcador viaja por la cola offline ordinaria, con sus permisos previos.
  Los datos históricos NULL y los clientes anteriores conservan compatibilidad;
  no se reescribe ni se deduce el tipo de sus ventas.
- Antes del transporte se conserva una identidad de hashes del cuerpo, ruta,
  destino, credencial, documento y ambiente. Tras una interrupción/reinicio puede
  verificarse el mismo documento al vencer su lease: una llamada idéntica, un
  intento QUERY_PROVIDER auditado, sin otro SEND_TO_PROVIDER ni número.
  Los locks y la comprobación de propietario bloquean carreras y workers antiguos.
- El historial ofrece «Verificar con DOSA» para estados desconocidos, en envío o
  pendientes DGII. Una respuesta incierta obliga a actualizar antes de otra acción.
  La verificación no repite cobro, devolución, inventario ni contabilidad.
- El RFCE E32 válido sin TrackId usa una referencia local identificada como RFCE,
  ligada a ambiente/RNC/e-NCF. Se conserva TrackId nulo; no se fabrica uno.
  La aceptación sigue requiriendo recibo correlacionado, importe, QR y evidencias.
- HTTP202 continúa pendiente DGII. Solo un timbre completo validado y la leyenda
  del proveedor habilitan impresión CONTINGENCY en ticket/PDF. No cuenta como
  aceptado. Una verificación posterior conserva QR, seguridad y firma originales.
- La activación productiva es explícita por empresa: permiso manageEcfConfig,
  certificación PRODUCTION_READY, credencial productiva activa propia y las dos
  compuertas de servidor. Resultados TEST pendientes/de revisión bloquean el paso.
  La acción verifica además el UUID de la empresa confirmada, de modo que un cambio
  de sesión durante el preflight no active otra empresa. Es idempotente, auditada
  y no emite. Se registra después la numeración
  productiva propia; no se copian rangos TEST. Una edición atrasada no devuelve
  una empresa activada a SANDBOX. El formulario descarta rangos TEST no guardados
  al cambiar de ambiente y recarga la fuente del servidor.

## Documentación consultada

El contrato RFCE, la repetición del mismo POST y la contingencia se contrastaron
con la documentación primaria de DOSA:
[repositorio de documentación](https://github.com/alapaix13/DosaInvoicecloud-Documentation/blob/main/README.md).
La URL developers de DOSA no pudo leerse con la herramienta web en esta sesión.
La implementación no necesita pedir otro endpoint de consulta a Alejandro.

## Validación ejecutada

API ejecutada en una copia aislada en TEMP porque el checkout conserva procesos
previos con el motor Prisma abierto. Se compararon 32 archivos API byte a byte
con el checkout, sin diferencias. PostgreSQL es el contenedor propio desechable
fullpos_ecf_finish_20261112, base verificada fullpos_ecf_ephemeral_test, host local.
Proveedor HTTP sintético en localhost; ninguna petición fiscal externa.
Los valores de entorno se prepararon solo en memoria para los procesos de prueba.
Al terminar se verificó su identidad y se detuvo únicamente ese contenedor propio,
reteniendo los datos. No se detuvieron procesos del usuario.

Desde la raíz de esa copia API:

```text
npm run api:build
PASS — prisma generate 5.22.0 + TypeScript; exit 0.

npm --workspace apps/api run test:unit -- --runTestsByPath src/ecf/ecf.service.spec.ts src/ecf/provider/dosa/dosa-provider-response.spec.ts
PASS — 39 tests después del último guard de contexto.

npm --workspace apps/api test
PASS — 275 suites, 3,293 tests; 13 suites / 101 tests optativos omitidos.
Exit 0. Aviso de handles Jest al finalizar, sin fallo de casos.

npm --workspace apps/api run test:integration -- --runTestsByPath src/ecf/provider/dosa/dosa-same-request-recovery-postgres.integration-spec.ts src/sales/sales-return-ecf-credit-postgres.integration-spec.ts
PASS — 2 suites, 22 tests con PostgreSQL real local.

npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts --forceExit
PASS — 26 tests HTTP locales, incluidas denegación de Normal y revisión TEST pendiente.
```

Desde apps/api de esa copia:

```text
npx prisma validate
PASS — schema válido; exit 0.
```

Desde apps/fulltech_app del checkout, TZ=AST4:

```text
flutter analyze
PASS — no issues, análisis final después del último cambio de código/test; exit 0.

flutter test test/features/ecf/ecf_production_activation_action_test.dart test/modules/cotizaciones/billing_ecf_selector_visible_test.dart test/modules/ventas/ecf_pos_fiscal_test.dart test/modules/ventas/sale_attempt_durability_test.dart test/features/ecf/ecf_repository_test.dart test/features/ecf/ecf_sale_history_panel_test.dart test/features/ecf/ecf_sequence_range_section_test.dart test/features/ecf/ecf_dosa_activation_status_test.dart test/core/printing/ecf_print_representation_test.dart
PASS — 115 tests enfocados.

flutter test test/features/ecf test/core/printing test/modules/ventas test/features/ventas test/modules/cotizaciones test/features/account/ecf_company_toggle_drawer_test.dart
PASS — 1,041 tests.

flutter test test/features/ecf/ecf_sale_history_panel_test.dart test/modules/cotizaciones/billing_ecf_selector_visible_test.dart
PASS — 11 tests finales, incluida verificación incierta y bloqueo de repetición.

flutter test test/modules/cotizaciones/billing_ecf_selector_visible_test.dart
PASS — 4 tests; captura con la pantalla POS real y Normal después de F5.

flutter test test/features/ecf/ecf_production_activation_action_test.dart test/features/ecf/ecf_sequence_range_section_test.dart test/features/ecf/ecf_repository_test.dart
PASS — 52 tests finales tras vincular el UUID de la empresa y actualizar las proyecciones fiscales del ambiente.
```

La regresión completa se ejecutó antes del último guard de UUID confirmado.
Después se revalidaron build, análisis, 39 tests API y 52 Flutter dirigidos;
los 26 casos HTTP se repitieron con el contrato final.

Control de cambios:

```text
git -c core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol diff --check -- <archivos de esta continuación>
PASS — sin errores de whitespace.
```

Se detectaron y corrigieron fallos de fixtures durante el desarrollo: selector POS
inicialmente montado en modo cotización, pumpAndSettle sobre animaciones periódicas,
clave única del intento QUERY_PROVIDER y expectativa antigua de RFCE sin referencia.
La primera regresión API falló por esa expectativa; una aserción adicional también
confundió trackId ausente con trackId nulo. Se corrigieron los tests conforme al
contrato, conservando los controles de correlación. La regresión completa posterior
pasó. No se debilitó un control fiscal para lograrlo.

Evidencia visual inspeccionada con view_image: Normal en POS a1280 y confirmación
productiva a320/1280; textos legibles, acciones visibles, sin overflow observado.
Son capturas widget con datos sintéticos; no se afirma una sesión browser/dispositivo.
Ticket/PDF se ejercitaron con los renderers reales y extracción de texto. No se hizo
otra prueba física de impresora ni se modificó su transporte.

## Riesgos y pendientes reales

- Producción todavía NO-GO para despliegue/operación: faltan el rollout revisado
  de las migraciones fiscales previas 0400/0500/0600 y clasificación histórica,
  API/cliente coordinados y configuración productiva verificada. Esta tarea no
  autoriza ni ejecuta esas operaciones compartidas. Las fuentes ya tienen la
  transición protegida y la preparación comercial antes bloqueadas.
- Documentos antiguos sin la identidad original persistida no se reenvían a ciegas.
  Requieren revisión. Un resultado ya llevado a revisión humana tampoco se
  reinterpreta automáticamente como aceptado por habilitar las compuertas.
- Devoluciones fuera de la ventana automática mantienen revisión fiscal explícita;
  no se deduce un tratamiento de ITBIS sin evidencia.
- El harness HTTP conserva handles abiertos y se ejecutó con --forceExit; es una
  limitación de cierre del runner, no prueba de funcionamiento productivo.
  La regresión no-e2e también emitió el aviso de handles, pero terminó con exit 0.
- No se generó instalador/release ni se validó contra FULLTECH/DOSA reales en esta
  continuación. Los casos «production» del HTTP test usan empresas sintéticas y
  destino localhost, con permisos de producción solo en el entorno del test.

## Herramientas

Terminal PowerShell, git, Node filesystem, apply_patch, Docker/PostgreSQL local,
Flutter/Dart, npm/Jest/Prisma, web y view_image. Sin Figma, Playwright, Context7,
subagentes ni integración GitHub. Ningún secreto se incluye en este informe.

## Inventario exacto de esta continuación

- apps/api/src/ecf/documents/ecf-document-idempotency.service.ts
- apps/api/src/ecf/documents/ecf-document-query.service.ts
- apps/api/src/ecf/documents/ecf-emission.service.ts
- apps/api/src/ecf/documents/ecf-preparation.service.ts
- apps/api/src/ecf/documents/ecf-print-view.ts
- apps/api/src/ecf/dto/ecf.dto.ts
- apps/api/src/ecf/ecf-documents.controller.ts
- apps/api/src/ecf/ecf.controller.ts
- apps/api/src/ecf/ecf.service.spec.ts
- apps/api/src/ecf/ecf.service.ts
- apps/api/src/ecf/pos/ecf-sale-fiscal.adapter.ts
- apps/api/src/ecf/provider/dosa/dosa-confirmed-outcome.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts
- apps/api/src/ecf/provider/dosa/dosa-emission.client.ts
- apps/api/src/ecf/provider/dosa/dosa-persisted-recovery.ts
- apps/api/src/ecf/provider/dosa/dosa-print-stamp.spec.ts
- apps/api/src/ecf/provider/dosa/dosa-print-stamp.ts
- apps/api/src/ecf/provider/dosa/dosa-provider-response.spec.ts
- apps/api/src/ecf/provider/dosa/dosa-provider-response.ts
- apps/api/src/ecf/provider/dosa/dosa-response.mapper.ts
- apps/api/src/ecf/provider/dosa/dosa-same-request-recovery-postgres.integration-spec.ts
- apps/api/src/sales/sales.service.ts
- apps/fulltech_app/lib/core/printing/models/ticket_data.dart
- apps/fulltech_app/lib/core/printing/unified_ticket_printer.dart
- apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart
- apps/fulltech_app/lib/features/ecf/ecf_models.dart
- apps/fulltech_app/lib/features/ecf/ecf_print_document.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_config_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_production_activation_action.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_sale_history_panel.dart
- apps/fulltech_app/lib/features/ecf/ui/flow/ecf_dosa_activation_status.dart
- apps/fulltech_app/lib/features/ecf/ui/flow/ecf_sequence_range_section.dart
- apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
- apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart
- apps/fulltech_app/lib/modules/ventas/ecf_pos_fiscal.dart
- apps/fulltech_app/lib/modules/ventas/sales_models.dart
- apps/fulltech_app/lib/modules/ventas/tpv_sales_history_screen.dart
- apps/fulltech_app/lib/modules/ventas/utils/sales_pdf_service.dart
- apps/fulltech_app/test/core/printing/ecf_print_representation_test.dart
- apps/fulltech_app/test/features/ecf/ecf_production_activation_action_test.dart
- apps/fulltech_app/test/features/ecf/ecf_sale_history_panel_test.dart
- apps/fulltech_app/test/modules/cotizaciones/billing_ecf_selector_visible_test.dart
- apps/fulltech_app/test/modules/ventas/sale_attempt_durability_test.dart
- docs/ARCHITECTURE.md
- docs/ENVIRONMENTS.md
- docs/EXECUTION_STATE.md
- docs/PRODUCT_SPEC.md
- docs/design-research/2026-11-13/ecf-normal-production/normal-new-ticket-1280.png
- docs/design-research/2026-11-13/ecf-normal-production/production-confirm-1280.png
- docs/design-research/2026-11-13/ecf-normal-production/production-confirm-320.png
- docs/ecf/ECF_NORMAL_PRODUCTION_RECOVERY_2026-11-13.md

## Estado

Implementación y validación local: PASS.
Producción/despliegue: NO-GO hasta completar los pendientes operativos indicados.
