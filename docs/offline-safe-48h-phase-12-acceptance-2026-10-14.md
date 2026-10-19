# Offline Safe 48h — Fase 12 — aceptación Windows

Fecha: 2026-10-14. **Fase parcialmente completada. NO-GO para cierre integral y producción.**
HECHO identifica evidencia ejecutada; HIPÓTESIS identifica riesgos pendientes;
RECOMENDACIÓN identifica el procedimiento propuesto. Los PASS técnicos no acreditan GUI ni hardware.

## 1. Resumen ejecutivo

HECHO: integridad producto inicial 0 → entrada +20 → venta de 4 → stock 16,
reintentos concurrentes, pérdida de tres confirmaciones, reapertura SQLite y
sincronización con grant vencido de prueba pasaron. Se preservaron el turno
original y los pendientes históricos. API build y Prisma validate pasaron.
Jest: 74 suites, 751 pruebas PASS, 8 omitidas. La regresión Flutter final se
documenta en §15.

El UAT visual Windows no se ejecutó: Computer Use devolvió
`Computer Use native pipe is unavailable ... The system cannot find the file specified. (os error 2)`.
La ventana UAT quedó abierta para el operador. No se atribuye al agente la
aceptación manual histórica del usuario.

HECHO: existe incompatibilidad comprobada con el DTO de inventario del backend
base 6b3e38ed: `operationId` produce HTTP 400. Falta validar binarios anteriores
y transición real del updater en UAT. No se autoriza distribución ni producción.

## 2. Estado inicial y cambios previos

Se consultaron los cuatro informes solicitados y el estado Git. Los pendientes
de fases anteriores se conservaron. Algunas conclusiones del final-sync-audit
(idempotencia producto/stock y build bloqueado) quedaron superadas por Fase 11;
no se interpretaron como defectos todavía ausentes.

`.uat/evidence/phase12-initial-manifest.json` registra SHA256 de los 23 archivos
listados en Fase 11, incluidos su informe y la migración no destructiva. El
contenido de aplicación/API sigue siendo el candidato Fase 11; Fase 12 amplía
pruebas y herramientas UAT. El único archivo de aquel manifiesto modificado
intencionalmente es `catalog_offline_uat_integrity_test.dart`.

SQLite inicial: 1 pendiente, 8 ventas, 20 líneas, 20 intenciones de inventario,
344 entradas de caché, integrity_check=ok. Respaldo consistente:
`.uat/evidence/phase12-manual-backup-20261014T164838Z.db`.
PostgreSQL: `.uat/evidence/phase12-postgres-before.dump` mediante pg_dump -Fc.

## 3. Worktree y aislamiento

Worktree `C:\src\fullpos-offline-safe-48h`, rama `feature/offline-safe-48h`,
base `6b3e38ed`. No se modificó production-main, producción, instalaciones
comerciales, licencias reales ni canales. Sin push/merge/deploy.

API manual 127.0.0.1:46548; PostgreSQL 127.0.0.1:56548;
contenedor `fullpos_offline_safe_48h_postgres`; identidad SQL confirmada
`daleventa_offline_safe_48h_uat`. Guard Assert-UatEnvironment ejecutado.

Para cierre/reapertura de caja y envío de la copia de cotización se creó una
base separada `daleventa_offline_safe_48h_phase12_uat` restaurando el respaldo,
API 127.0.0.1:46552. No hubo DROP, reset ni restore sobre la base manual.
El script rehúsa sobrescribir un clon existente y verifica current_database().

## 4. UAT Windows

Proceso final observado: PID 24488, responding=true, título
`FullPOS Cloud - Sistema de facturacion [UAT]`, ejecutable bajo este worktree.
Se reabrió únicamente cuando la consulta de procesos confirmó ausencia de la
instancia anterior. Lanzador `run-windows-portable.ps1 -SkipBuild`:
root `.uat/windows-app-root`, API 46548, updater deshabilitado por compilación.
app.so conserva SHA256 de Fase 11:
`D4D32687EBC1D2ACE9851FE00AE2213EBB04186C0E1446AACA7568DFF5D2F3DA`.
No se reconstruyó ni cambió código Flutter de aplicación en esta fase.

BLOCKED: login, pantalla, turno y grant mostrados al operador; creación/entrada/
venta desde GUI; reinicio visual offline; sincronización visible. Identificar
un proceso y su título no prueba haber operado visualmente.

## 5. Flujo completo producto +20 → venta -4

