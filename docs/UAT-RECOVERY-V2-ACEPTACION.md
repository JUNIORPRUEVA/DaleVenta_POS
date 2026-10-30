# Aceptación UAT — Recuperación automática v2 y conciliación financiera

Fecha: 2026-10-29 · Rama `agent/recovery-engine-v2` · HEAD `3e5b98b0` (+ correcciones de esta sesión).

Entorno usado, **aislado de producción**:

| Pieza | Valor |
| --- | --- |
| PostgreSQL | contenedor Docker `fullpos_recovery_uat_pg` (postgres:16-alpine), `127.0.0.1:56551` |
| Base de datos | `daleventa_uat_local` (nombre exigido por el guardián `uat-safety`) |
| API NestJS | `node dist/main.js`, `http://127.0.0.1:4010`, `APP_ENV=uat`, Redis desactivado, storage `none` |
| Empresas | 2 empresas sintéticas creadas por `POST /auth/register-business` en cada corrida |
| App Windows | `FullPOS-UAT-1.0.6-uat.2-148900` (perfil `FULLPOS_UAT_PROFILE=true`) |
| Almacenamiento de la app UAT | `DALEVENTAS_POS_ROOT` → carpeta de sandbox; nunca `C:\Program Files\DaleVentas POS` |

Nada de esto toca producción, la versión 148 publicada, ni datos de clientes reales.

---

## 1. Defectos encontrados y corregidos

### 1.1 `operationFingerprint` no hexadecimal perdía la obligación

El DTO exigía `^[0-9a-fA-F]{16,64}$`. La app genera 16 hex, pero cualquier registro
legado o cliente con otro formato recibía **400**, y la cola lo clasificaba como
fallo **permanente**: la obligación de conciliación se perdía en silencio.

Corrección: la huella es un dato de **correlación**, no financiero → se valida solo
como texto corto (`@MaxLength(64)`). Verificado con `DECL-05` y con el test de
integración cliente↔servidor.

### 1.2 La build UAT abría las bases REALES del cliente (crítico)

En release, la raíz de datos es `C:\Program Files\DaleVentas POS` — exactamente la
misma que la instalación real. Una compilación de prueba sin carpeta propia habría
leído y potencialmente escrito los datos del cliente.

Corrección en `WindowsProductPaths`: si `FULLPOS_UAT_PROFILE=true` y no se indicó
`DALEVENTAS_POS_ROOT`, la app **falla cerrada** (`StateError`) antes de resolver la
ruta de SQLite. Verificado con:

- test `windows_product_paths_uat_guard_test` en sus dos ramas (con y sin perfil UAT);
- ejecución real CASO A (sin variable → no crea base, datos reales intactos) y
  CASO B (con variable → todo dentro del sandbox).

### 1.3 Defectos de la fase anterior (ya commitados en `3e5b98b0`)

- Doble barrido al arrancar → «servidor inalcanzable» falso y backoff inexistente.
- Huella de la declaración incluía la hora → dos obligaciones por un doble toque.
- Un 401 dejaba la declaración varada para siempre.

### 1.4 Dos encargados duplicaban el saldo pendiente (crítico financiero)

Cada declaración con importe, nota o actor distinto creaba una obligación
`PENDING` **independiente** para la misma operación: dos personas declarando
RD$50 dejaban RD$100 pendientes. Encontrado al auditar el caso de dos
dispositivos (la aceptación anterior lo daba por bueno como «2 registros
auditables», que era precisamente el error).

Corrección estructural:

- Índice único **parcial** `(company_id, client_request_id) WHERE status='PENDING'`
  → una operación, una obligación activa.
- Tabla nueva `sale_reconciliation_declaration_events` (append-only) con `kind`
  (`CREATED` | `AMENDED` | `RECTIFIED` | `RECTIFICATION_REJECTED`), importe
  anterior y nuevo, actor, rol, nota y hora.
- Cambiar el importe es una **rectificación** y exige rol administrativo; sin
  permiso devuelve 403 y la obligación queda intacta.
- La migración marca como `SUPERSEDED` las obligaciones `PENDING` duplicadas que
  ya existieran (no borra ninguna fila): en el UAT, 77 filas → 41 activas y 36
  superseded, `pending_per_operation_max = 1`.

