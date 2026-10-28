# Guardian AI — Fase 3: piloto Windows aislado y preparación de la aceptación final

Validado el 2026-10-28 sobre el worktree `agent/guardian-telemetry-phase1`
(`C:\src\fullpos-guardian-telemetry-uat`). Sin tocar `production-main`, sin
instalaciones de clientes, sin llamadas facturables a IA y sin envíos de WhatsApp.

---

## 1. Aislamiento real del piloto Windows

### 1.1 Identidad separada del ejecutable

La identidad del runner de Windows es ahora parametrizable (con valores por
defecto idénticos a producción, así que el build oficial no cambia):

| Pieza | Producción | Piloto UAT |
| --- | --- | --- |
| Ejecutable | `fullpos_cloud.exe` | `fullpos_uat.exe` |
| CompanyName | `FullPOS` | `DaleVentas UAT` |
| ProductName | `FullPOS` | `DaleVentas POS UAT` |
| FileDescription | `FullPOS` | `DaleVentas POS UAT - Piloto Guardian` |
| Título de ventana | `FullPOS Cloud - Sistema de facturacion` | `DaleVentas POS UAT (Piloto)` |
| Mutex de instancia única | `Local\DaleVentasPOSSingleInstance` | `Local\DaleVentasPOSUATSingleInstance` |

Verificado leyendo el recurso de versión del binario generado
(`CompanyName=DaleVentas UAT`, `ProductName=DaleVentas POS UAT`,
`OriginalFilename=fullpos_uat.exe`).

### 1.2 Rutas de datos efectivas del piloto

Windows resuelve el directorio de datos a partir de CompanyName/ProductName, de
modo que el piloto escribe **solo** en:

```
%APPDATA%\DaleVentas UAT\DaleVentas POS UAT\
├─ shared_preferences.json          (preferencias locales separadas)
├─ flutter_secure_storage.dat       (credencial de instalación)
├─ guardian_agent.log               (diagnóstico del agente, 32 KB rotativo)
└─ databases\
   ├─ fulltech_offline.db           (cola de negocio del piloto)
   └─ guardian_outbox.db            (cola de Guardian, INDEPENDIENTE)
```

Además, con `--dart-define=DALEVENTAS_POS_UAT_ISOLATION=true`,
`WindowsProductPaths.productRoot()` **nunca** devuelve
`C:\Program Files\DaleVentas POS`: si no hay `DALEVENTAS_POS_ROOT` explícito, la
raíz de producto es `null` y todo cae al directorio de datos de la propia
identidad (fail-safe, no fail-open).

### 1.3 Prueba de no interferencia con producción

Se tomaron huellas SHA-256 de los 12 archivos de
`C:\Program Files\DaleVentas POS\databases` antes y después de **cuatro**
ejecuciones del piloto (online, offline, reinicio, reconexión):

```
IDENTICO: 12 archivos con mismo SHA-256 (sin lecturas/escrituras de producción)
```

No se migró, movió, borró ni modificó ninguna base de datos de producción.

## 2. Seguridad del enrolamiento

| Requisito | Implementación verificada |
| --- | --- |
| Sin código embebido en el ejecutable | El código ya **no** se pasa por `--dart-define`. Se lee en tiempo de ejecución desde un archivo (`GUARDIAN_ENROLLMENT_CODE_FILE`, una *ruta*, no un secreto) o desde la variable de entorno `GUARDIAN_ENROLLMENT_CODE` |
| Un solo uso | Consumo atómico en servidor (`updateMany ... uses < maxUses`); verificado `genr_9fe7baf` → `uses=1/1` |
| Caducidad | Código con TTL (3 h en UAT); credencial con `expires_at` (`GUARDIAN_INSTALL_CREDENTIAL_DAYS`, 30 días) |
| Vinculación a la instalación | La credencial queda ligada a `install_id` (`hnn1mtzc4e` en el piloto) |
| Revocación | `enabled=false` / `revoked_at`; el transporte detecta 401/403, **borra la credencial local** (`onCredentialRejected`) y el siguiente arranque vuelve a enrolarse |
| Almacenamiento | `flutter_secure_storage` (DPAPI en Windows); el archivo del código se elimina tras el canje (verificado: `Test-Path` = `false`) |
| Aislamiento multiempresa | La empresa la determina el código/credencial; el DTO rechaza `companyId` (`400 property companyId should not exist`) |
| No debilitar autenticación | Guard propio, hash SHA-256, `401` inválida, `503` no verificable, 120 req/min por credencial |

## 3. Ejecutable y pruebas