Prueba automatizada real: repositorios Flutter, SQLite FFI, cola y HTTP local,
root desechable distinto del manual. Producto nuevo stock 0; entrada delta +20;
venta cash 400 por cuatro unidades. Tres pendientes sobrevivieron a reapertura.
Durante desconexión simulada del adaptador, dependencias no intentaron stock/
venta antes del producto. No es una desconexión física de la API ni GUI.

Evidencia: `.uat/phase11-flutter-client-*/integrity-result.json`, corrida
`phase11-flutter-1791997025390`; producto
`e1ddbd45-f046-481b-ad44-eb3eaffe3bb0`.

## 6. Reinicio offline

PASS técnico: store.closeForTesting(), reapertura SQLite y reconstrucción de
servicios conservaron identidades de las tres acciones y producto stock 20.
Se repitió reapertura después de cada ciclo que pierde confirmaciones.
BLOCKED: terminación del proceso Windows entre commit remoto y ACK local, y
cerrar/reabrir la ventana real con API detenida. No hubo corte eléctrico.

## 7. Sincronización

PASS técnico: la cola terminó vacía, venta local `synced`, tres respuestas
descartadas después de commits remotos. Reaperturas no duplicaron efectos.
El grant de la prueba se venció en preferencias simuladas después de guardar
las operaciones: bloqueó nuevas ventas offline, conservó tres acciones y
permitió sincronizar. No se cambió reloj, grant manual ni vigencia real.

La prueba de error permanente independiente conservó el fixture de cotización
failed/permanent con 41 intentos y su payload, y procesó otra venta sin llamar
el handler de la cotización. No manipuló la operación histórica.

## 8. Conciliación PostgreSQL

`audit-phase11-flutter.cjs`: PASS tenant-scoped; un producto, una entrada +20,
una venta de cuatro unidades/400, una línea, dos movimientos, stock 16.
Turno `104ffcf3-5e0e-4ecb-9ee1-ba8ec1ec23ca` conservado.
Evidencia `.uat/evidence/phase11-flutter-postgres-reconciliation.json` (nombre del
auditor heredado; contiene corrida Fase 12).

Preservación manual: fila completa de cotización idéntica al backup; cuentas
SQLite iniciales idénticas. `.uat/evidence/phase12-preservation-final.json`.
Auditor PostgreSQL confirmó 8 ventas manuales, 20 líneas, 20 movimientos,
totales y turnos originales. `.uat/evidence/phase11-preservation-postgres.json`.
Estas ventas históricas no se confundieron con las fixtures nuevas.

## 9. Idempotencia

`run-product-stock-integrity-smoke.ps1`: PASS HTTP + PostgreSQL, cinco solicitudes
concurrentes por producto/entrada/venta, un efecto por operación. Replays con
payload divergente devuelven 409 y no alteran stock. Producto
`8f527761-fe4f-4a93-a864-770951ac5475`, entrada
`9cdd5413-2b5f-4e79-b4d0-51acad88aa69`, venta
`82d2836c-0880-40a8-8048-bef8b111b1d0`.
Evidencia `.uat/evidence/phase11-1791996826698-product-stock-integrity.json`.

## 10. Reintentos

Se detuvieron únicamente watcher/listener del worktree y listener del clon
identificados, para liberar Prisma durante build. PostgreSQL permaneció vivo.
Se restauraron ambas APIs. Una petición de health durante la pausa venció en
2 segundos; no se presenta como prueba de recuperación de una operación.
Replays reales de producto, entrada y venta después del reinicio de backend
mantuvieron la misma venta, stock 16 y dos movimientos.
`.uat/evidence/phase12-post-backend-restart.json`: PASS.

Smoke de caja en clon: tres ventas, tres líneas, tres movimientos, total360,
un turno original, sin duplicados antes/después de cierre y nuevo turno.
Stock insuficiente devuelve409. `.uat/evidence/phase12-sync-smoke.json`; repetición
posterior al build: `.uat/evidence/phase12-sync-smoke-final.json`, corrida
`fase8-1791997981301`, mismo total360 y tres efectos únicos, clon identificado.
El script ahora exige `-DisposablePhase12` y concilia por company_id.

## 11. Recuperación ante fallos

