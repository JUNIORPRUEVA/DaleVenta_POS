# Revisión visual de facturación — 2026-11-12

Rama local: `detalleVisuales`, worktree `C:/b/fp-detalleVisuales`, basada en
`production-main` (`cada11f8`). Incluye los ajustes de login realizados antes
de esta revisión. Los cambios no están publicados ni integrados.

## Cambios

- «Factura actual»: título de 18 px y acciones de 24 px en áreas de 44 px.
- Primera fila: Comprobante, seguido de Lista de precios cuando corresponde.
  El selector electrónico reutiliza el menú, modos y acciones existentes;
  conserva el aviso de receptor pendiente y el bloqueo por falta de numeración.
- Segunda fila: cliente dentro de un borde común y botón «Nuevo», con el PNG
  proporcionado por el usuario en `assets/image/cliente-nuevo.png`.
- Separación alrededor de sincronización reducida de 8 a 2 px, manteniendo
  el área de interacción de 40 px y los indicadores de estado.
- Logo compartido con filtrado ajustado (véase revisión de nitidez); lupa vectorial en el buscador
  para evitar la rasterización de un PNG pequeño.
- Vista previa aislada con botón «Probar e-CF» para comprobar ambos selectores
  sin modificar empresas, precios o ventas.

## Verificaciones ejecutadas

- Windows: 35 pruebas del conjunto de panel, cliente, AppBar, marca, selector
  fiscal y mayoreo. Después, 10 pruebas del panel con una regresión adicional
  de e-CF, alineación y receptor pendiente: 36 pruebas distintas aprobadas.
- Linux real, Docker Flutter 3.41.6: 19 pruebas visuales aprobadas. Se generaron
  las referencias de Linux dentro de Linux y las de Windows dentro de Windows.
- Análisis de los componentes modificados: sin incidencias.
- `git diff --check`: correcto.
- Compilación web release de la vista previa: correcta, disponible localmente
  en `http://127.0.0.1:4020` mientras siga funcionando el servidor de revisión.
- Compilación Windows debug del punto de entrada real: correcta. App abierta
  desde este worktree y comprobada visualmente en la pantalla de facturación,
  con el comprobante encima del cliente, botón Nuevo y totales visibles.

## Límite pendiente

La herramienta no pudo controlar las ventanas de Chrome y el conector del
navegador estaba indisponible. No se afirma una revisión visual real de la PWA
ni se atribuye definitivamente la borrosidad anterior al zoom. Se solicitó al
usuario dejar Chrome visible para completar esa comprobación. La vista web
compilada usa fixtures y los widgets reales; no crea operaciones comerciales.

No se ejecutaron ventas ni se cambiaron las opciones de la empresa para
forzar mayoreo. La lista aparece solo cuando la función está habilitada.

## Ajuste adicional — 2026-11-13

- Fila de cliente reducida de 44 a 38 px; selector interior de 36 px, botón
  Nuevo de 34 px e icono de 24 px. Etiqueta, nombre y acciones quedan centrados;
  el espacio de la etiqueta se adapta al texto ampliado.
- Se comprobaron los bordes superior e inferior de Comprobante y Lista de
  precios en la misma fila. La lista requiere función habilitada y listas activas.
- 14 pruebas Windows y 10 pruebas Linux aprobadas; referencias visuales de
  ambos sistemas actualizadas. Compilaciones web y Windows correctas.
- App nativa abierta desde `detalleVisuales` y fila compacta comprobada
  visualmente. Revisión en navegador omitida por decisión del usuario.
- Android actualizado con el enlace corregido por el usuario:
  `https://play.google.com/store/apps/details?id=com.daleventa.pos`.
  Respondió HTTP 200 y el identificador coincide con `applicationId` del proyecto.
  `AppAccessLinks.androidReleaseUri` alimenta los accesos Flutter, copia y
  compartir; `website/src/config/site.ts` alimenta la web. Se activó Google Play
  y se retiró la opción duplicada de APK de la web. No quedan referencias al
  antiguo APK en el código de ejecución de estas dos superficies.
- Android: 23 pruebas Flutter y 12 pruebas web aprobadas, incluida la copia del
  enlace Android y la igualdad entre la configuración web y Flutter. Astro
  check sin errores ni advertencias; build de 14 páginas correcto. Windows
  debug recompilado con Google Play. Se abrió Configuración → Apps de la empresa
  en Windows y se confirmó visualmente Android con la etiqueta Google Play y
  sus acciones Descargar, Copiar y Compartir. No se publicaron estos cambios.

## Revisión de nitidez y panel compacto — 2026-11-13

- El logo original mide 1254 × 1254: no falta resolución. Su reducción extrema
  a 36 px pierde detalles del diseño. Se aumentó a 40 px lógicos y se utiliza
  `FilterQuality.medium`, adecuado para reducir imágenes según la documentación
  del SDK instalado (`sky_engine/lib/ui/painting.dart`). El filtrado `high`
  del ajuste anterior no era apropiado para esta reducción. El primer intento
  decodificaba a 40 × DPR; la revisión posterior descrita abajo lo sustituye.
  También se ajustó el filtrado del icono Nuevo.
- No se encontró un filtro global de desenfoque en el POS. La causa de cualquier
  borrosidad adicional exclusiva de un navegador concreto queda pendiente de
  observación real; no se atribuye sin evidencia al zoom ni a la caché.
- Apps de la empresa deja de ocupar todo el alto: ancho máximo de 560 px,
  margen de 12 px, borde redondeado y altura del contenido. En pantallas bajas
  permite desplazamiento. Conserva descargar/instalar, copiar y compartir.
- Cada plataforma muestra instrucciones breves y el pie recuerda iniciar
  sesión con el mismo correo y contraseña. El anuncio web reutiliza las mismas
  tarjetas y el ancho máximo. No se cambiaron los enlaces oficiales.
- Windows: 39 pruebas aprobadas, incluyendo densidades 1/1.25/2/3, geometría
  del panel, cierre y desplazamiento a 320 × 480, copia Android y regresiones
  de cliente, comprobante, mayoreo y AppBar. Análisis de nueve archivos limpio.
- Linux (Docker Flutter 3.41.6): 29 pruebas aprobadas y referencias visuales
  generadas en Linux, conservando las referencias propias de cada plataforma.
- Compilaciones Windows debug y web release correctas. El ensayo de Wasm
  informa incompatibilidades existentes de dependencias; el build JavaScript
  finaliza correctamente. Vista previa local: http://127.0.0.1:4021.
- Verificación visual real en Windows: panel estrecho arriba a la derecha,
  cuatro plataformas, instrucciones y pie visibles, sin el antiguo bloque vacío.
  App abierta desde este worktree. Navegador no verificado: el host de acceso
  devolvió «The browser access host is unavailable».
