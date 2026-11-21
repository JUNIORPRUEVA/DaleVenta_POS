# Consolidación de ambos chats — 21 de noviembre de 2026

Seguimiento posterior: [cierre de bloqueos locales](CONSOLIDACION_CIERRE_BLOQUEOS_20261121.md).
Este informe conserva la evidencia de su checkpoint; los resultados posteriores
de CRM y el ensayo privado de saneamiento se registran en ese seguimiento.

## Alcance y resultado

HECHO: se pausó el rediseño móvil y se prepararon candidatos **locales** de
integración. El propietario confirmó que los otros chats dejaron de editar.
No se hizo push, merge a una rama protegida, despliegue, reinicio productivo,
migración compartida, cambio de credenciales ni modificación de empresas reales.

**NO-GO para publicación y producción.** Los checkpoints locales conservan trabajo;
no constituyen aprobación de release. Los bloqueos se detallan más abajo.

## Ramas, procedencia y destino

| Repositorio | Base verificada | Candidato local | Worktree |
|---|---|---|---|
| FullPOS | origin/production-main `33625e3c` | agent/consolidacion-total-20261121, código `e5a053e4` + prueba `c9231113` | C:/t/fp-integ-20261121 |
| APPYRA IA | origin/main `09c451e` | agent/consolidacion-ia-20261121, `4dc19e2` | C:/t/ai-integ-20261121 |
| APPYRA CRM | entrega `15af69a` | agent/consolidacion-soporte-planes-20261121, `4e8d4a2` | C:/t/crm-integ-20261121 |
| Puente | entrega `0ea6d3f` | agent/consolidacion-puente-20261121, `dd80d7f` | C:/t/bridge-integ-20261121 |

FullPOS conserva los diez commits `6b0f8c68`, `840caadf`, `d5986236`,
`a4ebdf1e`, `c4bfd1d5`, `5545d07c`, `30e030db`, `57b4e095`, `20709dc3`
y `24f6d771` del otro chat, más `759bf50c` y `2388fe94` de IA/PDF.
Los merges locales `8f36da76` y `bd9bac1f` conservan ambos padres y su historia.
`e5a053e4` incorpora el pendiente móvil, sus recursos y las adaptaciones de pruebas.

APPYRA IA conserva `05c8bda`, `aac5c83`, `cdce8ef`, `f13409b` y `4dc19e2`;
no se reconstruyó el motor ni se cambió su configuración real.
CRM conserva primero la entrega de planes `15af69a` y añade el soporte interno.
La referencia reciente de CRM es `origin/feature/whatsapp-readiness-20261115`
(`0315c4c`); `master` es anterior. No publicar automáticamente a master.
El puente conserva su entrega comercial y suma pruebas ignoradas y protecciones
de empaquetado. Su etiqueta Docker continúa expresamente en NO_GO.

La copia original de FullPOS llamada production-main sigue en `6b3e38ed`,
anterior al remoto y con cambios propios. **No usarla para publicar ni ejecutar
pull/reset/restore globales.** Esta tarea no la actualizó.

## Inventario y conservación

HECHO: se tomaron snapshots y hashes de **1.189 archivos pendientes en 21
worktrees originales**, más 12 archivos ignorados del puente. La comprobación
posterior de archivos, parches staged/unstaged y HEAD no encontró diferencias.
Los recuentos incluyen duplicados entre worktrees; no son 1.189 funciones nuevas.

El ledger [CONSOLIDACION_CAMBIOS_20261121.csv](CONSOLIDACION_CAMBIOS_20261121.csv)
contiene una fila por archivo pendiente, origen, HEAD, comparación y disposición.
No contiene valores de entorno ni material privado.
La lista por archivo del candidato de cada repositorio está en
[CONSOLIDACION_ARCHIVOS_CANDIDATOS_20261121.csv](CONSOLIDACION_ARCHIVOS_CANDIDATOS_20261121.csv).

Backup privado con ACL restringida:
`C:/Users/pc/.codex/backups/fullpos-consolidacion-20261121`.
Contiene manifests, hashes, parches binarios, copias originales y logs. No subir
esa carpeta: incluye contexto privado y artefactos históricos excluidos del Git.

