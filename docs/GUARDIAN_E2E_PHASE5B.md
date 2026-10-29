# GUARDIAN AI — Fase 5B: prueba E2E real controlada (resultado)

Fecha: 2026-10-28 · Entorno: UAT (`guardian-uat_*`) · Producción: no tocada.

Autorización usada: **1** petición real a DeepSeek + **1** envío WhatsApp Cloud API a
un único destinatario administrativo ya aprobado. Sin reintentos, sin escalados.

## Cadena real verificada

```
Windows UAT (piloto aislado)
  → excepción sintética (SyntheticGuardianProbeException / guardian-uat-selftest)
  → POST /guardian/machine/incidents (credencial de máquina)
  → PostgreSQL: guardian_incidents 79990044-875c-4ee1-87e0-3941de5606cf
  → DeepSeek deepseek-flash (HTTP 200, finish_reason=stop) → diagnóstico DONE
  → plantilla guardian_incident_alert (8 parámetros, param 6 = resumen real)
  → WhatsApp Cloud API (HTTP 200, accepted) → webhook → DELIVERED
```

## Datos de la ejecución

| Elemento | Valor |
| --- | --- |
| Incidente | `79990044-875c-4ee1-87e0-3941de5606cf` (flutter/Zone, Windows, SEV2) |
| Ingesta | 2026-10-28 20:31:59.957 UTC |
| Diagnóstico | `05f3462c-29d9-428f-b904-bd99e5846da2` — `DONE`, veredicto `PROBABLE`, confianza 0.72 |
| Proveedor | DeepSeek `deepseek-flash`, HTTP 200, `finish_reason=stop` |
| Contenido | 2 727 caracteres, sha256 corto `f9f3c069d734ef24` |
| Tokens | prompt 1 262 + completion 831 = **2 093** (persistidos en `tokens_used`) |
| Duración | 5 389 ms |
| `promptHash` | `3fa55d8fd26a39a95581bd4bde91d6c7e680eb73c92179c30922af1c6618b6c7` |
| Alerta | `2048f088-878b-4fed-9b10-d97d403d4490` — 1 intento, `DELIVERED` |
| Mensaje Meta | `wamid.HBgLMTgwOTM5ODc4MjYVAgARGBI3NURFMzExRDlEODc1QzI1N0QA` |
| Aceptado | 20:36:32.210 UTC (`accepted`) |
| Entregado | 20:36:36.824 UTC (webhook, 4.6 s después) |
| Leído | pendiente (`read_at` nulo) |

## Causa raíz de la Fase 5: CONFIRMADA

La respuesta buena consumió **831 tokens de salida**, muy por encima del tope
anterior de **700**. Es decir: con 700 el JSON no cabía y se cortaba
(`finish_reason=length`), lo que producía `HTTP 2xx` + contenido no parseable.
Con `max_tokens=1600` el JSON cerró y validó contra el esquema.

## Aislamiento aplicado

- Workers globales a **0 réplicas** durante la captura; el incidente y su
  hermano de updater se difirieron (`next_diagnosis_at` a 2027) antes de
  devolver los workers a 1 → **0 incidentes reclamables** en todo momento.
- Diagnóstico y alerta ejecutados como one-shot con `-e` **por proceso**; el
  servicio permaneció siempre en `GUARDIAN_AI_PROVIDER=mock` y
  `GUARDIAN_ALERTS_ENABLED=false`.
- El canal de respaldo (`http_webhook`) no se pasó al envío: sin escalado ni
  segundo intento posibles.
- Guardas verificadas: sin alertas previas, un único destinatario, `canSend=true`,
  un solo intento (`attempts=1`, 1 fila en `guardian_alert_attempts`).

## Estado final

- `guardian-uat_api` `97b63f71-alert6` healthy, `guardian-uat_workers`
  `97b63f71-alert6` running, `restarts=0`, latidos al día.
- Banderas: `GUARDIAN_AI_PROVIDER=mock`, `GUARDIAN_AI_MAX_TOKENS=1600`,
  `GUARDIAN_ALERTS_ENABLED=false`, `GUARDIAN_DIAGNOSIS_ENABLED=true`.
- Colas: 0 incidentes pendientes, 0 alertas pendientes/enviando, 0 alertas de
  escalado. Incidentes: 25 `DIAGNOSED`, 1 `FAILED`, 2 `SKIPPED`.
- Scripts one-shot eliminados del contenedor. Sin rastro de credenciales en
  logs ni en la documentación.
- Producción (`fullpos_*`, `ventas_*`, `daleventapos_pwa`) 1/1 y sin cambios;
  FULLTECH BOT y Phytoemagry conservan sus propias credenciales (0 variables y
  0 secretos `GUARDIAN_*`).
