# FullPOS Cloud Offline Safe 48h — Fase 11

Fecha: 2026-10-14. Worktree: `C:\src\fullpos-offline-safe-48h`.
Rama: `feature/offline-safe-48h`. Base: `6b3e38ed`.

## 1. Resumen ejecutivo

HECHO: se retomaron los cambios acumulados, sin reiniciar las fases anteriores.
La prueba real HTTP/PostgreSQL produjo un producto, una entrada +20 y una venta
-4, con stock final 16 pese a cinco solicitudes concurrentes por operación.
Los payloads divergentes se rechazaron con 409.

HECHO: una prueba separada usa los repositorios reales de Flutter, SQLite FFI,
la cola real y la API UAT. Reabre SQLite y pierde intencionalmente la respuesta
de producto, entrada y venta DESPUÉS de la persistencia remota. Reintentar
conserva las identidades, deja cero pendientes y stock 16. Una auditoría SQL
independiente concilió producto, entrada, venta, línea y turno.

No se autoriza producción. El flujo GUI Windows del código nuevo requiere
aprobación manual. Reabrir SQLite en un test no equivale a reiniciar Windows.

## 2. Estado Git inicial y atribución

El directorio principal estaba en `production-main`, con cambios ajenos al
alcance. No se editó. El worktree offline ya tenía 79 archivos rastreados
modificados, archivos nuevos de fases anteriores y una migración de inventario.
Esos cambios se conservaron. Ningún commit, push, merge o publicación se realizó.

La migración `20261014113000_inventory_movement_operation_id` ya estaba aplicada
en UAT al revisar `_prisma_migrations`; no se reescribió.
`docs/EXECUTION_STATE.md` describe un trabajo anterior de updater en otro
worktree/puerto. Se leyó y preservó; este informe es el checkpoint de Fase 11.

## 3. Aislamiento UAT

HECHO: `Assert-UatEnvironment` pasó antes de los comandos con base de datos.

- API: `http://127.0.0.1:46548`.
- PostgreSQL: localhost:56548, contenedor `fullpos_offline_safe_48h_postgres`.
- Base consultada: `daleventa_offline_safe_48h_uat`.
- Configuración: archivo ignorado `apps/api/.env.offline-safe-48h.uat.local`.
- SQLite manual: `.uat/windows-app-root/databases/fulltech_offline.db`.
- SQLite de prueba integral: `.uat/phase11-flutter-client-<timestamp>/databases`.

Los scripts nuevos comprueban identidad de host, puerto, nombre de base y modo
UAT. No se imprimen contraseñas, tokens ni cadenas de conexión.

## 4. Evidencia histórica preservada

Backup consistente mediante `sqlite3.Connection.backup`, incluyendo el estado
del WAL: `.uat/evidence/fulltech_offline_backup_phase11_20261014T152131Z.db`.
`integrity_check`: `ok`.

| Tabla manual | Inicial |
| --- | ---: |
| pending_actions | 1 |
| offline_sales | 8 |
| offline_sale_items | 20 |
| offline_sale_payments | 8 |
| offline_inventory_intents | 20 |
| cache_entries | 344 |

Auditoría independiente: las 8 ventas manuales siguen siendo únicas por
identificador, conservan importe y turno; se conciliaron 20 líneas y 20
movimientos. La fila completa de la cotización pendiente se comparó con el
backup y quedó idéntica, incluidos payload, error e intentos.

## 5. Arquitectura conservada

PostgreSQL continúa como fuente oficial. SQLite guarda el catálogo local y el
outbox. No se añadió otro servidor POS ni se replicó toda la base empresarial.
La ruta sigue siendo UI → controlador → repositorio → SQLite/cola → API →
transacción PostgreSQL. Los handlers históricos permanecen registrados.

## 6. Productos offline

El repositorio genera identidad UUID antes del primer envío si el caller no la
proporcionó. Para identificadores no UUID, calcula el mismo UUID determinístico
por empresa que el backend. El ID local nuevo y el remoto coinciden.

