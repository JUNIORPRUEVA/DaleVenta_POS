# Execution State

## Ciclo de vida de productos — cierre técnico y revisión visual

Copia privada `C:/t/fppl-7e92-20261120`, rama
`agent/product-lifecycle-private-20261120`, base `a4ebdf1e`. No editar las copias
anteriores que siguen expuestas a otra sesión. API local 4017, PostgreSQL
exclusivo 56562, datos sintéticos. Producción únicamente consultada para hashes
de artefactos; ninguna mutación, migración, reinicio o publicación remota.

El commit web previo solicitado quedó en `a4ebdf1e`; recuperación en `d5986236`.
Backend e interfaz implementados, commits locales `c4bfd1d5` y `5545d07c`.
Revisión profunda del 21 de noviembre: cinco fallos adicionales del cliente
reproducidos y corregidos (identidad/estado de respuestas, cambio de sesión y
avisos huérfanos). 121 pruebas backend; 278 Flutter más dos casos de avisos y
seis de autenticación/ámbito aprobados; dos omisiones históricas por entorno.
Repetición focalizada de 104 pruebas aprobada y análisis sin incidencias.
Windows y Android emulado aprobaron la ejecución con
API/SQLite reales, reconexión y archivo de incidencia sin borrar evidencia.
PostgreSQL confirmó compensación/replay únicos y stock conservado. Backup y
restauración aprobados. El cierre nuevo conserva runId de cada plataforma y
comprobación SQL; los ejecutores rechazan resultados antiguos. Manifest de la
revisión actual: 11 archivos de código/pruebas sin cambios antes del commit,
incluidas las adiciones ya preparadas para commit; excluye capturas de fallos.
Galería Flutter: http://127.0.0.1:4493/ — 39 vistas y 78 capturas, sin API.
Estado técnico del alcance: GO WITH ISSUES. Aprobación visual concedida por el
propietario el 21 de noviembre; iOS físico no disponible. Integración y despliegue
siguen separados; no hay autorización de despliegue.
Documentos y ledger en `docs/audits/PRODUCT_LIFECYCLE_*_20261120.md`.

## Registro web: entrada automática — 2026-11-20

Recuperación guardada en commit local `d5986236`, sin push/despliegue.
Trabajo web en `C:/src/fp-signup-20261120`, rama
`agent/signup-auto-entry-20261120`. Se reprodujo la carrera entre actualización
PWA y preparación del acceso; se añadió espera al primer frame y recuperación
explícita del canje fallido. 16 pruebas web y 22 Flutter PASS, análisis sin
incidencias, compilaciones Astro/Web y registro real en Chrome con API/SQL
aislados. Una sola cuenta y ningún login manual o movimiento financiero.
Informe: `docs/WEB_REGISTRO_ACCESO_AUDITORIA_2026-11-20.md`.
Corrección local, no desplegada. El contenido inferior es historial.

## Entrega automática de incidencias entre usuarios — 2026-11-20

Copia actual: `C:/Users/pc/.codex/worktrees/fullpos-recovery-courier-20261120`,
rama `agent/recovery-courier-20261120`. Alias de compilación Windows `C:/fprc`.
Se aisló por una escritura simultánea en la copia anterior. No editar aquella.

Se conectó la publicación administrativa automática, limitada al propietario,
con checkpoints persistentes, respeto de Retry-After y recepción de la decisión
del administrador. No hay replay financiero ni nuevos permisos. Se añadió
comparación y actualización SQLite para no sobrescribir evidencias más recientes.
63 pruebas focalizadas PASS, análisis sin incidencias y recorrido nativo PASS
en Windows y Android emulado con API/PostgreSQL locales. Comparación financiera
sin cambios: 12 ventas y 32 movimientos sintéticos. Sin producción ni despliegue.
Detalles y límites: `docs/CENTRO_RECUPERACION_CIERRE_ENTRE_USUARIOS.md`.
El contenido inferior conserva el historial de las fases anteriores.

## Simplificación de diez estados y continuidad por ticket — 2026-11-20

Fase actual: `C:/src/fullpos-recovery-simple-ui-20261120`, rama
`agent/recovery-simple-ui-20261120`. Se creó una copia nueva después de detectar
otra edición en el worktree anterior. No editar ni integrar automáticamente
aquella copia. Base `840caadf`, con la recuperación previa conservada.

Vista previa actual: `http://127.0.0.1:4488`, entrada Flutter
`test/preview/recovery_design_preview.dart`. Datos ficticios en memoria y HTTP
bloqueado. Se conserva la previsualización anterior y el servidor ajeno IPv4:4004.

Implementado: estado vacío de una línea; lista compacta; solo sincronizar arriba;
sin importación ni Más opciones; verificación reforzada y luego dos soluciones;
archivo manual sin perder contenido; ticket nuevo editable sin cobrar; resolución
directa auditada de dinero declarado; acceso ADMIN. La identidad estable de
ticket permite dos ventas nuevas iguales y conserva la protección del mismo
ticket incierto. Legacy sin identidad mantiene su guardia conservadora.

Validación: Flutter 539 PASS/3 omitidas opt-in; repetición focalizada 28 PASS;
backend 38 PASS; HTTP real 8 escenarios PASS; Windows nativo 1 escenario integral
PASS. Análisis sin incidencias; TypeScript compilado. PostgreSQL conserva las
mismas 2 ventas y 3 movimientos. Perfil Windows separado: 47 incidencias previas
conservadas más una sintética de prueba, que sigue pendiente. No se ejecutó Cobrar.

Informes vigentes:
`docs/CENTRO_RECUPERACION_SIMPLIFICACION_AUDITORIA.md` y
`docs/IA_CENTRO_RECUPERACION_GUIA_CLIENTE.md`.
GO de revisión local; NO-GO de publicación general por los pendientes descritos.
Sin producción, commit ni despliegue. Los informes inferiores son historial.

## Ajuste solicitado: soluciones directas y acceso ADMIN — 2026-11-20

Prevalece sobre las descripciones de interfaz anteriores. Worktree
`C:/src/fullpos-recovery-ui-20261120`. Se retiró «Solicitar revisión» del
flujo visible; «Comprobar» conserva internamente el expediente y consulta el
registro. Caja ofrece marcar no realizada con motivo; el cobro incierto muestra
los botones de venta nueva y no realizada. Evidencia conservada, sin replay
financiero. Pantalla y consultas de expedientes reservadas a ADMIN.

Galería Flutter: `http://127.0.0.1:4487`, diez escenarios ficticios y anchos
adaptable/390/1280. Widgets reales, preferencias en memoria y HTTP bloqueado.
No es aceptación de datos offline Web ni un servidor de producción.

Validación: 55 PASS focalizadas y 30 PASS en la última repetición de pantalla y
repositorio; conjuntos solapados. Continuidad/SQLite: 44 PASS. Backend: 19 PASS.
Flutter analyze sin incidencias y typecheck de tsconfig.build PASS. El intento
de automatización Chrome se detuvo en carga, no se contabiliza como aprobado.

Informe y límites:
`docs/RECOVERY_ADMIN_UX_REVIEW_2026-11-20.md`. Continúan pendientes la identidad
persistida del ticket para dos ventas iguales, la entrega automática de casos
de otros usuarios y la aceptación HTTP del último guard ADMIN. No se declara
continuidad total ni GO de publicación. Sin producción, commit ni despliegue.

## Centro de recuperación: diseño y mensajes — 2026-11-20

Esta fase se trabaja en `C:/src/fullpos-recovery-ui-20261120`, rama
`recovery-ui-20261120`, base `840caadf`, conservando los cambios de recuperación
de la fase anterior. Se creó esta copia después de detectar otra edición en
el worktree anterior. El informe inferior describe esa fase anterior y sus
pruebas; no equivale a una nueva ejecución de toda aquella batería.

### Cambios de esta fase

- Pantalla con tarjeta central de ancho máximo 920, contadores relevantes y
  estado del servidor independiente. Se ocultan secciones vacías y avisos
  redundantes; no se afirma sincronización global por tener cero pendientes.
- Ventas: una acción principal, «Verificar ahora», y un menú «Más opciones».
  Referencias, historial y decisiones administrativas quedan bajo demanda.
  «Reporte para soporte» identifica correctamente la acción que copia el
  reporte; no promete enviar una solicitud al servidor.
- Operaciones de caja, revisiones y conciliaciones usan filas desplegables,
  nombres comprensibles e importes visibles. Las revisiones solicitadas se
  muestran antes de la lista de incidencias y las finalizadas en archivo.
- Mensajes comunes del backend abreviados: autenticación, permisos,
  validación, conflicto, límite de solicitudes y servicio no disponible.
  Los errores de existencias conservan producto y cantidades. Se mantienen
  diagnósticos originales y clasificación HTTP; no se cambian decisiones
  de reintento por razones de presentación.
- Botones cuadrados, decisiones con motivo mínimo de diez caracteres y
  acciones deshabilitadas mientras se procesan. Se evita el doble envío de
  comprobaciones o solicitudes. Cancelar una decisión no escribe datos.
- Se corrigió una colisión de PageStorage entre ExpansionTile y su
  SelectableText que producía un error bool/double al desplegar detalles.

Archivos principales: `sale_attempt_recovery_screen.dart`,
`recovery_reviews_panel.dart`, `reconciliation_obligations_panel.dart`,
`recovery_status_card.dart`, nuevo `recovery_presentation.dart` y el traductor
compartido `core/errors/operation_error_message.dart`. No se modificaron
servicios backend ni reglas financieras durante esta fase de diseño.

### Verificaciones de esta fase

- Regresión focalizada de recuperación, cola, errores y caja: **334 PASS,
  3 omitidas opt-in**. `.uat/recovery-ui-regression-final.log`.
- Después del último ajuste de alineación: **26 PASS** en
  `test/features/offline` y `test/core/errors`.
  `.uat/recovery-ui-final-polish-tests.log`. Son una repetición parcial de la
  batería anterior; no se suman como casos independientes.
- `flutter analyze --no-pub`: **sin incidencias**.
  `.uat/recovery-ui-analyze-final.log`.
- Pruebas de presentación a 320, 390 y 1280 px con fuentes e iconos reales.
  PNG locales: `.uat/evidence/recovery-ui/recovery-320.png`,
  `recovery-390.png`, `recovery-1280.png`.
- Aplicación Windows real iniciada mediante `flutter run -d windows`,
  perfil UAT separado, API local 4005 mediante puente IPv6:4004 y PostgreSQL
  aislado 56560. Solicitar revisión desde una operación rechazada creó un
  caso real enlazado; la fila original permanece y ya no ofrece solicitarlo
  otra vez. Contadores: 45 bloqueadas y una por revisar.
  «Comprobar registro» también consultó la API real y conservó el caso
  pendiente, sin confirmarlo. Se inspeccionó el diálogo administrativo con
  guardado deshabilitado al faltar el motivo. El envío de una decisión válida
  y su cancelación se validaron en pruebas de widget; no se envió una decisión
  administrativa desde la sesión visual de esta fase.
- Comparación SQLite/PostgreSQL antes/después **PASS**:
  **2 ventas, 3 movimientos y 46 incidencias originales conservados**;
  mismos identificadores, importes, fechas y payloads originales. Un caso
  de revisión añadido; ningún registro financiero creado o modificado.
  Evidencia: `.uat/recovery-ui-native/before.json`, `after.json`;
  verificador reproducible `scripts/uat/verify-recovery-ui.cjs`.

**Alcance y límites:** GO para revisión local de esta interfaz. No es una
autorización de publicación ni una certificación de todas las pantallas o
todos los mensajes posibles del backend. Esta fase no volvió a ejecutar
aceptación nativa Android/iPhone ni toda la batería Flutter. Se conserva
el criterio de publicación de la fase anterior. Sin cambios en producción,
operaciones financieras reales, commit, despliegue ni publicación.

## Informe de cierre local — 2026-11-20 (prevalece sobre el historial inferior)

**Ámbito:** copia aislada `C:/src/fullpos-recovery-closing-isolated-20261120`,
rama `recovery-closing-isolated-20261120`, base auditada `840caadf`.
La otra sesión conserva su worktree. Esta rama todavía no está integrada ni
publicada. No se modificó producción ni se realizaron operaciones financieras
reales. El laboratorio usa API `127.0.0.1:4005`, PostgreSQL dedicado
`127.0.0.1:56560/fullpos_recovery_closing` y perfiles UAT separados.
La previsualización ajena en IPv4:4004 sigue intacta; Windows utiliza un puente
loopback IPv6 y Android `adb reverse`. No se relajó el bloqueo de destinos UAT.

### Cambios funcionales y cobertura de los diez requisitos

| Requisito | Implementación y verificación |
| --- | --- |
| 1. Empresa y usuario correctos | Contexto fijado por operación, recuperación automática con propietario explícito, cola y repositorios ligados al almacén de autenticación compartido. Cambiar de empresa durante preparación cancela el envío; cambiar después de un resultado incierto conserva la incidencia para la cuenta original. Cinco regresiones de cambio de propietario PASS. |
| 2. `occurredAt` original | Se guarda antes del POST y se reenvía sin sustituirlo por la fecha de sincronización. Columna propia, formato estricto y ventana financiera en backend. API real y comparación PostgreSQL verifican igualdad del instante y ausencia de duplicados. |
| 3. Cola y dependencias | Las acciones permanentes se excluyen antes de aplicar el límite de envío; se conservan dependencias por turno/producto y el orden necesario para cierre. Prueba nativa: 45 bloqueadas permiten una operación nueva válida. |
| 4. Confirmación estricta | Venta/caja requieren identidad original, identificador devuelto no vacío e importe finito coincidente. Datos ausentes, incompatibles o inciertos permanecen para revisión. Apertura añade `openingAmount` al contrato de respuesta. |
| 5. HTTP 422 | Tanto el error Dio original como el error ya traducido se consideran validación permanente; no hay reintento automático infinito. |
| 6. HTTP 401/403/409/429 | Recuperación normal de autenticación; bloqueo por usuario cuando no puede recuperarse; permiso permanente; conflicto conservado; `Retry-After` en segundos o fecha persistido. Se prueban clasificación local y respuestas reales del laboratorio. |
| 7. Contadores | Pendientes, reintentables, bloqueadas e intervención se cuentan sin truncar el conjunto. Una revisión resuelta sale de los contadores activos y conserva la fila original. |
| 8. Servidor y cola | Conexión desconocida/accesible/inaccesible separada de la cola. Ausencia de pendientes locales no afirma sincronización global. Apertura local permanece `fromCache` hasta confirmación exacta. Se eliminó la promesa incondicional de poder vender del aviso de recuperación. |
| 9. Turnos y cierres | Límite real del laboratorio: 24 horas; valor por defecto del código: 24, techo de configuración existente: 72. No se leyó ni cambió configuración de producción. Se validan turno de 26 h, turno nocturno, caja diaria cerrada y cierre del turno original. |
| 10. Rechazos sin duplicar | Diario SQLite previo al primer POST nativo de venta, apertura, movimiento y cierre. Una respuesta perdida después del commit no pierde la referencia. Revisión administrativa auditada comprueba el registro existente; no recrea dinero. |

