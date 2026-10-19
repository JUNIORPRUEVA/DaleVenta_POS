# FullPOS Cloud Offline Safe 48H — Fase 14

Fecha: 2026-10-14. **NO-GO técnico integral / NO-GO publicación.**

HECHO: se identificó la causa del 409 y se mantuvo el rechazo seguro. Se añadió
un expediente de conciliación supervisada de solo lectura. El banco Windows
nativo A→B acreditó persistencia de identidad, preferencias, token seguro, sello,
autorización original, SQLite y operaciones dependientes; sincronizó y concilió
en PostgreSQL después de tres confirmaciones perdidas. Esto no acredita todavía
compatibilidad con binarios comerciales históricos ni el updater completo firmado.

## Alcance y seguridad

- Worktree: `C:\src\fullpos-offline-safe-48h`.
- Rama: `feature/offline-safe-48h`; HEAD `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.
- Se conservaron los cambios acumulados anteriores. Los 19 hashes del manifiesto
  `.uat/evidence/phase13-final-source-manifest.json` permanecieron iguales.
- No hubo cambios en contratos económicos, licencias, migraciones ni código del
  updater comercial en esta fase. Los archivos incorporados son herramientas UAT,
  una sonda nativa opt-in, sus pruebas y este informe.
- PostgreSQL local `127.0.0.1:56548`, contenedor
  `fullpos_offline_safe_48h_postgres`. API manual `46548`; API desechable `46552`,
  base `daleventa_offline_safe_48h_phase12_uat`.
- Se pararon únicamente APIs locales identificadas para `api:build`; ambas se
  restauraron. La API clon se detuvo adicionalmente para probar B sin backend.
- Sin producción, push, merge, deploy, main, canal comercial ni clientes reales.
  Sin reset SQLite, purga, eliminación de pendientes ni migraciones ejecutadas.
- Backup consistente SQLite mediante Backup API:
  `.uat/evidence/phase14-manual-before.db`; backup PostgreSQL local:
  `.uat/evidence/phase14-postgres-before.dump`.

## Causa exacta de LEGACY_MISSING_SESSION

HECHO: el snapshot Git `69dd871b64b8b08f80ee26332a981c24322df5e0`, cuyo pubspec
declara `1.0.6+130`, no envía `originCashSessionId` ni `cashSessionId` en
`VentasRepository._createSaleRemote` ni guarda esa asociación en el payload de
la venta pendiente. Sí conserva `clientRequestId`, fecha de ocurrencia,
dispositivo y, cuando se resuelven, terminal y almacén. La fila de cola conserva
empresa, usuario, identidad/idempotency key y fechas; el agregado offline guarda
el mismo payload, líneas y pagos. Ninguno demuestra por sí solo el turno original.

El `CashRepository` histórico mantiene `cash.active.session`, con `shiftId` y
`businessDate`. Es una caché del estado más reciente, reemplazable y eliminada al
cerrar. No hay una relación inmutable por venta entre esa caché y la operación
pendiente. Un turno local `local_shift_<tiempo>` tampoco constituye una asociación
remota verificable con una venta que no lo guardó.

HECHO: en ese mismo commit, `apps/api/src/sales/sales.service.ts` busca
`cashSession.findFirst` por empresa, usuario, `status=OPEN`, `closedAt=null`,
ordenado por `openedAt desc`, y asigna `activeSession.id`. Ese contrato elegía el
turno abierto al recibir la venta; no acreditaba el de origen. No se restauró.

El backend nuevo clasifica `originCashSessionId` obligatorio y
`originTerminalId` opcional. Sin ambos, con compatibilidad financiera desactivada,
rechaza en `resolveOriginCashSessionForSale` mediante `legacyCompatRejected()`:
`409 LEGACY_MISSING_SESSION`. Con turno explícito verifica empresa, usuario y
estado abierto; un turno cerrado se rechaza para nuevas escrituras. Un replay
ya procesado se resuelve por identidad antes de crear otra venta. No se activó
`FINANCIAL_LEGACY_COMPAT`, que recuperaría la selección peligrosa del turno actual.

### Reproducción aislada y payload exacto

Endpoint: `POST http://127.0.0.1:46552/sales`. Empresa UAT
`11111111-1111-4111-8111-111111111111`, usuario UAT
`33333333-3333-4333-8333-333333333333` autenticado. Payload de la reproducción:

