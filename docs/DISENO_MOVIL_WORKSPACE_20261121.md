# Sesión de diseño móvil

Rama exclusiva: `agent/diseno-movil-android-ios-20261121`.
Worktree: `C:/src/fullpos-diseno-movil-20261121`.
Base: `2388fe94`, con los cambios de IA y el panel PDF ya guardados.

El objetivo inicial es ejecutar la app Android en modo debug y mantener la
sesión para revisar diseños con hot reload. No se han rediseñado pantallas.
No se publica ni se modifica producción. La verificación de iOS es independiente.

## Instalación de pruebas

La propiedad Gradle opcional `fullposMobilePreview=true` añade el sufijo
`.mobilepreview` únicamente al build debug. La instalación existente
`com.daleventa.pos` permanece separada. El perfil UAT mantiene las barreras de
destino local y la separación de datos y credenciales.

El manifiesto debug distingue visualmente esta aplicación y permite HTTP solo
a localhost/127.0.0.1. No se cambia el manifiesto release ni se amplía la lista
de destinos del guard UAT. ADB reverse comunica el puerto local permitido del
emulador con el mismo puerto del laboratorio Windows.

## Ejecución

Desde `apps/fulltech_app`:

```text
flutter pub get
flutter run --machine -d emulator-5554 --debug --no-pub
  --android-project-arg=fullposMobilePreview=true
  --dart-define=FULLPOS_UAT_PROFILE=true
  --dart-define=FULLPOS_UAT_BUILD=true
  --dart-define=FULLPOS_UAT_LABEL=DISENO_MOVIL
  --dart-define=APP_ENV=uat
  --dart-define=API_BASE_URL=http://127.0.0.1:4004/api
  --dart-define=APP_BASE_URL=http://127.0.0.1:4004
```

La ejecución utiliza el protocolo machine oficial para poder solicitar
`app.restart` con `fullRestart=false` tras cada edición Dart. No confundirlo
con hot restart: los cambios nativos o de inicialización pueden requerir una
nueva ejecución. El entorno local no acepta cuentas de producción.

## Verificación de la sesión

El 21/11/2026 se compiló, instaló y abrió la app en `emulator-5554`.
Se verificó visualmente la pantalla de inicio de sesión. Ambos paquetes,
el original y `.mobilepreview`, permanecen instalados.

Un proceso local privado conserva stdin del protocolo machine y observa los
archivos Dart de `lib` de este worktree. Al guardar solicita hot reload con
una pequeña espera para agrupar escrituras. Se comprobó una recarga exitosa
(`code: 0`) mediante un cambio de fecha del archivo, sin modificar su contenido.
El proceso debe permanecer activo para conservar esta comodidad durante la sesión.

La primera compilación detectó un conflicto entre las etiquetas de los
manifiestos principal y debug. Se corrigió con `tools:replace="android:label"`
en debug y la compilación posterior terminó correctamente. No se verificó iOS.

`flutter analyze`: sin incidencias (72,7 s). `git diff --check`: correcto.

## Sesión con cuenta real autorizada

El usuario solicitó conectar esta instalación móvil al backend real para entrar
con su cuenta. El lanzador privado admite `--real-backend`, que selecciona el
destino HTTPS de DaleVentas documentado en ENVIRONMENTS.md y usa
`APP_ENV=production`, sin habilitar el perfil UAT local ni modificar sus barreras.
La propiedad debug `.mobilepreview` permanece independiente del paquete habitual.
Esto no despliega ni modifica el servidor. En esta sesión las acciones de negocio
usarían datos reales: no efectuar pruebas de ventas, fiscal, caja ni escrituras.
El comando UAT anterior sigue disponible para pruebas aisladas.

Los ajustes del teclado del login son exclusivos de Android/iOS nativos:
evitan duplicar el inset inferior, permiten ocultar el teclado al desplazar y
proporcionan pistas de autocompletado sin autocorrección de credenciales.
El aspecto y las animaciones del teclado dependen del sistema operativo y del
teclado instalado; la app no instala ni sustituye el teclado del dispositivo.

