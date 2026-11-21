# Revisión transversal móvil — 21/11/2026

## Alcance y entorno
Worktree exclusivo: C:/src/fullpos-diseno-movil-20261121.
Rama: agent/diseno-movil-android-ios-20261121. Base: 2388fe94.
Se conserva el trabajo móvil anterior, sin commit, push, merge o despliegue.
Ningún cambio en backend, Prisma, permisos fiscales, licencias o datos productivos.
Las consultas visuales Android usaron la sesión existente; no se confirmaron ventas,
ajustes de stock, devoluciones, pagos ni movimientos de caja.

## Criterios implementados
- Iconos originales suministrados: atrás, lupa, filtro y actualizar. Los cuatro
  assets son idénticos byte a byte a los originales del propietario.
- CustomAppBar prioriza Atrás sobre drawer en teléfonos nativos. Facturación
  conserva su encabezado propio con marca y menú. No se cambia el destino del
  botón Atrás ni se eliminan callbacks de acciones existentes.
- MobileActionIcon conserva el Icon original fuera de teléfonos Android/iOS.
- MobilePageAppBar adapta barras directas; devuelve exactamente el AppBar original
  en Windows/web/tabletas. Mantiene leading, acciones, título, bottom y callbacks.
- MobilePresentationTheme reduce espacios de listas/tarjetas compartidas
  exclusivamente en teléfonos nativos. Los widgets con medidas explícitas
  mantienen sus propias restricciones; esto no equivale a rediseñar cada fila.
- Historial de ventas: lista nativa compacta, sin repetir «Factura» ni cajero;
  el cajero sigue disponible en el detalle, conservando estado fiscal y total.
- Productos: stock y costo completos junto al nombre, sin columna estrecha que
  cortaba importes. Categoría queda en detalle. Se mantienen selección, menú,
  impuestos, unidades y acciones; no cambia cálculo ni datos.
- Compras: estado mostrado una vez y en español en lista nativa; conteos de
  líneas y unidades explícitos. Windows conserva sus etiquetas anteriores.
- Reportes: cuatro indicadores principales visibles; seis apartados desplegables,
  reutilizando consultas, cifras y gráficos existentes. Margen y ventas abren
  correctamente. PageStorage separado entre expansión y scroll de los gráficos.
- Fiscal: cuatro pantallas que dependían del encabezado desktop reciben una barra
  nativa propia. El asistente conserva _navigateBack para sus pasos internos.
  La portada móvil evita repetir el título y reduce el margen horizontal.

## Cobertura por módulo
«Fuente» significa inspección del código y adaptación compartida, no una visita
manual a cada formulario. «Widget» utiliza repositorios simulados. No confundir
estas verificaciones con operaciones reales o certificaciones externas.

| Módulo / páginas | Cobertura de fuente y automatizada | Evidencia Android real de esta revisión |
|---|---|---|
| Facturación / acciones / tickets | Se conserva el trabajo previo; regresión completa de cotizaciones | Drawer y retorno desde módulos; no se cobra |
| Ventas / cotizaciones / créditos | Barras, iconos, pruebas de filtros, listas y detalle; goldens 390 y escritorio | Ventas y filtro inspeccionados; cotizaciones y créditos con referencias ficticias, pendiente visita real final |
| Clientes / detalle / formulario | Barras comunes, iconos; suites existentes en batería completa | Lista de clientes inspeccionada; sin editar |
| Productos / stock / categorías / recuento | Barras y acciones comunes; resumen probado a 320/390/430 con texto 1.3 y variantes Android/iOS/Windows | Productos inspeccionados; pendiente repetir captura tras compactar la fila |
| Listas de precios / formulario / selector | Pruebas funcionales y goldens 390, 1024, 1920, 2560 | No visitada manualmente en esta revisión |
| Compras / órdenes / suplidores / facturas / por comprar | Pruebas funcionales y goldens móviles/escritorio | Lista de compra inspeccionada sin ejecutar acciones |
| Reportes / gráficos / filtros | Pruebas de cálculos, expansión, KPIs, tamaños, goldens móvil/escritorio | Pantalla y apartados inspeccionados |
| Fiscal / portada / documentos / configuración / datos / asistente | Solo presentación; suites e-CF existentes | Portada inspeccionada; detectó falta de encabezado móvil y se corrigió |
| Configuración / empresa / impresora / app / planes | Barra común, lista nativa anterior, navegación Android/iOS y Windows probada | Menú principal, pie y lista de Configuración inspeccionados |
| Usuarios / perfil / permisos / contrato | Barra y acciones compartidas; suites existentes | No se visita un usuario real ni se cambia un permiso |
| Caja / movimientos / gastos / turnos | Barra y acciones; sin cambios de negocio | No abrir/cerrar cajas ni registrar operaciones |
| Contabilidad / cierres / depósitos / pagos pendientes | Barras directas y acciones comunes; suites existentes | No se ejecutan operaciones financieras |
| Nómina / mis pagos | Barras directas y acciones comunes; suites existentes | No se ejecutan operaciones de nómina |
| IA / recuperación offline / vistas auxiliares | Iconos compartidos y respeto al comportamiento previo | Sin operaciones de recuperación o soporte |