```json
{
  "paymentMethod": "cash",
  "paymentCashAmount": 400,
  "cashReceived": 400,
  "expectedTotalSold": 400,
  "clientRequestId": "sale_req_1792002631235000",
  "saleOccurredAt": "2026-10-14T18:30:31.773Z",
  "deviceFingerprint": "phase14-source-shaped-130",
  "items": [{
    "productId": "2e9366f3-d2a5-4628-a5db-66d181b38a79",
    "qty": 4,
    "priceSoldUnit": 100
  }]
}
```

Respuesta `409 LEGACY_MISSING_SESSION`; ventas guardadas para esa empresa y
operación: **0**; stock antes/después: **20/20**. Existía el turno UAT
`eb976ed5-5b99-4ef2-9764-abd630b277c1`, `OPEN`, fecha operativa `2026-10-14`,
de la misma empresa y usuario. Se registró como dato disponible, **no como origen**.
La fecha de venta no permite determinar la fecha operativa original de un turno
que la operación no identifica. No se seleccionó por apertura ni por horario.

Evidencia íntegra: `.uat/evidence/phase14-legacy-http.json`, incluyendo payload,
respuesta, stack y consulta de turno. Ejecutable de reproducción:
`scripts/uat/phase14-legacy-http.cjs`. Es una petición representativa del contrato
verificado en código: **no es captura ni ejecución del binario distribuido +130**.

## Decisión y conciliación supervisada

HECHO: no se encontró prueba inequívoca por operación. **No se implementó adaptador
automático**, no se agregó un turno al payload y no se convirtió el 409 en 200.

Se incorporó `scripts/uat/phase14-legacy-case.py`. Exporta una fila exacta desde
una copia consistente SQLite en `.uat`; exige empresa, usuario, `sales.create`,
`clientRequestId` y coincidencia con `idempotency_key`. Rechaza cotizaciones,
scope divergente, identidades ausentes/divergentes, operaciones con turno
explícito y la ruta manual `windows-app-root`. Abre SQLite `mode=ro` y
`query_only=on`, cierra la conexión y crea el expediente con modo exclusivo.
Conserva fila completa, payload literal, hashes SHA256 e identidad original.
No tiene red, credenciales, modo apply, requeue ni envío HTTP.

```powershell
python scripts/uat/phase14-legacy-case.py --database .uat/evidence/phase14-legacy-source-shaped.db --action-id sales.create:phase14-130 --company-id 11111111-1111-4111-8111-111111111111 --user-id 33333333-3333-4333-8333-333333333333 --output .uat/evidence/phase14-legacy-supervised-case.json
```

Ejecutado una vez: `BLOCKED_PENDING_INDEPENDENT_EVIDENCE`, cero mutaciones y cero
peticiones. La entrada de ese ejemplo es un fixture SQLite del payload reproducido,
no una base extraída de un cliente +130. Hash del payload original del caso:
`ef1e7dfa342d59d5e7fdb5a6c5a85986241881f7b073e3746bcdf8f689366c35`.

RECOMENDACIÓN / procedimiento para un caso real:

1. Respaldar consistentemente sin alterar la cola; exportar la operación en su scope.
2. El supervisor aporta referencia y hash de evidencia independiente que vincule
   **esa identidad de operación** al turno original: recibo/log verificable o
   registro remoto cuya economía y operación coincidan. No basta un turno abierto
   ni una coincidencia temporal. Si no existe prueba, conservar bloqueo y operación.
3. Conciliar por empresa + `clientRequestId` en backend antes de cualquier envío.
   Si ya existe, comparar usuario, turno, líneas, pagos e importes; no crear otra
   identidad. Una divergencia requiere investigación, no reasignación.
4. Registrar supervisor y decisión explícita; verificar titularidad del turno.
   Si está cerrado, se necesita una decisión contable supervisada separada. No
   reabrirlo, trasladar la venta a otro turno ni modificar su fecha silenciosamente.
5. Antes de una eventual recuperación autorizada, releer y comparar hashes del
   original y mantener el mismo identificador económico. El expediente **no autoriza
   ni ejecuta esa recuperación**. No existe ruta de envío implementada sin evidencia.