Verificación de esta sesión: compilación debug e inicio correctos con el destino
real, `/health` HTTPS respondió HTTP200 y se revisó el formulario Android con
el teclado abierto. No se introdujo ninguna contraseña ni se envió un login por
parte del agente. La autenticación real queda para el usuario.
Las tres suites de acceso ejecutadas completaron30 pruebas aprobadas, incluyendo
insets simulados y acción Siguiente en Android/iOS. El análisis de los dos archivos
Dart de esta edición terminó sin incidencias. Una primera ejecución del test
detectó un uso de un booleano nullable en la nueva aserción; se corrigió y se
repitieron las tres suites completas. No se cambió el backend ni se desplegó.

## Vista de facturación móvil: revisión de diseño

La variante nueva exige Android/iOS nativo, lado corto menor de600px y ancho
menor de900px. Windows, web y tabletas con distribución de escritorio conservan
los controles anteriores. No se cambian autorización fiscal, precios, stock,
persistencia de tickets ni el motor del asistente.

Se reorganizó comprobante/cliente, lista de precios y búsqueda. Los tickets
se consultan desde la barra junto al escáner, con nombre independiente del
cliente, cantidad de líneas y total obtenido del calculador fiscal existente.
Crear, cambiar, editar y eliminar reutilizan sus manejadores existentes.
Acciones muestra cuatro filas compactas y abre el chat existente desde
«Asistente IA». Se conserva la calculadora y se retira el acceso flotante de
IA únicamente en esta pantalla de teléfono. Las tarjetas conservan imágenes
sin deformación, dos líneas de nombre, precio, stock y acceso para agregar.

Verificado:

- Hot reload exitoso en el emulador ya abierto; sesión real conservada.
- Revisión visual Android de cabecera, productos sin stock, Acciones y apertura
  del chat, sin enviar mensajes ni generar operaciones de negocio reales.
- `flutter test --no-pub test/modules/cotizaciones`:181 aprobadas.
- `flutter test --no-pub test/modules/cotizaciones/mobile_sales_controls_test.dart`:
  cinco adicionales aprobadas, incluyendo nombres largos y exclusión de tabletas,
  web/plataformas por condición y ventanas Windows estrechas.
- Las pruebas de la pantalla completa crean y cambian tickets ficticios separados
  y abren el chat en variantes Android/iOS. Son pruebas de widgets con repositorios
  simulados, no una emisión ni operación productiva.
- Análisis completo y análisis final de los seis archivos del cambio: sin incidencias.
- Comparación con HEAD del bloque `_buildMobileDraggableCartSheet` hasta
  `_buildMobileBody`: idéntico; el panel inferior no fue modificado.

Capturas locales privadas: `mobile-sales-before.png`, `mobile-sales-after.png`,
`mobile-actions-after.png` y `mobile-ai-after.png`, en el directorio de evidencias
de la sesión dentro de `.codex/backups/fullpos-release-preparation-20261120`.
La validación visual iPhone no se ejecutó en este equipo Windows. Quedan la
revisión del usuario y la ejecución de las pruebas de navegador: la tentativa
Chrome se quedó cargando. No hay autorización de publicación ni despliegue.

## Segunda revisión móvil autorizada

El usuario amplió expresamente el alcance al carrito y totales. Por ello la
preservación visual del panel inferior de la revisión anterior deja de aplicar
a teléfonos Android/iOS; los cálculos y los manejadores siguen intactos.

- Señal lateral Acciones que permite pulsar o deslizar hacia la izquierda.
  Se respeta `MediaQuery.systemGestureInsets.right`: se comprobó en el emulador
  que deslizar desde el borde físico activaba Atrás de Android. La señal queda
  fuera de esa franja del sistema; deslizar desde la señal abrió Acciones.
- IA y calculadora dentro de Acciones, ambos64×64, sin un segundo acceso IA en
  la lista de filas. Se mantiene su implementación funcional existente.
- Cabecera fiscal/cliente/precios oculta al avanzar por el catálogo y visible al
  invertir el gesto. Búsqueda y panel de cobro permanecen; se ignoran desplazamientos
  de otras listas y reajustes sin arrastre. Pruebas en variantes Android/iOS.
- Productos con miniatura izquierda y nombre a la derecha, dos líneas como máximo;
  precios y stock en la segunda fila, botón de44px. Sin cambios de inventario.
