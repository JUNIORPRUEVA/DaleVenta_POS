# FullPOS Cloud Offline Safe 48H — Fase 16

Fecha: 2026-10-14. Evidencia privada local: `.uat/evidence/phase16-*`.
HECHO significa observado en código, artefactos o ejecución; HIPÓTESIS no es una
garantía; RECOMENDACIÓN identifica trabajo futuro. No se incluyen secretos ni
payloads de clientes en este documento.

## 1. Resumen ejecutivo

Se corrigieron tres exposiciones económicas: recuperación que podía resetear una
base Windows tras un error de apertura; ausencia de constancia local antes de un
cobro remoto; y copias de migración mediante archivos DB/WAL/SHM sucesivos sin
snapshot consistente. También se rechazó explícitamente el downgrade de esquema
y se actualizó el SQLite nativo afectado por el defecto WAL-reset documentado.

HECHO: 20 casos de terminación de procesos con el OfflineStore real recuperaron
transacciones completas o descartaron las no confirmadas. La conciliación del
clon y una prueba Windows Release con respuesta remota perdida conservaron la
identidad económica sin duplicar venta ni stock. Esto es nivel A; no demuestra
resistencia a una pérdida física de alimentación. El veredicto integral para
candidato, piloto y publicación sigue siendo **NO-GO**, por pruebas obligatorias
y cadena firmada pendientes. No hubo acceso a producción, push, merge ni deploy.

## 2. Estado anterior y límites de los antecedentes

Se conservaron las fases 1–15 y su negociación de capacidades, idempotencia y
rechazo LEGACY_MISSING_SESSION. No se repitió la recuperación de la cotización
histórica. Los resultados nativos A14001→B14002, grant/identidad/WAL de F14 y
verificación del helper auténtico +132 de F15 son antecedentes, no nuevas
ejecuciones completas de esta fase. Véanse los informes F14/F15 del mismo directorio.

## 3. Arquitectura verificada

Registro de venta → VentasRepository → SQLite/OfflineStore → cola existente →
handlers → NestJS → transacciones PostgreSQL. La venta offline guarda cabecera,
líneas, pagos, intenciones de inventario y `sales.create` en una transacción.
El catálogo guarda cache+operación pendiente atómicamente. La cola conserva
company/user/terminal/idempotencyKey y dependencias; la API conserva tenant,
turno de origen y comprobaciones de replay/payload. No se creó otro motor de sync.

## 4. Worktree y atribución

`C:\src\fullpos-offline-safe-48h`, `feature/offline-safe-48h`, HEAD
`6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`. El worktree ya contenía cambios
acumulados; no son todos de F16. Las diferencias propias de los repositorios Dart
se revisaron también contra la copia previa `.uat/n/lib`. No se cambió main ni
se creó commit. No se detuvieron procesos de Flutter de otros proyectos.

## 5. Aislamiento y preservación

API local46548/PG56548 conservados; escrituras económicas de laboratorio en
API46552 y `daleventa_offline_safe_48h_phase12_uat`. El fallo de PG utiliza solo
el contenedor etiquetado `fullpos_phase13_failure_postgres`, puerto56593; terminó
detenido, con sus datos conservados. Las APIs locales se detuvieron para generar
Prisma/build y se reabrieron después sin seed ni migraciones compartidas.

Antes: `phase16-manual-before.db` mediante Backup API y
`phase16-postgres-before.dump`. Después: `phase16-manual-after.db` y comparación
exacta de filas: 8 ventas,20 líneas,8 pagos,20 intenciones,1 pendiente idénticas;
integrity_check=ok. La cotización fallida conserva identidad, importe390 y41
intentos. Auditoría PG de solo lectura:8 ventas únicas,20 líneas,20 movimientos,
turnos originales y0 candidatos de cotización. Evidencias:
`phase16-manual-preservation.json`, `phase16-manual-postgres.json`.

## 6. SQLite real y dependencias

DLL archivada del candidato previo:3.51.2; sqlite3 Dart3.1.6 usaba esa versión.
SQLite documenta WAL-reset en ciertas carreras entre conexiones y checkpoints,
afectando hasta3.51.2. Se fijó sqlite3 Dart3.1.7, que incorpora SQLite3.52.0.
Los workers FFI y el probe Windows Release consultaron3.52.0 en ejecución.
No se afirma haber reproducido espontáneamente esa carrera; se identificó una
versión afectada y se retiró del candidato nuevo.

sqflite_common2.5.6 pasó de transitiva a dev explícita para instrumentar el driver
en pruebas, sin cambiar su versión. sqlite3_flutter_libs0.5.41 continúa instalado;
la versión efectiva del DLL/native asset se verifica, no se deduce de ese plugin.
El banco Python usa3.50.4 y sirve solo para primitivas/corrupción; no prueba la
versión ni la carrera del driver de producción.