Cinco pruebas focales verifican scope, identidad, exclusión de cotizaciones,
preservación literal, sensibilidad de hashes y ejecución CLI sin escritura de la
base ni sobrescritura del expediente.

## Artefactos históricos: origen y cobertura real

HECHO: se revisaron Git y artefactos locales del worktree y de los directorios
`C:\src\fullpos-136` a `fullpos-141` y `fullpos-release-141-build`.
No se encontró un binario distribuido verificable +130/+132/+133 en ese alcance.
No se inspeccionaron instalaciones comerciales ni se conectó a producción.

| Versión declarada | Origen comprobado | SHA256 de ventas_repository.dart | Contrato observado |
| --- | --- | --- | --- |
| 1.0.6+130 | Git 69dd871b64b8b08f80ee26332a981c24322df5e0 | e04e1e891cfcb5fbbcceeae887461a3d2f45b820862c901436f78323c3d94fe0 | Sin origen de turno |
| 1.0.6+132 | Git 5278477e9b2238f77b648bc9526bc2268dd6a064 | c0fef1525d99e0ade2bf489fbcba6c7f3e4d56e76b088587dbcc24b20c4fdf9b | Envía origen explícito |
| 1.0.6+133 | Git 07664153d4bd8ffda35fbe5fafd41a783074a311 | 4cd49cba0ecafcdce2e10891c98df0d68632a353664313938a3b77e218f0cc71 | Envía origen explícito |

Los DTO históricos de ajuste de stock tienen hash común
`a03b9399043ed732c242093053f22db9d92c69c60421c2530264bf450bbddf60`.
Los tres fixtures HTTP ejecutados con el DTO/ValidationPipe originales aceptan
`delta` sin operationId (200) y rechazan operationId (400). Esto valida el contrato
del DTO, **no una API antigua completa con PostgreSQL ni una aplicación antigua**.

Los ejecutables locales encontrados declaran versiones +136/+137/+138/+139/+140/
+141 y otro +141 de build de release. Sus rutas, versiones PE y siete hashes
completos están en `.uat/evidence/phase14-other-local-artifacts.json`. Son builds
locales disponibles: no se probó su procedencia de distribución, su contrato por
ejecución ni se lanzaron para acceder a sesiones comerciales. No se los cuenta
como compatibilidad histórica aprobada.

### Matriz cliente/backend

| Combinación | Evidencia real | Resultado y límite |
| --- | --- | --- |
| Antiguo +130 → nuevo | Fuente Git + petición HTTP aislada con PG | 409 seguro; incompatibilidad operativa confirmada para forma sin turno; binario pendiente |
| Antiguos +132/+133 → nuevo | Fuente con origen + regresiones backend; sin binarios | Origen presente en código; compatibilidad integral NO PROBADA |
| Nuevo → anterior | Fixtures HTTP de DTO anteriores y suite Flutter de negociación | Funciones avanzadas bloqueadas de forma segura ante backend sin capabilities; API antigua completa NO PROBADA |
| Nuevo → nuevo | Sonda nativa +14001/+14002, repositorios actuales, HTTP/SQLite/PG; smokes y suites | PASS del alcance descrito; no aceptación completa de UI/hardware/distribución |
| Antiguo → antiguo | Lectura de código original y DTO HTTP histórico | Selección del último turno abierto verificada en código; combinación completa NO EJECUTADA |

No se eliminaron operationId, payload hashes, negociación, validaciones tenant
ni idempotencia de Fase 13. No se declara compatibilidad total.

## Banco Windows nativo A→B

HECHO: nueva sonda opt-in `apps/fulltech_app/tool/phase14_native_probe.dart`.
`lib/main.dart` y los scripts de release no la invocan. Exige Windows, define de
compilación, APP_ENV/UAT local, raíz exacta del banco y `PackageInfo.appName`
`FullPOSPhase14NativeUAT` **antes de acceder a preferencias o secure storage**.