### Hallazgos adicionales corregidos en esta continuación

- La apertura offline necesita prueba firmada de empresa/usuario/dispositivo y
  sesión de autorización. Conserva la apertura original; no reabre caja diaria
  cerrada ni permite usar una autorización revocada antes de la apertura.
  Las aperturas antiguas sin prueba quedan para intervención explícita.
- El emulador tenía aproximadamente 400 ms de atraso: una apertura inmediata
  podía resultar anterior al inicio exacto del permiso. La fecha se calcula
  una sola vez con la observación sellada del servidor y el tiempo transcurrido
  del dispositivo. Se persiste ese instante; no se amplía la ventana firmada ni
  se cambia la validación del servidor. Regresiones con desfase positivo y
  negativo y retroceso de reloj PASS.
- Se serializó el acceso al plugin de almacenamiento seguro para evitar
  escrituras simultáneas sobre su mapa cifrado. El cifrado y el plugin se
  conservan. Reinicios reales verifican 30 claves sintéticas por plataforma.
- Una revisión humana de cierre NO_REALIZADO comprueba que no exista cierre
  financiero, conserva el turno OPEN y registra el evento. Si otro proceso lo
  cerró, la comprobación concurrente impide resolverlo como no realizado.
- Las decisiones administrativas actualizan las estimaciones/cachés del mismo
  propietario y los contadores. Una decisión humana no es una confirmación
  financiera; la incidencia original sigue disponible y no se reenvía.
- El replay de caja exige un importe original presente, finito y no negativo.
  Un campo ausente o inválido no se convierte en cero. Doce regresiones cubren
  apertura/movimiento/cierre con importe ausente, NaN, infinito y negativo.
  La revisión de apertura/cierre exige además que el identificador registrado
  sea exactamente el turno original: cuatro regresiones de aceptación/rechazo.
- El test de login con router real expuso una lectura de controlador dispuesto
  tras esperar el catálogo local. Se añadieron dos comprobaciones del ciclo de
  vida en cotizaciones (siete líneas), sin cambiar ventas, cálculos ni catálogo.

### Pruebas y evidencia realmente observadas

No se suman baterías que cubren las mismas pruebas. Los números `+2` de los
drivers nativos incluyen `tearDownAll`: representan un escenario principal,
no dos escenarios financieros.

| Comprobación | Resultado / evidencia local |
| --- | --- |
| Backend focalizado de caja, revisión, permiso y conciliación | 124 pruebas PASS, 12 suites. `.uat/recovery-closing-backend-final.log`; compilación TypeScript PASS. |
| Prisma | `prisma validate --schema apps/api/prisma/schema.prisma` PASS. Tres migraciones aditivas aplicadas únicamente en PostgreSQL aislado. |
| API/PostgreSQL: aperturas y revisiones | 9 escenarios PASS. `.uat/recovery-closing-20261120/api-closing-1795205782084.json`: firma/dispositivo/empresa/fecha rechazados, apertura demorada preservada, idempotencia, caja cerrada, autorización revocada y cierre no realizado. La demora de diez minutos se representa con tiempos sintéticos firmados; no fue una espera física de diez minutos. |
| API/PostgreSQL: estabilización | 11 escenarios PASS. `.uat/recovery-stabilization-20261120/api-postgresql-evidence.json`: turnos antiguos/nocturnos, fechas inválidas/futuras, conflictos, autenticación, permisos y límite de peticiones. |
| Windows: ventas, caja y cola | Aceptación nativa PASS. `.uat/recovery-closing-windows-final.log`, evidencia `windows-1795203251943856.json/png`. Dos ventas de 50, tres movimientos de 7, cierre 114/esperado114/diferencia0, 46 incidencias conservadas. |
| Android 15/API35: ventas, caja y cola | Aceptación nativa PASS. `.uat/recovery-closing-android-final.log`, evidencia `android-1795203682643544.json/png`. Mismos invariantes, datos de otra empresa de prueba. |
| Windows: respuestas perdidas de caja | PASS con el código final. `.uat/recovery-closing-windows-journal-verified.log`, `windows-journal-1795207471066903.json` y `-postgresql.json`. Un turno, un movimiento7, cierre7/esperado7/diferencia0, cero duplicados, revisión conservada y comprobada también en SQLite. |
| Android: respuestas perdidas de caja | PASS después de corregir el desfase de reloj. `.uat/recovery-closing-android-journal-corrected.log`, `android-journal-1795206212230458.json` y `-postgresql.json`. Mismos invariantes financieros y comprobación de diario previo a cada POST. |
| Android: detención de proceso y reinicio | PASS. `.uat/recovery-closing-android-restart-final.log`; `android-1795203682643544-restart.json/png`. Usuario recuperado, 30 claves cifradas, 46 incidencias y dos identificadores de venta comprobados mediante conciliación sin POST financiero. |
| SQLite frente a PostgreSQL en ambas plataformas | PASS. En Android, copia binaria de DB/WAL tras detener únicamente el paquete UAT bajo `.uat/android-native-20261120/evidence/sqlite-before-restart`. Dos ventas sincronizadas coinciden con servidor, 46 incidencias permanentes. `android-1795203682643544-postgresql-crosscheck.json` y `windows-1795203251943856-postgresql-crosscheck.json`. El verificador del diario también leyó la incidencia de cierre de la otra empresa sintética: sigue presente como `review_resolved`, con el mismo turno, importe y revisión. |
| Windows: detención de proceso y reinicio final | PASS. `.uat/recovery-closing-windows-restart-latest.log`; `windows-1795203251943856-restart.json/png`. Los mismos invariantes de usuario, 30 claves y 46 incidencias. |
| Flutter completo | `flutter test --no-pub`: 2.562 PASS, 10 omitidas, 5 FAIL iniciales. `.uat/recovery-closing-all-flutter-latest.log`. No se presenta esta ejecución como una batería completa verde. Los cinco fallos se corrigieron y repitieron en las suites afectadas, según las filas siguientes. |
| Regresión de las suites corregidas y cotizaciones | 225 PASS. `.uat/recovery-closing-final-regression-confirmed.log`: empresa, topbar, login/router, revisión y toda `test/modules/cotizaciones`. Incluye los cinco casos inicialmente fallidos y las cuatro comprobaciones nuevas del turno devuelto. |
| Última regresión de recuperación/caja | 196 PASS. `.uat/recovery-closing-regression-final.log`: caja, cambio de propietario, revisión, empresa, topbar, login y pantalla de recuperación. Incluye los doce importes inválidos/ausentes. Tiene un aviso de hit-test en la prueba de pantalla; no se silenció ni se convirtió la comprobación en una omisión. |
| Análisis final | `flutter analyze --no-pub`: PASS sin incidencias. `.uat/recovery-closing-analyze-verified.log`. |
| Compilación Web final | `flutter build web --release --no-pub` con perfil UAT y API loopback: PASS (JavaScript). `.uat/recovery-closing-web-final.log`. El sondeo WebAssembly informa dependencias incompatibles; no se afirma soporte Wasm. La compilación no equivale a aceptación offline de navegador. |

Los JSON/PNG mencionados están bajo `.uat/windows-native-20261120/evidence`
o `.uat/android-native-20261120/evidence`. Se mantienen locales e ignorados por
Git. Las credenciales y claves privadas del laboratorio no forman parte del
informe ni se deben compartir.

### Fallos de pruebas conservados y corregidos

Se conservan los logs iniciales: dos errores estáticos al trasladar una utilidad
a extensión Dart; dos fixtures antiguos de caja sin propietario o confirmación
completa; ejecución amplia anterior con argumentos que invalidaban tres tests
de configuración; aislamiento de scheduler de almacenamiento seguro en tests;
primera prueba Android con destino incompatible con el guard UAT; primer diario
Android rechazado por desfase de reloj. No se presentan como ejecuciones PASS.
Las correcciones se repitieron con validaciones estrictas; no se borraron
filas para resolver errores ni se redujeron requisitos financieros para
hacerlas pasar. La incidencia del instalador Android se detalla debajo.
La batería completa final encontró tres fixtures de cola sin usuario, una
expectativa del texto anterior y el test de router con almacenamiento pendiente.
Desmontar correctamente ese test permitió reproducir y corregir la lectura
tardía del controlador de cotizaciones. Las nuevas pruebas de revisión primero
intentaban sustituir una operación por otro tipo con la misma referencia: el
almacén las rechazó correctamente; se corrigió el fixture para crear referencias
independientes, manteniendo la protección contra sobrescrituras.
Las diez omisiones corresponden a pruebas condicionadas por sus entornos UAT,
TLS, proceso auxiliar o conexión dedicada; no se afirma haberlas ejecutado.
Se ejecutaron por separado las aceptaciones nativas y de API aquí enumeradas.

**Incidente de herramienta Android durante la última repetición:** el emulador
del usuario quedó con unos 601 MiB libres. La instalación del APK debug de
215 MB falló con `INSTALL_FAILED_INSUFFICIENT_STORAGE`. Flutter hizo su
reintento automático de `installApp`, que desinstala el paquete anterior si la
primera instalación falla (comportamiento comprobado en el SDK local).
El paquete UAT `com.daleventa.pos.uat.recovery` quedó desinstalado; no se debe
afirmar que sus datos sigan presentes en ese dispositivo. La aplicación
habitual `com.daleventa.pos` sigue instalada y no fue seleccionada para borrar,
reinstalar ni limpiar. No se modificó su configuración para liberar espacio.

La copia binaria DB/WAL previa bajo
`.uat/android-native-20261120/evidence/sqlite-before-restart` conserva las
incidencias y ventas de prueba, y sus invariantes se contrastaron con
PostgreSQL. Las 30 claves sintéticas fueron verificadas antes del incidente;
no se afirma que sigan en el keystore del paquete desinstalado. No hubo una
operación financiera ni una modificación de datos de producción por este fallo.
Log conservado: `.uat/recovery-closing-android-journal-verified.log`.

Para completar la repetición se creó el AVD desechable
`FullPOS_Recovery_Closing_20261120` con partición de 12 GiB, ubicado bajo `.uat`,
en `emulator-5556`; no se sobrescribe el AVD del usuario. El nuevo flujo exige
comprobar el nombre del dispositivo y al menos 3 GiB libres antes de instalar.
La repetición completada y sus evidencias finales se describen a continuación.

**Repetición completada en el AVD separado:** PASS con el código final. Se
perdió el enlace de depuración al primer arranque en frío; se reconectó a la
misma app mediante el VM Service observado, sin reinstalar ni alterar datos.
El flujo posterior usa `adb install -r` directamente, copia DB/WAL antes de
actualizar y conecta `flutter drive --use-existing-app`; se evita así el
fallback automático de desinstalación. Script local:
`scripts/uat/run-recovery-android-native.ps1`. Se corrigieron y conservaron en
el historial de ejecución dos fallos del helper (redirección PowerShell y
`pidof` todavía vacío al arrancar); el probe final ejecutó el helper completo
con éxito.

Evidencia final bajo `.uat/android-isolated-final-20261120/evidence`:

- `android-1795207906161479.json/png`: aceptación completa de ventas, caja,
  cola, autenticación y aislamiento. Log:
  `.uat/recovery-closing-android-isolated-attached.log`.
- `android-journal-1795208241234539.json` y `-postgresql.json`: apertura,
  movimiento y cierre con respuesta perdida; un movimiento de7, diferencia0,
  cero duplicados y revisión original conservada en SQLite. Log:
  `.uat/recovery-closing-android-isolated-journal-attached.log`.
- `android-1795207906161479-restart.json/png`: proceso detenido y relanzado,
  mismo usuario, 30 claves cifradas y 46 incidencias; cero POST financieros en
  el probe. Log: `run-recovery_restart_probe_test.dart.log`.
- `android-1795207906161479-postgresql-crosscheck.json`: dos ventas, tres
  movimientos, identificadores de SQLite iguales al servidor, cierre114,
  esperado114, diferencia0, 46 incidencias conservadas y cero duplicados.
- `snapshots/`: copias DB/WAL y manifiestos SHA256 previos a las actualizaciones
  manuales del APK. El APK de pruebas se actualiza conservando datos y firma;
  un fallo cancela el flujo, sin desinstalar ni limpiar cachés de otras apps.

La copia del emulador anterior se volvió a consultar después de su incidente y
sigue pasando los dos verificadores contra PostgreSQL. Este resultado prueba
la conservación de la evidencia archivada; no restaura automáticamente el
paquete ni el keystore eliminado del emulador anterior.

### Aplicación visible al finalizar

Se ejecutó `flutter run --no-pub -d windows --target lib/main.dart` con perfil
UAT, API loopback y actualizador deshabilitado. Se abrió la aplicación normal
del código final y se navegó mediante UI al **Centro de recuperación**.
La observación final confirmó: servidor accesible, cero pendientes, cero
reintentables, 46 bloqueadas y cero que requieren intervención. Las 46 son
incidencias sintéticas conservadas deliberadamente, no datos de un negocio real.
La pantalla distingue cobros inciertos locales, cola y revisiones; no afirma
sincronización completa. La app se deja abierta en ese perfil aislado.
El AVD desechable separado se detuvo después de las pruebas, conservando sus
archivos; el emulador habitual del usuario permanece en ejecución.

### Archivos y compatibilidad

Cambios principales en `apps/api/src/{auth,cash,recovery,sales,common}`,
`apps/api/prisma/schema.prisma` y sus tres migraciones; cliente en
`apps/fulltech_app/lib/core/{api,auth,cache,offline,storage}`,
`lib/features/offline`, `lib/modules/{cash,ventas}`; regresiones en `test/`,
aceptación en `integration_test/` y verificadores locales en `scripts/uat/`.
Android añade sufijo y etiqueta al perfil UAT; conserva la identidad normal.
No se actualizaron dependencias ni se alteraron reglas fiscales, de licencia o
inventario. Se probaron regresiones de payload fiscal y ticket offline dentro
de sus suites. Esto limita el riesgo observado; no demuestra ausencia universal
de regresiones en cada funcionalidad histórica.
En plataformas nativas, si SQLite no puede guardar el diario previo, se detiene
el envío de la operación y se informa el error. Las aperturas offline anteriores
sin prueba verificable permanecen para intervención administrativa; no se les
asigna una fecha nueva ni se sustituyen por una apertura financiera automática.