- Sin cambios de datos, ventas, migraciones, merge ni despliegue.

## Segunda revisión de logo y lupa — 2026-11-13

El usuario confirmó que la primera corrección seguía viéndose mal. Se retiró
`cacheWidth/cacheHeight`: reducir durante la decodificación descartaba detalle
antes del filtrado. Ahora se entrega la imagen original al renderizador con
filtrado medio, manteniendo los 40 px lógicos. La referencia visual Windows
actualizada muestra bordes más suaves, sin el aspecto dentado anterior.

La lupa del catálogo usa ahora el icono vectorial compartido `AppIcons.search`,
de 22 px y trazo 2, en lugar del glifo Material de 18 px del primer intento.
Mantiene el área y la altura del campo de búsqueda y sus acciones.

24 pruebas Windows y 24 Linux aprobadas, referencias visuales actualizadas en
cada sistema y análisis de los tres archivos sin incidencias. Windows debug
compilado y app abierta desde `detalleVisuales`: comprobados visualmente el
logo con bordes más suaves y la lupa vectorial más definida, sin cambiar el
tamaño del buscador ni operar ventas.
Compilación web release de la vista previa correcta; conserva los avisos de
compatibilidad Wasm de dependencias ya documentados.
La observación en navegador continúa pendiente; no se afirma una verificación
visual de PWA ni una corrección global de resolución o escala del sistema.

## Historial de ventas y accesos — 2026-11-13

Alcance autorizado: presentación del historial y sus accesos. Esta etapa no
modifica el editor de facturación, empresa, clientes, compras o inventario.

### Auditoría y referencia

- FullPOS nativo: se observó el título incorrecto «Facturacion», búsqueda
  desproporcionadamente ancha y métricas que recargaban el encabezado.
- Tras restaurar Chrome el usuario, se inspeccionó visualmente su sesión de
  Alegra en `https://pos.alegra.com/invoices`. Se confirmó el título Historial
  de ventas, la tarjeta blanca, encabezados discretos, divisores suaves y
  estado vacío centrado. Columnas observadas: Número, Cliente, Creación,
  Total, Por cobrar y Estado. La cuenta no tenía ventas: no fue posible
  inspeccionar filas ni detalle reales, y no se creó ninguna operación.
