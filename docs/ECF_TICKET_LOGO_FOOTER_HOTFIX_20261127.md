# Corrección visual de ticket electrónico y acceso a previews

Base: `ebc9486a6`, último `production-main` consultado el 27/11/2026.
Rama de trabajo: `agent/ecf-ticket-logo-footer-20261127`.
Worktree: `C:/t/fp-ecf-receipt-fix-20261127`.

## Causa y corrección

El proyector térmico conservaba los bytes del logo, pero el encabezado PDF tenía
una rama electrónica que los omitía. Esa rama ahora usa el encabezado común sin
perder la identidad fiscal del documento. En RAW ESC/POS tampoco se rasterizaba
el logo electrónico: se incorpora antes del contenido, con proporción conservada,
máximo 128 puntos y transparencia sobre blanco. Si no hay logo no se inventa uno.

PDF, HTML, RAW y texto heredado colocaban el cierre antes del bloque fiscal. Ahora
el orden es contenido/notas/garantía → sello auténtico y datos de verificación →
agradecimiento y marca del sistema. El contenido, URL, dimensiones y zona libre
del QR se conservan. No se modificaron importes, impuestos, numeración, estados
DGII, certificados ni autorización de emisión.

«Ver pantallas» estaba condicionado a `kDebugMode`. Se retiraron el botón, el
selector modal y el estado de preview de la pantalla operativa, también en debug.
Las vistas de diseño aisladas y sus pruebas permanecen. La navegación real de una
empresa nueva y el expediente de una empresa postulada conservan sus reglas.

## Validación ejecutada

- Análisis Flutter de los cinco archivos de implementación: sin incidencias.
- Pruebas de PDF con/sin logo a 58/80 mm: imagen presente sólo cuando corresponde;
  e-NCF y RNC conservados; código de seguridad antes del agradecimiento.
- HTML: QR y firma preceden al cierre. Texto heredado: mismo orden.
- RAW: raster de logo antes del contenido, raster de QR y firma antes del cierre.
- Pendiente/rechazado: no se inventa sello ni código de seguridad.
- 76 pruebas focalizadas pasadas: regresión del renderer RAW, nuevo caso visual y
  módulo de habilitación, incluidos estados antes/después de postular.
- Regresión completa de impresión y previews aisladas: **247 pruebas pasadas**.
  Una prueba antigua exigía el QR después del agradecimiento; se actualizó al
  nuevo requisito, manteniendo las comprobaciones de sello, zona libre y datos.
- PDF renderizados a PNG e inspeccionados visualmente. Los cuatro QR de PDF
  (58/80 mm, con/sin logo) se decodificaron y coincidieron con la URL de prueba.
- Se reconstruyeron los dos raster de los bytes RAW: logo 128×128 y QR 224×224.
  El QR térmico decodificado coincide con la misma URL, sin consultas a DGII.

Evidencia local ignorada por Git: `.uat/ecf-ticket-hotfix/` y registros
`apps/fulltech_app/ecf-hotfix-*.local.log`. Los ejemplos dicen TEST / SIN VALIDEZ
FISCAL y no corresponden a ventas reales. No se emitieron comprobantes ni se
realizaron operaciones financieras. La impresora física no se utilizó en esta
validación; se comprobó la salida RAW y el PDF generado.

No se publicó ni desplegó. El cambio requiere integrar/publicar la versión
corregida para que llegue a la aplicación instalada de los clientes.
