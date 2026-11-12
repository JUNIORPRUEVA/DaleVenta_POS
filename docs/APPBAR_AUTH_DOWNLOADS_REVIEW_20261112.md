# Formularios, bienvenida y accesos web de FullPOS

## Alcance y reutilización

Cambios locales sobre `integration/astro-production-20261112`. No se realiza
merge, deploy, publicación ni modificación de producción. Se reutilizan
`ActivationPanel`, su controlador/progreso del servidor, `AppsDownloadsPanel`,
`AppAccessLinks` y el evento de instalación PWA existente. No hay pantallas
nuevas, cambios en API, esquema, permisos ni cálculos de ventas.

## Cambios

- Login y registro Astro: campos de 44 px y acción primaria proporcionada.
  Se corrige también el mínimo global de 52 px que impedía reducir la altura.
  El texto principal del panel azul mantiene contraste blanco.
- Bienvenida existente: ancho máximo de 580 px (antes 404), título y jerarquía
  más amplios, azul corporativo, 20 px de radio, scroll en ventanas pequeñas
  y explicación del acceso permanente desde Configuración.
- `WebSessionActions`: accesos integrados en CustomAppBar, cabecera del shell
  y AppBar móvil del POS. En anchos pequeños solo muestran iconos; en escritorio
  amplio, etiquetas. No se colocan sobre productos, cobro ni tickets.
- Onboarding: aparece solo con apartados pendientes y abre el panel existente
  mediante `reopen`. Al completarlos desaparece. Se retira el acceso flotante
  anterior. Su X solo oculta la promoción; no modifica ni reinicia tareas.
- Aplicaciones: cuadro centrado de hasta 680 px, abierto al pulsar Apps. Incluye
  cuatro tarjetas compactas con las acciones existentes de descargar/instalar,
  copiar y compartir, además del acceso directo a `/apps`. Su X oculta únicamente
  aplicaciones. Las acciones se adaptan al ancho disponible sin desbordarse.
- Cierres independientes en Riverpod y `sessionStorage`, por usuario/empresa:
  sobreviven a navegación y recarga en la pestaña. Si el almacenamiento está
  bloqueado, se conserva el cierre en memoria mientras la app sigue abierta.
- Promociones limitadas a web/PWA autenticada con permiso existente de
  configuración; las apps nativas no muestran esos accesos promocionales.
- Configuración conserva «Apps de la empresa» y «Termina de preparar FullPOS».
  Se añade también el segundo acceso al submenú rápido del POS, reutilizando
  el mismo panel, incluso después de ocultar la promoción.
- El aviso HTML inferior deja de ofrecer instalación automática. Se conserva
  el mecanismo de actualización existente. La acción PWA invoca el prompt real
  cuando existe; en otro caso muestra instrucciones de Safari, Chrome/Android
  y Chrome/Edge, sin presentar una acción vacía.

## Referencia Alegra

Se inspeccionaron visualmente en Chrome sus formularios públicos actuales:
registro con nombre/correo/contraseña y login con correo/contraseña. Se observan
campos compactos, etiquetas independientes, bordes suaves y una acción primaria.
El tamaño observado es una comparación visual, no una medición de su CSS.
Se mantiene la identidad azul de FullPOS. No se creó una cuenta en Alegra.

- https://app.alegra.com/user/login/pos
- https://app.alegra.com/user/register/country/republicaDominicana?product=POS

## Descargas oficiales verificadas

Se consultaron los enlaces ya presentes en `AppAccessLinks`, sin sustituirlos:

| Canal | Resultado HTTP |
| --- | --- |
| Windows | GET parcial 206, contenido binario. HEAD había devuelto 403; no se considera una descarga rota por ese HEAD. |
| Android | GET y HEAD 404 desde GitHub. Pendiente publicar el APK en el enlace oficial o confirmar otro enlace oficial. |
| iPhone | App Store 200. |
| PWA | Sitio oficial 200. |

No se descargaron ni ejecutaron instaladores ni se compraron servicios. El 404
de Android es una limitación real pendiente; no se afirma que todos los canales
estén disponibles.

## Verificación funcional y visual

Chrome real, API y PostgreSQL exclusivamente locales:

- Login Astro abre Flutter. Se observaron ambos accesos en el AppBar del POS.
- Apps abre el anuncio de cuatro plataformas y su enlace llega a la sección
  existente de descargas. No aparece la antigua tarjeta inferior de instalación.
- Cerrar Apps conserva onboarding; cerrar onboarding conserva el progreso.
  Tras recargar, los accesos cerrados permanecen ocultos durante la sesión.
- Login y registro se inspeccionaron a 320 px de ancho en emulación de Chrome,
  sin recorte horizontal. La revisión del encabezado móvil detectó solapamiento
  del área mínima de las X; se corrigió y se añadió una prueba geométrica.
- Pruebas de widgets a 320/390/1280 px: cierres, independencia, navegación a
  Apps, tareas completadas, apertura del asistente, ausencia nativa e instrucciones
  PWA. Configuración puede retomar el panel después de ocultar el aviso.
- Pruebas de regresión dirigidas: permisos/rutas, menú de cuenta, venta rápida,
  eliminación/restauración de tickets y barra de tickets.
- Astro check: 0 errores, 0 warnings, 1 hint existente por beforeunload.
  Pruebas de sesión web: 11 aprobadas; build: 14 páginas.
- Smoke de imagen combinada: 9 grupos aprobados, incluidos registro, login,
  tenant, ticket único concurrente, rutas/recursos y exclusión de tickets en logs.
- Imagen final local: `fullpos-public-web:entry-polish-qa`, compilación
  de Flutter Web y validación Nginx correctas; smoke repetido con los 9 grupos
  aprobados sobre esa imagen. Disponible exclusivamente en el entorno QA local
  `http://127.0.0.1:4018/` con API/base de datos aisladas. La clave pública
  ficticia usada para compilar el portal es solo de QA: esta imagen no es un
  artefacto de despliegue de producción.
- En la imagen final se observó el encabezado a 320 px con separación entre
  menú, onboarding, Apps, escáner y acciones. El anuncio se adapta también a
  anchos inferiores y mantiene acceso a sus opciones mediante scroll. Una parte
  de la revisión se vio interrumpida por otras ventanas superpuestas; no se
  afirma una inspección visual nativa completa en dispositivos físicos.

Validación dirigida final para preparar el PR: `flutter analyze --no-pub` sin
incidencias y 118 pruebas aprobadas en catorce archivos, incluyendo login,
Configuración, onboarding, descargas, mayoreo asíncrono, detalle y regresiones
de navegación/ventas. Incluye una prueba geométrica del encabezado a
320 px y la X del propio anuncio. Las primeras ejecuciones detectaron el
solapamiento del área táctil; el resultado final incluye su corrección.
La instalación nativa real de cada canal y la aceptación del prompt del
navegador no forman parte de esta prueba.

## Ajustes posteriores solicitados: entrada, bienvenida y venta vacía

- Al finalizar el registro se conserva el formulario con botón ocupado, sin
  pantalla Astro de carga completa. Se obtiene el mismo ticket de un uso y se
  abre Flutter directamente. Los fallos siguen dejando recuperación mediante
  login y se impide crear la misma cuenta dos veces.
- La cubierta HTML de Flutter permanece durante la restauración de sesión y
  carga de empresa, en lugar de revelar otra animación al primer frame. Flutter
  la retira después del frame listo, sin sesión o con error de preparación;
  el fallback de errores también la libera. Las apps nativas conservan su carga.
- La bienvenida espera a que la empresa esté lista y comprueba que el estado
  de activación corresponda a esa empresa. Panel, recorrido y retorno temporal
  se reinician al cambiar la identidad, sin reiniciar tareas del servidor ni
  marcar la bienvenida como vista automáticamente. El botón de bienvenida
  continúa abriendo el asistente existente. Se prueba también el cambio de
  identidad con un panel anterior abierto.
- La columna de detalle conserva subtotal, totales aplicables y el importe de
  cobro aun sin productos. Cobrar y el gesto de descuento quedan deshabilitados
  en vacío; no cambian cálculos ni condiciones fiscales. El icono pasa a bolsa
  de compras y el texto a «Aquí verás los productos que elijas para tu próxima
  venta». Las pruebas comprueban el estado vacío y las acciones con productos.
