# e-CF — UAT visual autenticada en Windows

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-15**.
Sin `commit`, sin `push`, sin `deploy`. Producción y UAT histórica **intactas**.

---

## 1. Backend utilizado

| Pieza | Valor |
| --- | --- |
| API | NestJS local en **`http://127.0.0.1:4004`** (`scripts/visual-uat/visual-uat.ps1 -Action start-api`) |
| Base de datos | **`fullpos_alanube_uat_test`** en `127.0.0.1:56551` — la PostgreSQL **desechable** del proyecto |
| Contenedor | `fullpos_alanube_ecf_test_postgres` (postgres:16-alpine, sano) |
| UAT histórica | `fullpos_alanube_uat_postgres` (56550) — **no se tocó**; es inmutable |
| Alanube | `ALANUBE_ENABLE_REAL_CALLS=false`, emisión `ECF_EMISSION_ENABLED=false`, transporte HTTP desactivado |

Se eligió la base desechable, y no la histórica, porque el proyecto la declara
explícitamente como tal (`scripts/ecf-test-db/_test-common.ps1`) y porque la
misión prohíbe escribir en las bases históricas UAT.

El perfil de entorno efímero **no puede arrancar la API**: su
`UAT_EXPECTED_DB_NAME` no coincide con la base real, así que
`assertSafeUatEnvironment()` (llamado en `main.ts:20`) rechaza el arranque. Por eso
se deriva un perfil propio (`.env.ecf.visual.uat.local`, **ignorado por git**) que
fija el nombre, el puerto y un `PORT` distinto, manteniendo todas las compuertas.

### Evidencia de aislamiento

El script de perfil rechaza el arranque si algo no cuadra:

```
APP_ENV=uat · UAT_LOCAL_ONLY=true · PORT=4004
UAT_EXPECTED_DB_NAME=fullpos_alanube_uat_test · UAT_EXPECTED_DB_PORT=56551
DATABASE_URL debe apuntar a 127.0.0.1:56551/<base desechable>
Rechazado si apunta a :56550/ o a /fullpos_alanube_uat
Rechazado si DATABASE_URL contiene easypanel|gcdndd|31.97.99.70|hostinger|phytoemagry
Rechazado si ALANUBE_ENABLE_REAL_CALLS != false o ECF_EMISSION_ENABLED != false
```

Y la suite automatizada sigue demostrando que la histórica no se mueve:

```
Historical UAT counts BEFORE (companies,trials,documents): 708,568,3462
Historical UAT counts AFTER  (companies,trials,documents): 708,568,3462
ISOLATION OK: historical UAT unchanged by the automated suite.
```

## 2. Blindaje de `API_BASE_URL` (Fase 2) — IMPLEMENTADO

**Riesgo eliminado:** `Env.apiBaseUrl` cae a `ProductConfig.productionApiBaseUrl`
cuando `API_BASE_URL` falta o es inválida; un `--dart-define` olvidado dejaba el
build de validación apuntando a producción.

- Nuevo `lib/core/config/uat_api_config.dart`, **aislado al perfil UAT**.
- `Env.apiBaseUrl` lo aplica **solo** si
  `--dart-define=FULLPOS_UAT_PROFILE=true`.
- Con el perfil activo: `API_BASE_URL` es obligatoria, **no hay ningún valor por
  defecto**, solo se admite host local (`localhost`/`127.0.0.1`/`::1`), se
  rechazan los hosts productivos conocidos y un valor ausente o inválido **falla
  de forma visible** (`StateError UAT_API_BASE_URL_REFUSED`) en vez de degradar a
  un backend remoto.
- Los builds comerciales **no cambian**: `isUatProfile` es `false` por defecto.

Cobertura: `test/core/config/uat_api_config_test.dart` (**9 pruebas**), incluidas
las que fijan que el perfil comercial conserva su comportamiento.

## 3. Empresa de prueba (Fase 3) — CREADA

Creada **exclusivamente** en la base desechable, a través del endpoint real de la
API (`POST /auth/register-business`), no por SQL ad-hoc:

| Dato | Valor |
| --- | --- |
| Empresa | `ECF Visual UAT Demo` (ficticia) |
| Administrador | usuario sintético `ecf.visual.admin@fullpos.local`, rol ADMIN |
| Credenciales | solo en `.env.ecf.visual.uat.local` (**ignorado por git**); no se imprimen ni se versionan |
| e-CF al inicio | **`settings.ecfEnabled = false`** |
| Emisión | `capabilities.emissionPathAvailable = false` |
| RNC/e-NCF reales | ninguno |
| Reproducibilidad | el seed es idempotente (si el correo ya existe, la API responde 409 y se trata como OK) |

