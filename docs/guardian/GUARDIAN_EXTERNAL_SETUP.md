# APPYRA Guardian AI — Configuración externa requerida

Este documento lista **todo** lo que falta fuera del repositorio para que Guardian
funcione con proveedores reales. No contiene valores secretos: solo nombres de
variables, rutas y criterios de aceptación.

Estado de las integraciones tras la Fase A:

| Integración | Estado real | Bloqueo |
| --- | --- | --- |
| Ingesta de incidentes, cuotas, redacción, diagnóstico, alertas, watchdog | Implementado y probado | — |
| WhatsApp Cloud API (envío) | Implementado y probado con dobles HTTP | **BLOQUEADA EXTERNAMENTE**: faltan credenciales |
| Webhook de entrega (SENT/DELIVERED/READ/FAILED) | Implementado y probado con firma HMAC | **BLOQUEADA EXTERNAMENTE**: falta App Secret y URL pública |
| Proveedor de IA real | Implementado y probado con HTTP simulado | **BLOQUEADA EXTERNAMENTE**: falta clave API |
| Canal de respaldo del watchdog | Implementado y probado con receptor HTTP local | **BLOQUEADA EXTERNAMENTE**: falta URL real |

> Regla: ninguna integración se declara "real" hasta ejecutarse contra el proveedor.
> Todo lo anterior está verificado con dobles deterministas, no con tráfico real.

---

## 1. Dónde se leen las variables

El proyecto lee variables de entorno en este orden (resuelto desde `process.cwd()`):

1. `apps/api/.env` — **archivo principal de la API** (cuando se arranca desde `apps/api`).
2. `apps/.env` — respaldo intermedio.
3. `.env` en la raíz del repo — respaldo final.

`ConfigModule.forRoot({ envFilePath: [...] })` de `apps/api/src/app.module.ts`.

Los scripts de Guardian se ejecutan desde `apps/api` y **necesitan las variables
exportadas en el proceso**:

- `guardian:workers` y `guardian:diagnosis`: crean el contexto Nest y sí cargan `.env`.
- `guardian:watchdog`, `guardian:retention`, `guardian:scale`: **no** cargan `.env`
  automáticamente. Deben lanzarse con las variables en el entorno (tarea
  programada, servicio systemd/Task Scheduler o `docker service --env-file`).

Nunca copiar valores de `.env` a este documento, a tickets o a capturas.

---

## 2. WhatsApp oficial de APPYRA

Guardian **solo** usa credenciales propias (`GUARDIAN_WA_*`). No hereda el número
comercial ni los tokens Meta de Phytoemagry ni de ningún otro producto.

### 2.1 Requisitos en Meta

| Requisito | Dónde se obtiene | Estado |
| --- | --- | --- |
| Meta Business Portfolio de APPYRA | business.facebook.com | Pendiente |
| WhatsApp Business Account (WABA) ID | Meta Business Suite → WhatsApp Accounts | Pendiente |
| Phone Number ID | Meta for Developers → WhatsApp → API Setup | Pendiente |
| Número oficial emisor (E.164) | Alta y verificación del número | Pendiente |
| Token de acceso permanente | System User del portfolio (nunca el token temporal de prueba) | Pendiente |
| App Secret | Meta for Developers → App → Settings → Basic | Pendiente |
| Verify Token (arbitrario, secreto) | Se define al configurar el webhook | Pendiente |
| Plantilla HSM aprobada | WhatsApp Manager → Message Templates | Pendiente |
| Números administrativos receptores | Operación de APPYRA | Pendiente |

### 2.2 Variables

