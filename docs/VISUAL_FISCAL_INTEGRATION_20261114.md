# Integración de detalleVisuales y autoservicio fiscal

Estado: candidato local integrado y validaciones automatizadas finales PASS.
NO-GO para publicación productiva hasta revisión, CI y aceptación autorizadas.
El propietario autorizó después de revisar este candidato crear el commit,
publicar exclusivamente la rama de integración y abrir PR hacia production-main.
Esta autorización no incluye merge ni deploy. Los checks vigentes se consultan
en el PR; los resultados de abajo corresponden a la validación local previa.

## Objetivo y conservación

- Destino revisado: `origin/production-main` en `cbc3eceb` (PR44).
- Worktree propio: `C:/src/fullpos-integration-20261114`.
- Rama propia: `agent/integrate-visual-fiscal-20261114`.
- `detalleVisuales` parte de `cada11f8`,11 commits por detrás del remoto.
  No tiene commits adicionales: sus cambios son archivos pendientes locales.
- Copia verificada del diseño:72 archivos con diferencias lógicas,245 nuevos
  y3 generados con diferencias normalizadas por Git, conservados en copia privada.
- Copia fiscal:55 archivos modificados y77 nuevos.
- También se preservó una copia del checkout original, con14 modificados y92
  nuevos. No se incorporan automáticamente esos cambios ajenos al alcance.
- Backups y manifiestos SHA256 privados:
  `C:/Users/pc/.codex/backups/fullpos-visual-fiscal-integration-20261114/`.
- Los worktrees originales no se modifican, limpian, cambian de rama ni hacen
  stash. No se usa la rama local production-main, cuyo checkout está atrasado
  y contiene cambios pendientes propios.

## Procedimiento

1. Se consultó el índice/historial local del chat `TRABAJANDO DISENO FINALES`
   y el informe `DETALLES_VISUALES_FACTURACION_20261112.md`.
2. Se congelaron los archivos pendientes y se comprobó su hash antes/después.
3. Se creó el worktree desde el remoto vigente, conservando los11 commits.
4. Se aplicó el diseño mediante combinación de tres vías contra sus blobs base.
5. Se resolvieron conflictos del drawer y del historial de ventas conservando
   los accesos visuales y los indicadores/paneles fiscales de producción.
6. Se aplicó después la copia fiscal mediante tres vías, sin conflictos manuales.
7. Los245+77 archivos nuevos se copiaron con verificación SHA256; sin colisiones.
8. Se validan el conjunto integrado y su procedencia antes de preparar revisión.

## Conflictos revisados

- `app_drawer.dart`: conservar entrada visual directa de facturación y estructura
  de grupos; retirar helper pickItems ya sin callers en la nueva distribución.
- `tpv_sales_history_screen.dart`: conservar cliente/cajero y composición visual,
  con EcfSaleHistoryBadge dentro del encabezado de factura y EcfSaleHistoryPanel
  como sliver del detalle. No se descarta el estado fiscal al rediseñar historial.
- `cotizaciones_screen.dart`: combinación automática revisada; mantiene selector
  visual embebido y la fecha E31 derivada de la autorización, con compatibilidad.

## Alcance adicional que ya trae el diseño

No es exclusivamente cosmético: cambia el acceso al registro web desde apps,
routing de registro, avisos de interfaz, enlaces de descarga y generación de
reportes PDF. Se incluyen en las regresiones; no se ocultan como simples estilos.

El alcance visual original está documentado en
`DETALLES_VISUALES_FACTURACION_20261112.md`. El fiscal está en
`ecf/ECF_SELF_SERVICE_HARDENING_2026-11-14.md`, además de las capturas aprobadas
de Empresa y del recorrido fiscal. Ambos conjuntos se incorporan al candidato.
La parte fiscal incluye derivar el vencimiento E31 de la autorización de la
empresa/ambiente, comprobarlo dentro de la asignación transaccional y permitir
la entrada al asistente de una empresa nueva elegible sin exigir una postulación
previa. La inscripción al portal respeta revocaciones/caducidad y no equivale
a autorizar emisiones productivas. No se cambian banderas globales de emisión.

## Validaciones

