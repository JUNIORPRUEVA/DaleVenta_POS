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

Suite `test/modules/cash/` → **37/37 OK** (incluye 7 nuevos en
`cash_lifecycle_test.dart`):
- Multi-dispositivo: B refresca y ve turno abierto por A.
- A cierra → B hace refresh silencioso y ve CERRADO.
- Error de red al revalidar NO convierte abierto en "cerrado" (conserva snapshot + unverified).
- Estado de caché se muestra como "no sincronizado", nunca como confirmado.
- Cerrar un turno ya cerrado por otro dispositivo converge a CERRADO.
- Abrir un turno ya abierto por otro dispositivo devuelve el existente (no crea otro).
- Cambio de empresa/logout: nueva instancia revalida y no hereda snapshot.

`flutter analyze --no-pub` → **No issues found**.

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
| `apps/fulltech_app/lib/modules/cash/cash_repository.dart` | fallback cache marcado, `lastStateFromCache`, `CashSessionAlreadyClosedException` |
| `apps/fulltech_app/lib/modules/cash/cash_providers.dart` | `cashStateUnverifiedProvider`, `refresh({silent})`, preserva snapshot en error, close "ya cerrado" |
| `apps/fulltech_app/lib/modules/cash/cash_box_screen.dart` | banner "Sin conexión — estado no sincronizado" |
| `apps/fulltech_app/lib/modules/cash/cash_turn_menu_button.dart` | aviso "Estado no sincronizado" en menú |
| `apps/fulltech_app/lib/core/realtime/operations_data_refresh_service.dart` | `refreshCash({silent})`, reconnect → refresh |
| `apps/fulltech_app/lib/main.dart` | resume → refresh cash; polling 30s foreground |
| `apps/fulltech_app/test/modules/cash/cash_lifecycle_test.dart` | +7 tests multi-dispositivo |
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
tests backend (6/6) + Flutter (37/37) en verde, `flutter analyze` limpio y builds
Android + Windows debug compilando. Pendiente únicamente la prueba física en
Windows+Android (checklist S). Sin commit/push/deploy.