Las migraciones son `20261120120000_cash_movement_occurred_at`,
`20261120180000_offline_cash_open_evidence` y
`20261120183000_recovery_review_cases`. Agregan datos/evidencia; no borran
operaciones ni sustituyen las tablas financieras existentes. Las columnas
nuevas permiten registros anteriores sin evidencia; esos registros no reciben
una confirmación automática inventada.

### Decisión y pendientes reales

**NO-GO para publicar/desplegar de forma general.** Las aceptaciones Windows y
Android emulado descritas pasan, pero no hay Mac/iPhone ni teléfono físico para
aceptación de hardware. Web conserva sus capacidades actuales: no se promete
persistencia SQLite nativa ni durabilidad equivalente frente a cierre abrupto
del navegador/concurrencia entre pestañas. Una compilación Web solo demuestra
compatibilidad de compilación. Hace falta revisar/integrar esta rama con la otra
sesión y validar la versión integrada antes de cualquier decisión de release.
La copia de fuentes está aislada; `node_modules` del monorepo sigue enlazado a
la instalación local anterior. La instalación reproducible con el lockfile y
la generación de Prisma deben repetirse en el checkout integrado de release.
El contrato de apertura del cliente nuevo exige `openingAmount` y la prueba
firmada para apertura offline: se debe validar la pareja cliente/API con sus
migraciones. Un servidor anterior que omita evidencia deja el resultado para
revisión; no autoriza una confirmación inventada.
No se ejecutó commit, merge, push, publicación ni despliegue en esta continuación.
La revisión general de la página pública y de todos los mensajes del backend
permanece como siguiente etapa; este informe cubre recuperación/sincronización.

## Continuación en copia aislada — 2026-11-20

El usuario confirmó que otra sesión continúa editando el worktree anterior.
Esta continuación pertenece a `C:/src/fullpos-recovery-closing-isolated-20261120`,
rama `recovery-closing-isolated-20261120`, basada en `840caadf`. Se copió la
instantánea local con sus cambios y archivos nuevos; no se sobrescribe la copia
de la otra sesión. Los cambios de esta continuación deben revisarse e integrarse
desde esta rama; el archivo del worktree anterior no es el estado actual.

Producción, publicación y despliegue siguen excluidos. Todas las operaciones
financieras de prueba son sintéticas en PostgreSQL dedicado de loopback 56560,
base `fullpos_recovery_closing`. API propia en `127.0.0.1:4005`; Windows conserva
el guardia UAT usando un reenvío exclusivamente local `[::1]:4004 -> 127.0.0.1:4005`.
Android utiliza `adb reverse tcp:4004 tcp:4005`. El servidor ajeno de IPv4 4004
no fue detenido. La clave del laboratorio permanece privada bajo `.uat`, sin
credenciales ni tokens en los informes.

### Correcciones añadidas respecto al informe anterior

- Apertura offline: autorización HMAC con propósito separado, formato no JWT,
  limitada a empresa, usuario, dispositivo, sesión de autorización e intervalo
  de 48 horas. Se conserva `openedAt` original y evidencia de autorización;
  no se acepta una fecha arbitraria anterior a la autorización. Se comprueba
  revocación, solapamiento y caja diaria cerrada. Se mantiene la ventana
  financiera configurada de 24 horas: son límites diferentes. Las aperturas
  legacy sin evidencia quedan para revisión, sin inventar fechas.
- Intentos de venta antes del POST: durabilidad activada por defecto en todas
  las plataformas nativas con SQLite, además de Windows release. La ausencia
  de almacenamiento durable impide dar por completada una operación.
- Aperturas y movimientos offline: caché y cola se escriben en la misma
  transacción SQLite antes de presentar el resultado local. La fecha de negocio
  utiliza el helper común de Santo Domingo.
- Revisión administrativa: casos idempotentes con ámbito de empresa y usuario,
  eventos de auditoría conservados y decisiones con versión. Confirmar exige
  registro, actor, turno, tipo e importe coincidentes. El cierre comprueba el
  actor que cerró el turno. Un registro ausente o discrepante conserva el caso.
  Solo ADMIN puede declarar que no se realizó o mantenerlo en revisión, con
  motivo obligatorio. Estas rutas no crean asientos financieros ni reenvían
  ventas o movimientos. Se conserva el registro local original y su resolución.
- Centro: solicitudes de revisión, consulta del registro y decisiones auditadas;
  las resoluciones dejan los contadores activos y los importes locales pendientes
  sin eliminar la evidencia. Una declaración humana no equivale a confirmación
  financiera. Los fallos al solicitar revisión conservan la incidencia original.
- Almacén seguro: acceso serializado entre credenciales, sello offline y Guardian;
  se mantienen el plugin y el cifrado existentes. Un timeout del consumidor no
  permite solapar una operación nativa todavía activa. Un error no envenena
  permanentemente la cola de acceso. No se borraron archivos seguros para reparar
  el problema.

### Evidencia comprobada durante la continuación

- Backend: 122 pruebas PASS en 12 suites; TypeScript compilado.
- API/PostgreSQL reales: 8 escenarios PASS. Apertura de hace 10 minutos y
  movimiento original preservados; reenvío exacto conserva un solo movimiento;
  firma alterada, otra empresa, otro dispositivo y fecha futura rechazados.
  Dos casos conservados, cuatro eventos auditados, empresa ajena sin cambios.
  Caja diaria cerrada y autorización histórica revocada rechazadas con cero
  aperturas nuevas. JSON: `.uat/recovery-closing-20261120/api-closing-*.json`.
- Android 15/API35: primera aceptación funcional PASS con venta offline,
  reapertura SQLite, respuesta perdida tras commit, replay idempotente, refresh
  real, turno rechazado y operación nueva detrás de 45 bloqueadas. Se observaron
  46 incidencias conservadas al reabrir el almacén durante la prueba. La primera
  ejecución falló en la fase visual por el puerto UAT; el reenvío local corrigió
  la configuración sin modificar el guardia. `flutter test` retiró su paquete
  temporal al finalizar; no confundirlo con una instalación durable final.
- Windows: escenarios financieros y 30 escrituras cifradas concurrentes PASS;
  la primera fase visual falló por una espera de SQLite insuficiente. Se corrigió
  la espera y la devolución inmediata de los manejadores de errores del arnés.
  Esa ejecución parcial no se cuenta como aceptación nativa completa.
- Grupo de caja: 19 pruebas PASS en la última repetición aislada. Otras pruebas
  de revisión, sello y serialización pasaron en sus ejecuciones específicas.
- Análisis Flutter: PASS sin incidencias. La batería amplia y las aceptaciones
  nativas finales siguen en ejecución; sus resultados deben añadirse debajo.

No sumar recuentos de baterías solapadas. Se conservan los logs de ejecuciones
fallidas bajo `.uat`; no se presentan como PASS. Las esperas corregidas son del
arnés con I/O real: no se debilitaron las validaciones del producto.

### Límites todavía vigentes

La aceptación en emulador no sustituye un teléfono físico. El usuario solo tiene
Windows y no hay Mac/iPhone disponible: no se afirma aceptación iOS. Web mantiene
su alcance de persistencia existente; compilar no demuestra durabilidad frente
a cierre abrupto ni concurrencia entre pestañas. Producción continúa NO-GO hasta
cerrar las aceptaciones pendientes y revisar la versión concreta a publicar.
No hubo push, merge ni despliegue. La web pública y la revisión general de todos
los mensajes del backend son una etapa posterior a este flujo de recuperación.

## Continuación autorizada — cierre de pendientes (2026-11-20)

El usuario autoriza continuar la implementación pendiente sin producción.
Android 15/API35 `emulator-5554` está disponible; no hay Mac/iPhone disponible.
Se preserva todo el trabajo local anterior sobre840caadf.

Plan de cierre: autorización firmada y limitada por empresa/usuario/dispositivo
para reconstruir aperturas offline originales, sin ampliar la ventana financiera
ni reabrir cajas diarias cerradas; durabilidad previa de ventas en plataformas
nativas con SQLite; registro y decisiones administrativas auditadas para
operaciones rechazadas sin inventar asientos financieros; revisión del almacén
seguro UAT Windows; regresiones y aceptación local secuencial Windows/Android/Web.
Las incidencias legacy sin prueba de apertura requieren revisión explícita.
Ninguna corrección autoriza fiscalidad offline, cambios de licencia/inventario,
confirmaciones inciertas, publicación o despliegue.

## Current work — offline recovery stabilization (2026-11-20)

Base840caadf; own worktree C:/src/fullpos-detalles-finales-importante, branch
detalles-finales-importante. Owner authorizes the complete local correction and
validation of the ten recovery/synchronization requirements. No production,
publication or deployment. All financial test operations must be synthetic in
a new isolated PostgreSQL/API/Windows storage environment. Preserve fiscal,
license, inventory and existing cash-window rules. Do not delete incidents.

Plan: (1) scoped automatic recovery and strict confirmation validation;
(2) original movement timestamps and server validation; (3) fair dependency-aware
queue and consistent permanent/auth/conflict/rate-limit handling; (4) separate
connectivity, queue and intervention UI states; (5) regression tests for each
reproduced issue; (6) real Windows/API/PostgreSQL disconnect/reconnect/restart,
shift and tenant scenarios with before/after persistent evidence; (7) final
review and GO/NO-GO report including platform limits and user-visible messages.
The public website remains available for subsequent authorized work.

Audit baseline: existing Flutter68 and backend54 tests passed but five temporary
probes reproduced missing recovery scope, movement timestamp loss, starvation
behind40 blocked actions, unvalidated confirmation and mapped422 retries.
The baseline app is running as an isolated UAT Windows debug build; stop only
this owned process when rebuilding. Baseline has no production modifications.

### Informe de estabilización — 20 de noviembre de 2026

**Resultado: correcciones verificadas en Windows/UAT; NO-GO para producción.**
La recomendación no equivale a una garantía universal de ausencia de pérdidas.
Los límites y pendientes que impiden esa garantía están indicados más abajo.
HEAD permanece en `840caadf`; los cambios están locales y sin publicar.

#### Cambios realizados

| Requisito | Corrección y comportamiento resultante |
| --- | --- |
| Ámbito de recuperación | Inicio, temporizador, final de cola y reconexión obtienen empresa/usuario actuales. Se comprueba el propietario antes y después de consultar. Los reintentos HTTP quedan ligados al JWT del propietario original. El estado y los mensajes persistidos del motor y de la cola se separan por empresa/usuario y entorno UAT. |
| Fecha original | El replay de caja transmite `occurredAt`; un registro antiguo puede utilizar su `createdAt` original, nunca inventar la fecha del reenvío. Sin fecha comprobable queda bloqueado para revisión. La API valida ISO con zona, calendario, futuro y ventana del turno. Una columna nullable `cash_movements.occurred_at` conserva el instante original separado de `createdAt` de recepción, con precisión de milisegundos. No se reescriben filas históricas. |
| Cola y dependencias | Los registros permanentes se excluyen de la selección procesable; no ocupan los primeros 40 lugares. Se limita a 40 envíos reales por pasada. Se conservan dependencias de apertura, movimientos, ventas, devoluciones, abonos, cierres y productos/stock. Una operación independiente nueva puede continuar. |
| Confirmaciones | La conciliación exige requestId coincidente, identificador de venta string no vacío, importe esperado/registrado finito, igualdad monetaria y `matchesExpected=true`. Una discrepancia conserva evidencia e incidencia. El envío de ventas y el replay de movimientos también comprueban identidad e importe. El cierre exige turno exacto, estado CLOSED e importe coincidente; una respuesta incierta o un 404/409 no se considera por sí solo un cierre confirmado y deja incidencia durable. |
| HTTP 422 | El error mapeado y el Dio original reciben el mismo tratamiento permanente. Las consultas de recuperación con validación permanente dejan de sondearse automáticamente. |
| Otros HTTP | 401 conserva la operación y permite renovación real de sesión/reanudación del mismo propietario; 403 exige revisión de permisos y no se rehabilita como un 401; 409 se conserva para intervención. 429 acepta Retry-After en segundos o fecha HTTP, conserva la espera y evita saltarla mediante reintento manual. La API de conciliación devuelve Retry-After. No se modificaron reglas de licencia. |
| Contadores | Se distinguen pendientes, enviando, reintentables, bloqueadas y que requieren intervención. Se eliminan los límites de 200/500 registros que ocultaban incidencias o contadores. También se evita truncar a 50 registros las escrituras de la cola en preferencias. Una colisión de id local no puede sobrescribir otra empresa/usuario. |
| Conexión y presentación | La respuesta HTTP real demuestra accesibilidad; una caché no la demuestra. La cola vacía muestra «Sin pendientes locales», no «Todo sincronizado». El Centro muestra las ventas y operaciones de caja rechazadas, además de los intentos inciertos y declaraciones, con referencias y pasos de revisión. Cambiar de propietario limpia la vista anterior. |
| Turnos | Se preservan el destino original, la regla de cierre, el bloqueo de turnos de día anterior y la ventana financiera. No se reasigna una operación a otro turno ni se cierra caja automáticamente. |
| Duplicaciones | Se conserva el mismo identificador al desconectar, reconectar y reiniciar. El backend devuelve el movimiento original solamente si usuario, turno, tipo e importe coinciden; reutilizar la identidad con otro importe devuelve conflicto. |

#### Entorno y evidencia

- API NestJS exclusivamente en `127.0.0.1:4004`, con `APP_ENV=uat`, guardia local activada y ventana configurada a 24 horas.
- PostgreSQL exclusivo: contenedor `fullpos_recovery_stabilization_20261120`, puerto de loopback 56560, base `fullpos_recovery_stabilization`. Ningún contenedor compartido fue alterado.
- Perfil de datos Windows: `.uat/recovery-stabilization-20261120`; datos financieros exclusivamente sintéticos. No se ejecutaron ventas ni movimientos de producción, cambios fiscales, cambios de licencia o ajustes de inventario para aprobar pruebas.
- Se conservaron las incidencias rechazadas. La retirada normal de un intento correctamente confirmado conserva su auditoría transaccional; no se utilizó una eliminación de incidencias para resolver fallos.
- Se detectó otra sesión escribiendo en el mismo worktree; el usuario indicó que la pausaría. La migración duplicada del laboratorio se consolidó en un único archivo de código. La carpeta vacía sobrante fue archivada, sin borrar datos.
- La primera base experimental conserva su historial de laboratorio. Se verificó además toda la cadena de migraciones sobre la base nueva y vacía `fullpos_recovery_stabilization_clean`, sin resetear ni borrar la primera base.

