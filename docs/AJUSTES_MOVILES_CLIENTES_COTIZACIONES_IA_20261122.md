# Ajustes móviles: Clientes, Cotizaciones, opciones y chat

Fecha: 22/11/2026. Rama `agent/refinamiento-movil-20261121`, worktree
`C:/t/fp-movil-final-20261121`, base `61d5d5aa`.

## Alcance y conservación

El propietario confirmó expresamente que todos los ajustes de presentación son
solo Android/iPhone. Se reutiliza `usesNativePhoneLayout`: exige plataforma
nativa Android/iOS, lado menor inferior a 600 y ancho inferior a 900. La PWA,
Windows y la presentación de tablet conservan su comportamiento anterior.
No se modificó ese predicado ni se mezcló el worktree de acceso sin conexión.

Se conservaron los catorce pendientes iniciales del refinamiento anterior:
footer, Usuario/Permisos, Impresora, Configuración, Acciones, sus pruebas y
documentación. Este informe describe los ajustes adicionales de esta solicitud.
No hay commit, push, merge, firma, publicación móvil ni deploy.

## Recorrido y cambios

1. Cliente: se conserva la carga mediante controlador/repositorios, el alcance
   del cliente actual y los callbacks de editar/eliminar. Solo en teléfono se
   añade cabecera compartida con nombre/teléfono y opciones, fondo de marca,
   métricas y secciones compactas. Formularios, confirmación y botones usan
   contornos cuadrados; el acceso a ubicación mantiene un área táctil adecuada.
   La cabecera anterior sigue en escritorio. Los iconos decorativos de movimientos
   se omiten solo en teléfono. La lista principal de clientes ya carecía de ese
   adorno y mantiene sus datos.
2. Cotizaciones: la tarjeta sigue abriendo su detalle con el callback existente.
   En teléfono desaparece la acción duplicada Ver detalle; se conservan Ver PDF,
   Editar, Duplicar y Eliminar conforme a sus permisos anteriores. Menú cuadrado,
   nuevo icono y fila sin la ilustración de documento. El menú anterior permanece
   en Windows, incluso a 390 px.
3. Opciones: el PNG entregado por el propietario se incorpora sin alterarlo como
   `assets/image/mobile_navigation/more.png`. MobileActionIcon cubre las variantes
   Material; AppIcon cubre las dos variantes HugeIcons, y PurchaseIcon delega las
   restantes. Los llamadores de opciones de Clientes, Ventas, Usuario, Inventario,
   Compras, Cotizaciones e historiales usan esa adaptación. El PNG no reemplaza
   iconos de otras funciones. El tema de menú cuadrado está limitado al teléfono;
   se respetan los callbacks, las áreas de interacción y los colores heredados.
4. Listas de registros: se omiten adornos iniciales equivalentes en facturas de
   compra, documentos fiscales, movimientos del cliente, pagos pendientes y ventas
   recientes de Reportes. Se conservan etiquetas y estados fiscales. No se retiraron
   fotos de productos, avatares de identidad, indicadores de selección/dirección
   ni iconos funcionales de navegación y menús de acciones.
5. IA: se elimina solo en teléfonos nativos el límite del 84 % de altura. Se
   conservan SafeArea y el manejo del teclado; escritorio/web mantienen el límite
   previo y el panel lateral. No se modificó el motor, contrato o conocimiento IA.

## Archivos adicionales de esta solicitud

Prefijo de aplicación: `apps/fulltech_app/`.

```text
lib/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart
lib/core/design_system/icons/app_icon.dart
lib/core/widgets/history_presentation.dart
lib/core/widgets/mobile_action_icon.dart
lib/core/widgets/mobile_presentation_theme.dart
lib/features/contabilidad/depositos_bancarios_screen.dart
lib/features/contabilidad/pagos_pendientes_screen.dart
lib/features/ecf/ui/ecf_documents_page.dart
lib/features/products/ui/inventory_module_pages.dart
lib/features/reports/ui/reports_page.dart
lib/features/user/users_screen.dart
lib/modules/clientes/cliente_detail_screen.dart
lib/modules/clientes/cliente_form_screen.dart
lib/modules/clientes/clientes_screen.dart
lib/modules/compras/compras_screen.dart
lib/modules/compras/purchase_visual_theme.dart
lib/modules/cotizaciones/cotizaciones_historial_screen.dart
lib/modules/cotizaciones/cotizaciones_screen.dart
lib/modules/ventas/tpv_sales_history_screen.dart
assets/image/mobile_navigation/more.png
test/core/ai_assistant/ai_assistant_sheet_composer_test.dart
test/core/widgets/mobile_options_icon_test.dart
test/modules/clientes/cliente_detail_screen_widget_test.dart
test/modules/cotizaciones/quotation_mobile_menu_test.dart
test/modules/compras/purchases_design_test.dart
test/modules/ventas/sales_history_design_test.dart
```

