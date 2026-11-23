# Acceso local seguro — implementación local

Base: production-main `61d5d5aa`. Rama y worktree exclusivos:
`agent/acceso-local-seguro-20261122`, `C:/t/fp-offline-login-20261122`.

## Alcance autorizado y aceptación

Windows, Android e iOS instalados. La PWA conserva autenticación online.
Correo y contraseña existentes, sin guardar la contraseña legible. Preparación
solo tras autenticación online correcta y permiso offline vigente. El acceso
local requiere identidad de usuario/empresa/equipo/servidor coincidente y un
plazo máximo de 48 horas desde la validación, sin extenderlo durante una caída.
No se añade capacidad fiscal, permiso, licencia ni autoridad de emisión offline.

Fases internas: auditoría y diseño → implementación mínima → análisis, pruebas
de aislamiento y recuperación → revisión funcional/visual → informe. El usuario
autorizó implementar y verificar todo el alcance, sin publicar ni desplegar.

## Diseño y barreras

- Verificador PBKDF2-HMAC-SHA256 (600000 iteraciones, sal aleatoria) mediante
  biblioteca, almacenado exclusivamente en almacenamiento seguro del sistema.
- Perfil ligado a empresa, usuario, dispositivo y URL del servicio. No se copian
  perfiles a SharedPreferences; no hay fallback inseguro si falla el almacén.
- Solo fallos de transporte o indisponibilidad temporal habilitan la comprobación
  local. Un rechazo de contraseña, permisos, licencia o certificado TLS no permite
  ese fallback y revoca el perfil local correspondiente cuando sea autoritativo.
- Cambiar de identidad no reutiliza datos, permisos ni colas de la anterior.
  No se borran ventas ni operaciones pendientes al bloquear o cerrar sesión.
- Un fallo de red durante login no borra la sesión anterior. La identidad nueva
  se confirma antes de sustituirla. Cerrar sesión explícitamente retira el acceso
  local; bloquear el equipo permite desbloquear con la misma contraseña.
- Los avisos del login describen el acceso real, sin prometer ventas durante 48
  horas cuando falta sesión/autorización.

## Validación pendiente

Primer acceso; éxito online y posterior acceso offline; contraseña errónea;
caducidad; retroceso del reloj; fallo del almacén; dispositivo distinto;
empresas distintas; usuarios distintos; credenciales rechazadas online;
concurrencia; cierre/bloqueo; recuperación del servicio; regresión de sesión,
rutas y permiso offline. Separar dobles de HTTP, HTTP real local y pruebas nativas.

Estado inicial: NO-GO, implementación y validaciones pendientes. Producción intacta.

## Avance verificado

Implementación en el cliente únicamente. Se conserva la sesión anterior hasta
confirmar el nuevo usuario y se limita la petición candidata a `/users/me`.
Las respuestas 401/403 retiran el perfil de ese correo; un error TLS no permite
fallback local. El perfil valida también las identidades del JWT guardado, el
reloj, el bloqueo conocido del usuario y el permiso offline existente.

El verificador y los tokens del perfil solo viven en almacenamiento seguro. En
SharedPreferences se guarda únicamente una marca no secreta de revocación, para
que un fallo al borrar la credencial nativa no vuelva a habilitarla. Actualizar
tokens no renueva el plazo de la contraseña; observar otro rol, permisos,
empresa o correo retira el perfil anterior. El cierre explícito retira el acceso
local; el bloqueo conserva el perfil y limpia la identidad activa, sin borrar
datos comerciales ni colas.

Las primeras 31 pruebas focalizadas y las 139 de autenticación/aviso/permiso
offline aprobaron. Ocho recorridos adicionales usaron HTTP real en loopback y
repositorios de credenciales en memoria. La regresión completa está en curso.
El análisis estático llegó a PASS; deberá repetirse sobre el diff final.

La APK Android debug compiló. El caso nativo con HTTP loopback, PBKDF2 real y
almacenamiento cifrado alcanzó PASS, pero `flutter test -d emulator-5556 --no-dds`
terminó con error del ejecutor: `streamListen: invalid 'streamId' parameter:
integration_test.VmServiceProxyGoldenFileComparator`. Los intentos anteriores
agotaron la espera de conexión o fallaron al iniciar DDS. No se presenta ese
comando como aprobado. Se comprobará el mismo caso con el driver oficial existente
`test_driver/integration_test.dart`, sin eliminar ninguna aserción.

Se creó el AVD exclusivo `FullPOS_OfflineAuth_QA_20261122` (emulator-5556). El primer
intento instaló una APK UAT separada en 5554; los siguientes se aislaron en el
AVD nuevo. No se reemplazó el paquete original ni se borraron sus datos.

