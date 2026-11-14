# Cierre TEST y PDF — preparación de entrega

Estado: los cuatro controles del último commit, las dos publicaciones finales,
la descarga real por digest y la aceptación local de ambos artefactos pasaron.
No desplegar las imágenes del commit anterior a1885097. Ningún despliegue está
autorizado por este documento.

## Fuente y controles

- PR #42: https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/42.
- Fuente congelada: 3217f0cd14cecb97b5c20f146812e0cd5df7d8ec.
- CI exacto: https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43606789878.
- Constructor final: https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43607017565.
- CI final: análisis sin incidencias y 2247 pruebas Flutter PASS / 16 omisiones
  por compuertas; API/security, sitio público y actualizador Windows PASS.
- La rama de preparación conserva su nombre inicial
  agent/ecf-test-images-a1885097; el checkout, las etiquetas y las imágenes
  toman exclusivamente la fuente 3217f0cd, no el HEAD de esa rama.
- Una preparación intermedia falló porque conservaba el checkout anterior;
  la comparación de identidad bloqueó el trabajo antes de construir/publicar.
  Se corrigió la referencia sin relajar la comprobación.

## Imágenes inmutables finales

Ambas linux/amd64; fuente 3217f0cd verificada por checkout, CI y etiqueta OCI.
El constructor probó el arranque Nginx con proxy real, MIME de los tres módulos,
hashes de biblioteca/worker y 404 antes de publicar la PWA.

Backend:

```text
ghcr.io/juniorprueva/fullpos-cloud-api@sha256:4e6fb33c823b8f93978da3b3a3e0ef17ff0a8d22e168841986295aab7c4990af
```

PWA:

```text
ghcr.io/juniorprueva/fullpos-cloud-web@sha256:542cc3d8f94d9c900e11a4928465e712307554efd851e508039f632a736f230b
```

## Evidencia local adicional

Además de los resultados de docs/ecf/ECF_TEST_CLOSURE_2026-11-14.md:

- El visor Flutter real se compiló en un arnés privado y mostró el PDF TEST
  existente a 1280/390. PDF.js 4.10.38, un documento cargado, páginas renderizadas,
  cero fallos del motor y cero errores de página en cada tamaño. Capturas
  inspeccionadas: datos fiscales y QR visibles. Esto no es una nueva emisión.
- El arranque completo de la PWA dejó PDF.js listo antes del primer frame.
- Se descargó E340000000001.pdf desde la PWA abierta, 8648 bytes,
  SHA256: 982e70a34aa1b6016c1cf922c312d874c4cb020d4146546457863bf2bd07d718.
  Una página con número, e-NCF original/fecha/motivo, emisor, ITBIS/total y sello
  TEST; QR decodificado a la consulta oficial TEST para esa E34. Se reprodujo
  la vista en blanco de la versión desplegada y se dejó la PWA en Comprobantes.
  Fue lectura/descarga de un documento existente, sin impresión física, envío
  ni cambios en el estado fiscal. Los cinco documentos y contadores se conservan.
- Formulario TEST y cierre conjunto revisados a 390/1280, sin desbordamiento.
- Proxy original: módulo 200 application/octet-stream y archivo inexistente 200
  HTML. Proxy corregido: módulo 200 application/javascript, caché versionada y
  archivo inexistente 404. El motor renderizó el PDF real a través del proxy.
- El smoke combinado pasó 9 grupos con datos sintéticos: registro/login,
  permisos, handoff de un solo uso, onboarding, rutas / 16 assets, PWA y módulos
  PDF. Ese ensayo preliminar usó la imagen a188 con el entrypoint corregido
  montado. Después se repitieron los 9 grupos con ambas imágenes finales 3217,
  sin montajes ni sustituciones. Se verificaron las etiquetas OCI/linux/amd64,
  Nginx y el render PDF real a 1280/390 con el worker de la imagen publicada.
- La API final descargada confirmó Node 22.23.4, Nest 11.2.7, Prisma 5.22.0 y
  ausencia de .env raíz, antes de iniciarla contra la base sintética propia.
- La sonda adicional pwa-bootstrap-qa.cjs sobre la imagen publicada llegó a
  verificar PDF.js antes del primer frame, pero terminó con código 1 por su
  aserción global de no solicitar otros orígenes: el build productivo solicita
  connect.facebook.net además de las fuentes. Todas esas conexiones se
  bloquearon en Playwright. Dockerfile.public-web, index.html, Env y la
  analítica no tienen diferencias frente a 8fa; es comportamiento preexistente
  del píxel compilado, ajeno al renderer local. No se relajó esa aserción ni se
  modificó la analítica para ocultarlo. La prueba específica del renderer en
  la imagen final pasó con sólo conexiones loopback y 0 errores de página.
- El preflight PowerShell no se pudo ejecutar por la política local de scripts.
  Una sonda SSH/Python de sólo lectura confirmó API saludable, imágenes
  anteriores activas, migraciones automáticas deshabilitadas y ambas barreras
  productivas cerradas. No se cambió la política local de seguridad.

La evidencia privada está en
C:/Users/pc/.codex/backups/fullpos-ecf-test-close-20261114/.

Comandos finales ejecutados (entorno y base sólo locales):