| Variable | Obligatoria | Descripción |
| --- | --- | --- |
| `GUARDIAN_WA_CLOUD_TOKEN` | Sí | Token de acceso del System User. Secreto. |
| `GUARDIAN_WA_PHONE_NUMBER_ID` | Sí | Phone Number ID del número oficial APPYRA. |
| `GUARDIAN_WA_WABA_ID` | Recomendada | Identificador de la WhatsApp Business Account. |
| `GUARDIAN_WA_DISPLAY_NUMBER` | Recomendada | Número visible del remitente (E.164). No es secreto. |
| `GUARDIAN_WA_DISPLAY_NAME` | Opcional | Nombre visible (`APPYRA` por defecto). |
| `GUARDIAN_WA_API_VERSION` | Opcional | Versión Graph API (`v21.0` por defecto). |
| `GUARDIAN_WA_TEMPLATE_NAME` | Sí (producción) | Plantilla de alerta administrativa (`guardian_incident_alert` por defecto). |
| `GUARDIAN_WA_TEMPLATE_LANG` | Opcional | Idioma de la plantilla (`es` por defecto; admite `es_DO`). |
| `GUARDIAN_WA_WATCHDOG_TEMPLATE_NAME` | Opcional | Plantilla del watchdog (`guardian_watchdog_alert` por defecto). |
| `GUARDIAN_WA_APP_SECRET` | Sí (webhook) | App Secret para validar `X-Hub-Signature-256`. |
| `GUARDIAN_WA_VERIFY_TOKEN` | Sí (webhook) | Token de verificación `hub.verify_token`. |
| `GUARDIAN_ALERT_RECIPIENTS` | Sí | Lista de números administrativos separada por comas o punto y coma. |
| `GUARDIAN_ALERT_RECIPIENT` | Compatibilidad | Un único destinatario (legado). |
| `GUARDIAN_ALERTS_ENABLED` | Sí | Interruptor general de alertas (`true`). |
| `GUARDIAN_ALERTS_EVOLUTION_ENABLED` | Opcional | Habilita el canal de respaldo por `notification_outbox`. Por defecto `false`. |
| `GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL` | Recomendada | Canal secundario independiente (HTTPS). |
| `GUARDIAN_ALERT_FALLBACK_SECRET` | Recomendada | Secreto enviado en `x-guardian-secret`. |
| `GUARDIAN_ALERT_SEV3_ENABLED` | Opcional | `false` silencia SEV3 (por defecto `true`). |
| `GUARDIAN_ALERT_SEV4_ENABLED` | Opcional | `true` incluye SEV4 (por defecto solo se registra). |
| `GUARDIAN_ALERT_GROUP_WINDOW_MINUTES` | Opcional | Ventana de agrupación (30 por defecto). |

### 2.3 Plantilla HSM esperada

`guardian_incident_alert`, categoría UTILITY, idioma `es`/`es_DO`, **8 parámetros
de cuerpo en este orden**:

1. Nivel (`CRÍTICO`, `ALTO`, `MEDIO`, `BAJO`)
2. Empresa
3. Módulo / operación
4. Hora local (`es-DO`)
5. Problema
6. Diagnóstico (o "Información pendiente de confirmar.")
7. Impacto
8. ID corto del incidente (`INC-XXXXXX`)

El envío usa plantilla cuando existe nombre configurado; sin plantilla cae a texto
libre (solo válido dentro de la ventana de 24 h). Las alertas administrativas son
iniciadas por el negocio: la plantilla es la vía correcta fuera de la ventana.

### 2.4 Webhook público

- URL: `https://<backend-apto-para-produccion>/guardian/webhooks/whatsapp`
- Debe ser HTTPS público y aceptar `GET` (verificación) y `POST` (estados).
- Suscripción mínima: campo `messages`.
- La API valida la firma sobre el cuerpo crudo; un `POST` sin `GUARDIAN_WA_APP_SECRET`
  responde `503` (fail-closed).
- Solo se procesan eventos del `phone_number_id` propio; el resto se ignora sin
  alterar alertas.

### 2.5 Política 24/7

Las alertas internas de Guardian se envían a cualquier hora (madrugada, domingo,
feriado). El canal Evolution, si se habilita, encola con
`allowOutsideBusinessHours: true`. Las notificaciones comerciales normales
(`notification_outbox` sin esa marca) conservan su horario actual: no se tocaron.

---

## 3. Proveedor de IA

| Variable | Obligatoria | Descripción |
| --- | --- | --- |
| `GUARDIAN_AI_API_KEY` | Sí | Clave **exclusiva de Guardian**. No se reutiliza `OPENAI_API_KEY` de otros productos. |
| `GUARDIAN_AI_BASE_URL` | Opcional | Endpoint compatible con OpenAI Chat Completions (`https://api.openai.com/v1` por defecto). |
| `GUARDIAN_AI_MODEL` | Opcional | Modelo (`gpt-4o-mini` por defecto). |
| `GUARDIAN_AI_TIMEOUT_MS` | Opcional | Tiempo límite por llamada (20000 ms). |
| `GUARDIAN_AI_MAX_TOKENS` | Opcional | Tokens máximos de salida (900). |
| `GUARDIAN_AI_MAX_CONCURRENCY` | Opcional | Llamadas simultáneas al proveedor (2). |
| `GUARDIAN_AI_TOKENS_PER_COMPANY_DAY` | Opcional | Presupuesto diario por empresa (`200000`; `0` = sin límite). |
| `GUARDIAN_DIAGNOSIS_ENABLED` | Sí | Interruptor del worker de diagnóstico. |
| `GUARDIAN_DIAGNOSIS_MAX_ATTEMPTS` | Opcional | Reintentos antes de `FAILED` (4). |
| `GUARDIAN_CODE_ROOT` | Opcional | Raíz de búsqueda de código para la herramienta de lectura. |