Se copió la aplicación a `.uat/n` excluyendo build, ephemeral y el `.env` real.
Solo la copia usa CompanyName/ProductName/FileDescription
`FullPOSPhase14NativeUAT` y mutex `Local\FullPOSPhase14NativeUAT`. Esto separa
las rutas nativas de preferencias y flutter_secure_storage de las de FullPOS:
`DALEVENTAS_POS_ROOT` por sí solo no separa esos plugins Windows. El `.env` de
la copia contiene exclusivamente el perfil UAT local sin secretos. Los accesos
UAT se heredaron en el entorno del proceso, sin compilarlos ni publicarlos.
Los hashes de la sonda, lockfile y fuentes nativas de la copia están en
`.uat/evidence/phase14-native-source-hashes.json`; el updater C++ copiado no cambió.

Comandos de build ejecutados en `.uat/n` (A se recompiló después del análisis focal):

```powershell
flutter build windows --release -t tool/phase14_native_probe.dart --build-number=14001 --dart-define=FULLPOS_PHASE14_NATIVE_PROBE=true --dart-define=API_BASE_URL=http://127.0.0.1:46552 --dart-define=DISABLE_APP_UPDATES=true
flutter build windows --release -t tool/phase14_native_probe.dart --build-number=14002 --dart-define=FULLPOS_PHASE14_NATIVE_PROBE=true --dart-define=API_BASE_URL=http://127.0.0.1:46552 --dart-define=DISABLE_APP_UPDATES=true
```

| Artefacto real UAT | SHA256 |
| --- | --- |
| A 1.0.6+14001 fullpos_cloud.exe | 838310B8B79C88ADBD4D6C62010B2CD9E7298C879AB40FAFC77D1FCCAF6BE470 |
| B 1.0.6+14002 fullpos_cloud.exe | D4095A310C220B7EE08CECFA9C98D83CA34A65B61E01B010A5A09E27C14F6ED5 |
| A y B data/app.so | C93CCEC3CD0A1134455671246AACBAB3435551C43742B53B0D2928F2EBCB56A8 |
| Instalador B aislado | A0D74F3A1108BF67EF4AE9B3727ABA13729A72CE3DA70C815F3039DED630C552 |

Los dos runners son distintos por versión PE; la lógica Dart de la sonda es la
misma. Es una prueba de persistencia entre builds reales de laboratorio con
SQLite v3, no prueba de migración desde cada versión distribuida histórica.

### Secuencia ejecutada y resultados

1. Instalación portable A en `.uat/phase14-native-bank/app`, lanzamiento nativo
   oculto mediante Start-Process. Login HTTP UAT real; TokenStorage y preferencias
   reales; grant real del backend. Se comprobó existencia de clave HMAC y sello
   en FlutterSecureStorage, sin registrar sus valores. Proceso A terminó con 0.
2. Se guardaron offline producto 0 → entrada +20 → venta -4 con repositorios,
   OfflineStore FFI y cola reales. Tres operaciones dependientes pendientes, IDs
   económicos y turno original conservados en `native-A.json`.
3. B se empaquetó con Inno Setup 6, `phase14-native-bank.iss`: ruta exacta fija,
   lowest, sin desinstalador, registry, shortcuts, borrado de datos ni canal.
4. FullposUpdater.exe nativo de A verificó paquete `.ready`, ruta y SHA256:
   `--verify-only --allow-unsigned --package ... --update-root ...` → exit 0.
   La política unsigned se usó solo en esa invocación UAT del verificador.
5. Se inició Inno B con pausa controlada durante sustitución de archivos, se
   observó `interrupted.marker` y se terminaron exclusivamente sus dos procesos
   identificados. Hash de SQLite intacto. Reinstalación completa B → exit 0,
   hash SQLite intacto y `app.so` instalado igual al B archivado.
6. `phase14-live-wal.py` mantuvo una conexión SQLite con transacción ya confirmada
   y WAL/SHM vivos durante interrupción y reinstalación. Los tres hashes quedaron
   idénticos y la fila de importe 400 siguió legible. No eran archivos sentinel.
7. Se detuvo API clon 46552. B se abrió como proceso Windows nativo y restauró
   empresa, usuario, device ID, token seguro, grant/sello originales, vencimiento,
   turno, identidades y payloads de las tres operaciones. Se comparó antes de
   reconectar y sin login ni renovación. `native-B.json` PASS.
8. A y B comprobaron aceptación de la autorización vigente y rechazo por
   expiración con un reloj inyectado +49h; no se cambió el reloj del equipo.