- Dependencias Flutter resueltas sin actualizar restricciones.
- Dependencias npm instaladas desde lockfile con scripts omitidos; Prisma Client
  se genera expresamente por `npm run api:build`.
- `npm run api:build`: PASS.
- Flutter analyze completo inicial: PASS (215.2s); final: PASS (278.4s).
  Los diez archivos de pruebas auxiliares modificados en la integración también
  se analizaron tras el último ajuste: PASS (48.1s).
- Primera suite Flutter:2399 PASS/9 omitidas/27 fallos. Se identificaron
  expectativas anteriores de constructor, tooltip, textos y tipo de botón,
  referencias del logo/lupa anteriores y dos esperas de SQLite no deterministas.
  Se conservan las aserciones de cierre, persistencia, permisos, estado fiscal,
  ausencia de errores globales y geometría. No se relajan tolerancias visuales.
- Regresión enfocada de esos recorridos:179 PASS. Referencias Windows del logo y
  lupa revisadas visualmente y actualizadas solo en los dos archivos de pruebas.
- Segunda suite completa:2425 PASS/9 omitidas/1 fallo de espera de un aviso de
  caja pendiente de I/O. Se usa ahora el helper acotado existente, manteniendo
  las mismas aserciones. Regresión de caja:19 PASS. Tercera suite completa final:
  **2426 PASS/9 omitidas/0 fallos**, en aproximadamente10min, secuencialmente.
- PostgreSQL dedicado de integración en loopback55500; no reutiliza otra base.
  Las migraciones solo se ensayan en ese contenedor desechable.
- Primera API:3326 PASS/15 fallos/101 omitidas. Los15 fallos estaban en la misma
  fixture de devoluciones: no declaraba vencimiento E31. Se añadió vencimiento
  sintético válido a esa autorización, sin relajar la validación del servicio.
- Regresión PostgreSQL de devoluciones/E34:15 PASS.
- API completa final:3341 PASS/101 omitidas,279 suites PASS/13 omitidas.
- Web pública: instalación,12 pruebas, astro check (0 errores/0 warnings/1 hint)
  y compilación PASS. Cliente Flutter web release UAT: PASS (156.9s); los avisos
  de compatibilidad Wasm pertenecen a dependencias existentes y no impiden JS.
- `sync_api_docker_lock.mjs --check`: PASS (756 paquetes).
- HTTP fiscal:3 suites/44 pruebas PASS, con proveedor simulado y PostgreSQL local.
  Incluye compatibilidad POS anterior, aislamiento y errores de conectividad.
- Inventarios de auditoría generados:168 modelos y431 endpoints. Solo cambiaron
  timestamps frente a HEAD; los resultados se conservaron privadamente y se
  retiró ese ruido del candidato. Generar inventarios no acredita por sí solo
  ausencia de vulnerabilidades.
- Referencias Windows:14 pruebas PASS tras revisión del logo/lupa. Linux:
  primeras14 PASS; revisión adicional detectó cuatro diferencias de bordes
  (184–333 píxeles) en encabezados. Capturas y diffs inspeccionados: textos,
  distribución y controles conservados. Solo se actualizan sus cuatro PNG Linux,
  sin tolerancias nuevas; verificación conjunta final:42 PASS.
- Runtime local: Node24.14.1/npm11.11.0; Flutter3.41.6/Dart3.11.4.
- npm audit:1 aviso bajo y10 moderados;0 altos/0 críticos. Las dependencias y
  lockfiles no cambian en esta integración; no se ejecutó audit fix. Sitio:0 avisos.
- Se volvió a consultar el remoto:production-main sigue en cbc3eceb.

## Ajustes exclusivos de integración

- Adaptar pruebas a los textos, constructores y botones realmente aprobados.
- Compartir finder de cierre de notificaciones por tooltip o etiqueta semántica;
  se conservan las pruebas de cierre, persistencia y accesibilidad de la X.
- Esperar resultados reales de SQLite con límite, en lugar de tiempos fijos,
  para caja y recuperación de ventas; no cambiar las expectativas de negocio.
- Completar el vencimiento sintético E31 de una fixture PostgreSQL de devoluciones;
  el control productivo permanece intacto.