- Menú, lápiz y papelera provenientes de `Desktop/ICONOS PROFECIONLES`, copiados
  sin modificar. Los nuevos recursos se incluyen explícitamente en pubspec.
- Carrito sin miniaturas, contador discreto, superficies rectangulares y tarjeta
  de totales sin margen exterior lateral. Las líneas se ocultan al colapsar para
  evitar fragmentos recortados. El editor de cantidad/descuento es rectangular y
  desplazable en teléfono para admitir el teclado; conserva la validación actual.

Validación: análisis completo sin incidencias; módulo de cotizaciones190 pruebas
aprobadas. Tras ajustar el inset del gesto, el archivo de integración de pantalla
completó11 pruebas aprobadas. Los nuevos recursos requirieron regenerar el bundle
y volver a ejecutar solamente la app debug del emulador; no se reinició ningún
servicio ni se desplegó. La prueba del editor espera400ms porque la fila admite
tap y doble tap: sin esperar el reconocedor todavía no abre la ruta. No se alteró
ese comportamiento para satisfacer la prueba.

Evidencia visual: `mobile-sales-refinement.png`, `mobile-header-collapsed.png`,
`mobile-floating-tools.png` en el directorio privado de evidencias de esta sesión.
Revisión iPhone física/simulador pendiente. No se emitieron ventas de prueba ni
se modificaron datos/configuración productivos como parte de la validación.

## Tercera revisión: ajustes solicitados por el usuario

La señal Acciones pasa a estar visualmente pegada al borde derecho. La superficie
de gesto continúa incluyendo la zona interior más allá del inset de navegación
del sistema; pulsar la señal también abre el panel. El gesto Atrás reservado por
Android no se desactiva ni se reasigna.

En teléfonos se elimina el botón de editar de cada línea, conservando la edición
al pulsar la fila. La papelera no lleva fondo ni borde: icono16px y área táctil44px.
El importe y la papelera comparten fila para reducir la altura del detalle; la
estimación visual por línea pasa a52px. El contador queda a la izquierda y el
indicador de arrastre se centra mediante un Stack independiente del ancho del
contador. No cambia cantidad, precio, borrado, fiscalidad ni persistencia.

El AppBar nativo muestra FullPOS junto al menú. Se reutiliza `search.png`, cuyo
hash coincide con `lupa (3).png` de la carpeta del usuario; se incorporan sin editar
`categoria - Copy (2).png`, `usuario (3).png` y `lista-de-opciones.png` como recursos
de categorías, cliente y lista de precios. Los destinos y acciones son los mismos.
Las ventanas Windows, web y tabletas con presentación de escritorio conservan
los controles y las alturas anteriores.

Validación: análisis completo y190 pruebas del módulo aprobadas. Dos pruebas
adicionales Android/iOS cubren navegación hacia Facturación y regreso: el acceso
global IA ahora escucha el cambio de ruta, evitando que reaparezca tras un inicio
en frío. El usuario conserva su acceso desde Acciones y las otras rutas conservan
su botón. Prueba visual Android con `mobile-refinement-final.png`; paquete debug
recompilado para incluir los PNG nuevos y hot reload nuevamente confirmado.
Quedan la revisión del usuario y la comprobación visual en iPhone. No hubo push,
merge, despliegue ni cambios del backend o de configuración productiva.

## Cuarta revisión: catálogo limpio y datos en Acciones

El propietario aprobó dejar únicamente el buscador sobre el catálogo de teléfonos
Android/iOS. Cliente, comprobante y lista de precios (cuando existe el módulo y
hay listas activas) pasan a Datos de la venta dentro de Acciones. Esta decisión
sustituye la ocultación del encabezado al desplazar el catálogo. Se reutilizan
los selectores y operaciones existentes; no hay nuevas llamadas de escritura.
El panel observa los proveedores y actualiza sus controles tras las selecciones.

Antes de confirmar el cobro, el resumen móvil muestra Cliente, Comprobante y el
modo de precios si corresponde. Cliente general no obliga a seleccionar cliente
para efectivo Normal; E31 sigue exigiendo identidad fiscal y crédito sigue
exigiendo cliente. No se cambiaron los validadores ni las transacciones.

