# Guardian AI — Telemetría del backend de DaleVentas POS

Integración **opcional, asíncrona y fail-open** entre el backend de DaleVentas POS y
APPYRA Guardian AI. Fase 1 (backend). El agente Flutter queda **planificado**, no
desplegado (ver §10).

Estado: validado en UAT el 2026-10-28. Sin cambios en producción, sin mensajes de
WhatsApp y sin llamadas facturables a IA.

---

## 1. Arquitectura

```
DaleVentas POS (backend)
  └─ GlobalExceptionFilter (5xx)  ─┐
  └─ reportGuardianJobFailure()   ─┤
                                   ▼
                     GuardianCaptureRegistry.capture()
                     ├─ consumidor 1: captura local (Prisma, misma BD)   [existente]
                     └─ consumidor 2: puente HTTP remoto                  [nuevo]
                                   ▼
                     GuardianTelemetryBridge  (cola en memoria acotada)
                                   ▼  POST /guardian/machine/incidents
                     APPYRA Guardian API  (guard de credencial de máquina)
                                   ▼
                     GuardianIngestService (cuota, dedupe, redacción, evidencias)
                                   ▼
                     PostgreSQL (guardian_incidents / evidences / groups)
                                   ▼
                     Workers Guardian: diagnóstico IA (mock|deepseek) + alertas
                                   ▼
                     API de administración Guardian (panel Appyra)
```

No se creó una segunda arquitectura de monitorización: se reutiliza el registro y el
filtro global que ya existían y se añadió **un segundo consumidor** independiente
(`registerBridge`). Ninguno de los dos puede romper al otro.

## 2. Qué se reutilizó (no se duplicó)

| Pieza existente | Uso en esta fase |
| --- | --- |
| `GlobalExceptionFilter` + `GuardianCaptureRegistry` | Punto único de captura de 5xx |
| `GuardianIngestService` | Persistencia, cuotas, dedupe, evidencias, planificación de alertas |
| `GuardianIngestBatchDto` | Contrato del evento (ya cubría los campos de la Fase 3) |
| `guardian.redaction.ts` | Redacción en cliente y servidor |
| `guardian.fingerprint.ts` | Agrupación y supresión de repetidos |
| `guardian.quota.service.ts` | Cuota por empresa y dispositivo |
| `guardian.diagnosis.service.ts` + workers | Diagnóstico con IA y presupuestos |
| `guardian.platform.controller.ts` | Recuperación del diagnóstico por la API del panel |
| `guardian.secret.ts` | Credenciales por entorno o `*_FILE` (Docker Secrets) |
| Agente Flutter `lib/core/guardian/*` | Ya existente y cableado en `main.dart` |

## 3. Flujo por el que viaja un fallo

1. Una petición falla con 5xx (o una tarea de fondo falla).
2. El filtro global llama a `GuardianCaptureRegistry.capture(...)` **después** de
   escribir el log y **antes** de responder: es síncrono y no hace red.
3. El puente clasifica, redacta, deduplica, muestrea y **encola en memoria**.
4. Un temporizador (`unref`) envía el lote con `AbortController` y reintentos limitados.
5. Guardian autentica la credencial, resuelve la empresa, valida y persiste.
6. Los workers generan el diagnóstico (IA) y planifican la alerta (sin enviarla en
   la misma petición).

Ningún paso del 1 al 4 participa en una transacción de Prisma ni espera a la red.

## 4. Banderas (todas fail-closed)

Servidor POS (backend):

| Variable | Defecto | Descripción |
| --- | --- | --- |
| `GUARDIAN_TELEMETRY_ENABLED` | `false` | Interruptor maestro del puente |
| `GUARDIAN_TELEMETRY_URL` | — | URL completa del endpoint de ingesta |
| `GUARDIAN_TELEMETRY_KEY` / `_FILE` | — | Credencial de máquina (`gmk_…`) |
| `GUARDIAN_TELEMETRY_INSTALL_ID` | `pos-default` | Identificador de la instalación |
| `GUARDIAN_TELEMETRY_APP_VERSION` | — | Versión reportada |
| `GUARDIAN_TELEMETRY_TIMEOUT_MS` | `3000` | Timeout absoluto por envío (200–10000) |
| `GUARDIAN_TELEMETRY_QUEUE_CAPACITY` | `100` | Eventos en cola (descarta el más antiguo) |
| `GUARDIAN_TELEMETRY_BATCH_SIZE` | `5` | Eventos por envío (máx. 20) |
| `GUARDIAN_TELEMETRY_DEDUPE_WINDOW_MS` | `60000` | Supresión de repetidos por firma |
| `GUARDIAN_TELEMETRY_MAX_PER_MINUTE` | `30` | Caudal local (0 = sin límite) |
| `GUARDIAN_TELEMETRY_SAMPLE_RATE` | `1` | Muestreo determinista por firma (0–1) |
| `GUARDIAN_TELEMETRY_MAX_ATTEMPTS` | `2` | Intentos por lote (1–3) |
| `GUARDIAN_TELEMETRY_FLUSH_INTERVAL_MS` | `2000` | Periodicidad del envío |

Si falta la URL o la credencial, el puente **no arranca** y se registra un aviso con el
motivo (nunca el valor de la credencial).

## 5. Autenticación y aislamiento multiempresa

- Endpoint: `POST /guardian/machine/incidents` (`GuardianMachineGuard`).
- Cabeceras: `x-guardian-key` (obligatoria) y `x-guardian-ts` (opcional, ±5 min).
- La clave **nunca** se guarda en claro: solo `sha256` en
  `guardian_machine_credentials`. Se identifica la credencial por `key_prefix`.
- La empresa se resuelve **por la credencial**. El DTO no admite `companyId`: enviarlo
  devuelve `400 property companyId should not exist`.
