# e-CF — Compuerta de integración final

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-15**.
Sin `commit`, sin `push`, sin `deploy`. Producción y UAT histórica **intactas**.

Estados: **IMPLEMENTADO** · **EJECUTADO** · **NO EJECUTADO** · **BLOQUEADO**.

---

## 1. Resultado de la sesión en una línea

**El primer E2E visual de Flutter quedó IMPLEMENTADO y compila limpio, pero NO se
ejecutó**: los tres destinos posibles están bloqueados por infraestructura de la
máquina, no por la prueba. **No se declara ningún PASS visual y no se generó
ninguna captura.**

## 2. Qué se construyó

`apps/fulltech_app/integration_test/ecf_visual_e2e_test.dart`

Prueba de integración **real** (no widget test): corre sobre un dispositivo con el
motor de Flutter, gestos reales y **HTTP real sobre socket** contra un backend
local levantado por la propia prueba (`HttpServer` en `127.0.0.1`, puerto
efímero). Recorre los tres recorridos e-CF de la interfaz:

| Recorrido | Pasos que ejercita |
| --- | --- |
| **E31** | Abre el diálogo desde la venta → **elección explícita de tipo** → forma de pago fiscal → confirmar → ver resultado con su e-NCF |
| **E32** | Elección explícita de consumo → confirmar → resultado → **bandeja sin e-NCF** y sin presentarse como aceptado |
| **Bandeja** | Abre el detalle → estado operativo, resultado fiscal e historial |
| **E34** | Muestra el original y su **saldo** → nota parcial → motivo obligatorio → confirmar → **exceso de saldo bloqueado** → comprueba que **no se gastó número** |

Incluye captura de pantalla a `docs/ecf-integration-evidence/` (mismo mecanismo que
las pruebas UAT ya existentes del proyecto).

**Alcance declarado:** no recorre *login* ni el alta de la venta; eso pertenece al
armazón completo de la app y **no está cubierto**. El backend es local y sintético:
no hay proveedor, no hay emisión y ninguna respuesta declara aceptación de la DGII.

## 3. Qué se ejecutó exactamente (y qué no)

| Intento | Comando | Resultado |
| --- | --- | --- |
| Windows (ruta del worktree) | `flutter test integration_test/… -d windows` | **BLOQUEADO**: el build nativo falla con `MSB3491` — la ruta del plugin `media_kit_libs_windows_video` supera el límite de 260 caracteres de Windows. **No es un defecto de la prueba.** |
| Windows (unidad `subst` corta) | `subst X: <worktree>` + mismo comando | **La app COMPILÓ y ENLAZÓ** (`Built build\windows\x64\runner\Debug\fullpos_cloud.exe`, 143,7 s), lo que **descarta que la prueba sea el problema**. Después: `Unable to start the app on the device` (el lector de depuración no arranca). **BLOQUEADO** por el arranque del dispositivo en esta máquina. |
| Android (emulador `emulator-5554`) | `flutter test integration_test/… -d emulator-5554` | **BLOQUEADO** por configuración **preexistente** de Gradle: `android/app/build.gradle.kts:50` hace `keystoreProperties["keyAlias"] as String` y falta `key.properties`. Es un **secreto de firma**: no se fabrica ni se inventa. La prueba ni siquiera llega a compilarse. |
| Web (Chrome / Edge) | — | **INCOMPATIBLE**: la prueba usa `dart:io` (servidor HTTP local), que no existe en web. |

La unidad `subst` se liberó al terminar. No se modificó ninguna configuración del
proyecto.

**`flutter analyze`: No issues found** — la prueba compila sin errores ni avisos.

## 4. Tabla de estado

