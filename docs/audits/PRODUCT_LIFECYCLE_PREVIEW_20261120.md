# Galería Flutter para aprobación visual

## Ajustes visuales solicitados — 21 de noviembre de 2026

Excepción de diseño aprobada por el propietario para productos: los cuadros del
ciclo de vida, confirmaciones y resultados usan esquinas rectas. No se cambia
el tema de diálogos de otros módulos. Los tres PNG entregados se incluyen sin
alterar en `assets/image/product_{filter,delete,add}.png`.

- Catálogo: iconos suministrados, filtro rectangular de 48 px como el buscador.
- Crear/editar: panel algo más ancho, margen derecho en categoría y ajuste de
  stock rectangular.
- Archivados: cuadro de hasta 820 px de ancho y 640 px de contenido alto,
  limitado por el espacio disponible; búsqueda rectangular separada de la lista.
- Avisos del ciclo de vida: párrafo compacto con el estilo compartido,
  a 12 px del borde superior derecho, respetando la zona segura. Esta ubicación
  corrige la indicación anterior por aclaración expresa del propietario.
  Entrada de 220 ms; respeta la preferencia de reducir movimiento.

Los avisos generales de AppFeedback también usan párrafo compacto arriba a la
derecha. Se ocultan identificadores técnicos en los avisos y en nombres/detalles
visibles de productos, sin cambiar los datos originales. Archivados no usa el ID
como código comercial; conserva referencias como AUD-001 y códigos de barras.
La galería conserva los 39 números y retira los nombres técnicos de sus rutas.

La corrección de ubicación y texto pasó 184 pruebas de Productos, avisos y
login, análisis focalizado sin incidencias y una ejecución real en Windows con
API/SQLite locales. Incluye comprobación de esquina superior a 12 px, ocultación
de IDs en detalles/archivados y aviso, y acción Configuración operativa. Se
retiraron las barras inferiores de importar/exportar/categorías/permisos de
imagen en Productos. Las 78 capturas web verifican móvil y escritorio.
Logs: `.uat/product-lifecycle/top-notices-*`. No se cambian datos persistidos,
reglas financieras ni permisos. El preview se recompila con esta corrección.

Comprobación de esta revisión: 145 pruebas de interfaz aprobadas, incluidas
las 39 vistas en 390×844 y 1280×900, radios de los diálogos, iconos, alturas y
posición de avisos. Las comprobaciones previas de integridad financiera son
independientes de esta revisión visual. No se despliega ni modifica producción.

Verificación final: análisis sin incidencias; 7 pruebas del catálogo aprobadas
tras actualizar las referencias visuales; 81 pruebas de la galería repetidas
después del ajuste de altura final, aprobadas. La revisión web generó 78 capturas
de las 39 vistas, sin llamadas a API ni desbordamiento horizontal del documento.
Evidencia: `.uat/product-lifecycle/design-evidence/result.json` y sus PNG.

Abrir **http://127.0.0.1:4493/** en el equipo de desarrollo.
La galería contiene 39 vistas numeradas y usa los widgets del cliente real.
Los datos son ficticios y las llamadas al servidor están bloqueadas. Los botones
simulan sus resultados; esta galería no demuestra por sí sola integridad financiera.
Esa parte se verifica separadamente con API/PostgreSQL y pruebas nativas.

También se puede enlazar una vista: `http://127.0.0.1:4493/?case=initial`.

| Grupo | Casos |
| --- | --- |
| Pantallas existentes | `catalog`, `create`, `edit`, `stock` |
| Estado y elegibilidad | `zero`, `initial`, `history`, `legacy`, `inconsistent`, `archived`, `annulled`, `identity`, `nonadmin`, `disabled` |
| Carga y acceso | `loading`, `offline`, `forbidden`, `missing` |
| Rechazo al confirmar | `version`, `plan`, `pending`, `uncertain` — pulsar la acción y confirmar para ver el aviso |
| Archivados | `archives`, `empty`, `pages`, `archives-loading`, `archives-error` |
| Confirmaciones | `confirm-archive`, `confirm-restore`, `confirm-delete`, `confirm-annul` |
| Selección múltiple | `bulk-archive`, `bulk-delete`, `results` |
| Notificaciones | `notice-archive`, `notice-restore`, `notice-delete`, `notice-annul`, `notice-refresh` |

Cada cuadro permite cancelar/cerrar. El estado incierto retira las acciones hasta
comprobar el estado nuevamente. Un fallo de archivados muestra Reintentar, no
un mensaje de lista vacía. Las confirmaciones usan botones cuadrados y una barra
de acciones adaptable; no se cambia el diálogo compartido de otros módulos.

Para solicitar un cambio basta indicar el número de la vista, el ancho aproximado
y el texto/botón que debe ajustarse. El propietario aprobó visualmente la galería
el 21 de noviembre de 2026, después del commit `c4bfd1d5`. Esta aprobación cierra
la revisión visual; no constituye autorización de despliegue en producción.

## Reproducir

Desde `apps/fulltech_app`, compilar el punto de entrada de revisión con
`flutter build web --debug --no-pub --target=test/preview/product_lifecycle_design_preview.dart`
y `--output` **absoluto** hacia `.uat/product-lifecycle/design-web`.
Desde la raíz, ejecutar `node scripts/uat/preview-product-design.cjs`.
No publicar esta compilación ni incluir su entrada de prueba en una release.

`product_lifecycle_design_test.dart` comprueba las vistas en móvil y escritorio.
`scripts/uat/product-design-web.cjs` captura ambas medidas y comprueba que no
se envíen solicitudes a las APIs locales. Evidencia en `.uat/product-lifecycle/design-evidence`.