Referencias visuales actualizadas únicamente a 390 px, en sus variantes de
rasterización Windows y Linux: `assistant_390.png`, `purchases_orders_390.png`,
`purchases_invoices_390.png`, `purchase_invoice_form_390.png`,
`sales_history_390.png`. Los archivos bajo carpetas goldens de ambos entornos
representan aquí UI de teléfono; no son cambios al diseño de Windows.
`docs/DESIGN_SYSTEM.md` y este informe completan el registro.

## Validación ejecutada

```text
flutter analyze --no-pub
PASS: sin incidencias (12,7 s), log fullpos-mobile-final-analysis-pass.log.

flutter test --no-pub test/modules/clientes
  test/core/widgets/mobile_options_icon_test.dart
  test/core/widgets/mobile_page_presentation_test.dart
  test/core/ai_assistant/ai_assistant_sheet_composer_test.dart
  --dart-define=MOBILE_DETAIL_EVIDENCE=C:/Users/pc/Documents/FullPOS-Movil-Clientes-20261122
  --reporter expanded
PASS: 62 pruebas; fullpos-mobile-client-refinement-final.log.

flutter test --no-pub
  test/modules/cotizaciones/quotation_history_no_full_catalog_test.dart
  test/modules/cotizaciones/quotation_mobile_menu_test.dart
  test/modules/compras/purchases_design_test.dart
  test/features/reports/reports_page_loading_test.dart
  test/features/reports/reports_design_test.dart
  test/modules/ventas/sales_history_design_test.dart
  test/features/user/users_mobile_presentation_test.dart
  test/features/ecf/ecf_documents_page_test.dart --reporter expanded
PASS: 90 pruebas; fullpos-mobile-adjacent-final.log.

Flutter 3.41.6 en Docker Linux, copia desechable con fuente montada solo lectura:
pruebas de diseño de Compras, Ventas, Reportes, chat, iconos, menú de cotizaciones
y detalle de cliente.
PASS: 80 pruebas; linux-final-regression.log.

flutter build apk --debug --no-pub --target-platform android-x64
  --dart-define=APP_ENV=production
  --dart-define=API_BASE_URL=https://daleventapos-backend.gcdndd.easypanel.host
  --dart-define=API_TIMEOUT_MS=15000
  --dart-define=APP_BASE_URL=https://fullposcloud.fulltechrd.com
PASS: APK debug para emulador; no es un artefacto release.

adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
PASS: Success, actualización sin desinstalar ni borrar datos.

adb -s emulator-5554 shell am start -n com.daleventa.pos/.MainActivity
PASS: app abierta; flutter attach y app.restart devolvieron code 0.

git diff --check
PASS. Sin cambios en backend ni proyectos Windows/web/Android/iOS.
```

No se suman los casos entre baterías: existe solapamiento. Las variantes iOS
son pruebas Flutter, no ejecución nativa en un iPhone.

## Evidencia visual y correcciones de prueba

En `C:/Users/pc/Documents/FullPOS-Movil-Clientes-20261122` se conservaron capturas
del widget real de detalle de cliente Android/iOS/Windows, referencias Linux y
captura nativa de la app Android actual. Se inspeccionaron las capturas del
detalle, chat, facturas de compra, lista de compras e historial de ventas.
La captura nativa contiene el estado comercial del usuario y no se agrega a Git.

Las pruebas de menú recorren la pantalla y sus callbacks reales con repositorios
ficticios: verifican opciones, ausencia del adorno y apertura del detalle desde
la tarjeta. El chat comprueba sus límites superior/inferior respetando SafeArea
y conserva los recorridos existentes con teclado. El PNG nuevo se comprueba en
Android/iOS y su ausencia se exige en Windows.

Primeros intentos detectaron defectos del fixture: espera de captura dentro del
reloj simulado, restauración incorrecta de la plataforma de pruebas y captura
antes de cargar el logo. Se corrigieron con runAsync, TargetPlatformVariant y
precacheImage. No se redujeron aserciones ni se relajó la comparación exacta de
píxeles. Las diferencias posteriores eran las modificaciones visuales móviles
autorizadas: se inspeccionaron y regeneraron solo las referencias indicadas.
Linux necesitó completar dependencias en una caché aislada; la fuente permaneció
de solo lectura. Los fallos iniciales y logs se preservan fuera del repositorio.

## Límites y estado

Los flujos funcionales se probaron con repositorios de prueba; no se generaron
ventas, cambios fiscales, pagos o escrituras de clientes en producción. La app
del emulador apunta al backend real por petición del propietario para su revisión
manual. No se introdujeron credenciales del usuario ni se realizaron operaciones
comerciales desde las herramientas. Productos e imágenes permanecen presentes.

GO para revisión local de diseño Android/iPhone. Pendiente aprobación visual del
propietario y validación nativa iOS antes de distribuir. Sin GO de publicación
ni autorización implícita de deploy. El trabajo de acceso offline permanece en
su worktree separado y no forma parte de esta instalación de diseño.