| Funcionalidad | Implementación | Prueba ejecutada | Evidencia | Riesgo residual | Estado |
| --- | --- | --- | --- | --- | --- |
| E2E visual Flutter (E31/E32/E34) | **IMPLEMENTADO** | **NO EJECUTADA** | `flutter analyze` limpio; build Windows enlazado | Infraestructura local (MAX_PATH, arranque de dispositivo, firma Android) | **BLOQUEADO** |
| Simulador Alanube (16 escenarios) | IMPLEMENTADO | **EJECUTADA** (sesión previa, 33/33) | `alanube-scenario.transport.spec.ts` | Ninguno | **PASS** |
| Matriz de máquina de estados | IMPLEMENTADO | **EJECUTADA** (sesión previa, 20/20) | `ecf-document-state-machine.matrix.spec.ts` | Ninguno | **PASS** |
| E2E HTTP + PostgreSQL (E31/E32/E34) | IMPLEMENTADO | **EJECUTADA** (sesión previa, 3/3) | `ecf-documents-http.e2e-spec.ts` | Venta y original sembrados por Prisma | **PASS** |
| Simulador Alanube **integrado** (despacho→persistencia→bandeja) | **NO IMPLEMENTADO** | NO EJECUTADA | — | El recorrido completo del despacho con transporte simulado sigue sin probarse | **NO EJECUTADO** |
| Compatibilidad POS tradicional (login, refresh, NCF, turnos, offline…) | Parcial (auditoría estática) | **NO EJECUTADA** esta sesión | Diff aditivo: 5 archivos, +35/−4 | Cliente antiguo sin ejecutar | **BLOQUEADO / NO PROBADO** |
| Contratos por tipo (E31/E32/E34) | NO IMPLEMENTADO | NO EJECUTADA | — | Sin pruebas contractuales independientes por tipo | **NO EJECUTADO** |
| Concurrencia HTTP e idempotencia | Parcial (nivel de servicio) | **NO EJECUTADA** por HTTP | Suites PG previas | Carrera entre dos notas cubierta a nivel de servicio | **NO EJECUTADO** (HTTP) |
| Migración y rollback | NO IMPLEMENTADO | NO EJECUTADA | — | Orden de migración documentado, no simulado | **NO EJECUTADO** |
| Seguridad multiempresa | IMPLEMENTADO | **EJECUTADA** (suites previas) | Aislamiento por empresa, IDOR, e-CF apagado | Ninguno conocido | **PASS** |
| Integridad financiera | IMPLEMENTADO | **EJECUTADA** (E2E previo) | Sin movimientos de inventario ni de caja | Ninguno conocido | **PASS** |

## 5. Suites completas (última ejecución, sin cambios de producto en esta sesión)

```
flutter analyze                            → No issues found!  (incluye integration_test/)
flutter test                               → 1325 passed, 1 skipped
npx tsc -p tsconfig.build.json --noEmit    → TSC_EXIT=0
npx prisma validate                        → schema is valid
pwsh scripts/ecf-test-db/run-tests.ps1     → 127 suites passed (1 skipped), 1375 passed, 8 skipped
                                             ISOLATION OK: 708/568/3462
git diff --check                           → DIFFCHECK_EXIT=0
```

El único cambio de esta sesión es la prueba de integración (no ejecutable en este
entorno); no se tocó código de producto, por lo que las suites anteriores siguen
siendo válidas y se declara así en lugar de repetirlas sin motivo.

## 6. Cómo desbloquear el E2E visual

1. **Windows**: habilitar rutas largas (`LongPathsEnabled`) **o** construir desde
   una ruta corta (la unidad `subst` ya lo demostró) y hacer que el arranque del
   dispositivo funcione. El build en sí funciona.
2. **Android**: proveer `android/key.properties` con un keystore **de desarrollo**
   (decisión del propietario del proyecto; es material de firma y no se fabrica aquí).
3. **Web**: requiere reescribir la prueba sin `dart:io` (sustituir el servidor
   local por interceptación), lo que dejaría de ser HTTP real.

## 7. Riesgos

| Riesgo | Severidad | Estado |
| --- | --- | --- |
| Ningún recorrido de interfaz ha sido ejecutado end-to-end | Media | Mitigado por 61 pruebas de widget y el E2E HTTP; el recorrido gráfico completo sigue sin evidencia |
| Despacho real nunca ejercitado | Alta | Deliberado: la emisión es inalcanzable por construcción |
| Cliente tradicional sin probar contra el backend nuevo | Media | Mitigado por la auditoría estática; **no cerrado** |
| Contrato E32 `PARTIAL_OFFICIAL` | Alta | Bloquea emisión, no preparación local |

## 8. Bloqueantes externos

1. Contrato E32 `PARTIAL_OFFICIAL` (proveedor).
2. Mecanismo de firma del webhook (proveedor).
3. Credenciales de sandbox y ventana autorizada.
4. Certificación DGII (ejecución y autorización humanas).
5. Artefacto de una versión anterior verificable.
6. **Infraestructura de ejecución gráfica** en esta máquina (§6).