| Caso | Estado técnico | Evidencia / límite |
| --- | --- | --- |
| A backend antes de recibir | BLOCKED físico; PASS adaptador | error connectionError conserva cola; falta repetir con API detenida y app real |
| B commit con respuesta perdida | PASS | tres confirmaciones descartadas tras persistencia, conciliación PG |
| C cerrar tras guardado local | PASS SQLite; BLOCKED proceso | tres acciones sobreviven cierre store |
| D reiniciar antes de sync | PASS servicios; BLOCKED Windows | store y handlers reconstruidos |
| E reiniciar tras commit antes ACK | PASS store tras error; BLOCKED muerte abrupta | reapertura tras pérdida ACK, no kill en instante crítico |
| F SQLite bloqueada | PASS banco | locked=5/read-only=8; falta flujo completo GUI y recuperación de escritura |
| G HTTP500 | PASS unitario | mensaje seguro, pending y backoff en sync_queue_service_test |
| H sesión expirada | PASS unitario | 401 auth_blocked sin marcar synced; falta renovar sesión GUI |
| I grant vencido | PASS integración | fixture vencido, conserva tres y sincroniza; reloj real intacto |
| J padre pendiente | PASS integración | entrada/venta esperan producto antes de dispatch |
| K permanente independiente | PASS unitario SQLite | fixture preservado, otra venta sincroniza |
| L código duplicado | PASS HTTP clon |409; falta verificar mensaje visual y outbox en GUI |
| M cambio remoto stock | PASS HTTP clon | conteo stale409 sin movimiento; incremento20 aplica una vez sobre25→45 |

## 12. Autorización 48h

PASS técnico: endpoint dedicado con empresa/usuario/dispositivo/categorías,
pruebas de ausencia de validación, 47h59m, vencimiento48h, reloj hacia atrás,
dispositivo distinto, respuesta dedicada, sello manipulado y duración >48h.
Jest verifica permisos/licencia de emisión; no se alteró enforcement.
Limitación heredada: la seguridad real de secure storage/sello en cada equipo
requiere aceptación; tests no prueban resistencia ante control total del PC.

Inventario mantiene intención: entrada delta positiva autorizada offline;
conteos absolutos/salidas nuevas requieren conexión, sin convertirlos en entradas.
Prueba del callback incremental incluida en Flutter. No se cambiaron pantallas.

## 13. Compatibilidad legacy

| Combinación | Estado | Evidencia / pendiente |
| --- | --- | --- |
| DTO anterior + backend candidato | PASS parcial / BLOCKED binario | producto/stock sin operationId y venta con turno explícito aceptados en clon; sin turno409 LEGACY_MISSING_SESSION |
| Cliente nuevo + backend base6b3e38ed | FAIL contrato stock | DTO anterior no declara operationId; ValidationPipe real whitelist/forbidNonWhitelisted genera400 |
| Cliente nuevo + backend desplegado actual | BLOCKED | no se consultó producción; no asumir que coincide con base |
| Cliente nuevo + backend candidato | PASS técnico / BLOCKED GUI | Flutter/SQLite/API/PG conciliados |
| SQLite manual existente + candidato | PASS preservación / BLOCKED uso GUI | integrityok, cuentas/fila intactas; app abierta sin reset |
| Outbox legacy + candidato | PASS parcial / BLOCKED matriz | ventas históricas conciliadas; fixture stale y permanente pasan; falta referencia de producto temporal y clientes legacy |

Contrato base probado en memoria desde git show y Nest ValidationPipe, evidencia
`.uat/evidence/phase12-baseline-contract.json`. No prueba backend comercial.
Se localizaron builds candidato y worktrees136–141; la búsqueda dirigida en
`.uat`, build y scripts no encontró binarios identificados130/132/133. No se
examinaron instalaciones comerciales. Combinaciones exactas130/132/133 y otras
transiciones quedan BLOCKED hasta aportar builds UAT de referencia verificables.
Sin operationId no se acredita deduplicación de reintentos legacy.

RECOMENDACIÓN: backend compatible antes de distribución del cliente y pruebas
de ambos contratos en clon; nunca retirar operationId para ocultar el400.

## 14. Updater e instalador

PASS limitado del banco: builds ficticios201001/201002, hashes de DB/WAL/SHM
iguales, un pendiente, identidad de venta/turno/total y .part/.ready conservados.
Root `.uat/updater-preservation-bench-20261014125346`.
No ejecuta actualización firmada ni transición de binarios reales. Sello,
installationID, grant, logs y migración durante instalación: BLOCKED transición
real. Instalador: NOT RUN por alcance; no se tocó updater comercial.

## 15. Regresiones y comandos ejecutados