- Estados: credencial inexistente/deshabilitada/revocada/caducada → `401`; base de datos
  inaccesible al verificar → `503` (nunca se confunde con credencial inválida).
- Límite de caudal por credencial: 120 peticiones/minuto (`MACHINE_RATE_LIMITED`).
- Auditoría: cada ingesta deja una fila en `guardian_access_logs` con `actorRole=MACHINE`.
- Revocación inmediata: `revoked_at` o `enabled=false` en la credencial.

Gestión de la credencial (UAT):

```sql
-- crear (hash calculado en el servidor, nunca la clave)
INSERT INTO guardian_machine_credentials (id, company_id, label, key_hash, key_prefix, install_id, enabled)
VALUES (gen_random_uuid(), '<companyId>', 'POS <instalación>', '<sha256 hex>', '<12 chars>', '<installId>', true);

-- revocar
UPDATE guardian_machine_credentials SET enabled = false, revoked_at = now() WHERE key_prefix = '<prefijo>';
```

## 6. Clasificación (Fase 3 y 4)

- **Nunca se genera incidente** para: `status < 500`, códigos de Prisma de negocio
  (`P2000`, `P2002`, `P2025`, …), ni mensajes de regla de negocio (stock insuficiente,
  turno cerrado, crédito excedido, duplicado…). La comprobación de infraestructura gana
  a la de negocio: una caída de base de datos no se puede camuflar como validación.
- **SEV1**: infraestructura (conexión caída, timeouts de pool, deriva de esquema
  `42P01`/`42703`, `08006`, `53300`, `57P01`).
- **SEV2**: resto de fallos técnicos 5xx.
- Módulo derivado de la ruta (`/cash`, `/products`, `/sync`, `/license`, `/dgii`…) o
  declarado por las tareas de fondo (`/jobs/<módulo>/<operación>`).
- Puntos instrumentados: excepciones no controladas (filtro global), fallos de
  infraestructura de base de datos, fallos de tareas de fondo
  (`NotificationsDispatcher`, antes silenciados), sincronización y módulos críticos
  (caja, inventario, fiscal, licencia) vía el mismo filtro.

## 7. Protección de datos sensibles

- Redacción en el cliente **y** en el servidor (`redactText`, `redactContext`).
- Se elimina: correo, JWT, `Bearer …`, rutas de Windows/POSIX, números largos,
  y credenciales embebidas (`password=…`, `clave: …`, `token=…`, `api_key=…`).
- La ruta se normaliza (`/products/<uuid>` → `/products/:id`) y se descarta la query.
- Nunca se envían: filas de base de datos, importes, datos de cliente, parámetros SQL
  ni credenciales.
- Evidencias almacenadas con `redacted = true`.

## 8. Operación (UAT)

```bash
# estado del puente en el backend POS
docker logs <contenedor-pos> 2>&1 | grep "Telemetría Guardian activa"
```

`snapshot()` del servicio expone configuración + contadores (`received`, `queued`,
`accepted`, `droppedDuplicate`, `droppedRateLimit`, `droppedQueueFull`,
`droppedAfterAttempts`, `lastError`).

Diagnóstico del incidente:

```
GET /guardian/platform/incidents/:id      (cabecera x-guardian-platform-token)
```

## 9. Pruebas

- Unitarias: clasificación (11), configuración (8), puente (12), credenciales (7),
  guard (7), redacción (8).
- Integración con PostgreSQL real: ingesta y credenciales de máquina (5).
- UAT en vivo: fallo sintético capturado, credencial inválida, inyección de empresa,
  duplicado, lote de 5, redacción, caudal, tarea de fondo y Guardian inalcanzable.

## 10. Agente Flutter — plan (no desplegado)

Estado actual auditado (`apps/fulltech_app`):

- Ya existe `lib/core/guardian/` (bootstrap, client, config, event, reporter,
  transport, store SQLite, store web, redacción) y `main.dart` lo arranca con
  `GuardianBootstrap.start()` (fail-closed por `--dart-define`).
- `FlutterError.onError` y `PlatformDispatcher.instance.onError` ya escriben en
  `AppErrorReporter`, y `GuardianReporter` se suscribe a ese stream.
- La cola del agente es una base SQLite **propia**, separada de la cola de ventas
  offline: no puede bloquear ni alterar la operación OFFLINE SAFE 48H.
- El transporte actual usa `Authorization: Bearer <JWT de sesión>` contra
  `/guardian/incidents`.

Plan propuesto (fase posterior, con autorización):

1. **Eventos previos al login** (arranque, updater de Windows, migraciones locales):
   hoy no hay token de sesión y se pierden. Usar el endpoint de máquina con una
   credencial por instalación entregada con el build (`--dart-define`) o activada
   por el administrador, nunca un JWT guardado.
2. **Actualizador**: emitir `module=updater` con código de error y versión de origen/
   destino (sin rutas de usuario).
3. **Crash nativo**: `PlatformDispatcher.onError` cubre Dart; para fallos nativos en
   Windows/Android haría falta un manejador por plataforma (documentar límite).
4. **Conectividad/offline**: reportar solo transiciones y códigos, con muestreo;
   nunca el contenido de la cola de ventas ni la duración exacta de la sesión.
5. **Rendimiento**: los eventos deben emitirse desde un `Isolate`/cola aparte y con
   presupuesto de CPU acotado; prohibido en el camino crítico del cobro.
6. **Presupuesto**: reutilizar `GuardianClient` (ya tiene muestreo SEV3/SEV4,
   límites de tamaño y tamaño de lote) y añadir cuota diaria por instalación.
7. **Pruebas**: `flutter test test/core/guardian` (ya existen 2 suites) + widget test
   de no interferencia con la cola offline.
