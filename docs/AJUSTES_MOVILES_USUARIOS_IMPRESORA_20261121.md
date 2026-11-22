# Ajustes móviles: drawer, Usuario, Impresora y Acciones

Fecha: 21 de noviembre de 2026. Base: production-main `61d5d5aa`.
Worktree exclusivo: `C:/t/fp-movil-final-20261121`.
Rama: `agent/refinamiento-movil-20261121`.

## Alcance realizado

- Footer móvil: icono de salida proporcionado por el propietario, con tinte de
  marca; una sola entrada de Usuario, sin botón duplicado a la derecha.
- Cabecera nativa Usuario: flecha de regreso, título Usuario y acciones PIN y
  filtro. Sin avatar, búsqueda ni subtítulo departamental. Windows/web conservan
  su presentación anterior, incluso en ventanas estrechas.
- La opción Permisos abre directamente el editor existente para el usuario
  elegido. Se conservan los controles de autorización y el guardado existente.
- Crear/editar usuario en teléfonos: contenedor, campos y botones cuadrados;
  altura acotada con contenido desplazable. El propietario confirmó que se
  refería a crear usuario, no al formulario de productos.
- Configuración nativa: se omite App y actualizaciones. Windows/web conservan
  su destino App. Las demás entradas no se retiraron.
- Impresora móvil: controles rectangulares, resumen sin datos repetidos, textos
  de conexión más breves y opciones menos frecuentes agrupadas en Opciones
  avanzadas. No se eliminan valores persistidos ni se modifica el motor de
  impresión. WindowsPrinterSettingsView no se modifica.
- Acciones nativas de Facturación: ancho 75%, superficie blanca sólida, sin
  degradado lateral, conservando divisores, selectores y herramientas existentes.

## Fallo encontrado y corrección

La ejecución Android detectó `TextEditingController was used after being
disposed` al cerrar el formulario y navegar inmediatamente. La limpieza estaba
ligada al resultado de pop, que termina antes de retirar la ruta animada.
En teléfonos nativos ahora espera `TransitionRoute.completed` antes de liberar
los controladores. Se añadió el recorrido cancelar con texto escrito, avanzar
30 ms de la animación y navegar a Configuración. No se cambió ese comportamiento
en Windows/web. La reproducción nativa posterior no presentó la pantalla de error.

## Archivos

Prefijo de aplicación: `apps/fulltech_app/`.

- `lib/core/widgets/mobile_drawer_account_footer.dart`
- `lib/features/account/account_menu_screens.dart`
- `lib/features/settings/ui/printer_settings_page.dart`
- `lib/features/user/users_screen.dart`
- `lib/modules/cotizaciones/cotizaciones_screen.dart`
- `assets/image/mobile_navigation/logout_outline.png`
- `test/core/widgets/mobile_drawer_account_footer_test.dart`
- `test/features/account/account_settings_navigation_test.dart`
- `test/features/settings/printer_settings_platform_test.dart`
- `test/features/user/users_mobile_presentation_test.dart`
- `test/modules/cotizaciones/billing_ecf_selector_visible_test.dart`
- `test/preview/mobile_refinement_preview.dart`
- `docs/DESIGN_SYSTEM.md` y este informe, desde la raíz del repositorio.

El `.env` local ignorado de este worktree apunta exclusivamente a loopback para
las pruebas; no contiene credenciales. No se publica ni se copia a producción.
Los tres generados Windows que modificó pub get se restituyeron desde HEAD,
exclusivamente en este worktree nuevo. Ningún worktree anterior fue modificado.

## Validación y evidencia

- `flutter pub get`: PASS, sin actualizar versiones del lockfile.
- `flutter analyze --no-pub`: PASS, sin incidencias después de crear el entorno
  local requerido por pubspec. El primer intento señaló únicamente su ausencia.
- Diez archivos de pruebas relacionados: 84 PASS. Registro completo en
  `C:/Users/pc/Documents/FullPOS-Movil-20261121-final/flutter-regression.log`.
- Tras corregir el cierre del formulario se repitieron las siete pruebas de
  Usuario: PASS, incluyendo variantes Android, iOS y Windows. Evidencia adicional
  `flutter-users-final.log` en la misma carpeta.
- Footer: repetición PASS, verificando callbacks y ausencia de administración de
  usuarios sin permiso, con captura del widget real y fuente Manrope.
- Android: `flutter run -d emulator-5556 -t
  test/preview/mobile_refinement_preview.dart --no-pub` compiló e instaló el APK
  debug (247 s de Gradle). La conexión interactiva inicial se interrumpió;
  `flutter attach` recuperó el servicio y se verificaron hot reload y restart.
  El PTY de PowerShell fue denegado por Windows; se utilizó stdin privado del
  proceso Flutter sin modificar permisos del sistema.
- La vista local usa los widgets reales, dos usuarios ficticios, repositorios
  en memoria y un adaptador HTTP sin conexiones externas. No prueba el backend
  productivo ni la autenticación real.
- Capturas Android inspeccionadas: Usuario, Crear usuario, Configuración e
  Impresora. Acciones se inspeccionó en capturas de widget Android/iOS;
  drawer-footer-widget.png muestra el footer real con el nuevo icono.
- El emulador 5556 dejó de estar disponible al final de la revisión. No se
  reinició ni se reemplazó el contenido del emulador Samsung 5554 para compensarlo.
- `git diff --check`: PASS. Solo cambios móviles, pruebas y documentación;
  sin modificaciones de backend, fiscal, Prisma, licencias o producción.

## Límites y siguiente paso

No se realizó compilación/ejecución nativa de iOS desde Windows. Las variantes
iOS citadas son pruebas Flutter, no un iPhone real. No se ejecutó una impresión
física ni se probaron dispositivos Bluetooth/AirPrint; el alcance es de interfaz.
La revisión del propietario y la comprobación nativa iOS quedan antes de publicar
las apps móviles. No hay push, commit, merge, firma ni despliegue de esta entrega.

Estado: cambios locales preparados para revisión. Sin autorización de publicación
ni GO de producción móvil derivado de este informe.
