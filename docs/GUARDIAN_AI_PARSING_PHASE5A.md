# GUARDIAN AI — Fase 5A: corrección del parseo de respuestas del proveedor

Fecha: 2026-10-28 · Entorno: UAT (`guardian-uat_*`, VPS 31.97.99.70) · Producción: no tocada.

## 1. Hecho observado (Fase 5)

El único diagnóstico real autorizado (DeepSeek, `deepseek-flash`, incidente
`207f2f98-686a-4582-99ba-cf8e5d8bb8c3`) respondió **HTTP 2xx** pero terminó en:

```
guardian_diagnoses.status = FAILED
guardian_diagnoses.error  = "el proveedor devolvió una respuesta que no es JSON utilizable"
ELAPSED_MS                = 4587
```

No se registraban `finish_reason`, tokens ni hash del contenido, así que la causa
exacta no era verificable. Ese es el defecto que corrige esta fase.

## 2. Análisis de la causa

Verificado en el código de la versión desplegada:

1. El error solo se producía **después** de `response.ok` (un fallo HTTP habría
   lanzado `IA HTTP <status>`). Es decir: la petición llegó, se aceptó y se
   facturó.
2. El fallo estaba en `extractJsonObject(raw)`, cuyo único modo de error era «no
   hay JSON parseable»: contenido vacío, texto libre o **JSON incompleto**.
3. Con `content` vacío el código tomaba `'{}'` como valor por defecto y habría
   producido un diagnóstico `INSUFFICIENT` vacío, **no** este error. Por tanto el
   contenido **no estaba vacío**.
4. El tope de salida efectivo en UAT era `GUARDIAN_AI_MAX_TOKENS=700`, mientras el
   contrato de respuesta admite `summary` 600 + `impact` 600 + `explanation` 4000
   + 8 `nextSteps` + 20 `evidenceRefs`.
5. No se aplicaba ninguna validación de esquema ni se distinguía truncamiento de
   texto libre.

**Conclusión honesta:**

- **HECHO**: la respuesta fue 2xx con contenido no vacío que no se pudo parsear.
- **HIPÓTESIS** (no confirmada, ahora medible): truncamiento por `max_tokens=700`
  (`finish_reason=length`), que deja el JSON abierto.
- **NO DESCARTADO**: texto alrededor del JSON imposible de aislar correctamente.

## 3. Corrección aplicada

`apps/api/src/guardian/ai/openai-guardian-ai.provider.ts`

- `parseGuardianJson(raw)`: parseo **estructurado** que devuelve el motivo del
  fallo (`EMPTY` / `TRUNCATED` / `NO_JSON`), tolera JSON puro, JSON con texto
  alrededor y JSON en vallas markdown.
- `looksTruncatedJson(raw)`: detecta estructura abierta (llaves/corchetes sin
  cerrar o cadena sin terminar) ignorando lo que aparece dentro de cadenas.
- `validateDiagnosisPayload(parsed)`: esquema mínimo obligatorio
  (`verdict`, `confidence`, `summary`, `explanation`) y tipos de los opcionales
  (`impact`, `causeCategory`, `nextSteps`, `evidenceRefs`). **Nunca se rellenan
  campos ausentes con contenido inventado.**
- `describeAiContent(...)`: metadatos **seguros** (`finish_reason`, longitud,
  `sha256` truncado, si empieza por JSON, si está balanceado, si va en valla,
  `max_tokens`, campos ausentes/inválidos). Nunca incluye el texto del modelo.
- `analyze()`:
  - lee `choices[0].finish_reason`;
  - contenido vacío → `AI_INVALID_RESPONSE`;
  - JSON truncado **o** `finish_reason=length` → `AI_OUTPUT_TRUNCATED`;
  - texto libre / JSON malformado cerrado → `AI_INVALID_RESPONSE`;
  - esquema incompleto → `AI_SCHEMA_INVALID` (con nombres de campos);
  - 2xx con cuerpo no JSON → `AI_INVALID_RESPONSE`.

`apps/api/src/guardian/ai/guardian-ai.provider.ts`

