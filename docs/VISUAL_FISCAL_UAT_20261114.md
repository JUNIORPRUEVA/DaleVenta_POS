# Aceptación aislada de la integración visual/fiscal — PR45

## Alcance y seguridad

Pruebas del conjunto integrado en `C:/src/fullpos-integration-20261114`, rama
`agent/integrate-visual-fiscal-20261114`. Los commits iniciales `5bbc36b7` y
`385df9f7` se conservan. PR: https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/45.

Se utilizan exclusivamente PostgreSQL desechable en loopback55500, API local
4871 y PWA UAT local4004. Las empresas Alfa/Beta son ficticias; sus usuarios,
ventas, devoluciones y numeraciones son fixtures aisladas. No se accede a
producción, FULLTECH, certificados ni credenciales productivas. Los clientes de
navegador bloquean destinos externos y service workers. No se realizan llamadas
de emisión a DOSA/DGII, merge, deploy ni cambios productivos.

## Resultados comprobados

- API real, registro/acceso/configuración/ventas:17 verificaciones PASS. Una
  venta NORMAL conserva base100+ITBIS18=118 con e-CF activado, sin comprobante.
  Una E31 sin preparación fiscal responde409 y no aumenta las ventas guardadas.
  Beta no obtiene ventas ni configuración fiscal de Alfa.
- Proyecciones HTTP de impresión:5 PASS, incluyendo E31/E34, devolución parcial,
  referencia al comprobante original y rechazo de acceso desde otra empresa.
- Devoluciones por HTTP:6 PASS. La devolución normal conserva ITBIS; repetir la
  solicitud no duplica el movimiento. La devolución electrónica incompleta
  informa `ECF_LINE_CLASSIFICATION_UNCONFIRMED`; el reintento fiscal no vuelve a
  devolver dinero. Intentos de emisión externa:0.
- PWA real en Chrome headless independiente: acceso y navegación por empresa,
  módulo fiscal, comprobantes, historial, configuración y detalle E34. Capturas
  de escritorio1440px y móvil390px. No se controla el navegador del propietario.
- Sin conexión: al intentar emitir aparece el aviso pequeño superior derecho
  «Sin conexión / La factura electrónica requiere internet.»; desaparece a los
  4.8s. Ninguna petición fiscal POST sale durante el intento.
- E34 exportada por la propia PWA: PDF de una página, base/impuesto/total,
  numeración, referencia E31, información fiscal y leyenda TEST. El QR se
  decodificó desde una imagen del PDF renderizada a288dpi y coincide con la E34.

Los estados aceptados E31/E34 fueron insertados como fixtures sintéticas para
comprobar visualización y documentos. No son una certificación, aceptación ni
emisión externa efectiva. El caso de devolución HTTP anterior comprueba el
estado pendiente seguro; la emisión E34 satisfactoria simulada queda cubierta
por las15 regresiones PostgreSQL del informe principal.

## Hallazgo y corrección posterior al candidato inicial

La exportación PDF del historial para una venta ordinaria falla en Web antes de
construir el documento: `PrinterSettingsRepository.getOrCreate()` solicita SQLite
nativo, no disponible en navegador. Se reprodujo con la PWA real; el PDF E34
independiente usa otra ruta y sí funciona.

Corrección mínima: Web utiliza el perfil estándar de impresión del navegador
sin consultar SQLite ni heredar encabezados globales de otra empresa. El flujo
nativo y la identidad fiscal de la venta no cambian. Se añade una regresión en
Chrome que genera un PDF normal con ITBIS y verifica que no hereda un RNC ajeno;
GitHub Actions debe ejecutar esa prueba además de la suite habitual.

Análisis posterior PASS: `flutter analyze --no-pub` (135.7s). Regresión nativa de
ajustes/impresión/PDF:228 PASS,1 omisión explícita correspondiente a la prueba
exclusiva de navegador. La comprobación Chrome local por `flutter test` está
bloqueada por el servidor CanvasKit del SDK Windows3.41.6 (404 de archivos
existentes por separadores de ruta); no se cambió el SDK ni se cuenta como PASS.
La prueba Chrome debe comprobarse en el runner Linux del nuevo commit del PR.

La imagen combinada UAT se reconstruyó correctamente con la corrección. Se
reemplazó únicamente el contenedor Web desechable identificado por la etiqueta
de esta tarea, conservando el anterior detenido. No es un despliegue productivo.
Imagen local de validación: `fullpos-local-uat:pr45-web-pdf-workingtree`, image id
`a6c1d7660d6d31ec96d68c7dad732a35bd50fe92b6a9afef721cde08294c8cae`.
Su etiqueta de revisión heredada385df9f7 no identifica el working tree corregido;
no debe utilizarse para publicar ni como prueba de correspondencia a ese commit.

Aceptación posterior del PDF real desde Historial:

- NORMAL: descarga PASS, una página, base100/ITBIS18/total118, sin QR ni e-NCF;
  cero consultas a `/api/ecf/sales/:id/print` durante la generación.
- E31 sintética: descarga PASS, una consulta fiscal de impresión, una página,
  total118, e-NCF E310000000101, vencimiento31/12/2035 de la fixture, QR decodificado
  correspondiente y leyenda TEST. Se accede a la venta devuelta mediante el
  filtro Todas; no se modifica su devolución ni su documento histórico.
- Los tres PDFs (NORMAL/E31/E34) se renderizaron, inspeccionaron y verificaron
  por extracción de texto; solo los dos fiscales contienen QR decodificable.
- El intento offline se repitió en la imagen corregida:0 POST fiscales.

## Límites y observaciones

- Las pruebas con instrumentación de semántica no consiguieron accionar el menú
  PDF ni el aviso offline. Se repitieron en el lienzo normal de la aplicación y
  estos recorridos sí se comprobaron. Los intentos fallidos no se cuentan PASS.
- Una carga fría de rutas internas vuelve a cotizaciones durante el arranque
  existente; las capturas usan navegación SPA con sesión iniciada. No se afirma
  compatibilidad de enlaces profundos fríos.
- La tipografía PDF estándar no representa correctamente el separador em-dash
  del nombre de una fixture. No se alteran nombres históricos para ocultarlo.
- En la captura Web del panel Filtros de ventas los textos de los segmentos de
  fecha/estado no se dibujan, aunque el cambio a Todas y la aplicación del filtro
  funcionan. Se registra como detalle visual pendiente; no se amplía aquí el
  rediseño ni se sustituyen las reglas del filtro.
- No se comprueban actualización del service worker, dispositivos Android/iOS,
  instalador Windows, impresoras físicas ni certificación externa en esta UAT.
- La imagen local lleva perfil UAT y no constituye un artefacto productivo.

Evidencia privada (capturas, PDFs, resultados seguros y scripts):
`C:/Users/pc/.codex/backups/fullpos-visual-fiscal-integration-20261114/`.
Las cuentas, tokens y respuestas privadas permanecen fuera de Git.

## Control de publicación

La integración inicial tuvo cuatro controles CI satisfactorios en el commit
`385df9f7` (run43659369390). Esos resultados no validan automáticamente esta
corrección posterior: hay que comprobar el nuevo head y la nueva prueba Chrome.
El propietario mantiene el control del merge. Deploy sigue NO-GO sin autorización
expresa y sin preparar/verificar los artefactos por el procedimiento de release.