### 1.5 Concurrencia y auditoría del rechazo (encontrado al probarlo)

- En PostgreSQL, un choque del índice único **aborta la transacción**; el código
  intentaba continuar dentro de ella y 3 de 5 envíos simultáneos devolvían 500.
  Ahora se reintenta la transacción completa (con espera + jitter) y, al existir
  ya la obligación, se aplica como `AMENDED`/`DUPLICATE`.
- El evento `RECTIFICATION_REJECTED` se escribía **dentro** de la transacción que
  luego se revertía, así que el rechazo se perdía. Ahora se escribe en una
  transacción nueva tras el rollback.

---

## 1bis. Seguridad de los datos locales (demostrada ANTES de abrir la app)

Snapshot previo de las **14 bases reales** de `C:\Program Files\DaleVentas POS\databases`,
incluida `fulltech_offline.db` (88,9 MB) y sus ficheros WAL/SHM.

**CASO A — build UAT sin carpeta propia:**

- `productRoot()` lanza `StateError`; la app no resuelve ninguna ruta de SQLite.
- `archivos_bajo_sandbox = 0` (no creó ninguna base).
- Comparación de las 14 bases reales: **SIN CAMBIOS** (nombre, tamaño y `mtime`).

**CASO B — build UAT con `DALEVENTAS_POS_ROOT` en el sandbox:**

| Archivo | Tamaño | Dónde |
| --- | --- | --- |
| `databases\fulltech_offline.db` | 4 096 B | sandbox |
| `databases\fulltech_offline.db-wal` | 131 872 B | sandbox |
| `databases\fulltech_offline.db-shm` | 32 768 B | sandbox |
| `logs\fullpos-client.log` | 5 940 B | sandbox |
| `updates\update_state.json` | 422 B | sandbox |

- `APPDATA` y `LOCALAPPDATA` redirigidos: preferencias y credenciales quedan en el sandbox.
- Comparación posterior de las 14 bases reales: **SIN CAMBIOS**.
- Conexiones TCP a hosts no locales durante la ejecución: **0**.
- La API local recibió la build: `GET /api/app-updates/check?…version=1.0.6-uat.2&build=148900 → 200`.

**Nota honesta:** antes de existir este guardián, la build UAT se abrió una vez **sin**
la variable de aislamiento. El fichero `fulltech_offline.db-shm` tiene `mtime 18:46:14`,
dentro de esa ventana, así que el proceso pudo abrir la base real. Verificado que **no
hubo escritura**: el `.db` (88,9 MB) y el `.db-wal` (4,2 MB) conservan su `mtime` del
28-10 y su tamaño —no se añadieron páginas ni se hizo checkpoint— y la app no tenía
sesión (`getUserSnapshot() miss`), por lo que ninguna operación financiera pudo
ejecutarse. El guardián 1.2 impide que se repita.

---

## 2. Matriz de resultados

### PASS (ejecutado con evidencia real)

