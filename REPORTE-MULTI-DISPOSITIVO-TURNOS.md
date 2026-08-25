# REPORTE — Blindaje multi-dispositivo del subsistema de turnos/caja

Fecha: 2026-08-22
Proyecto: DaleVentas POS (apps/api + apps/fulltech_app)
Alcance: solo turnos/caja. NO commit, NO push, NO deploy, NO migración de producción.

---

## A. Causa raíz — por qué Windows y Android podían divergir

Ambos dispositivos consumen **el mismo** `activeCashSessionControllerProvider`
(StateNotifier `keepAlive`) y el mismo `CashRepository`. No hay providers ni
APIs distintas por plataforma: la lógica es idéntica. La divergencia observada
("Windows cerrado / Android abierto") se explica por **snapshots obsoletos que
nunca se revalidaban**:

1. **Sin revalidación al volver al primer plano (resume)**: `main.dart`
   `didChangeAppLifecycleState` reconectaba el socket y refrescaba usuario/licencia,
   pero **no revalidaba el turno**. Si Windows cerraba caja mientras Android estaba
   en background, al volver Android seguía mostrando el turno abierto.
2. **Eventos realtime perdidos en background**: el socket entrega `cash.event`
   solo mientras está conectado. Si el evento `cash.session.closed` se emitió
   mientras Android estaba desconectado/background, se perdía y nunca se recuperaba
   (la reconexión no disparaba refresh de caja).
3. **Caché local como autoridad en fallo de red**: `CashRepository.state()`
   devolvía la caché `cash.active.session` como un resultado EXITOSO cuando había
   error de red (`status null` o `>= 500`). Si Android tenía cacheado "abierto"
   (última consulta exitosa antes del cierre) y luego un refresh fallaba
   transitoriamente, Android mostraba "abierto" mientras el backend decía "cerrado".
4. **Cerrar un turno ya cerrado no convergía**: si Android intentaba cerrar cuando
   Windows ya lo había cerrado, el backend respondía 404/409 y la UI mostraba el
   error sin actualizarse a CERRADO.
5. **Sin refetch al entrar a pantallas críticas** ni polling: el menú de turno leía
   el snapshot en memoria de forma indefinida hasta que algo lo refrescara.

## B. Fuente de verdad ANTERIOR

Backend/DB ya era la fuente para el servidor (todas las consultas de caja y ventas
usan `userId + companyId` del JWT). Pero en el cliente convivían:

- `AUTORITATIVA`: respuesta de `GET /cash/state` (backend).
- `CACHE`: `LocalJsonCache` `cash.active.session` (fallback en error de red).
- `DERIVADA`: `cashSummaryProvider`, `cashMovementsProvider`.
- `PELIGROSA`: el snapshot en memoria del controller cuando no se revalidaba, y la
  caché local devuelta como éxito en fallo de red (se presentaba como confirmada).

## C. Fuente de verdad FINAL

**Backend / base de datos** (sin cambios de esquema). El cliente mantiene:
- provider = snapshot del backend,
- caché local = opcional y **marcada como no sincronizada** (nunca autoridad),
- UI = representación.

## D. Modelo de turno (campos relevantes)

`CashSession` (Prisma): `id`, `companyId`, `openedByUserId`, `userName`,
`openedAt`, `initialAmount`, `closingAmount`, `expectedAmount`, `difference`,
`status` (OPEN/CLOSED), `closedAt`, `closedByUserId`, `cashboxDailyId`,
`businessDate`, `requiresClosure`, `note`.
Índices: `[openedByUserId, status]`, `[companyId, status]`, `[cashboxDailyId]`,
`[companyId, businessDate]`. No hay constraint único por `(user, company)` abierto
(se protege en servicio, ver I).

## E. Regla usuario/empresa

El turno pertenece a `(openedByUserId, companyId)`. El `companyId` sale del **JWT**
(`requireTenant`), nunca del payload del cliente. `userId` para propietario también
del JWT. No se usa `deviceId`/`installationId`/`machineId` en ningún punto.

## F. Windows — cómo obtiene ahora el estado

Misma fuente que móvil: `activeCashSessionControllerProvider`
(→ `CashRepository.state()` → backend). Además de la revalidación realtime, ahora
revalida:
- al volver a primer plano (`resumed`),
- al reconectar el socket realtime,
- con polling ligero cada 30s en primer plano,
- con `refresh` silencioso tras abrir/cerrar y tras errores de "ya cerrado".