Los 24 pendientes de licencias del CRM original coinciden exactamente con
`15af69a`: no se reaplican. El móvil se importa desde su snapshot de 121 archivos
de trabajo, excluyendo tres capturas ajenas. Las versiones antiguas de recuperación
y productos se conservan, pero no reemplazan la entrega final del otro chat.

RECOMENDACIÓN: conservar esos residuos archivados hasta la revisión del ledger.
No se afirma que todas las variantes antiguas divergentes sean intercambiables:
su disposición explícita es «preservado, no sobrescribe entrega final».
Seis residuos del checkout antiguo (preview e instalador Windows), iconos sin
referencias y binarios de release del puente tampoco se importan a ciegas.
Nada de ello fue borrado, descartado, stasheado ni sobrescrito en origen.

## Resoluciones semánticas

- Recuperación: se conserva la implementación final del otro chat; del móvil se
  aplican únicamente sus wrappers e iconos. No se reemplaza su flujo financiero.
- Inventario: los iconos nuevos se condicionan al teléfono nativo; Windows/web
  conservan ProductArtwork y la implementación final del ciclo de vida.
- Registro: se conserva el acceso automático web, mientras Android/iOS nativos
  muestran el requisito de cuenta existente. La documentación arquitectónica se
  ajustó a esa distinción; no se retiró el registro web/Windows.
- Diseño: se conservan ambos apartados del sistema visual y ambos historiales
  del estado de ejecución, sin declarar vigente un GO histórico.
- Pruebas: se completan fakes con productStream, catálogo dentro de transacción y
  filtro archivedAt. Los avisos se buscan en RichText sin perder las aserciones
  de posición, persistencia, guardado, permisos o aislamiento.
- El laboratorio fiscal admite una quinta tupla exacta de loopback, puerto y
  nombre de base. Se prueban también puerto/base incorrectos y host externo.
  No habilita emisión real ni modifica variables fiscales productivas.
- El UAT de planes admite un segundo laboratorio exacto, separado del laboratorio
  del otro chat. Solo allí crea catálogo sintético para sus pruebas.

## Validación ejecutada sobre la combinación

Los resultados de suites solapadas no se suman como casos únicos.