| ID | Caso | Evidencia |
| --- | --- | --- |
| ENV-01 | Alta empresa sintética A + login | HTTP 201 |
| ENV-02 | Alta empresa sintética B + login | HTTP 201 |
| DB-01 | Migración `20261029190000_sale_reconciliation_obligations` aplicada | `prisma migrate deploy` → "All migrations have been successfully applied" |
| DB-02 | Tabla e índices reales | `\d sale_reconciliation_obligations` → PK + UNIQUE(company,request,hash) + 2 índices |
| DB-03 | Las declaraciones no crean ventas/caja/inventario | `sales=0`, `cash_sessions`/`cash_movements=0`, `inventory_movements=0` en la empresa A antes del ciclo |
| CASH-01 | Turno de caja sintético abierto | HTTP 201, `shiftId` real |
| CYCLE-01 | Venta sintética en efectivo registrada | HTTP 201 + saleId |
| CYCLE-02 | El motor confirma la venta real | `CONFIRMED` + saleId correcto |
| CYCLE-03 | Verificar 3 veces más no duplica | 3/3 CONFIRMED, 1 venta |
| CYCLE-04 | Reenviar la misma venta (mismo `clientRequestId`) | mismo saleId, 1 venta |
| DECL-01 | Declaración crea obligación PENDING | `retryAllowed=false`, `assertsPaymentReceived=false` |
| DECL-02 | Reenvío idéntico es idempotente | `duplicate=true`, mismo id |
| DECL-03 | Rectificación de importe | obligación nueva, `duplicate=false` |
| DECL-04 | Misma operación con otra nota | obligación nueva, trazable |
| DECL-05 | Huella no hexadecimal | HTTP 201 (defecto corregido) |
| LIST-01 | Listado por empresa | 3 obligaciones de la operación |
| TENANT-01 | Aislamiento entre empresas | empresa B ve 0 filas |
| AUTH-01 | Sin token | HTTP 401 |
| VALID-01 | Importe 0 | HTTP 400 |
| VALID-02 | Fecha no ISO-8601 UTC | HTTP 400 |
| DEV-01 | Dos encargados declaran el MISMO importe | **UNA** obligación, `declarationCount=2`, `AMENDED` |
| DEV-02 | Un cajero intenta cambiar el importe | 403 `RECTIFICATION_REQUIRES_ADMIN`, importe sigue 50 |
| DEV-03 | Rectificación autorizada por el administrativo | mismo id, importe 55, `version=2`, `RECTIFIED` |
| EVT-01 | Historial de la obligación | `[CREATED, AMENDED, RECTIFICATION_REJECTED, RECTIFIED]`, anterior=50 nuevo=55 |
| TENANT-02 | Historial de otra empresa | 403, sin filtrar datos |
| CONC-01 | 5 envíos simultáneos de la misma declaración | 1 creada, 4 duplicadas, 1 solo id |
| RECON-01 | Operación inexistente | `NOT_FOUND`, `NOT_REGISTERED`, `retryAllowed=false` |
| RECON-02 | Consulta repetida | idéntica, sin efectos |
| SAFE-01 | Declarar dinero no crea ventas | 0 ventas en la empresa A |
| LIVE-01 | Cliente Dart real: intento inexistente | no cierra el intento (`inconclusive=1`, fila intacta) |
| LIVE-02 | Cliente Dart real: intento con venta real | `CONFIRMED`, aviso retirado, auditoría `autoConfirmed`, 1 sola venta |
| LIVE-03 | Cliente Dart real: declaración sin red → reintento | queda guardada, se envía tras el backoff real, obligación única en PostgreSQL, cola vacía |
| ISO-01 | Guardián de almacenamiento UAT | `StateError` sin `DALEVENTAS_POS_ROOT`; ruta correcta con ella (2 ramas probadas) |
| ISO-02 | Ejecución real aislada (CASO A y B) | 5 archivos solo en el sandbox · 0 conexiones remotas · 14 bases reales idénticas antes y después |
| BUILD-01 | Compilación Windows UAT | `flutter build windows --release` → exit 0, 80 archivos, 112,4 MB |
| BUILD-02 | La build solo habla con la API UAT | `GET /api/app-updates/check?…version=1.0.6-uat.2&build=148900` → 200 en `127.0.0.1:4010`; 0 conexiones remotas |
| BUILD-03 | El actualizador no ofrece nada | `app_update_check … result=none` (canal stable intacto) |
| SUITE-01 | `flutter analyze` | No issues found (exit 0) |
| SUITE-02 | `flutter test` (suite completa) | **1483 PASS, 9 skip, 0 FAIL** (el 9.º skip es `sqlite_durability_test`, que exige `DALEVENTAS_POS_ROOT` y `UAT_API_BASE`) |
| SUITE-03 | API `npm run api:build` + tests | build 0 · 80 suites / **822 tests** PASS, 8 skip |
| FAIL-01 | 429 real con `Retry-After` | declaración conservada, `status=error`, reintentable |
| FAIL-02 | 500 real del servidor | declaración conservada, `attempts≥2` |
| FAIL-03 | Timeout real (servidor que no contesta) | declaración conservada, `attempts≥3` |
| FAIL-04 | El servidor vuelve | la MISMA cola la envía y queda **una** obligación; cola vacía |
| IMP-01 | Importación histórica en dry-run | 93 obligaciones antes y después; 0 filas de Siarah; fila sin importe rechazada |
| INST-01 | Instalador candidato UAT | `FullPOS-UAT-Setup-1.0.7-rc.1-150000.exe` (38,4 MB), AppId y carpeta propios |
| INST-02 | Ciclo **instalar → abrir/cerrar → reinstalar → desinstalar** (variante per-usuario con la misma carga, para no requerir UAC) | install exit 0 (83 archivos) · abre y cierra · 0 conexiones remotas · reinstala con `db`/`-wal`/`-shm` intactos · desinstala y **conserva** `databases/logs/config/media_cache/updates` |
| INST-03 | Identidad del candidato real | `ProductName=FullPOS UAT`, `FileVersion=1.0.7.1500`, AppId `4C1F9E6A…` ≠ estable `0ED49D5E…` |
| DURA-01 | Cierre forzado con declaración pendiente | copia de `.db`+`-wal` **con la conexión abierta** (`SNAPSHOT files=2 bytes=185408 skipped=[-shm]`: el `-shm` está mapeado por el proceso vivo y SQLite lo reconstruye del WAL) → una conexión nueva lee `sales.declaration` y `sales.attempt` → al reconectar se envía **una sola obligación de 50,00** |
| MIG-01 | Migración sobre la **COPIA** de la base real de 148 (84,8 MB) | `user_version 5→5`, 8 tablas, `integrity ok`, **481 filas antes y después**, **columnas idénticas** (la 148 puede reabrir la base) y conteo por tabla sin cambios; el original conserva `SHA256` y `mtime` idénticos (nunca se abrió) |
| UPD-01 | Base escrita por una versión POSTERIOR (`user_version=99`) | la apertura falla; el archivo queda **byte a byte idéntico** (mismo `SHA256` y tamaño) y `user_version` sigue en 99: no se degrada ni se vacía |
| INST-04 | Ciclo real en **modo administrador** (instalar → reinstalar → actualizar → desinstalar) | los 4 pasos `exit 0`; datos de `databases/config/updates` intactos tras reinstalar y actualizar; al desinstalar se conservan las carpetas de datos **y sus archivos**; la instalación estable (147 archivos) queda con 0 altas, 0 bajas y 0 cambios |
| SEC-01 | El instalador UAT no puede tocar la estable | AppId, carpeta, ejecutable y accesos directos propios; el bloque `[InstallDelete]` que borraba los accesos de `DaleVentas POS` ya no se compila en las variantes UAT (verificado en el binario) |
| INT-01 | Integración sobre la línea con Guardian AI | rama `agent/integrate-recovery-v2-guardian` desde `agent/guardian-phase12`: 2 conflictos resueltos (schema Prisma y rutas de almacenamiento), `api:build` OK, **1125 tests API** y **1517 tests Flutter** PASS, `analyze` sin issues |
| SIG-01 | Estado de firma de los artefactos | `FullPOS-Setup-1.0.7-150.exe`, `…UAT…rc.2-150002.exe` y `…rc.3-150003.exe`: **NotSigned** (sin certificado; no se fabrificó ninguno) |
| WIN-01 | La app **instalada** abre y se mantiene viva | ventana `FullPOS Cloud - Sistema de facturacion`, proceso vivo, base y log en la raíz aislada; todas las peticiones a `127.0.0.1:4010` |
| WIN-02 | POS desde la app instalada | Facturación con catálogo, búsqueda, Venta rápida, `Turno: Abierto` y ticket; chip `UAT` |
| WIN-03 | Centro de recuperación desde la app instalada | con 1 cobro sintético muestra `Requiere intervención`, `RD$ 75,00` y las acciones; la declaración «sí recibimos el dinero» devuelve **201** y crea **1 obligación PENDING** de 75,00 en el servidor |
| WIN-04 | Build de producción sin restos de UAT | `app.so`: `easypanel`×7, `daleventapos-backend`×5, `127.0.0.1:4010`=0, `FULLPOS_UAT_PROFILE`=0, `C:\src\fullpos`=0, `guardian`=0 |
| WIN-05 | Credenciales de la build UAT aisladas de la instalación real | login vacío, `_bootstrap() no local session`, base `fulltech_offline.uat.db`; `flutter_secure_storage.dat` (`1B64041D…`) y `shared_preferences.json` (`F7F687E4…`) de la app real con el **mismo SHA256** antes y después |
| PILOT-01 | Ensayo del piloto 148→150 sobre **copia** de la base real | `user_version 5`, 8 tablas, `offline_sales=1`, items=2, payments=1, inventario=2, pendientes=0 → **idénticos**; base original con SHA256 y tamaño sin cambios |
| PGBK-01 | Respaldo + **restauración probada** | dump 637.105 B, 127 bloques `TABLE DATA`, restore en base aparte exit 0, conteos idénticos (95/24/19/55) |
| STABLE-01 | Canal estable intacto | sigue ofreciendo **solo** `releases/windows/stable/1.0.6-148/…` |