- Actualizar solo referencias visuales inspeccionadas; no cambiar comparadores.
- No hay cambios de esquema, migraciones, restricciones de dependencias ni
  Dockerfiles respecto a la base remota. La aceptación posterior añade una
  regresión Chrome al workflow CI; no cambia el proceso de publicación.

## Procedencia y límites

El manifiesto `visual-fiscal-integration-provenance-20261114.json` relaciona los
449 registros de origen (447 rutas únicas), sus hashes y el resultado integrado.
Los archivos combinados deliberadamente no tienen por qué coincidir byte a byte;
el manifiesto los distingue. Las copias originales se verifican contra snapshots.
Resultado final:434 registros byte-idénticos,15 combinados o referencias
revisadas,0 faltantes y0 cambios en los originales desde la copia congelada.
Inventario completo del candidato en `VISUAL_FISCAL_INTEGRATION_FILES_20261114.md`.
El escaneo de patrones de secretos de alta confianza no encontró candidatos;
no sustituye una revisión manual ni un análisis exhaustivo de secretos.
Los tres generados normalizados se conservan en backup privado; no representan
cambios lógicos que deban introducirse en Git.

No se afirma una nueva certificación externa ni una emisión real ante DGII/DOSA.
La aceptación posterior de navegador/API está documentada en
`VISUAL_FISCAL_UAT_20261114.md`, con escenarios reales locales y fixtures fiscales
simuladas claramente separados. No hay aceptación de dispositivo ni impresión
física. Las pruebas widget/HTTP no sustituyen esas comprobaciones. El build
Flutter lleva perfil UAT; no es una imagen productiva para desplegar.
Las omisiones de pruebas se informan y no se contabilizan como PASS.

## Comandos de validación ejecutados

Desde raíz:

```text
npm run api:build
node scripts/release/sync_api_docker_lock.mjs --check
git diff --check
git diff --cached --check
```

Desde `apps/api`, siempre con la conexión privada al PostgreSQL desechable local:

```text
npx prisma migrate deploy
npx prisma validate
npm test -- --runTestsByPath src/sales/sales-return-ecf-credit-postgres.integration-spec.ts --forceExit
npm test -- --forceExit
npm run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/ecf-documents-http.e2e-spec.ts src/ecf/pos/legacy-pos-compatibility-http.e2e-spec.ts --forceExit
npm run audit:tenant-inventory
npm run audit:endpoints
```

Desde `apps/fulltech_app`:

```text
flutter analyze
flutter test --no-pub --concurrency=1
flutter build web --release --no-pub --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=FULLPOS_UAT_BUILD=true
```

Se ejecutaron además las regresiones enfocadas descritas arriba y la verificación
Linux sin `--update-goldens` de estos cinco archivos: `branded_menu_button_test`,
`refined_topbar_controls_test`, `sales_detail_panel_test`,
`sales_catalog_command_bar_test` y `sales_ticket_bar_test`.
Los logs completos se conservan en el backup privado indicado al inicio.

## Pasos pendientes de publicación

1. Autorización recibida del propietario para commit/push/PR únicamente de
   `agent/integrate-visual-fiscal-20261114` hacia `production-main`.
   Las ramas y copias originales no se alteran; no se utiliza force-push.
2. Los cuatro controles del candidato inicial385df9f7 pasaron en GitHub Actions.
   La aceptación aislada encontró un bloqueo Web de SQLite al exportar PDF normal;
   su corrección mínima, prueba Chrome y nueva aceptación deben validarse en el
   head posterior. Consultar `VISUAL_FISCAL_UAT_20261114.md` y los checks actuales
   de PR45; un resultado del head anterior no aprueba automáticamente el nuevo.
3. El propietario decide el merge; no se hace automáticamente.
4. Preparar imágenes por el procedimiento vigente y registrar versiones actuales
   para rollback antes de un deploy expresamente autorizado. No restaurar la
   base de datos como parte de un rollback de interfaz.

## Publicación

Solo commit, push de la rama de integración y apertura de PR están autorizados.
No merge, tag, release, deploy, reinicio, configuración productiva, credenciales
productivas, activación global fiscal ni escritura de base real.
El usuario conserva el control del merge y del deploy.