| Comando / entorno | Resultado observado | Evidencia privada |
|---|---|---|
| npm run api:build, FullPOS | PASS | fp-api-build-final.log |
| npx prisma validate | PASS | validación local de esquema |
| npx prisma migrate deploy, PostgreSQL nuevo local | PASS; ninguna base compartida | fp-local-migrations.log |
| npm --workspace apps/api test | 273 suites PASS, 3.149 pruebas PASS; 57 suites / 599 casos omitidos | fp-api-final.log |
| Cuatro suites de licencias con PostgreSQL real | 25 PASS: legado, concurrencia, límites y conservación fiscal | fp-real-license-postgres.log |
| Tres suites fiscales con PostgreSQL real y emisión externa desactivada | 41 PASS | fp-real-fiscal-postgres-retry.log |
| UAT HTTP FullPOS → puente → CRM, PostgreSQL real | 11 checks PASS, errors vacío | plans-crm-real-http-final.log y .uat/plans-crm/result.json |
| UAT de productos con HTTP/SQL reales | 9 escenarios PASS; compensación, replay, archivo, legado y empresa ajena | product-real-http.log |
| UAT de recuperación/cierre con HTTP/SQL reales | 9 escenarios PASS; movimientos únicos, casos conservados y empresa ajena intacta | recovery-real-http.log |
| flutter analyze, FullPOS | PASS, sin incidencias | fp-flutter-analyze-final.log |
| flutter test, primera combinación | 2.826 PASS, 10 omitidas, 7 fallos de integración de fixtures | fp-flutter-all.log |
| flutter test, segunda pasada | 2.831 PASS, 10 omitidas, dos finders de Compras antiguos | fp-flutter-final.log |
| flutter test, Compras tras adaptar RichText | 22 PASS | fp-purchases-final.log |
| flutter test, cuatro suites corregidas | 30 PASS | fp-flutter-fixed-cases.log |
| Prueba móvil de imágenes después de esperar el IO | 2 PASS, unicidad preservada | fp-image-picker-stable.log |
| Comparación de siete suites visuales en Linux, sin update-goldens | 101 PASS | linux-goldens-verified.log |
| Flutter completo Linux final con --concurrency=1 | 2.826 PASS, 17 omitidas, cero fallos | linux-flutter-clean-final.log |
| Compositor y columna IA en Linux, referencia de dock actualizada | 17 PASS sin regeneración | linux-ai-verified.log |
| Respaldo y fallos de BD local, Linux serial | 15 PASS, 1 omitida de plataforma | linux-storage-focused.log |
| flutter build web --release | PASS | fp-web-build-final.log |
| flutter build windows --debug --no-pub -v | PASS; ejecutable de prueba, no instalador release | fp-windows-debug-build-retry.log |
| npm test / npm run build, website | 16 PASS / build PASS de 14 páginas | website-tests.log, website-build.log |
| npm test, puente | 95 PASS tras adaptar tres fixtures al contrato final | bridge-tests-retry.log |
| npm run check:secrets, puente | PASS sobre árbol/index actual, incluido pre-commit | bridge-index-secrets.log y salida del commit |
| npm run check:secrets:history, puente | FAIL: material privado histórico y archivo tar grande | bridge-history-secrets.log |
| npm test, CRM backend | 2.525 PASS, 17 fallos, 23 omitidas bajo ejecución paralela | crm-backend-tests.log |
| Diez suites fallidas CRM, repetición serial | 110 PASS y cuatro fallos en dos suites | crm-failed-serial.log |
| Dos suites CRM en baseline 15af69a, sin soporte nuevo | Reproduce los mismos cuatro fallos | crm-real-baseline.log |
| npx vitest run tests/fullpos-support.test.js --no-file-parallelism | 4 PASS | crm-support-final.log |
| node --check, cinco módulos CRM modificados | PASS | salida de terminal |
| flutter test, CRM | 362 PASS, 5 omitidas | crm-flutter-all.log |
| flutter analyze, CRM | 57 avisos/informaciones; no PASS limpio | crm-flutter-analyze.log |
| npm run typecheck / npm run lint, APPYRA API | PASS | ai-typecheck.log, ai-lint.log |
| npm test -- --runInBand, APPYRA API | 86 suites, 960 casos PASS; proveedores simulados | ai-unit-tests.log |
| npm run build, desde APPYRA apps/api | PASS, nest build | salida de terminal; intento inicial desde raíz fue ENOENT |
| node scripts/release/sync_api_docker_lock.mjs --check | PASS, 756 paquetes | salida de terminal |
| YAML del gate revisado, parser js-yaml instalado | PASS; conserva flutter test completo con concurrencia explícita de uno | salida de terminal |

Las 24 referencias PNG nuevas de Linux fueron generadas en Linux, copiadas con
verificación SHA-256 y repetidas sin regeneración. No se copiaron PNG Windows
sobre Linux ni se relajó el comparador. Se inspeccionaron imágenes de historial,
reportes, catálogo y soporte; esto es evidencia de render de pruebas, no un
recorrido humano de todos los formularios ni validación física de iPhone.

La repetición completa final en Linux terminó **PASS: 2.826 aprobadas y 17
omitidas explícitas**, sin fallos, con `flutter test --no-pub --concurrency=1`.
El gate Flutter mantiene todas las pruebas y fija esa misma concurrencia.
El análisis final FullPOS también pasó sin incidencias. Los intentos parciales
o con configuración de arnés incompleta nunca se consideran PASS.
Se verificaron por SHA-256 los 1.370 archivos versionados de lib/assets/test/web
y configuración de Flutter: no hubo diferencias entre candidato y contenedor.

Los dos UAT adicionales usan copias del ejecutor canónico bajo
`.uat/consolidation`: solo cambian los destinos a las bases sintéticas de esta
tarea, puertos 4029/4030 y directorios de evidencia. No se ejecutaron contra los
laboratorios originales ni se cambiaron sus aserciones. Ambos servidores locales
se terminaron al cerrar sus pruebas.