Evidencias Android reales en el respaldo privado:
`mobile-search-only.png` y `mobile-sale-data-actions.png`. Se inspeccionaron sin
cambiar cliente, comprobante, precios ni confirmar ventas en el backend real.
La aplicación continúa con hot reload y la misma sesión y carrito del usuario.

Pruebas locales simuladas: apertura/cancelación del cobro con caja ficticia;
Normal permite Cliente general; E31 sin receptor bloquea el botón; cambio a
E32 desde Acciones se conserva al cerrar/reabrir. Los dobles de repositorio
evitan el caché de archivos de caja en widget tests. La prueba del menú espera
su cierre diferido y el siguiente frame antes de comprobar el valor actualizado.
Análisis completo sin incidencias y194 pruebas de cotizaciones/acceso IA
aprobadas; el caso adicional del menú también pasó en Android/iOS.

Pendiente: aprobación visual del propietario y visual nativa en iPhone. No se
autoriza publicación con este informe. No hubo commit, push, merge ni deploy.

## Quinta revisión: lista única y buscador independiente

Por solicitud del propietario se eliminan los rótulos Datos de la venta y
Herramientas. Acciones presenta una lista plana sin tarjetas individuales,
con panel recto y botones flotantes de radio4. Cliente, comprobante y precios
mantienen sus manejadores; Tickets se traslada del AppBar a la misma lista.
Al elegir Tickets primero se cierra Acciones y se abre el panel existente,
conservando creación, selección y separación entre carritos.

El AppBar telefónico usa el icono estándar de menú con el título Facturar.
El buscador y categorías son hermanos en una fila: el icono de categoría
queda fuera del campo, con área44px e indicador cuando hay filtro activo.
Windows/web/tabletas conservan la presentación anterior.

Validación: `flutter analyze --no-pub` sin incidencias;
`flutter test --no-pub test/modules/cotizaciones test/core/ai_assistant/mobile_billing_entry_point_test.dart`
aprobó194 pruebas. La regresión Android/iOS recorre Tickets desde Acciones,
conserva carritos separados, confirma ausencia de encabezados y verifica la
alineación de categoría fuera del campo. Capturas Android locales:
mobile-flat-search.png, mobile-flat-actions.png y mobile-flat-tickets.png en
la carpeta privada de evidencias. Hot reload confirmado. Sin ventas reales,
commit, push, merge, deploy ni modificaciones productivas. Sigue pendiente la
revisión visual del propietario y del iPhone real antes de publicación.

## Sexta revisión: mitad de pantalla y recursos del propietario

Acciones ocupa exactamente50% del ancho telefónico; separadores inferiores
de0.5px ordenan la lista. Los selectores admiten dos líneas para los valores en
ese ancho y mantienen el área táctil. IA/calculadora usan CircleBorder con64px.
El encabezado reutiliza el BrandedMenuButton original, sin modificar el widget
compartido de Windows. Categorías tiene superficie blanca propia y la lupa usa
una copia íntegra de `lupa-grande - Copy.png` como `mobile_search.png`.

Las fotografías móviles pasan de48a60px, con BoxFit.contain para conservar el
producto completo. El pie de totales añade sombra ascendente; Cotizar y Cobrar
tienen44px de alto y Cobrar incorpora elevación. La papelera pasa de16a22px
con la misma superficie táctil44px y sin añadir un botón de edición.

Análisis completo aprobado y194 pruebas de regresión aprobadas. Capturas de
widgets renderizados con datos ficticios: half-main-android.png y
half-actions-android.png (también variante iOS). Cubren el ancho195px sobre
viewport390, selección fiscal y navegación Tickets; no son una verificación de
emisión ni una prueba en iPhone real. El debug Android se recompiló para incluir
el asset y arrancó con hot reload. Tras arrancar pidió login nuevamente; se
solicitó al propietario entrar directamente en el emulador, sin solicitar ni
leer sus credenciales. La revisión visual autenticada sigue pendiente.

No se cambió el código del botón compartido ni archivos de Windows; se retiró
únicamente el ruido de sus tres archivos generados por pub get en este worktree.
No hubo commit, push, merge, deploy, emisiones reales ni cambios del backend.