- Copiar usa la URL oficial de cada tarjeta; compartir reutiliza SharePlus y
  su alternativa existente de copiar si no está disponible. Se prueba la copia
  real al portapapeles simulado y la disponibilidad de las cuatro acciones.
  No se envían enlaces a terceros durante QA.

Comprobación real posterior en Chrome sobre `http://127.0.0.1:4018/`:

- Alta de una empresa ficticia nueva: Finalizar conserva el formulario con
  «Creando tu cuenta…» y navega a Flutter, sin la antigua pantalla Astro de carga.
- Aparece la bienvenida amplia en el POS. «¡Comencemos!» abre el panel existente,
  que muestra 2 de 5 apartados completados y 3 pendientes. No se crearon productos,
  no se abrieron turnos ni se registraron ventas para esta comprobación.
- Se observaron el icono/texto nuevos, subtotal/utilidad en RD$ 0.00 y Cobrar
  deshabilitado sin productos.
- Apps se observa centrado y ancho, con las cuatro plataformas y acciones
  descargar/instalar, copiar y compartir. La copia está cubierta también por
  la prueba de portapapeles; no se completó un envío mediante el selector del
  sistema. La revisión móvil de estos cambios está cubierta por widgets a
  320/390 px; no equivale a probar instalación en teléfonos físicos.
- La observación del cambio de pantalla se hizo mediante capturas puntuales,
  no mediante grabación continua de todos los frames del arranque.
- Smoke repetido en la nueva imagen: 9 grupos aprobados. ID de imagen local:
  `sha256:21e23c2e4d23399ad460598092c4902be00137150791862f167c512e5fbef302`.
  Análisis Flutter final: sin incidencias. Las primeras ejecuciones de widgets
  detectaron desbordamiento de las acciones a 320 px; se corrigió con distribución
  adaptable y las ejecuciones finales pasan.

La consola de la revisión local anterior mostró reconexiones fallidas de `/socket.io`,
un 404 de `/api/company-manual`, rechazo del header `Accept-Encoding` por el
navegador y un aviso de transición abortada al salir de
Astro hacia Flutter. Las rutas/formularios y el POS siguieron abriendo. No se
modificó infraestructura de sockets ni el módulo de manuales para ocultar estos
resultados; esta comprobación no certifica sincronización en tiempo real ni
una consola global libre de errores.

## Estado para revisión

Por solicitud posterior del usuario, estos cambios se preparan en el PR #40
existente hacia `production-main`; no hace falta otro PR. No se realiza merge
ni despliegue. Android requiere atención antes de anunciar todos los canales
como descargables.

La revisión previa del PR detectó 11 fallos en la ejecución de Flutter del commit
`5009dc75`: pruebas de Configuración sin fixture de activación, y una prueba de
login con router real sin inicialización de idioma/fuentes ni aislamiento de
almacenamiento/red. Se añadieron esas dependencias de prueba sin retirar
aserciones, y se comprueba la transición de ruta con frames acotados en lugar de
esperar animaciones de fondo del POS. También se protege el controlador del pie
de página contra publicaciones/limpiezas diferidas tras su destrucción, con una
prueba de regresión. El backend compila mediante `npm run api:build` después de
instalar las dependencias del checkout con `npm ci`.

Se actualizan también las expectativas del texto vacío en las regresiones de
mayoreo asíncrono y la etiqueta PWA «Instalar» en el panel de descargas. Se
mantienen los controles sobre respuestas pendientes, sesión expirada, carrito
y plataformas; no se omiten pruebas ni se relajan comparaciones visuales.

Para desplegar después del merge: EasyPanel `daleventapos/pwa`, rama
`production-main`, contexto `/`, receta `Dockerfile.public-web`. Mantener el
entorno y los argumentos reales existentes, especialmente la clave pública DOSA.
No usar la imagen local de QA, que contiene una clave ficticia. No se añaden
migraciones, seeds ni cambios de API. Conservar la imagen anterior para rollback
y comprobar acceso, empresa, bienvenida, POS y descargas después del despliegue,
siguiendo `docs/RELEASE.md`. La aceptación final exige los checks del nuevo SHA.