## Validaciones
- flutter pub get --offline: PASS; registro de cuatro assets.
- flutter analyze --no-pub: PASS sin incidencias, también después del resumen de productos.
- 179 pruebas específicas de presentación, productos, reportes, compras, listas de
  precios e historiales: PASS. Incluye tamaños de escritorio y variantes nativas.
- Referencias visuales actualizadas solo a 390px; no se actualizan goldens desktop.
- Android debug real: hot reload confirmado. No se generó artefacto de publicación.
- Primera batería completa: 2540 PASS, 10 omitidas, 22 fallos. Los fallos por cambios
  intencionales de encabezado/golden y expansión de reportes se corrigieron y sus
  suites pasaron. Se detectó y corrigió además un efecto del fondo en ventanas
  estrechas no nativas: el relleno del degradado queda limitado a teléfono nativo.
- Tres fallos del preview BrandedMenuButton permanecen: test exige IA 64×64 y el
  componente sin modificar mide 60×60. Test, preview y componente son idénticos a
  HEAD (git diff vacío). No se cambia el botón desktop para satisfacer esa prueba.
- Segunda batería completa: 2565 PASS, 10 omitidas y 6 fallos; tres del preview
  de IA y tres de Productos. Después se corrigieron la referencia visual de
  catálogo y la presentación de stock/unidades/servicios. La regresión final
  ampliada de 852 pruebas pasó, incluidas las tres de Productos.
- Último ajuste de filtros y etiqueta de compras: 40 pruebas PASS; no se suman
  con las 852 porque comparten casos. Los filtros conservan selección por color
  y muestran los textos completos en Android.
- Fondo decorativo y marcas de rol ocultos solo en teléfono nativo; variantes
  Android/iOS/Windows verificadas en mobile_page_presentation_test.dart.
- iOS: variantes de widget; no build iOS ni revisión visual en iPhone real.
- git diff --check: PASS. Los tres generados Windows de pub get se restauraron.
- Análisis final después del ajuste de filtros: flutter analyze --no-pub, PASS
  sin incidencias (21.4 s). Hot reload Android confirmado después de los cambios.

## Evidencias
Capturas privadas en C:/Users/pc/.codex/backups/fullpos-release-preparation-20261120:
mobile-module-current.png, mobile-clients-review.png, mobile-products-audit.png,
mobile-purchase-orders-final.png, mobile-fiscal-final.png,
mobile-goldens-review-sheet.png.
Las capturas con datos de empresas quedan fuera de Git.
Logs: mobile-full-suite.log, mobile-full-suite-final.log,
mobile-modules-regression.log, mobile-modules-analyze-final.log.
Los goldens versionados usan datos ficticios.