| Validación ejecutada | Resultado y alcance |
| --- | --- |
| Flutter: offline, auth, API, errores, caja, durabilidad de ventas y Centro | 341 pruebas PASS; 4 pruebas opt-in omitidas, sin contarlas como aprobadas. |
| Regresiones finales después de aislar metadatos | 51 PASS; incluyen restauración de mensajes/contadores por propietario, 401/403/409/422/429, reinicio SQLite, dependencias y cierres inciertos. No deben sumarse a 341 como si fueran pruebas distintas. |
| Backend: caja, conciliación y obligaciones | 104 pruebas PASS, 11 suites. Incluyen seis regresiones nuevas de fechas, persistencia e identidad del movimiento. |
| Flutter analyze | PASS sin incidencias; análisis focal posterior de los últimos cambios también PASS. |
| API build | PASS con Prisma generado y TypeScript. |
| Web release build | PASS JavaScript. El dry-run Wasm advierte sobre dependencias existentes; no se afirma soporte Wasm. |
| API real + SQLite real en Windows host | 5 PASS: intento inexistente, intento confirmado, declaración tras caída, HTTP 422 real permanente tras reinicio, y 429/500/timeout mediante sockets reales con envío posterior único a PostgreSQL. |
| Ejecutable nativo Windows | PASS: venta offline, reapertura SQLite/motor, respuesta perdida después del commit del servidor, replay idempotente, fecha de movimiento, renovación real tras 401, rechazo de turno anterior, 45 registros bloqueados delante de trabajo válido, cambio de ámbito y render del Centro con incidencias persistidas. |
| Verificación PostgreSQL posterior al escenario nativo | PASS: exactamente 2 ventas y 3 movimientos, cero duplicados, ningún movimiento aplicado al turno rechazado; cierre contado=114, esperado=114, diferencia=0; turno posterior permanece OPEN. Se conservan 46 incidencias en SQLite después de reiniciar. |
| Aceptación API/PostgreSQL adicional | 11 escenarios comprobados, incluyendo empresas reales distintas, permisos 401/403, rate limit real, turno de 26 horas, operación nocturna histórica y cierre de turno antiguo. Uno documenta el límite de apertura offline tardía, no su resolución. |
| Migraciones desde base vacía | PASS de la cadena completa, incluida la columna nueva nullable. No se aplicó ninguna migración a producción. |

Archivos de evidencia local, ignorados por Git y sin credenciales en el informe:

- `.uat/audit-caja-sync-20261120/flutter-final.log`
- `.uat/audit-caja-sync-20261120/last-regression.log`
- `.uat/audit-caja-sync-20261120/live-api-5-sequential.log`
- `.uat/audit-caja-sync-20261120/windows-scope-final.log`
- `.uat/audit-caja-sync-20261120/flutter-analyze-final.log`
- `.uat/audit-caja-sync-20261120/web-build.log`
- `.uat/audit-caja-sync-20261120/migrations-clean.log`
- `.uat/recovery-stabilization-20261120/windows-persistence.json`
- `.uat/recovery-stabilization-20261120/postgresql-native-crosscheck.json`
- `.uat/recovery-stabilization-20261120/api-postgresql-evidence.json`
- `.uat/recovery-stabilization-20261120/windows-recovery-center.png`

Verificación visual final tras iniciar un proceso nuevo con `flutter run -d
windows`: aplicación abierta y Centro de recuperación visible. El menú muestra
servidor accesible, 0 pendientes, 0 reintentables y 46 bloqueadas sintéticas;
el Centro muestra esos mismos contadores y conserva las referencias originales.
Se comprobó mediante lectura y captura de la ventana nativa. La aplicación y la
API local quedan abiertas para revisión. Las 46 incidencias son fixtures de
aceptación, no registros de un negocio real.

Se registraron fallos intermedios del banco de pruebas (proxy gzip, comparación
de microsegundos frente a milisegundos y restauración de handlers de Flutter).
Fueron corregidos y la aceptación nativa pasó. Ejecutar builds/tests Flutter
simultáneos también produjo conflictos de assets nativos/MSBuild; se repitió
la aceptación de forma secuencial. Estos intentos fallidos permanecen en los
logs y no se presentan como aprobaciones.

#### Límites financieros comprobados

HECHO: el proceso local usa `CASH_SHIFT_MAX_SPAN_HOURS=24`. El valor por defecto
del código es 24, con techo 72; el desfase por defecto es 5 minutos, con techo
30. No se inspeccionó ni se afirma el valor configurado en producción.

HECHO: el gate exige cierre al cambiar el día comercial. La validación de un
replay usa la fecha original y permite una operación nocturna del día siguiente
dentro de la ventana, si el turno original sigue abierto. Son comprobaciones
distintas; la prueba de replay nocturno no demuestra que la interfaz permita
mantener cualquier turno abierto indefinidamente.

#### Pendientes y recomendación

1. **Aperturas offline antiguas:** la apertura actual del servidor usa la hora
   de recepción. Un movimiento ocurrido más de la tolerancia antes de esa
   apertura devuelve `CASH_OPERATION_BEFORE_SHIFT`. Se reprodujo con 10 minutos
   de diferencia y cero movimientos insertados. La cola conserva la operación
   para revisión. Aceptar una apertura retroactiva requiere un protocolo de
   evidencia autorizado; no se habilitó una fecha arbitraria del cliente ni se
   debilitó la ventana financiera para aprobar el escenario.
2. **Alcance de durabilidad por plataforma:** la reserva previa de intentos de
   venta del código base está habilitada por defecto en Windows release. La
   prueba nativa activa explícitamente ese mismo modo. No se afirma que Android,
   iPhone o Web tengan esa misma garantía frente al cierre abrupto de una venta
   online incierta. Esa extensión y su aceptación por plataforma quedan
   pendientes; el build Web no sustituye esa prueba.
3. **Revisión administrativa de caja rechazada:** ahora es visible y conserva
   evidencia, pero el Centro no incorpora un nuevo mecanismo financiero para
   regularizar esos movimientos. No se inventó una venta ni se trasladó el
   movimiento a otra caja. Hace falta completar la resolución autorizada de
   estos casos antes de prometer que todos pueden resolverse dentro de la app.
4. **Credenciales UAT Windows:** el plugin registró advertencias de descifrado
   de su archivo seguro UAT; el fallback permitió renovar la sesión en la
   prueba. No se borró manualmente ese archivo. Debe verificarse el almacén
   seguro de una instalación limpia antes de aprobar distribución.
5. Quedan pendientes aceptación física Android/iPhone y pruebas de navegador
   sobre sus capacidades reales de persistencia. No se verificó una instalación
   de producción ni se modificó su configuración.

RECOMENDACIÓN: GO únicamente para revisión y más aceptación en este laboratorio
local. **NO-GO para publicar o desplegar** mientras sigan pendientes la apertura
offline tardía, la resolución administrativa y la garantía por plataforma.
La revisión integral de la web y de todos los mensajes del backend es una etapa
posterior; en esta corrección se revisaron los mensajes del flujo de recuperación,
cola y caja descritos arriba. No hubo push, publicación ni despliegue.

## Current work — final public website refinements (2026-11-20)

Worktree C:/src/fullpos-detalles-finales-importante; branch
detalles-finales-importante, created at PR52 HEAD0c16a76a. Owner requests local
website corrections and a VS Code preview. No push, merge or deployment requested.

Prices and user/product/warehouse limits match the existing backend catalogue
(seed read as source only). Preserve the agreed commercial e-CF wording without
publishing numeric e-CF quotas. Clarified FAQ user limits and e-CF eligibility;
home/pricing now explicitly identify Negocio/Pro/Empresa for the guided assistant.
Mobile marketing header scrolls with the root document at widths up to900px;
desktop stays sticky. Larger mobile plan text, badge clearance, keyboard-focusable
comparison carousels and explicit menu close; same-page links close the popover.

Validation: website14 tests PASS, Astro check0 errors/0 warnings (existing
returnValue deprecation hint), static build14 routes PASS. Native VS Code browser
inspection: home, pricing and menu at approximately420px and narrow pricing at
approximately320px; desktop pricing inspected at approximately1900px. Vertical
scroll moves mobile header out of view; horizontal scroll reaches Negocio with
its full recommendation badge visible. Local preview http://127.0.0.1:4325/.
Browser toolbar hiding on a physical Android Chrome device is not verified;
the page preserves native document scrolling and cannot force Chrome's toolbar.

Owner follow-up: replace the separate two-line notice with a single24px line
inside the header: "Facturación electrónica disponible", white background and
subtle moving1px accent respecting reduced motion. Replace the rounded floating
menu with a rectangular full-height right drawer; remove its WhatsApp/phone row,
keep close/navigation/registration actions. Preserve the non-sticky mobile header.
Follow-up validation:14 website tests PASS; Astro check0 errors/0 warnings with
the same existing hint; build14 routes PASS; git diff --check PASS. Inspected the
single-line header and edge-aligned drawer around320/420px in VS Code; explicit
close works and both bottom actions remain visible. Local preview remains open.

Owner additionally authorizes square website buttons and a commit of all local
website refinements in this branch. Shared button radius0 covers CTA sizes,
header/drawer, mobile bar, downloads, floating WhatsApp, carousel controls and
auth actions (including password/niche/modal controls). Standalone preparing
page matches. Scope remains website/docs only; no push/deployment authorized.
Final checks for square buttons:14 tests PASS, Astro check0 errors/0 warnings
(same existing hint), static build14 routes PASS. Visual inspection in the VS Code
browser confirms square header/hero/mobile bar/WhatsApp/drawer buttons, mobile
login actions and desktop home actions. No authentication form was submitted.
Owner's final exception: restore the floating WhatsApp button to50% radius;
its pulse inherits the circle. All other action buttons stay square.

Historical authorizations and production state below do not extend this task.

## Current work — recover pending Plans, IA and cash warning (2026-11-20)

Owner authorizes auditing all related branches and recovering the omitted work
for commit/PR integration into production-main, followed by a safe owner-driven
deployment. Worktree C:/src/fullpos-recover-ui-20261120, branch
agent/recover-plans-ia-cash-20261120, base d35fc09e (deployed PR51).
Execution is continuous through local audit, integration, validation and authorized
commits; owner retains merge/deploy. No production configuration/data changes.

Audit: 219 Git references inventoried, 19 named related references reviewed.
The existing IA design (19d3a57c/bf03b30e/b2fb1b54) and backend account context
1bb48ae0 are already in main; do not replace them with older dirty worktrees.
Omitted: seven uncommitted files from fullpos-planes-de-pago-impl (POS company
Plans side panel, navigation test and five marketing website files). Source
checkpoint captured privately without env/backups. Original source remains intact.
Cash warning aa79fa75 was absent; merge c0f32092 retains its original ancestry.
Excluded: unrelated menu-removal commit13e039b1, host baseline ebfdda35, unrelated
generated files, media evidence and real database backups.

Plan: recover only the pending UI diff, align public catalogue copy with the
existing documented/seeded catalogue, retain server license/fiscal rules and
cash policy. Cash wording reflects the existing previous-business-day condition,
not a new 24-hour timer or an automatic close. Revalidate AI, cash, plans, fiscal
flows and visuals before publication. No API/schema/migration changes required.

Local checks: company-panel10 PASS at1280/390, including payment navigation,
legacy license preservation and neutral blocked-license wording. Broad859 PASS;
final Plans/panel64 PASS after preserving themed button typography. Final full
Flutter analyze PASS, web release build PASS54.9s. Website14 PASS, Astro0 errors/
0 warnings (one existing hint), build14 routes PASS. Visual captures use actual
widgets and synthetic data. API, schema, fiscal and AI code diffs remain empty.

Pending: commit recovered files only, publish PR and inspect CI. Owner's claim
that IA appears old in private remains under visual clarification; all named IA
design commits are already preserved and must not be replaced by old snapshots.
Never merge/deploy automatically or assign catalogue plans to existing clients.

## Current work — state-aware fiscal home and public logout (2026-11-15)

Owner requests visual audit before local fixes: no fiscal bottom-sheet menu or
help appbar action, no perpetual congratulations, correct new public website on
logout, preserve unfinished certification. Own worktree fullpos-fiscal-home-logout-20261115,
branch agent/fiscal-home-logout-20261115, base a495c356. Captures/code audited:
completed state rendered celebration permanently; shell added duplicate menu;
internal Flutter '/' rendered legacy landing rather than server-side Astro.
Plan: direct compact fiscal home gated by backend readiness, local once-only
company/user acknowledgement, retain pending wizard, full-document public route
only on Web; tests and synthetic desktop/mobile preview; no deploy/production writes.

Local results: full Flutter analysis PASS91.9s; regression544 PASS covering e-CF,
auth, routing and startup; initial focused54 PASS. Full app UAT web build PASS72.2s,
private gallery PASS31.4s. Browser1440/390 PASS on notice acknowledgement,
re-entry, company isolation, incomplete readiness and full-document public exit
that clears Astro session. Public exit used local compiled Astro as a fixture;
no real company login/logout/emission. Screenshots inspected. Gallery available
127.0.0.1:53900. New views use actual widgets and private synthetic callbacks.
No appbar fiscal menu or help registered; debug-only selector preserved.
No API/schema/credentials/ranges/production changes. No commit/push/merge/deploy.
GO for local review; owner must review before publication/deployment.

## Current work — public website, startup and three histories (2026-11-15)

Owner requests a separate electronic-invoicing announcement above the public
navigation, Dominican-only positioning and bank-transfer-only plan payment copy;
remove the old branded HTML access cover so the existing large-logo/ring Flutter
splash becomes visible at the first frame; narrow history search and square
filter controls/panels for sales, quotations and credit; preview together locally.
Own worktree C:/src/fullpos-web-history-polish-20261115, own branch
agent/web-history-polish-20261115, base production-main deb96f86 (merged PR47).
No production changes, deploy, migration, real invoice or shared worktree edits.

Audit: the HTML cover hid Flutter until completion instead of its first frame.
Astro login added another handoff cover; its busy button already covers waiting.
Desktop history search had unbounded width; quote/credit share HistoryToolbar
with an existing maxSearchWidth property, while sales has a separate toolbar.
Mobile auth fixed-height nested scrolling prevented document-level scrolling.
Browser chrome belongs to Chrome/Safari: document scrolling can be repaired,
but hiding an address bar cannot be guaranteed by page CSS or headless emulation.

