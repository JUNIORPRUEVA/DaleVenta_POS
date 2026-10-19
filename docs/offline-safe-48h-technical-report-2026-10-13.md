# FullPOS Cloud Offline Safe 48h - Informe tecnico

Fecha: 2026-10-13
Worktree: `C:\src\fullpos-offline-safe-48h`
Rama: `feature/offline-safe-48h`
Commit base observado: `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`
Merge-base con `origin/production-main`: `bdb0d10e08e197adb68b302410c0a131fa83b2bc`

## A. Estado anterior

HECHO: existia una primera implementacion cliente de politica offline de 48 horas en Flutter, con bloqueo fiscal offline, restriccion a efectivo y persistencia atomica de venta local + accion pendiente.

HECHO: la implementacion anterior renovaba la autorizacion offline desde cualquier respuesta HTTP 2xx del API. Ese comportamiento era demasiado amplio para una politica de continuidad de ventas porque un endpoint no dedicado podia refrescar la ventana offline.

HECHO: `OfflineStore` ya persistia ventas offline, pagos, items, intenciones de inventario y cola pendiente en SQLite con una transaccion local; en web o fallo de SQLite cae a SharedPreferences como modo limitado.

## B. Arquitectura final

Flujo autorizado:

1. Cliente autenticado llama `POST /auth/offline-emergency/authorize`.
2. Backend valida JWT, sesion activa, empresa activa, usuario no bloqueado, membresia/empresa, licencia usable y `x-client-device-id`.
3. Backend devuelve autorizacion con `policyVersion`, `companyId`, `userId`, `sessionId`, `deviceFingerprint`, `serverUtc`, `validUntilUtc` y `maxOfflineHours`.
4. Flutter almacena localmente la autorizacion por `companyId:userId` y vinculada al dispositivo.
5. Al caer la red durante `sales.create`, Flutter permite crear venta local solo si la autorizacion corresponde a la misma empresa, usuario y dispositivo, no vencio, y no hay retroceso inseguro del reloj.
6. La venta local y su accion `sales.create` pendiente se guardan atomicamente.
7. La cola sincroniza despues con `clientRequestId` estable y el backend mantiene idempotencia por `companyId + clientRequestId`.

## C. Archivos modificados

- `apps/api/src/auth/auth.controller.ts`: endpoint dedicado de autorizacion offline.
- `apps/api/src/auth/auth.service.ts`: validacion backend de sesion, usuario, empresa, licencia, dispositivo y ventana de 48h.
- `apps/api/src/auth/jwt.strategy.ts`: conserva `sessionId` en `req.user` para validacion dedicada.
- `apps/api/src/auth/auth.service.spec.ts`: pruebas backend de autorizacion offline.
- `apps/fulltech_app/lib/core/api/api_routes.dart`: ruta cliente del endpoint dedicado.
- `apps/fulltech_app/lib/core/auth/auth_repository.dart`: solicitud no bloqueante de autorizacion offline despues de hidratar/confirmar sesion.
- `apps/fulltech_app/lib/core/offline/offline_emergency_policy.dart`: politica local con version, empresa, usuario, dispositivo, vencimiento y rollback.
- `apps/fulltech_app/lib/core/offline/offline_emergency_validation_interceptor.dart`: ya no registra cualquier 2xx; solo procesa la respuesta del endpoint dedicado.
- `apps/fulltech_app/lib/core/usage/client_telemetry_headers.dart`: el `x-client-device-id` sobrevive aunque falle `package_info_plus`.
- `apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart`: la venta offline exige autorizacion vinculada al dispositivo.
- `apps/fulltech_app/test/core/offline/offline_emergency_policy_test.dart`: pruebas de autorizacion, vencimiento, rollback y dispositivo.
- `apps/fulltech_app/test/features/ventas/ventas_offline_tax_ticket_test.dart`: regresion de venta offline autorizada y bloqueo de casos no permitidos.

## D. Proteccion de produccion

HECHO: no se hizo deploy, push, merge, seed, migracion ni escritura contra bases compartidas.

HECHO: `127.0.0.1:55432` fue identificado previamente como otro contenedor; no se uso para pruebas de escritura. El trabajo se mantuvo en codigo y pruebas locales.

HECHO: `npx prisma validate` se ejecuto con `DATABASE_URL` ficticio local no sensible solo para validar schema, sin conectar ni escribir.

## E. Seguridad

HECHO: una respuesta HTTP 2xx generica ya no renueva offline.

HECHO: la autorizacion requiere sesion autenticada y validada por `JwtStrategy`, licencia usable, empresa activa y dispositivo identificado.

HECHO: la autorizacion local esta limitada por `policyVersion`, `companyId`, `userId`, `deviceFingerprint`, `serverUtc` y `validUntilUtc`.

HECHO: la autorizacion local ahora se sella con HMAC SHA-256 y una clave local creada en `flutter_secure_storage`. Si el JSON editable en SharedPreferences cambia y el sello seguro existe, la politica bloquea como `corruptedValidation`.

LIMITACION: el sello es una proteccion local proporcional; no incorpora secretos del servidor en Flutter y no pretende resistir un dispositivo completamente comprometido con acceso a secure storage. En plataformas/tests donde secure storage no este disponible, la politica mantiene validacion de alcance, expiracion y rollback, pero sin sello anti-tamper.

## F. Persistencia

HECHO: las ventas offline se guardan con `offline_sales`, `offline_sale_items`, `offline_sale_payments`, `offline_inventory_intents` y `pending_actions` en una transaccion SQLite cuando el motor esta disponible.

