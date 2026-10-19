# Offline Safe 48h — Fase 13 — compatibilidad y candidato Windows

Fecha: 2026-10-14. **NO-GO para cierre técnico integral y publicación**.
La incompatibilidad HTTP400 está comprendida y mitigada en el candidato; no se
elimina operationId. Persisten límites de validación de versiones y del estado
nativo durante actualización, y un FAIL verificado del contrato de ventas del
snapshot130 sin turno de origen (§11). HECHO = ejecutado; HIPÓTESIS = pendiente;
RECOMENDACIÓN = procedimiento futuro. No confundir contratos con binarios reales.

## 1. Resumen ejecutivo

HECHO: se reutilizó POST /auth/offline-emergency/authorize para negociar protocolo
explícito2. El backend comprueba expansión de esquema antes de anunciar las
capacidades de idempotencia. El cliente verifica compatibilidad antes de enviar
producto/stock con operationId, bloquea nuevas admisiones offline avanzadas si
falta evidencia y conserva la cola para reintentar con backend compatible.

Se probaron dos builds Windows reales en banco UAT, instalador Inno aislado,
interrupción/reanudación, DB/WAL/SHM vivos, migraciones sobre respaldos y caída
de PostgreSQL en un contenedor separado. Recuperación Flutter/SQLite posterior
a reemplazo de archivos: un producto, una entrada20, una venta4, stock16,
turno original y cero duplicados. Fixtures permanente/desconocida preservadas.

BLOCKED: binarios históricos identificados130/132/133; sesión nativa completa
que demuestre identidad/secure storage/sello/grant a través de actualización;
flujo comercial firmado completo. La declaración del propietario sobre las
pruebas manuales anteriores se conserva como evidencia del propietario, no
como ejecución GUI de este agente.

## 2. Estado inicial

Se contrastaron los cinco informes anteriores, documentación canónica aplicable,
Git, migraciones y scripts existentes. Se conservaron los cambios acumulados
sin commits ni descartes. Fase12 registraba1310 pruebas Flutter y751 backend.
El HTTP400 del backend base estaba probado en memoria; se reprodujo por HTTP
en esta fase. No se reconstruyó el sistema offline.

SQLite manual inicial: pending_actions1, offline_sales8, sale_items20,
inventory_intents20, cache_entries344, integrityok. Cotización
`quotes.create:local_quote_1791944878261619`: failed/permanent,41intentos.
Respaldo consistente SQLite Backup API: `.uat/evidence/phase13-manual-before.db`.
PostgreSQL pg_dump -Fc: `.uat/evidence/phase13-postgres-before.dump`.

## 3. Worktree y recursos