Sin `GUARDIAN_AI_API_KEY` el sistema usa el proveedor determinista `mock`, que
**no inventa causas**: devuelve `INSUFFICIENT` sin evidencia. Un presupuesto
agotado deja el incidente en `SKIPPED` con diagnóstico `INSUFFICIENT` explicando
el motivo y sin llamar al proveedor.

---

## 4. Operación

| Variable | Obligatoria | Descripción |
| --- | --- | --- |
| `GUARDIAN_ENABLED` | Sí | Interruptor maestro (fail-closed: `false` por defecto). |
| `GUARDIAN_INGEST_ENABLED` | Sí | Recepción de incidentes del POS. |
| `GUARDIAN_PLATFORM_TOKEN` | Sí (panel) | Token del panel Appyra (`x-guardian-platform-token`). |
| `GUARDIAN_READER_DATABASE_URL` | Recomendada | Conexión del rol `guardian_reader` (solo `SELECT`). Sin ella, las consultas usan el usuario principal. |
| `GUARDIAN_WATCHDOG_DATABASE_URL` | Sí (watchdog) | Conexión del watchdog independiente. |
| `GUARDIAN_WATCHDOG_WEBHOOK_URL` | Sí (watchdog) | Canal de aviso independiente de Guardian. |
| `GUARDIAN_WATCHDOG_WEBHOOK_TOKEN` | Recomendada | `Authorization: Bearer` del canal. |
| `GUARDIAN_WATCHDOG_STATE_PATH` | Opcional | Archivo de estado para deduplicar y detectar recuperación. |
| `GUARDIAN_WATCHDOG_STUCK_MINUTES` | Opcional | Umbral de cola atascada (30). |
| `GUARDIAN_WATCHDOG_HEARTBEAT_MINUTES` | Opcional | Umbral de latido (10). |
| `GUARDIAN_WATCHDOG_REALERT_MINUTES` | Opcional | Reaviso si persiste (60). |
| `GUARDIAN_WORKER_INTERVAL_SECONDS` | Opcional | Ciclo de los workers (5). |

### 4.1 Comandos

```text
npm --workspace apps/api run guardian:workers      # diagnóstico + alertas (proceso aparte)
npm --workspace apps/api run guardian:watchdog     # cron cada 5-10 min, fuera del API
npm --workspace apps/api run guardian:retention    # cron diario de retención
npm --workspace apps/api run guardian:scale        # prueba de carga local
```

### 4.2 Rol PostgreSQL de solo lectura

Crear un rol con permisos mínimos y usarlo en `GUARDIAN_READER_DATABASE_URL`:

```sql
CREATE ROLE guardian_reader LOGIN PASSWORD '<definir-en-gestor-de-secretos>';
GRANT CONNECT ON DATABASE <base> TO guardian_reader;
GRANT USAGE ON SCHEMA public TO guardian_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO guardian_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO guardian_reader;
```

Verificación: `guardian_reader` debe poder hacer `SELECT` y fallar en `INSERT`,
`UPDATE`, `DELETE` y `CREATE`.

---

## 5. Rotación de secretos

Procedimiento detallado en `docs/guardian/SECRET_ROTATION.md`. Resumen:

1. Emitir el secreto nuevo en el proveedor.
2. Cargarlo en el gestor de secretos del entorno.
3. Reiniciar workers y API de forma escalonada.
4. Verificar un envío/consulta con el secreto nuevo.
5. Revocar el anterior.
6. Registrar fecha y responsable (sin incluir el valor).

Nunca se imprimen claves ni cadenas de conexión completas en logs o reportes.

---

## 6. Criterio de cierre de cada bloqueo

- **WhatsApp**: un envío real a un número de prueba recibe `messages[0].id` y el
  webhook registra `sent → delivered → read` en `guardian_alerts`.
- **IA**: una llamada real devuelve JSON válido, se guarda `prompt_hash` y el
  veredicto respeta `CONFIRMED`/`PROBABLE`/`INSUFFICIENT`.
- **Watchdog**: una caída controlada en UAT genera aviso y recuperación en el canal
  independiente, sin duplicados.