## 9. GO / NO-GO por entorno

| Entorno | Veredicto | Motivo |
| --- | --- | --- |
| **Desarrollo local** | **GO** | Suites completas en verde, analyze limpio, aislamiento histórico intacto |
| **UAT** | **GO** | E2E HTTP 3/3, simulador 33/33, matriz de estados 20/20, integridad financiera verificada |
| **Sandbox Alanube** | **NO-GO** | Sin contrato E32 confirmado, sin firma de webhook y sin credenciales: cualquier llamada sería una simulación presentada como real |
| **Certificación DGII** | **NO-GO** | Requiere ejecución y autorización humanas |
| **Producción** | **NO-GO** | Sin certificación, sin E2E gráfico ejecutado y sin cliente tradicional probado. **Superar pruebas automatizadas no convierte esto en GO.** |
| **Emisión real** | **NO-GO** | La única ruta que cablea `dispatchOnce` es `POST /ecf/documents/:id/simulate-dispatch`, que trabaja contra el simulador PURO y se niega fuera de una UAT local o si el transporte real estuviera activo. El proveedor real sigue sin ruta: no hay camino a `DGII_ACCEPTED`. |

## 10. Actualización 2026-10-16 — cadena simulada cableada

Se cerró la brecha «simulador conectado de extremo a extremo». Dos hallazgos, no uno:

1. `dispatchOnce` no tenía ruta HTTP. Ahora la tiene, **solo** contra el simulador.
2. Los cuerpos del simulador **no correlacionaban** (usaban `documentStatus` en lugar del
   contrato local). Ahora existe una capa de respuesta fiel al contrato local, tomando la
   identidad del propio payload (`idDoc.encf`, `sender.rnc`), sin tocar el simulador
   original ni sus 33 pruebas.

Evidencia: `correlated: true`, las 10 comprobaciones en verde, `providerOutcome: ACCEPTED`,
`officialFiscalAcceptance: false`, estado persistido `HUMAN_REVIEW_REQUIRED`, 1 recibo de
evidencia y **0** documentos en `DGII_ACCEPTED`/`PROVIDER_ACCEPTED`.

Pruebas: 15 nuevas (6 de política + 9 E2E PostgreSQL). Totales actuales: Flutter 1351,
backend 1391 en 129 suites, aislamiento histórico intacto (708/568/3462).
Detalle completo en `docs/ECF_ALANUBE_SIMULATED_END_TO_END.md`.

Sigue **pendiente**: el disparador en la interfaz Flutter (capa de datos lista), la prueba
de concurrencia en paralelo, y todo lo relativo a proveedor real, certificación y producción.

---

## Actualización 2026-10-16 — el disparador Flutter y la habilitación DGII ya existen

Los dos pendientes que encabezaba esta compuerta están cerrados:

1. **Disparador en la interfaz Flutter**: implementado (`EcfSimulatedDispatchAction`), con la
   UAT como única puerta y aviso explícito de que no es aceptación de la DGII. La concurrencia
   en paralelo también quedó cubierta (2 y 5 despachos simultáneos: siempre 1 ganador, 1 envío,
   1 recibo de evidencia, 0 en `DGII_ACCEPTED`/`PROVIDER_ACCEPTED`).
2. **Habilitación DGII por empresa**: backend completo (modelo, política fail-closed, servicio,
   endpoints, 30 pruebas) y **pantalla Flutter** integrada en el módulo e-CF.

**Circuito simulado de extremo a extremo por HTTP**: cubierto por un E2E que prepara,
 despacha contra el simulador, persiste, consulta banda y detalle, rechaza el segundo despacho
con 409 (un solo `SEND_TO_PROVIDER`) y comprueba el escenario de timeout. Ni un 201 simulado ni
la declaración del proveedor producen aceptación fiscal.

**Totales tras esta sesión**: Flutter **1386** pruebas (1 omitida); backend e-CF **696** en 60
suites; `flutter analyze` y `tsc --noEmit` sin incidencias; `prisma validate` válido; aislamiento
histórico intacto (708/568/3462).

**Compuertas que siguen cerradas**: emisión real (`PRODUCTION_EMISSION_IMPLEMENTED = false`),
certificación DGII (sin registro oficial verificado), despliegue a producción.
Ver `docs/ECF_NEXT_PRODUCTION_GATES.md`.