### Nota de reproducibilidad de la suite

`flutter test` usa un directorio compartido (`.dart_tool/sqflite_common_ffi/databases`).
Si se dejan bases de ejecuciones anteriores, `offline_store_large_migration_test`
y los tests de `sale_attempt_*` pueden fallar en falso (se observaron hasta 28
fallos espurios; con el directorio limpio son 0). Antes de una corrida de
aceptación:

```powershell
cd apps\fulltech_app
Remove-Item '.dart_tool\sqflite_common_ffi\databases\*' -Recurse -Force -ErrorAction SilentlyContinue
flutter test
```

Además, `test/modules/cash/turn_current_no_session_test.dart` y las pruebas de
migración de 85 MB pueden fallar de forma intermitente por bloqueos de SQLite de
10 s bajo carga (`Warning database has been locked for 0:00:10`): pasan siempre en
aislamiento y en su carpeta (`test/core/offline` → 125 PASS). Se observaron
corridas con 28 y 29 fallos mientras se compilaba o se ejecutaban apps en paralelo;
con la máquina libre la suite da **1483 PASS / 9 skip / 0 FAIL** sobre `cebd9aa6`.

### NO EJECUTADO (declarado, no se presenta como PASS)

| ID | Caso | Motivo |
| --- | --- | --- |
| UAT-NE-01 | Dos equipos físicos simultáneos de la misma empresa | solo hay un escritorio; el aislamiento se probó por tenant y la concurrencia en proceso |
| UAT-NE-02 | Reinicio de **Windows** y cierre forzado del proceso real a mitad de sincronización | requiere intervención sobre la máquina; la durabilidad del archivo se probó a nivel de fichero (DURA-01) y el backoff con tests de cola real |
| UAT-NE-03 | Reconexión tras varias horas de desconexión | se probó el backoff real (5–8 s), no horas de espera |
| UAT-NE-04 | HTTP 429 real | este UAT no tiene rate limiter que lo produzca; se cubrió a nivel unitario (Retry-After respetado) |
| UAT-NE-05 | HTTP 500 real del servidor | no se inyectó fallo en el proceso; se probó red caída y puerto muerto |
| UAT-NE-06 | Regresión funcional de NCF/clientes sobre la copia migrada | la migración se ensayó sobre copia real (MIG-01) pero **no** se levantó la app contra esa copia para revisar NCF/clientes |
| UAT-NE-07 | Importación del caso Siarah | el importador está en dry-run por defecto y exige importe con evidencia + autorización; no se ejecutó sobre datos reales |
| UAT-NE-08 | Instalador `.exe` (Inno Setup) **firmado** | no hay certificado Authenticode en el equipo; los artefactos son `NotSigned` y las advertencias de SmartScreen están documentadas en `RECOVERY-ENGINE-V2-ROLLOUT.md` §8.4 |
| UAT-NE-09 | Actualización `148 → 1.0.7+150` en un equipo piloto real | exige ejecutar el instalador de producción sobre la instalación de un cliente: requiere autorización del propietario (§8.5) |