HECHO: el vencimiento de la autorizacion bloquea nuevas ventas, pero no borra pendientes ni impide que pendientes existentes se intenten sincronizar.

PENDIENTE UAT: pruebas manuales de cierre forzado, reinicio de Windows, base bloqueada, disco lleno y recuperacion de WAL/SHM.

## G. Sincronizacion

HECHO: el cliente conserva `clientRequestId` estable por venta; el backend busca venta existente por `companyId + clientRequestId` y devuelve la existente ante duplicado.

HECHO: la cola distingue estados `pending`, `syncing`, `error`, `conflict`, `requires_action`, `auth_blocked`, `obsolete` y no marca sincronizado solo por enviar.

PENDIENTE UAT/integracion: pruebas reales contra PostgreSQL aislado de timeout, respuesta perdida, 401, 500, reintento simultaneo y colision con payload distinto.

## H. Caja e inventario

HECHO: la venta offline mantiene `originCashSessionId` original y envia `originTerminalId`, `terminalId`, `warehouseId` y `deviceFingerprint` cuando estan disponibles.

HECHO: el backend ya rechaza ventas sin `originCashSessionId` y no reasigna silenciosamente al turno actual.

HECHO: el alcance implementado permite solo ventas normales, no fiscales, completamente en efectivo.

PENDIENTE UAT: validar turno cerrado, conciliacion humana y conflictos de inventario con otro dispositivo vendiendo online.

## I. Pruebas ejecutadas

- `flutter test test/core/offline/offline_emergency_policy_test.dart test/features/ventas/ventas_offline_tax_ticket_test.dart`: PASS.
- `flutter analyze`: PASS.
- `npx prisma validate` con URL local ficticia: PASS.
- `npx prisma generate`: PASS.
- `npx jest --runInBand src/auth/auth.service.spec.ts`: PASS.
- `npm run api:build`: PASS.
- `flutter test`: PASS (`+1274 ~1`).

## J. Pruebas pendientes

- UAT manual Windows con app de pruebas, SQLite independiente y API/base aisladas.
- Pruebas con impresora/cajon reales.
- Pruebas de sincronizacion contra PostgreSQL UAT desechable con fixtures ficticios.
- Pruebas de updater Windows preservando SQLite, WAL, SHM y pendientes.

## K. Riesgos residuales

P0: no hay UAT real de perdida de respuesta / reintento simultaneo contra PostgreSQL aislado en esta ejecucion.

P1: no se validaron fallos fisicos de almacenamiento, disco lleno, corrupcion SQLite ni apagado abrupto real.

P1: la autorizacion offline tiene sello local HMAC respaldado por secure storage, pero no firma de servidor ni tiempo confiable offline absoluto; no protege contra control total del dispositivo.

P2: inventario offline es estimado; conflictos con otros dispositivos online requieren reconciliacion/estado `requires_action`.

## L. Compatibilidad

HECHO: la politica falla cerrado para snapshots viejos/corruptos que no tengan version, empresa, usuario y dispositivo; requiere reconexion para renovar.

HECHO: no se cambio ruta de SQLite ni esquema de Prisma.

PENDIENTE: UAT de actualizacion Windows para confirmar que pendientes existentes sobreviven al instalador/updater.

## M. Estado por modulo

- Autorizacion offline: implementado y verificado automaticamente.
- Venta offline minima en efectivo: implementado y verificado automaticamente.
- Fiscal offline: bloqueado.
- Cola pendiente: auditada a nivel codigo, pruebas focales existentes pasan.
- Backend idempotencia venta: auditado a nivel codigo, build pasa.
- UAT con PostgreSQL aislado: pendiente.
- Updater Windows: pendiente.
- Hardware impresion/caja: pendiente.

## N. GO / NO-GO

GO para continuar desarrollo: validaciones automaticas criticas PASS.

GO para UAT manual: usar entorno aislado y datos ficticios.

NO-GO para produccion: faltan UAT manual, PostgreSQL aislado con fixtures, pruebas de updater y hardware cuando aplique.

## O. Proximos pasos

1. Crear entorno UAT desechable PostgreSQL + API local con integraciones externas deshabilitadas.
2. Ejecutar guion manual Windows con login online, autorizacion offline, venta en efectivo, reinicio, reconexion y sincronizacion.
3. Probar reintentos idempotentes y turno original cerrado.
4. Probar actualizacion Windows ficticia preservando base local y pendientes.

## P. Evidencia nueva de Fase 3

### P.1 Seguridad del endpoint

HECHO: se agregaron pruebas unitarias backend para:

- sesion valida con autorizacion de 48h exactas;
- ausencia de `x-client-device-id`;
- sesion revocada/cambiada;
- usuario no activo en la empresa del token;
- licencia no usable.

HECHO: `JwtStrategy` ya valida sesion activa, empresa activa/licencia y usuario no bloqueado antes de llegar al controller; el servicio vuelve a validar sesion, usuario, empresa y licencia antes de emitir autorizacion.

LIMITACION: el endpoint recibe `x-client-device-id`, que sirve como vinculacion de instalacion/terminal y no como prueba fuerte de hardware. La seguridad fuerte sigue siendo JWT + sesion activa + licencia + sello local de autorizacion; la cabecera por si sola no debe tratarse como identidad infalsificable.

LIMITACION: no se implemento una regla nueva de permiso granular `createSales` porque el contrato actual de `POST /sales` no exige ese permiso. Cambiarlo ahora afectaria comportamiento online existente y requiere decision de producto.

### P.2 Blindaje local anti-tamper

