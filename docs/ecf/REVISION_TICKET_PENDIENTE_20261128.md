# Conservación de ajustes de impresión — 28/11/2026

Se publica este trabajo en borrador para conservar todos los ajustes solicitados: encabezado térmico, subtotal fiscal sin duplicación, cantidad legible y tabla compacta de 80 mm. No autoriza merge ni despliegue.

## Verificaciones ejecutadas

- `flutter test --no-pub test/core/printing --reporter compact`: 270 pruebas aprobadas.
- `flutter analyze --no-pub lib/core/printing lib/modules/ventas/utils/sales_pdf_service.dart test/core/printing`: sin problemas.

## Bloqueo fiscal

La versión compacta de 80 mm omite ITBIS y unidad por artículo, también en comprobantes electrónicos. Esto conserva la solicitud visual, pero no recibe aprobación fiscal: debe resolverse la observación de representación impresa electrónica antes de publicar. Las pruebas de diseño no acreditan cumplimiento normativo.

Estado: **NO-GO para merge y producción**. No se han modificado datos, numeraciones, credenciales ni documentos históricos. El video de bienvenida se publica por separado en el PR #59.