El servidor guarda `Product.createPayloadHash`: SHA-256 de los campos originales
de creación, incluyendo stock inicial, almacén, precio, costo, unidad,
clasificación, impuestos e imagen. Un replay usa ese hash inmutable, no el stock
actual, que puede haber cambiado por entradas/ventas posteriores.

Para operaciones identificadas se evita reutilizar otro producto equivalente o
podar duplicados por similitud. No se reemplazan referencias por nombre.
La inserción y el stock inicial están en una sola transacción. Una colisión
única recupera únicamente el producto de la misma empresa y comprueba payload.

## 7. Entradas de mercancía

La identidad se conserva desde el primer PATCH hasta el outbox. Se persiste el
hash del payload original en `InventoryMovement.operationPayloadHash`.
La barrera única heredada es `(company_id, operation_id)`.

Repetir una entrada no aumenta stock otra vez; cambiar cantidad, motivo o modo
genera `INVENTORY_OPERATION_PAYLOAD_MISMATCH`. Movimiento y stock permanecen
atómicos mediante el servicio de mutaciones existente.

El formulario Agregar/Disminuir ya expresa una cantidad incremental. Ahora
envía la base de stock también para almacén único, de modo que el controlador
manda delta. No cambió su diseño. Sin red se admiten únicamente deltas positivos
con categoría autorizada. Conteos absolutos, salidas y eliminación nueva
requieren conexión. Sus pendientes históricos no se borran ni se desregistran.

## 8. Dependencias

La cola espera la creación del producto antes de su entrada o venta. Una venta
también espera las entradas anteriores pendientes de sus productos. Se incluyen
pendientes en backoff y permanentes; un fallo del prerequisito no envía un ID
inválido ni marca al dependiente como sincronizado. El alcance sigue filtrado por
empresa/usuario. La revisión de dependencias tiene un límite de 100000 filas.
Antes de cada handler se vuelve a comprobar empresa/usuario. Si la sesión cambió,
se detiene el lote sin enviar los pendientes anteriores. La prueba específica y
los once casos existentes de la cola pasaron. El repositorio también captura
empresa/usuario antes del envío y comprueba que no cambien al guardar el fallback;
el outbox se asigna explícitamente al dueño original. La prueba cambia a una
empresa con grant válido durante el fallo de red: ni producto ni entrada se
encolan en ella. El pase focal con catálogo y cola pasó 18 pruebas.

## 9. Idempotencia y concurrencia

Se usan advisory locks de transacción por empresa/tipo/identidad junto con
restricciones únicas. Las colisiones del hash del lock solo serializan trabajo;
la identidad económica continúa comprobándose en las tablas tenant-scoped.