```
build\windows\x64\runner\Release\fullpos_uat.exe   (444 416 bytes)
flutter analyze                                    → No issues found
flutter test test/core/guardian                    → 34/34 PASS
flutter test test/core/offline|storage|app_update  → 91/91 PASS
npm --workspace apps/api test                      → 1057 PASS / 12 skipped / 0 FAIL
```

Comportamiento observado en ejecución real (log ordenado y sin intercalado):

```
18:18:18.483 flush: 1 pendientes            (evento pendiente del corte anterior)
18:18:19.236 respuesta: ok=1 ... retry=false
18:18:19.447 enviados=1                     ← reconexión automática
18:18:23.536 evento en cola (updater)
18:18:28.457 flush: 1 pendientes            ← cadencia de 10 s aplicada en caliente
18:18:28.905 respuesta: ok=1
```

Incidentes del piloto en Guardian (plataforma `windows`, todos con diagnóstico mock):

| incidentId | Módulo | Estado |
| --- | --- | --- |
| `4093e728-9606-4257-beda-1579e2c54c9a` | flutter (`Zone`) | DIAGNOSED |
| `032976ab-ee4c-4e05-860f-c3f41924081d` | updater | DIAGNOSED |
| `3db0ad90-fe58-4c72-99ad-916e0f7f5c27` | updater | DIAGNOSED |
| `f2abbc75-4932-4062-9d8a-4347d7128581` | updater | PENDING → DIAGNOSED por worker |

Total en UAT: 11 incidentes de plataforma `windows`.

## 4. Regresión offline

| Escenario | Evidencia |
| --- | --- |
| Guardian inalcanzable | App viva 50 s (`cpu=0.8 s`, `mem=184 MB`), **1 evento en cola**, **0 descartes**, 0 incidentes creados |
| Offline prolongado (110 s) | Sin pérdida; el flush falla con `connectionError`, `attempts=1` y backoff programado |
| Reconexión / reinicio | Al arrancar con Guardian disponible: `flush: 1 pendientes` → `enviados=1` en 0.03 s |
| Independencia de colas | `guardian_outbox.db` es un archivo aparte de `fulltech_offline.db`; ninguna escritura de Guardian toca la cola de ventas |
| 48 h offline / idempotencia | Sin cambios: `clientRequestId`, atomicidad SQLite y restricciones de transacción intactas (91 pruebas de offline/storage/updater en verde) |

## 5. Android

- **Corregido el bloqueo**: `android/app/build.gradle.kts` ya no exige material de
  firma para depurar. La configuración `signingConfigs.release` solo se crea si
  existe `android/key.properties`, y el fallo por falta de claves se evalúa en el
  *task graph* únicamente para tareas `release`.
- `flutter build apk --debug` → **OK** (`build\app\outputs\flutter-apk\app-debug.apk`, 258 s).
- `flutter build apk --release` sigue fallando con mensaje explícito si no hay
  `key.properties` (no se firmó nada con claves ajenas).
- No se generó, sustituyó ni expuso ninguna clave de producción. **No se publicó APK.**

## 6. iOS

- Sin macOS/Xcode no hay build ni pruebas de dispositivo. **No se afirma ninguna
  validación en iPhone.**
- Validación estática: `flutter analyze` limpio sobre el mismo código compartido;
  ATS estándar (solo HTTPS) y el endpoint de Guardian es HTTPS.
- Pendiente para iOS: build en macOS, prueba en dispositivo físico, y decidir si
  se usa `flutter_secure_storage` con Keychain (ya soportado por el código).

## 7. Secuencia DeepSeek → WhatsApp (análisis, sin ejecutar)

### 7.1 Hechos verificados en el código

1. `GuardianAlertService.planForIncident` se llama **desde la ingesta**
   (`guardian.ingest.service.ts:105`), en el mismo instante en que se persiste el
   incidente, **antes** de que exista cualquier diagnóstico.
2. Si `GUARDIAN_ALERTS_ENABLED=false`, `planForIncident` **no crea nada**
   (`ALERTS_DISABLED`, `alert.service.ts:223`) y `processDue` no despacha
   (`:335`). Es decir: con alertas apagadas no queda ninguna alerta en cola.
3. El ciclo del worker ejecuta **primero las alertas y después los diagnósticos**
   (`scripts/guardian/guardian-workers.ts:72` vs `:76`).
4. Los parámetros de la plantilla **sí** se construyen en el momento del envío y
   leen `diagnoses` con `status='DONE'` (`alert.service.ts:379-416`), y la
   posición 6 (`diagnosis`, máx. 400 caracteres) existe en la plantilla aprobada
   `guardian_incident_alert` (8 variables).