HECHO: `OfflineEmergencyPolicy` ahora escribe la autorizacion en SharedPreferences y un sello HMAC SHA-256 en secure storage. La prueba `blocks tampered local authorization when a secure seal exists` modifica el JSON local para extender la ventana hasta 7 dias y el cliente bloquea con `corruptedValidation`.

HECHO: la prueba `ignores authorization responses longer than 48 hours` confirma que una respuesta dedicada con `validUntilUtc` mayor a 48h no queda registrada.

### P.3 SQLite real

HECHO: se ejecuto `flutter test test/core/offline/offline_store_sales_test.dart` con `sqflite_common_ffi`: PASS. Cubre guardado atomico de venta, items, pagos, intents de inventario, outbox, deduplicacion por idempotency key, marcado synced/conflict, reinicio del store y recuperacion de acciones `syncing` obsoletas.

HECHO: se ejecuto `flutter test` completo despues del refuerzo anti-tamper: PASS (`+1274 ~1`).

### P.4 PostgreSQL / UAT

HECHO: `docker ps` mostro `daleventas_uat_postgres` en `127.0.0.1:55433` y `phytoemagry-prod-clone-db` en `55432`. Se inspecciono `daleventas_uat_postgres` sin imprimir variables de entorno ni secretos; pertenece a otro worktree (`C:\dv-hotfix-pag`) y compose project `uat`.

NO-GO: no se escribio en ese PostgreSQL porque no pertenece a este worktree aislado ni se demostro que sea desechable para esta tarea. No hay PASS real de PostgreSQL/UAT end-to-end en esta fase.

### P.5 Idempotencia PostgreSQL

HECHO: `apps/api/prisma/schema.prisma` contiene `@@unique([companyId, clientRequestId])` en `Sale`. `SalesService.create` busca venta existente por ese par antes de crear y captura `P2002` para devolver la venta existente si dos solicitudes compiten. Esto cubre la barrera de duplicacion economica a nivel DB para ventas con `clientRequestId`.

PENDIENTE: falta prueba concurrente real contra PostgreSQL aislado para misma venta enviada dos veces, timeout posterior a persistencia, respuesta perdida y payload distinto con mismo `clientRequestId`.

### P.6 Vulnerabilidades `npm audit`

HECHO: `npm audit --json` reporto 15 vulnerabilidades totales: 3 moderadas, 10 altas y 2 criticas.

HECHO: `npm audit --omit=dev --json` reporto 7 vulnerabilidades de dependencias de produccion:

- `proxy-addr` critica, transitive, posible spoofing de IP por IPv4-mapped IPv6 trust subnet. Relevancia: alta si Express/Nest confia en proxy headers para IP/rate-limit/auditoria.
- `@nestjs/platform-express` alta por `multer`. Relevancia: alta en endpoints con uploads multipart.
- `multer` alta, transitive, multiples DoS/file handling issues. Relevancia: alta donde haya carga de archivos.
- `compression` alta, directa, DoS por memory leak en cierre prematuro. Relevancia: alta si middleware esta activo en API publica.
- `engine.io` alta, transitive de Socket.IO, DoS por protocol mismatch. Relevancia: media/alta en realtime publico.
- `sharp` alta, directa, vulnerabilidades en dependencias nativas de imagen. Relevancia: alta en procesamiento de imagenes subidas por usuarios.
- `qs` moderada, transitive, DoS/array parsing. Relevancia: media en parsing de query/body si entrada externa no esta limitada.

HECHO: vulnerabilidades restantes solo aparecen en audit completo/dev: `handlebars` critica, `brace-expansion`, `braces`, `chokidar`, `js-yaml`, `argparse`, `sprintf-js`, `ts-node-dev`. Relevancia principal: toolchain/dev/test; no se ejecuto `npm audit fix`.

### P.7 Estado GO/NO-GO actualizado

GO para pruebas automaticas locales del cambio: PASS.

NO-GO para declarar candidato Windows completo de UAT: falta entorno UAT propio de esta rama, prueba HTTP real, PostgreSQL real, updater Windows y validacion manual visual/hardware.

NO-GO para produccion: faltan UAT end-to-end, pruebas de recuperacion reales y existen vulnerabilidades de produccion sin corregir/clasificar para remediacion.

## Q. Evidencia nueva de Fase 4

### Q.1 Entorno UAT aislado de la rama

HECHO: se creo un entorno Docker Compose propio de esta rama:

- compose project: `fullpos_offline_safe_48h_uat`;
- contenedor PostgreSQL: `fullpos_offline_safe_48h_postgres`;
- base: `daleventa_offline_safe_48h_uat`;
- usuario DB: `daleventa_offline_safe_48h_user`;
- puerto DB local: `127.0.0.1:56548`;
- puerto API local: `127.0.0.1:46548`;
- archivo local ignorado: `apps/api/.env.offline-safe-48h.uat.local`.

HECHO: `docker ps` mostro otros contenedores existentes en `55432` y `55433`; este entorno no reutiliza esos puertos ni nombres.

HECHO: `scripts/uat/start.ps1` ejecuto migraciones y seed sobre `daleventa_offline_safe_48h_uat`. La verificacion `scripts/verify-uat-db.ts` confirmo la identidad de base antes de migrar/sembrar.

HECHO: `seed-uat-local.ts` ahora acepta `UAT_EXPECTED_DB_NAME` y falla cerrado si la conexion no apunta a la base esperada. Tambien crea un turno de caja abierto deterministico para UAT offline.

### Q.2 Idempotencia real de ventas

HECHO: `SalesService.create` ya no devuelve silenciosamente una venta existente cuando el mismo `clientRequestId` llega con payload economico distinto. Antes de retornar el registro existente, compara cliente/caja/metodo/total esperado/items y lanza `409 IDEMPOTENCY_PAYLOAD_MISMATCH` si el contenido difiere.