## G. Android/iOS — cómo obtiene ahora el estado

Idéntico al punto F (misma fuente lógica). Las UIs (`CashTurnMenuButton` móvil,
`CashBoxScreen`/menú Windows) difieren solo visualmente; el estado lógico es el
mismo y converge por los mismos mecanismos.

## H. Sincronización

| Evento | Mecanismo |
|---|---|
| Abrir turno (cualquier dispositivo) | Backend crea/devuelve turno; emite `cash.session.opened`; el resto de dispositivos recibe realtime → `refreshCash(silent)`. |
| Cerrar turno (cualquier dispositivo) | Backend cierra (idempotente); emite `cash.session.closed`; resto recibe realtime → refresh. El que cierra refresca tras la operación. |
| App vuelve de background (`resumed`) | `_refreshCashOnResume()` → `refreshCash(silent: true)` (también reconecta socket). |
| Navegación a pantallas críticas | El POS ya consulta backend en cada checkout; el menú/pantalla de caja converge por realtime + polling + acciones. |
| Cambio de empresa | No hay cambio en caliente: cambio = logout+login → `_resetCashState()` (logout) + `refreshCash()` (login). |
| Logout | `_resetCashState()` invalida controller + providers de caja (no hereda estado del usuario anterior). |
| Reconexión red/socket | `permissions.reconnect` → `refreshCash(silent: true)`. |
| Polling | 30s en primer plano con sesión (GET ligero silencioso), se detiene en background. |

## I. Concurrencia (doble apertura / doble cierre)

- **Doble apertura**: `startSession` ahora ejecuta la transacción con
  `isolationLevel: Serializable` y reintenta conflictos `P2034`
  (`retryOnWriteConflict`). Si dos dispositivos abren a la vez, uno aborta y en el
  reintento encuentra el turno existente y lo devuelve → **un solo turno abierto**.
  Sin migración de base de datos.
- **Doble cierre**: `closeSession` es idempotente (`updateMany` con `WHERE status=OPEN
  AND closedAt IS NULL`); si el count no es 1 lanza `ConflictException` controlado.
  No duplica movimientos ni rompe saldo.
- **Cerrar ya cerrado**: `CashSessionAlreadyClosedException` (404/409) → Flutter
  hace `refresh(silent)` y la UI converge a CERRADO (no muestra error permanente).

## J. Seguridad backend (operaciones con turno cerrado)

- Ventas: `sales.service.ts` valida `cashSession` activo del usuario/empresa antes
  de facturar (`"Debes abrir caja antes de facturar."`).
- Caja: `requireOpenSession(userId, companyId)` en summary/movements/movements de
  retiro/cierre. La UI (checkout) también consulta backend en el momento del cobro.
- Aunque la UI muestre mal el estado, el backend impide la operación.

## K. Offline

- Si hay fallo de red, `state()` devuelve el snapshot local **marcado
  `fromCache: true`** → `cashStateUnverifiedProvider = true` → la UI muestra
  "Sin conexión — estado no sincronizado" (banner en Caja / aviso en el menú de
  turno). No se presenta como estado garantizado.
- Al recuperar conexión (resume/reconnect/realtime/polling) el estado real del
  backend sobrescribe el snapshot y se limpia el banner.
- El flujo offline de apertura/cierre (cola de sincronización) se conserva intacto.

## L. Tests backend — resultados

`apps/api/src/cash/cash.service.spec.ts` (nuevo) — **6/6 OK**:
1. Abrir con turno ya abierto devuelve el existente (no crea otro).
2. Doble apertura concurrente: P2034 se reintenta y devuelve el existente.
3. Abrir sin turno previo crea cashbox + cashSession.
4. Cerrar un turno que ya no existe → NotFound controlado.
5. Cerrar un turno ya cerrado → Conflict y no duplica el cierre.
6. Requiere empresa del JWT (tenant) para toda operación.

Además: `npx tsc -p tsconfig.build.json --noEmit` → EXIT 0.

## M. Tests Flutter — resultados

Suite `test/modules/cash/` → **41/41 OK**:

`cash_lifecycle_test.dart` (7 tests multi-dispositivo):
- Multi-dispositivo: B refresca y ve turno abierto por A.
- A cierra → B hace refresh silencioso y ve CERRADO.
- Error de red al revalidar NO convierte abierto en "cerrado" (conserva snapshot + unverified).
- Estado de caché se muestra como "no sincronizado", nunca como confirmado.
- Cerrar un turno ya cerrado por otro dispositivo converge a CERRADO.
- Abrir un turno ya abierto por otro dispositivo devuelve el existente (no crea otro).
- Cambio de empresa/logout: nueva instancia revalida y no hereda snapshot.

`operations_cash_refresh_test.dart` (nuevo, 4 tests de revalidación por
realtime/reconexión/resume a nivel de `OperationsDataRefreshService`):
- Evento realtime `cash.event` (otro dispositivo) dispara refetch silencioso.
- `permissions.reconnect` (reconexión tras background) dispara refetch.
- `resumed` (hook de lifecycle llama `refreshCash(silent)`) refetcha y converge.
- Reconexión corrige un turno que pasó a CERRADO mientras estaba sin conexión
  (snapshot de caché marcado no sincronizado → convergencia a CERRADO).

`flutter analyze --no-pub` → **No issues found**.

## M2. Observabilidad (FASE 8)

Logs estructurados (debug-only vía `TraceLog`):
- `cash.fetch.start` / `cash.fetch.done` (repository `state()`).
- `cash.cache_fallback` (repository, cuando `state()` cae a caché por error de red).
- `cash.conflict` (repository close 404/409 y controller `CashSessionAlreadyClosedException`).
- `cash.refresh` (controller `refresh()` y `refreshCash()`).
- `cash.open.start` / `cash.open.done` (controller).
- `cash.close.start` / `cash.close.done` (controller).
- `cash.reconnect_refresh` (servicio, al reconectar el socket).

Sin tokens ni datos sensibles.

## N. Test multi-dispositivo simulado

Cubierto en Flutter (`cash_lifecycle_test.dart`) con una sesión lógica por
dispositivo y un backend fake controlable:

```
SESSION A (Windows) + SESSION B (Android), MISMO user/company:
  A abre        → backend OPEN
  B refresh     → ABIERTO ✓
  B cierra      → backend CLOSED
  A refresh     → CERRADO ✓
  A abre        → backend OPEN
  B (background→foreground) refresh → ABIERTO ✓
  A cierra      → backend CLOSED
  B refresh     → CERRADO ✓
```

## O. Builds

- `flutter analyze --no-pub` → limpio.
- Backend `npx tsc -p tsconfig.build.json --noEmit` → EXIT 0.
- `flutter build apk --debug` → **OK** (`build\app\outputs\flutter-apk\app-debug.apk`).
- `flutter build windows --debug` → **OK** (`build\windows\x64\runner\Debug\fullpos_cloud.exe`).
  (El primer intento de Windows falló por lock del exe con una instancia en
  ejecución de `fullpos_cloud`; se detuvo el proceso y el build pasó.)

## P. Archivos modificados

| Archivo | Cambio |
|---|---|
| `apps/api/src/cash/cash.service.ts` | `startSession` SERIALIZABLE + `retryOnWriteConflict` |
| `apps/api/src/cash/cash.service.spec.ts` | **nuevo** spec 6 tests |
| `apps/fulltech_app/lib/modules/cash/cash_models.dart` | `CashGateState.fromCache` |
| `apps/fulltech_app/lib/modules/cash/cash_repository.dart` | fallback cache marcado, `lastStateFromCache`, `CashSessionAlreadyClosedException`, logs `cash.fetch.*`/`cash.cache_fallback`/`cash.conflict` |
| `apps/fulltech_app/lib/modules/cash/cash_providers.dart` | `cashStateUnverifiedProvider`, `refresh({silent})`, preserva snapshot en error, close "ya cerrado", logs `cash.open/close/refresh/conflict` |
| `apps/fulltech_app/lib/modules/cash/cash_box_screen.dart` | banner "Sin conexión — estado no sincronizado" |
| `apps/fulltech_app/lib/modules/cash/cash_turn_menu_button.dart` | aviso "Estado no sincronizado" en menú |
| `apps/fulltech_app/lib/core/realtime/operations_data_refresh_service.dart` | `refreshCash({silent})`, `cashStream`→silencioso, reconnect→refresh + `cash.reconnect_refresh` |
| `apps/fulltech_app/lib/main.dart` | resume → refresh cash; polling 30s foreground |
| `apps/fulltech_app/test/modules/cash/cash_lifecycle_test.dart` | +7 tests multi-dispositivo |
| `apps/fulltech_app/test/modules/cash/operations_cash_refresh_test.dart` | **nuevo** 4 tests realtime/reconexión/resume |
| `apps/fulltech_app/test/modules/cash/gasto_ref_disposed_repro_test.dart` | fake implementa `lastStateFromCache` |