Incidencias del procedimiento conservadas: un build Windows inicial devolvió
MSB8066; el reintento con salida detallada compiló. Un comando npm en la raíz de
APPYRA IA falló por falta de package.json; ejecutado desde apps/api pasó. Una
pasada Flutter con API_BASE_URL por dart-define contradijo tres aserciones que
comprueban expresamente el fallback sin esa definición; se repitió sin alterar
esas pruebas. El primer contenedor Linux carecía de dart_test.yaml y de archivos
web/backend leídos por pruebas de contrato: su ejecución incompleta no es un
resultado válido del candidato. No se silenció ninguno de esos intentos.

APPYRA IA: typecheck, lint, build y sus 960 pruebas Jest pasan desde apps/api.
CRM Flutter: 362 PASS, 5 omitidas; flutter analyze informa 57 incidencias, sin
atribuirlas automáticamente al cambio de soporte. El backend CRM obtuvo 2.525
PASS, 17 fallos y 23 omitidas en paralelo; al repetir las diez suites fallidas
en serie quedaron únicamente las dos suites previas reproducidas en baseline.
La prueba focal del soporte importado pasa sus cuatro casos. Puente: 95 pruebas
PASS después de actualizar fixtures de contratos; check:secrets del índice PASS,
check:secrets:history FAIL. Web pública: 16 pruebas PASS y build Astro PASS.
No se suman baterías solapadas como casos únicos.

La última pasada amplia Windows terminó con 2.832 PASS, 10 omitidas y un fallo
intermitente del helper de imágenes anterior a c9231113; la repetición focal
corregida pasó 2/2. No se describe esa pasada amplia como enteramente verde.
La pasada Linux configurada terminó con 2.811 PASS, 17 omitidas y cuatro fallos,
además de dos procesos de pruebas de almacenamiento que finalizaron con
segmentation fault y casos sin completar. Tres fallos eran archivos de contrato
ausentes en el arnés y una referencia visual antigua; se suministraron los
archivos y se repitieron las baterías relevantes. Almacenamiento pasó después
15 casos en ejecución serial. La causa de los cierres nativos amplios no se
atribuye a código de negocio sin prueba. La pasada completa con concurrencia
explícita de uno pasó completamente después de esos controles focales. Los
registros fallidos se conservan; no se cambia la tolerancia de las pruebas.
La biblioteca de pruebas legacy PayPal del puente se preservó en Git, pero no se
ejecutó como parte de npm test: pertenece al comando separado test:paypal:legacy.
No se considera verificado un flujo comercial PayPal mediante esta integración.

## Datos, migraciones y dependencias del futuro release

El PostgreSQL creado para esta tarea se llama
`fullpos_consolidacion_pg_20261121`, expone únicamente loopback 56711 y contiene
datos sintéticos. Los laboratorios existentes del otro chat no se reutilizan.
Las respuestas fiscales externas son simuladas; no se emitieron e-CF reales.
La entrega de avisos de pago usa recording transport, sin envío a Meta.
No se probó una compra, suscripción ni cobro real.

Siete migraciones FullPOS **adicionales respecto de la base remota**:

1. 20261120120000_cash_movement_occurred_at.
2. 20261120180000_offline_cash_open_evidence.
3. 20261120183000_recovery_review_cases.
4. 20261121010000_product_lifecycle.
5. 20261121011000_product_lifecycle_events.
6. 20261121012000_product_lifecycle_historical_returns.
7. 20261121013000_product_lifecycle_return_column_mapping.

Las dos primeras añaden columnas opcionales; recuperación añade sus tablas e
índices. Productos añade campos, auditoría, restricciones y triggers. Las dos
últimas ajustan la función para devoluciones históricas y sus nombres físicos.
No basta con desplegar la PWA: requieren revisión y procedimiento manual de BD
con autorización separada. No se alteró una migración histórica ya existente.
No se asignan planes automáticamente ni se recortan concesiones de clientes
antiguos. No se ejecutó seed/backfill sobre empresas existentes.