HECHO: la comparacion usa `productId` como identidad primaria; para productos locales esto evita falsos positivos cuando el backend persistio `sourceProductId = productId` y el cliente reintenta solo con `productId`.

HECHO: prueba unitaria nueva: `rejects the same clientRequestId when the sale payload is different`.

### Q.3 UAT HTTP/PostgreSQL real

HECHO: smoke real contra API local + PostgreSQL UAT:

- `POST /auth/login`: 201;
- `POST /auth/offline-emergency/authorize`: 201 con `authorized=true`;
- `GET /products`: 200;
- `GET /cash/state`: 200;
- 5 envios concurrentes `POST /sales` con el mismo `clientRequestId`: todos 201 y un unico `saleId`;
- replay divergente con mismo `clientRequestId` y precio/total distinto: 409 `IDEMPOTENCY_PAYLOAD_MISMATCH`;
- PostgreSQL confirmo 1 venta, 1 item, 1 movimiento de inventario, mismo `cashSessionId` y stock `8.000000 -> 7.000000` en la ejecucion final.

LIMITACION: este smoke cubre backend HTTP + PostgreSQL real. No ejecuta la app Windows real ni sincronizacion desde el cliente Flutter contra la API; la persistencia SQLite se valido en pruebas Flutter focales.

### Q.4 Vulnerabilidades

HECHO: se remediaron vulnerabilidades de produccion sin `npm audit fix --force`:

- `@nestjs/*` backend a `^11.2.7`;
- `compression` a `^1.8.2`;
- `sharp` a `^0.35.5`;
- overrides para `multer`, `proxy-addr`, `qs` y `engine.io`.

HECHO: `npm audit --omit=dev --json`: PASS, 0 vulnerabilidades de produccion.

PENDIENTE: `npm audit --json` completo aun reporta 8 vulnerabilidades dev/toolchain: `handlebars`, `brace-expansion`, `braces/chokidar/ts-node-dev`, `js-yaml/argparse/sprintf-js`. `ts-node-dev/chokidar/braces` aparece sin fix directo en npm audit.

### Q.5 Validaciones de Fase 4

PASS:

- `powershell -ExecutionPolicy Bypass -File scripts/uat/start.ps1`;
- `npm run api:build`;
- `npx jest --runInBand src/sales/sales.service.tenant.spec.ts`;
- `npx jest --runInBand src/auth/auth.service.spec.ts`;
- smoke HTTP/PostgreSQL real descrito en Q.3;
- `npm audit --omit=dev --json`;
- `flutter test test/core/offline/offline_emergency_policy_test.dart test/core/offline/offline_store_sales_test.dart test/features/ventas/ventas_offline_tax_ticket_test.dart`;
- `git diff --check` sin errores de whitespace, solo aviso CRLF en `apps/api/src/auth/auth.service.spec.ts`.

NO-GO pendiente:

- UAT manual real Windows con instalador/updater y preservacion SQLite/WAL/SHM;
- pruebas de impresora/cajon reales;
- escenarios fisicos de disco lleno, bloqueo/corrupcion SQLite y apagado abrupto real;
- resolucion o aceptacion explicita de vulnerabilidades dev/toolchain restantes.

## R. Evidencia nueva de Fase 5

### R.1 Windows UAT aislado

HECHO: `scripts/uat/run-windows.ps1` ahora ejecuta Flutter Windows con:

- `API_BASE_URL=http://127.0.0.1:46548`;
- `APP_BASE_URL=http://127.0.0.1:46548`;
- `DISABLE_APP_UPDATES=true`;
- `ALLOW_UNSIGNED_UPDATES_FOR_UAT=false`;
- `ALLOW_UNSIGNED_UPDATES_FOR_PRODUCTION=false`;
- `DALEVENTAS_POS_ROOT=<repo>\.uat\windows-app-root`.

HECHO: `scripts/uat/run-windows-portable.ps1` prepara/lanza un build Windows release UAT contra el API local y con la misma raiz aislada. El script falla si el backend UAT local no responde.

HECHO: `scripts/build/build_windows_uat_release.ps1` ya no usa por defecto el host remoto anterior; por defecto compila contra `http://127.0.0.1:46548` y rechaza `31.97.99.70`/host de produccion conocido.

HECHO: `.uat/` quedo ignorado en git para bases, logs, updates y evidencia local temporal.

LIMITACION: no se ejecuto interaccion visual nativa completa de Windows desde esta sesion. Por tanto no hay PASS manual de login/caja/venta offline/reopen/sync desde GUI.

### R.2 Updater protegido para UAT

HECHO: se agrego `DISABLE_APP_UPDATES` como `--dart-define`/env soportado por `Env`.

HECHO: el chequeo inicial y el chequeo por resume de lifecycle no ejecutan el updater cuando `DISABLE_APP_UPDATES=true`.

HECHO: el repositorio de updates considera no configurado el updater si `DISABLE_APP_UPDATES=true`.

HECHO: las descargas de updater en Windows ahora respetan `DALEVENTAS_POS_ROOT` mediante `WindowsProductFolder.updates`; esto evita usar `%LOCALAPPDATA%\DaleVentas POS\updates` en UAT cuando la raiz aislada esta definida.

LIMITACION: no se probo un bench completo de updater con dos builds falsos, descarga `.part`, promocion `.ready`, firma y recuperacion post-update. Se deja como NO-GO especifico.

### R.3 Identidad estable de intento de venta