- Se consultó la [guía oficial de Alegra](https://ayuda.alegra.com/migration/es/facturaci%C3%B3n-%C3%A1gil-en-el-punto-de-venta-pos)
  y su demostración visual del historial: lista, detalle separado, acciones
  visibles, divisores discretos y jerarquía de datos. La demostración publicada
  muestra datos de ejemplo de 2025 y complementa la inspección actual para
  observar un detalle con datos. Solo se tomaron criterios visuales, sin copiar sus
  campos, funciones ni colores.

### Cambios

- «Historial de ventas» sustituye «Lista de ventas» en navegación, resolución
  de títulos, sidebar y pantalla. Se conservan las mismas rutas y permisos.
- Facturación y Historial de ventas son los dos primeros accesos directos del
  drawer. La sidebar de escritorio también los presenta sin submenú Ventas.
  El resto de los grupos y accesos permanece disponible, incluido Turno móvil.
- Tras la corrección solicitada por el usuario, se recuperó la distribución
  original: métricas compactas en el AppBar, buscador/filtros/limpiar/fechas en
  una sola fila y proporciones originales 62/32 entre lista y detalle.
- Buscador de 40 px que aprovecha el ancho libre de su fila; bordes suaves y
  botones alineados sin sombra prominente. Métricas afinadas sin salir del
  encabezado. Se retiraron los nuevos encabezados de tabla y la reorganización
  interna de productos y botones del detalle para respetar el diseño original.
- Tarjetas con bordes del tema; tipografía del cliente más ligera. Cantidad y
  precio conservan su fila, cediendo ancho cuando hace falta para no desbordar.
- Sin cambios en carga/caché, búsqueda, filtros, selección, paginación,
  cálculos, repositorios, autorizaciones, devolución, PDF ni impresión.

### Verificación

- Windows: 9 pruebas del historial aprobadas a 1920/1280/960/760/390 px, texto
  ampliado, selección, búsqueda, filtros, fechas, limpiar, vacío y error.
  Los goldens fijan las fechas mediante los filtros reales para no depender
  del día de ejecución. Repositorio de prueba aislado; ninguna venta real.
- 53 regresiones aprobadas de navegación, drawer, Turno móvil, totales
  autoritativos, acciones de ventas y mensajes de error.
- Linux (Docker Flutter 3.41.6): 25 pruebas aprobadas de historial, navegación
  y drawer. Cinco referencias visuales Windows y cinco Linux, generadas en
  sus respectivos sistemas.
- Análisis de los cuatro archivos de ejecución y pruebas sin incidencias.
- Builds web release del punto de entrada real y Windows debug correctos.
  Web conserva los avisos ya conocidos de compatibilidad Wasm de dependencias.
- Windows real: se abrió el drawer y se comprobaron Facturación e Historial
  como accesos directos; se entró al historial y se verificaron título,
  métricas, barra de filtros y estado vacío. Las filas con datos se revisaron
  en referencias visuales generadas por las pruebas aisladas.
- No se hizo commit, PR, merge, despliegue ni operación comercial. App abierta
  en Historial de ventas desde el worktree `C:/b/fp-detalleVisuales`.
- La inspección posterior de Alegra confirma los criterios visuales usados;
  no requiere cambios adicionales de código. Se mantiene el detalle propio de
  FullPOS y no se incorporan columnas o acciones ajenas a su funcionamiento.

### Corrección de distribución solicitada por el usuario

El usuario rechazó la redistribución de métricas y el cambio de proporciones.
La versión final recupera la estructura anterior y limita la mejora a los
componentes existentes. Mantiene «Historial de ventas» y los accesos del menú
ya solicitados. Las pruebas incluyen ahora invariantes de posición: métricas
dentro de los 56 px del AppBar y buscador/filtro alineados en la fila siguiente.
Las referencias visuales anteriores de esta pantalla se sustituyen por las de
esta distribución recuperada; el resto de las mejoras de la rama se conserva.

Verificación de esta corrección: 9 pruebas Windows y 9 Linux aprobadas,
referencias actualizadas en cada sistema y análisis de los dos archivos
sin incidencias. Windows debug recompilado; comprobación visual real del
historial con métricas arriba, barra en una sola fila y proporciones originales.
La app queda abierta en esta pantalla, sin tocar ventas ni datos.

### Lista compacta y acciones sin duplicados

- En la lista de escritorio solo quedan Imprimir y Devolver. Se retiran los
  iconos Ver detalle y PDF de las filas; pulsar la fila sigue seleccionando la
  factura. PDF permanece en el detalle y en las acciones móviles existentes.
- La lista prioriza número, cliente, fecha/hora e importe. Estado y cajero
  permanecen en el detalle, sin repetirlos en cada fila de PC.
- Encabezado «Mostrando facturas…» de 40 px con texto y actualizar alineados.
  Buscador de 36 px y filtros/limpiar de 34 px, conservando la fila existente.
- Devolver, Imprimir y PDF del detalle tienen esquinas cuadradas y altura
  compacta. Sus callbacks y condiciones de habilitación se conservan.
- Datos y productos del detalle comparten un desplazamiento vertical con
  renderizado perezoso; totales y acciones permanecen abajo. Esto evita el
  recorte detectado al probar poca altura y conserva los campos fiscales.
- Se agregaron verificaciones a 1024 × 560, 1024 × 600 y 1280 × 720 con texto
  al 115 %, además del caso previo al 130 %. También se comprueba el detalle
  fiscal completo, los dos iconos de las filas y las tres formas cuadradas.
- Windows y Linux: 13 pruebas aprobadas en cada sistema. Se verifica también
  que los tres botones del detalle tienen exactamente 40 px de altura.
  Análisis de los dos archivos sin incidencias. Ninguna operación comercial
  ejecutada; las facturas existentes solo se consultaron por fecha.
- Revisión nativa: listado con dos iconos por fila, estado y cajero en el
  detalle, importes en una línea y filtros compactos. Se consultó desde
  04/09/2026 hasta 13/11/2026 para ver las filas existentes, sin imprimir,
  devolver ni modificar documentos.
- Compilaciones finales Windows debug y web release correctas. Se volvió a
  comprobar la app nativa tras igualar los tres botones a 40 px: rectangulares,
  alineados y visibles. App abierta en el historial con el período consultado.
  No se hizo merge ni despliegue.

### Vender ahora cuando no hay resultados

- Estado vacío: «No hay ventas con estos filtros», explicación breve y botón
  azul «Vender ahora», cuadrado y compacto. Actualizar permanece como acción
  secundaria. No se presupone que el negocio nunca haya realizado ventas.
- Solo aparece tras terminar la carga sin resultados; los errores conservan
  Reintentar. El botón usa `ensureAdminAuthorization` con el permiso y la ruta
  existentes de Facturación, y navega mediante `AppNavigator.go`.
- No crea ventas, tickets ni reinicia el carrito. En la revisión nativa se
  pulsó el botón y se comprobó la entrada a Facturación con los siete tickets
  previos y los productos del ticket activo conservados tras terminar su carga.
- Windows: 15 pruebas aprobadas, incluyendo navegación permitida y denegada,
  búsqueda sin coincidencias y ausencia del botón en errores. Análisis limpio.
  Compilación Windows debug y revisión visual del estado vacío correctas.
- Linux: las mismas 15 pruebas aprobadas sin regenerar referencias visuales.
  Compilación web release correcta.

## Auditoría y agrupación del menú Ventas — 2026-11-13

Se confirmó que los destinos ya existían: `/ventas/lista`, `/ventas/creditos`
y `/cotizaciones/historial`. Los dos últimos estaban dentro de Cliente. La
pantalla de créditos incluye consultas y abonos, que se conservan: el nuevo
nombre del acceso no convierte el módulo en una pantalla de solo lectura.

Distribución final del drawer y de la sidebar de escritorio:

- Facturación: acceso directo al POS existente.
- Ventas: Historial de ventas, Historial de créditos e Historial de cotizaciones.
- Cliente: acceso propio, sin repetir los historiales.

Solo se cambia la organización y el texto de los accesos. Se conservan los
ítems existentes, sus indicadores, habilitación, rutas y las comprobaciones
de autorización de cada destino. No se modifican pantallas, servicios,
permisos, modelos, consultas, cobros o cotizaciones. Los títulos largos de
la sidebar admiten dos líneas. El resaltado de Facturación requiere su ruta
exacta para no marcarse también al consultar el historial de cotizaciones.

Validación: 32 pruebas Windows aprobadas de navegación, drawer, sidebar y
Turno móvil; seis de ellas comprueban las tres rutas tanto desde el drawer
como desde la sidebar. Se verificó también accesibilidad en 390 × 500 y
1280 × 420. Análisis de los tres archivos limpio y build Windows debug
correcto. Revisión visual real: Facturación directa, Ventas desplegado con
los tres historiales completos y Cliente sin duplicados. App abierta con
ese menú visible desde `detalleVisuales`. Sin operaciones comerciales,
commit, PR, merge ni despliegue.
Linux (Docker Flutter 3.41.6): las mismas 32 pruebas aprobadas. Compilación
web release del punto de entrada real correcta.

## Alineación del nombre del cliente — 2026-11-13

Se ajustó únicamente la fila Cliente de facturación: selector que ocupa la
altura disponible y campo de texto con su altura natural, centrado dentro de
esa fila. Se retiró la altura tipográfica forzada a 12 px para
que el nombre use las métricas de la tipografía y el escalado existentes.
No se cambian dimensiones del panel, búsqueda, selección, creación, borrado
de selección, repositorios ni lógica de facturación.

La densidad compacta de escritorio desplazaba el nombre 4 px hacia abajo:
se reprodujo en dos pruebas antes de corregirla. Se fija la densidad estándar
únicamente en la decoración de este campo para mantener su centrado.
Windows: 18 pruebas aprobadas de panel y selector. Las cuatro comprobaciones
nuevas comparan la línea de base y la posición pintada del texto seleccionado
con «Cliente» a escala normal y 130 %, con densidad estándar y compacta.
Análisis de los archivos modificados sin incidencias.
Linux: las mismas 18 pruebas aprobadas y referencias visuales actualizadas.
Compilación Windows debug correcta y revisión real en la app: «Cliente»,
«Fune, srl» y «Nuevo» centrados en la fila. Se conserva la venta abierta.
Compilación web release correcta; sin revisión visual nueva en navegador.
- Sin operaciones comerciales, merge ni despliegue.

## Contornos del encabezado de facturación — 2026-11-13

El contenido blanco del selector fiscal podía tapar el contorno y sobresalir
de las esquinas del campo. `SalesDetailField` recorta ahora el contenido al
radio existente y pinta el borde por encima. Se aplica el mismo acabado a
Comprobante y Lista de precios, conservando dimensiones y comportamiento.
Windows: 18 pruebas de panel y selector aprobadas, incluidas vistas de
1920, 1280, 960 y 900 px. Referencias visuales actualizadas.
Linux: las mismas 18 pruebas aprobadas. Análisis del widget sin incidencias.
Build Windows debug correcto. Revisión real en ventana normal y maximizada
a 1920 px: contornos completos en ambos selectores, fila Cliente conservada.
App abierta desde detalleVisuales; sin operaciones comerciales ni despliegue.

## Historiales adaptables — 2026-11-13

- Ventas: se conserva la distribución compacta. A partir de 1000 px útiles
  dentro de la lista (ajustados al escalado de texto), aparece la columna
  del cajero. El estado vacío presenta solo «Vender ahora»; la recarga del
  encabezado y el reintento ante errores permanecen disponibles.
- Créditos y cotizaciones: buscador de 36 px sobre ambas columnas, paneles
  blancos con borde de 8 px, filas alineadas con selección azul suave y
  columnas secundarias según el espacio real. Detalle desplazable, importes
  visibles y acciones de esquinas rectas. Los teléfonos conservan sus tarjetas.
- Créditos usa el mismo umbral de 860 px en web y escritorio para evitar
  diferencias de presentación; el menú de turno reutiliza la variante compacta
  ya existente. Se conservan búsqueda, refresco y callbacks de abono, saldo,
  PDF, impresión, WhatsApp y eliminación con sus permisos existentes.
- Cotizaciones conserva filtros, panel de resumen, paginación, selección,
  edición, duplicado, PDF, eliminación y paso a ticket. Las métricas nuevas
  se etiquetan «cargadas» y «visible», sin confundir una página con el total
  del servidor. Teléfono, autor, productos e impuestos permanecen en el detalle;
  los filtros y el menú de acciones mantienen sus opciones.

Verificación: 37 pruebas Windows aprobadas (18 ventas, 10 créditos/cotizaciones,
6 utilidades y 3 contratos de paginación/catálogo). Las pruebas visuales cubren
390, 1024, 1920 y 2560 px en los historiales relacionados, además de las cinco
anchuras de ventas. Búsqueda, selección y acceso a las acciones/importes
comprobados con texto al 115 % en 1024 × 600. Análisis de seis archivos sin
incidencias; compilación Windows debug correcta. Datos de pruebas aislados,
sin ejecutar abonos, ventas, devoluciones, eliminaciones ni envíos.

Linux (Docker Flutter 3.41.6): las mismas 37 pruebas aprobadas y referencias
visuales actualizadas. Build web release correcto; el proyecto conserva los
avisos previos de dependencias no compatibles con Wasm y compila JavaScript.
Se inspeccionaron las imágenes renderizadas de los tres historiales. La app
nativa principal se ejecutó desde el binario de detalleVisuales; su árbol de
accesibilidad carga el POS existente. La herramienta no consiguió mostrar
su ventana por encima de VS Code, por lo que no se afirma revisión manual
nueva de los historiales ni revisión real en navegador en esta entrega.
Sin commit, PR, merge ni despliegue.

## Acciones de historiales y acceso a Facturar — 2026-11-13

- Drawer y barra lateral: «Facturar», conservando la ruta y los permisos.
- Créditos: «Crear nuevo crédito» en el buscador de escritorio y en el estado
  vacío sin error. Abre el POS existente tras verificar autorización; no crea
  una venta ni asigna automáticamente la forma de pago.
- Listas de escritorio: únicamente dos iconos, PDF/Editar en cotizaciones e
  Imprimir/Registrar abono en créditos. Selección de fila conservada.
- Detalle de cotizaciones: cliente y metadatos sobre fondo blanco, siguiendo
  la jerarquía de ventas. Productos desplazables e importes fijos. Todas las
  acciones anteriores, incluida eliminación con su autorización, accesibles
  desde el detalle.
- Detalles de créditos/cotizaciones: una sola fila de acciones de 40 px.
  El ancho se calcula con la tipografía y el escalado activos; lo que no cabe
  pasa a «Más acciones». Etiquetas sin saltos de línea, permisos y estados
  deshabilitados conservados. No se ejecutaron operaciones comerciales.

Windows: 60 pruebas aprobadas de historiales, navegación, drawer y cabecera.
Incluyen ruta de Crear nuevo crédito hacia Facturar, dos iconos por fila y
acceso a las acciones adicionales desde el menú en ventana de 1024 × 600
al 115 %. Referencias visuales actualizadas e inspeccionadas. Análisis de
seis archivos sin incidencias. Sin commit, PR, merge ni despliegue.

Linux: las mismas 60 pruebas aprobadas; referencias visuales de ambos sistemas
actualizadas. Compilaciones Windows debug y web release correctas. Se dejó
ejecutándose la app nativa de detalleVisuales. Revisión de imágenes renderizadas;
sin afirmar una nueva validación manual en navegador ni acciones comerciales.

## Ajuste al modelo visual de Ventas — 2026-11-13

Se retiró el desplazamiento fijo de 80 px del estado vacío de créditos y se
reutiliza un estado centrado con las medidas de Ventas: icono de 44 px, título,
descripción de 12 px y botón azul recto de 40 px. Cotizaciones usa el mismo
componente y ofrece «Crear nueva cotización». Ambos accesos abren el POS
existente tras verificar permisos; no crean documentos automáticamente.
En créditos sin registros no se duplica el botón en el buscador. Se redujeron
los pesos tipográficos extra de créditos y los valores de metadatos de
cotizaciones ahora usan el texto normal, como Ventas. Se mantienen los filtros,
paneles y las acciones comerciales existentes.

Windows: 34 pruebas aprobadas de los tres historiales. Cuatro pruebas comprueban
el centro geométrico de los estados vacíos en 1024 × 600 y 1920 × 1080; dos
comprueban la navegación autorizada de crédito/cotización hacia Facturar.
Se inspeccionaron sus imágenes renderizadas. Sin merge ni despliegue.

Linux: las mismas 34 pruebas aprobadas, referencias visuales actualizadas.
Análisis de cuatro archivos sin incidencias; build Windows debug correcto.
App nativa recompilada, abierta y revisada realmente en Historial de créditos:
botón centrado, sin duplicarlo en el buscador vacío y encabezados suavizados.
Se conserva el carrito previo y no se ejecutaron operaciones comerciales.

## Paneles de filtros coherentes con Ventas — 2026-11-13

Créditos y cotizaciones reutilizan un panel blanco de hasta 430 px, cabecera
con icono azul, campos rectos con fondo claro, contenido desplazable y acciones
Cancelar/Aplicar fijas abajo. Cotizaciones conserva cliente, búsqueda de cliente,
categoría y fechas; estas aparecen primero. Limpiar modifica el borrador y
Aplicar confirma los cambios; cerrar/cancelar descarta el borrador.

Créditos no tenía panel: se incorporó rango de fechas inclusivo en horario del
negocio, estado Pendiente/Saldado/Todos y cajero, sobre los créditos ya cargados.
No se inventan criterios de pago ni se alteran consultas, abonos o saldos.
La búsqueda, selección y resumen usan los filtros aplicados. El cajero aplicado
se conserva en las opciones aunque desaparezca tras una recarga.

Windows: 39 pruebas aprobadas de los tres historiales, incluidos aplicar,
cancelar, limpiar, límites de fechas y combinación de estado/cajero. Paneles
comprobados en 1024 × 600 y 1920 × 1080 con botones inferiores accesibles.
Análisis de cinco archivos sin incidencias. Sin operaciones comerciales,
commit, merge ni despliegue.

Build Windows debug correcto. Revisión real del panel de créditos en la app
recompilada: cabecera, campos y acciones inferiores visibles; se dejó abierto
para revisión. No se aplicaron filtros ni operaciones comerciales en la cuenta
real durante esta inspección.

Linux: las mismas 39 pruebas aprobadas y referencias visuales actualizadas.
Compilación web release correcta. Sin merge ni despliegue.

## Clientes: presentación coherente con Ventas — 2026-11-13

Se sustituyeron los botones de texto del AppBar por iconos de Exportar,
Importar y Actualizar con sus tooltips y estados deshabilitados existentes.
Se retiraron Nuevo cliente del AppBar, el FAB móvil y la creación duplicada
del detalle. En el estado vacío queda un botón centrado «Crear cliente» que
abre Facturar tras comprobar permisos; el alta se realiza allí.

Buscador sobre ambas columnas, paneles blancos con borde fino y detalle
derecho desplazable. El nombre se muestra una sola vez en su cabecera;
tipografía más suave, tarjetas de actividad proporcionadas al escalado de
texto, correo también en el detalle. Se conserva resumen, movimientos,
edición, importación/exportación, filtros y paginación. En listas con al menos
1000 px útiles se añade la columna Correo; en ventanas pequeñas se mantiene
la distribución compacta. Umbral compartido de 860 px en web y escritorio.

Windows: 15 pruebas aprobadas: ocho variantes visuales (1024/1366/1920/2560,
con datos y vacías), navegación de Crear cliente hacia Facturar y seis pruebas
de paginación/filtros/offline. La vista de 1024 × 600 usa texto al 115 %.
Análisis de pantalla y pruebas sin incidencias. Imágenes renderizadas
inspeccionadas. Sin operaciones comerciales, commit, merge ni despliegue.

Compilación Windows debug correcta. Revisión real en ventana normal y
maximizada a 1920 px: AppBar con iconos, columna Correo adaptable y detalle
con datos, tarjetas y movimientos. App dejada abierta en Clientes desde
detalleVisuales. No se crearon, editaron ni importaron clientes en la cuenta real.

Linux: las mismas 15 pruebas aprobadas y referencias visuales actualizadas.
Compilación web release correcta. Sin merge ni despliegue.

## Inventario: afinado de Productos — 2026-11-13

Auditoría previa: buscador limitado a 760 px en monitores amplios, nombre de
producto fijo en 230 px, filas con máximo fijo de 54 px y sombras superpuestas
en tarjetas/superficies. La pantalla ya tenía tabla, tarjetas, permisos,
selección múltiple y callbacks de inventario reutilizables.

Se ajustaron únicamente los widgets del catálogo: buscador que aprovecha el
ancho con espacio para filtros/almacenes/acciones, bordes finos y radio de 8 px,
nombre de producto adaptable hasta 480 px y filas que admiten texto ampliado.
La tabla conserva todas sus columnas y permite desplazamiento horizontal en
ventanas estrechas; teléfonos conservan sus tarjetas. Sin columna derecha.
No se modificaron reglas de stock, impuestos, precios, repositorios, formularios,
permisos ni acciones de importación/exportación/eliminación.

Windows: nueve pruebas aprobadas. Cinco vistas de 390/768/1024/1920/2560 px,
1024 con texto al 115 %, búsqueda por código y callback remoto, selección
múltiple, edición y botones deshabilitados por permisos. Dos regresiones de
ajuste incremental de stock conservan el incremento. Referencias visuales
inspeccionadas. Análisis limpio. Sin merge ni despliegue.

Compilaciones Windows debug y web release correctas. Revisión real de Productos
en ventana normal y maximizada a 1920 px: buscador amplio, nombres largos
legibles y acciones conservadas. La app quedó abierta desde detalleVisuales.
No se ejecutaron altas, cambios, ajustes ni eliminaciones en la cuenta real.

Linux: las mismas nueve pruebas aprobadas y referencias visuales actualizadas.

## Productos y Clientes: buscadores compactos e iconos entregados

Se limita el buscador de ambas pantallas a 760 px en escritorio, conservando
su adaptación al espacio disponible. Productos aumenta sus filas de tabla
a 64–72 px y las tarjetas compactas a 80 px (88 px en teléfono). Se preservan
columnas, permisos, selección, filtros y callbacks; sin cambios de negocio.

Los siete PNG originales entregados se copian como assets locales y se usan
en búsqueda, exportación, nuevo producto, actualización, cierre, edición y
eliminación donde corresponde. El símbolo «más» se usa para agregar, sin
sustituir el menú de tres puntos. Se respeta el color heredado de los botones.

Verificación: 24 pruebas de Productos/Clientes aprobadas en Windows y Linux;
16 pruebas visuales repetidas tras asegurar la decodificación de los PNG.
21 pruebas de historiales aprobadas sin actualizar sus referencias. Análisis
de los cuatro archivos de implementación limpio. Revisión de capturas entre
390 y 2560 px, incluido texto al 115 % en 1024 px. Windows debug compilado y
Productos comprobado en la aplicación nativa con datos existentes, sin
ejecutar acciones de escritura. Se deja abierta desde detalleVisuales.

Alegra no pudo inspeccionarse en vivo: su ventana estaba minimizada y la
herramienta no pudo restaurarla. Se utilizó la captura enviada por el usuario
como referencia de composición. Sin merge ni despliegue.

Web release compilado correctamente. El ensayo Wasm emitió advertencias de
dependencias existentes; la compilación JavaScript terminó correctamente.
No se realizó revisión visual en navegador en esta iteración.

## Afinación posterior de la lista de Productos

A petición del usuario se reduce la densidad visual: contenido de escritorio
centrado con máximo 1440 px, buscador y tabla alineados, filas de 48–56 px
(ampliables con la escala de texto) y encabezado de 40 px. Las tarjetas de
teléfono/tablet se ajustan a 74/64 px mínimos. Se conservan todas las columnas,
iconos, permisos y acciones. No se modifica Clientes en esta corrección.

Nueve pruebas del catálogo y de incremento de stock aprobadas en Windows.
Se comprueba el centrado y ancho máximo en 1920/2560 px, la adaptación en
390/768/1024 px y la escala de texto al 115 %. Análisis sin incidencias.

Las mismas nueve pruebas pasaron en Linux. Compilación Windows debug correcta
y revisión nativa maximizada a 1920 px: márgenes laterales de 240 px, filas
compactas con imagen, precio e impuesto legibles y todas las acciones visibles.
La aplicación queda abierta en Productos. No se ejecutaron operaciones de
escritura ni cambios de datos. Sin merge ni despliegue.

Compilación web release de esta corrección aprobada; persisten los avisos
previos del ensayo Wasm de dependencias, sin impedir la salida JavaScript.

## Categorías: lista vertical y formulario cuadrado

Se sustituye la cuadrícula por filas verticales de 64 px, con miniaturas de
40 px y acciones de editar/eliminar con tooltip. El contenido queda centrado
y limitado a 1240 px. Se retiran el título y el botón «Nueva categoría»
duplicados dentro del contenido; permanece el acceso del AppBar. Se conservan
buscador, contadores, categorías derivadas, permisos y operaciones existentes.

El formulario usa contorno cuadrado, espaciado interior de 20 px, campo y
botones cuadrados, y previsualización de 72 px junto al selector de foto.
Se conserva la selección, retirada y optimización de fotos móvil/escritorio,
la validación, el guardado y el renombrado existentes. El radio opcional del
diálogo compartido mantiene su valor anterior para todos los demás usos.

16 pruebas aprobadas en Windows: cuatro tamaños (390/1024/1920/2560), lista
vertical alineada, ausencia de título/botón repetido, búsqueda, formulario,
validación/guardado con controlador simulado, persistencia real en caché de
prueba de la imagen y regresión del catálogo de Productos. Análisis limpio.

Windows debug compilado correctamente y ejecutado desde detalleVisuales. La
app quedó en login (sin sesión activa), por lo que no se afirma una revisión
nativa de Categorías autenticada. Las ocho capturas de pantalla/formulario
se revisaron mediante las pruebas visuales. No se inició sesión ni se crearon,
editaron o eliminaron categorías reales. Sin merge ni despliegue.

Las mismas 16 pruebas pasaron en Linux; referencias por plataforma actualizadas.
Web release compilado correctamente. El ensayo Wasm conserva los avisos de
dependencias ya existentes; la salida JavaScript se genera correctamente.

## Recuento y Listas de precios

Recuento: únicamente pesos de tipografía de tarjetas, resumen móvil y desglose
por categoría (500/600 en lugar de 700/800/900). Se mantienen posiciones,
colores, valores y cálculos.

Listas: contenido centrado con máximo 1320 px, paneles blancos separados y
controles cuadrados mediante un tema local. Formulario de crear/editar
ampliado a 580 px, borde recto, campos espaciados y acciones alineadas.
Se reutiliza FullTechDialog, conservando la validación y persistencia previas.

El selector sustituye la hoja inferior por un panel anclado a la derecha, de
alto completo, 38 % del ancho de escritorio (360–760 px) y ancho completo en
teléfono. Incluye cierre, búsqueda paginada y categoría. Reutiliza
ProductSearchController y fetchProductCategories del repositorio existente;
el filtro se envía al servidor antes de paginar. No descarga todo el catálogo
ni filtra únicamente la primera página. Se conservan carga, errores, reintento
y cargar más. No se modifican API, modelos, reglas, precios ni sus cálculos.

Referencia visual consultada: https://store.softhealer.com/blog/odoo-store-9/manage-pricelist-items-from-product-v17-10072

Windows: 18 pruebas aprobadas, incluida regresión de facturación/mayoreo,
crear/editar/activar, conservación de escalas, búsqueda remota y cuatro tamaños
390/1024/1920/2560 px (1024 con texto al 115 %). Doce referencias visuales
de pantalla, formulario y selector; geometría de anclaje/ancho/alto, cierre y
filtro con categoría fuera de la primera página. Análisis limpio.

Linux: las mismas 18 pruebas aprobadas y referencias por plataforma guardadas.
Windows debug compilado correctamente desde detalleVisuales. La sesión real
quedó en login tras abrir la compilación; se pidió al usuario entrar en la app
sin transmitir su contraseña por el chat para poder finalizar la revisión.

Web release compilado correctamente; el ensayo Wasm conserva advertencias de
dependencias previas sin impedir la salida JavaScript. Sin merge ni despliegue.

### Revisión nativa después de iniciar sesión

Se comprobó la compilación de detalleVisuales en la sesión real. Listas de
precios conserva los paneles centrados y cuadrados. Selector lateral derecho
de alto completo, carga de productos y categorías reales correctas. Al elegir
HERRAMIENTAS devuelve los tres productos de esa categoría. Formulario de nueva
lista amplio y cuadrado, abierto y cancelado sin guardar ni crear registros.

Recuento comprobado con datos cargados: tipografía más fina, mismas tarjetas,
distribución y valores de la captura del usuario. La app queda abierta allí.

Límite de la revisión manual: la escritura mediante la herramienta produjo
una aserción de HardwareKeyboard de Flutter (KeyDownEvent para Control Left
ya presionada), mostrada como aviso de depuración. Se cerró el aviso; no se
modificó código de autenticación ni teclado. La búsqueda remota y su combinación
con categoría están verificadas por las pruebas automatizadas. No se guardaron
reglas, listas ni precios reales durante esta revisión.

## Recuento, selector de productos y módulo Compras — 13/11/2026

Trabajo en `detalleVisuales`, worktree `C:/b/fp-detalleVisuales`.
Se conservaron los cambios anteriores. Sin merge ni despliegue.

Auditoría: Compras utiliza cinco vistas del mismo módulo: Nueva compra,
Lista de compra, Suplidores, Facturas y Por comprar. Se reutilizaron sus
repositorios, permisos, borradores, formularios, estados y acciones existentes.
No se modificaron modelos, endpoints, cálculo de costes, cantidades ni PDF.

Recuento: iconos originales de filtro y actualización suministrados por el
usuario; tarjetas más compactas que conservan su diseño en tamaños reducidos.
Panel de filtro blanco, controles cuadrados, contenido desplazable y acciones
fijas al pie. Aplicar y limpiar conservan su comportamiento. En Listas de
precios el selector muestra la miniatura del producto a la izquierda, usando
el componente de imágenes y sus alternativas existentes.

Compras: tema local compartido con controles cuadrados, bordes discretos,
campos blancos y tipografía más fina. Catálogo con imagen separada de nombre,
coste y existencias. Carrito ajustado a pantallas pequeñas, contenido desplazable
y totales accesibles. Órdenes con PDF visible y acciones secundarias en menú;
detalle sin saltos de línea en sus acciones. Suplidores, facturas y recomendaciones
mantienen sus datos, formularios y funciones con el mismo estilo. Eliminadas
acciones visuales duplicadas donde ya queda acceso equivalente. Contenido
centrado con ancho máximo; paneles de detalle más proporcionados.

Se copiaron los PNG originales de la carpeta de iconos sin modificar las imágenes.
Los iconos se dimensionan dentro de su contenedor para evitar que las restricciones
de los campos agranden las imágenes.

Validación Windows: 48 pruebas aprobadas del módulo Compras, Recuento y Listas
de precios. Incluyen borradores, PDF, selector remoto, acciones según estado,
formularios, filtros y diseños a 390/1024/1920 px; texto al 115 % en 1024 y carrito
con opciones adicionales a 1024 × 600. Referencias visuales por plataforma.
Análisis de los archivos modificados y pruebas nuevas sin incidencias.
Compilación Windows debug correcta con el backend configurado para la app real.
Las pruebas utilizan repositorio simulado y no crean ni cambian datos reales.

Web release compilado correctamente en `build/web-history-review`. El ensayo
Wasm conserva advertencias de dependencias existentes; la compilación JavaScript
terminó correctamente.

Revisión nativa real: usuario inició sesión directamente en la nueva compilación
del worktree. Comprobados catálogo con imágenes, costes y existencias; carrito
vacío con totales y acciones; filtro lateral blanco; dos órdenes existentes y
su detalle. Suplidores carga su estado vacío; formulario cuadrado abierto y
cancelado sin guardar. No se aprobaron, enviaron, recibieron ni crearon órdenes,
productos, suplidores o facturas. App dejada abierta en Suplidores.
La comprobación nativa fue parcial; las cinco vistas y sus formularios se
cubrieron con pruebas visuales automatizadas. No se realizó E2E web real.

Validación adicional Linux: las mismas 48 pruebas aprobadas. Referencias visuales
Linux guardadas separadas de las de Windows. `git diff --check` sin incidencias.

## Segunda pasada de Compras y avisos de Ventas — 13/11/2026

- Se conserva `detalleVisuales` y todo el trabajo anterior. Sin commit, merge,
  despliegue ni cambios de datos de producción.
- Las cinco rutas de Compras usan ahora la flecha y el mecanismo compartido de
  regreso. Se retiró el drawer local; navegación y destino de respaldo conservados.
- Nueva compra: switch de opciones adicionales en el encabezado de la orden,
  con tooltip y semántica; mantiene sus campos, valores y guardado del borrador.
  Filas blancas más compactas con imagen, cantidades, coste, importe y acciones.
- Lista de compra: detalle de 340–460 px, filas blancas con separadores discretos
  y resumen más fino; total destacado en azul. No se modificaron cálculos.
- Suplidores: botón central Nuevo suplidor cuando la lista está vacía y acceso
  con icono en el AppBar, tanto móvil como escritorio.
- Por comprar: eliminados los bordes de cada tarjeta y usados separadores suaves.
  Agregar conserva la cantidad sugerida, guarda el borrador local antes de salir y
  confirma con aviso superior. Acceso Ver nueva compra en el AppBar. Un error de
  validación de cantidad no se informa como agregado correctamente.
- Facturas: se conserva selección con bytes y envío multipart existente. La
  validación mantiene abierto el formulario cuando falta suplidor/archivo. Límite
  de 20 MB coherente con el servidor, protección de contexto desmontado y bloqueo
  de nueva subida mientras se procesa. No se subieron documentos reales.
- Avisos: sustituidas las barras inferiores de impresión, WhatsApp, acciones de
  cotizaciones y reglas por el aviso superior existente. El fallback compartido
  de enlaces también usa AppFeedback arriba. Los avisos previos de Cash ya estaban
  arriba; no se alteraron las confirmaciones ni los permisos.
- PDF: todas las entradas de compra siguen usando buildPurchaseOrderPdf, incluido
  el documento compartido. Se conservan los componentes/paleta de pdf_kit, iguales
  al estilo de factura y cotización. Encabezados de tabla y total alineados al
  lenguaje visual común. Un borrador guardado conserva su número de orden y muestra
  Estado: Borrador. Se compararon imágenes renderizadas de los tres PDF con datos
  ficticios; sin recortes ni superposiciones. No se modificó el PDF del proveedor
  que el cliente adjunta en Facturas.

Verificaciones: análisis de los siete grupos de archivos y pruebas sin incidencias.
101 pruebas Windows aprobadas (Compras, avisos, PDF fiscal e historiales); 41 de
Compras en Linux aprobadas, con referencias por plataforma actualizadas. Además
se ejecutó el render de tres documentos de muestra en .dart_tool, fuera de los
tests versionados. La prueba PDF extrae texto para comprobar número, estado,
suplidor y total. El extractor reutiliza la dependencia transitiva existente del
visor, siguiendo el patrón de los demás tests PDF del proyecto.

La subida se verificó mediante selector/repo simulados y contrato multipart
interceptado, sin conexión a un servidor ni persistencia de facturas reales.
Windows debug y web release compilados correctamente. Web mantiene los avisos
previos del ensayo Wasm sin impedir la salida JavaScript.

Revisión nativa: la nueva app restauró la sesión y el borrador de cinco productos.
Verificados encabezado con switch, flecha Regresar y filas compactas con imágenes.
El PDF real del borrador abrió y renderizó correctamente con logo, empresa y cinco
líneas; se cerró sin compartir, guardar orden ni modificar registros de producción.
Se detectó texto recortado en Generar orden a ancho mediano: la franja pasa al
formato de iconos secundarios y acción principal ancha por debajo de 520 px.

Después de ese ajuste final: las 21 pruebas de diseño de Compras volvieron a
pasar, análisis limpio y recompilaciones Windows/web correctas. Se abrió la
compilación final y se confirmó Generar orden completo a ancho mediano, con
los cinco artículos y RD$ 1,889.65 conservados. La app queda abierta en Nueva
compra; no se pulsaron Borrador, Generar orden, Enviar ni Recibir.

Comandos ejecutados desde apps/fulltech_app:

```text
flutter analyze --no-pub lib/modules/compras lib/modules/cotizaciones/cotizaciones_screen.dart lib/modules/cotizaciones/cotizaciones_historial_screen.dart lib/modules/cotizaciones/ai/presentation/widgets/quotation_rule_detail_sheet.dart lib/modules/ventas/tpv_sales_history_screen.dart lib/core/utils/safe_url_launcher.dart test/modules/compras
Sin incidencias.
flutter test --no-pub --update-goldens --dart-define=API_BASE_URL=http://127.0.0.1:1 test/modules/compras test/core/utils/app_feedback_toast_test.dart test/modules/documentos/pdf_fiscal_templates_test.dart test/modules/ventas/related_history_design_test.dart test/modules/ventas/sales_history_design_test.dart
101 pruebas aprobadas.
flutter test --no-pub --update-goldens --dart-define=API_BASE_URL=http://127.0.0.1:1 test/modules/compras/purchases_design_test.dart
21 pruebas aprobadas después del ajuste final.
flutter build windows --debug --no-pub
Compilación correcta (destino API pasado por dart-define, sin modificar .env).
flutter build web --release --no-pub --output=build/web-history-review
Compilación correcta.
```

Herramientas: terminal/git, apply_patch, Flutter/Dart, Docker, revisión de imágenes,
render PDF con PyMuPDF y Computer Use. Sin Figma, Context7 ni Playwright.
Limitación: no se realizó E2E web ni una subida real contra el backend. La subida
no recibe una certificación de producción a partir de estas pruebas simuladas.

## Reportes: presentación y exploración de rentabilidad — 2026-11-13

- Contenido centrado con ancho máximo de 1360 px; indicadores financieros al inicio y secciones adaptables para ventas, cobros, utilidad, comparativas, categorías, productos, clientes y ventas recientes.
- Botones y campos cuadrados, calendario blanco con lápiz/calendario suministrados, y selector de categorías con búsqueda sobre la lista real de la empresa. Iconos originales copiados desde la carpeta del escritorio, sin modificar las imágenes.
- Gráficos con consulta por toque, cursor y teclado, fechas e importes exactos, escala con cero y valores negativos. Cobros permite seleccionar métodos desde su leyenda; importes negativos usan gráfico con signo.
- Conservados los modelos, consultas, carga diferida, cálculos, devoluciones, proyección por categoría, PDF y límites de empresa. Comparación textual con la versión previa confirmó intactos esos bloques; no se modificó backend ni configuración persistente.

Verificación ejecutada:

```text
flutter analyze --no-pub lib/features/reports lib/core/widgets/provided_action_icon.dart test/features/reports test/modules/ventas/reports_models_test.dart
Sin incidencias.
flutter test --no-pub --update-goldens --dart-define=API_BASE_URL=http://127.0.0.1:1 test/features/reports test/modules/ventas/reports_models_test.dart
97 pruebas aprobadas en Windows y 97 en Linux (Flutter 3.41.6, Docker).
flutter build windows --debug --no-pub
Compilación correcta con destino API explícito, sin modificar .env.
flutter build web --release --no-pub --output=build/web-history-review
Compilación JavaScript correcta; advertencias existentes del ensayo Wasm en dependencias.
```

Capturas automatizadas a 390, 1024, 1920 y 2560 px, incluyendo texto al 115%, estados vacíos, secciones inferiores, categorías y calendario. Pruebas de selección real de filtros, intervalos y valores de gráficos con repositorio simulado. Revisión nativa de la compilación exacta de `detalleVisuales`: sesión conservada, cifras del año, selector de categorías y calendario en español. La app quedó abierta en Reportes. Sin cambios de registros, despliegue, merge ni commit. No se ejecutó E2E visual en navegador ni una nueva exportación PDF real en esta tarea.

## Afinado de Reportes y panel PDF de Compras — 2026-11-14

- Cabecera de Reportes fuera del contenedor limitado: ocupa todo el ancho desde el borde superior. El contenido mantiene su máximo de 1360 px y centrado, con bordes de tarjetas más suaves. Se conservan filtros, cifras y gráficos.
- Las vistas PDF de órdenes y borradores de Compras reutilizan `showPdfPreviewPanel`, `PdfPreviewPanelHeader` y `PdfPreviewStage`, igual que facturas y cotizaciones: entrada desde la izquierda, todo el alto, 50% de ancho en escritorio, mínimo legible y ancho completo en móvil. Se conservan impresión, descarga y compartir mediante el menú existente, incluidos permisos y guardado al compartir. No se modificó la generación del documento ni sus importes.
- Prueba integrada abre el PDF desde Lista de compra, comprueba posición (0,0), tamaño 800×900 en ventana 1600×900 y cierre conservando la lista. El rasterizador nativo no se certifica mediante widget tests. Las pruebas compartidas verifican también la adaptación a ventanas estrechas.
- Análisis estático de las áreas modificadas sin incidencias. Suite final de Reportes, modelos, diseño de Compras, generación PDF y panel compartido: 136 pruebas aprobadas en Windows y 136 en Linux (Docker, Flutter 3.41.6). Compilaciones Windows debug y web JavaScript release correctas; advertencias previas de compatibilidad Wasm en dependencias.
- Compilación de `detalleVisuales` abierta en Windows con la sesión conservada. Revisión visual del nuevo Reportes mediante capturas automatizadas a 390/1024/1920/2560 px. La revisión manual se interrumpió porque Computer Use devolvió `unknown screenshotId` y `helper already has an active request`, incluso tras recuperar su sesión. No se afirma una comprobación manual completa del PDF ni E2E de navegador. Sin cambios de registros, deploy, merge o commit.

## PDF de ventas y rentabilidad — 2026-11-14

- La descarga de Reportes pasa la configuración de la empresa autenticada al generador existente. Cabecera con nombre, logo, RNC, dirección, teléfono y web cuando están configurados; no se incorporan claves, datos del representante ni campos ajenos al documento.
- Título «Reporte de ventas y rentabilidad», Manrope incrustada con acentos, azul corporativo del kit PDF existente, resumen de nueve indicadores, desglose bruta/gastos/neta, ranking visual de cinco categorías y tablas de categorías y ventas con importes alineados a la derecha, filas alternadas y encabezados repetidos.
- Se conserva la semántica de ventas/devoluciones y los indicadores recibidos. El documento incluye todas las ventas disponibles en lugar del límite anterior de 30; distingue el conteo agregado del detalle disponible. No se recalculan los totales a partir del detalle ni de la suma de categorías.
- Vista previa local recreada con los ocho renglones de categorías y las 30 ventas presentes en el PDF adjunto. El adjunto original indica 113 registros, pero contiene solo 30: no se inventaron las 83 filas ausentes. La vista previa conserva nombres, fechas e importes y usa el nombre de empresa ya observado en FullPOS; omite RNC/dirección/teléfono no presentes en el adjunto. La descarga real usa los campos configurados.
- Verificación: 100 pruebas de Reportes/modelos/PDF aprobadas, incluyendo empresa, acentos, pérdida, devolución parcial, 80 registros, ausencia de datos de empresa y exclusión de una clave ficticia. Análisis estático sin incidencias. Renderizado con PyMuPDF y revisión visual de las tres páginas de la vista previa y de cabecera/continuación con nombres largos (seis páginas). PDF de vista previa: `output/pdf/reporte_ventas_20260101_20261114.pdf`. No se modifican consultas, backend ni datos del negocio. Sin deploy/merge/commit.
- Compilaciones Windows debug y web JavaScript release correctas; se mantienen las advertencias previas del ensayo Wasm de dependencias. App nativa actualizada abierta desde el ejecutable de `detalleVisuales`, sesión conservada. La validación del PDF se hizo mediante generación local, extracción y renderizado; no se afirma una descarga E2E en navegador ni desde el botón de la app en esta tarea.
