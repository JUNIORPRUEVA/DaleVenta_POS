# Cierre TEST y previsualización fiscal —2026-11-14

## Alcance autorizado

El propietario aprobó corregir numeración TEST, registro verificado de DOSA,
pruebas E31/E34 desde el software cuando sea posible, regresión de venta Normal
y previsualización PDF. Producción fiscal permanece bloqueada. El propietario
conserva merge y Deploy; esta autorización de TEST no activa producción.

Rama aislada: `agent/ecf-test-close-20261114`, basada en el merge desplegado
`8fa5eba6cc2f4b7a7be6f51c3ff8d576b15c937c`. Otros worktrees no se modificaron.

## Hallazgos confirmados

- FULLTECH conserva certificación y credenciales propias; está en SANDBOX,
  con productionEnabled=false. Sólo hay rangos/autorizaciones PRODUCTION.
  Las pruebas históricas clasificadas mantienen consumidos E31 hasta2 y E34
  hasta1; los siguientes mínimos revisados son3 y2. No se deben reutilizar.
- El registrador síncrono exigía una bandera global apagada incluso en TEST.
  Los originales quedaban en revisión y no podían iniciar nuevas E34.
- La pantalla daba por terminada la configuración sólo por certificación,
  ocultando el formulario incluso sin disponibilidad fiscal real.
- El PDF TEST descargado tiene datos fiscales y QR legible. La vista web en
  blanco carecía de PDF.js, requerido por Syncfusion29.2.11.

## Correcciones

SANDBOX autorizado puede registrar un HTTP200 aceptado/correlacionado bajo el
contrato existente, manteniendo todas las pruebas de recibo, hashes, identidad,
ambiente, e-NCF, secuencia consumida y sello oficial. Producción continúa
requiriendo ambas banderas y la autorización propia de empresa. El kill switch
también bloquea el registro. No se promueven documentos históricos ni se crea
una ruta para importar o aprobar evidencia del cliente.

La pantalla de cierre usa posReady del backend. Sin disponibilidad conserva
el formulario existente de numeración; no exige repetir la postulación.
Después de guardar actualiza los proveedores compartidos de capacidades/rangos.
Una frontera TEST sólo se toma de la respuesta409 específica del servidor,
dentro del rango declarado. Se requiere otra acción explícita del usuario:
no hay reintento automático, modificación de autorización ni reinicio de contador.
La segunda escritura se cancela si el formulario se desmonta o cambia de
ambiente después de declarar. Se conserva la acción existente de activación por
empresa cuando el backend la permite, sin exigir una etapa TEST manual a nuevos
clientes ni modificar las compuertas globales.

El visor usa biblioteca y worker PDF.js4.10.38 locales, con licencia y hashes
conservados. El bootstrap documentado de Flutter inicializa la biblioteca antes
de Dart, con espera máxima de8s y preservando el worker de la PWA. Si falla la
vista, conserva las acciones de descarga y muestra un error. No cambia los
transportes de impresora, las ventas normales ni el contenido fiscal del PDF.

Referencias primarias: [Syncfusion29.2.11](https://pub.dev/packages/syncfusion_flutter_pdfviewer/versions/29.2.11),
[inicialización Flutter](https://docs.flutter.dev/platform-integration/web/initialization).
Se contrastó el bootstrap contra Flutter3.41.6 instalado. Context7 y Playwright
MCP no están expuestos en esta sesión; se usó documentación primaria y
Playwright local para el motor PDF.

## Validaciones realizadas

| Comando / comprobación | Resultado |
| --- | --- |
| npm ci | Instalación PASS;11 avisos en el árbol completo; no se ejecutó audit fix |
| npm audit --omit=dev --json |PASS,0 vulnerabilidades en dependencias de producción |
| npm run api:build | PASS, Prisma5.22 + TypeScript |
| npx prisma validate | PASS |
| npm --workspace apps/api test -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-confirmed-outcome.spec.ts |8/8 PASS |
| npm --workspace apps/api run test:e2e -- --runInBand --forceExit --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts |26/26 PASS, sólo HTTP local y bases sintéticas propias |
| npm --workspace apps/api run test:integration -- --runInBand --runTestsByPath [seis suites fiscales documentadas abajo] |53/53 PASS, PostgreSQL local permitido |
| npm --workspace apps/api test -- --runInBand |3328 PASS,101 omitidas por compuertas; código0; aviso de handles abiertos documentado |
| flutter analyze --no-pub |PASS, sin incidencias |
| flutter test --no-pub test/features/ecf test/core/printing test/modules/ventas test/core/widgets/pdf_preview_panel_test.dart |828/828 PASS |
| flutter test --no-pub test/features/ecf/ecf_dgii_habilitation_page_test.dart test/features/ecf/ecf_sequence_range_section_test.dart test/features/ecf/ecf_production_activation_action_test.dart |71/71 PASS tras las protecciones finales de sesión/ambiente y el acceso a activación existente |
| flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn [defines UAT local] |PASS, código final,68–80s; no es un artefacto productivo |
| node [ejecutor privado]/pdf-browser-qa.cjs |PASS: PDF real TEST renderizado a1280/390, worker cargado, sólo peticiones loopback,0 errores de página |
| docker run --rm --entrypoint nginx [imagen aprobada y nginx.conf de esta rama] -t |PASS, sintaxis del servidor y módulos existentes |

Las seis suites PostgreSQL: sales-ecf-atomic, ecf-pos-readiness,
ecf-legacy-test-classification, ecf-environment-isolation, ecf-e34-emission y
sales-return-ecf-credit. Se usó el contenedor propio fullpos_ecf_finish_20261112,
base efímera permitida en55500; el HTTP usa su base nueva propia en55503 y
crea/elimina sólo bases con su prefijo de ensayo. No se usó un clon productivo.

Los primeros intentos detectaron configuración local incompleta: compuerta de
red del ensayo HTTP, credenciales locales no disponibles en variables Docker y
asset.env ausente del worktree nuevo. Se corrigió el entorno sin relajar guardas.
La prueba Normal omitía originCashSessionId; ahora usa la sesión real de su
fixture, conservando la expectativa ECF_NORMAL_SALES_DISABLED. El ensayo de PDF
inválido necesitó drenar el callback500ms del visor en el reloj de prueba.
También se revisaron visualmente los PNG del formulario TEST a390/1280 y del
motor PDF local. La evidencia del motor no se presenta como validación de la PWA
productiva corregida; esa aceptación aún requiere su despliegue.

## Pendiente de aceptación completa

Publicación/CI, imágenes
inmutables y acción de integración/despliegue del propietario. Después:

1. Verificar ambas compuertas productivas apagadas y empresa SANDBOX.
2. Registrar sólo la numeración TEST confirmada por Alejandro: permiso1–10000000,
   vencimiento31/12/2028; rangos operativos desde los mínimos no consumidos.
3. Preparar un borrador MANUAL de ensayo sin venta comercial, caja o inventario;
   enviar desde la PWA cuando sea posible y acreditar el aceptado con una E34.
4. Verificar documento, QR/consulta TEST, un único envío lógico, reserva aplicada
   y persistencia. Menos de10 ensayos por tipo. No reescribir revisiones antiguas.

No se han enviado comprobantes nuevos, modificado datos compartidos, cambiado
banderas globales, ejecutado migraciones compartidas ni desplegado este cambio.
NO-GO para declarar cerrada la aceptación externa o activar emisión productiva.