| Comando | Resultado |
| --- | --- |
| docker pull [cada digest final indicado arriba] |2/2 PASS |
| docker run --rm --network none --entrypoint node [API final] -e [sonda de versiones/ausencia de .env] |PASS |
| PUBLIC_WEB_TEST_URL=[proxy local propio] node website/tests/public-web-smoke.mjs |9 grupos PASS, ambas imágenes finales sin montajes |
| PDF_QA_PROXY_ORIGIN=[proxy local propio] node [ejecutor privado]/pdf-browser-qa.cjs |PASS a 1280/390, PDF real/worker,0 errores |
| docker exec fullpos-ecf-closure-qa-web nginx -t |PASS |
| PWA_QA_ORIGIN=[proxy local propio] node [ejecutor privado]/pwa-bootstrap-qa.cjs |PDF listo antes del frame; comprobación adicional global FAIL por el píxel preexistente descrito arriba |
| git diff 8fa5eba6 HEAD -- Dockerfile.public-web apps/fulltech_app/web/index.html apps/fulltech_app/lib/core/api/env.dart apps/fulltech_app/lib/core/analytics/marketing_analytics.dart |Sin diferencias; no se alteró la analítica |

Los 11 avisos del árbol npm completo son de desarrollo; npm audit --omit=dev
reportó 0. No se ejecutó audit fix ni se cambiaron dependencias en este PR.
Se retiraron los contenedores web/API de ensayo y su red propia; las dos bases
locales se detuvieron y conservaron. No se tocaron contenedores de otros trabajos.

## Protección y siguiente aceptación

El propietario conserva merge y Deploy. Antes de usar los nuevos digests debe
integrar el PR y comprobar que los archivos de construcción de production-main
siguen coincidiendo con la fuente congelada; una integración adicional exige
evaluar de nuevo el artefacto. Mantener RUN_MIGRATIONS=false, seed apagado,
DOSA_PRODUCTION_EMISSION_ENABLED=false y
DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED=false. FULLTECH permanece SANDBOX y no se
modifican credenciales, certificación, rangos productivos ni resultados antiguos.

La fuente actual de EasyPanel sigue apuntando a los digests anteriores. Pulsar
Implementar sin cambiar la fuente volvería a usar el software anterior. Después
del merge/controles y de comprobar la equivalencia del código, el propietario
debe guardar la referencia Docker Image final en backend y pwa; desplegar
primero API, comprobar salud y después PWA. Esta preparación no guardó fuentes
productivas, no ejecutó Deploy ni reinició servicios.

Después del despliegue manual de API y PWA, verificar salud y revisiones; luego
registrar sólo TEST 1–10000000, vencimiento 31/12/2028. Conservar las fronteras consumidas:
E31 mínimo 3, E34 mínimo 2. La declaración conserva el rango confirmado original;
el formulario sólo toma la frontera del servidor tras otro guardado explícito.

La nueva aceptación externa debe emitir un borrador MANUAL sin venta comercial,
caja o inventario, enviar desde la PWA y verificar E31 aceptado antes de E34.
Comprobar correlación, QR/consulta TEST, persistencia, idempotencia y aplicación
única de la reserva. Menos de 10 ensayos por tipo. No está ejecutada todavía.

Conservar los digests anteriores para reversión del software, sin restaurar la
base de datos ni rebobinar contadores:

- API: ghcr.io/juniorprueva/fullpos-cloud-api@sha256:50e6e51217922b48eeefbea6addf34776dc0773e05fa937f5862baa62191e1f6.
- PWA: ghcr.io/juniorprueva/fullpos-cloud-web@sha256:a4841b785239b602869b621ac424fa08d9667af561c3868cc4177a293d434177.

NO-GO para dar por cerrada la aceptación externa o habilitar emisión productiva.
Las correcciones y artefactos están listos para la revisión y la integración
controlada del propietario; no se afirma aceptación de nuevas E31/E34 en la PWA.

## Archivos de aplicación modificados en PR #42

- `.gitattributes`.
- `apps/api/src/ecf/provider/dosa/dosa-confirmed-outcome.spec.ts`.
- `apps/api/src/ecf/provider/dosa/dosa-confirmed-outcome.ts`.
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts`.
- `apps/fulltech_app/docker-entrypoint.sh`.
- `apps/fulltech_app/lib/core/widgets/pdf_preview_panel.dart`.
- `apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart`.
- `apps/fulltech_app/lib/features/ecf/ui/ecf_dgii_habilitation_page.dart`.
- `apps/fulltech_app/lib/features/ecf/ui/flow/ecf_completed_view.dart`.
- `apps/fulltech_app/lib/features/ecf/ui/flow/ecf_sequence_range_section.dart`.
- `apps/fulltech_app/nginx.conf`.
- `apps/fulltech_app/test/core/widgets/pdf_preview_panel_test.dart`.
- `apps/fulltech_app/test/features/ecf/ecf_completed_view_test.dart`.
- `apps/fulltech_app/test/features/ecf/ecf_dgii_habilitation_page_test.dart`.
- `apps/fulltech_app/test/features/ecf/ecf_repository_test.dart`.
- `apps/fulltech_app/test/features/ecf/ecf_sequence_range_section_test.dart`.
- `apps/fulltech_app/web/flutter_bootstrap.js`.
- `apps/fulltech_app/web/pdfjs/4.10.38/LICENSE`.
- `apps/fulltech_app/web/pdfjs/4.10.38/init.mjs`.
- `apps/fulltech_app/web/pdfjs/4.10.38/pdf.min.mjs`.
- `apps/fulltech_app/web/pdfjs/4.10.38/pdf.worker.min.mjs`.
- `apps/fulltech_app/web/pdfjs/README.md`.
- `docs/ARCHITECTURE.md`.
- `docs/ENVIRONMENTS.md`.
- `docs/EXECUTION_STATE.md`.
- `docs/PRODUCT_SPEC.md`.
- `docs/RELEASE.md`.
- `docs/ecf/ECF_TEST_CLOSURE_2026-11-14.md`.
- `website/tests/public-web-smoke.mjs`.

La preparación aislada añade además este informe y
`.github/workflows/ecf-test-images-a1885097.yml`; no se integra esa rama en
production-main ni se construye desde su HEAD.