| Comando (worktree autorizado) | Resultado |
| --- | --- |
| flutter analyze --no-pub (apps/fulltech_app) | PASS; repetido después de ampliar tests |
| flutter test --no-pub (apps/fulltech_app) | Primer pase PASS1309/3 omitidas; pase final PASS1310/3 omitidas (03:51), log .uat/evidence/phase12-flutter-final.log |
| flutter test --no-pub test/core/offline/sync_queue_service_test.dart | PASS12 |
| FULLPOS_PHASE11_UAT=true + flutter test --no-pub test/features/catalogo/catalog_offline_uat_integrity_test.dart | PASS2, raíz desechable y guard local |
| npm --workspace apps/api test | PASS74 suites/751,8 omitidas |
| npm run api:build | PASS Prisma generate5.22.0 + TypeScript |
| npx prisma validate (apps/api, env UAT guardado) | PASS |
| . ./scripts/uat/run-sync-integrity-smoke.ps1 -DisposablePhase12 | PASS clon; repetir solo con clon46552 |
| . ./scripts/uat/run-product-stock-integrity-smoke.ps1 | PASS |
| . ./scripts/uat/run-updater-preservation-bench.ps1 | PASS banco limitado |
| . ./scripts/uat/run-sqlite-failure-bench.ps1 | PASS locked5/read-only8 |
| node scripts/uat/phase12-compatibility-smoke.cjs (env clon) | PASS fixtures y cotización copia |
| node scripts/uat/audit-phase11-flutter.cjs | PASS conciliación nueva |
| node scripts/uat/audit-phase11-preservation.cjs | PASS conciliación histórica |
| git diff --check | PASS; avisos LF→CRLF sin errores |

Pruebas completas cubren login, productos, ventas, inventario, clientes, turnos,
caja, reportes, licencias, tickets y reglas fiscales como regresión automatizada.
Regresión funcional GUI online por módulo: BLOCKED. Emisión fiscal/eCF/Alanube
real y hardware: NOT RUN; no se mezclaron integraciones ni se emitieron documentos.
Los tests imprimen fallback API_BASE_URL heredado: transporte del ensayo real
se construye explícitamente a127.0.0.1:46548; ese mensaje no acredita llamada remota.

## 16. Problemas corregidos y límites

No se reprodujo un nuevo defecto que justificara cambiar lógica de aplicación.
Se protegió el smoke heredado que podía cerrar el turno manual, se agregó scope
tenant a su conciliación, y se amplió evidencia de reinicio/expiración/independencia.

Ensayos del nuevo harness corrigieron fixtures: faltaba categoría obligatoria;
venta sin turno obtuvo409 esperado; expectedCurrentStock se aplica a conteos,
los deltas son incrementales. No se alteraron reglas para hacer pasar pruebas.
El primer ensayo en memoria del DTO falló por usar Module._compile sin filename
y abortó el proceso Node de prueba; repetido con evaluación CommonJS en memoria
pasó. No afectó API ni datos. No se ocultan esos intentos fallidos de herramientas.

Cotización original `quotes.create:local_quote_1791944878261619`: failed,
permanent,41intentos; customerId local no UUID. DTO de copia conserva tres líneas,
nombre/teléfono y total390 omitiendo referencia inválida. Envío único en clon
guardó total390, id `c630ac83-da77-4f4e-bb15-01a56bb0e914`.
No se reenvió ni cambió original. Búsqueda remota tenant/nombre/teléfono/total
en base manual=0; no es garantía universal de ausencia de duplicados.
Quotes carece de ledger idempotente equivalente; recuperación original requiere
revisión documental y autorización explícita antes de cualquier modificación.

## 17. Archivos modificados en Fase 12

- apps/fulltech_app/test/features/catalogo/catalog_offline_uat_integrity_test.dart
- apps/fulltech_app/test/core/offline/sync_queue_service_test.dart
- scripts/uat/run-sync-integrity-smoke.ps1
- scripts/uat/run-phase12-clone.ps1 (nuevo)
- scripts/uat/phase12-compatibility-smoke.cjs (nuevo)
- docs/offline-safe-48h-phase-12-acceptance-2026-10-14.md (nuevo)

Backups y evidencia bajo .uat ignorado; no atribuir archivos de otras fases ni
PNGs regenerados por suites existentes a cambios funcionales de Fase12.
Herramientas: terminal PowerShell7, git CLI, apply_patch, Python sqlite3,
Docker/psql/pg_dump/pg_restore, Flutter/Dart, npm/Jest/Prisma, node_repl + sky
(intento fallido nativo). Sin subagents, Figma, Playwright, Context7 ni inspección
visual de la ventana en esta fase. No se necesitó un patrón externo nuevo.