HECHO: `VentasRepository.createSale` acepta `clientRequestId` del caller. Si se provee, ese mismo id se usa en payload online, venta local offline, idempotency key y local id.

HECHO: `RegistrarVentaScreen` genera un solo `saleAttemptClientRequestId` por cobro confirmado y lo reutiliza si el primer intento falla por permiso y requiere autorizacion admin. Esto evita que una misma intencion de cobro sea enviada luego con otro id por el fallback de autorizacion.

HECHO: pruebas Flutter agregadas verifican `clientRequestId` provisto por caller tanto online como en la venta offline encolada.

LIMITACION: una caida total de proceso antes de persistir la venta local no puede ser resuelta solo desde memoria. La proteccion fuerte ante respuesta perdida sigue dependiendo de que el intento llegue a backend con el mismo `clientRequestId` o quede guardado en SQLite como pendiente.

### R.4 Runbook UAT manual

HECHO: se creo `docs/offline-safe-48h-windows-uat-runbook-2026-10-13.md` con procedimiento manual para:

- verificar rama/worktree;
- levantar UAT local aislado;
- lanzar app Windows con raiz `.uat`;
- ejecutar venta online/offline/reopen/sync;
- consultar PostgreSQL UAT;
- validar recuperacion SQLite;
- separar bench de updater sin canal comercial.

### R.5 Estado Fase 5

HECHO: build Windows UAT release ejecutado con:

`powershell -ExecutionPolicy Bypass -File scripts/build/build_windows_uat_release.ps1 -ApiBaseUrl http://127.0.0.1:46548 -AppBaseUrl http://127.0.0.1:46548 -WindowsAppRoot C:\src\fullpos-offline-safe-48h\.uat\windows-app-root -SkipPubGet`

Resultado: PASS. Artefacto generado: `apps/fulltech_app/build/windows/x64/runner/Release/fullpos_cloud.exe`.

OBSERVACION: el build emitio advertencias CMake de desarrollo en `media_kit_libs_windows_video` sobre `add_custom_command` sin `PRE_BUILD/PRE_LINK/POST_BUILD`; no bloqueo la compilacion.

GO parcial para blindaje tecnico adicional y scripts UAT seguros.

NO-GO para declarar candidato Windows UAT final: falta ejecutar app Windows nativa real con evidencia visual/funcional, SQLite fisico bajo `.uat`, reinicio real, sincronizacion desde GUI, updater bench falso y hardware impresora/cajon.

### R.6 Validaciones de Fase 5

PASS:

- `flutter analyze`;
- `flutter test test/features/ventas/ventas_offline_tax_ticket_test.dart test/features/ventas/ventas_controller_dispose_test.dart test/core/storage/windows_product_paths_test.dart test/core/offline/offline_store_sales_test.dart`;
- `npm run api:build`;
- `npx jest --runInBand src/sales/sales.service.tenant.spec.ts src/auth/auth.service.spec.ts`;
- `powershell -ExecutionPolicy Bypass -File scripts/uat/start.ps1`;
- sintaxis PowerShell de `scripts/uat/run-windows-portable.ps1`, `scripts/uat/run-windows.ps1` y `scripts/build/build_windows_uat_release.ps1`;
- `powershell -ExecutionPolicy Bypass -File scripts/build/build_windows_uat_release.ps1 -ApiBaseUrl http://127.0.0.1:46548 -AppBaseUrl http://127.0.0.1:46548 -WindowsAppRoot C:\src\fullpos-offline-safe-48h\.uat\windows-app-root -SkipPubGet`;
- `npm audit --omit=dev --json`;
- `git diff --check` sin errores de whitespace; solo aviso CRLF en `apps/api/src/auth/auth.service.spec.ts`.

FAIL / pendiente:

- `npm audit --json`: 8 vulnerabilidades dev/toolchain restantes (`handlebars`, `brace-expansion`, `braces`, `chokidar`, `ts-node-dev`, `js-yaml`, `argparse`, `sprintf-js`).

## S. Evidencia nueva de Fase 6

### S.1 Arranque Windows nativo e aislamiento

HECHO: se detecto que el ejecutable UAT podia salir inmediatamente si ya habia una instancia estable abierta, porque el runner Windows compartia titulo y mutex con produccion.

HECHO: `apps/fulltech_app/windows/runner/main.cpp` ahora separa el modo UAT cuando existe `FULLPOS_UAT_MODE`: titulo `FullPOS Cloud - Sistema de facturacion [UAT]` y mutex `Local\DaleVentasPOSSingleInstance-UAT`. Produccion conserva el titulo y mutex anteriores.

HECHO: se detecto que una raiz UAT fresca con `DALEVENTAS_POS_ROOT` importaba una base SQLite legacy desde rutas oficiales. Eso contaminaba la evidencia UAT.

HECHO: `local_database_path.dart` ahora omite la copia legacy cuando `WindowsProductPaths.hasOverrideRoot` es verdadero. Una raiz UAT override queda aislada y empieza con SQLite limpio.

HECHO: `trace_log_sink_io.dart` ahora escribe logs bajo la raiz Windows del producto, respeta `DALEVENTAS_POS_ROOT` y serializa escrituras para evitar lineas entremezcladas.

EVIDENCIA: arranque release UAT con raiz `C:\src\fullpos-offline-safe-48h\.uat\windows-app-root-isolated-20261013134014`:

- proceso vivo despues de 20s;
- `Responding: true`;
- titulo `FullPOS Cloud - Sistema de facturacion [UAT]`;
- `databases\fulltech_offline.db` inicial 4096 bytes;
- `databases\fulltech_offline.db-wal` y `databases\fulltech_offline.db-shm` creados;
- `logs\fullpos-client.log` creado bajo `.uat`.