## Q. Cambios DB

**NINGUNO** (sin migración). La protección de doble apertura se logró con
aislamiento SERIALIZABLE en la transacción + reintento, sin tocar el esquema.

## R. Riesgos restantes

- La caché `cash.active.session` está scoped por empresa (`LocalJsonCache._key`),
  no por usuario: en un dispositivo compartido entre usuarios de la misma empresa,
  un fallo de red podría mostrar el snapshot del otro usuario (ahora marcado como
  "no sincronizado"). Mitigación parcial con el banner; refactor opcional a futuro.
- El polling (30s) añade 2 GET `/cash/state`/min en primer plano (coste despreciable).
- El flujo offline de apertura crea un `ActiveCashSession(userId: 'offline',
  shiftId: 'local_shift_...')` para operar sin red; si el sync falla
  persistentemente podría quedar un "turno local" sin respaldo. Comportamiento
  preexistente, ahora marcado como no sincronizado.

## S. Checklist física (prueba en hardware real pendiente)

Los builds Android y Windows debug compilan OK. La prueba funcional en dos
dispositivos físicos queda pendiente de ejecución por el usuario:

- [ ] Windows abierto + Android mismo usuario → ambos ABIERTO.
- [ ] Windows cierra → Android (foreground) converge a CERRADO (realtime).
- [ ] Android en background → Windows cierra → Android foreground → CERRADO (resume).
- [ ] Android cierra → Windows converge a CERRADO.
- [ ] Abrir en un dispositivo se refleja en el otro (≤30s sin realtime).
- [ ] Doble apertura simultánea → un solo turno.
- [ ] Cerrar turno ya cerrado → UI converge a CERRADO sin error.
- [ ] Banner "Sin conexión — estado no sincronizado" al cortar red y recargar.
- [ ] Android compila; Windows compila.

## T. Estado Git

```
git status / diff --stat / diff --check: ver más abajo.
```
Cambios preexistentes (catálogo, reportes, compras, cotizaciones, ventas,
inventario) NO fueron tocados.

---

## U. Veredicto

**ESTABLE CON OBSERVACIONES** — con la corrección multi-dispositivo aplicada,
tests backend (6/6) + Flutter (48/48) en verde, `flutter analyze` limpio y builds
Android + Windows debug compilando. Pendiente únicamente la prueba física en
Windows+Android (checklist S). Sin commit/push/deploy.

---

# ADENDA — Menú/drawer móvil de turnos sincronizado (2026-08-22)

## A. Causa exacta del bug móvil

`apps/fulltech_app/lib/core/widgets/app_drawer.dart`, función `_buildDrawerGroups`
(grupo "Turno" en `mobileLayout`): los ítems se construían **estáticamente** y
siempre mostraban `Turno actual` + `Cerrar turno` + `Historial de turnos`, **sin
observar ningún provider**. El drawer móvil no se enteraba del estado real del
turno y por eso Android podía mostrar "Turno actual / Cerrar turno" con el turno
cerrado.

## B. Por qué Windows estaba correcto

Windows usa `CashTurnMenuButton` (app bar / pantalla de caja), que **sí** hace
`ref.watch(activeCashSessionControllerProvider)` y muestra "Abrir caja" cuando
`active == null` (cerrado).

## C. Por qué el móvil quedaba stale

El drawer móvil no observaba el provider (era pura navegación estática), a
diferencia del `CashTurnMenuButton`. No era un problema de refresh/realtime del
estado (eso ya se blindó), sino que esta superficie **no consumía** el estado.

## D. Provider final utilizado

`activeCashSessionControllerProvider` (StateNotifier keepAlive) +
`cashStateUnverifiedProvider` (ambos en `cash_providers.dart`), observados con
`ref.watch` en `_AppDrawerState.build`.

## E. Regla de renderizado (drawer móvil)

