# Guardian AI — Fase 2: agente Flutter y UAT Windows

Continuación de `GUARDIAN_POS_TELEMETRY.md` (backend). Aquí se documenta el **agente
cliente** (Flutter) y la aceptación en Windows UAT. Validado el 2026-10-28.

Sin llamadas facturables a IA (`GUARDIAN_AI_PROVIDER=mock`), sin WhatsApp
(`GUARDIAN_ALERTS_ENABLED=false`), sin tocar producción.

---

## 1. Qué ya existía y se reutilizó

`apps/fulltech_app/lib/core/guardian/` ya contenía el agente completo y `main.dart`
ya lo arrancaba fail-closed. Se reutilizó **sin reescribir**:

| Pieza existente | Uso |
| --- | --- |
| `GuardianBootstrap` | Arranque, temporizador de flush, parada |
| `GuardianClient` | Cola, dedupe, backoff, cuotas, ACK durable |
| `GuardianStore` / `SqfliteGuardianStore` / `WebGuardianStore` | Cola persistente propia |
| `GuardianReporter` | Traducción de `AppErrorDetails` → incidente |
| `guardian_redaction.dart` | Redacción en cliente |
| `GuardianEvent` | Contrato con el DTO del API |
| `AppErrorReporter` (`lastError`) | Fuente de errores ya cableada en `main.dart` |
| `FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded` | Manejadores globales ya instalados |

## 2. Qué se completó (solo lo que faltaba)

| Capacidad | Cómo |
| --- | --- |
| Fallos de **arranque** (antes se perdían) | `GuardianBootstrap.installStartupCapture()` registra un buffer síncrono al inicio de `main()` (20 eventos, dedupe por `eventId`) y lo reinyecta cuando el cliente está listo |
| Errores **silenciosos** (los que la UI oculta) | `AppErrorReporter.lastRecorded` (nuevo notifier) + `GuardianReporter` lo escucha en vez de `lastError` |
| **SQLite local técnico** | Ya reportado por `resilient_local_database`/`offline_store`; ahora llega a Guardian |
| **Fallos de sincronización offline** | Ya reportado por `sync_queue_service`; ahora llega a Guardian |
| **Fallos del actualizador Windows** | `AppUpdateController._reportUpdaterFailure()` (silencioso, `module=updater`) en las dos ramas de error |
| **Credencial de instalación** | Enrolamiento por código de un solo uso + transporte `x-guardian-key` |
| Recuperación tras corte | Cola local + reintentos con backoff; al volver la conectividad se envía sola |
| Diagnóstico del propio agente | `guardian_agent.log` (32 KB, rotación, sin datos de cliente) |

## 3. Autenticación de la instalación (sin secretos en el instalador)

```
Operador plataforma → genera código de un solo uso (guardian_enrollment_codes)
App (1ª ejecución)  → POST /guardian/installations/enroll  {code, installId, platform, appVersion}
Guardian            → crea/rota credencial de máquina (gmk_…, caduca en 30 días)
App                 → guarda la credencial en flutter_secure_storage
App                 → POST /guardian/machine/incidents  (x-guardian-key)
```

- Ni el instalador ni el APK contienen una clave de máquina: el código de enrolamiento
  es de un solo uso y caduca (3 h en UAT).
- La credencial caduca (`GUARDIAN_INSTALL_CREDENTIAL_DAYS`, 30 por defecto) y es
  revocable (`enabled=false` / `revoked_at`).
- La empresa la determina el código; el DTO no admite `companyId`.
- Auditoría: `guardian_access_logs` con `INSTALLATION_ENROLLED` y `MACHINE_INGEST`.
- Sin enrolamiento configurado, el agente mantiene el transporte anterior con JWT de
  sesión (comportamiento previo intacto).

## 4. Banderas del cliente (`--dart-define`)

| Bandera | Defecto | Descripción |
| --- | --- | --- |
| `GUARDIAN_ENABLED` | `false` | Interruptor maestro |
| `GUARDIAN_BASE_URL` | *(vacío → API del POS)* | Base URL de Guardian |
| `GUARDIAN_USE_MACHINE_API` | `false` | Usa credencial de instalación |
| `GUARDIAN_ENROLLMENT_CODE` | *(vacío)* | Código de un solo uso (solo UAT/alta) |
| `GUARDIAN_SELFTEST` | `false` | Sonda sintética de UAT (una vez por perfil) |
| `GUARDIAN_MIN_SEVERITY` | `SEV3` | Severidad mínima persistida |
| `GUARDIAN_FLUSH_SECONDS` | `120` | Periodicidad del envío |
| `GUARDIAN_MAX_EVENTS` / `GUARDIAN_MAX_BYTES` / `GUARDIAN_BATCH_SIZE` | 200 / 5 MB / 20 | Límites de la cola |

## 5. Build UAT de Windows

```powershell
flutter build windows --release `
  --dart-define=APP_ENV=uat `
  --dart-define=API_BASE_URL=http://127.0.0.1:4004 `
  --dart-define=APP_BASE_URL=http://127.0.0.1:4004 `
  --dart-define=FULLPOS_UAT_PROFILE=true `
  --dart-define=GUARDIAN_ENABLED=true `
  --dart-define=GUARDIAN_BASE_URL=https://guardian-uat-api.gcdndd.easypanel.host `
  --dart-define=GUARDIAN_USE_MACHINE_API=true `
  --dart-define=GUARDIAN_ENROLLMENT_CODE=<código de un solo uso> `
  --dart-define=GUARDIAN_SELFTEST=true `
  --dart-define=GUARDIAN_FLUSH_SECONDS=10
```

Salida: `build\windows\x64\runner\Release\fullpos_cloud.exe`.

La sonda (`GUARDIAN_SELFTEST`) lanza **un** error asíncrono no controlado 4 s después
del arranque, una sola vez por perfil (`shared_preferences`), y nunca crea ventas,
pagos ni movimientos.

## 6. Operación

- Cola local: `C:\Program Files\DaleVentas POS\databases\guardian_outbox.db`
  (archivo propio; no toca las bases de ventas).
- Diagnóstico: `%APPDATA%\FullPOS\FullPOS\guardian_agent.log`.
- Revocar una instalación: `UPDATE guardian_machine_credentials SET enabled=false WHERE key_prefix='gmk_…';`
- Revocar un código: `UPDATE guardian_enrollment_codes SET revoked_at=now() WHERE code_prefix='genr_…';`

## 7. Limitaciones conocidas

- **Android**: el agente compiles y analiza sin problemas, pero el *build* APK en este
  equipo está bloqueado por un problema previo del repositorio: `android/key.properties`
  no existe y `android/app/build.gradle.kts` lo castea a `String` en la configuración
  `signingConfigs.release`. No se creó material de firma (fuera de alcance).
- **iOS**: requiere macOS/Xcode. Validado solo estáticamente (analyze + tests);
  ATS estándar (solo HTTPS) y el endpoint de Guardian es HTTPS.
- La sonda de UAT es un error sintético: sirve para aceptar el pipeline, no para
  validar la clasificación de un fallo real de negocio.
- El agente no captura *crashes nativos* (fuera de Dart): haría falta un manejador por
  plataforma (Windows WER / Android NDK).