9. Se restauró API clon, se comprobó health y se emitió `reconnect.signal`.
   B sincronizó con repositorios reales y perdió deliberadamente tres respuestas
   después del commit remoto. Replay con las mismas identidades → pendientes 0.
   Proceso B terminó; `native-B-synced.json` PASS, stock 16.
10. `phase14-native-audit.cjs` concilió PostgreSQL por empresa: producto 1,
    entrada 1, venta 1, movimiento de venta 1, total 400, stock 16 y turno
    `eb976ed5-5b99-4ef2-9764-abd630b277c1`. Hashes de identidad/grant A=B.

Evidencia: `.uat/evidence/phase14-native-install.json`,
`phase14-native-artifact-hashes.json`, `phase14-native-postgres.json`,
`.uat/phase14-native-bank/{native-A.json,native-B.json,native-B-synced.json,wal-result.json}`,
logs nativos/Inno del mismo banco y logs de build bajo `.uat/evidence`.

### Límite del updater

**PASS banco nativo de persistencia/recuperación; BLOCKED updater integral.**
La instalación aislada y la reapertura se orquestaron con el banco, no con el
flujo completo Dart → helper → espera del padre/mutex → elevación → Inno →
relaunch automático. No se ejerció UAC ni publisher/firma de un paquete UAT
firmado. No se alteró el helper para saltar elevación o hacer pasar esa prueba.
No se operó la UI real del POS ni hardware. No se considera que verify-only +
Inno por separado prueben el updater completo. Hace falta un candidato UAT
firmado y ese recorrido completo en un entorno interactivo aislado.

## Regresiones ejecutadas en esta fase

| Comando / prueba real | Resultado | Evidencia |
| --- | --- | --- |
| `flutter analyze` | PASS inicial y final; final sin issues, incluye sonda | phase14-flutter-analyze-final.log |
| `dart analyze tool/phase14_native_probe.dart` | PASS tras corrección del harness | salida terminal |
| `flutter test` | 1316 PASS, 3 omitidas opt-in | phase14-flutter-test.log |
| `npm --workspace apps/api test -- --runInBand` | 74 suites PASS; 752 pruebas PASS, 8 omitidas | phase14-jest.log |
| `npm run api:build` | PASS, Prisma generate 5.22 + tsc | phase14-api-build.log |
| `npx prisma validate` desde apps/api con perfil UAT | PASS | phase14-prisma-validate.log |
| `python -m unittest discover -s scripts/uat -p test_phase14_legacy_case.py -v` | 5 PASS | phase14-legacy-case-tests.log |
| `node scripts/uat/phase14-legacy-http.cjs` con perfil clon | PASS rechazo 409, cero venta/descuento | phase14-legacy-http.json/log |
| `node scripts/uat/phase13-baseline-http-contract.cjs 69dd871b` (también 5278477e, 07664153) | 3 PASS DTO HTTP 200/400 | phase14-baseline-130/132/133.log |
| `scripts/uat/run-sync-integrity-smoke.ps1 -DisposablePhase12` | PASS 3 ventas, total360, mismo turno, insuficiencia409 | phase14-sync.log |
| `scripts/uat/run-product-stock-integrity-smoke.ps1` | PASS +20−4=16, 5 reintentos concurrentes, una aplicación | phase14-product-stock.log |
| `scripts/uat/run-updater-preservation-bench.ps1` | PASS fixture; no sustituye prueba nativa | phase14-updater-preservation.log |
| Builds A/B + Inno + native verify + interrupción + procesos A/B | PASS del banco; límites arriba | phase14-native-* y banco |
| `python scripts/uat/phase14-live-wal.py` | PASS WAL/SHM confirmados | phase14-live-wal.log |
| `node scripts/uat/phase14-native-audit.cjs` con perfil clon | PASS conciliación PG | phase14-native-audit.log |
| `scripts/uat/run-sqlite-failure-bench.ps1` | PASS locked5/readonly8 esperados, fuente conservada | phase14-sqlite-failure.log |
| `node scripts/uat/audit-phase11-preservation.cjs` con perfil manual local | PASS solo lectura PG | phase14-preservation-postgres.log |
| Backup API y comparación de todas las columnas/filas económicas manuales | PASS | phase14-manual-preservation.json |
| `git diff --check` | PASS; advertencias LF→CRLF anteriores, sin errores de whitespace | phase14-diff-check.log |

