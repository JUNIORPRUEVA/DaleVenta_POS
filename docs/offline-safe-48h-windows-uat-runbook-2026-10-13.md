# FullPOS Cloud Offline Safe 48h - Runbook Windows UAT

Fecha: 2026-10-13
Worktree esperado: `C:\src\fullpos-offline-safe-48h`
Rama esperada: `feature/offline-safe-48h`

## 1. Alcance

Este runbook valida la app Windows contra UAT local aislado, sin usar produccion, sin instalador comercial y con almacenamiento local separado en `.uat\windows-app-root`.

No autoriza deploy, push, merge, migraciones productivas, seed productivo, ni canal comercial de actualizaciones.

## 2. Preparacion

1. Abrir PowerShell en `C:\src\fullpos-offline-safe-48h`.
2. Verificar rama:

```powershell
git branch --show-current
```

Debe responder `feature/offline-safe-48h`.

3. Levantar UAT local:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/uat/start.ps1
```

Confirmar en la salida:

- `ENVIRONMENT: UAT LOCAL`
- `DATABASE: daleventa_offline_safe_48h_uat`
- `DATABASE_PORT: 56548`
- `API: http://127.0.0.1:46548`
- `PRODUCTION: NOT CONNECTED`

4. Confirmar salud API:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:46548/health
```

## 3. Ejecutar app Windows aislada

Opcion portable release:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/uat/run-windows-portable.ps1
```

Opcion debug por Flutter:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/uat/run-windows.ps1
```

Ambas opciones deben mostrar:

- `WINDOWS_UAT_ROOT: C:\src\fullpos-offline-safe-48h\.uat\windows-app-root`
- `API_BASE_URL: http://127.0.0.1:46548`
- `UPDATER: DISABLED`

No continuar si aparece un host remoto, `31.97.99.70`, `easypanel`, `gcdndd`, o una ruta de datos bajo `C:\Program Files\DaleVentas POS`.

## 4. Flujo funcional manual

1. Iniciar sesion con las credenciales UAT creadas por `scripts/uat/start.ps1`.
2. Confirmar que productos/caja cargan desde UAT.
3. Abrir caja si no esta abierta.
4. Ejecutar una venta normal online de producto con inventario.
5. Cerrar la app.
6. Confirmar que existe SQLite bajo `.uat\windows-app-root\databases`.
7. Abrir la app otra vez.
8. Desconectar el API local o bloquear temporalmente red local hacia `127.0.0.1:46548`.
9. Ejecutar venta no fiscal, completamente en efectivo.
10. Confirmar mensaje de venta guardada y cola pendiente.
11. Cerrar y reabrir app.
12. Confirmar que la venta offline sigue visible/pendiente.
13. Restaurar API local.
14. Esperar sincronizacion o forzar accion de sincronizar si la UI la expone.
15. Confirmar que la cola queda sin pendientes o con error explicito no silencioso.

## 5. Verificacion PostgreSQL UAT

Despues de sincronizar, consultar solo la base UAT:

```powershell
docker exec fullpos_offline_safe_48h_postgres psql -U daleventa_offline_safe_48h_user -d daleventa_offline_safe_48h_uat -c "select id, client_request_id, \"cashSessionId\", \"totalSold\", \"createdAt\" from \"Sale\" order by \"createdAt\" desc limit 5;"
docker exec fullpos_offline_safe_48h_postgres psql -U daleventa_offline_safe_48h_user -d daleventa_offline_safe_48h_uat -c "select \"saleId\", \"productId\", qty, \"priceSoldUnit\", \"createdAt\" from \"SaleItem\" order by \"createdAt\" desc limit 5;"
docker exec fullpos_offline_safe_48h_postgres psql -U daleventa_offline_safe_48h_user -d daleventa_offline_safe_48h_uat -c "select product_id, quantity_delta, source_type, source_id, created_at from inventory_movements order by created_at desc limit 5;"
```

Aceptar solo si:

- La venta sincronizada tiene `client_request_id` estable.
- Hay una sola venta por `client_request_id`.
- El movimiento de inventario corresponde a la venta.
- La caja corresponde al turno UAT.

## 6. Recuperacion SQLite

Validaciones manuales recomendadas:

1. Con app cerrada, copiar el contenido de `.uat\windows-app-root\databases` como respaldo de evidencia.
2. Corromper solo una copia UAT de la DB o sus archivos `-wal` / `-shm`; nunca usar datos reales.
3. Abrir app y confirmar que se crea respaldo en `db_recovery` y que el error se informa.
4. Simular archivo bloqueado abriendo la DB UAT con otra herramienta y confirmar que la app no queda congelada.
5. Simular falta de permisos sobre `.uat\windows-app-root\databases` y confirmar que la app falla con mensaje/registro, no de forma silenciosa.

## 7. Updater UAT

