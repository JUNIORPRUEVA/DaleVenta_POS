# Vista previa: web, carga y tres historiales — 15/11/2026

## Alcance

Rama `agent/web-history-polish-20261115`, worktree exclusivo
`C:/src/fullpos-web-history-polish-20261115`, base `deb96f86` de production-main
(PR47 ya fusionado). Cambios locales para revisión del propietario; sin commit,
push, merge, cambios de configuración ni despliegues en esta tarea.

La web presenta una franja separada de la navegación que anuncia facturación
electrónica integrada para empresas de República Dominicana. Los textos de planes,
preguntas, precios, registro, soporte, descargas y pie de página indican únicamente
transferencia bancaria. No se cambiaron los métodos de cobro de las ventas del POS.

Se retiró la antigua portada HTML con logo pequeño y la segunda cubierta de acceso
de Astro. Antes del motor queda un estado mínimo «Iniciando…». El primer fotograma
de Flutter retira esa cubierta y permite ver el SplashScreen existente con el logo
grande y aro animado, incluida su recuperación de errores. No se modificaron la
autenticación, las claves, los tickets de acceso, las sesiones ni sus vencimientos.
La precarga usa ahora el logo realmente utilizado por ese SplashScreen.

Ventas, cotizaciones y créditos limitan el buscador de escritorio a560px,
conservando36px de alto. Los filtros usan esquinas de6px y paneles de hasta380px,
con encabezados compactos y acciones inferiores de40px. Búsqueda, fechas, cajeros,
estado, pagos, selección de documentos y permisos conservan sus reglas.
Los rótulos de segmentos de ventas y la barra fiscal heredan la fuente de la app
en lugar de perder su familia al crear TextStyle parciales. La vista previa
comprueba las etiquetas con fuentes externas bloqueadas.

## Desplazamiento móvil

Las páginas de acceso dejan de desplazar una columna fija de100dvh: en móvil
desplazan el documento, sin bloquear los gestos normales del navegador.
El sitio público conserva el desplazamiento del documento y su overflow horizontal
controlado. No se simulan ocultaciones de Chrome/Safari ni se solicita fullscreen.
La barra nativa pertenece al navegador y su movimiento debe comprobarse en el
teléfono real; una emulación headless no prueba ese comportamiento físico.
La PWA instalada ya tiene su modo standalone independiente del sitio público.
Referencia: [MDN, modos de visualización](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Manifest/Reference/display).

## Vista previa local

- Web: http://127.0.0.1:49975/
- Galería con datos ficticios: http://127.0.0.1:59627/
- Pestañas: Ventas, Cotizaciones, Créditos, Carga y Menú fiscal.

La galería es un entrypoint privado fuera del repositorio, con repositorios y
sesión ficticios. No crea empresas, ventas, créditos ni comprobantes reales.
Solo contiene controles para revisar el diseño; no prueba emisión externa.
Los fallos iniciales de sesión en la galería se corrigieron en su fixture privado,
sin modificar la autenticación del producto. Las capturas de filtros esperan el
final de su animación antes de evaluar opacidad y contraste.

## Validación

Evidencia privada:
`C:/Users/pc/.codex/backups/fullpos-web-history-polish-20261115/`.

- `npm ci --no-audit --no-fund`: PASS,266 paquetes del sitio.
- `npm test` (website):13 PASS, incluida la regresión de primer fotograma.
- `npm run check`:0 errores/0 warnings; un hint preexistente por returnValue.
- `npm run build` (website):14 rutas estáticas generadas, PASS.
- `flutter analyze --no-pub`: PASS,118s en la última ejecución completa.
  `dart analyze` de ventas, filtros de crédito y barra fiscal: PASS tras el ajuste final.
- Compilación web release de la app: PASS,96.8s. Galería con el último rótulo
  móvil «Rango»: PASS,66.7s. No se generó ni publicó una imagen de despliegue.
- Regresión Flutter de ventas, cotizaciones, arranque y panel fiscal:391 PASS.
- Diseño final de historiales en Windows:39 PASS sin actualizar referencias;
  Linux:39 PASS sin actualizar referencias, ambos con el código final.
- Las referencias PNG se regeneran solo para las vistas solicitadas y se
  inspeccionan muestras visuales; no se relajan tolerancias ni se eliminan aserciones.
- Navegador local1440/390: franja, navegación pública, pago por transferencia,
  desplazamiento de registro, tres paneles y SplashScreen revisados:10 escenarios
  PASS,0 excepciones de página. Incluye la barra fiscal con fuentes externas
  bloqueadas y registros ficticios visibles en ambos tamaños. Los selectores
  privados distinguen texto de escritorio de las etiquetas accesibles combinadas
  de las tarjetas móviles. No se modificó el producto para satisfacer el fixture.

Sin modificaciones en apps/api, schema, migraciones, credenciales, rangos,
contadores, documentos históricos ni permisos fiscales. Los worktrees anteriores
no fueron editados. Sin acceso SSH ni escrituras en producción en esta tarea.

## Estado

GO para revisión local: los cambios solicitados están implementados y probados.
Pendiente la revisión del propietario. NO-GO para publicar o desplegar sin esa
revisión. La ocultación física de la barra del teléfono no se puede certificar
con las herramientas headless; sí se verificó el scroll del documento.

Revisión del propietario: aprobada el 2026-11-15 sin cambios solicitados.
GO para publicar mediante un PR nuevo hacia production-main. El despliegue, la
migración de actividad y sus indicadores siguen siendo decisiones separadas que
esta revisión no autoriza.