Verificado por HTTP tras el seed:

```
login                                 : OK
settings.ecfEnabled                   : False
settings.companyName                  : ECF Visual UAT Demo
ecf.capabilities.enabled               : False
ecf.capabilities.emissionPathAvailable : False
```

> Nota: este `settings.ecfEnabled = False` es además **la comprobación en vivo
> del defecto 2** corregido en la fase anterior (`toPublicSettings` publicaba el
> flag solo tras el arreglo).

## 4. Estado de autenticación

| Vía | Estado |
| --- | --- |
| Login por API (HTTP) con el administrador sintético | **OK** (`accessToken` emitido) |
| Login **dentro de la app Windows** | **NO conseguido** — ver §6 |

## 5. Aplicación Windows (Fase 4)

- Build UAT compilado con binding explícito y con el perfil blindado:

```
flutter build windows --debug \
  --dart-define=API_BASE_URL=http://127.0.0.1:4004 \
  --dart-define=APP_BASE_URL=http://127.0.0.1:4004 \
  --dart-define=FULLPOS_UAT_PROFILE=true
√ Built build\windows\x64\runner\Debug\fullpos_cloud.exe
```

Se fijó también `APP_BASE_URL` para que el comprobador de actualizaciones del
build de validación no apunte a la infraestructura remota.

- La aplicación **abre y se mantiene** (ventana «FullPOS Cloud - Sistema de
  facturación»), sin ninguna instancia comercial en ejecución.
- Con el perfil UAT activo, `Env.apiBaseUrl` **no puede** devolver la URL de
  producción: o devuelve una URL local admitida o lanza. Que la app llegue a la
  pantalla de inicio de sesión demuestra que la resolución pasó el blindaje, es
  decir que está atada a `http://127.0.0.1:4004`.
- Mientras la app estuvo abierta, sus conexiones TCP fueron
  `Listen 0.0.0.0:0` y **ninguna** conexión establecida a un host remoto.
- Captura de la ventana real: `fullpos-uat-login-attempt.png` (pantalla de inicio
  de sesión, capturada con `PrintWindow` sobre el proceso real).

## 6. Recorrido visual (Fase 5) — **BLOCKED**, sin PASS visual

**No se completó el recorrido y no se declara ningún PASS visual del interruptor.**

Causas exactas, ambas de infraestructura de automatización (no del producto):

1. **Flutter no expone su árbol de accesibilidad a UI Automation.**
   Sondeando la ventana real con `System.Windows.Automation` se obtiene
   **1 elemento**: `[ControlType.Pane] name='FLUTTERVIEW'`. Sin árbol de
   semántica no hay automatización por elemento (ni clic ni lectura de estado).
2. **La inyección sintética de teclas rompe el modelo de eventos de Flutter.**
   Al enviar `Ctrl+V`/`{TAB}` con `SendKeys` para rellenar el formulario, la
   aplicación mostró su diálogo «Diagnóstico interno» con:

```
Tipo: _AssertionError
Contexto: FlutterError
#2 HardwareKeyboard._assertEventsRegular (package:flutter/src/services/hardware_keyboard.dart)
Message: ... KeyUpEvent ... "Control Left" ... recorded logical key ... "Tab"
```

   Es la aserción de Flutter que detecta eventos de teclado sintéticos
   desordenados. El error lo provocó **la automatización**, no el backend: por eso
   el formulario de inicio de sesión **no puede rellenarse por esta vía**. Los
   clics de ratón sí funcionan (se usó para abrir el diálogo), pero la entrada de
   texto no.

**Consecuencia honesta:** las Fases 5 y 6 (recorrido visual y regresiones en vivo)
quedan **BLOCKED**. La cadena del interruptor y del Drawer sigue cubierta por
**11 pruebas funcionales ejecutadas** sobre la pantalla real y el `AppDrawer` real
(con red ausente), no por inspección visual.

### Qué haría falta para desbloquearlo

- Ejecutar el recorrido con `flutter test integration_test/... -d windows`
  (motor real, sin inyección de entrada del sistema). El repositorio ya tiene
  `integration_test/ecf_visual_e2e_test.dart`, pero cubre **solo** los recorridos
  e-CF de la interfaz contra un backend sintético propio: **no** cubre login ni el
  interruptor de empresa, así que hoy no sustituye al recorrido manual.