Exclusivamente `C:\src\fullpos-offline-safe-48h`, rama
`feature/offline-safe-48h`, base `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.
API46548/PG56548, DB `daleventa_offline_safe_48h_uat`, contenedor
`fullpos_offline_safe_48h_postgres`; guard y current_database verificados.

Clon caja/contratos: API46552, DB `daleventa_offline_safe_48h_phase12_uat`.
Clones de migración separados: `...phase13_migration_uat` y `...phase13_prisma_uat`.
Fallo PG: contenedor nuevo `fullpos_phase13_failure_postgres`, puerto56593,
DB `daleventa_offline_safe_48h_failure_uat`, API46554; etiqueta de fase verificada.
No se detuvo PostgreSQL manual ni Docker globalmente. No se conectó a producción,
no se usaron credenciales comerciales, no hubo push/merge/deploy ni cambios main.

## 4. Archivos modificados en Fase13

- apps/api/src/auth/auth.service.ts
- apps/api/src/auth/auth.service.spec.ts
- apps/fulltech_app/lib/core/auth/auth_repository.dart
- apps/fulltech_app/lib/core/offline/offline_emergency_policy.dart
- apps/fulltech_app/lib/core/offline/offline_emergency_validation_interceptor.dart
- apps/fulltech_app/lib/core/offline/sync_queue_service.dart
- apps/fulltech_app/test/core/offline/offline_backend_compatibility_test.dart (nuevo)
- apps/fulltech_app/test/features/catalogo/catalog_offline_repository_test.dart
- apps/fulltech_app/test/features/catalogo/catalog_offline_uat_integrity_test.dart
- scripts/uat/audit-phase11-flutter.cjs
- scripts/uat/run-sync-integrity-smoke.ps1
- scripts/uat/phase12-compatibility-smoke.cjs
- scripts/uat/phase13-baseline-http-contract.cjs (nuevo)
- scripts/uat/run-phase13-migration-clone.ps1 (nuevo)
- scripts/uat/run-phase13-failure-api.ps1 (nuevo)
- scripts/uat/phase13-postgres-outage.cjs (nuevo)
- scripts/uat/phase13-update-bench.iss (nuevo)
- scripts/uat/phase13-wal-proof.py (nuevo)
- este informe (nuevo).

No atribuir otros archivos heredados ni PNGs de suites existentes a Fase13.
Backups, paquetes, manifiestos y logs están bajo .uat ignorado. Sin migración
nueva ni cambio de esquema SQLite en esta fase.

## 5. HTTP400 reproducido

`node scripts/uat/phase13-baseline-http-contract.cjs`: PASS de reproducción.
Servidor HTTP aislado127.0.0.1:46553, cerrado al finalizar. DTO obtenido por
git show del baseline, SHA256
`a03b9399043ed732c242093053f22db9d92c69c60421c2530264bf450bbddf60`.

PATCH /products/uat-product/stock:

```json
{"delta":20,"reason":"UAT advanced","operationId":"c552deab-5468-430b-bace-e4a3982ebdd8"}
```

HTTP400, `property operationId should not exist`. Legacy
`{"delta":"20","reason":"UAT legacy"}` produce200 y transforma delta a20.
Evidencia `.uat/evidence/phase13-baseline-http-contract.json` incluye request,
status y respuesta, sin secretos. Es fixture HTTP del DTO/pipe reales, sin
ejecutar el backend completo antiguo ni modificar inventario.

## 6. Causa raíz

AdjustProductStockDto anterior no declara operationId. main.ts usa ValidationPipe
con whitelist=true, forbidNonWhitelisted=true, transform=true. Rechaza el campo
antes de ProductsService. El DTO candidato lo declara opcional string; no se
debilitó whitelist ni se añadió excepción global.

El cliente conserva UUID económico en primer intento/outbox/replay. El backend
nuevo guarda operation_id y operation_payload_hash en inventory_movements,
único por empresa/operación; producto usa identidad estable y create_payload_hash.
La respuesta de mutación continúa siendo el producto existente. No se alteraron
formas de respuesta de productos/stock, caja ni ventas.

## 7. Solución aplicada

El grant existente agrega capabilities: protocolVersion2, minimumClientProtocol2,
productOperationId, productPayloadHash, inventoryOperationId,
inventoryPayloadHash, stableProductIdentity, dependentSync. No se creó endpoint.
La última capacidad declara soporte para el protocolo del cliente que ordena
dependencias; el servidor no ejecuta una cola de dependencias por sí mismo.

Antes de emitir flags avanzados true, AuthService comprueba las tres columnas
requeridas y el índice de operación mediante metadatos SQL; mantiene controles
de sesión, usuario, empresa, licencia y allowedOperations. No lee datos de otra
empresa. No sustituye permisos por capacidades.

El interceptor nuevo negocia antes de POST /products y PATCH /products/:id/stock
con operationId; valida empresa/usuario/dispositivo y cambio de sesión durante
consulta. Sin endpoint o sin flags explícitos, no envía la mutación avanzada.
Genera error local recuperable OFFLINE_PROTOCOL_UNSUPPORTED y explicación
discreta. Desactiva fast-fail/retry HTTP para ese rechazo local: un servidor
incompatible no se anuncia globalmente como desconectado.

La cola conserva id, payload e idempotencyKey, reintenta después, sin borrar ni
marcar synced. No convierte un400 real del negocio en200. Si aparece otro400
real, sigue clasificación existente para revisión. No retira operationId.

## 8. Justificación de compatibilidad

Expand-and-contract: campos del DTO nuevos opcionales; grant conserva campos
v1 y suma capabilities. Grants viejos se leen, pero sin verificación explícita
no autorizan nuevas operaciones avanzadas. El JSON local agrega un booleano
sellado advancedProtocolVerified; snapshot antiguo lo interpreta false.
No borra caché ni outbox. Una evidencia incompatible retira ese booleano sin
reiniciar serverUtc/validUntilUtc ni conceder otras categorías.

Consultas y contratos online legacy sin campos avanzados siguen su ruta normal.
Las nuevas mutaciones que requieren la garantía avanzada esperan actualización
del servicio; no hay fallback silencioso al contrato sin identidad económica.
Ventas legacy no reciben una dispensa financiera: sin turno explícito conservan
409 LEGACY_MISSING_SESSION.

## 9. Contratos legacy

`phase12-compatibility-smoke.cjs` contra candidato/clon: producto y entrada sin
operationId aceptados, venta con turno aceptada y stock16; sin turno409;
barcode duplicado409 y conteo stale409. No acredita seguridad de reintentos
legacy sin identidad ni compatibilidad universal de clientes históricos.
El smoke de caja usa ahora productos únicos por corrida: no consume semillas
compartidas hasta agotarlas. Mantiene tres ventas/total360/turno original.

## 10. Contratos nuevos

Seis pruebas focales: flags explícitos, payload íntegro, grant sin capacidades,
endpoint404 sin ampliar48h, empresa incorrecta, rutas legacy sin negociación y
cola que se conserva y vuelve a enviarse al recuperar compatibilidad (algunas
aserciones comparten caso). También verifica no marcar circuito offline por
incompatibilidad. Backend: schema incompleto anuncia flagsfalse.

El chequeo se realiza también al sincronizar mediante el Dio de aplicación;
el ensayo Flutter real incorpora ese interceptor. La expiración bloquea nuevas
operaciones, no elimina pendientes; una conexión válida puede renovar grant
mediante el endpoint autorizado. Instalador no renueva48h.

## 11. Matriz A/B/C/D de versiones

| Par | Contratos realmente ejecutados | App antigua real | Estado/límite |
| --- | --- | --- | --- |
| A cliente anterior + backend anterior | DTO stock baseline6b3e38ed por HTTP, legacy200 | No | PASS contrato stock; BLOCKED conjunto auth/caja/sesión/etc. |
| B cliente anterior + backend nuevo | fixtures legacy HTTP candidato y PG, suites existentes | No | PASS contratos acotados; FAIL forma de venta130, BLOCKED binarios completos |
| C cliente nuevo + backend anterior | nuevo payload HTTP400; interceptor Dio ante404/grant anterior conserva cola | No | PASS control de incompatibilidad; no backend antiguo completo |
| D cliente nuevo + backend nuevo | Flutter/SQLite/interceptor/API/PG, Windows builds reales | B nativo inició almacenamiento; sin operación GUI | PASS técnico; límites nativos §16 |

La búsqueda de .exe/.zip130/132/133 se amplió a todo el worktree incluyendo
ignorados, excluyendo node_modules y .git: sin artefactos identificados. Sí se
localizaron snapshots verificables en Git:69dd871b declara1.0.6+130,
5278477e declara+132 y07664153 declara+133. El runner HTTP se ejecutó para los
tres: mismo DTOstockSHA, legacy200/nuevo400. Evidencias
phase13-baseline-http-contract-<revision>.json registran commit, versión y hashes.
No se inspeccionaron instalaciones comerciales ni se infiere despliegue real.

**FAIL de compatibilidad de ventas en el snapshot130**: su repositorio remoto
no transmite originCashSessionId;132/133 sí contienen esa referencia. Su payload
representativo con clientRequestId, saleOccurredAt y deviceFingerprint obtuvo
409 LEGACY_MISSING_SESSION contra el candidato/clon; cero ventas guardadas.
phase12-compatibility-smoke.json conserva la reproducción. No implica que todo
instalador comercial con etiqueta130 proceda de ese commit; faltan binarios.
No se activó FINANCIAL_LEGACY_COMPAT ni se asignó silenciosamente turno actual.
Sin evidencia del turno de origen no hay adaptación general que garantice no
reasignar una venta recuperada: ese invariante impide declarar compatibilidad
universal. Se requiere identificar cohortes y una transición autorizada que
transmita turno, o un adaptador con evidencia original verificable por operación.

## 12. Migraciones

Auditadas: 20261014113000_inventory_movement_operation_id (nullable TEXT e índice
único empresa/operación) y 20261014153000_offline_operation_payload_hash
(hashes nullable). Sin DROP/DELETE/UPDATE de datos ni campos nuevos obligatorios
para filas anteriores. UUID/índices existentes de ventas/caja preservados.

Dos ensayos separados desde phase11_postgres_before.dump:

- SQL exacto de ambas migraciones, clon ...phase13_migration_uat: PASS.
- `npx prisma migrate deploy`, clon ...phase13_prisma_uat: PASS,31 migraciones
  encontradas y aplicación de la pendiente20261014153000; ledger gestionado por Prisma.

Conteos tenant antes/después: productos6, ventas51, movimientos74. Hashes
históricos continúan null; no se inventaron hashes retrospectivos. Evidencia:
`.uat/evidence/phase13-migration-clone.json` y
`phase13-prisma-migration-clone.json`. El esquema expandido conserva columnas
legacy; ejecución completa de backend antiguo contra él: NOT RUN. No se acredita
rollback destructivo: conservar expansión al volver código anterior, con
pendientes avanzados retenidos hasta restaurar backend compatible.

## 13. Idempotencia e integridad financiera

Smoke HTTP + PG: cinco concurrentes por producto/entrada/venta, replays y payload
divergente409; producto4334c0a7-cd17-482d-a539-9f44da966411, stock16,
una entrada, una venta, dos movimientos. Evidencia
`.uat/evidence/phase11-1792000053954-product-stock-integrity.json`.

Caja en clon: corrida fase8-1792000074235, tres ventas únicas, total360,
un turno original después de cierre/reapertura, tres líneas/movimientos;
insuficiencia409. `.uat/evidence/phase13-sync-smoke-final.json`.
No se cerró ni reasignó el turno manual104ffcf3-5e0e-4ecb-9ee1-ba8ec1ec23ca.

## 14. SQLite

Versión local3 preservada; Fase13 no agrega migración SQLite. Se usó una DB
representativa existente y respaldos por Backup API, no copia .db en vivo.
El build A abrió el almacenamiento del banco (trace); B lo reabrió tras instalar.
Cinco acciones antes/después de instalación y recuperación tuvieron filas
completas idénticas. El ensayo con conexión WAL viva verificó hashes DB/WAL/SHM
idénticos durante instalación real del fixture, y fila comprometida amount400.
`.uat/evidence/phase13-live-wal.json`.

Banco SQLite bloqueada/read-only: errores5/8 esperados y fuente preservada.
No equivale a demostrar recuperación completa de una pantalla ante disco lleno.
No se cambió reloj de Windows ni se hizo corte eléctrico.

## 15. PostgreSQL

Reconciliación de actualización: producto bbed31f9-96b3-47fa-82d4-a1553d197efc,
entrada56954d62-dd9d-4c41-9303-6cf1684cc27f, venta
sale_req_1791999122843120, turno original, entrada20/venta4/stock16, una fila de
cada efecto. Tres confirmaciones descartadas tras commit. Archivo
`.uat/evidence/phase13-update-postgres-reconciliation.json`.

Caída PG real: solo contenedor nuevo56593. API retornó500, cero productos antes
de recuperar. Reintentos devolvieron500 y luego201; replay adicional mantuvo
un producto. `.uat/evidence/phase13-postgres-outage.json`. Pool puede necesitar
un reintento tras recuperación; no se oculta como éxito instantáneo. La prueba
HTTP de caída y las pruebas SQLite de conservación se distinguen entre sí.

## 16. Updater e instalador aislados

Banco `.uat/phase13-update-bench`: A archivado del build real Fase11;
B compilado con cambios de protocolo. Ambos declaran1.0.6+140: se distinguen
por SHA256 y manifiesto, no por una versión visual inventada.

- A app.so D4D32687EBC1D2ACE9851FE00AE2213EBB04186C0E1446AACA7568DFF5D2F3DA.
- B inicial7996AD7097E1DFFCFF78622A67C116D1A71C073B636C65724D1C81B657CB0649.
- B finalF1D0F6D2F40F95D81705B2BEBB8EB3906124D68CF2BC99353A4BC11AB13AAA7D.

Último B incorpora protección para que el rechazo de compatibilidad no active
el circuito offline. Se reconstruyó y se reinstaló conservando el hash completo
de la DB y las dos fixtures pendientes restantes.

Instalador de fixture Inno separado: destino fijo dentro .uat, privilegioslowest,
sin shortcuts, sin registro de desinstalación ni borrado de carpetas mutables.
No se modificó installer/setup.iss. FullposUpdater real se ejecutó SOLO
--verify-only (hash/ruta/política UAT); no se ejecutó RunInstaller comercial,
su elevación runas ni su mutex comercial. Inno fixture terminó0.

Se interrumpieron únicamente procesos del instalador fixture en un punto
controlado de reemplazo y se reinstaló con éxito. Cinco filas pendientes
permanecieron idénticas. WAL vivo es un ensayo separado, no se atribuye al
instante de interrupción del primer ensayo. Evidencias phase13-real-update.json,
phase13-live-wal.json y phase13-final-candidate-install.json.

Los procesos A/B se iniciaron en el banco y abrieron SQLite; al estar ocultos no
se operaron visualmente. Sin ventana principal accesible para cierre, se detuvo
solo el proceso del banco identificado, con respaldo consistente conservado.
No se presenta como cierre GUI normal. La reanudación económica posterior fue
por repositorios Flutter/SQLite automatizados, no por interacción nativa del cajero.

Identidad/grant/log del descriptor de fixture se preservaron. **No demuestra
identidad del plugin, HMAC/DPAPI/secure storage y grant nativos entre versiones**.
Falta esa sesión real y el flujo comercial firmado completo en UAT: BLOCKED.
El paquete bajo .uat es laboratorio, no instalador distribuible.

## 17. Operaciones pendientes e históricos

Banco: producto, entrada recuperable y venta preservaron id/payload/empresa/
usuario/turno. Tras reinstalar, la cola Flutter perdió tres confirmaciones,
reintentó y confirmó solo esos tres efectos. Fixture quotes.create permanente
y legacy.unknown quedaron intactas, sin falsa sincronización. Formato desconocido
preservado no acredita que toda cola legacy pueda procesarse.

Manual: 1 pendiente histórico,8 ventas,20líneas,20intenciones,344cachés,
integrityok. Fila completa de cotización idéntica a respaldo. Auditor PG volvió
a confirmar8ventas/20líneas/20movimientos/totales/turnos. phase13-manual-preservation.json
y phase11-preservation-postgres.json. Cotización original no se borró, reenvió,
reencoló ni marcó synced. Ensayo de copia en clon no autoriza recuperar original.
Recuperación requiere revisión de equivalentes remotos y permiso específico;
quotes no tiene ledger idempotente equivalente. Candidatos por nombre/teléfono/
total en base manual=0, sin garantía universal de ausencia de duplicados.

## 18. Regresiones ejecutadas

| Comando real | Resultado |
| --- | --- |
| flutter analyze --no-pub | PASS; repetido tras cambios |
| flutter test --no-pub | PASS1316/3omitidas en ambos pases; final03:43, phase13-flutter-final.log |
| flutter test --no-pub test/core/offline/offline_backend_compatibility_test.dart | PASS6, repetido con circuito offline |
| flutter test --no-pub test/features/catalogo/catalog_offline_repository_test.dart test/core/offline/offline_emergency_policy_test.dart | PASS14 |
| FULLPOS_PHASE11_UAT=true + flutter test --no-pub test/features/catalogo/catalog_offline_uat_integrity_test.dart | PASS2 preparación, PASS2 reanudación y PASS2 final completo; raíces desechables, modos explícitos |
| npm --workspace apps/api test -- --runTestsByPath src/auth/auth.service.spec.ts | PASS15 |
| npm --workspace apps/api test | PASS74suites/752pruebas,8omitidas |
| npm run api:build | PASS Prisma generate5.22.0 + TypeScript5.9.3 instalado |
| npx prisma validate | PASS |
| . ./scripts/build/build_windows_uat_release.ps1 -SkipPubGet -WindowsAppRoot <raíz UAT> | PASS buildsB yBfinal;82.2s último |
| node scripts/uat/phase13-baseline-http-contract.cjs | PASS HTTP400/legacy200 |
| node scripts/uat/phase13-baseline-http-contract.cjs 69dd871b / 5278477e / 07664153 (tres invocaciones) | PASS contratos stock snapshots130/132/133; no binarios |
| . ./scripts/uat/run-phase13-migration-clone.ps1 | PASS SQL sobre clon |
| . ./scripts/uat/run-phase13-migration-clone.ps1 -PrismaDeploy | PASS Prisma sobre otro clon |
| . ./scripts/uat/run-sync-integrity-smoke.ps1 -DisposablePhase12 | PASS final; primer intento stockfixture agotado, §19 |
| . ./scripts/uat/run-product-stock-integrity-smoke.ps1 | PASS |
| . ./scripts/uat/run-updater-preservation-bench.ps1 | PASS banco heredado201001/201002 |
| . ./scripts/uat/run-sqlite-failure-bench.ps1 | PASS5/8 |
| node scripts/uat/phase12-compatibility-smoke.cjs (envclon46552) | PASS |
| node scripts/uat/phase13-postgres-outage.cjs (perfil UAT cargado) | PASS contenedor separado |
| ISCC.exe scripts/uat/phase13-update-bench.iss | PASS paquetes laboratorio |
| FullposUpdater.exe --verify-only ... --allow-unsigned | PASS por ExitCode0 esperado con Start-Process -Wait |
| python scripts/uat/phase13-wal-proof.py --run 2 | PASS hashesDB/WAL/SHM |
| FULLPOS_PHASE13_UPDATE_AUDIT=true + node scripts/uat/audit-phase11-flutter.cjs | PASS conciliaciónupdate |
| node scripts/uat/audit-phase11-preservation.cjs | PASS históricos |
| git diff --check | PASS, avisos LF→CRLF |

Comandos Flutter desde apps/fulltech_app; backend/scripts desde worktree,
Prisma validate desde apps/api. Logs phase13-flutter*.log, phase13-jest.log,
phase13-windows*-build.log y artefactos nombrados bajo .uat/evidence.
Mensajes de fallback API_BASE_URL heredados en tests no prueban llamadas remotas:
transportes de ensayos reales se construyen explícitamente con localhost.

Ensayo final completo: corrida phase11-flutter-1792000757581, producto
9ff72d7d-3a73-4deb-a8e5-dfcb8dec307c, tresACKperdidos, cero pendientes del
escenario nuevo, stock16, reapertura y grant vencido de fixture; auditor PG PASS.
La ventana final observada: PID33252, worktree correcto, título[UAT], respondingtrue;
API46548/health/db devolvió statusok/dbok. No acredita interacción visual.

Herramientas: terminal PowerShell7, git CLI, apply_patch, Flutter/Dart,
npm/Jest/Prisma, NodeHTTP/ValidationPipe, Docker/PostgreSQL, PythonSQLite,
ISCC y verificación nativa del updater. Sin subagents, Context7, Figma,
Playwright ni operación visual de Windows en esta fase. Versiones instaladas
conocidas; no se introdujo patrón externo ni dependencia nueva.

## 19. Fallos encontrados

-400 reproducido por campo no declarado, sin pérdida de operación.
-Snapshot130 no transmite turno:409 en candidato, sin escritura. Bloqueante
 de compatibilidad de esa forma de request; no corregido debilitando finanzas.
-Smoke heredado agotó semilla fija en clon: tercera venta409; dos ventas fixture
 previas quedaron preservadas, sin reset. No fue fallo del stock de negocio.
-Fixture que duplicaba clave de outbox recibió UNIQUE: protección correcta;
 transacción fallida no cambió datos. No se debilitó el índice.
-Puerto56549 ocupado: se rechazó arranque, no se tocó proceso ajeno; se usó56593.
-pg_isready por socket aceptó servidor temporal de inicialización y restore fue
 rechazado al apagarse ese servidor. Se verificó DBvacía antes de reanudar.
-Prisma tras reiniciar PG devolvió un500 adicional antes de201; reintento explícito.
-Verificación de exe GUI con $LASTEXITCODE heredado dio falso fallo pese a
 RESULT=SUCCESS; se midió ExitCode real con Start-Process -Wait, resultando0.
-PTY no pudo crearse (Access denied); no se desactivó protección.
-Primer WAL helper venció esperando señal; no se contó PASS. Se repitió con otra
 DB desechable y señal específica; PASS real antes de cerrar conexión.
-Procesos nativos ocultos no ofrecieron MainWindowHandle para cierre GUI;
 tampoco acreditan login/operación manual. Respaldos y terminación solo del banco.

## 20. Fallos corregidos

Guard explícito de capacidades, evidencia local sellada compatible con snapshots
viejos, cola recuperable y mensaje discreto. Rechazo local no afecta conectividad
de otras rutas. Smoke crea productos propios por corrida. Readiness PG ahora usa
TCP127.0.0.1 para distinguir servidor final del temporal. Ensayo de outage espera
recuperación con mismooperationId, sin falsificar éxito del primerreintento.
Fixtures y runners se corrigieron sin debilitar reglas financieras.

## 21. Pruebas no ejecutadas

Binarios130/132/133 completos; backend antiguo completo sobre esquema expandido;
instalador/updater comercial firmado completo; identidad/secure storage/sello/
grant nativos A→B y sincronización desde GUI durante esa transición; muerte
abrupta exactamente entre commit remoto y ACK SQLite en proceso Windows;
impresora/cajón y cortes físicos de disco; emisión fiscal real. No se alteró
eCF/Alanube ni se usaron clientes como laboratorio.

## 22. Riesgos residuales

HIPÓTESIS: referencias temporales de producto/clientes en colas legacy pueden
necesitar adaptación específica; faltan fixtures verificables, no borrarlas ni
reidentificarlas. Registros históricos sinhash no permiten comparar todo el
payload original. Secure storage/sello mantienen límites heredados ante control
total del dispositivo o almacenamiento seguro no disponible. Una capacidad
anunciada no sustituye controles económicos/tenant del endpoint.

El backend debe actualizarse antes del cliente. Con backend anterior, las
funciones avanzadas quedan bloqueadas de forma segura; ello no equivale a
compatibilidad operativa completa del nuevo POS contra cualquier backend viejo.
Antes de ese orden de publicación se debe resolver la cohorte cuyo contrato no
envía turno, identificada en el snapshot130. No activar la compatibilidad
financiera global como sustituto de evidencia del turno original.
Los builds de laboratorio comparten número140: antes de una distribución futura
se necesita versión monotónica autorizada y proceso oficial de empaquetado.

## 23. GO/NO-GO técnico y matriz de aceptación

**NO-GO técnico integral**: control delP0 y conservación tienen PASS técnicos,
pero no se acredita compatibilidad universal ni toda la identidad nativa del
updater. Matriz: C=candidato protocolo2, R=baseline6b3e38ed, A=buildFase11.

| Área | Estado | Evidencia / versión real | Riesgo / acción pendiente | Bloquea publicación |
| --- | --- | --- | --- | --- |
| Autenticación | PASS técnico | loginHTTP/JestC | app antigua real pendiente | Sí por matrizlegacy |
| Sesión | BLOCKED integral | scope/401testsC | sesión nativa update | Sí |
| Licencias | PASS técnico | grant/JestC | no validación comercial requerida aquí | No adicional |
| Ventas online | PASS explícito / FAIL130 | HTTPclonC, turno explícito;130sin turno409 | resolver cohorte y binariolegacy | Sí |
| Ventas offline | PASS técnico | Flutter/SQLite/PGC | GUItransición no ejecutada | Sí por updater |
| Productos offline | PASS técnico | guard+create únicoC | backend antiguo no habilita | No adicional |
| Entradas offline | PASS técnico | delta20/idempotenciaC | mensaje GUIincompatibilidad | Sí por aceptación nativa |
| Inventario | PASS técnico |16/45/409C | conflictos GUI | Sí por aceptación |
| Caja | PASS técnico |360/3movimientosC | clientes antiguos reales | Sí |
| Turnos | PASS técnico | turno originalC | legacy sin turno409 deliberado | Sí por matrizlegacy |
| Clientes | BLOCKED integral | tests existentesC | dependencias y versiones reales | Sí |
| Cotizaciones | BLOCKED recuperación | copia390clonC, original intacto | permiso específico para original | Sí para cierre histórico |
| Historial | PASS preservación |8manuales/20líneas, fixtureupdateC | GUItransición | Sí por updater |
| Tickets | NOT RUN hardware | suitesC; sin cambio de impresión | aceptación física según alcance | Condicional |
| SQLite | PASS técnico | v3real, BackupAPI, WALvivoA→B | otras versiones locales representativas | Sí por legacy |
| PostgreSQL | PASS | cloneDDL+Prisma+outageC | sin ejecución productiva | No adicional |
| Sincronización | PASS técnico | tresACKperdidos,16C | worker nativo con sesión real | Sí |
| Idempotencia | PASS contratosC |5concurrentes/409/replay | sin garantía para legacy sinID | Sí por matrizlegacy |
| Multiempresa | PASS técnico | scope/tenantJest/guardC | pares reales de versiones | Sí por matrizlegacy |
| Backend nuevo | PASS técnico | build/schema/Jest/smokesC | validación con binarios anteriores | Sí |
| Backend antiguo | BLOCKED conjunto | DTOHTTPR200/400 | APIcompleta con esquema nuevo | Sí |
| Windows nuevo | PASS build | BfinalSHAverificado | sesión nativa actualización | Sí |
| Windows antiguo | FAIL contrato130 / BLOCKED binarios | snapshots130/132/133 y A real del banco | resolver origen del turno130 y artefactos referencia | Sí |
| Instalador | PASS fixture / BLOCKED comercial | Inno aisladoBfinal0 | firmado y flujo oficialUAT | Sí |
| Updater | PASS parcial / BLOCKED integral | nativeverify0+Inno+WAL | identidad/grant nativos y flujo completo | Sí |
| Recuperación | PASS técnica parcial | PG500→201, interrumpirinstalación | proceso commit/ACK nativo | Sí |
| Expiración48h | PASS técnica / BLOCKED nativa | reloj inyectadoC; no extensión por incompatibilidad | grant real A→B | Sí |

## 24. GO/NO-GO publicación y plan futuro

**NO-GO de publicación.** Plan documental, no ejecutado:

1. Backup verificado y restauración ensayada; acordarRPO/RTO.
2. Migraciones aditivas, sin retirar columnas/contratos legacy.
3. Backend compatible primero; verificar capabilities2 con esquema listo.
4. Ejecutar versiones antiguas reales y documentar DTO/turnos admitidos. No
   ejecutar ese despliegue mientras la cohorte130sin origen siga sin solución
   autorizada; el orden expand-and-contract presupone esa compatibilidad.
5. Confirmar permisos, identidad/grant nativos y pendientes A→B.
6. Asignar versión monotónica y generar paquete por proceso oficial autorizado.
7. Piloto en dispositivo expresamente autorizado, sin sustituir base real porfixture.
8. Monitorear por empresa, operación y turno: pendientes, conflictos, duplicados.
9. Expandir gradualmente solo tras aprobación.
10. Rollback operativo: conservar expansión y outbox; volver binario solo con
    contratos probados. No prometer que restaurar una DB anterior preserve
    escrituras posteriores. Sin DROP/reset automático ni falsa reversibilidad.

No se publicó paquete, canal, tag, PR ni anuncio a clientes.

## 25. Pasos exactos restantes

1. Aportar builds UAT verificables130/132/133 u otras versiones realmente usadas;
   contrastarlos con snapshots y resolver la forma130sin origen antes de aprobar
   backend. Ejecutar matriz completa con esquema expandido; no usar clientes comerciales.
2. Ensayar sesión nativa A→B con identidad, secure storage, sello, grant y vencimiento
   observados; operar/sincronizar desde la app real en ese banco. El descriptor
   de laboratorio no reemplaza esa prueba. Conservar evidencia sin secretos.
3. Ejecutar flujo oficial de updater/instalador firmado exclusivamenteUAT y validar
   fallo/recuperación del proceso, con backups y datos ficticios.
4. Decidir recuperación de la cotización original mediante autorización separada.
5. Revisar informe y riesgos, asignar versión de publicación y solicitar aprobación
   futura de piloto/publicación con resultado concreto. No avanzar automáticamente.

El UAT manual original permanece conservado; no mezclar sus pendientes con
fixtures del banco. La aprobación de esta documentación no autoriza producción.