Las tres variantes de aviso de login (Windows, Android e iOS) aprobaron sin
overflow y generaron capturas de widgets en
`C:/Users/pc/Documents/FullPOS-Acceso-Local-20261122`. El aviso se inspeccionó
visualmente. Algunos botones no afectados conservan la fuente de pruebas en esas
capturas; no se presentan como capturas de una app nativa completa.

## Límites de la entrega

- Cada equipo necesita un acceso online con contraseña después de actualizarse
  y completar la autorización offline. No se puede reconstruir un verificador
  desde una contraseña antigua que nunca se almacenó.
- Preparar el perfil es una tarea posterior al login online y puede fallar sin
  impedir ese login. Sin perfil preparado se exige conexión; nunca se inventa
  autorización local. Se conserva el registro diagnóstico sin contraseñas.
- La revocación remota no puede conocerse instantáneamente durante una caída;
  el permiso y la verificación quedan acotados por el plazo local existente.
- No se alteraron reglas fiscales, licencias, sincronización de ventas, Prisma,
  base de producción ni configuración del servidor.
- iPhone nativo no puede ejecutarse desde este entorno Windows. La variante iOS
  de widget no sustituye una prueba de Keychain en un iPhone.
- No hay commits, push, merge ni despliegue de esta entrega.

Referencias técnicas: [almacenamiento de contraseñas OWASP](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html),
[PBKDF2 de cryptography](https://pub.dev/documentation/cryptography/2.9.0/cryptography/Pbkdf2-class.html),
[driver oficial de integración Flutter](https://docs.flutter.dev/testing/integration-tests).

## Regresión completa y desbloqueo del ejecutor

`flutter test --no-pub --reporter expanded`: 2858 PASS, 10 omisiones explícitas,
sin fallos (16 min 51 s). Este recorrido se ejecutó durante la implementación;
los últimos ajustes se validan adicionalmente con la batería focalizada final.
Las omisiones no son pruebas del nuevo acceso local.

Se reutilizó el driver oficial ya existente, sin cambiar el SDK ni quitar
aserciones:

```text
flutter drive --no-pub --driver=test_driver/integration_test.dart
  --target=integration_test/offline_login_native_test.dart
  -d emulator-5556 --no-dds
  --dart-define=FULLPOS_UAT_PROFILE=true
  --dart-define=FULLPOS_UAT_BUILD=true
  --dart-define=FULLPOS_UAT_LABEL=ACCESO_LOCAL
  --dart-define=API_BASE_URL=http://127.0.0.1:4000
```

Resultado: PASS limpio, `All tests passed`, caso nativo en 11 s tras compilar.
Se probaron autenticación online contra API HTTP loopback, preparación real del
perfil, almacenamiento cifrado Android, verificador PBKDF2 real, recreación del
repositorio, acceso durante HTTP 503, contraseña incorrecta sin destruir la sesión
anterior y retiro explícito de la autorización. La API es una simulación local;
no se presentan la autenticación ni la base productiva como pruebas externas.

La comprobación Windows con el mismo driver terminó en PASS, `All tests passed`,
caso nativo en 9 s. Se usó el selector existente de CMake mediante la variable
del proceso `FULLPOS_WINDOWS_CHANNEL=uat-mayoreo`; no se modificó la configuración
de compilación del proyecto. El fixture conserva y restaura cualquier identidad
UAT previa; las claves productivas no se borran. El ejecutor imprimió la advertencia
del colector de integration_test en Windows y recibió el resultado aprobado.

## Cierre de validación local

- `flutter analyze --no-pub`: PASS, sin incidencias (11,2 s).
- `flutter test --no-pub test/core/auth test/features/auth test/core/offline/offline_emergency_policy_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:4000 --reporter expanded`:
  151 PASS sobre el código final.
- Regresión completa durante la implementación: 2858 PASS, 10 omisiones explícitas;
  los refinamientos posteriores quedaron cubiertos por la batería final anterior.
- Drivers nativos Windows y Android: PASS, almacenamiento cifrado real y HTTP
  local simulado. No equivalen a probar una caída del servidor productivo.
- Avisos y diálogo: variantes de widgets Windows/Android/iOS y tamaños
  320/390/1280; capturas del aviso inspeccionadas, con las limitaciones indicadas.
- `git diff --check`: PASS. Sin cambios en backend, Prisma ni proyectos nativos
  Android/iOS. Restaurados solamente los registrantes y PNG generados por estas
  pruebas que estaban limpios al crear este worktree.

Logs conservados fuera de Git en
`C:/Users/pc/.codex/backups/fullpos-offline-login-20261122`.

### Inventario de la entrega (20 archivos)

```text
apps/fulltech_app/lib/core/auth/auth_interceptor.dart
apps/fulltech_app/lib/core/auth/auth_provider.dart
apps/fulltech_app/lib/core/auth/auth_repository.dart
apps/fulltech_app/lib/core/auth/offline_login.dart
apps/fulltech_app/lib/core/offline/offline_emergency_policy.dart
apps/fulltech_app/lib/core/widgets/app_drawer.dart
apps/fulltech_app/lib/features/auth/presentation/login_screen.dart
apps/fulltech_app/lib/features/auth/presentation/session_exit_dialog.dart
apps/fulltech_app/pubspec.yaml
apps/fulltech_app/pubspec.lock
apps/fulltech_app/test/core/auth/auth_repository_login_test.dart
apps/fulltech_app/test/core/auth/offline_login_test.dart
apps/fulltech_app/test/core/auth/offline_login_http_test.dart
apps/fulltech_app/test/core/auth/offline_login_grant_rejection_test.dart
apps/fulltech_app/test/features/auth/login_offline_notice_test.dart
apps/fulltech_app/test/features/auth/session_exit_dialog_test.dart
apps/fulltech_app/integration_test/offline_login_native_test.dart
apps/fulltech_app/integration_test/offline_login_restart_native_test.dart
docs/EXECUTION_STATE.md
docs/OFFLINE_LOGIN_SEGURO_20261122.md
```

No se generó instalador oficial ni se publicó una actualización. El cliente
necesitará actualizarse y completar un login online con autorización válida antes
del primer acceso local. No hace falta desplegar backend ni ejecutar migraciones
para esta entrega. La PWA queda fuera del nuevo acceso local autorizado.

Estado final: implementación local validada en Windows y Android; pendiente
validación nativa de Keychain/iPhone. **NO-GO para publicación general** hasta
completar esa comprobación y recibir autorización de publicación. Sin commits,
push, merge, despliegue ni modificaciones productivas.

## Revisión profunda adicional — Android y Windows

La revisión solicitada después del cierre anterior detectó un defecto reproducible:
si la respuesta nueva de autorización era HTTP 200 con `authorized: false`,
`recordAuthorizationResponse` descartaba esa respuesta pero no comunicaba el
rechazo. La preparación de contraseña continuaba y podía usar una autorización
anterior aún válida de la misma identidad. Una prueba aislada externa al repo
falló antes de la corrección al encontrar un perfil creado indebidamente.

Corrección mínima: la función existente de registro ahora devuelve `bool` y
la preparación solo continúa cuando esa respuesta concreta es aceptada.
Los demás consumidores siguen esperando la misma escritura y pueden ignorar
el resultado; revisados todos los llamadores. No se cambió la estructura del
permiso, sus reglas de vigencia ni las operaciones autorizadas.

Nueve regresiones permanentes cubren denegación, otra empresa/usuario/dispositivo,
política desconocida, fecha ausente, fecha inválida, fechas invertidas y vigencia
excesiva. Todas parten de un permiso anterior válido y comprueban que no se
deriva ni guarda una contraseña nueva, conservando el acceso online correcto.

Validación sobre la corrección final:

```text
flutter analyze --no-pub
PASS: sin incidencias (17,2 s).

flutter test --no-pub test/core/auth test/features/auth test/core/offline
  --dart-define=API_BASE_URL=http://127.0.0.1:4000 --reporter expanded
PASS: 349 pruebas, 3 omisiones explícitas (2 min 28 s).

flutter test --no-pub C:/Users/pc/AppData/Local/Temp/fullpos_offline_denied_probe_test.dart
  test/core/routing --dart-define=API_BASE_URL=http://127.0.0.1:4000 --reporter expanded
PASS: 16 pruebas, incluida la reproducción que fallaba antes.

flutter drive --no-pub --driver=test_driver/integration_test.dart
  --target=integration_test/offline_login_native_test.dart -d windows --no-dds
  --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=FULLPOS_UAT_BUILD=true
  --dart-define=FULLPOS_UAT_LABEL=ACCESO_LOCAL
  --dart-define=API_BASE_URL=http://127.0.0.1:4000
PASS: caso nativo, 11 s; FULLPOS_WINDOWS_CHANNEL=uat-mayoreo solo en el proceso.

Mismo driver con -d emulator-5556
PASS: caso nativo Android, 13 s.

flutter test --no-pub test/features/catalogo/catalog_offline_uat_integrity_test.dart
  --dart-define=API_BASE_URL=http://127.0.0.1:4000 --reporter expanded
NO EJECUTADAS: sus 2 pruebas están condicionadas a configuración UAT adicional.

git diff --check
PASS.
```

La batería ampliada también contiene un caso visual W13 que termina sin ejecutar
su recorrido externo cuando faltan `W13_VIS_*`. Sus logs lo indican: no se cuenta
como evidencia de una validación externa. No se habilitó un destino compartido
para forzarlo. Las pruebas nativas efectivas usan HTTP loopback simulado y los
almacenes nativos reales; el Android probado es un emulador, no un teléfono físico.

Registros adicionales: `fullpos-offline-login-reaudit-*.log`, conservados en la
misma carpeta privada de evidencias. Sin cambios en backend, proyectos nativos,
datos productivos ni en otros worktrees. Sin commit/push/deploy.

**GO de validación local del acceso en Windows y Android**, con los límites
indicados. No se afirma seguridad absoluta ni funcionamiento del 100 % en todo
equipo. No se probó un reinicio completo del sistema operativo ni todos los
modelos físicos Android; recrear los repositorios no equivale a ese reinicio.
La compatibilidad iPhone y la autorización de publicación siguen pendientes.

## Persistencia entre procesos — cierre limitado a Windows

El propietario limitó expresamente la comprobación final a Windows. Se detuvo
la continuación de Android. No se reinició el ordenador del usuario.

Se añadió `integration_test/offline_login_restart_native_test.dart`, una prueba
nativa en tres procesos separados. Usa un usuario ficticio específico, claves
UAT y almacenamiento cifrado real. La fase de preparación registra un permiso
sintético local (no una autorización externa). La fase siguiente usa una conexión
loopback rechazada en el puerto 1, no un servidor productivo. Restaura cualquier
identidad activa UAT anterior después de la prueba.

Comando ejecutado tres veces desde `apps/fulltech_app`:

```text
FULLPOS_WINDOWS_CHANNEL=uat-mayoreo (variable del proceso)
flutter drive --no-pub --driver=test_driver/integration_test.dart
  --target=integration_test/offline_login_restart_native_test.dart
  -d windows --no-dds
  --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=FULLPOS_UAT_BUILD=true
  --dart-define=FULLPOS_UAT_LABEL=ACCESO_LOCAL
  --dart-define=API_BASE_URL=http://127.0.0.1:4000
  --dart-define=OFFLINE_RESTART_RUN=windows-20261122-restart-a
  --dart-define=OFFLINE_RESTART_PHASE=<prepare|verify|revoked>
```

Resultados efectivos, todos con código de salida 0:

- `prepare`: PASS (4 s), persistencia cifrada preparada y contraseña verificada.
- `verify`: PASS (10 s), nuevo proceso sin preparación: rechaza contraseña
  incorrecta y otra cuenta, recupera su empresa desde el almacén persistente,
  autentica mediante el repositorio ante conexión rechazada y revoca el acceso.
- `revoked`: PASS (0 s), tercer proceso: el acceso revocado permanece bloqueado.
- `flutter analyze --no-pub`: PASS, sin incidencias (63,9 s).
- `git diff --check`: PASS; backend y proyectos nativos sin cambios.

Los logs Windows están preservados como `fullpos-offline-restart-windows-*.log`
en la carpeta privada de evidencias. El aviso conocido del colector Windows del
driver no impidió recibir los resultados ni cambió aserciones.

**GO de validación local Windows**, incluida persistencia entre ejecuciones de la
app. No equivale a probar el reinicio completo de Windows, un instalador release,
ni todos los equipos físicos. No se publicaron commits ni se desplegó nada.

### Android suspendido: no extender el resultado Windows

Antes de la limitación del propietario se preparó el perfil y reinició solamente
el AVD exclusivo `FullPOS_OfflineAuth_QA_20261122`. Los identificadores de arranque
eran distintos, confirmando el reinicio. La fase posterior falló al no recuperar
el perfil (`LOCAL_LOGIN_UNAVAILABLE`, lectura nula en `offline_login.dart:165`).
No está determinada la causa ni se presenta como aprobada. La instalación del
ejecutor entre fases debe investigarse antes de atribuirlo al reinicio o al
almacén. Se conservaron los logs y se pausó Android según instrucción expresa;
no se ejecutó allí la tercera fase. Este hallazgo reemplaza cualquier lectura
anterior de GO para el caso de reinicio Android. No hay teléfono físico conectado.