5. La alerta inicial es única por incidente (`dedupeKey = guardian:alert:initial:<id>`,
   `ALREADY_QUEUED` si ya existe): no hay re-planificación posterior.

### 7.2 Conclusión

El diagnóstico **no** aparece automáticamente en WhatsApp en el flujo actual: la
alerta se envía en el mismo ciclo en que el diagnóstico aún no existe, así que la
posición 6 sale como «Información pendiente de confirmar.». La plantilla sí puede
llevar el resumen real; el problema es **de orden**, no de contrato.

### 7.3 Cambio de código necesario (no aplicado) para que sea automático

En `scripts/guardian/guardian-workers.ts`, dentro de `tick()`, invertir el orden:

```ts
// antes: alerts.processDue(...) y luego diagnosis.runBatch(...)
const diagnosisOutcome = await diagnosis.runBatch(5).catch(...);
const alertOutcome = await alerts.processDue(10).catch(...);
```

Con eso, en el mismo ciclo el incidente se diagnostica primero y la alerta lee
`diagnoses[0]` ya en `DONE`. Requiere reconstruir la imagen de workers y actualizar
`guardian-uat_workers` (autorización expresa; afecta a la ruta de comunicación).

### 7.4 Secuencia operativa recomendada para UNA prueba controlada (sin cambios de código)

1. UAT con `GUARDIAN_AI_PROVIDER=mock` y `GUARDIAN_ALERTS_ENABLED=false` (estado actual).
2. `GUARDIAN_ALERTS_ENABLED=false` **se mantiene** y `GUARDIAN_AI_PROVIDER=deepseek`
   con clave montada, `GUARDIAN_AI_MODEL=deepseek-flash`, presupuesto
   `GUARDIAN_AI_TOKENS_PER_COMPANY_DAY` suficiente y un solo incidente candidato.
3. Lanzar el piloto Windows (`fullpos_uat.exe`) → **un** incidente (sonda `GUARDIAN_SELFTEST`).
4. Esperar a que `guardian_diagnoses.status='DONE'` para ese incidente y comprobar
   `count(*)=1` (una sola petición facturable, `tokens_used>0`).
5. Restaurar `GUARDIAN_AI_PROVIDER=mock` de inmediato.
6. Con `GUARDIAN_ALERTS_ENABLED=true` y **un** destinatario, crear la alerta con una
   única llamada a `alerts.planForIncident(incidentId)` (script en contenedor, mismo
   patrón que el *one-shot* de IA). El envío leerá el diagnóstico ya en `DONE`.
7. Verificar: 1 alerta, 1 intento, `template_params[5]` = resumen del diagnóstico.
8. Volver a `GUARDIAN_ALERTS_ENABLED=false` inmediatamente y comprobar que no hay
   intentos adicionales.

Reglas para no duplicar: un solo incidente, una sola llamada a `planForIncident`,
alertas desactivadas fuera de la ventana del paso 6-7 y `dedupeKey` de alerta
único por incidente.

## 8. Bloqueadores restantes

1. **Orden alertas/diagnóstico** (§7.3): sin el cambio, la alerta no lleva el
   diagnóstico. Decisión pendiente de autorización.
2. **Android release**: requiere `android/key.properties` con material de firma
   autorizado (no se creó nada).
3. **iOS**: necesita macOS + Xcode + dispositivo físico.
4. **Credenciales del piloto**: `gmk_6ea02a8d` caduca el 2026-11-27; el código de
   enrolamiento se consume, así que una reinstalación del piloto necesita un
   código nuevo.
5. `windows/flutter/generated_plugin_registrant.*` y `generated_plugins.cmake`
   aparecen modificados por los builds (archivos generados).

## 9. GO / NO-GO

**GO** para ejecutar **una** prueba de aceptación de extremo a extremo controlada
(sonda real → ingesta autenticada → diagnóstico DeepSeek real → WhatsApp oficial),
siguiendo la secuencia de §7.4 y con estas condiciones:

- Un único incidente sintético y una única llamada facturable a IA.
- Un único destinatario administrativo y una única alerta.
- Alertas desactivadas antes y después de la ventana del envío.
- `GUARDIAN_AI_PROVIDER` restaurado a `mock` inmediatamente después del diagnóstico.

**NO-GO** si se pretende que el diagnóstico aparezca en WhatsApp **sin** aplicar el
cambio de orden de §7.3 ni la llamada manual de §7.4 paso 6.