## Archivos de código de esta revisión
- apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_resource_card.dart
- apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart
- apps/fulltech_app/lib/core/guardian/guardian_monitoring_panel.dart
- apps/fulltech_app/lib/core/loading/app_loading_screen.dart
- apps/fulltech_app/lib/core/routing/app_navigator.dart
- apps/fulltech_app/lib/core/widgets/custom_app_bar.dart
- apps/fulltech_app/lib/core/widgets/history_filter_panel.dart
- apps/fulltech_app/lib/core/widgets/history_presentation.dart
- apps/fulltech_app/lib/core/widgets/mobile_action_icon.dart
- apps/fulltech_app/lib/core/widgets/mobile_page_app_bar.dart
- apps/fulltech_app/lib/core/widgets/mobile_presentation_theme.dart
- apps/fulltech_app/lib/core/widgets/professional_recovery_card.dart
- apps/fulltech_app/lib/core/widgets/provided_action_icon.dart
- apps/fulltech_app/lib/core/widgets/responsive_shell.dart
- apps/fulltech_app/lib/features/account/account_menu_screens.dart
- apps/fulltech_app/lib/features/assistant/presentation/assistant_panel.dart
- apps/fulltech_app/lib/features/assistant/presentation/views/assistant_help_view.dart
- apps/fulltech_app/lib/features/assistant/presentation/widgets/assistant_widgets.dart
- apps/fulltech_app/lib/features/contabilidad/cierres_diarios_screen.dart
- apps/fulltech_app/lib/features/contabilidad/depositos_bancarios_screen.dart
- apps/fulltech_app/lib/features/contabilidad/pagos_pendientes_screen.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_activation_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_certification_recovery_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_config_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_dgii_application_wizard.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_dgii_habilitation_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_documents_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_fiscal_data_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_platform_review_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_ready_home.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_sale_history_panel.dart
- apps/fulltech_app/lib/features/ecf/ui/flow/ecf_dosa_activation_status.dart
- apps/fulltech_app/lib/features/offline/sale_attempt_recovery_screen.dart
- apps/fulltech_app/lib/features/plans/presentation/plans_shell.dart
- apps/fulltech_app/lib/features/price_lists/ui/price_lists_screen.dart
- apps/fulltech_app/lib/features/products/ui/inventory_module_pages.dart
- apps/fulltech_app/lib/features/settings/ui/printer_settings_page.dart
- apps/fulltech_app/lib/features/splash/splash_screen.dart
- apps/fulltech_app/lib/features/user/users_screen.dart
- apps/fulltech_app/lib/features/user/utils/work_contract_preview_screen.dart
- apps/fulltech_app/lib/features/warehouses/ui/inventory_kardex_screen.dart
- apps/fulltech_app/lib/features/warehouses/ui/warehouse_settings_screen.dart
- apps/fulltech_app/lib/main.dart
- apps/fulltech_app/lib/modules/cash/cash_box_screen.dart
- apps/fulltech_app/lib/modules/cash/cash_management_screens.dart
- apps/fulltech_app/lib/modules/cash/cash_turn_menu_button.dart
- apps/fulltech_app/lib/modules/clientes/cliente_detail_screen.dart
- apps/fulltech_app/lib/modules/clientes/clientes_screen.dart
- apps/fulltech_app/lib/modules/compras/compras_screen.dart
- apps/fulltech_app/lib/modules/cotizaciones/ai/presentation/widgets/ai_chat_sheet.dart
- apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_historial_screen.dart
- apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
- apps/fulltech_app/lib/modules/nomina/mis_pagos_screen.dart
- apps/fulltech_app/lib/modules/nomina/nomina_screen.dart
- apps/fulltech_app/lib/modules/ventas/sales_credit_screen.dart
- apps/fulltech_app/lib/modules/ventas/tpv_sales_history_screen.dart
- apps/fulltech_app/lib/modules/ventas/widgets/recent_sales_panel.dart

Además:
- apps/fulltech_app/pubspec.yaml y assets/image/mobile_navigation/{back,search,filter,refresh}.png.
- apps/fulltech_app/lib/core/widgets/fulltech_global_background.dart.
- apps/fulltech_app/lib/modules/clientes/clientes_map_screen.dart.
- apps/fulltech_app/test/features/products/catalog_design_test.dart.
- test/core/widgets/mobile_page_presentation_test.dart.
- test/features/products/mobile_product_summary_test.dart.
- test/features/account/account_settings_navigation_test.dart.
- test/features/reports/reports_design_test.dart.
- test/features/price_lists/price_lists_screen_test.dart.
- test/modules/compras/purchases_design_test.dart.
- test/modules/ventas/{related_history_design_test,sales_history_design_test,reports_models_test}.dart.
- Goldens 390px de reportes, listas de precios, compras e historiales.
- docs/DESIGN_SYSTEM.md y docs/DISENO_MOVIL_WORKSPACE_20261121.md.

## Pendientes / estado
NO-GO para publicación. No se afirma que cada formulario y cada estado se haya
recorrido visualmente. Falta iPhone real y las visitas manuales indicadas, además
de resolver o aprobar explícitamente el desajuste previo de pruebas del menú.
CI ejecuta Flutter en Ubuntu. Existen referencias separadas en goldens/linux y
esta revisión actualizó las referencias generadas en Windows; antes de publicar
hay que regenerar y revisar los goldens móviles en Linux y ejecutar ese gate.
No se copian capturas Windows sobre referencias Linux, ni se omite el comparador.
No se hicieron push, merge, deploy, migraciones ni escrituras productivas.

## Cierre visual adicional
Android real: Historial de ventas, abrir/cerrar filtro sin aplicar cambios,
Configuración y portada fiscal con nuevo encabezado comprobados. Capturas:
mobile-sales-history-final.png, mobile-sales-filter-labels-final.png,
mobile-settings-current.png y mobile-fiscal-header-final.png. Hot reload activo.
Productos y compras también tienen referencias ficticias finales inspeccionadas:
catalog_390.png y purchases_orders_390.png. La cobertura anterior distingue las
visitas pendientes; este cierre no equivale a recorrer todos los formularios.

## Actualización de consolidación — 2026-11-21

Las referencias Linux pendientes se generaron y comprobaron en el worktree
de integración, incluyendo el dock de IA. Flutter completo Linux serial:
2.826 PASS y 17 omisiones explícitas. No autoriza publicación ni sustituye el
recorrido físico de iOS; ver `audits/CONSOLIDACION_AMBOS_CHATS_20261121.md`.
