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
| DEV-01 | Dos dispositivos, misma declaración | 2 registros auditables (actores distintos) |
| DEV-02 | Rectificación desde el dispositivo B | 3.º registro, `duplicate=false` |
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
| SUITE-02 | `flutter test` (suite completa) | **1483 PASS, 8 skip, 0 FAIL** |
| SUITE-03 | API `npm run api:build` + tests | build 0 · 80 suites / 819 tests PASS, 8 skip |

### NO EJECUTADO (declarado, no se presenta como PASS)

| ID | Caso | Motivo |
| --- | --- | --- |
| UAT-NE-01 | Dos equipos físicos simultáneos de la misma empresa | solo hay un escritorio; el aislamiento se probó por tenant y la concurrencia en proceso |
| UAT-NE-02 | Reinicio de Windows y cierre forzado del proceso a mitad de sincronización | requiere intervención sobre la máquina; el backoff y la persistencia están cubiertos por tests de cola real |
| UAT-NE-03 | Reconexión tras varias horas de desconexión | se probó el backoff real (5–8 s), no horas de espera |
| UAT-NE-04 | HTTP 429 real | este UAT no tiene rate limiter que lo produzca; se cubrió a nivel unitario (Retry-After respetado) |
| UAT-NE-05 | HTTP 500 real del servidor | no se inyectó fallo en el proceso; se probó red caída y puerto muerto |
| UAT-NE-06 | Copia de base SQLite real de 145–148 con WAL/SHM y regresión de NCF/clientes | no se localizó una base real aislada; la migración se validó con las suites `sale_attempt_schema_migration_test` (v2/v3→actual, con auditoría) |
| UAT-NE-07 | Importación del caso Siarah | el importador está en dry-run por defecto y exige importe con evidencia + autorización; no se ejecutó sobre datos reales |
| UAT-NE-08 | Instalador `.exe` (Inno Setup) firmado | se entregó la carpeta `Release` empaquetada, no un instalador |

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
   node scripts/uat/recovery-v2-acceptance.cjs          # 23 casos HTTP
   cd apps\fulltech_app
   flutter test test\integration_uat\recovery_live_api_test.dart `
     --dart-define=UAT_API_BASE=http://127.0.0.1:4010   # 3 casos cliente↔servidor
   ```

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