Plan/acceptance: implement only copy/layout/loading-cover changes, keep auth
ticket/session logic and fiscal/business operations intact; run website unit,
check/build, Flutter analysis and targeted history/fiscal regression; inspect
desktop/mobile visual artifacts and serve a local synthetic preview for owner
review. Existing approved design/fiscal history is preserved. No auto merge/deploy.

Local acceptance: website13 tests PASS, Astro check0 errors/0 warnings with one
pre-existing returnValue hint, website14 routes built. Flutter full analysis
PASS118s; final three affected control files analyze PASS. Final full-app web
release build PASS96.8s, private synthetic gallery build PASS. Broad sales,
quotation, startup and fiscal history regression391 PASS; final Windows39 and
Linux39 history tests PASS without updating references. Browser10 checks PASS
at1440/390, zero page errors, all external requests blocked except locally served
CanvasKit; fiscal action text visible/clickable with external fonts blocked.
Private preview fixture/session and mobile accessibility selectors were corrected
without changing product authentication. Intentional scoped PNG baselines
updated on Windows/Linux and sampled visually. No test tolerances relaxed.

Local previews remain available: website127.0.0.1:49975, gallery127.0.0.1:59627.
Gallery tabs: sales, quotations, credit, actual Flutter splash and fiscal toolbar.
No API/schema/migration/lockfile change. No SSH, production access or real billing.
Owner reviewed the design on 2026-11-15 and approved it without further changes.
Integration continues as a new PR to production-main; deployment, the optional
activity migration and its flags remain separate decisions. Previews were
restarted on the same local ports after the earlier servers stopped replying.
NO-GO for deployment until the owner authorizes it explicitly.

## Current work — fiscal navigation and company activity integration (2026-11-15)

Owner confirmed the activity writer finished and authorized integration of the
pending work. Own worktree C:/src/fullpos-fiscal-activity-integration-20261115,
branch agent/fiscal-activity-integration-20261115, base origin/production-main
859bc5a9. Source worktree is clean at0576cfd0. Merge5db36b6b preserves commits
ec6c2b05/0576cfd0 and the entire existing fiscal/design ancestry. The only merge
conflict was main.dart: retain the current login-aware AppErrorOverlay and add
the default-disabled UsageActivityBoundary around the existing stack.

Plan: audit activity authentication, company isolation, optional-table behavior
and retention; integrate source commits; clarify fiscal navigation and the empty
invoice tray; validate backend, real disposable PostgreSQL, Flutter, browser
layout and regressions; review provenance and publish one reviewable PR.
The client reporting build flag and server collection flag stay off by default.
The new additive migration is tested only on dedicated local fixtures56701.
No production migration, data/configuration change, deployment or real emission.
Main merge and deployment remain review gates; further requested design edits
can be added to this same PR before release.

Local results: API build/schema PASS, migrations only on disposable local DBs
PASS, backend3362 PASS/101 conditional skips, fiscal PostgreSQL32 PASS,
HTTP56 PASS, Flutter767 PASS, analysis PASS89.1s, real app web build PASS80.7s.
Published draft PR47 targets production-main and has22 changed paths with a
matching remote/local inventory. The synthetic browser harness compiles, but
its header action labels were not rendered, preventing navigation validation
by accessible name. The completed-view screenshot was inspected; this does not
grant visual PASS. Further design changes/review remain in the same PR.
NO-GO for main merge/deploy until visual acceptance and final GitHub gates.

## Current work — consolidate deployed CRM licenses and PR45 (2026-11-15)

Owner authorized local consolidation after the deployed backend changed to
crm-license-daleventas:87316912. Own worktree C:/src/fullpos-license-fiscal-20261115,
branch agent/consolidate-license-fiscal-20261115. Base221d530c contains PR45 and
all approved design/fiscal work. Commit87316912 is merged without conflicts,
preserving its ancestry; only six license files are added/changed by that merge.
The original license worktree has uncommitted usage/activity work and is read-only;
none of those unfinished changes or migrations enter this consolidation.
Plan: preserve the deployed license implementation, verify HTTP authentication
and tenant-safe/idempotent commands, run license and fiscal PostgreSQL regression,
then review the final diff and create the reviewable checkpoint. No merge into
production-main, production migration/configuration change or deploy is authorized.
Dedicated local PostgreSQL56701 will contain separate disposable fiscal and CRM
fixture databases, with synthetic credentials and external emission disabled.
The CRM fixture guard admits that exact loopback port and name, rejecting URL
query/hash. Build PASS, CRM PostgreSQL12 PASS, HTTP boundary6 PASS, fiscal
atomic/readiness/returns PostgreSQL32 PASS. Docker lock756 packages PASS.
Full backend suite3353 PASS/101 skipped,280 suites PASS/13 skipped (300.688s).
Additional license/fiscal preservation regression1 PASS, executed separately.
Fiscal HTTP regression44 PASS/3 suites. Full built Nest application HTTP smoke
8 PASS with synthetic companies:bridge auth, legacy license endpoint, versioning,
deduplicated command and tenant-specific session revocation. Additional regression
typecheck PASS. Audit generators168 models/435 endpoints; CI YAML parse PASS.
Local consolidation validated; preserve both parent histories in its checkpoint.
GitHub checks for the review head are still a separate gate. No product UI,
schema/migration/lockfile/Dockerfile changes. Do not deploy the old221d530c API
over the live license backend. Owner retains main merge and deployment.
Original activity
writer changed two uncommitted activity files during this task; original HEAD
remains87316912 and no edits from this consolidation target that worktree.
Do not claim the original worktree is frozen. Deploy remains NO-GO.

First consolidation commit643dffe9 preserves parents221d530c/87316912 and is
published in draft PR46. CI43736648017:API/site/Windows PASS; Flutter failed7
reports goldens that use the real date (reference14 Nov, execution15 Nov).
No reports code differed from PR45 at that commit. Minimal follow-up provides
an optional reference date, defaulting to the system date, and fixes only the
golden fixture date. Existing PNGs/tolerances remain unchanged. Initial reports
regression18 PASS on Windows and Linux; explicit system-date regression added.
Final follow-up19 reports tests PASS on Windows and19 PASS on Linux, without
updating golden references. Full Flutter analysis PASS61.5s and Linux scoped
analysis PASS24.3s. New CI remains a gate. Do not publish the API candidate
from643dffe9 on the strength of the failed first run; prepare images tied to
the final reviewed head. The old UI-byte-identical claim applies only to the
initial consolidation; this follow-up changes the optional report date seam.

## Current acceptance — PR45 (2026-11-14)

Owned worktree/branch below; PR45 targets production-main and remains owner-controlled.
Initial commits5bbc36b7/385df9f7 preserved. Four CI jobs passed at385df9f7.
Isolated real API/PWA acceptance found normal-sale Web PDF blocked by native
SQLite printer settings. Minimal fix returns browser defaults in getOrCreate,
preserving native storage and avoiding legacy cross-company receipt identity.
Browser regression and Chrome CI step added; no dependency/schema/runtime change.
Post-fix analysis PASS135.7s; settings/printing/PDF regression228 PASS,1 explicit
browser-only skip. Windows Chrome test harness blocked by SDK CanvasKit404;
new Linux CI Chrome test must be verified, not inferred from earlier CI success.
API17 checks, print projections5, returns6 PASS with fictional Alfa/Beta and
zero external emission attempts. Real E34 export/QR decode and transient offline
notice verified in isolated browser. Fiscal accepted statuses are synthetic.
Rebuilt combined UAT PWA PASS; actual history NORMAL PDF download PASS with
ITBIS18/total118 and zero fiscal print reads. E31 PDF download PASS with one
fiscal print read, fixture expiry and decoded QR. NORMAL/E31/E34 PDF rendering
and extraction PASS; both fiscal QR decode PASS. Offline recheck:0 fiscal POST.
Web filter segment text and fixture em-dash PDF glyph remain visual observations;
no cold deep-link, physical printer/device or service-worker acceptance claimed.
See docs/VISUAL_FISCAL_UAT_20261114.md for evidence, limitations and final gates.
No source worktree or production data/config changed; no merge/deploy authorized.

## Current work — integración visual/fiscal segura (2026-11-14)

Own worktree C:/src/fullpos-integration-20261114,
branch agent/integrate-visual-fiscal-20261114, base origin/production-main cbc3eceb.
Owner requested preserving all detalleVisuales and fiscal work before integrating
to production-main. Source snapshots/hashes complete; design72 modified+245 new,
fiscal55 modified+77 new, plus three raw-normalized generated files preserved.
Original checkout preserved separately; no source worktree cleaned or modified.
Two design conflict files resolved preserving fiscal badge/panel and visual drawer.
Fiscal patch applied cleanly afterward. API build PASS; final automated validation PASS.
Dedicated disposable PostgreSQL in loopback55500; no production DB/config touched.
Current report:docs/VISUAL_FISCAL_INTEGRATION_20261114.md.
Private evidence/scripts: C:/Users/pc/.codex/backups/fullpos-visual-fiscal-integration-20261114/.
API final3341 PASS/101 skipped; return PostgreSQL15 PASS; HTTP3 suites/44 PASS.
Full Flutter final2426 PASS/9 skipped/0 failures in about10min, after stale UI assertions,
reviewed references and bounded SQLite waits were corrected. Earlier failures
are documented in the report, not hidden. Focused fixes179 PASS; cash19 PASS.
Full web UAT build PASS156.9s; website12 tests/check/build PASS; full analysis
PASS278.4s and final10 modified helper/test files PASS48.1s.
Linux final42 visual tests PASS, without update mode; eleven Linux PNG references
copied back after inspection (seven logo/search plus four header border images).
Windows selected14 PASS; final full suite verifies Windows references normally.
Tenant inventory168 models/endpoint matrix431 rows generated successfully;
timestamp-only changes preserved privately and excluded from the candidate.
Final provenance449 source records:434 byte-identical,15 merged/reviewed,
no missing files, no changed originals, no high-confidence secret candidates.
Final candidate inventory472 paths in docs/VISUAL_FISCAL_INTEGRATION_FILES_20261114.md.
Integration test helper added at test/support/feedback_finders.dart. Preserve
semantic X close affordance; no tooltip reintroduced into approved design.
Generated notification screenshots copied privately and restored narrowly to HEAD;
Windows failure evidence moved safely into the task backup, excluded from Git.
App .env is synthetic/ignored. No schema/migration/lockfile/Docker diffs.
The later acceptance above adds a Chrome CI regression step.
Remote re-fetch confirms cbc3eceb; branch upstream removed to avoid an accidental
default push to production-main. Original worktrees remain untouched.
Owner subsequently authorized commit/push/PR of this exact integration candidate.
Only agent/integrate-visual-fiscal-20261114 may be published, targeting production-main.
Do not force-push, merge, deploy, restart or change production data/configuration.
NO-GO for release: PR CI and real UAT remain gates. Local evidence above is final;
consult the actual PR checks for publication status, not these frozen local results.
The previous task state below is retained as source history, not current status.

## Current work — paired fiscal design review (2026-11-14)

Owner requested a preview and joint screen-by-screen refinement before any deploy.
Owner selected Empresa and the fiscal module entry as the first review scope.
All previous self-service changes remain on the same owned isolated worktree and
branch below; no other worktree or production operation is authorized.

Current design iteration explicitly requested by owner:
- Owner resolved "screen20" as19 fiscal configuration. Updated only that
  layout and its numbering summary: responsive two-column panels on desktop,
  one column on mobile, rectangular6px buttons, compact existing consent switch,
  readable stacked numbering metadata, no empty document-types panel.
  Existing permission checks, confirmation text and repository writes preserved.
  Added desktop640px control-visibility/button-shape regression plus actual
  preview1280x760 E34-action visibility check.55 regression tests PASS before
  the final text-button border polish; scoped analysis4 files PASS (4.2s).
  Final14 preview tests PASS after final border polish. Final scoped analysis
  four files PASS (3.9s), git diff --check PASS. Preview compiled31.3s,
  session3652, HTTP200 at localhost4804. Desktop1280x760 and390px mobile
  widget captures inspected and archived at docs/ecf/config-compact-design-2026-11-14/.
  Logs:config-compact-tests-final.log, config-compact-preview-final.log,
  config-compact-analyze-final.log, config-compact-server.log.
  No browser/device interaction or production operation. Deployment NO-GO.
- Owner requested compact tracking (4–6), a single centered pending-close card
  (15), rectangular tray filters/search and finer rows (16–18). Implemented in
  existing widgets only: tracking max-width700/neutral subtitle, embedded
  numbering in a single pending EcfSurface,6px tray controls/row borders and a
  compact neutral connection-error row. Selected-filter text contrast corrected.
  The optional embedded flag defaults false, preserving other EcfSection callers.
  Gallery fixtures now use actual known pending reason and AUTHORIZED_SANDBOX
  for the certified example; previous demo values caused raw/fallback messages.
  Pending-close fixture uses fictional PRODUCTION numbering for customer copy.
  Regression82 tests PASS across preview/tray/completion/numbering/flow/activation.
  Final preview13 tests PASS after fixture adjustment; scoped analysis9 files
  PASS (66.8s). Preview compiled40.3s, session35363, localhost4804 HTTP200.
  Desktop/mobile captures inspected for tracking, close15, tray16 and error18;
  fourteen captures archived at docs/ecf/compact-fiscal-design-2026-11-14/.
  Final diff reviewed and git diff --check PASS. No production changes.
  Logs:compact-fiscal-tests.log, compact-fiscal-preview-final.log,
  compact-fiscal-analyze.log and compact-fiscal-server.log.
  Owner also mentioned screen20, but gallery has only4–19: async clarification
  asks whether this means19 configuration or the E34 dialog; no reply yet.
  Do not claim that unidentified screen completed.