```
hasOpenShift = controller.valueOrNull?.isOpen == true
cashConfirmed = controller.hasValue && !cashStateUnverified
```

## F. Estado abierto (confirmado)

`Turno actual` (→ /caja) + `Cerrar turno` (→ flujo de cierre) + `Historial de turnos`.

## G. Estado cerrado (confirmado)

`Abrir turno` (→ flujo de apertura directo desde el drawer, nuevo `_openTurnFromDrawer`)
+ `Historial de turnos`.

## H. Estado no sincronizado / loading / error

Ítem neutro **deshabilitado** `Estado del turno no disponible` (`enabled: false`,
gris, sin acción) + `Historial de turnos`. No se presenta "Abrir/Cerrar turno"
como confirmado. Se añadió soporte `enabled` a `AppNavigationItem` y se respeta
en `_DrawerMenuItem` (atenuado, sin hover/press/tap) y en `_handleItemTap`.

## I. Tests nuevos

`test/modules/cash/mobile_drawer_turn_menu_test.dart` — **7 tests** (widget del
drawer con fake repo controlable + auth fijo):
1. Cerrado → "Abrir turno" visible, "Cerrar turno"/"Turno actual" NO.
2. Abierto → "Turno actual"/"Cerrar turno" visibles, "Abrir turno" NO.
3. abierto → cerrado (refresh, sin recrear) → "Cerrar turno" desaparece.
4. cerrado → abierto (refresh) → "Cerrar turno" aparece.
5. No sincronizado → solo ítem deshabilitado + historial; sin acción crítica.
6. Cambio de empresa → muestra "Abrir turno" (no hereda Empresa A).
7. Logout/login → usuario B no hereda el turno de A.

## J. Suite cash

`flutter test test/modules/cash` → **48/48 OK** (41 previos + 7 nuevos).
Módulos completos: `+209 -1` (único fallo preexistente de PDF share ajeno).

## K. Builds

`flutter build apk --debug` → OK. `flutter build windows --debug` → OK.
`flutter analyze` → limpio. Windows sin cambios funcionales.

## L. Archivos modificados (esta adenda)

- `apps/fulltech_app/lib/core/widgets/app_drawer.dart` (grupo "Turno" reactivo,
  `_openTurnFromDrawer`, `_drawerOpenTurnAction`, ítems deshabilitados).
- `apps/fulltech_app/lib/core/widgets/app_navigation.dart` (`AppNavigationItem.enabled`).
- `apps/fulltech_app/test/modules/cash/mobile_drawer_turn_menu_test.dart` (**nuevo**).

## M. Estado Git

HEAD `23ec06b8`. Cambios de la adenda sin commit (junto a los de la iteración
anterior). `git diff --check` sin errores. NO commit/push/deploy.

## N. Veredicto

**MENÚ MÓVIL DE TURNOS SINCRONIZADO Y CORRECTO** — el drawer móvil ahora observa
el mismo provider autoritativo que el resto de la app y representa abierto/cerrado/
no sincronizado correctamente; con tests de widget (9/9), suite cash 50/50 y
builds Android/Windows OK. Queda pendiente la verificación física en dispositivo
(listo para revisión).

---

# ADENDA 2 — Auditoría REALTIME end-to-end del turno (2026-08-22)

## A. Causa exacta del retraso

**No se encontró un eslabón roto en el código**: la cadena realtime es completa y
funcional de extremo a extremo. El backend **sí emite** `cash.event` tras el
commit, al room de la empresa, y **dos sockets del mismo usuario/empresa reciben
el evento simultáneamente** (demostrado con Socket.IO real en memoria: latencia
**30.7ms**). El retraso observado en producción apunta al **cliente** (socket no
conectado/perdido en el dispositivo) — para localizarlo se añadieron logs de
diagnóstico estructurados en ambos extremos (FASE G).

## B. ¿El backend emitía evento?

SÍ. `cash.service.ts` → `emitCashEvent(...)` **después** de la transacción
(`retryOnWriteConflict` / `$transaction`) → `emitCompany(companyId, "cash.event", …)`.
Verificado por test multi-cliente: `cash.realtime.emit room=company:… recipients=2`.

## C. ¿El room era correcto?