El updater queda desactivado por `DISABLE_APP_UPDATES=true` en scripts UAT. Para bench separado, usar solo paquetes falsos en `.uat`, nunca el canal comercial.

No declarar PASS de updater hasta validar:

- Descarga `.part` incompleta y reintento.
- Promocion `.ready`.
- Validacion SHA.
- Firma o rechazo explicito.
- Resultado del updater nativo.
- Preservacion de `.uat\windows-app-root\databases`, `-wal`, `-shm`, `updates` y `db_recovery`.

## 8. Criterio GO/NO-GO

GO UAT Windows manual solo si todo el flujo de las secciones 3 a 7 se ejecuto con evidencia local y sin tocar produccion.

NO-GO si no se pudo controlar la app Windows nativa, si no hay evidencia SQLite/PG, si hubo acceso a produccion, o si queda duda sobre caja/inventario/auth/updater.

## 9. Evidencia observada en Fase 6

HECHO: el build release UAT abrio la ventana nativa con titulo `FullPOS Cloud - Sistema de facturacion [UAT]` y uso mutex separado `Local\DaleVentasPOSSingleInstance-UAT`.

HECHO: con `DALEVENTAS_POS_ROOT=C:\src\fullpos-offline-safe-48h\.uat\windows-app-root-isolated-20261013134014`, la app creo:

- `databases\fulltech_offline.db`;
- `databases\fulltech_offline.db-wal`;
- `databases\fulltech_offline.db-shm`;
- `logs\fullpos-client.log`.

HECHO: la base SQLite inicial midio 4096 bytes antes de aplicar WAL, lo que confirma raiz UAT limpia sin copia legacy.

LIMITACION: esta evidencia fue de arranque/proceso/archivos. No se completo interaccion GUI manual de login, venta offline, reapertura y sincronizacion desde la pantalla.

## 10. Acciones exactas para UAT manual Fase 7

### 10.1 Abrir UAT local

En una PowerShell:

```powershell
cd C:\src\fullpos-offline-safe-48h
powershell -ExecutionPolicy Bypass -File scripts/uat/start.ps1
powershell -ExecutionPolicy Bypass -File scripts/uat/run-backend.ps1
```

Dejar esa ventana abierta. Debe indicar API local `http://127.0.0.1:46548`.

En una segunda PowerShell:

```powershell
cd C:\src\fullpos-offline-safe-48h
powershell -ExecutionPolicy Bypass -File scripts/uat/run-windows-portable.ps1 -SkipBuild
```

El ejecutable es:

```text
C:\src\fullpos-offline-safe-48h\apps\fulltech_app\build\windows\x64\runner\Release\fullpos_cloud.exe
```

### 10.2 Credenciales UAT

Usuario:

```text
uat.admin@daleventa.local
```

La contrasena ficticia esta solo en el archivo local ignorado:

```text
C:\src\fullpos-offline-safe-48h\apps\api\.env.offline-safe-48h.uat.local
```

Campo:

```text
UAT_ADMIN_PASSWORD
```

No copiar esta contrasena a commits, tickets, capturas publicas ni reportes.

### 10.3 Simular desconexion

Usar solo la API UAT local. En la PowerShell donde corre `scripts/uat/run-backend.ps1`, presionar:

```text
Ctrl+C
```

No detener Docker/PostgreSQL y no tocar servicios de produccion.

### 10.4 Reconectar

En la misma PowerShell:

```powershell
cd C:\src\fullpos-offline-safe-48h
powershell -ExecutionPolicy Bypass -File scripts/uat/run-backend.ps1
```

Validar:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:46548/health
```

### 10.5 Ver pendientes SQLite

Con la app cerrada, ejecutar:

```powershell
sqlite3 .uat\windows-app-root\databases\fulltech_offline.db "select status, count(*) from pending_actions group by status; select status, count(*) from offline_sales group by status; pragma integrity_check;"
```

Aceptar solo si `integrity_check` responde `ok`. Antes de reconectar deben existir pendientes si se hicieron ventas offline. Despues de sincronizar deben quedar sin pendientes o con error explicito revisable.

### 10.6 Ver PostgreSQL UAT

Consultar solo el contenedor UAT:

```powershell
docker exec fullpos_offline_safe_48h_postgres psql -U daleventa_offline_safe_48h_user -d daleventa_offline_safe_48h_uat -c "select id, client_request_id, ""cashSessionId"", ""totalSold"", ""createdAt"" from ""Sale"" order by ""createdAt"" desc limit 10;"
docker exec fullpos_offline_safe_48h_postgres psql -U daleventa_offline_safe_48h_user -d daleventa_offline_safe_48h_uat -c "select ""saleId"", ""productId"", qty, ""priceSoldUnit"", ""createdAt"" from ""SaleItem"" order by ""createdAt"" desc limit 10;"
docker exec fullpos_offline_safe_48h_postgres psql -U daleventa_offline_safe_48h_user -d daleventa_offline_safe_48h_uat -c "select product_id, quantity_delta, source_type, source_id, created_at from inventory_movements order by created_at desc limit 10;"
```

### 10.7 Bancos seguros

Updater UAT aislado:

```powershell
powershell -ExecutionPolicy Bypass -File apps/fulltech_app/windows/updater/updater_harness_test.ps1 -UpdaterPath apps/fulltech_app/build/windows/x64/runner/Release/updater/FullposUpdater.exe
powershell -ExecutionPolicy Bypass -File scripts/uat/run-updater-preservation-bench.ps1
```

Errores SQLite seguros:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/uat/run-sqlite-failure-bench.ps1
```