## 18. Riesgos y pendientes

Bloqueantes: recorrido visual Windows nuevo; muerte abrupta del proceso en
ventana commit/ACK; combinación backend anterior/candidato; binarioslegacy;
transición updater/instalador UAT con sello/grant/identidad/logs.
Recuperación original de cotización requiere autorización independiente.
Faltan hardware real, fallos de disco físico y aceptación funcional fiscal online.
HIPÓTESIS: pendientes legacy con IDs temporales de producto pueden necesitar
mapping; no modificar/borrar acciones sin reproducir con copia verificable.
Inventario offline estimado puede requerir revisión ante venta de otro dispositivo.

## 19. Matriz de aceptación GO/NO-GO

Estados integrales; PASS parcial técnico se describe en evidencia. «Sí» bloquea
aprobar producción del alcance pedido. Ningún BLOCKED se interpreta como aprobado.

| Módulo | Estado | Evidencia ejecutada | Riesgo / acción pendiente | Bloquea producción |
| --- | --- | --- | --- | --- |
| Autenticación | BLOCKED | login HTTP + Jest | login/renovación GUI | Sí |
| Autorización48h | BLOCKED | policy + grant real + expiryfixture | muestra GUI/secure storage equipo | Sí |
| Ventas | BLOCKED | Flutter/SQLite/PG stock16 | recorrido Windows | Sí |
| Productos | BLOCKED | create idempotente5concurrentes | GUI | Sí |
| Inventario | BLOCKED | conteo stale409/delta replay | GUI conflictos | Sí |
| Entradas mercancía | BLOCKED | +20 único | GUI incremental | Sí |
| Clientes | BLOCKED | tests repositorio/tenant suite | consulta/referencias GUI, legacy dependencia | Sí |
| Cotizaciones | BLOCKED | DTO copia + envío clon390 | resolver original con permiso | Sí |
| Turnos | BLOCKED | cierre/reopen clon y replays turno original | GUI real | Sí |
| Caja | BLOCKED | total360/3movimientos clon | conciliación GUI/hardware según alcance | Sí |
| Tickets | BLOCKED | suites ticket no fiscal | estado GUI/impresión/doble automático real | Sí |
| Historial | BLOCKED | SQLite8ventas/20líneas | consulta GUI tras reinicio | Sí |
| Cola SQLite | PASS técnico | atómica/reopen/preservación/independencia | muerte proceso pendiente en recuperación | Sí por alcance integral |
| Sincronización | BLOCKED | cero pendientes ensayo nuevo | reconexión GUI | Sí |
| Idempotencia | PASS técnico |5concurrentes+ACK perdido+backend reiniciado | no universal legacy | Sí por compatibilidad |
| Updater | BLOCKED | banco ficticio preservación | transición real UAT | Sí |
| Instalador | NOT RUN | ninguno comercial | fixture UAT firmado | Sí |
| Compatibilidad antigua | FAIL contrato / BLOCKED binarios | baseline stock400; fixtures candidato | backend compatible primero y versiones referencia | Sí |
| Multiempresa | BLOCKED integral | scope tests/tenant Jest | matriz almacén/licencia/GUI | Sí |
| Recuperación fallos | BLOCKED integral | matrizA–M §11 | proceso abrupto/GUI/disco real | Sí |

## 20. Procedimiento final recomendado

Continuar exclusivamente UAT. API46548 y PostgreSQL disponibles; ventanaUAT
abierta, SQLite original preservada. Paso inmediato del operador: traer al
frente la ventana cuyo título termina `[UAT]` e informar la pantalla visible,
sin cambiar sesión ni registrar operaciones. Esperar ese resultado antes del
siguiente paso. Una sola acción manual por respuesta.

Después: validar login/grant/turno; detener exclusivamente API46548 cuando el
operador esté listo; producto ficticio stock0, entrada20, venta cash4, cierre/
reapertura offline; restaurar API y conciliar producto/entrada/venta/stock16/
turno original con IDs capturados. Conservar cotización pendiente independiente.
Cerrar brechaslegacy/updater/fallos críticos en clon, revisar evidencia y obtener
aprobación expresa posterior. No pasar automáticamente a fase de publicación.