## Séptima revisión: lupa compacta y eliminar proporcionado

Se reemplazó íntegramente mobile_delete.png por `Downloads/eliminar (3).png`,
verificando igualdad de hash. El icono solo se usa en los controles telefónicos;
la zona táctil sigue siendo44px. El buscador nativo tiene36px de alto, márgenes
laterales12px y lupa16px centrada dentro de un contenedor32px para impedir que
las restricciones del prefixIcon la estiren. Categorías conserva su botón44px.

Análisis completo aprobado,13 pruebas de la pantalla aprobadas (Android/iOS y
regresión Windows). La prueba mide explícitamente campo36px y lupa16px.
Captura real Android inspeccionada: mobile-compact-search-live.png. Hot reload
confirmó el nuevo recurso y el diseño sin reiniciar ni borrar datos de la app.
No se pulsó eliminar ni se confirmó ninguna venta. Sin cambios de Windows,
backend, producción, commit, push ni deploy.

## Octava revisión: turno en AppBar y escáner en Acciones

El botón Categorías mide36px, igual que el buscador. En teléfonos nativos el
AppBar muestra únicamente el acceso de turno y Acciones junto al menú/logo.
El turno reutiliza el PopupMenuButton y todas las operaciones preexistentes de
CashTurnMenuButton; mobileHeader es una opción visual con valor predeterminado
false. El estado distingue carga, revisión, no verificado, turno anterior,
abierto y cerrado. No se alteraron contratos, repositorios, permisos ni cálculos.

El escáner se abre desde la lista Acciones mediante el mismo manejador. El grupo
Turno del drawer se elimina solo cuando usesNativePhoneLayout es verdadero;
Windows, web y tabletas mantienen sus accesos anteriores. No se borraron rutas.

Análisis completo sin incidencias. Caja + drawer + prueba de pantalla:127 pruebas
aprobadas. Facturación + acceso IA:196 pruebas aprobadas. Esta última ejecución
se repitió secuencialmente tras una colisión temporal de copia de sqlite3.dll al
ejecutar dos procesos Flutter sobre el mismo build; el reintento pasó sin cambios
de código ni eliminación de artefactos. Los conjuntos comparten pruebas, no son
323 casos únicos. Se verifican apertura del menú en caja ficticia abierta y
cerrada, opciones de cierre/entrada y categoría36px en Android/iOS.

Captura Android real inspeccionada: mobile-turn-inspect.png. El estado real era
Turno anterior. Se revisó además el drawer sin el grupo Turno. No se abrió ni
cerró caja ni se registraron movimientos. Hot reload confirmado; no hay commit,
push, merge, deploy ni cambios del backend. Pendiente revisión del propietario
y comprobación visual en iPhone real antes de publicación.

## Novena revisión: navegación móvil y configuración compacta

Acciones pasa a60% de ancho y su borde hacia el catálogo se difumina a blanco
en el primer8% del panel. El extremo exterior permanece pegado al dispositivo.
La revisión visual detectó un fondo completamente transparente: se corrigió
el color de BoxDecoration a null cuando existe el gradiente, conservando el
resto del área opaca y legible. Se cerró/reabrió el diálogo tras hot reload para
evaluar la nueva construcción. No se aplicó transparencia al texto ni botones.

El drawer telefónico ocupa75%, presenta grupos planos de48px y elimina la
textura de fondo del cuerpo. Su pie rectangular ocupa todo el ancho lateral.
Los cinco PNG del propietario se copiaron sin transformar a
assets/image/mobile_navigation/{profile,users,add_users,settings,logout}.png.
Perfil/configuración/cierre mantienen sus callbacks existentes; Usuario y el
icono de administración están sujetos al permiso manageUsers y abren la misma
gestión existente. No se promete crear usuarios sin pasar por esa pantalla.

Configuración móvil usa filas de altura mínima56px, separadores finos, texto
oscuro e iconos azules. Las opciones de escritorio se mantienen en la misma
lista compartida, con las mismas condiciones de impresión/almacenes/activación.
App y actualizaciones conserva la ruta existente; Planes usa /planes, que ya
era el destino de la redirección desde /licencias. No se cambia licencia alguna
ni se implementan nuevos mecanismos de actualización móvil. Windows conserva
sus tarjetas, textos, rutas y acceso global IA. En teléfonos el acceso flotante
IA se oculta en todas las rutas; sigue disponible dentro de Acciones.