- Owner requested multiple remaining screens for joint review. Added local-only
  EcfDesignGallery (test/preview) with16 scenarios numbered4–19: request/tests/
  certification/network failure, unsigned/signed authorization, production
  action, new/active/expired numbering, ready/incomplete closure, documents
  populated/empty/error, and fiscal configuration. All mount real widgets;
  no production UI or fiscal behavior changed in this iteration.
  Numbering/configuration use synthetic PRODUCTION data to review the actual
  customer labels; no credential or real authorization is used. Other examples
  remain synthetic SANDBOX. HTTP stays blocked by the existing adapter.
  Inventory:docs/ecf/FISCAL_DESIGN_REVIEW_2026-11-14.md lists what is present
  and all identified auxiliary/admin/dialog/printing areas still to review.
  Initial gallery tests found Riverpod nested-scope dependencies; explicit
  local provider overrides and a local Navigator fixed the fixture. A subsequent
  page/list return-type compile error in that override was corrected.
  Final13 tests PASS across390/1280px, exercising all16 gallery scenarios plus
  existing Empresa/welcome/preparation regressions. Final scoped analysis of
  three preview files PASS (3.7s); git diff --check PASS.
  Generated32 gallery captures; inspected mobile documents/authorization and
  desktop production-numbering. Evidence:docs/ecf/gallery-design-2026-11-14/.
  Logs:gallery-tests-final.log, gallery-analyze-final.log, gallery-server.log.
  Browser interaction and physical devices remain unverified. Deployment NO-GO.
- Preparation follow-up: owner requested neutral FullPOS-facing assistant copy
  and optional managed setup advertising for US$150 paid once. Removed DOSA
  from the preparation card description only; provider integration is unchanged.
  New EcfManagedSetupOffer below the primary card reuses SupportConfig (the same
  contact used by features/assistant/data/assistant_whatsapp_service.dart).
  Opens WhatsApp with a prepared inquiry; no automatic message/payment/session.
  A brief fade/slide entrance respects reduced-motion/accessibility preferences.
  No perpetual animation, popup or change to primary postulation action.
  Local regression:59 tests PASS (offer, preview, fiscal steps, DOSA section).
  Tested URI target/message, 320/700px with1.4x text, reduced motion and CTA.
  Desktop/320px rendered captures inspected; three preparation captures archived
  at docs/ecf/managed-setup-design-2026-11-14/. No real WhatsApp message sent.
  Scoped static analysis PASS:five files, no issues (122.5s).
  Preview compiled in45.3s, session43077, HTTP200 at localhost4804.
  Logs:managed-setup-tests.log, managed-setup-analyze.log,
  managed-setup-server.log. Final diff reviewed; git diff --check PASS.
  Browser/physical-device interaction remains unverified; native widget renders
  and navigation were checked. Production remains NO-GO until owner approval.
- Welcome follow-up: owner requested only refinement of the video and text
  columns, then access to the next screen. Balanced desktop columns, aligned
  video padding and readable14px step descriptions preserve the existing flow.
  The missing-video state remains explicit, without a disabled duplicate action;
  its caption no longer incorrectly references three DGII prerequisites.
  Preview now exposes `3. Preparación` directly; Comenzar still navigates there.
  Fixed its incomplete fixture: the real DosaAssistantSection now receives local
  eligibility and intent responses. Previously the fixture lacked dosaEntry and
  displayed a permission notice instead of the postulation card. Registration
  is overridden to reject locally, with no real provider/session request.
  Regression asserts the real card/button, the blocked action and return route.
  No video uploaded, no provider/session opened and no production touched.
  Validation:44 preview/fiscal-flow/certificate tests PASS. Initial run failed
  only on an assertion of the replaced introduction; updated to the intended
  copy, then all44 passed, including the final complete preparation fixture.
  Final scoped analysis of six files PASS (4.8s).
  Screenshots at320/390/1280 plus compact desktop generated; desktop and320
  inspected; the final real preparation card was also visually inspected.
  Browser interaction remains unavailable; these are widget renders.
  Evidence logs:welcome-design-tests-final.log, welcome-design-analyze-final.log.
  Updated preview compiled in40.3s, session43386, HTTP200 on localhost4804.
  Captures archived at docs/ecf/welcome-design-2026-11-14/.
  Deployment remains NO-GO pending explicit owner authorization.
- Owner approved the compact company design, then requested visible optional logo
  upload and a cleaner mobile appbar, and explicitly authorized advancing to the
  next screen after those corrections. Logo upload/change now appears in the data
  header using the existing picker/normalization/save flow. Only Empresa opts
  into a plain mobile AppBar (title/back/sync), avoiding web-session window pills
  in that narrow header. Other screens retain their existing bars.
- Next joint screen: fiscal welcome. Corrected its inaccurate "sin salir de
  FullPOS" copy to explain browser handoff and return. No external session is
  opened by the local preview. Remaining welcome design is for owner review.
- Follow-up regression95 tests PASS (preview, account, fiscal flow). Scoped
  analysis PASS with no issues (40.5s); final preview9 tests PASS after the upload
  label adjustment. Logs: company-logo-appbar-tests.log,
  company-logo-appbar-analyze.log and company-logo-preview-final.log.
  Follow-up files: account_menu_screens.dart, ecf_welcome_step.dart,
  ecf_design_preview_test.dart, PRODUCT_SPEC.md, EXECUTION_STATE.md and the three
  existing company-design screenshots. No global appbar behavior was changed.
  Preview server session13420 compiled in21.3s and serves HTTP200 at
  http://127.0.0.1:4804/ for the next joint review. Final screenshots refreshed.
- Default company fields: name, optional RNC, phone/address; optional legal
  representative name/ID remain visible. Header disclosure "Ver más" contains
  logo, fiscal email, other contacts, extra representative fields and banking.
- "Activación de módulos" is a flat responsive set of columns, with compact
  rectangular switches beside their labels; existing confirmations and permissions
  remain. Inventory and sales share columns in phone widths where they fit.
- Same controllers/save contract preserve hidden values. A save regression
  exposed existing loss of additional bank accounts; retaining the existing tail
  fixes it without changing the primary-account editing contract.
- Local widget regression93 PASS: company save with hidden data and empty
  optional identity fields, disclosure persistence, consent/permissions/tenant
  navigation, keyboard/disabled semantics, desktop1264x681 without scrolling,
  Android/iPhone-sized mock views. This is layout simulation, not device QA.
- First analysis found two deprecated test semantics calls; updated to current
  flagsCollection API. Final whole Flutter analysis PASS (96.5s). Early test issues
  (semantics handle cleanup, old title assertions and a generic dropdown finder)
  were corrected; no failing assertion was disabled.
- Desktop, Android-sized and iPhone-sized screenshots rendered with real widgets
  were inspected and retained in docs/ecf/company-design-2026-11-14/.
- Only generated unrelated notification PNGs from this run were restored to HEAD.
  Other worktrees, production data/config and the previous fiscal work are intact.
Validation commands actually executed from apps/fulltech_app:
`flutter analyze --no-pub`: PASS, no issues.
`flutter test --no-pub test/core/widgets/compact_square_switch_test.dart test/preview/ecf_design_preview_test.dart test/features/account test/features/ecf/ecf_sales_without_document_section_test.dart`:
93 PASS. Evidence in company-design-analyze-final.log and
company-design-regression-final.log under the private backups folder.
Final diff review/check PASS; unrelated generated notification images restored.
Preview was stopped only for sequential validation, recompiled successfully in
21.8s and serves HTTP200 on127.0.0.1:4804 (server session65713).
No commit/push/merge/deploy is authorized here.
Owner review of this company screen is next, before moving to another screen.

Files in this company design iteration:
apps/fulltech_app/lib/features/account/account_menu_screens.dart;
apps/fulltech_app/lib/features/ecf/ui/ecf_config_page.dart;
apps/fulltech_app/lib/core/widgets/compact_square_switch.dart;
apps/fulltech_app/test/core/widgets/compact_square_switch_test.dart;
apps/fulltech_app/test/features/account/account_settings_navigation_test.dart;
apps/fulltech_app/test/features/account/ecf_company_toggle_drawer_test.dart;
apps/fulltech_app/test/features/account/settings_notifications_visual_qa_test.dart;
apps/fulltech_app/test/features/ecf/ecf_sales_without_document_section_test.dart;
apps/fulltech_app/test/preview/ecf_design_preview_test.dart;
docs/DESIGN_SYSTEM.md; docs/PRODUCT_SPEC.md; docs/EXECUTION_STATE.md;
docs/ecf/company-design-2026-11-14/empresa-escritorio-compacta.png;
docs/ecf/company-design-2026-11-14/empresa-android.png;
docs/ecf/company-design-2026-11-14/empresa-iphone.png.

New test-only entry point: apps/fulltech_app/test/preview/ecf_design_preview.dart.
Uses AccountCompanySettingsScreen, EcfWelcomeStep and EcfPreparationStep directly,
with synthetic in-memory repositories, simulated auth and an HTTP adapter that
rejects every network request. No deployment .env values are loaded. The UI lets
the owner navigate Empresa/entry, change desktop/Android/iPhone/tablet layout
sizes, test the fiscal switches and reset demo state. Layout simulation is NOT
physical-device QA. External postulation is not opened from the preparation CTA.
The baseline preview is now updated by the company design iteration above.
Welcome and later fiscal screens await the next joint review; the welcome copy
promising "sin salir de FullPOS" despite native external-browser handoff remains
an identified item for that screen, outside this company-only iteration.

Initial preview analysis/four widget tests passed before this design iteration;
current final counts are recorded above. Existing company/portal/assistant
baseline61 tests had passed. Six initial screenshots were rendered before the
company redesign; current design screenshots are listed above.
Local preview includes the startup correction and new company design; current
server session65713 runs on127.0.0.1:4804 with HTTP200 for joint review. Older
sessions15120/25488 were stopped only for local correction/validation.
Do not stop the current preview while the owner reviews it.
Interactive browser rendering is owner review, not an automated browser PASS.
Private logs/screenshots remain under
.codex/backups/fullpos-ecf-selfservice-20261114/design-preview*.
Company UI redesign was explicitly requested and implemented in this iteration.
No backend edit, commit, push, merge or deployment was performed in this design
step. Await owner feedback, then iterate together; do not advance through the
remaining screens without that review.
Production/new deployment stays NO-GO. Previous browser/device QA limits remain.

Preview startup follow-up: owner reported an indefinite loading cover. Root cause
confirmed in source: web/index.html keeps #app-loader until the existing
fullposCompleteWebStartup hook is called, and the new preview omitted that hook.
Preview now calls the shared completeWebStartup helper after its first rendered
frame. Production startup/shell code is unchanged. A new lifecycle regression
checks that completion happens after content exists and only once across
navigation/reset; all5 native preview tests PASS, analysis of all3 preview/test
files PASS. A browser-only regression was added, but its Chrome
runner stalled at loading before executing assertions and was aborted. Browser
access MCP also remains unavailable; no browser functional PASS is claimed.
Only the verified old local preview and owned stalled test process tree were
stopped; no user browser or production service was stopped. Preview recompiled
successfully and serves HTTP200 on the same127.0.0.1:4804 URL. Owner should reload
to receive the fixed entry point; actual browser confirmation remains pending.
Private evidence: design-preview-startup-{analyze,tests,red}.log. The "red" log
contains an interrupted browser startup, NOT an executed RED assertion.

## Previous work — self-service e-CF hardening (2026-11-14)

Owner explicitly authorized local investigation, fixes and full simulated QA for
all-company self-service. New isolated worktree C:/src/fullpos-ecf-selfservice-20261114,
branch agent/ecf-selfservice-hardening-20261114, based on merged PR44/cbc3eceb.
Original dirty workspace and all other worktrees are preserved. No production
access or mutation is needed; FULLTECH's previously verified activation remains.
No deploy/restart/configuration/migration or real invoice is authorized here.
Deployment stays NO-GO pending a new explicit owner authorization.

Confirmed root cause: form authorization expiry is not passed to the operational
range; POS asks for the E31 expiry on checkout and the sale trusts that input.
Plan: use own company/environment authorization as the server source, retain old
contracts/data/counters, remove repeated date entry, prove new-company self-service
and security on a fresh local PostgreSQL database with localhost external mocks.
Implementation derives E31 expiry on server/new ranges, projects it to POS,
validates dates and own authorizations, scopes fiscal providers to session/company
and hides unnecessary TEST numbering before production opt-in. Customer-route
HTTP case completes two synthetic onboarding/certification/production/E31 cycles
with signed localhost-mocked outcomes and separate credentials/dates/QR.
Audit also reproduced revoked/expired auto-enrollment being replaced and a
standalone preparation race between expiry resolution and allocation. Both have
RED-to-GREEN regressions and minimal locking/recheck fixes. Old E31 test fixtures
now include consistent synthetic expiry; no production range/history was rewritten.

Final PASS: API build; strict types for four principal specs; general backend
240 suites/2887 tests (555 opt-in skipped); ECF PostgreSQL160 suites/2054 tests;
atomic/readiness/sequence/environment PostgreSQL4 suites/39 tests; HTTP3 suites/44
tests; Flutter analyze; full Flutter2266 tests (9 skipped before two new scope
regressions); final focused Flutter128 tests including those new regressions;
release web JS build with loopback API target. Static inventories:168 models,
431 endpoints; unsafe query heuristic audit0 errors/298 warnings, reviewed in
changed scope without suppressing warnings. Diff reviewed/check passes.

Six screenshots rendered with real Flutter widgets and AppTheme.light were
generated; mobile/desktop PNGs inspected. Interactive browser QA remains pending:
browser access host unavailable, native CUA blocked on URL confidence, stopped
and completed. Do NOT retry or bypass CUA this turn. Synthetic preview on4803
was stopped. Only two owned task-labelled local PG containers were used on
55500/55501, both verified and stopped (Exited0) at closeout; no allowlist was
relaxed, no production access occurred. Temporary
native DLL contention and a Supertest auto-close race were corrected/revalidated;
final evidence and exact commands are in the report/private logs.

No commit/push/merge/production action occurred. Changes remain on the isolated
branch for review. Browser QA and explicit owner authorization are required before
any new deployment. See docs/ecf/ECF_SELF_SERVICE_HARDENING_2026-11-14.md.

## Previous work — commercial E31/refund/E34 closeout (2026-11-14)

Mode: CONTINUOUS_CONTROLLED_EXECUTION. Owner asked to finish the remaining fiscal
work before a later design phase. Existing user-controlled merge/deploy and
separate production activation gates remain. No live commercial QA data writes.

Fresh worktree C:/src/fullpos-ecf-commercial-closeout-20261114, branch
agent/ecf-commercial-closeout-20261114, starts at merged PR43/38142fce. Other
worktrees, the immutable PR43 source and preparation branch remain untouched.
The owner-deployed PWA d56a9c97 and healthy API4e6fb33c were already verified;
actual accepted TEST E31/E34 PDFs now pass preview, download, fields and QR checks.