Referencias primarias: [WAL y WAL-reset](https://www.sqlite.org/wal.html),
[sqlite3 Dart changelog](https://pub.dev/packages/sqlite3/changelog).

## 7. PRAGMAs observados

Workers con el driver real: journal_mode=wal, synchronous=2(FULL),
foreign_keys=1, busy_timeout=5000, locking_mode=normal, wal_autocheckpoint=1000,
user_version=3, sqlite_version=3.52.0. Se registran en los fixtures del banco.
FULL solicita sincronización de cada commit; depende de que OS/controlador/disco
cumplan las barreras. No hay garantía universal de cero pérdida bajo hardware
defectuoso. [Documentación synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous).

## 8. Atomicidad y ventana remoto/local

La transacción offline ya existente se conservó y probó con el driver real. En
Windows Release ahora se persiste `sales.attempt` antes de POST, con payload,
empresa, usuario, terminal, turno e identidad originales. No es una venta local
confirmada ni un evento autoejecutable: queda `requires_action`.

Respuesta confirmada elimina el intento; rechazo definitivo400/401/403/404/422
lo libera.409/5xx/resultado ambiguo lo conservan. Con grant válido y operación
offline admitida, convertir intento a venta+outbox ocurre en la misma transacción.
Un fallo de esa transacción conserva el intento original. Un intento incierto
bloquea nuevos cobros de ese actor antes de POST; cambiar de empresa no lo
convierte en una venta de la empresa nueva. No se hace replay ciego de facturas.

HECHO: probe Release terminó tras commit remoto y antes de entregar respuesta;
al reabrir conservó el intento y bloqueó otro cobro. Repetir el payload original
en ese fixture devolvió la misma venta:1 venta,1 movimiento,stock16,total400,
mismo turno. Evidencia `phase16-process-postgres.json`, sección native. No hay
pantalla nueva de conciliación ni resolución automática del resultado incierto.

## 9. WAL y SHM

El WAL contiene commits aún no checkpointed; no debe borrarse ni separarse de
su DB. SHM es índice regenerable, no sustituto de WAL. Los reinicios nivel A
recuperaron agregados y cola. Una corrupción deliberada de WAL en copia produjo
un estado anterior coherente (1 de2 filas) con integrity_check=ok: integridad
estructural no prueba completitud económica. Conservar evidencias independientes.
`phase16-storage-chaos.json` documenta el límite, no lo cuenta como cero pérdida.

## 10. Checkpoints y crecimiento

Un lector retenido dejó WAL de4.210.672bytes: PASSIVE devolvió[0,1022,7]; al
liberarlo TRUNCATE devolvió[0,0,0], conservando502 filas. No se añadió TRUNCATE
automático durante cobro ni se borró WAL para recuperar espacio.
Caso L mata después de que PASSIVE retorna; **no** demuestra interrupción dentro
del I/O de checkpoint. Ese punto exacto queda NOT RUN. No hay aún alerta de
retención/crecimiento ni política empresarial de rotación.

## 11. Process kill A–L

`phase16-process-bench.py`, fixtures exclusivos y nonce; PID/EXE y descendencia
Windows verificados antes de TerminateProcess. OfflineStore real, no réplica
SQL del algoritmo. Resultado `phase16-process-bench.json`:20 casos PASS.

| Casos | Punto | Resultado y alcance |
|---|---|---|
| Venta A–F | Antes BEGIN; después BEGIN; cabecera; línea; outbox; antes COMMIT | Ninguna venta parcial ni outbox huérfano tras reabrir |
| Venta G | COMMIT retornó | Venta, líneas, pago, intención y outbox completos |
| Venta H/I | Antes/después del marcador de éxito del worker | Persistencia completa; marcador simulado, no GUI ni ticket físico |
| Venta J | Reapertura antes de validación | Datos confirmados recuperados |
| Venta K | Migración controlada en transacción | Rollback de esa migración; no equivale a todos los upgrades históricos |
| Venta L | Después de PASSIVE | Commit conservado; I/O interno de checkpoint no interceptado |
| Producto A/F/G/I | Antes BEGIN/COMMIT; después COMMIT/éxito | Cache y outbox juntos o ausentes |
| Entrada stock A/F/G/I | Mismos límites | Intención y cache juntos o ausentes |

Cinco ventas confirmadas G/H/I/J/L se reenviaron perdiendo un ACK real y se
reconciliaron una vez. Productos/entradas confirmados se conciliaron sin duplicar;
casos abortados no llegaron al backend. Las20 comprobaciones PG están en
`phase16-process-postgres.json`. El primer ensayo tuvo una carrera del marcador
de prueba vacío; se corrigió publicándolo mediante rename atómico y se reanudó
sin resetear fixtures (`phase16-process-bench-resumed.log`).

Nivel B VM: bloqueado por permisos Hyper-V ya documentados, sin elevación ni
bypass. Nivel C máquina dedicada/UPS: no ejecutado. El host real nunca se apagó.

## 12. Almacenamiento lleno y errores de acceso

Driver real con max_page_count acotado, solo en DB desechable: SQLITE_FULL
reproducido al guardar venta/producto/stock y al actualizar ACK (en este último
test se fuerza una asignación grande con un identificador artificial, no una
respuesta UUID normal del servidor). Cada transacción
revirtió sin perder operaciones previas; no se dio éxito ficticio ni fallback
a preferencias. Ocho tests financieros + uno de backup:9 PASS.

Banco de primitivas: BUSY timeout150ms(código5), LOCKED cursor(código6),
READONLY(código8). Banco SQLite CLI final: escritura bloqueada exit5 y readonly
exit8, originales conservados. No se llenó el disco host; espacio libre amplio.
No se inyectó IOERR real de VFS, fallo de FlushFileBuffers ni cuota física de
volumen Windows. No se afirma haber cubierto esos códigos mediante mocks.

## 13. Corrupción

Cabecera, página y truncamiento en copias: NOTADB/CORRUPT detectados y archivo
dañado conservado. Prueba Flutter del opener Windows con cabecera corrupta:
rechazo, mismos bytes originales, sin DB vacía ni directorio de reset. Esquema99
rechazado por cliente3 conservando versión99 y fila original. No se ejecutó
`.recover` sobre datos manuales ni reemplazo automático de la base dañada.

## 14. Backups de migración

El helper existente usa ahora SQLite Backup API hacia `.partial` en el directorio
privado de datos, verifica integrity_check, cuenta cola, obtiene versión y SHA256,
publica DB y manifest. Pausas de stream limitadas5s y duración observada10s;
no constituye un límite de tiempo de kernel I/O bloqueado. Copias parciales no
se restauran automáticamente y quedan para inspección. El test mantiene una
conexión WAL activa y comprueba que la copia incluye el commit no checkpointed.

Outbox v1 se respalda antes de alterar schema; prueba real1→3 conserva el
registro legacy y valida backup con esquema1. Cotizaciones solicita backup solo
si necesita subir versión7; no crea otra copia en cada apertura. Export
condicional evita importar sqlite3 nativo al módulo web. No se implementó backup
empresarial periódico, cifrado propio, retención ni almacenamiento externo.
[SQLite Backup API](https://www.sqlite.org/backup.html).

## 15. Recuperación supervisada

1. Detener nuevos cobros del actor afectado; conservar carrito, identidad y mensaje.
2. No resetear ni borrar DB/WAL/SHM. Registrar versión de aplicación, actor, hora
   UTC, operationId y hashes en expediente restringido, sin tokens.
3. Si la DB abre, obtener Backup API y verificar copia+manifest. Si no abre,
   preservar el conjunto físico original antes de cualquier intervención sobre copia.
4. Consultar backend autenticado y scoped por empresa+operationId; comparar
   payload económico completo y turno, no solo fecha/total. No elegir turno abierto.
5. Resultado incierto: conservar hold. Un replay exacto requiere evidencia y
   autorización de conciliación; nunca cambiar requestId/turno para pasar409.
6. Solo con resultado probado resolver el expediente. No eliminar el intento por
   presión operativa. El probe limpió únicamente su fixture tras replay confirmado.
7. Corrupta/incompleta: valorar copia verificada y operaciones posteriores con
   supervisión; restaurar una copia antigua sin conciliarlas puede perder pendientes.

No hay restauración empresarial automática ni herramienta apply nueva. Un fallo
de almacenamiento Windows conserva originales y propaga el error; otros sistemas
que permiten fallback conservan su comportamiento previo, fuera de este alcance.

## 16. PostgreSQL y transacciones

API build y Jest cubren validación/transacción/tenant. En PG desechable se
observaron fsync=on,synchronous_commit=on,full_page_writes=on,wal_level=replica.
El contenedor56593 se mató con SIGKILL: API500; tras reinicio0 productos antes
de retry,201 al reintentar y1 producto después. No se mató PG56548. Evidencia
`phase16-postgres-outage.json`. SIGKILL de contenedor no corta alimentación de
disco/host, no demuestra recuperación física de PostgreSQL ni RPO empresarial.

## 17. Idempotencia y sincronización

Se conservan IDs estables, hash del payload y restricciones de unicidad
backend existentes. Perder respuesta después del commit remoto no autoriza otro
cobro. Outbox normal reintenta la misma identidad; journal incierto no se
autoenvía. Sync smoke:3 ventas,total360,3 líneas/3 movimientos,mismo turno.
No se convirtieron409 en200 ni se relajó autorización para aprobar pruebas.

## 18. Inventario

Producto+20→venta−4→16 en clone/native; smoke también valida5 operaciones
concurrentes. Las operaciones locales anteriores a COMMIT no aparecen remotamente;
las confirmadas tienen un efecto. Se conserva orden producto→entrada→venta y
no se resuelve un producto faltante inventando otra identidad. Esto cubre fixtures
concretos y regresión de handlers, no toda combinación de inventario/fiscal.

## 19. Caja, turnos e impresión

Se captura y conserva originCashSessionId; PG comprueba turno original y efectivo
400 en el probe. LEGACY_MISSING_SESSION permanece409 si falta evidencia.
La persistencia de venta se espera antes del retorno y posterior impresión;
pruebas existentes de ticket pasan en la regresión. No se validó impresora/cajón
físico, corte de alimentación durante spool ni cobro manual duplicado fuera del
sistema. No se autoriza reemitir venta porque falló impresión; reimpresión debe
usar la venta existente.

## 20. Actualización Windows

Banco Inno propio sin AppId comercial, elevación, registro, desinstalación ni
borrado de datos. A es el probe Release archivado; B es main UAT. Se interrumpe
el instalador hijo antes/durante/después de copiar; reinstalación completa debe
dejar app.so igual al candidato y DB byte a byte idéntica. La DB del banco es una
copia sintética con pendientes retenidos, no las ocho ventas manuales.

Primer banco14016:3 PASS y rollback solo binarios, DB SHA256
`466F30119277CF11DF6F81DFFFDDEA25044537FFA3DD202810667DCDF277DFFE`.
El banco final14017 se registra aparte:3 etapas PASS, recuperación exit0 y DB
idéntica; `phase16-update-recovery-final.json`. Paquete SHA256
`8B314C22CD82B624F52723A80088D035F0E9B79C7822C6CF57397D1C7F3EEA9F`.
Se preservó la evidencia del primero. Build final main:99,3s, fuentes copiadas
comparadas byte a byte; `phase16-final-build-manifest.json` registra EXE/app.so/
DLL/helper. DLL3.52.0 SHA256
`2750D018864A8C0E6A8B189CBCEDB67A623352D5C40AD053F5CE8123394C998D`.
No es prueba de apagón físico, helper elevado, firma del publisher ni relanzamiento
automático comercial. Un binario antiguo no debe abrir schema nuevo por fuerza:
el guard de downgrade nuevo falla conservando datos; los antiguos no lo heredan.

## 21. Binarios históricos

HECHO heredado de F15, sin presentarlo como ejecución nueva: instaladores+130 y
+132 locales con SHA/manifiesto coincidentes. +130 SHA
`A0383ABB772347D76A9394CC3F56C233F6D149A7AE218846D6E514644F67A6E9`;
+132 `EC3A60BFADF8C5E00E37B2FC11EA6BDA9C80162C1A2806DFB993F3A6FD1A172D`.
Origen+130 e8473c02 sí envía originCashSessionId; +132 f1be244c también. El snapshot
69dd871b que no lo envía no equivale al instalador+130 encontrado. Distribución
real en clientes no está atestada; +133 no disponible. Helper auténtico+132 sí
ejecutado en verify-only; no se ejecutó ciclo completo de GUI histórica contra
backend. No se ha demostrado compatibilidad histórica total.

## 22. Firma digital, sustitución y permisos

Artefactos UAT/anteriores sin firma; no existe certificado disponible probado.
Validación del helper: ruta canónica bajo update-root, SHA, WinVerifyTrust y
publisher. PrepareExecutablePackage vuelve a verificar SHA del .exe staged tras
copiar .ready. La prueba verify-only no prueba ausencia de toda carrera entre
validación/ejecución ni ACL del canal comercial; falta prueba firmada de extremo
a extremo. No se desactivó validación comercial para aceptar unsigned.

F16 ejecutó10 casos verify-only con el helper auténtico+132 y el helper de la
build final14017 sobre el paquete final: válido unsigned de laboratorio exit0,
hash erróneo exit4, paquete incompleto exit4, fuera de raíz exit3 y firma exigida
exit5. Todos dieron el resultado esperado. `phase16-package-verifier.json`.
No hubo elevación ni instalación en ese ensayo; la firma exigida rechaza, no
valida un publisher firmado. Get-AuthenticodeSignature del runner final:NotSigned.

Un bloqueo Win32 real impidió reemplazar el archivo fixture (error5), conservando
original. No es evidencia de Defender, cuarentena, SmartScreen ni política de
empresa. No se desactivó antivirus ni se concedieron privilegios al host.

## 23. Matriz de compatibilidad real

| Combinación | Cobertura real | Límite |
|---|---|---|
| Cliente anterior → backend nuevo | Contratos HTTP/source-shaped; helper real+132 verify-only; evidencia F15 | No GUI/venta con instaladores auténticos130/132 |
| Cliente nuevo → backend anterior | Negociación de capacidades y baseline aislado de F13/F15 | No servidor comercial ni garantía de toda versión antigua |
| Cliente nuevo → backend nuevo | WorkerFFI, probe Release, sync/product-stock y PG de F16 | UI completa/hardware/canal firmado pendientes |
| Cliente antiguo → backend antiguo | Fuentes/artefactos inventariados | No ciclo histórico completo reproducido |

La prueba HTTP F16 sin turno da409 y deja stock intacto. No se agrega adaptador
que infiera sesión por horario ni que seleccione la caja abierta.

## 24. Autorización offline48h y reloj

No se amplió el grant, firma, identidad ni vencimiento. Tests de policy/clock/
actor permanecen en la suite completa; F14 probó persistencia de identidad/grant
en su banco nativo. El intento remoto duradero se conserva aunque el grant ya
no permita una venta offline; el mensaje exige revisión, no extiende48h.
No se adelantó/atrasó reloj del host ni se simuló un nuevo ciclo físico de48h.

## 25. Regresiones y comandos

Comandos ejecutados desde este worktree; logs en `.uat/evidence`:

| Comando | Resultado/evidencia |
|---|---|
| `flutter analyze` | PASS sin issues; phase16-flutter-analyze-final.log |
| `flutter test` | Final1330 PASS/5 omitidas,4min13s; phase16-flutter-test-final.log |
| `flutter test test/core/storage/financial_database_failure_test.dart test/core/storage/local_migration_backup_test.dart` |9 PASS; phase16-final-storage-tests.log |
| `flutter test test/modules/ventas/sale_attempt_durability_test.dart` |5 PASS |
| `npm --workspace apps/api test` |752 PASS/8 omitidas,74 suites; phase16-jest.log |
| `npm run api:build` |PASS Prisma generate+tsc; phase16-api-build.log |
| `npx prisma validate` desde apps/api |PASS; phase16-prisma-validate.log |
| `python scripts/uat/phase16-process-bench.py --resume` |20 PASS; phase16-process-bench-resumed.log |
| `python scripts/uat/phase16-storage-chaos.py` |PASS_WITH_DOCUMENTED_LIMIT; no apagón físico |
| `run-sync-integrity-smoke.ps1 -DisposablePhase12` |PASS; phase16-sync-smoke-final.log |
| `run-product-stock-integrity-smoke.ps1 -DisposablePhase12` |PASS; phase16-product-stock-smoke-final.log |
| `node scripts/uat/phase14-legacy-http.cjs` con envclone |PASS_SAFE_REJECTION; phase16-legacy-http.json |
| `run-sqlite-failure-bench.ps1 -BenchRoot .uat/phase16-final-sqlite-bench` |PASS; phase16-sqlite-failure-bench.log |
| `phase16-update-recovery-bench.ps1` |3 PASS; phase16-update-recovery.json |
| `phase16-update-recovery-bench.ps1 -FinalCandidate` |3 PASS; phase16-update-recovery-final.json |
| `phase16-package-verifier.ps1` |10 PASS; phase16-package-verifier.json |
| `flutter build windows --release --build-number=14017 --dart-define=API_BASE_URL=http://127.0.0.1:46552 --dart-define=DISABLE_APP_UPDATES=true` en .uat/n16 |PASS99,3s; phase16-final-main-build.log |
| `git diff --check` |PASS; solo avisos LF/CRLF, sin errores whitespace |

## 26. Archivos propios de F16

- `apps/fulltech_app/pubspec.yaml`, `pubspec.lock`.
- `lib/core/storage/resilient_local_database.dart`.
- `lib/core/storage/local_migration_backup.dart`, `local_migration_backup_io.dart`, `local_migration_backup_stub.dart`.
- `lib/core/offline/offline_store.dart`.
- `lib/modules/ventas/data/ventas_repository.dart`.
- `lib/modules/cotizaciones/data/cotizaciones_local_repository.dart`.
- `test/core/storage/financial_database_failure_test.dart`, `local_migration_backup_test.dart`.
- `test/modules/ventas/sale_attempt_durability_test.dart`.
- `test/core/offline/phase16_process_worker_test.dart`.
- `tool/phase16_native_attempt_probe.dart`.
- `scripts/uat/phase16-process-fixtures.cjs`, `phase16-process-bench.py`, `phase16-storage-chaos.py`.
- `scripts/uat/phase16-update-bank.iss`, `phase16-update-recovery-bench.ps1`, `phase16-package-verifier.ps1`.
- `scripts/uat/run-product-stock-integrity-smoke.ps1`, `product-stock-integrity-smoke.cjs`: opción clone explícita, conservando default.
- `scripts/uat/phase13-postgres-outage.cjs`: opción SIGKILL solo contenedor desechable.
- Este informe. Los paths lib/test/tool son relativos a apps/fulltech_app.

No se atribuyen aquí los demás archivos del git status acumulado. El runner
comercial y el updater C++ no se modificaron en F16. Metadata/mutex de compilación
solo en la copia ignorada .uat/n16, namespace FullPOSPhase16NativeUAT.

## 27. Fallos reproducidos

Opener anterior podía clasificar FULL/BUSY/IOERR/corrupción como recuperables y
resetear originales aun con copia incompleta. Ausencia de onDowngrade permitía
cambiar user_version99→3. Un POST remoto no tenía journal previo y podía dejar
resultado incierto tras morir el proceso. Backup activo copiaba archivos sucesivos.
Tests reprodujeron corrupción, FULL y la frontera de commit. El defecto WAL-reset
es exposición por versión documentada, no una carrera reproducida en esta máquina.

## 28. Correcciones y verificación focal

Windows/fail-no-fallback conserva y rethrow; no usa preferencias al fallarSQLite.
Downgrade por defecto rechazado. Journal previo en Windows Release y conversión
atómica; resultados inciertos bloquean nuevo POST. Backup API verificado antes
de migración; dependenciaSQLite3.52.0. No se rebajó ningún test, tenant ni
restricción de idempotencia. La instrumentación de cortes queda solo en tests.

## 29. Pruebas bloqueadas o no ejecutadas

Hyper-V sin permisos (B); host dedicado/UPS(C); checkpoint dentro de I/O;
IOERR físico/flush; cuota de volumen Windows; firma/publisher/cadenaUAC;
antivirus/SmartScreen reales; impresora/cajón; GUI histórica130/132; +133;
apagón físico PostgreSQL; web release final. No se intentó eludir permisos ni
declarar los tests unitarios sustitutos de esos ensayos.

## 30. Riesgos residuales y rendimiento

Corrupción arbitraria puede perder commits aun con integrity_check=ok. FULL no
repara hardware que miente al sincronizar. El journal reduce doble cobro pero
puede bloquear operación legítima hasta revisión; falta flujo supervisado en GUI.
Cotización/outbox en archivos distintos no obtuvo aquí prueba de atomicidad
cross-DB. Conservación de backups sin rotación puede crecer; no hay backup
empresarial externo. Binarios históricos no heredan estas protecciones.

500 commits FULL del banco Python: p503,4504ms,p9510,5341ms,máx57,8775ms,
CPU0,0625s. Es microbenchmark local, no throughput del POS ni SLA. No se atribuye
probabilidad numérica de pérdida ni se presenta carga sostenida empresarial.

## 31. FMEA

Probabilidad cualitativa: plausible/exposición observada/desconocida; severidad
crítica=dinero/datos, alta=bloqueo operativo; detectabilidad alta=error visible,
baja=puede quedar estado coherente incompleto. Dos tablas por ID forman una fila
lógica e incluyen todos los campos solicitados. GO es solo para alcance probado.

| ID/componente | Evento y causa | Probabilidad; severidad; detectabilidad | Efecto económico | Protección/prueba/resultado |
|---|---|---|---|---|
|R01 hardware|Apagón; caché/flush no durable|Desconocida;crítica;baja|Venta confirmada perdida|FULL observado;B/C bloqueados/no ejecutados|
|R02 SQLite|Proceso muere entre escrituras|Plausible;crítica;alta|Agregado parcial|Transacción;A–I20casos PASS|
|R03 SQLite|Disco lleno en venta/ACK|Observada;crítica;alta|Pérdida de pendientes|max_page_count real;rollback PASS|
|R04 SQLite|DB corrupta/header/página|Observada;crítica;alta|Archivo ilegible|Fail closed;corruptcopies PASS|
|R05 WAL|WAL roto o race/checkpoint|Exposición observada;crítica;baja|Estado anterior incompleto|3.52.0;WAL roto LIMIT;checkpoint interno NOT RUN|
|R06 backup|Copia incompleta/activa|Observada en diseño;crítica;baja|Restauración pierde dinero|Backup API/hash/integrity;tests PASS|
|R07 updater|Proceso termina reemplazando archivos|Observada;alta;alta|POS no inicia|Inno aislado3 etapas/reinstalar PASS|
|R08 API|API caída/red rechazada|Plausible;alta;alta|Cobro en espera|Outbox/grant;sync/timeout PASS|
|R09 PG|PG cae antes de commit|Observada;crítica;alta|Operación perdida o duplicada|SIGKILL clone/retry PASS|
|R10 red|Timeout de POST|Observada;crítica;media|Cliente desconoce resultado|Journal previo;tests PASS|
|R11 respuesta|Commit remoto sin ACK|Observada;crítica;baja|Repetición económica|Releasekill+replayigual PASS|
|R12 ventas|Nuevo cobro tras incierto|Plausible;crítica;media|Doble cobro|Hold actor antesPOST;probe PASS|
|R13 inventario|Replay de entrada/venta|Plausible;crítica;media|Doble stock|IDs/hash/unicidad;smokes PASS|
|R14 caja|Legacy sin turno de origen|Observada;crítica;alta|Caja equivocada|409 sin efectos;HTTP PASS|
|R15 producto|Producto nuevo reenviado|Plausible;alta;media|Producto duplicado|ID estable/dependencias;worker PASS|
|R16 outbox|Venta sin evento o líneas|Plausible;crítica;media|Venta huérfana|Transacción A–G PASS|
|R17 tenant|Actor cambia durante cobro|Plausible;crítica;media|Imputación a empresa ajena|Captura/verificación;test PASS|
|R18 reloj|Fecha alterada tras reinicio|Plausible;alta;media|Fecha/ventana incorrecta|Policy/sello/occurredAt;regresión;sinrelojhost|
|R19 licencia|Grant expira offline|Plausible;alta;alta|Venta no autorizada|Policy48h;tests;sinextensión|
|R20 permisos|Usuario sin permiso vende|Plausible;crítica;alta|Venta indebida|Backend403;test journal libera rechazo|
|R21 antivirus|Cuarentena del binario|Desconocida;alta;alta|POS indisponible|Sinprueba Defender/SmartScreen real|
|R22 Win32|Archivo abierto impide reemplazo|Observada;alta;alta|Instalación falla|Fixturelocked error5 PASS;noAV|
|R23 instalador|Instalación parcial/downgrade|Plausible;crítica;alta|App rota/schema alterado|Reinstalarbinario+schema99guard PASS|
|R24 impresión|Impresora falla tras venta|Plausible;alta;alta|Reemisión duplicada|Persistirantesretorno;tests ticket;sinhardware|
|R25 migración|Corte/fallo DDL|Plausible;crítica;alta|Cola ilegible|K rollback,v1backup PASS|
|R26 legacy|Binario/contrato no atestado|Observada;crítica;media|Operación rechazada|Inventario130/132;GUI noejecutada;133ausente|
|R27 espacio|WAL/backups crecen|Plausible;alta;alta|Disco sin espacio|Readerpin/release PASS;sinrotación|
|R28 cola|requires_action permanente|Observada;alta;alta|Cobros bloqueados|Visible hold;sin borrado;revisiónmanual|
|R29 dependencia|Producto/entrada previa falla|Plausible;crítica;alta|Venta sin stock coherente|Orden/IDs/syncsmoke PASS|
|R30 firma|Sustitución/paquete ajeno|Plausible;crítica;media|Código no autorizado|SHA/rutacanónica/signature-required;cadena firmada pendiente|

| ID | Residual y acción concreta | Prioridad | Decisión |
|---|---|---|---|
|R01|Hardware no validado; ejecutarB/C con inventario y UPS|P0|NO-GO general|
|R02|Sin corte físico; conservar alcance nivelA|P1|GO nivelA|
|R03|Falta cuota volumen/IOERR; preparar disco virtual acotado|P1|GO SQLite acotado|
|R04|Detección no recupera dinero; expediente/copia supervisada|P0|NO-GO recuperación integral|
|R05|Checkpoint en I/O pendiente; probar B y carreras multiwriter|P1|NO-GO garantía física|
|R06|Sin retención/externalización; definir política segura|P1|GO backup de migración|
|R07|Sin UAC/canal real; ejecutar paquete firmado aislado|P0|NO-GO updater integral|
|R08|Resultados ambiguos requieren revisión; mantener hold|P1|GO fixture|
|R09|Sin powerloss real PG; validar infraestructura aislada|P1|GO SIGKILL clone|
|R10|Posibles holds legítimos; procedimiento soporte|P1|GO prevención automática|
|R11|No autoreconciliación universal; verificar expediente|P1|GO fixture|
|R12|Cobro externo manual no controlado; formación/GUI|P1|GO bloqueo probado|
|R13|No todas combinaciones fiscales; preservar matriz|P1|GO fixtures|
|R14|Sin evidencia no recuperar; no inventar turno|P0|NO-GO legacy integral|
|R15|Distribución anterior sin protección nueva|P1|GO cliente nuevo probado|
|R16|Cotización crossDB no probada; ensayar cortes separados|P1|GO ventas probadas|
|R17|Sin degradar tenant; mantener tests|P1|GO fixture|
|R18|No certificado reloj físico; ensayo VM sin tocarhost|P1|GO policy automatizada|
|R19|Reinicio nativo48h nuevo no repetido; evidenciaF14 delimitada|P1|GO policy automatizada|
|R20|No asumir403 de proxies como commit; auditar canal final|P1|GO backend local|
|R21|Validar firmado con Defender/SmartScreen enVM|P1|NO-GO distribución|
|R22|No prueba antivirus; repetir con instaladorfirmado|P1|GO bloqueo fixture|
|R23|Clientesviejos no heredan guard; prohibir rollbackDB|P0|NO-GO rollback universal|
|R24|Reimpresión/cajón real pendiente|P1|NO-GO hardware|
|R25|No todos esquemas; ensayar130/132→final|P0|NO-GO migración histórica integral|
|R26|Obtener evidencia distribución y matriz auténtica|P0|NO-GO compatibilidad total|
|R27|Alerta/retención no implementadas; no borrarWAL|P2|NO-GO operación prolongada certificada|
|R28|Falta interfaz/procedimiento empresarial practicado|P1|GO conservación;NO-GO cierre integral|
|R29|Falla debe detenerdependientes; no regenerar IDs|P1|GO fixtures|
|R30|Sin cadena/publisher/UAC final; no permitir unsigned comercial|P0|NO-GO publicación|

## 32. GO/NO-GO por módulo

| Módulo/alcance | Estado |
|---|---|
|Motor ventas/productos/stock nuevo, durabilidad nivelA, fixtures UAT|GO acotado a evidencia|
|Conservación ante apertura corrupta/FULL y schema futuro|GO tests focales|
|Backup de migración consistente|GO tests focales; no backup empresarial|
|SQLite frente a apagón físico|NO-GO de certificación;B/C pendientes|
|Updater nativo integral/históricos/GUI/hardware|NO-GO|

## 33. Candidato Windows

NO-GO técnico integral. Build main UAT y reemplazo aislado no equivalen al
instalador comercial firmado ni al circuito histórico completo. Se conserva
namespace aislado, API local y updates deshabilitados en el candidato de prueba.

## 34. Piloto

NO-GO para clientes reales. Antes: paquete/hash final firmado, VM dedicada,
matriz130/132 real, backup/restore ensayado con pendientes posteriores, flujos
de resultado incierto operables y aceptación de caja/impresión con hardware.
La autorización para ejecutar ese piloto debe ser otra tarea explícita.

## 35. Distribución general

NO-GO. Además del piloto aprobado: evidencia del canal comercial, publisher y
SmartScreen, soporte/recuperación documentados, observabilidad de WAL/colas y
ejecución satisfactoria del plan físico representativo. No hay declaración de
compatibilidad total ni garantía absoluta de cero pérdida.

## 36. Acciones finales y respuestas A–L

Plan B/C pendiente, sin ejecutarlo en el host: VM/máquina dedicada autorizada,
disco virtual acotado, snapshots externos verificados y fixture único; registrar
hardware/controlador/OS/SQLite/PRAGMAs. Crear producto+20 y venta−4 con operationId
fijo, cortar alimentación solo del invitado/dispositivo antes/después de commit,
durante WAL/checkpoint/migración e instalación. Reabrir conservando DB/WAL/SHM,
verificar agregado/outbox/identidad/grant/turno, reconectar al clon y cotejar una
venta/un efecto/stock16/importe/turno. Ante fallo preservar conjunto y logs;
no resetear. Repetir con almacenamiento lleno acotado y paquete firmado. Definir
criterios y aprobar evidencia antes de autorizar piloto, sin inventar porcentajes.

| Pregunta final | Respuesta basada en evidencia |
|---|---|
|A Venta confirmada ante caída de proceso|Agregados probados nivelA sí; POST incierto queda hold antes de otro cobro. No garantía de todas las rutas de todo cliente|
|B Pérdida de alimentación|WAL+FULL solicitan durabilidad; hardware/flush/B/C no certificados|
|C RecuperaciónSQLite|Sí en20 fixtures; corrupción arbitraria puede ser irrecuperable o incompleta|
|D Pendientes|Preservados fixtures y filas manuales exactas; sin reset|
|E Sync sin duplicados|Sí en fixtures y probe remoto con ACK perdido; misma identidad|
|F Inventario|16 y efectos únicos en conciliación scoped|
|G Caja/turnos|Original y efectivo400 en probe; sin origen409; hardware pendiente|
|H Updater|Reemplazo Inno aislado conserva DB; circuito firmado/UAC/energía pendiente|
|I Versiones realmente ejecutadas|Nuevo probe Release14016 y main UAT; helper auténtico132 verify-only. No GUI completa130/132 ni133|
|J P0 pendientes|Recuperación física, cadena firmada/UAC, matriz histórica, recuperación corrupta integral/rollback seguro|
|K Habilitar piloto|Resolver P0 y aceptación GUI/hardware/conciliación; nueva autorización|
|L Distribución general|Piloto aceptado, canal/publisher/soporte/observabilidad y ensayos físicos aprobados|

[Atomicidad y límites del almacenamiento](https://www.sqlite.org/atomiccommit.html).
Las omisiones y bloqueos son requisitos pendientes, no PASS implícitos.