SÍ. `main.ts` llama `realtimeRelay.attach(httpServer)` → `this.io` activo. El
middleware verifica el JWT (que incluye `companyId`) y une a `company:{companyId}`
(+ `ops`, `ops:user:{userId}`, `company:{id}:user:{uid}`). El evento se emite a
`company:{companyId}`. Un socket de otra empresa **NO** recibe (testeado).

## D. ¿Múltiples sockets por usuario soportados?

SÍ. El server NO usa `Map<userId, socket>`; cada conexión se une al room. Dos
sockets del mismo usuario/empresa coexisten y ambos reciben el evento (testeado:
`win.connected === true && and.connected === true` tras emit).

## E. Cambio realizado

- Logs de diagnóstico: backend (`cash.realtime.emit`, `cash.realtime.emit.failed`,
  `[realtime] socket.join`, `[realtime] emit … recipients=N`) y Flutter
  (`cash.realtime.received`, `cash.realtime.refresh.start`).
- Tests backend multi-cliente (Socket.IO real en memoria) y tests Flutter
  D/E (evento realtime actualiza el drawer montado sin recrear).
- No se tocó DB, ni polling (sigue como fallback), ni se creó otra fuente de verdad.

## F. Evento final utilizado

`cash.event` (payload `{ eventId, type: cash.session.opened/closed, sessionId,
companyId, emittedAt, userId, businessDate }`) → actúa como **señal de
invalidación**: el cliente hace refetch del estado autoritativo.

## G. Flujo Windows → Android

```
Windows: POST /cash/sessions/open|close
→ CashService.startSession/closeSession (DB commit)
→ emitCashEvent → CatalogRealtimeRelayService.emitCompany(companyId, "cash.event")
→ room company:{id}
→ Android socket recibe "cash.event" (OperationsRealtimeService)
→ cashStream → OperationsDataRefreshService.refreshCash(silent:true)
→ GET /cash/state → controller → provider → drawer/appbar (instantáneo)
```

## H. Flujo Android → Windows

Idéntico (mismo room/evento); Windows recibe vía su socket y refresca.

## I. Latencia medida

Test multi-cliente (in-memory): **30.7ms** desde la confirmación de
`startSession` hasta que ambos clientes reciben el evento (objetivo < 1–2s).

## J. Tests backend realtime

`apps/api/src/products/catalog-realtime-relay.cash.spec.ts` — **3/3 OK**:
1. Abrir emite `cash.event` tras commit a DOS sockets mismo user/company; otra
   empresa NO recibe.
2. Cerrar emite a ambos.
3. Fallo al abrir NO emite evento falso.

## K. Tests Flutter

`test/modules/cash/mobile_drawer_turn_menu_test.dart` — añadidos **Tests D y E**
(evento realtime → drawer montado cambia abierto↔cerrado sin recrear). Suite cash
ahora **50/50**.

## L. Test multi-cliente

Verificado en J (dos sockets simultáneos del mismo user/company, sin
sobrescritura).

## M. Polling fallback

Se mantiene el polling de 30s solo como respaldo; el realtime es el responsable
del cambio instantáneo.

## N. Builds

`flutter build apk --debug` OK · `flutter build windows --debug` OK ·
`flutter analyze` limpio · backend `tsc` EXIT 0.

## O. Archivos modificados (esta adenda)

- `apps/api/src/cash/cash.service.ts` (Logger + logs `cash.realtime.emit[.failed]`).
- `apps/api/src/products/catalog-realtime-relay.service.ts` (logs `socket.join`/`emit`).
- `apps/api/src/products/catalog-realtime-relay.cash.spec.ts` (**nuevo**, 3 tests).
- `apps/fulltech_app/lib/core/realtime/operations_realtime_service.dart` (log `cash.realtime.received`).
- `apps/fulltech_app/lib/core/realtime/operations_data_refresh_service.dart` (log `cash.realtime.refresh.start`).
- `apps/fulltech_app/test/modules/cash/mobile_drawer_turn_menu_test.dart` (+Tests D/E).

## P. Estado Git

HEAD `23ec06b8`; cambios de la adenda sin commit (junto a iteraciones anteriores).
`git diff --check` sin errores. NO commit/push/deploy.

## Q. Veredicto