LIMITACION: no se pudo operar la GUI nativa con login/venta/reapertura/sync desde esta sesion. La evidencia Windows de Fase 6 es arranque, aislamiento de proceso, rutas, SQLite y logs.

### S.2 UAT HTTP/PostgreSQL final

HECHO: UAT local se levanto con `scripts/uat/start.ps1` sobre:

- contenedor `fullpos_offline_safe_48h_postgres`;
- base `daleventa_offline_safe_48h_uat`;
- usuario `daleventa_offline_safe_48h_user`;
- puerto DB `127.0.0.1:56548`;
- API `http://127.0.0.1:46548`.

HECHO: smoke final contra API local + PostgreSQL UAT:

- login UAT: PASS;
- `POST /auth/offline-emergency/authorize`: `authorized=true`, `policyVersion=offline-safe-48h.v1`, `maxOfflineHours=48`;
- 3 ventas nuevas con `clientRequestId` unicos: PASS;
- replay del primer `clientRequestId`: devolvio el mismo `saleId`;
- PostgreSQL confirmo `salesCreated=3`, `distinctClientRequestIds=3`, `saleItems=3`, `inventoryMovements=3`;
- stock del producto UAT `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1` bajo de `7` a `4`;
- las 3 ventas quedaron en el mismo `originCashSessionId`/turno UAT.

HECHO: se corrigio la prueba `sales.service.inventory-optional.spec.ts` para que el replay idempotente simule una venta existente con items equivalentes. La prueba vieja aceptaba cualquier venta existente sin items; eso contradecia el bloqueo nuevo de payload divergente.

### S.3 Dependencias

HECHO: `npm audit --omit=dev`: PASS, 0 vulnerabilidades de produccion.

HECHO: `npm audit fix --package-lock-only` + `npm install` aplico correcciones compatibles de transitorios, incluyendo `brace-expansion 2.1.7`, `handlebars 4.7.10` y `js-yaml 3.15.2`.

NO-GO dev/toolchain: `npm audit` completo sigue fallando con 23 vulnerabilidades reportadas por npm:

- `braces` via `chokidar`/`ts-node-dev`: high, sin fix disponible segun npm audit;
- `sprintf-js` via `argparse`/`js-yaml`/Jest transform chain: moderate; npm solo propone `npm audit fix --force` con downgrade breaking de `ts-jest@29.1.2`.

RECOMENDACION: reemplazar `ts-node-dev` por tooling mantenido y evaluar ruta de Jest/ts-jest sin downgrade breaking en una fase separada.

### S.4 Validaciones finales de Fase 6

PASS:

- `powershell -ExecutionPolicy Bypass -File scripts/uat/start.ps1`;
- `Invoke-WebRequest -UseBasicParsing http://127.0.0.1:46548/health`;
- consulta `current_database()/current_user` contra `fullpos_offline_safe_48h_postgres`;
- smoke HTTP/PostgreSQL final de 3 ventas + replay idempotente;
- `dart format lib/core/debug/trace_log_sink_io.dart`;
- `flutter analyze`;
- `flutter test test/core/storage/windows_product_paths_test.dart test/features/ventas/ventas_offline_tax_ticket_test.dart`;
- `npm install`;
- `npm run api:build`;
- `npm --workspace apps/api exec -- jest --runInBand --testPathIgnorePatterns=\.e2e-spec\.ts$ --runTestsByPath src/sales/sales.service.inventory-optional.spec.ts src/sales/sales.service.tenant.spec.ts src/auth/auth.service.spec.ts`;
- `npm --workspace apps/api test`;
- `npm audit --omit=dev`;
- build Windows UAT release con `scripts/build/build_windows_uat_release.ps1`.

NO-GO pendiente:

- flujo GUI Windows completo login/catalogo/caja/venta offline/reinicio/sync;
- bench real de updater con `.part`, `.ready`, SHA/firma y preservacion de SQLite/WAL/SHM;
- impresora/cajon reales;
- disco lleno, bloqueo/corrupcion SQLite y apagado abrupto fisico;
- `npm audit` completo por vulnerabilidades dev/toolchain.

### S.5 Estado actualizado

GO para continuar UAT local controlado y para integrar estos blindajes en revision.

NO-GO para produccion y NO-GO para candidato Windows final hasta completar GUI real, updater bench, hardware y decision sobre vulnerabilidades dev/toolchain.

## T. Evidencia nueva de Fase 7

### T.1 Windows UAT real preparado

HECHO: `scripts/uat/start.ps1` confirmo entorno UAT local:

- API `http://127.0.0.1:46548`;
- PostgreSQL `127.0.0.1:56548`;
- base `daleventa_offline_safe_48h_uat`;
- usuario `daleventa_offline_safe_48h_user`;
- `PRODUCTION: NOT CONNECTED`.

HECHO: `scripts/uat/run-windows-portable.ps1 -SkipBuild` inicio el ejecutable release real:

- ejecutable `C:\src\fullpos-offline-safe-48h\apps\fulltech_app\build\windows\x64\runner\Release\fullpos_cloud.exe`;
- raiz local `C:\src\fullpos-offline-safe-48h\.uat\windows-app-root`;
- titulo de ventana `FullPOS Cloud - Sistema de facturacion [UAT]`;
- proceso UAT vivo y `Responding: true`;
- updater desactivado en modo UAT.

HECHO: SQLite UAT en `.uat\windows-app-root\databases\fulltech_offline.db` paso `pragma integrity_check` y no tenia `pending_actions` ni `offline_sales` antes de la UAT manual.