Audit found separate HTTP tests for sale/emission/manual E34 and PostgreSQL
tests for financial refunds, but no single HTTP checkout -> financial return ->
E34 acceptance regression. Added three synthetic end-to-end cases to the existing
CI suite: normal response, lost provider response, and missing E34 range followed
by fiscal-only recovery. Initial focused run:3 PASS/26 intentionally filtered.
Each asserts one financial refund/stock return, net cash0, ITBIS18, one E34
allocation/applied credit, unchanged financial state on replay and cross-tenant
denial. All provider traffic is loopback; no real DOSA/DGII calls.

Full API build PASS. Existing regressions PASS:3 HTTP suites/43 tests,
5 PostgreSQL suites/48 tests,240 unit/general suites/2882 tests.52 opt-in suites
and547 tests are intentionally skipped by the general run. An extra strict
TypeScript check found two old fixtures missing encf; explicit empty values
preserve server allocation and the changed suite now typechecks. Final HTTP
revalidation after those two fixture corrections:3 suites/43 PASS. Tests ran
on a fresh owned local postgres:16-alpine container fullpos_ecf_closeout_20261114,
loopback55500, label fullpos.task=ecf-commercial-closeout-20261114. No restored
customer data, shared database or external credential is used.

Fresh tenant-scoped live read-only audit confirms FULLTECH has own ACTIVE keys
for both environments, certification PRODUCTION_READY and no unresolved TEST
results (four reviewed legacy trials remain unchanged). Stored production
authorizations/ranges are E31=1–150/next3, E32=1–1000/next3, E34=1–50/next2.
E31 authorization expires2027-12-31 but all operational range expiries are null;
E32/E34 authorization expiries are null. The two persisted authenticated webhook
summaries contain no numbering metadata. The owner confirmed he registered the
FULLTECH database values and requested using them; preserve those declarations,
not the generic email range. No further numbering information request is pending.
The concrete E31 operational renewal proposal is start/next3,end150,expiry matching
its existing2027-12-31 authorization; preserve E32/E34 and all consumed counters.
Do not invent dates for null declarations. Production changes remain unexecuted.

Local implementation and validation are complete. Publish only the new
test/documentation branch and require green GitHub controls on its final head
before merging; then present the concrete production operation
in docs/ecf/ECF_COMMERCIAL_CLOSEOUT_2026-11-14.md for separate owner authorization.
Global production flags, company production opt-in, migrations and seed stay off.
Production activation requires the separate owner gate; no real invoice is a
smoke test. Private tools/evidence: C:/Users/pc/.codex/backups/
fullpos-ecf-commercial-closeout-20261114/.

## Previous work — deployed TEST acceptance and numbering access (2026-11-14)

The owner deployed both final PR42 images. Read-only inspection confirms API
4e6fb33c and PWA542cc3d8, from3217f0cd; merged ac729b16 has the identical tree.
API is healthy on Node22.23.4. Production fiscal flags, company production
activation, automatic migrations and seed remain off. Owner retains merge/deploy.

Authorized FULLTECH SANDBOX acceptance is successful: E310000000003 and its
total E34 E340000000002 were each dispatched once from the actual PWA and are
DGII_ACCEPTED. Each has a bound HTTP200 receipt, immutable fiscal snapshot and
official TEST QR query showing Aceptado. E34 credit118.00 is APPLIED once.
Drafts use existing services, the real verified operator and MANUAL source,
without a commercial sale. Confirmed TEST authorizations are1–10000000, expiry
2028-12-31; operational starts preserve historical frontiers E31=3/E34=2.

Whole-row fingerprints/counts for FULLTECH sales, cash sessions/movements and
inventory movements match the pretrial checkpoint. Five legacy document row
fingerprints, production ranges/counters and production authorization
fingerprint also match. No historical promotion, production issuance, new
migration, restart or deployment was performed by the agent.

New live finding: completed onboarding hides its numbering form as soon as E31
makes POS ready; configuration had only a read-only range overview. Minimal
fix reuses EcfSequenceRangeSection in configuration for enabled companies with
manageEcfSequences, keyed by company/user/environment to cancel stale forms.
Fresh isolated branch agent/ecf-numbering-access-20261114 at
C:/src/fullpos-ecf-numbering-access-20261114 is based on merged ac729b16.
The merged PR42/release preparation branches and unrelated worktrees are intact.

Six new widget regressions pass; full Flutter analysis passes;661 tests pass
in e-CF/printing plus a temporary read-only print projection probe (removed).
390/1280 widget screenshots inspected. Web release compilation passes;
publication/CI is pending. No backend/schema/dependency change.

E31 PDF opens/downloads from the deployed PWA. Both actual TEST backend print
projections generate valid A4 and58/80mm representations with matching decoded
QR and fiscal fields. Physical hardware was not exercised. E34 deployed preview
could not be completed because the browser moved to the public site on two
attempts; cause unconfirmed. User asked to leave the PWA on fiscal documents.
Do not claim that preview passed or repeat an accepted fiscal send.

Private receipts/helpers/rendered evidence are under
C:/Users/pc/.codex/backups/fullpos-ecf-test-close-20261114/.
See docs/ecf/ECF_LIVE_TEST_ACCEPTANCE_2026-11-14.md. Next:
review/publish the small UI fix, verify CI and close deployed E34 preview if the
user leaves the PWA available. Production emission remains NO-GO pending the
separate operator readiness/activation gate; do not change global permissions.

## Previous work — SANDBOX checkout and PDF closure (2026-11-14)

Mode: CONTINUOUS_CONTROLLED_EXECUTION. The owner approved completing TEST
numbering, verified DOSA outcomes, E31/E34 trials from the software where possible,
Normal-sale regression and the blank web PDF preview. Production emission remains
blocked; the owner retains merge and deployment. No production flag, credential,
historical fiscal status or production range may be changed by this task.

Isolated worktree C:/src/fullpos-ecf-test-close-20261114, branch
agent/ecf-test-close-20261114, based on deployed merge8fa5eba6. Other worktrees
contain unrelated edits and are untouched. Local synthetic PostgreSQL is
fullpos_ecf_test_close_20261114, loopback port55503; never use a restored live DB.

Audit: FULLTECH has its own active TEST credential and SANDBOX configuration,
but no SANDBOX authorization/range. Legacy reviewed TEST numbers stay consumed
(E31 frontier3, E34 frontier2). DOSA's accepted historical E31/E34 remain visible
in official TEST queries; their internal review state is not rewritten. Web PDF
download has valid fiscal fields/QR; the Syncfusion web renderer lacks PDF.js.

Plan: retain all identity/receipt/fingerprint/QR checks; authorize confirmed
outcomes only for valid SANDBOX dispatches without opening production gates;
restore the documented web renderer; validate real local HTTP/database chains,
tenant boundaries, connectivity, Normal intent and printing before publication.
Shared TEST setup/issuance is restricted to FULLTECH and confirmed provider
metadata. New code is not deployed by this checkpoint.

Implementation: confirmed outcomes are now environment-gated, with all receipt
checks retained. Completed onboarding uses real POS readiness and preserves
numbering and the existing company activation. Range saves retain the original
authorization and cancel the second write after an unmount/environment change.
Local PDF.js/worker and bounded bootstrap restore the web renderer; failed
previews retain download actions. No schema, credentials or production flags
changed.

Validation: API build/schema PASS;3328 backend tests PASS/101 gated skips,
26 real-local-HTTP scenarios PASS,53 PostgreSQL fiscal regressions PASS,8 new
outcome-gate tests PASS. Final Flutter analysis/web build PASS,828 broad tests
PASS,71 final context/numbering/activation tests PASS. Local browser PDF
engine1280/390 and Nginx config PASS. Runtime npm audit reports0;11 full-tree
development advisories remain outside runtime. Final diff reviewed; publication,
CI and owner-controlled deployment remain before live FULLTECH TEST acceptance.
Evidence: docs/ecf/ECF_TEST_CLOSURE_2026-11-14.md.

Publication checkpoint: PR42, sourcea1885097, passed all four GitHub gates
(43605208442):2247 Flutter tests PASS/16 gated skips, backend/security,
public website and Windows updater PASS. The final runtime review then found
the proxy-generated Nginx template lacked the PDF module rule. That template
is now corrected as well; local before/after HTTP proved octet-stream/HTML200
becomes JavaScript/versioned cache/404. Combined-image smoke now covers these
assets. Sourcea188 images are superseded and must not be deployed; the final
commit needs its own CI and immutable images. No deployment occurred.

## Previous correction — PR41 critical findings (2026-11-13)

Explicit E31/E32 checkout now shares admission with POS capabilities and commits
sale, stock, number allocation and local fiscal preparation atomically. Ordinary
ITBIS printing no longer triggers electronic queries; historical electronic
links use an additive tenant-scoped read flag. API Docker/CI pin Node22.23.4 LTS.
No schema, production configuration, deployment or external emission change.

Local validation:3320 backend tests,1119 broad Flutter tests,13 dedicated real
PostgreSQL regressions,63 tests inside the Node22 Linux image; API build, Prisma
validate, Flutter analyze/web build,30 HTTP tests and runtime dependency audit
passed. Publication and
the final CI result must be checked on the corrected PR HEAD. Details:
[critical findings correction](ecf/ECF_PR41_CRITICAL_FIXES_2026-11-13.md).

## Previous checkpoint — audited manual ECF migration and release candidate (2026-11-13)

HECHO: the explicitly authorized production migrations0400/0500/0600 were
applied manually, rehearsed against a restored backup, and recorded with their
original checksums. All223 previous migration rows remain; the ledger has226.
Five reviewed FULLTECH engineering trials are Sandbox; none is unclassified.
Their fiscal status, identity and original sequence counters were preserved.
The API container/image, disabled automatic migrations and company configuration
were unchanged. No application deployment, restart or external fiscal send.

The candidate lives at C:/src/fullpos-ecf-predeploy-20261113 on
agent/ecf-predeploy-20261113, based on current production-main cada11f8.
Only the prior working-tree delta was ported; the old branch's divergent commits
were not merged. The original218 files, Git history bundle, database backups and
running API/PWA images are retained with verified hashes outside the repository.

Audit fixes close reviewed terminal TEST trials without granting fiscal
acceptance, block unclassified documents on activation, and enforce the original
TEST numbering frontier. Compatible API dependency patches and the explicitly
approved Astro7.4.12 update are included. Docker uses the generated API lock
from the authoritative root lock; the website stage pins Node22.23.4.

Validation: API build;3300 broad tests;30 HTTP tests;48 PostgreSQL tests;
Flutter analyze;1117 broad Flutter tests;14 visual widget checks; Flutter web
validation build; Linux API, Astro and complete combined Docker builds passed.
The combined image passed17 read-only routes/6 assets/PWA/portal checks.
Astro browser QA passed8 desktop/mobile views with0 page errors. Both Linux runtime audits
reported zero advisories. No hardware or deployed-client acceptance is claimed.

The owner authorized commits, branch publication and a PR. Implementation commit
50617f39a7d744d2a528c30fa51b33e8d11b131e is published in
[PR41](https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/41), targeting
production-main. GitHub confirmed no merge conflicts. The owner retains merge
and Deploy; neither was executed by the agent. CI must pass before integration.
Both server production gates remain disabled. autoDeploy=false on API and PWA.
The public DOSA assistant key is already configured; it was not printed/changed.
Full evidence, current file inventory and manual deployment sequence:
[predeployment audit](ecf/ECF_PREDEPLOY_AUDIT_2026-11-13.md).
The 246-file inventory is the implementation checkpoint at50617f39; subsequent
publication documentation is identified separately in the
[operator guide](ecf/ECF_RELEASE_OPERATOR_2026-11-13.md).

## Previous local closure — Normal sales and DOSA recovery (historical)


Checkout finalesdaleventas, branch agent/ecf-offline-history-20261113.
Normal is explicit, internal and the default for every new ticket when allowed.
No e-NCF/expiry, fiscal preparation, sequence consumption or DOSA/DGII dispatch
is possible for that intent. Ordinary ITBIS and existing offline permissions remain.
Ticket drafts retain their own manual fiscal selection without changing the next
ticket's default. Ordinary ticket/PDF bypass the electronic projection.

Added persisted hash/lease recovery after interruption/restart, serialized queries
and stale-worker fencing; validated RFCE E32 no-TrackId receipt references;
HTTP202 contingency printing with pending status and provider legend; explicit
per-company production activation/commercial preparation with certification,
own credentials, server gates and unresolved-TEST guards. The existing assistant
is retained. None of these source changes enables a deployed environment.

Final API build and Prisma validation PASS. Full non-e2e:275 suites /3,293 tests
PASS,101 opt-in tests skipped. PostgreSQL replay/returns:22 PASS. HTTP:26 PASS
against localhost; forceExit remains a documented test-harness limitation.
Flutter final analysis: no issues. Broad regression:1,041 PASS; focused:115 PASS;
last UI recovery/POS checks:11 PASS. Final company-context guards:39 API /52 Flutter PASS;
API build and analysis rerun after those changes. Widget screenshots were visually inspected
at320/1280; the POS screenshot shows Normal on the new ticket. No new hardware
or browser-device acceptance is claimed.

All32 isolated API files match the checkout byte-for-byte. The owned disposable
PostgreSQL was identity-checked and stopped, retaining data. No production access,
external fiscal send, commit/push/deploy, credential edit or shared migration.

Production remains NO-GO pending reviewed shared rollout of prior fiscal
migrations/classification, coordinated API/client and verified runtime activation.
Old documents without replay proof and late fiscal returns still require review.
Current report and exact52-file inventory:
docs/ecf/ECF_NORMAL_PRODUCTION_RECOVERY_2026-11-13.md.

## Previous checkpoint — connection, sales history and E34 (historical)

Checkout finalesdaleventas, branch agent/ecf-offline-history-20261113.
The authorized implementation is locally complete and validated; nothing was
committed, pushed, deployed, migrated on a shared database or sent to DOSA/DGII.
Earlier dirty fiscal work is preserved. The existing DOSA assistant and printer
transports are unchanged.

Implemented: real HTTP connection checks without offline cache; four-second
upper-right notices; E31/E32 intent and frozen E31 expiry persisted before fiscal
preparation; bounded company/owner history projection with reserved e-NCF and
original/E34 states; fiscal-only recovery without another financial refund;
partial/remnant quantity correction; original-bound refund idempotency; ordinary
electronic cancellation blocked; electronic print/PDF guards; stable unresolved
manual E34 request identity. No schema change or new dependency in this task.