Hashes SHA-256 de los siete archivos SQL revisados (orden de la lista anterior):

```text
afe4c77a06541b292add467efa8677fa3f16ee9b35ed9db2fa79b49b987c242a
8473aea1a073531207cabe0269c6aa6e203086054acd1ab5543bbfbe0f41665e
e3bf993e76e31ca3161952e4fef739910980ae65f38102dee5a64c656936e8ab
9e8e81c529b0f1e5af2e6de3724c18b93fdae57c7655e903fc6b62b8852051c6
99dd1e9509d6c21c22dd76db421fb9281a4ac64bbe488e76a20a7f284e6cf0d1
924de2a7d8116c5d9caa1a832d087d35a510e07e85fdd08d1465339db670ebe1
3251e456a2d060a1e5db5c5ff1f2c751868cc759e9683b0c0a081fe500de4070
```

Soporte depende de APPYRA_CRM_SUPPORT_URL y FULLPOS_SUPPORT_SHARED_SECRET,
configurados de forma coordinada en los backends. Se documentan solo nombres;
no se consultaron ni cambiaron valores productivos. La API valida la firma,
ámbito de empresa/usuario y visibilidad de mensajes; el cliente no recibe claves.
La configuración fiscal y las credenciales por empresa permanecen protegidas.

## Bloqueos y límites de la conclusión

1. **Puente: NO-GO de publicación del historial.** Hay una clave privada en
   commits antiguos y un tar que exige revisión privada. Esta tarea no imprimió
   ni expuso su contenido, no reescribió historia y no rotó claves. Requiere un plan
   separado para sanear/publicar y evaluar claves sin interrumpir clientes.
2. **CRM: dos suites anteriores siguen rojas.** whatsapp-calling tiene un error
   de sintaxis al importar su script; laura-whatsapp-end-to-end mantiene cuatro
   casos sin respuesta. Reproducción en baseline demuestra que el soporte nuevo
   no los introduce. No se eliminan pruebas ni se silencian sus fallos.
3. **Omisiones:** 599 casos backend FullPOS no ejecutados por el comando normal
   no son PASS. Las baterías opt-in reales cubren solo el subconjunto indicado.
   Hardware, iOS físico y todos los formularios requieren sus verificaciones.
4. **Entrega combinada todavía no publicada:** no existen controles nuevos de
   GitHub Actions de estos candidatos locales. El estado verde de PR anteriores
   no certifica esta mezcla.
5. Los residuos antiguos divergentes permanecen identificados y respaldados;
   no deben importarse ni descartarse mediante una elección masiva ours/theirs.
6. La pasada amplia Windows detectó un caso intermitente de imagen móvil que
   esperaba 1,8 segundos de IO fijo. Se cambió solo su helper de prueba para
   esperar la condición de subida con hasta 80 ciclos de 120 ms; permanece la
   exigencia de exactamente un picker y un upload. No se cambió código de
   producción, timeout del selector ni validación de imágenes.

Consulta final read-only de remotos: FullPOS production-main continúa en
33625e3c, APPYRA IA main en 09c451e, CRM feature/whatsapp-readiness-20261115 en
0315c4c y puente main en afa4230. No aparecieron commits nuevos que exigieran
rebasar estas bases durante la preparación.

## Revisión y reversibilidad

Revisar el ledger y los diffs contra las bases de la tabla. Continuar únicamente
en estos candidatos o en worktrees nuevos. Los originales y los padres de merge
son puntos de retorno; no hacer reset de otros worktrees ni force-push.
Un checkpoint de Git no es rollback de base de datos. No ejecutar migraciones
inversas ni restaurar respaldos productivos como parte de revertir el diseño.
El futuro rollback de servicios debe usar artefactos verificados y compatibles
con el esquema que exista entonces, con autorización y respaldo propios.

**Decisión actual: conservar candidatos locales; NO-GO para merge protegido,
publicación de imágenes y despliegue.** El propietario mantiene el control de
esas acciones. Producción continúa intacta.