---

## 3. Cómo probar el ejecutable UAT (con aislamiento OBLIGATORIO)

Carpeta entregada:

```
C:\src\fullpos-recovery-v2\uat-artifacts\FullPOS-UAT-1.0.6-uat.2-148900\
```

1. Levantar la base y la API UAT:
   ```powershell
   docker start fullpos_recovery_uat_pg
   cd C:\src\fullpos-recovery-v2\apps\api
   node dist/main.js        # escucha en 127.0.0.1:4010
   ```
2. Ejecutar la app **con almacenamiento aislado** (sin esto se niega a arrancar):
   ```powershell
   $sandbox = 'C:\src\fullpos-recovery-v2\uat-runtime-sandbox'
   $env:APPDATA             = "$sandbox\Roaming"
   $env:LOCALAPPDATA        = "$sandbox\Local"
   $env:DALEVENTAS_POS_ROOT = "$sandbox\pos-root"
   & 'C:\src\fullpos-recovery-v2\uat-artifacts\FullPOS-UAT-1.0.6-uat.2-148900\fullpos_cloud.exe'
   ```
3. Registrar un negocio de prueba desde la propia app (correo `@daleventa.local`).
4. Vender en efectivo y, desde el **Centro de recuperación**, probar:
   verificar, declarar «no se realizó», declarar «sí recibí el dinero» y
   revisar que la obligación aparece como *Conciliación pendiente*.