Referencias consultadas: [PostgreSQL 16, locks](https://www.postgresql.org/docs/16/explicit-locking.html)
y [Prisma, transacciones](https://www.prisma.io/docs/orm/fundamentals/transactions).
Context7 no está expuesto en esta sesión. Se verificó Prisma 5.22 generado,
Flutter 3.41.6 y Dart 3.11.4; no se actualizaron dependencias.
Discrepancia documental: el manifiesto declara TypeScript ^5.6.3 y el runtime de
ts-node-dev reporta TypeScript 5.9.3 instalado. Las reglas generales describen
5.6; esta sesión utilizó la instalación existente y no cambió package/lockfiles.

## 10. Cotización histórica y recuperación propuesta

`quotes.create:local_quote_1791944878261619` permanece `failed`, permanente, con
41 intentos y `customerId must be a UUID`. El ID temporal está dentro de
`payload.quote.customerId`: `local_1791939693146043`. Tiene tres líneas y total
390. No se reencoló ni se recuperó sobre el original.

Se creó `.uat/evidence/phase11-quote-recovery-copy.db` desde el backup. Una prueba
leyó esa copia en modo read-only y ejecutó `CotizacionModel.toCreateDto()` real:
omite customerId local y conserva nombre, teléfono y tres líneas. El DTO de
ensayo queda en `.uat/evidence/phase11-quote-recovery-dto.json`, ignorado en Git.

La búsqueda tenant-scoped por nombre/teléfono/total encontró cero candidatos
remotos. Esto no demuestra ausencia absoluta de duplicados: Cotizacion no tiene
identidad idempotente persistida equivalente a Sale.

RECOMENDACIÓN: antes de recuperar el original, revisar cliente y líneas, comparar
otra vez posibles equivalentes remotos, guardar checkpoint y probar el envío del
DTO en una base desechable. Solicitar autorización expresa para la recuperación
original. No basta con limpiar el estado permanente y reintentar a ciegas.

## 11. Caja y turnos

Los smokes nuevos utilizan un turno UAT existente y no abren/cierran turnos.
La venta nueva conserva `originCashSessionId`; las ventas manuales mantienen sus
turnos históricos. El smoke antiguo de Fase 8 cambia turnos y consume stock de
fixtures manuales: no se volvió a ejecutar sobre esa evidencia. Su objetivo de
integridad se cubrió con fixtures nuevos y conciliación SQL separada.

## 12. SQLite

Catálogo y acción de producto/entrada se guardan en una transacción SQLite antes
de devolver confirmación local. Si SQLite no está disponible, esas mutaciones
fallan; no se anuncian como durables mediante SharedPreferences.
La prueba integral confirma cierre y reapertura del store real.

Los reintentos locales con la misma identidad conservan el pendiente original;
los payloads divergentes requieren revisión. La autorización vencida bloquea
nuevas operaciones, pero los handlers de sincronización no dependen de renovar
esa autorización.

## 13. PostgreSQL y backups

Backup previo: `.uat/evidence/phase11_postgres_before.dump`, producido por pg_dump
del contenedor UAT comprobado. No hubo DROP, TRUNCATE, reset, seed, purga,
backfill ni restauración sobre la evidencia manual.

Evidencias: `phase11-flutter-postgres-reconciliation.json` y
`phase11-preservation-postgres.json` bajo `.uat/evidence`.

## 14. Archivos editados en esta continuación

Se incluyen solo archivos tocados por esta sesión; algunos tenían cambios previos.

- `apps/api/prisma/schema.prisma`
- `apps/api/prisma/migrations/20261014153000_offline_operation_payload_hash/migration.sql`
- `apps/api/src/auth/auth.service.ts`
- `apps/api/src/auth/auth.service.spec.ts`
- `apps/api/src/inventory/inventory-mutation.service.ts`
- `apps/api/src/products/products.service.ts`
- `apps/api/src/products/products.service.stock-hardening.spec.ts`
- `apps/fulltech_app/lib/core/cache/local_json_cache.dart`
- `apps/fulltech_app/lib/core/offline/offline_emergency_policy.dart`
- `apps/fulltech_app/lib/core/offline/offline_store.dart`
- `apps/fulltech_app/lib/core/offline/sync_queue_service.dart`
- `apps/fulltech_app/lib/features/catalogo/data/catalog_repository.dart`
- `apps/fulltech_app/lib/features/products/ui/inventory_module_pages.dart`
- `apps/fulltech_app/test/features/catalogo/catalog_offline_repository_test.dart`
- `apps/fulltech_app/test/features/catalogo/catalog_offline_uat_integrity_test.dart`
- `apps/fulltech_app/test/core/offline/sync_queue_scope_switch_test.dart`
- `apps/fulltech_app/test/features/products/stock_incremental_callback_test.dart`
- `scripts/build/build_windows_uat_release.ps1`
- `scripts/uat/run-product-stock-integrity-smoke.ps1`
- `scripts/uat/product-stock-integrity-smoke.cjs`
- `scripts/uat/audit-phase11-flutter.cjs`
- `scripts/uat/audit-phase11-preservation.cjs`
- Este informe.

## 15. Migraciones UAT

Tras verificar aislamiento y guardar pg_dump se ejecutó `npx prisma migrate
deploy` desde `apps/api`, con entorno cargado por `_common.ps1`.
Aplicó solo `20261014153000_offline_operation_payload_hash`, que añade dos
columnas nullable; las filas previas no se reescribieron. No se cambió una
migración aplicada. Los productos antiguos sin hash mantienen comparación
legacy; no es posible reconstruir retrospectivamente todo su payload original.

## 16. Pruebas automáticas

| Comando ejecutado | Resultado observado |
| --- | --- |
| flutter analyze --no-pub | PASS sin issues |
| flutter test --no-pub | Pases previos: 1302, 1307 y 1308 PASS. Último pase completo con dueño de operación capturado: 1309 PASS, 3 omitidas (incluye 2 ensayos UAT opt-in, ejecutados aparte con PASS) |
| npm --workspace apps/api test | 74 suites PASS, 751 tests PASS, 8 omitidos |
| npm --workspace apps/api test -- --runTestsByPath src/products/products.service.stock-hardening.spec.ts src/auth/auth.service.spec.ts | PASS 35 antes de agregar los cuatro casos de permisos, incluidos luego en el pase completo |
| flutter test --no-pub test/features/catalogo/catalog_offline_repository_test.dart | PASS 6, identidad, reintento local sin doble incremento, payload divergente y cambio de empresa durante fallo de red incluidos |
| flutter test --no-pub test/features/products/stock_incremental_callback_test.dart | PASS desktop y móvil |
| flutter test test/features/catalogo/catalog_offline_repository_test.dart test/core/offline/offline_emergency_policy_test.dart test/core/offline/offline_store_sales_test.dart | PASS 18, SQLite FFI incluido |
| npx prisma validate | PASS |
| npm run api:build | PASS, prisma generate y TypeScript completos |
| git diff --check | PASS; avisos CRLF, sin errores whitespace |

El pase focal final de catálogo, formulario incremental, política 48h, SQLite
y unidades de medida pasó 29 pruebas. Tras el último ajuste de llaves de lint,
`flutter analyze --no-pub` volvió a pasar. El segundo ensayo UAT opt-in pasó
ambas pruebas: cotización en copia y producto/entrada/venta con respuestas
perdidas, usando el código revisado de reintentos locales.

Fallos transitorios registrados: expectativas de select en auth, nulabilidad en
el test UAT nuevo, lints locales y selector de cantidad móvil en el test nuevo.
Se corrigieron y se repitieron las comprobaciones correspondientes. No se
debilitaron validaciones de seguridad para hacerlas pasar.
Un intento extra de test Flutter coincidió con otra ejecución Flutter y falló
antes de cargar tests por PathExistsException al copiar sqlite3.dll. Se repitió
secuencialmente: ambas pruebas UAT y su conciliación SQL pasaron. No se borraron
archivos ni se modificaron dependencias para resolverlo.

## 17. Pruebas PostgreSQL reales

- `. ./scripts/uat/run-product-stock-integrity-smoke.ps1`: PASS. Cinco solicitudes
  concurrentes de producto, entrada y venta; replay equivalente y divergente.
- Prueba Flutter opt-in `catalog_offline_uat_integrity_test.dart`: PASS con API
  localhost, SQLite aislada, pérdida de tres confirmaciones y reapertura SQLite.
- `node scripts/uat/audit-phase11-flutter.cjs`: PASS, stock 16, una venta/entrada.
- `node scripts/uat/audit-phase11-preservation.cjs`: PASS, 8 ventas manuales,
  20 líneas, 20 movimientos, cotización intacta y cero candidatos por los
  criterios acotados de la búsqueda.
- GET local `/health` y `/health/db`: `ok` tras reiniciar API UAT.

## 18. UAT manual y visual

La evidencia histórica del usuario sigue siendo válida como evidencia histórica:
ventas, creación de productos, clientes, turnos y reapertura manual funcionaron.
No equivale a validar el binario nuevo de esta fase.

Se probaron los widgets reales a 1366×768 y 390×844, con fuentes reales, sin
excepciones/overflow detectado por Flutter. Capturas inspeccionadas:
`.uat/evidence/phase11-stock-increment-1366.png` y `...-390.png`.
Hallazgo visual ajeno al cambio: el toast existente queda recortado por la
izquierda en 390 px. Se documenta y no se rediseñó.

No hay control nativo de escritorio expuesto en esta sesión. Login, operación
offline y reinicio Windows GUI del binario nuevo quedan para el operador.

## 19. Build backend y bloqueo del shell

Al iniciar no había listener en 46548. `powershell -NoProfile -File
scripts/uat/run-backend.ps1` fue rechazado por ejecución de scripts deshabilitada.
PowerShell 7 tiene RemoteSigned y ya ejecutaba `_common.ps1`; la invocación normal
`. ./scripts/uat/run-backend.ps1` arrancó UAT. No se cambió ExecutionPolicy ni se
usó Bypass para resolverlo.

El build completo pasó inicialmente y volvió a pasar después de detener solo el
watcher UAT verificado PID 23972 y su listener PID 33312. La API se reinició con
el script permitido; ambos healthchecks pasaron. EPERM no se reprodujo.

## 20. Windows

El primer build UAT con subst falló C1083 en archivos generados. Al usar la ruta
física, CMake detectó que su cache todavía refería Y:. Se preservó el directorio
generado x64 completo en `.uat/evidence/windows-x64-before-physical-phase11`,
verificando ambos destinos dentro del worktree y ausencia de app UAT abierta.
No se borró SQLite ni código. El script ahora usa la ruta física corta.
Build físico limpio: PASS, 200.6 s; produjo
`apps/fulltech_app/build/windows/x64/runner/Release/fullpos_cloud.exe`.
Los dos builds incrementales posteriores también pasaron (89.7 s y 87.1 s).
El último incluye la protección de cambio de sesión de la cola. Se ejecutó
`. ./scripts/uat/run-windows-portable.ps1 -SkipBuild` con la raíz manual preservada
y API localhost. HECHO: proceso UAT PID 23472, ventana
`FullPOS Cloud - Sistema de facturacion [UAT]`, Responding=true y ejecutable
dentro del worktree autorizado. Esto acredita arranque, no UAT GUI funcional.
Después del último guard del dueño se cerró esa ventana mediante CloseMainWindow,
sin cierre forzado. El build final pasó en 82.4 s y se volvió a abrir por el
launcher UAT: PID final 10168, mismo título [UAT], Responding=true.
SHA-256 del `data/app.so` final:
`D4D32687EBC1D2ACE9851FE00AE2213EBB04186C0E1446AACA7568DFF5D2F3DA`.
Solo se generó un build UAT local, sin instalador ni publicación.

## 21. Regresiones online y updater

Jest completo cubre regresiones tenant, autorización, ventas, caja, inventario y
servicios existentes. El smoke online nuevo pasó antes y después del build API.
El formulario incremental conserva el mismo objetivo de cantidad, con delta.

`. ./scripts/uat/run-updater-preservation-bench.ps1`: PASS en builds ficticios
201001/201002, preservación de DB/WAL/SHM y `.part`/`.ready`.
`. ./scripts/uat/run-sqlite-failure-bench.ps1`: PASS; locked=5, readonly=8.
El bench de updater prepara archivos ficticios; no ejecuta instalación comercial
ni demuestra por sí solo que un instalador de producción preserve datos.

## 22. Riesgos P0/P1/P2

- P0 para publicación: producción no está autorizada y el nuevo flujo GUI
  Windows aún no tiene aprobación manual completa.
- P1: muerte del proceso entre persistencia remota y guardado del outbox, antes
  de observar el timeout, sigue requiriendo ensayo de recuperación. La prueba
  realizada pierde respuestas con el proceso Flutter vivo.
- P1: la cotización original sigue sin conciliación; su recuperación requiere
  aprobación y ensayo de envío en base desechable, sin idempotencia de quotes.
- P1: HMAC/secure storage no protege ante control total del dispositivo; sin
  secure storage disponible subsisten las limitaciones heredadas del sello.
- P1: inventario offline es estimado y pueden existir conflictos con otro
  dispositivo; se conservan pendientes para revisión, sin inventar stock.
- P2: creación legacy sin hash no permite verificar todo el payload original.
- P2: toast móvil recortado y advertencias CMake de plugins.
- Pendientes externos: disco lleno/corte eléctrico físico, impresión/cajón real,
  actualizador comercial firmado y UAT en otras plataformas.

## 23. Matriz por módulo

H = evidencia histórica del usuario/otras fases; T = técnica de esta fase;
ND = no demostrado; N/A = operación no aplicable. GO T permite continuar UAT,
no producción. NO-GO GUI no autoriza publicar.

| Módulo | Offline permitido | SQLite | Idempotencia backend | PostgreSQL | Windows manual nuevo | Riesgo / estado |
| --- | --- | --- | --- | --- | --- | --- |
| Ventas cash no fiscal | Sí con 48h | T | T | T | H, nuevo pendiente | GO T / NO-GO GUI |
| Productos crear | Categoría propia | T atómica | T | T | H, nuevo pendiente | GO T / NO-GO GUI |
| Entradas mercancía | Delta positivo autorizado | T atómica | T | T | H, nuevo pendiente | GO T / NO-GO GUI |
| Conteos/salidas/eliminar | No nuevo offline | Histórico conservado | Delta T; conteos limitados | Incrementos T | ND | Restringido |
| Turnos | No ampliar soporte | H | H | Turno original T | H | Sin nuevas aperturas/cierres habilitados |
| Caja | Alcance heredado | H | H | Ventas cash T | H | Conciliar GUI/hardware |
| Clientes consulta | Caché | H | N/A consulta | H | H | No ampliar mutaciones |
| Cotizaciones | Alcance heredado | H | ND | Diagnóstico T | H | NO-GO recuperación original |
| Tickets no fiscales | Heredado | Venta persistida | N/A impresión | Datos venta T | H | Impresora real pendiente |
| Historial | Heredado | T ventas | N/A lectura | T ventas | H | GUI nuevo pendiente |
| Autorización 48h | Empresa/usuario/dispositivo/categoría | Prefs + sello | N/A | T endpoint | H | GO T, límites de tiempo/sello documentados |
| Sincronización | Producto → entrada → venta | T | T | T | H, nuevo pendiente | GO T / NO-GO GUI |
| Updater | Desactivado UAT | Bench T | N/A | N/A | No comercial | GO bench, NO-GO comercial |
| Licencias | Backend emite grant | H snapshot | N/A | Auth/Jest T | H | No cambiar enforcement comercial |
| Multiempresa | Cola scope empresa/usuario | T filtros | Tenant-scoped | UAT tenant + Jest | ND cruce GUI | Regresión técnica; GUI pendiente |

## 24. Continuación exacta y despliegue futuro

Checkpoint: el build Windows físico y sus incrementales pasaron. La app UAT está
preparada para el operador. El pase completo final de 1309 pruebas pasó,
incluyendo los casos de cambio de sesión. Se cerró normalmente únicamente la
ventana UAT verificada para recompilar el último guard del dueño de la operación;
el build final, la reapertura y las dos pruebas reales secuenciales pasaron.
La última conciliación usa `phase11-flutter-1791994551319`: un producto, una
entrada +20, una venta de cuatro unidades, tres confirmaciones perdidas, cero
pendientes y stock 16. El turno se mantuvo y PostgreSQL confirmó esos efectos.
La aprobación funcional GUI queda a cargo del operador.
No continuar a producción. Para el operador: login online para renovar categorías,
producto nuevo stock 0 → entrada +20 → venta cash 4 → cerrar/reabrir offline →
reconectar → verificar un producto/entrada/venta, stock 16 y turno original.

Antes de publicar: aceptar riesgos residuales, resolver cotización con permiso,
validar cliente anterior/cache/migración/updater firmado, tener backups,
recuperación y rollback, y obtener autorización expresa del propietario.

Estado actual: **NO-GO para cierre integral GUI/publicación**. Blindajes técnicos
críticos producto/entrada/venta tienen evidencia UAT real; pendientes identificados
arriba. No se autoriza producción. La recuperación original de cotización y el
flujo GUI del binario final requieren las acciones descritas anteriormente.