- Nuevos códigos `AI_OUTPUT_TRUNCATED` y `AI_SCHEMA_INVALID`.
- `GuardianAiError.retryable`: **no reintentables** `AI_NOT_CONFIGURED`,
  `AI_INVALID_RESPONSE`, `AI_OUTPUT_TRUNCATED`, `AI_SCHEMA_INVALID`.
  Transitorios (429/5xx/timeout) conservan su backoff.
- `GuardianAiResponseDiagnostic` + `diagnosticSummary` (resumen compacto, seguro).

`apps/api/src/guardian/guardian.diagnosis.service.ts`

- Un error **no reintentable** deja el incidente en `FAILED` (terminal) con
  `next_diagnosis_at` a 24 h: no se repite la llamada facturable.
- Un error transitorio mantiene el comportamiento anterior (PENDING + backoff).
- Se persisten los metadatos seguros en `guardian_diagnoses.error`
  (`… [meta finish=length chars=812 sha=abcd… json=si balanced=no …]`) y una
  traza `ai_response` en `toolCalls`.
- Presupuestos intactos: la comprobación por empresa ocurre **antes** de llamar
  al proveedor.

`apps/api/src/guardian/ai/guardian.ai.runtime.ts`

- `GUARDIAN_AI_DEFAULT_MAX_TOKENS`: 900 → **1600** (justificado en el propio
  código). Sigue siendo configurable por `GUARDIAN_AI_MAX_TOKENS` (64..8192).
- En UAT el servicio de workers pasó de `GUARDIAN_AI_MAX_TOKENS=700` a **1600**.

## 4. Pruebas

- `apps/api/src/guardian/ai/guardian.ai.parsing.spec.ts` (nuevo): parser,
  esquema, metadatos seguros y los 12 escenarios pedidos con `fetch` simulado.
- `guardian.diagnosis.pg.integration-spec.ts`: nueva prueba «un fallo no
  reintentable no se reprograma ni se vuelve a facturar».
- Resultados: ver informe de la fase (unitarias 102/102 suites, 1028 pruebas;
  IA 74/74; PostgreSQL 12/12 suites, 83 pruebas).

## 5. Neutralización de los incidentes de la Fase 5

| Incidente | Módulo | Estado final | `next_diagnosis_at` |
| --- | --- | --- | --- |
| `207f2f98-686a-4582-99ba-cf8e5d8bb8c3` | flutter/Zone (SEV2) | `FAILED` | 2027-01-01 |
| `f183204a-c327-4155-975b-54c63303cdcd` | updater (SEV3) | `SKIPPED` | 2027-01-01 |

`claimDueIncidents` solo reclama `PENDING`, así que quedan fuera de la cola de
forma permanente. No se borró ninguna evidencia: filas, payload y el
diagnóstico fallido se conservan. `guardian_alerts` no tiene filas para ellos, y
el worker solo envía alertas ya existentes (`processDue`), nunca las planifica.

## 6. Despliegue

| Artefacto | Imagen |
| --- | --- |
| API | `guardian-uat-api:97b63f71-alert6` |
| Workers | `guardian-uat-scripts:97b63f71-alert6` |

(`alert5` fue la primera compilación; `alert6` es la definitiva, reconstruida tras
un ajuste de metadatos para que el artefacto desplegado coincida exactamente con
el fuente validado.)

Respaldo previo en `/root/guardian-telemetry-20261028/backup-p5a/`
(`guardian_uat_before_ai_parsing.sql.gz`, `api-before.json`, `workers-before.json`).
Despliegue `--update-order start-first --update-failure-action rollback`;
`restarts=0`, API `healthy`. Banderas finales: `GUARDIAN_AI_PROVIDER=mock`,
`GUARDIAN_ALERTS_ENABLED=false`, `GUARDIAN_DIAGNOSIS_ENABLED=true`.

## 7. Pendiente

Una única prueba de aceptación real (1 diagnóstico DeepSeek + 1 mensaje
WhatsApp) sigue **pendiente de autorización**. Con esta corrección el fallo, si
se repite, quedará clasificado y con evidencia (`finish_reason`, longitud, hash),
en lugar de un error genérico.