5. Comprobar en la base:
   ```sql
   SELECT client_request_id, total_declared, status, declared_by_role
   FROM sale_reconciliation_obligations ORDER BY created_at DESC;
   ```
6. Pruebas automáticas reproducibles:
   ```powershell
   node scripts/uat/recovery-v2-acceptance.cjs          # 25 casos HTTP
   cd apps\fulltech_app
   flutter test test\integration_uat\recovery_live_api_test.dart `
     --dart-define=UAT_API_BASE=http://127.0.0.1:4010   # 4 casos cliente↔servidor
   ```
7. Durabilidad y migración (escriben en disco, por eso exigen raíz aislada;
   sin `DALEVENTAS_POS_ROOT` la prueba se OMITE y no toca la carpeta compartida):
   ```powershell
   cd apps\fulltech_app
   $env:DALEVENTAS_POS_ROOT = 'C:\src\fullpos-recovery-v2\uat-artifacts\durability-root'
   # opcional: copia de una base real para el ensayo de migración (nunca la original)
   $env:UAT_LEGACY_DB = 'C:\src\fullpos-recovery-v2\uat-artifacts\legacy-copy\fulltech_offline.db'
   flutter test test\integration_uat\sqlite_durability_test.dart `
     --dart-define=UAT_API_BASE=http://127.0.0.1:4010   # DURA-01 + MIG-01
   ```
   Evidencia esperada: `SNAPSHOT files=2 … skipped=[-shm]` y
   `REHEARSAL {user_version_before: 5, user_version_after: 5, … rows_after: 481}`.

---

## 4. Compatibilidad con clientes actuales

- Migración **aditiva** (`CREATE TABLE` + índices): 145–148 siguen operando igual.
- El backend puede desplegarse **antes** que el cliente nuevo.
- Sin migración de SQLite: `pending_actions` ya existía; no se añadieron tablas ni
  columnas locales (las suites de migración v2/v3 → actual siguen pasando).
- Un cliente nuevo contra un backend viejo recibiría 404 al declarar: la declaración
  queda en la cola como `failed` (visible, no se pierde). Por eso el orden
  recomendado es **backend primero**.

---

## 5. Qué falta exactamente para autorizar producción

1. UAT en **dos equipos físicos** con la misma empresa.
2. **Cierre forzado** del proceso y **reinicio de Windows** durante la sincronización.
3. **429 y 500 reales** (proxy o rate-limit delante del backend).
4. Ensayo de migración sobre **copia de base 145–148** con WAL/SHM y regresión
   funcional de NCF, clientes, turnos e inventario.
5. Importación del caso Siarah con importes aportados y autorización explícita.
6. **Instalador firmado** (Inno Setup) + prueba de actualización 148 → candidato.
7. Autorizaciones de despliegue (migración en producción, backend, publicación).

---

## 6. Dictamen

**GO de la fase UAT** para el código de esta rama: la autocorrección y la
conciliación financiera funcionan de extremo a extremo contra un backend y una
base reales, sin duplicar ventas ni perder obligaciones, con aislamiento por
empresa verificado y con almacenamiento local aislado **demostrado** (la app no
puede abrir las bases reales del cliente).

**NO-GO para publicar** hasta cerrar: UAT en dos equipos, reinicio/cierre forzado,
reconexión larga, 429/500 reales, ensayo sobre copia de base 145–148, instalador
firmado y las autorizaciones de despliegue.