LIMITACION: no se opero la GUI nativa con mouse/teclado desde esta sesion. La evidencia visual/funcional manual queda pendiente para el operador.

### T.2 Smoke HTTP/PostgreSQL UAT

HECHO: smoke seguro contra API local completo:

- login UAT: PASS;
- `POST /auth/offline-emergency/authorize`: PASS;
- apertura de turno UAT: `84a3f506-4f27-47e1-943c-59dc97739e8d`;
- 3 ventas en efectivo con `clientRequestId` unicos: PASS;
- replay idempotente de cada venta: devolvio el mismo `saleId`.

HECHO: PostgreSQL UAT confirmo las 3 ventas:

- `fase7-http-1791915596949-1-a016f25b-c13f-43fd-98cd-af6c3843d728`, total `100.00`, producto `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1`;
- `fase7-http-1791915597060-2-5e82be06-2354-4860-b2dc-95e08057cbd6`, total `240.00`, producto `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2`;
- `fase7-http-1791915597131-3-6b43cba3-d704-41a6-9256-918ec8b9049a`, total `420.00`, producto `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3`.

### T.3 Updater UAT bench

HECHO: `apps/fulltech_app/windows/updater/updater_harness_test.ps1` contra `FullposUpdater.exe` paso:

- unsigned UAT valido;
- argumentos invalidos rechazados;
- paquete fuera del root rechazado;
- hash mismatch rechazado;
- unsigned production policy rechazado.

HECHO: `scripts/uat/run-updater-preservation-bench.ps1` creo dos builds ficticios `201001` y `201002` bajo `.uat`, simulo artefactos `.part`/`.ready`, preservo SQLite, `-wal`, `-shm`, `pending_actions`, identificador de venta offline y estado de autorizacion local.

LIMITACION: esto es banco UAT aislado y harness del binario; no declara PASS del updater comercial ni de instalacion sobre un cliente real.

### T.4 Recuperacion y errores

HECHO: `scripts/uat/run-sqlite-failure-bench.ps1` valido errores seguros y desechables:

- SQLite bloqueada: exit code `5`, `database is locked`;
- escritura read-only: exit code `8`, `attempt to write a readonly database`;
- base fuente preservada.

HECHO: los tests existentes cubren HTTP 500, timeout/retry, reintento duplicado, stale syncing, conflictos 409 y persistencia de ventas offline en SQLite.

LIMITACION: no se simulo disco lleno fisico ni cierre abrupto de energia real; solo quedan instrucciones manuales seguras en el runbook.

## U. Evidencia nueva de Fase 8

### U.1 Entorno y ejecutable Windows UAT

HECHO: `scripts/uat/start.ps1` preparo exclusivamente el entorno UAT local:

- API `http://127.0.0.1:46548`;
- PostgreSQL `127.0.0.1:56548`;
- base `daleventa_offline_safe_48h_uat`;
- contenedor `fullpos_offline_safe_48h_postgres`;
- `PRODUCTION: NOT CONNECTED`.

HECHO: se recompilo el release Windows UAT con `scripts/build/build_windows_uat_release.ps1 -ApiBaseUrl http://127.0.0.1:46548 -AppBaseUrl http://127.0.0.1:46548 -WindowsAppRoot C:\src\fullpos-offline-safe-48h\.uat\windows-app-root -SkipPubGet`.

HECHO: `scripts/uat/run-windows-portable.ps1 -SkipBuild` inicio el ejecutable real:

- ejecutable `C:\src\fullpos-offline-safe-48h\apps\fulltech_app\build\windows\x64\runner\Release\fullpos_cloud.exe`;
- raiz local `C:\src\fullpos-offline-safe-48h\.uat\windows-app-root`;
- titulo `FullPOS Cloud - Sistema de facturacion [UAT]`;
- proceso `Responding: true`;
- updater desactivado en compile/runtime UAT.

HECHO: SQLite local UAT existia en `.uat\windows-app-root\databases\fulltech_offline.db`, con WAL/SHM creados, `pragma integrity_check` en `ok` y sin pendientes antes de operar la GUI.

LIMITACION: no se opero visualmente la GUI nativa desde esta sesion. La prueba manual login/catalogo/venta offline/reinicio/sync sigue pendiente.

### U.2 Smoke de integridad sync HTTP/PostgreSQL

HECHO: se agrego `scripts/uat/run-sync-integrity-smoke.ps1` para ejecutar una conciliacion UAT segura sin escribir produccion.

HECHO: ejecucion final PASS con `runId` `fase8-1791920552870`:

- login UAT: PASS;
- autorizacion offline emergency: PASS;
- turno original `6650f3c0-aa90-475d-949f-c7b9ceb65506`;
- turno nuevo posterior `d845f087-9395-4cf1-8e98-e8c97a1aa0a7`;
- tres ventas cash con `clientRequestId` unico e importes `100`, `120`, `140`;
- replay dentro del mismo turno devolvio el mismo `saleId`;
- replay posterior al cambio de turno mantuvo el `saleId` y el turno original;
- venta con stock insuficiente rechazo con `409 INSUFFICIENT_WAREHOUSE_STOCK`.

HECHO: conciliacion PostgreSQL UAT del mismo `runId`:

- ventas: `3`;
- `clientRequestId` distintos: `3`;
- turnos distintos asociados a esas ventas: `1`;
- total vendido: `360.00`;
- items de venta: `3`;
- movimientos de inventario: `3`.

### U.3 Updater y recuperacion

HECHO: `apps/fulltech_app/windows/updater/updater_harness_test.ps1` paso contra el `FullposUpdater.exe` del build UAT: paquete UAT valido, argumentos invalidos rechazados, paquete fuera del root rechazado, hash mismatch rechazado y unsigned production policy rechazado.

