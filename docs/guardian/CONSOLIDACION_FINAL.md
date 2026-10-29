# Guardian UAT — consolidación final (una sola implementación)

Este documento cierra la duplicación entre el candidato UAT y la entrega de
integraciones, y deja registrado qué se adoptó, qué se descartó y por qué.

## 1. Ramas implicadas

| Rol | Rama | Commit de partida |
| --- | --- | --- |
| Candidato UAT integrado | `agent/guardian-uat-final` | `1c320765` |
| Integraciones (Equipo B) | `agent/guardian-integraciones-final` | `eedf4cd4` |
| Consolidación (esta rama) | `agent/guardian-uat-consolidada` | `1c320765` |

Ancestro común: `d3a08987`. Ninguna rama productiva se fusiona.

## 2. Implementación única de IA

`apps/api/src/guardian/ai/guardian.ai.runtime.ts` es el **único** punto que
resuelve el proveedor (`deepseek` | `openai` | `mock`), valida base URL y modelo
y degrada a `mock` ante incoherencias. Se eliminó el `describeGuardianAiRuntime`
duplicado que vivía en `guardian.config.ts` (retirado en `1c320765`) y la única
fábrica es `createGuardianAiProvider()` en `guardian.module.ts`.

Consumidores del runtime: la fábrica del módulo, `health()` de plataforma y los
dos validadores de configuración. Ninguno reimplementa la selección.

## 3. Qué se conservó de la entrega de integraciones

- Selección explícita `GUARDIAN_AI_PROVIDER=deepseek`.
- Adaptador OpenAI-compatible con base URL (`https://api.deepseek.com/v1`) y
  modelo (`deepseek-flash`) validados, `response_format: json_object` y
  `reasoning_effort: "none"`.
- Fallo seguro: sin clave, host incoherente, modelo no admitido o proveedor
  desconocido → `mock` con código estable. Nunca se reutiliza `OPENAI_API_KEY`.
- **Corrección del webhook Meta**: `entry[].id` es el WABA ID (no el Phone Number
  ID) y el filtro por número se aplica en `value.metadata.phone_number_id`. Con
  el código anterior se descartaban todos los estados reales de entrega.
- Verificación HMAC SHA-256 sobre el cuerpo crudo y fail-closed sin App Secret.
- Contrato único de la plantilla `guardian_incident_alert` de 8 parámetros.
- `guardian:first-real-test` bloqueado tras `--confirm-first-real-test`.
- Pruebas y documentación (`WHATSAPP_DEEPSEEK_ACCEPTANCE.md`,
  `WHATSAPP_TEMPLATE_GUARDIAN_INCIDENT_ALERT.md`).

## 4. Qué se conservó del candidato UAT

`guardian-ai-model-probe.ts`, `guardian-uat-config-check.ts`, los documentos
`UAT_DEPLOYMENT_PLAN.md`, `RUNBOOK_UAT_CREATE.md`, `SECRETS_INSTALLATION.md`,
`DEEPSEEK_MODEL_VERIFICATION.md` y el contrato de entrega
QUEUED/ACCEPTED/SENT/DELIVERED/READ/FAILED de `d3a08987`.

Los dos validadores tienen propósitos distintos y no duplican lógica: uno valida
el entorno del proceso (`guardian:integraciones-check`) y el otro un archivo
privado por perfil (`guardian-uat-config-check`). Ambos llaman al mismo runtime.

## 5. Suites `notifications` — causa de los 11 fallos

Los 11 fallos de `notifications.claim.pg.integration-spec.ts` y
`notifications.outbox-concurrency.spec.ts` **no eran un defecto del producto**:
eran pruebas dependientes del reloj. `processOutboxBatch()` respeta la ventana
comercial (09:00–18:00, America/Santo_Domingo, domingo cerrado); las filas de
prueba no llevaban `payload.allowOutsideBusinessHours`, así que al ejecutarse
fuera de horario el despachador las reprogramaba y el test observaba 0 envíos
(filas 500 / enviadas 0 / pendientes 500).

Corrección aplicada (solo pruebas): las filas de esas suites se siembran con
`allowOutsideBusinessHours: true`, igual que hace Guardian en producción. No se
tocó la lógica comercial, ni el claim, ni la deduplicación.

Efecto sobre Guardian: **ninguno**. El canal Evolution de Guardian encola con
`allowOutsideBusinessHours: true` (24/7) y el claim usa compare-and-swap
(`updateMany` sobre `status` + `lockedAt`) con TTL de lock, por lo que no hay
doble envío ni pérdida. La prueba `guardian.alert.channels.spec.ts` ya verifica
`acceptance: 'queued'` y la marca 24/7.

## 6. Verificación ejecutada en esta rama

```text
npm run api:build                                    -> BUILD_EXIT=0
npm --workspace apps/api test (BD aislada)            -> 984 passed, 8 skipped, 0 failed (102 suites + 1 skipped)
guardian.security.pg + guardian.integrity.pg + tenant -> 9 suites, 103 tests passed
guardian:integration (Fullpos 4010 + Appyra 3100)     -> RESULTADO INTEGRACIÓN E2E: GO
```

Bases usadas: `guardian_consolidada_final` (creada para esta verificación) y
`appyra_panel_uat_integration` para el proxy del panel. Producción no se tocó.

## 7. Perfiles privados (`%USERPROFILE%\.guardian-uat`) — solo nombres

| Perfil | Archivo | Estado | Pendiente |
| --- | --- | --- | --- |
| api | `fullpos-backend.env` | OK — `adapter=deepseek`, `deepseek-flash`, `meta_cloud`, WABA presente, plantilla 8 parámetros | `GUARDIAN_ALERT_RECIPIENTS`; `GUARDIAN_WA_TEMPLATE_NAME`/`_LANG` usan el valor por defecto del código |
| workers | `guardian-workers.env` | OK — mismo adaptador | igual que api |
| watchdog | `guardian-watchdog.env` | FALLA | falta `GUARDIAN_WATCHDOG_DATABASE_URL` (o `GUARDIAN_READER_DATABASE_URL`/`GUARDIAN_UAT_DATABASE_URL`) |
| appyra | `appyra-backend.env` | FALLA | falta `GUARDIAN_API_BASE_URL` |
| alt | `fullpos-backend.deepseek-alt.env` | Compatible | sin `GUARDIAN_AI_MODEL` (usa `deepseek-flash`) y sin destinatarios |

Observación adicional: ningún perfil declara `GUARDIAN_ENABLED`; el despliegue
debe inyectarlo o Guardian arrancará desactivado (fail-closed por diseño).

Ningún valor de estos archivos se leyó, copió ni registró.