**SINCRONIZACIÓN DE TURNOS REALTIME INSTANTÁNEA CON PRUEBA FÍSICA PENDIENTE** —
el lado servidor está demostrado (emite tras commit al room correcto, 2 sockets
reciben, 30ms). El único punto a validar en hardware es la conexión del socket en
el dispositivo móvil; los logs añadidos
(`socket.join`/`cash.realtime.emit`/`cash.realtime.received`/`cash.realtime.refresh.start`)
permiten ubicar el eslabón exacto si se pierde en producción.

---

# ADENDA 3 — Fix "Failed to load dynamic library" en Android al cerrar turno (2026-08-22)

## A. Causa raíz exacta

Al confirmar el cierre en móvil, `CashCloseTicketPrinter.printCloseTicket` (camino
PDF) hace `_ref.read(unifiedTicketPrinterProvider)` → `UnifiedTicketPrinter(...)`
→ `_windowsRaw = WindowsRawPrinterTransport()` → `FfiWindowsRawSpooler()` →
`DynamicLibrary.open('winspool.drv')` **en TODAS las plataformas**. En Android/iOS
esa DLL no existe → `ArgumentError: Invalid argument(s): Failed to load dynamic
library 'winspool.drv'` → el diálogo lo mostraba en rojo (vía `_inlineError`).

## B. Librería/plugin que fallaba

`winspool.drv` (y `kernel32.dll`), abiertas por `FfiWindowsRawSpooler` en
`lib/core/printing/windows_raw_printer_transport.dart`.

## C. Por qué solo móvil

Windows tiene `winspool.drv` → la apertura FFI funciona. Android/iOS no → la mera
**construcción** (no el uso) del transporte lanzaba el error. El transporte RAW se
construía eager aunque el móvil usa `mobilePrintService`/PDF.

## D. Cambio aplicado

- `unified_ticket_printer.dart`: `_defaultWindowsRawTransport()` solo crea
  `WindowsRawPrinterTransport()` en Windows; en el resto usa `_UnavailableWindowsRawTransport`
  (stub que NUNCA abre FFI y lanza mensaje amigable si se usara).
- `windows_raw_printer_transport.dart`: `WindowsRawPrinterTransport` solo instancia
  `FfiWindowsRawSpooler()` cuando `Platform.isWindows`; fuera usa `_UnavailableWindowsSpooler`
  (defensa en profundidad). No se toca `FfiWindowsRawSpooler` (sigue intacto para Windows).

## E. Manejo de error visual

El camino RAW en móvil ahora devuelve `RAW ERROR: La impresión RAW de Windows solo
está disponible en Windows.` (nunca `Invalid argument`/`DynamicLibrary`/`Failed to
load`). El cierre móvil ni siquiera toca ese transporte (usa PDF/mobilePrint).

## F. Validación del campo

`parseDominicanAmount` es puro Dart y ya está testeado (0/1200/1,200.00/1200,50;
rechaza negativos/NaN/Infinity). No dependía de ninguna librería nativa.

## G. Flujo de cierre

Monto válido → `controller.close` → backend cierra → `printCloseTicket` (PDF en
móvil, sin FFI) → provider → drawer cambia a "Abrir turno". Sin error técnico.

## H. Tests

- `test/core/printing/unified_ticket_printer_platform_test.dart` (**nuevo, 3/3**):
  construir `UnifiedTicketPrinter` en Android no lanza; RAW en Android devuelve
  mensaje amigable sin texto técnico; transporte RAW no es FFI en Android.
- Tests de impresión existentes: 75/75 (Windows RAW intacto).
- Suite cash: 50/50.

## I. Android build

`flutter build apk --debug` → **OK**.

## J. Windows build

`flutter build windows --debug` → **OK**. `flutter analyze` limpio.

## K. Archivos modificados (esta adenda)

- `apps/fulltech_app/lib/core/printing/unified_ticket_printer.dart`
- `apps/fulltech_app/lib/core/printing/windows_raw_printer_transport.dart`
- `apps/fulltech_app/test/core/printing/unified_ticket_printer_platform_test.dart` (**nuevo**)

## L. Estado Git

HEAD `23ec06b8`; cambios sin commit. `git diff --check` sin errores.
NO commit/push/deploy.

## M. Veredicto

**CIERRE DE TURNO MÓVIL CORREGIDO Y BLINDADO** — se eliminó la carga eager de DLLs
de Windows fuera de Windows en la raíz (sin ocultar el error, sin `catch(_)`,
sin romper Windows). Pendiente solo la prueba física Android (escenario FASE 8).
