# WhatsApp Cloud API + DeepSeek — aceptación técnica de integraciones

Documento de entrega del **Equipo B** (integraciones externas). Cubre lo que
queda preparado y verificado en código, lo que sigue bloqueado por terceros y el
procedimiento exacto para la primera prueba real.

> Alcance deliberado: este equipo **no** toca Docker Swarm, EasyPanel, PostgreSQL
> UAT, redes, dominios, despliegue, workers como servicio ni secretos del VPS
> (responsabilidad del Equipo A). Tampoco hace push, merge ni deploy.

---

## 1. Rama y commit

- Repositorio: Fullpos monorepo, worktree aislado `C:\src\guardian-integraciones-final`
- Rama: `agent/guardian-integraciones-final`
- Base: `agent/guardian-uat-final` @ `d3a08987`
- Commit de este trabajo: `600fdd39` (feat(guardian): DeepSeek explicito y WhatsApp Cloud API endurecido).
- Sin push, sin merge a `agent/guardian-uat-final`, sin despliegue.

## 2. Archivos modificados y añadidos

Nuevos:

- `apps/api/src/guardian/ai/guardian.ai.runtime.ts` — resolución del proveedor de IA (DeepSeek/OpenAI/mock).
- `apps/api/src/guardian/ai/guardian.ai.runtime.spec.ts` — 15 pruebas de selección y validación.
- `apps/api/src/guardian/ai/deepseek-guardian-ai.provider.spec.ts` — 13 pruebas del adaptador con respuestas simuladas.
- `apps/api/src/guardian/guardian.webhook.controller.spec.ts` — 20 pruebas del webhook de Meta.
- `apps/api/src/guardian/guardian.whatsapp.template.spec.ts` — 7 pruebas del contrato de plantilla.
- `apps/api/scripts/guardian/guardian-integraciones-check.ts` — validador de configuración (sin red, sin base).
- `apps/api/scripts/guardian/guardian-first-real-test.ts` — procedimiento de primera prueba real (fail-closed).
- `docs/guardian/WHATSAPP_DEEPSEEK_ACCEPTANCE.md` (este documento).
- `docs/guardian/WHATSAPP_TEMPLATE_GUARDIAN_INCIDENT_ALERT.md` — texto exacto para WhatsApp Manager.

Modificados:

- `apps/api/src/guardian/ai/openai-guardian-ai.provider.ts` — adaptador `openai` | `deepseek`, base URL y cuerpo por proveedor.
- `apps/api/src/guardian/guardian.module.ts` — la fábrica usa el runtime efectivo y registra el adaptador (sin credenciales).
- `apps/api/src/guardian/guardian.platform.service.ts` — `health()` informa el proveedor real y sus errores de configuración.
- `apps/api/src/guardian/guardian.webhook.controller.ts` — **corrección de aislamiento**: `entry[].id` es el WABA ID, no el Phone Number ID.
- `apps/api/src/guardian/guardian.whatsapp.config.ts` — contrato único de plantilla (8 parámetros) y cuerpo exacto.
- `apps/api/package.json` — `guardian:integraciones-check`, `guardian:first-real-test`.

## 3. Compatibilidad con DeepSeek

DeepSeek expone una API **OpenAI-compatible**, así que se reutiliza el adaptador
`fetch` ya existente en lugar de añadir un SDK. Diferencias aplicadas:

| Aspecto | OpenAI | DeepSeek |
| --- | --- | --- |
| Base URL por defecto | `https://api.openai.com/v1` | `https://api.deepseek.com/v1` |
| Modelo por defecto | `gpt-4o-mini` | `deepseek-flash` |
| `response_format` | `json_object` | `json_object` (exige instrucción JSON; el prompt de sistema ya la incluye) |
| Modo razonamiento | no aplica | `reasoning_effort: "none"` (diagnóstico barato y determinista) |
| Endpoint | `POST /chat/completions` | `POST /chat/completions` |
| Error 429 | `AI_RATE_LIMITED` + `Retry-After` | idéntico |

Selección del proveedor (`resolveGuardianAiRuntime`), con `GUARDIAN_AI_PROVIDER`:

- `deepseek` → adaptador DeepSeek (exige credencial propia y modelo admitido).
- `openai` / `openai-compatible` → comportamiento previo intacto.
- `mock` → sin llamadas externas, aunque exista credencial.
- sin declarar → se infiere por el host de `GUARDIAN_AI_BASE_URL` si es de
  DeepSeek; en cualquier otro caso se mantiene OpenAI (compatibilidad previa).