Archivos de esta revisión:
- apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
- apps/fulltech_app/lib/core/widgets/app_drawer.dart
- apps/fulltech_app/lib/core/widgets/mobile_drawer_account_footer.dart
- apps/fulltech_app/lib/features/account/account_menu_screens.dart
- apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart
- apps/fulltech_app/pubspec.yaml
- apps/fulltech_app/assets/image/mobile_navigation/profile.png
- apps/fulltech_app/assets/image/mobile_navigation/users.png
- apps/fulltech_app/assets/image/mobile_navigation/add_users.png
- apps/fulltech_app/assets/image/mobile_navigation/settings.png
- apps/fulltech_app/assets/image/mobile_navigation/logout.png
- apps/fulltech_app/test/core/widgets/mobile_drawer_account_footer_test.dart
- apps/fulltech_app/test/core/ai_assistant/mobile_billing_entry_point_test.dart
- apps/fulltech_app/test/modules/cotizaciones/billing_ecf_selector_visible_test.dart
- apps/fulltech_app/test/features/account/account_settings_navigation_test.dart
- docs/DESIGN_SYSTEM.md
- docs/DISENO_MOVIL_WORKSPACE_20261121.md

Validación: análisis completo sin incidencias;58 pruebas específicas aprobadas
(pantalla, pie, drawer, acceso IA y configuración),298 de cotizaciones/caja
aprobadas. Tras el ajuste visual del gradiente y del texto App y actualizaciones
se repitieron sus dos variantes Android/iOS, ambas aprobadas. Se corrigieron un
import no usado en la implementación y otro faltante en un test antes del PASS.
Las cifras comparten casos y no se suman como pruebas únicas.

Capturas Android reales inspeccionadas en el respaldo privado:
mobile-actions-60-final.png, mobile-drawer-75-final.png y
mobile-settings-list-final.png. Se recompiló únicamente el paquete debug de
pruebas para incorporar los assets y se confirmó hot reload. No se pulsaron
acciones destructivas, ni se cambiaron caja, ventas, datos fiscales o producción.
Sin commit, push, merge o deploy. Pendientes: aprobación del propietario y
revisión visual en iPhone real; no es un GO de publicación.

## Décima revisión: módulos móviles y Reportes

Se unificaron los cuatro iconos proporcionados (atrás, buscar, filtro y recargar)
y el encabezado con degradado exclusivamente para teléfonos Android/iOS.
Facturación conserva su menú; los módulos priorizan Atrás. Las barras que antes
dependían del shell de escritorio, incluidas las fiscales, reciben encabezado
nativo sin cambiar la navegación interna del asistente.

Se compactaron listas compartidas, historial de ventas y resumen de productos,
conservando importes completos y unidades; categorías/cajero permanecen en el
detalle. Compras presenta el estado una vez, en español. Reportes mantiene cuatro
indicadores y seis apartados desplegables. El fondo móvil omite marcas decorativas
de rol. Windows conserva el estilo y los controles anteriores.

Regresión ampliada: 852 pruebas PASS; después del último ajuste de filtros y
etiqueta de compras, 40 PASS. Son conjuntos con solapamiento, no deben sumarse.
La batería completa registró 2565 PASS, 10 omitidas y 6 fallos; tres de Productos
se corrigieron y pasaron en la regresión final. Persisten tres fallos del preview
de marca ya presente en HEAD (espera IA 64px frente al componente real 60px).

Android real inspeccionado con hot reload: Clientes, Productos, Lista de compra,
Reportes, Configuración, Historial de ventas/filtros y portada fiscal. No se
realizaron escrituras de negocio. Inventario de fuentes, archivos, evidencias y
visitas visuales pendientes: AUDITORIA_UI_MOVIL_MODULOS_20261121.md.
Sin commit, push, merge o despliegue. NO-GO de publicación: falta iPhone real,
las visitas detalladas que señala el inventario y resolver el desajuste de tests.