Final API: build and Prisma validation PASS; 275 suites / 3,289 tests PASS,
101 opt-in tests skipped. PostgreSQL returns 15 PASS. Local HTTP 25 PASS with
forceExit: the two HTTP suites leave the runner alive without it, including under
detectOpenHandles; this harness limitation remains documented.
Flutter analyze PASS after the last source edit; directed regression 99 PASS,
final repository/print guard 32 PASS. Broad regression 1,145 PASS / 3 SKIP /
1 failed source-text assertion; ordinary confirmation text restored and the failed
suite passed in the final directed regression. Actual widget screenshots at320/1280
and existing synthetic fiscal print images were visually inspected. No new paper
or browser-device acceptance is claimed.

The owned disposable PostgreSQL fullpos_ecf_finish_20261112 was identity-checked
and stopped, retaining its database. No unrelated process was stopped. Isolated
API sources matched all14 current API files byte-for-byte.

The pending implementation list at this checkpoint was superseded by the current
closure above. Shared fiscal rollout and late-return tax review remain pending.

Report and exact file inventory:
docs/ecf/ECF_OFFLINE_HISTORY_E34_2026-11-13.md.

Historical entries below are not authorization for this task.

## Completed — Installed144 startup regression / reference141 review

Worktree C:/src/fullpos-144-fix, agent/release144-regression-audit.
Owner reference:1.0.6-141 from original installer/output. Exact SHA8CB439B0...
matched retained141 build and selectively extracted runner/AOT. Login Widget
build matches candidate after ignoring whitespace/trailing commas only.
Installed runner/AOT match144. No proof of an accidentally published old binary.
Confirmed packaging regression:144 updater uses ProgramFiles/updates; installer
does not provision it. Installed logs show PathAccessException after silent check.
Fix8dd67542 provisions updates with users-modify, preserves it on uninstall,
leaves binary ACLs and all app logic untouched. Candidate145 compiled PASS;
40258303 bytes, SHA FA66972E49B6E99BEE80BDA7E906ECB2C044E158E174FC7A8FFD2C6113F4201E.
Before-fix contract FAIL; after-fix67 storage/updater tests PASS/1 skipped,
flutter analyze clean; local Inno packaging check PASS. Standard-user install
145 passed: installed runtime hash matched candidate, `updates` ACL allowed a
non-admin write, updater saved UP_TO_DATE without PathAccessException, and the
app restored the existing Facturacion session. Owner authorized unsigned
publication only after acceptance; release145 is now published as
ff5a78cc-0f1b-4535-8bec-ec19404a0539 with retention dry-run. Public check maps
144 to145 and145 to current; stable download is302/no-store then200, PE header,
40,258,303 bytes and approved SHA. Releases142/144 remain published with their
objects present. No API/PWA redeploy or migration was required. Login screen
was not visually inspected because the existing session restored directly to
Facturacion; source comparison shows login widget in141 and145 unchanged.
Review:docs/RELEASE144_REGRESSION_REVIEW.md. Earlier deployment history follows;
it is not the current verdict.

## Active task — Offline48h + Mayoreo production integration

Worktree C:/src/fullpos-offline-prod; branch agent/offline-mayoreo-integration-20261018.
Owner authorizes combining the offline worktree, production-main integration,
deployment and a new Windows installer. Continuous controlled execution.
Production now API/PWA144 and Windows144 published; Windows142 preserved.
Source snapshot 8c19bbac; merge 1c2c7a61 preserves production base 2f33df45.
Seven conflicts resolved preserving Mayoreo and offline identity/storage behavior.
SQLite3.52.0 was officially withdrawn; candidate uses sqlite3 Dart3.3.2 / SQLite3.53.1.
API build and766 tests PASS; Flutter analyze PASS; first full suite1368 PASS/6 skips.
Real dedicated clone fullpos_offline_mayoreo144_uat on localhost56549, API46554.
Both additive migrations rehearsed. HTTP concurrent product/stock/sale retries PASS.
Combined Flutter SQLite/reopen/real HTTP wholesale sale test PASS. Sync handler
now preserves manual price-list and source-quotation fields; final regression pending.
Final regression1369 Flutter/766 API PASS, analysis PASS; immutable144 artifacts
built and verified. Owner explicitly authorizes both production migrations and
unsigned Windows144 publication (SHA8F645A04...), followed by repeated continua.
Both authorized production migrations applied; Swarm API/PWA completed,
health ok, protected endpoints401, runtime errors0, config/mounts/ports preserved.
Windows144 published1efef881-4c3f-4dd4-8794-fd64058a8660, retention dry-run,
Windows142 remains published with artifact intact. Final public verification
PASS:142->144,144 up-to-date, full external download exact SHA/size/MZ and
stable download302/no-store. GO for agreed deployment/publication scope.
Full record: docs/OFFLINE_MAYOREO_PRODUCTION_INTEGRATION.md.
Historical task state below is not the current target or authorization.

## Active task — Offline Safe48H Phase17 (2026-10-14)

Worktree `C:\src\fullpos-offline-safe-48h`, branch `feature/offline-safe-48h`.
Scope: Windows candidate and historical installer/updater acceptance, UAT only.
Production/push/merge/deploy/customer updates remain prohibited. The state below
is historical evidence from another worktree, not authorization or the active
environment. Current API46548/clone46552, PostgreSQL56548; manual SQLite preserved.
Phase16 source manifest:24/24 hashes matched before starting;1135 source files
hashed in `.uat/evidence/phase17-baseline.json`; consistent manual backup created.
Hyper-V inventory still permission-blocked; no bypass. No code-signing certificate.
Cached-policy/build/disabled-update handoff guards fixed and tested. New native
helper binds target to PE ProductVersion and locks/revalidates final package.
Final local UAT candidate17002 packaged/hashed;3 interrupted replacements preserve
open DB/WAL/SHM and8 fixture pending actions;9 native and6 real HTTPS tests PASS.
Flutter1335 PASS/5 skipped;Jest752 PASS/8 skipped;analyze/API build/Prisma PASS.
Candidate opened in `.uat/phase17-visual`, title[UAT], cloneAPI46552; owner confirms
POS visible without startup error and Updates shows no pending update/no error.
Candidate left open; no further manual screen repetition requested. No historical GUI, elevated signed chain or physical
hardware result asserted. Next external steps: authorized Windows isolation and
safe historical API routing, signed positive updater UAT, then explicit pilot
approval. Motor GO within proven UAT; integral acceptance/pilot/publication NO-GO.
Final decisions belong in
`docs/offline-safe-48h-phase-17-final-windows-acceptance-2026-10-14.md`.

---

Last updated: 2026-10-07 12:35 local.

## Objective

Implement safe Windows release retention automation for FullPOS Cloud:
prepare/publish separation plus Windows/STABLE current+previous artifact
retention.

## Mode

`CONTINUOUS_CONTROLLED_EXECUTION`

## Environment

- Repository worktree: `C:\src\fullpos-update`
- Branch: `agent/windows-autoupdate-phase6b-build`
- Production authorization: not granted
- Production deployment: blocked
- Production Authenticode certificate: not available
- UAT unsigned update exception: enabled only for local UAT
- UAT API: `http://127.0.0.1:4000`
- UAT DB: `127.0.0.1:55432/daleventa_uat_local`
- UAT HTTPS artifact storage: `https://localhost:9443`
- Windows release retention target: keep current + previous, archive older
  Windows/STABLE artifacts only after publish verification.

## Final Builds

- Installed build N: `1.0.6+130`
- Installed update build N+1: `1.0.6+131`
- Final N+1 UAT installer SHA-256 used in the successful upgrade:
  `265EFDAB1A2CF27EE4E51DC8839B954AF5A1CDCCBBAA9B643737976613685D61`
- Final N+1 UAT installer size: `40167704`
- Authenticode status: unsigned, accepted only by the explicit local UAT policy.

## Completed

- Audited current AppRelease API and confirmed existing statuses were
  `DRAFT`, `PUBLISHED`, `REVOKED`; `REVOKED` is not reused for retention.
- Added AppRelease retention metadata:
  - `ARCHIVED` status.
  - exact `storageKey`.
  - `storageDeletedAt`.
- Implemented Windows/STABLE retention after publish:
  - keeps newest published build.
  - keeps immediate previous published build.
  - skips DRAFT, other platform, other channel, current, previous, unsafe keys,
    and missing keys.
  - deletes only an exact `storageKey` through the release storage adapter.
  - uses R2 by default and local exact-file deletion only for explicit local UAT.
  - marks deleted historical rows `ARCHIVED` and preserves DB history.
  - reports partial cleanup without reverting a successful publish.
- Added admin retention dry-run endpoint:
  `POST /api/app-updates/releases/retention/windows-stable`.
- Updated public update check to ignore releases whose artifact has been
  removed.
- Created release scripts:
  - `scripts/release/prepare_windows_release.ps1`
  - `scripts/release/publish_windows_release.ps1`
- Added surgical `.gitignore` exceptions so the release scripts are tracked
  without unignoring release artifact output directories.
- Updated `docs/WINDOWS_RELEASE_PROCESS.md` with prepare/publish/retention
  workflow.
- Resolved local Prisma `EPERM` by stopping the repo-local backend dev process
  that held the Prisma Windows query engine DLL.
- Applied migration `20261007130000_app_release_retention` to local UAT only
  after verifying DB identity and creating a logical UAT backup.
- Executed real local-UAT retention rotation:
  - `131/132 -> publish 133`: kept `133` and `132`, archived `131`, physically
    deleted artifact `131`, and update checks for builds `130`, `131`, `132`
    offered `133`; build `133` was up to date.
  - `132/133 -> publish 134`: kept `134` and `133`, archived `132`, physically
    deleted artifact `132`, and update checks for builds `132`, `133` offered
    `134`; build `134` was up to date.
- Verified controlled retention failure behavior in local UAT:
  - storage delete failure reports `PARTIAL`;
  - newly published current and previous remain `PUBLISHED`;
  - publish failure does not run cleanup;
  - DRAFT, other channels/platforms, and shared storage keys are preserved.

- Verified elevated agent privileges: `IsAdministrator=True`.
- Verified local UAT API, DB, and HTTPS storage.
- Built and installed build `1.0.6+130`.
- Published UAT AppRelease for build `1.0.6+131`.
- Verified update check returned build `131`.
- Verified silent download, size validation, SHA-256 validation, and `READY_TO_INSTALL`.
- Verified dismiss persistence: `dismissedBuild=131` persisted and did not delete the prepared package.
- Verified menu access from the real Windows topbar company menu: `Actualizaciones` is visible and navigates to the update screen.
- Verified UAC cancel path:
  - `installer_result.json` wrote `UAC_CANCELLED`.
  - exit code was `1223` (`ERROR_CANCELLED`).
  - installed build remained `1.0.6+130`.
  - package remained ready.
  - state returned to `READY_TO_INSTALL`.
  - no updater loop remained.
- Verified and corrected installer handoff bugs found during UAT:
  - local UAT official build URL validation needed an explicit localhost UAT exception.
  - same-build ready artifacts must not be cleared by a re-check.
  - Windows account menu needed an `Actualizaciones` entry in the real POS topbar.
  - native updater must materialize `.exe.ready` to `.exe` before invoking UAC.
  - Flutter must stage `FullposUpdater.exe` outside `Program Files` before launching so Inno can replace the installed updater.
- Verified upgrade path:
  - Inno installer exited `0`.
  - updater log recorded `INSTALLER_SUCCESS`.
  - app relaunched.
  - Windows registry reports `FullPOS 1.0.6 (build 131)`.
  - update state reconciled to `IDLE` / `UP_TO_DATE`.
  - prepared build directory was cleaned.
- Verified data preservation:
  - same cash session remained `OPEN`.
  - same business date remained `2026-10-07`.
  - company/user/product fixture remained scoped to the UAT tenant.
  - local app DB files remained present.
- Executed post-update UAT sale:
  - sale id `5815a377-8c0a-4d46-b59e-cd5761ac020b`.
  - product stock moved from `19` to `18`.
  - warehouse stock moved from `19` to `18`.
- Verified financial regression after update:
  - sales count moved from `3` to `4`.
  - net total sold moved from `100` to `150`.
  - total cost moved from `40` to `60`.
  - total profit moved from `60` to `90`.
  - commission total moved from `12` to `15`.

## Validation

- `npx prisma validate` with dummy local-safe `DATABASE_URL`: PASS.
- `npx prisma generate`: PASS after stopping the repo-local backend dev process
  that held the Prisma engine DLL.
- `npm run api:build`: PASS after Prisma DLL lock was released.
- `npm --workspace apps/api test -- app-updates`: PASS.
- `npm --workspace apps/api exec -- tsc -p tsconfig.build.json`: PASS.
- PowerShell parser validation for release scripts: PASS.
- `git check-ignore` for release scripts: PASS; scripts are no longer ignored.
- `prisma migrate deploy` against local UAT: PASS.
- `prisma migrate status` against local UAT: PASS.
- Real local-UAT retention rotation and failure scenarios: PASS.
- `flutter analyze`: PASS.
- Focused Flutter regression:
  `flutter test test\core\app_update\app_update_controller_test.dart test\core\config\product_config_test.dart test\modules\cotizaciones\company_account_menu_navigation_test.dart`: PASS.
- `npx prisma validate` with local UAT `DATABASE_URL`: PASS.
- Physical Windows UAT N -> N+1: PASS in local UAT with unsigned exception.

## Findings

- Production remains blocked because a production Authenticode certificate is not available.
- No production deployment, production database, customer data, or bridge changes were performed.
- The successful UAT used local-only unsigned policy; production must require trusted signing.
- Retention is code/test validated and real local-UAT rotation was executed
  against an isolated local storage root. Production storage was not touched.

## Next Action

Sign production Windows artifacts and execute signed final release UAT before
production rollout. Production remains NO-GO until signing and owner approval
exist.

## Status

READY_FOR_WINDOWS_RELEASE_AUTOMATION. Production NO-GO until Authenticode
certificate and explicit production approval exist.

## Portada fiscal con datos — ajuste local 2026-11-15

- En `agent/fiscal-home-logout-20261115`, worktree aislado
  `C:/src/fullpos-fiscal-home-logout-20261115`.
- Empresa lista: resumen de tipos y rangos del backend; empresas pendientes
  conservan el asistente. Ventas sin comprobante solo en Empresa, sin cambiar
  su comportamiento. Se mantienen correcciones locales de appbar y salida web.
- Análisis PASS; 546 pruebas PASS; build web UAT PASS. Informe e inventario:
  `docs/AUDITORIA_PORTADA_FISCAL_SALIDA_20261115.md`.
- El 2026-11-16 el usuario pidió preparar el proceso de publicación. Se prepara
  commit/PR y se verifican sus controles; no hacer merge automáticamente.
  Sin despliegue ni cambios productivos durante la preparación.