Reglas fail-closed:

- Sin `GUARDIAN_AI_API_KEY` → `mock` (nunca se llama a la red).
- Host de base URL incoherente con el proveedor → `mock` (`AI_BASE_URL_MISMATCH`); la credencial no se envía a un host equivocado.
- Modelo no admitido → `mock` (`AI_MODEL_UNSUPPORTED`).
- Proveedor desconocido → `mock` (`AI_PROVIDER_UNKNOWN`).
- Nunca se reutiliza `OPENAI_API_KEY` ni credenciales de otro producto.

`GET /guardian/platform/health` informa `aiProvider`, `aiModel` y
`aiConfigurationIssues`, de modo que el panel no puede mostrar un proveedor real
que el código no está usando.

## 4. Modelo confirmado

Consultado en la documentación oficial de DeepSeek el **2026-10-26**
(`https://api-docs.deepseek.com/api/create-chat-completion` y
`https://api-docs.deepseek.com/api/list-models`):

- Modelos publicados para `POST /chat/completions`: `deepseek-flash` y `deepseek-v4-pro`.
- `max_tokens` admite 1–384 000; por defecto 8 000 sin razonamiento.
- `response_format: {"type":"json_object"}` es válido y **exige** instruir JSON en el prompt.
- `reasoning_effort: "none"` desactiva el modo razonamiento.

Valor recomendado para Guardian: `GUARDIAN_AI_MODEL=deepseek-flash`
(coste/latencia bajos y respuesta JSON; el diagnóstico no necesita razonamiento
profundo). Cualquier modelo fuera de la lista documentada degrada a `mock` a
propósito: si Meta-DeepSeek publica nuevos modelos, se añaden a
`GUARDIAN_DEEPSEEK_MODELS` con su documentación y una prueba.

## 5. Plantilla Meta de ocho parámetros

Contrato (orden exacto, vigilado por pruebas):

1. `severity` — `CRÍTICO` | `ALTO` | `MEDIO` | `BAJO`
2. `company` — empresa afectada
3. `moduleOperation` — módulo / operación
4. `occurredAtLocal` — día/mes y hora local (es-DO)
5. `problem` — síntoma redactado (sin datos de clientes)
6. `diagnosis` — hipótesis con evidencia o «Información pendiente de confirmar.»
7. `impact` — impacto operativo
8. `incidentShortId` — `INC-XXXXXX`

Nombre `guardian_incident_alert`, categoría **UTILITY**, idioma `es`.
Texto exacto y ejemplos sintéticos listos para WhatsApp Manager:
`docs/guardian/WHATSAPP_TEMPLATE_GUARDIAN_INCIDENT_ALERT.md`.

**La plantilla no está aprobada.** La aprobación la da Meta y es un bloqueo
externo.

## 6. URL del webhook real

`https://<dominio-del-backend-UAT-o-producción>/guardian/webhooks/whatsapp`

- `GET` — verificación con `hub.verify_token` (`GUARDIAN_WA_VERIFY_TOKEN`). Sin token configurado responde `403`.
- `POST` — estados, con firma `X-Hub-Signature-256` (HMAC SHA-256 del cuerpo **crudo**). Sin `GUARDIAN_WA_APP_SECRET` responde `503` (fail-closed); sin firma o con firma inválida, `401`.
- El cuerpo crudo se captura antes del parser JSON (`express.raw` en `/guardian/webhooks/whatsapp`).
- El dominio público concreto NO se fija aquí: depende del despliegue del Equipo A.

Corrección aplicada en este trabajo: el filtro de aislamiento comparaba
`entry[].id` con el **Phone Number ID**. En Meta, `entry[].id` es el **WABA ID**,
así que un despliegue real habría descartado todos los eventos de entrega. Ahora
se compara con `GUARDIAN_WA_WABA_ID` (si está configurado) y el filtro por número
se aplica en `value.metadata.phone_number_id`, que es el campo correcto.

## 7. Variables requeridas (solo nombres)

IA:

- `GUARDIAN_AI_PROVIDER` (`deepseek`), `GUARDIAN_AI_API_KEY`,
  `GUARDIAN_AI_BASE_URL`, `GUARDIAN_AI_MODEL`, `GUARDIAN_AI_TIMEOUT_MS`,
  `GUARDIAN_AI_MAX_TOKENS`, `GUARDIAN_AI_MAX_CONCURRENCY`,
  `GUARDIAN_AI_TOKENS_PER_COMPANY_DAY`

WhatsApp Cloud API:

- `GUARDIAN_WA_CLOUD_TOKEN`, `GUARDIAN_WA_PHONE_NUMBER_ID`, `GUARDIAN_WA_WABA_ID`,
  `GUARDIAN_WA_DISPLAY_NUMBER`, `GUARDIAN_WA_DISPLAY_NAME`,
  `GUARDIAN_WA_API_VERSION`, `GUARDIAN_WA_TEMPLATE_NAME`,
  `GUARDIAN_WA_TEMPLATE_LANG`, `GUARDIAN_WA_APP_SECRET`,
  `GUARDIAN_WA_VERIFY_TOKEN`, `GUARDIAN_WA_TIMEOUT_MS`

Alertas y respaldo:

- `GUARDIAN_ALERT_RECIPIENTS`, `GUARDIAN_ALERTS_ENABLED`,
  `GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL`, `GUARDIAN_ALERT_FALLBACK_SECRET`,
  `GUARDIAN_ALERT_SEV3_ENABLED`, `GUARDIAN_ALERT_SEV4_ENABLED`,
  `GUARDIAN_ALERT_GROUP_WINDOW_MINUTES`

Interruptores de Guardian y plataforma:

- `GUARDIAN_ENABLED`, `GUARDIAN_INGEST_ENABLED`, `GUARDIAN_DIAGNOSIS_ENABLED`,
  `GUARDIAN_BACKEND_CAPTURE_ENABLED`, `GUARDIAN_PLATFORM_TOKEN`,
  `GUARDIAN_READER_DATABASE_URL`

Ningún valor aparece en este documento ni en el repositorio.

## 8. Pruebas ejecutadas (todas locales, sin tráfico real)

```text
npm run api:build                         -> BUILD_EXIT=0
npx jest --testPathPatterns="guardian/ai" -> 41 passed
npx jest --testPathPatterns="guardian.webhook" -> 20 passed
npx jest --testPathPatterns="guardian.whatsapp" -> 14 passed
npm --workspace apps/api test             -> 969 passed, 11 failed (preexistentes), 8 skipped
```

Cobertura por control exigido:

| Control | Prueba |
| --- | --- |
| Selección explícita de DeepSeek | `guardian.ai.runtime.spec.ts` |
| No reutilizar claves de otros productos | `guardian.ai.runtime.spec.ts` |
| Base URL incoherente / modelo inválido → mock | `guardian.ai.runtime.spec.ts` |
| Timeout, tokens y concurrencia acotados | `guardian.ai.runtime.spec.ts` |
| Respuesta inválida / JSON envuelto / campos fuera de contrato | `deepseek-guardian-ai.provider.spec.ts` |
| 429 + `Retry-After`, 5xx, 401 sin filtrar credencial | `deepseek-guardian-ai.provider.spec.ts` |
| Prompt injection neutralizado y evidencia delimitada | `deepseek-guardian-ai.provider.spec.ts` |
| GET de verificación de Meta | `guardian.webhook.controller.spec.ts` |
| HMAC válido / inválido / ausente / cuerpo crudo | `guardian.webhook.controller.spec.ts` |
| Fail-closed sin App Secret (503) | `guardian.webhook.controller.spec.ts` |
| Aislamiento por WABA ID y Phone Number ID | `guardian.webhook.controller.spec.ts` |
| Eventos duplicados y desordenados | `guardian.webhook.controller.spec.ts` |
| Estados desconocidos no tocan la alerta | `guardian.webhook.controller.spec.ts` |
| Contrato de 8 parámetros y texto de plantilla | `guardian.whatsapp.template.spec.ts` |
| Presupuesto de IA por empresa y backoff | `guardian.diagnosis.budget.pg.integration-spec.ts`, `guardian.diagnosis.service` |
| Estados QUEUED/ACCEPTED/SENT/DELIVERED/READ/FAILED | `guardian.alert.delivery.spec.ts`, `guardian.alerts.pg.integration-spec.ts` |