HECHO: `scripts/uat/run-updater-preservation-bench.ps1` paso preservando SQLite, WAL, SHM, `pending_actions`, identificador de venta offline, autorizaciones locales y artefactos `.part`/`.ready` en dos builds ficticios.

HECHO: `scripts/uat/run-sqlite-failure-bench.ps1` paso con errores seguros y desechables: SQLite bloqueada (`database is locked`) y escritura read-only (`attempt to write a readonly database`), preservando la base fuente.

LIMITACION: no se ejecuto updater comercial, instalador real sobre cliente, disco lleno fisico, corte electrico, impresora ni cajon.

### U.4 Regresiones Fase 8

HECHO: `flutter analyze` paso sin issues.

HECHO: `flutter test` paso con `1276` tests y `1` skip.

HECHO: `npm --workspace apps/api test` paso con `74` suites, `745` tests y `8` skips.

HECHO: `npm run api:build` paso despues de detener procesos UAT que tenian tomado el cliente Prisma. El primer intento fallo con `EPERM` durante `prisma generate`.

HECHO: `npx prisma validate` paso contra el schema UAT local.

HECHO: `npm audit --omit=dev` paso con `0` vulnerabilidades.

NO-GO: `npm audit` completo sigue fallando por vulnerabilidades dev/toolchain conocidas (`braces` via `chokidar`/`ts-node-dev` sin fix disponible y `sprintf-js` via cadena Jest/ts-jest con fix forzado incompatible).

### U.5 Estado Fase 8

GO limitado para UAT manual local preparado y para bancos tecnicos aislados.

NO-GO para produccion y NO-GO para aprobar el flujo Windows final hasta que un operador complete la GUI real de punta a punta y se decida el tratamiento de vulnerabilidades dev/toolchain.

## V. Evidencia nueva de Fase 9

### V.1 Limpieza visual de conectividad en Ventas

HECHO: se audito el flujo de conectividad/sync visible en Flutter con foco en Ventas, Caja, Almacenes, banners, SnackBars, dialogos y el indicador global de sincronizacion.

HECHO: en `registrar_venta_screen.dart` el aviso offline de catalogo ya no ocupa una franja/bloque grande en la pantalla de cobro. Se reemplazo por un indicador discreto `Catalogo local` integrado a la barra superior en desktop y a una posicion compacta en mobile.

HECHO: el indicador conserva informacion necesaria: el tooltip aclara que los productos provienen de este equipo y que se actualizaran al recuperar conexion. Mantiene accion de actualizar catalogo sin dialogos automaticos.

HECHO: el mensaje posterior al guardado de venta ahora distingue:

- venta online: `Venta confirmada por el servidor.`;
- venta offline/local: `Venta guardada en este equipo. Pendiente de sincronizacion.`

HECHO: se preservaron mensajes criticos de caja, fiscalidad, stock insuficiente, fallos de impresion y operaciones que requieren revision; no se ocultaron errores que puedan afectar dinero o datos.

### V.2 Validacion Flutter

HECHO: `dart format lib/modules/ventas/registrar_venta_screen.dart test/modules/ventas/registrar_venta_paged_products_test.dart` ejecuto sin cambios pendientes de formato.

HECHO: prueba focal `flutter test test/modules/ventas/registrar_venta_paged_products_test.dart` paso. La prueba ahora verifica indicador discreto y ausencia del banner grande anterior.

HECHO: `flutter analyze` paso sin issues.

HECHO: `flutter test` paso con `1277` tests y `1` skip.

### V.3 Windows UAT abierto

HECHO: se recompilo Windows UAT con API local `http://127.0.0.1:46548`, root `C:\src\fullpos-offline-safe-48h\.uat\windows-app-root` y updater deshabilitado.

HECHO: `scripts/uat/start.ps1` confirmo UAT local:

- PostgreSQL `127.0.0.1:56548`;
- base `daleventa_offline_safe_48h_uat`;
- contenedor `fullpos_offline_safe_48h_postgres`;
- `PRODUCTION: NOT CONNECTED`.

HECHO: backend UAT quedo escuchando en `http://127.0.0.1:46548` y `/health` respondio `ok`.

HECHO: datos ficticios UAT verificados por lectura local:

- usuarios UAT: `2`;
- productos de empresa UAT: `5`;
- filas de inventario UAT: `5`;
- sesiones de caja abiertas: `2`.

HECHO: no se cerraron esas sesiones de caja abiertas para no modificar estado UAT existente antes de la prueba manual.

HECHO: `scripts/uat/run-windows-portable.ps1 -SkipBuild` abrio la app UAT:

- proceso `fullpos_cloud.exe` PID `14268`;
- titulo `FullPOS Cloud - Sistema de facturacion [UAT]`;
- ruta `C:\src\fullpos-offline-safe-48h\apps\fulltech_app\build\windows\x64\runner\Release\fullpos_cloud.exe`;
- SQLite `fulltech_offline.db` con `pragma integrity_check = ok`;
- `pending_actions = 0`;
- `offline_sales = 0`.

LIMITACION: Computer Use nativo no estuvo disponible (`native pipe` inexistente). La ventana quedo abierta, pero no se opero visualmente desde esta sesion. El UAT manual debe continuar con operador humano.

### V.4 Estado Fase 9

GO para iniciar UAT manual local guiado.

NO-GO para declarar UAT manual completo y NO-GO para produccion hasta completar login, catalogo, desconexion, ventas offline, reapertura, reconexion, sync y conciliacion desde la GUI real.