Los paths de evidencia de esta tabla son relativos a `.uat/evidence` salvo el
banco indicado. Las omisiones no se contabilizan como pruebas ejecutadas.

Fallos investigados y corregidos en el harness: estado de login esperado 200
cuando el endpoint devuelve 201; consulta a `CashSession` en vez del nombre real
`cash_sessions`; acceso protegido a state de StateNotifier en la sonda, corregido
mediante una subclase de prueba; conexión Python no cerrada en una prueba Windows,
corregida con `closing`. El verificador fue invocado inicialmente con una opción
incorrecta `--packagepath` (exit1 sin instalar), corregida a `--package` (exit0).
El primer health de reconexión ocurrió antes del arranque del clon; se verificó
arranque/health antes de emitir la señal. Ninguno se ocultó ni se debilitó una
validación de negocio para resolverlo. CMake emitió avisos de desarrollo de plugins
existentes; los builds terminaron correctamente. No se detectó un defecto nuevo
de producción reproducible que justificase alterar caja o idempotencia.

## Preservación manual

HECHO: comparación de filas completas antes/después, no solo conteos:

| Tabla SQLite | Filas | Resultado |
| --- | --- | --- |
| pending_actions | 1 | Idéntica; cotización histórica fallida conservada |
| offline_sales | 8 | Idénticas |
| offline_sale_items | 20 | Idénticas |
| offline_sale_payments | 8 | Idénticas |
| offline_inventory_intents | 20 | Idénticas |

`PRAGMA integrity_check`: ok. PostgreSQL manual: ocho ventas únicas en sus turnos
originales, 20 líneas y 20 movimientos. Cotizaciones remotas candidatas de la
histórica: 0; no se aplicó recuperación. El caso legacy y el banco nativo no
utilizaron esa fila histórica para producir una nueva operación.

## Requisitos, riesgos y decisión

| Requisito | Estado |
| --- | --- |
| Proteger producción, ramas, clientes y pendientes manuales | VERIFICADO en operaciones realizadas |
| Causa del409 y contratos históricos/nuevo | VERIFICADO por código y reproducción aislada |
| No inventar/reasignar turno; no duplicar operaciones | VERIFICADO en alcance ensayado; 409 conservado |
| Adaptador solo con prueba inequívoca | NO APLICA: evidencia insuficiente; bloqueo justificado |
| Conciliación supervisada preservando original | IMPLEMENTADO expediente y procedimiento; aplicación bloqueada sin evidencia |
| Artefactos +130/+132/+133 con procedencia de distribución | BLOQUEADO; snapshots no equivalen a binarios |
| Matriz antigua/nueva completa por ejecución | PARCIAL; límites explícitos en matriz |
| Instalación/identidad/grant/SQLite/WAL/SHM/dependencias/reconexión/replay/PG | PASS banco nativo aislado A/B |
| Recuperación de instalación interrumpida | PASS banco nativo aislado |
| Updater nativo completo firmado/elevado/relaunch | BLOQUEADO; verify-only y banco no sustituyen recorrido completo |
| Regresiones solicitadas | EJECUTADAS; resultados arriba |
| Informe y decisión final de publicación | DOCUMENTADO, sin publicar |

**NO-GO técnico integral** por cobertura histórica y updater integral pendientes.
Los controles y pruebas parciales con PASS son utilizables como evidencia; no
convierten una aceptación obligatoria incompleta en GO.

**NO-GO publicación.** No autorizar backend primero basándose en una compatibilidad
financiera global que elija el turno actual: la cohorte +130 sin origen sigue
necesitando tratamiento supervisado o una estrategia de compatibilidad probada.

RECOMENDACIÓN: para resolver lo que falta se necesitan artefactos históricos con
cadena de origen/hash verificable, datos ficticios representativos y ejecución
de las cuatro combinaciones completas; evidencia independiente por operación
legacy si se pretende recuperarla; y un candidato firmado UAT para ejecutar el
recorrido real del updater, incluido fallo, elevación y relaunch. La sonda no
reemplaza la aplicación final ni un instalador oficial. No avanzar a otra fase,
publicar o tocar clientes mientras esos bloqueos continúen.