Fallos **preexistentes** (no causados por este trabajo, reproducidos con los
cambios apartados en `git stash`): `src/notifications/notifications.claim.pg.integration-spec.ts`
y `src/notifications/notifications.outbox-concurrency.spec.ts` (11 pruebas). Quedan
fuera del alcance de estas integraciones y se reportan sin ocultarlos.

## 9. Bloqueos externos pendientes

1. **Plantilla `guardian_incident_alert` sin aprobar** en WhatsApp Manager.
2. **Número administrativo receptor** definitivo (`GUARDIAN_ALERT_RECIPIENTS`).
3. **Credenciales DeepSeek** en el entorno del backend (`GUARDIAN_AI_API_KEY`).
4. **Dominio HTTPS público** del webhook y su registro en Meta (Equipo A).
5. **App Secret y Verify Token** cargados en el entorno desplegado.
6. **Workers de Guardian como servicio** (Equipo A) para que el panel muestre latido.

## 10. Procedimiento de la primera prueba real

Requisitos previos: 8.1–8.4 del checklist de la sección 9 resueltos y
`guardian:integraciones-check` en `Listo para prueba real: SÍ`.

```text
# 1) Validación de configuración (sin red, sin base)
npm --workspace apps/api run guardian:integraciones-check

# 2) Primera prueba real (1 llamada DeepSeek + 1 mensaje WhatsApp)
npm --workspace apps/api run guardian:first-real-test -- --confirm-first-real-test
```

Controles que implementa el script:

- Sin `--confirm-first-real-test` **no hace nada** (fail-closed).
- Un solo mensaje por ejecución; no hay bucles ni reintentos.
- Solo envía al primer número de `GUARDIAN_ALERT_RECIPIENTS`; rechaza números ad-hoc.
- No escribe en la base de datos ni modifica empresas, ventas o caja.
- Verifica que la plantilla recibe exactamente 8 parámetros antes de enviar.
- No imprime credenciales ni el cuerpo completo de las respuestas.

Verificación posterior (manual, sin datos sensibles en el reporte):

1. Estado de la alerta en el panel APPYRA (`#/admin/guardian`).
2. Historial de intentos de la alerta: debe mostrar `acceptance=accepted`.
3. Webhook: los estados `sent` → `delivered` → `read` aparecen con su hora.
4. DeepSeek: `guardian_diagnoses.model` debe ser `deepseek-flash` y `tokens_used > 0`.
5. Ventas y caja del negocio de prueba siguen operativas (sin bloqueo).

Plan de reversa: `GUARDIAN_ALERTS_ENABLED=false` y `GUARDIAN_DIAGNOSIS_ENABLED=false`
detienen el envío sin tocar datos; el proveedor de IA vuelve a `mock` quitando
`GUARDIAN_AI_API_KEY`.

## 11. Riesgos

- **La plantilla puede ser rechazada** si Meta considera que el texto no es
  UTILITY; en ese caso se ajusta el texto y se reenvía.
- **Coste de IA**: el presupuesto diario por empresa está activo, pero un pico de
  incidentes puede consumirlo; el incidente queda `SKIPPED` con diagnóstico
  explícito, nunca con una causa inventada.
- **`deepseek-flash` es un identificador vigente hoy**; si DeepSeek lo retira, el
  runtime degrada a `mock` en lugar de fallar en silencio.
- **Webhook público**: mientras no exista dominio HTTPS registrado en Meta, los
  estados de entrega no llegarán; el panel mostrará `ACCEPTED` (evidencia real)
  y no `DELIVERED`.
- **El modo razonamiento desactivado** reduce calidad en incidentes muy
  complejos; si se necesita, `GUARDIAN_AI_PROVIDER=deepseek` +
  `GUARDIAN_AI_MODEL=deepseek-v4-pro` sigue siendo válido.
- **Sin workers desplegados** el latido no existe: el panel dirá «sin latido»,
  que es correcto, no un error de integración.

## 12. GO / NO-GO de integración

- **Integración en código**: **GO**. Contrato DeepSeek explícito y probado,
  webhook endurecido y con un fallo real corregido, plantilla y validador listos.
- **Primera prueba real**: **GO condicionado** a los seis bloqueos externos de la
  sección 9 y a autorización explícita del responsable.
- **Producción**: **NO-GO**. Este trabajo no despliega, no hace push ni merge, y
  no se ha ejecutado ninguna llamada real a WhatsApp ni a DeepSeek.