Estos bancos usan `.uat` y no instalan sobre FullPOS Cloud estable.

## 11. Complemento Fase 8

### 11.1 Smoke automatico de integridad sync

Con la API UAT encendida en `127.0.0.1:46548`, ejecutar:

```powershell
cd C:\src\fullpos-offline-safe-48h
powershell -ExecutionPolicy Bypass -File scripts/uat/run-sync-integrity-smoke.ps1
```

Debe terminar con `status: PASS` y mostrar:

- 3 ventas creadas;
- 3 `clientRequestId` distintos;
- 1 turno asociado a esas ventas;
- total vendido conciliado;
- 3 items;
- 3 movimientos de inventario;
- rechazo `409 INSUFFICIENT_WAREHOUSE_STOCK` para la venta de stock insuficiente.

Este smoke no sustituye la UAT visual: valida la API, idempotencia, turno original y conciliacion PostgreSQL con datos ficticios.

### 11.2 Verificar proceso y archivos Windows UAT

```powershell
Get-Process fullpos_cloud | Select-Object Id,MainWindowTitle,Responding,Path
Get-ChildItem .uat\windows-app-root -Recurse -File | Select-Object FullName,Length,LastWriteTime
sqlite3 .uat\windows-app-root\databases\fulltech_offline.db "select count(*) from pending_actions; select count(*) from offline_sales; pragma integrity_check;"
Get-Content .uat\windows-app-root\logs\fullpos-client.log -Tail 120
```

La ventana UAT debe incluir `[UAT]` en el titulo y su ruta debe estar bajo:

```text
C:\src\fullpos-offline-safe-48h
```

Si aparece una ventana sin `[UAT]` o bajo otro directorio, no usarla para esta prueba.

### 11.3 Cierre seguro de servicios UAT

Para detener la API UAT, usar `Ctrl+C` en la PowerShell donde corre:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/uat/run-backend.ps1
```

Para cerrar la app UAT, cerrar la ventana `[UAT]`. Si queda colgada, detener solo el proceso cuya ruta apunte a `C:\src\fullpos-offline-safe-48h`:

```powershell
$target = 'C:\src\fullpos-offline-safe-48h'
Get-Process fullpos_cloud -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -like "$target*" } |
  Stop-Process -Force
```

No cerrar ni sobrescribir instalaciones estables de FullPOS Cloud.

## 12. Complemento Fase 9

### 12.1 Estado visual esperado

En Ventas, cuando el catalogo cae al snapshot local, no debe aparecer una franja grande de desconexion. Debe verse un indicador compacto:

```text
Catalogo local
```

El indicador puede actualizar el catalogo y su tooltip explica que los productos vienen de este equipo hasta recuperar conexion.

Despues de cobrar:

- venta confirmada online: `Venta confirmada por el servidor.`;
- venta guardada local: `Venta guardada en este equipo. Pendiente de sincronizacion.`;
- venta no guardada: debe mostrar un error claro y no debe anunciar cobro confirmado.

### 12.2 Primera accion manual

Con la ventana `FullPOS Cloud - Sistema de facturacion [UAT]` abierta, iniciar sesion con:

```text
uat.admin@daleventa.local
```

La contrasena esta en el archivo local ignorado:

```text
C:\src\fullpos-offline-safe-48h\apps\api\.env.offline-safe-48h.uat.local
```

Campo:

```text
UAT_ADMIN_PASSWORD
```

No imprimir ni capturar la contrasena.

### 12.3 Evidencia tecnica previa a la operacion manual

Antes del login manual de Fase 9 se verifico:

- API UAT `http://127.0.0.1:46548/health`: `ok`;
- PostgreSQL UAT `127.0.0.1:56548`;
- base `daleventa_offline_safe_48h_uat`;
- `PRODUCTION: NOT CONNECTED`;
- usuarios UAT: `2`;
- productos UAT: `5`;
- filas de inventario UAT: `5`;
- SQLite UAT `integrity_check`: `ok`;
- `pending_actions`: `0`;
- `offline_sales`: `0`;
- updater UAT deshabilitado.

Hay `2` sesiones de caja abiertas en la base UAT local; no se cerraron automaticamente para no modificar estado UAT antes de que el operador vea la pantalla real.