- O habilitar/aceptar la accesibilidad del build para exponer la semántica a UIA.

## 7. Pruebas (Fase 8)

```
flutter analyze                          -> No issues found!
flutter test                             -> 1349 passed / 1 skipped
flutter test test/core/config/uat_api_config_test.dart  -> 9 passed
npx tsc -p tsconfig.build.json --noEmit  -> exit 0
npx prisma validate                      -> schema is valid
pwsh scripts/ecf-test-db/run-tests.ps1   -> 1376 passed / 8 skipped, 127 suites
                                            ISOLATION OK (708,568,3462 sin cambios)
git diff --check                         -> exit 0
```

## 8. Problemas encontrados

1. `Env.apiBaseUrl` degradaba a producción en un build de validación → **corregido**
   con el blindaje del perfil UAT.
2. El perfil de entorno efímero no puede arrancar la API (`UAT_EXPECTED_DB_NAME`
   no coincide) → se derivó un perfil visual propio, sin debilitar ninguna
   compuerta.
3. Automatización de la UI de escritorio no viable por las dos causas de §6.
4. **Riesgo residual:** el blindaje cubre `API_BASE_URL`. `appBaseUrl` y el
   comprobador de actualizaciones siguen teniendo valor por defecto de producción;
   en el build UAT se fijó a mano (`APP_BASE_URL`), pero **no está forzado por
   código**. RECOMENDACIÓN: extender el perfil UAT a esas variables.

## 9. GO / NO-GO

| Fase | Estado |
| --- | --- |
| 1. Auditoría del entorno | **GO** |
| 2. Blindaje de `API_BASE_URL` | **GO** (implementado + 9 pruebas) |
| 3. Empresa de prueba en base desechable | **GO** |
| 4. Aplicación Windows abierta contra el backend UAT | **GO** |
| 5. Recorrido visual autenticado | **NO-GO / BLOCKED** (§6) |
| 6. Regresiones en vivo | **NO-GO / BLOCKED** (dependen de §5) |
| 7. Simulador Alanube | **NO INICIADA** |
| 8. Validaciones | **GO** |

**Global: GO WITH BLOCKERS.** Sin PASS visual: el recorrido del interruptor en una
sesión autenticada real queda pendiente y así se declara.

## 10. Próxima fase — Alanube

Punto de partida auditado en la fase anterior: existe
`apps/api/src/ecf/alanube/alanube-scenario.transport.ts` con simulador
(16 escenarios / 33 pruebas) y la emisión **no es alcanzable por construcción**
(ningún endpoint HTTP cablea `dispatchOnce`; `capabilities.emissionPathAvailable`
es `false`). El orden propuesto, sin llamar nunca al proveedor real ni consumir
numeración fiscal:

1. Cablear el transporte simulado a la ruta de preparación con
   `ALANUBE_ENABLE_REAL_CALLS=false` sobre la base desechable.
2. Matriz de estados E31/E32/E34 → bandeja Flutter, con los contratos ya
   documentados.
3. Concurrencia e idempotencia HTTP (sin reutilizar secuencias consumidas).
4. Migraciones y reversión en el entorno desechable.

---

## Actualización 2026-10-16 — qué falta de esta lista

| Punto original | Estado |
| --- | --- |
| 1. Cablear el transporte simulado a la ruta de preparación | **Hecho**: `POST /ecf/documents/:id/simulate-dispatch`, con política que se niega si el transporte real estuviera seleccionado |
| 2. Matriz de estados E31/E32/E34 → bandeja Flutter | **Hecho**: bandeja, detalle y presentación de estados |
| 3. Concurrencia e idempotencia HTTP | **Hecho**: concurrencia real probada; el segundo despacho responde 409 |
| 4. Migraciones y reversión en el entorno desechable | **Parcial**: migración aditiva de habilitación DGII aplicada y verificada en la base efímera; la *reversión* no se ha ensayado |

### Pendiente real de UAT visual

El recorrido visual autenticado **sigue sin hacerse**. La ruta a comprobar es
`Configuración de empresa` → `Facturación electrónica` → `Habilitación DGII`, y el bloqueo
conocido es que la automatización de entrada de texto en Windows dispara
`HardwareKeyboard._assertEventsRegular`. **No** se debe reintentar `SendKeys` una y otra vez:
la comprobación debe ser manual u otra vía compatible.

Mientras la ruta no se recorra a mano, el estado de cualquier verificación visual es
**BLOCKED**, por mucha evidencia estructural que exista.
