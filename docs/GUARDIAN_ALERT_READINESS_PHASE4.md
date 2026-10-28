# Guardian AI — Fase 4: despacho de alertas consciente del diagnóstico

Implementado y validado el 2026-10-28 en `agent/guardian-telemetry-phase1`.
IA en modo `mock`, alertas desactivadas en el entorno desplegado, sin llamadas
facturables y sin envíos reales de WhatsApp.

---

## 1. Auditoría de las máquinas de estado (previo al cambio)

| Pieza | Estado encontrado |
| --- | --- |
| `guardian_alerts.state` | `PENDING → SENDING → QUEUED/ACCEPTED/SENT → DELIVERED/READ`, fallos `FAILED_PERMANENT`/`DEAD` |
| `guardian_diagnoses.status` | `PENDING → RUNNING → DONE` / `FAILED` |
| Planificación | `planForIncident` se llamaba **en la ingesta**, antes de que existiera diagnóstico |
| Selección | `claimDue`: `state IN (PENDING,SENDING) AND nextAttemptAt<=now` + compare-and-swap con `lockedAt`/`lockedBy` (TTL) |
| Parámetros de plantilla | Se construían **al enviar**, leyendo `diagnoses` con `status='DONE'` |
| Orden del worker | Alertas antes que diagnósticos |

Conclusión: el contrato de la plantilla ya permitía el diagnóstico; el problema era
**de secuencia**, no de formato.

## 2. Cambios implementados

### 2.1 Regla de readiness (módulo puro)

`src/guardian/guardian.alert.readiness.ts`

| Severidad | Comportamiento |
| --- | --- |
| **SEV1** | Envío inmediato, sin esperar a la IA (`SEV1_IMMEDIATE`) |
| **SEV2 / SEV3** | Espera al diagnóstico hasta `GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS` (defecto **90 s**) |
| — con diagnóstico `DONE` | Envío inmediato (`DIAGNOSIS_DONE`) |
| — al vencer el plazo | Envío con texto de respaldo (`DEADLINE_REACHED`) aunque el diagnóstico esté `FAILED`, `RUNNING` o no exista |
| **SEV4** | Sin alerta (solo registro), igual que antes |

`wait=0` desactiva la espera y restaura el comportamiento anterior.

### 2.2 Filtro en base de datos (no en memoria)

`guardian.alert.service.ts → claimDue()` añade a la consulta:

```
AND ( incidente.severity = SEV1
      OR existe diagnóstico con status = DONE
      OR incidente.receivedAt <= now - wait )
```

Ventajas: el despacho es correcto con varios workers, tras reinicios y sin estado en
memoria. Las alertas no listas **no se reclaman**, así que no consumen el lote.

### 2.3 Idempotencia reforzada

- `planForIncident` captura `P2002` (carrera de dos workers creando la alerta
  inicial) y devuelve `ALREADY_QUEUED`: **exactamente una** alerta inicial por
  incidente, garantizado por el índice único de `dedupeKey`.
- `attempt()` no reenvía si la alerta ya tiene `providerMessageId`.

### 2.4 Observabilidad

`processDue()` devuelve ahora `deferred` (alertas vencidas que esperan diagnóstico) y
el worker registra:

```
alertas procesadas=N enviadas=N fallidas=N esperando-diagnostico=N
```

### 2.5 Interacción con el ciclo del worker

`guardian-workers` corre cada **60 s** y procesa alertas antes que diagnósticos. Con
una espera de 90 s, un incidente SEV2/SEV3 se diagnostica en el primer ciclo y su
alerta sale en el siguiente (~60 s) ya con el diagnóstico. SEV1 sale en el primer
ciclo. No se modificó el orden del worker (necesario para no retrasar SEV1).

## 3. Pruebas (16 nuevas, todas en verde)

Regla pura (`guardian.alert.readiness.spec.ts`, 7 casos) y PostgreSQL real + canal
HTTP simulado (`guardian.alert.readiness.pg.integration-spec.ts`, 9 casos):

| Caso | Resultado |
| --- | --- |
| SEV1 sin diagnóstico → envío inmediato | ✅ `Nivel: CRÍTICO`, texto de respaldo |
| SEV2/SEV3 sin diagnóstico ni plazo → **deferida** (`processed=0`, `deferred=1`) | ✅ alerta sigue `PENDING` |
| Diagnóstico `DONE` → envío con **posición 6 = resumen real** | ✅ `Diagnóstico: La suma de movimientos…`, sin texto de respaldo |
| Plazo vencido sin diagnóstico → envío con respaldo | ✅ |
| Dos `processDue` concurrentes → 1 solo envío | ✅ 1 alerta con `providerMessageId`, 1 mensaje recibido |
| Reinicio tras envío → no reenvía | ✅ `sent=0` |
| `planForIncident` concurrente ×2 → 1 sola alerta | ✅ |
| `wait=0` → comportamiento inmediato | ✅ |
| **Fin a fin con IA mock**: incidente → `runBatch` (mock) → `DONE` → alerta con ese resumen → segundo ciclo sin duplicar | ✅ |

Evidencia del mensaje real enviado al canal (extracto del receptor simulado):

```
Nivel: CRÍTICO
Módulo: cash / POST /api/v1/cash/close
Problema:
Se detectó una posible inconsistencia en operaciones asociadas a turnos.
Diagnóstico:
La suma de movimientos no coincide con el saldo de apertura del turno.
Impacto:
El turno queda abierto y no se puede facturar
ID: INC-…
```

## 4. Suite completa

```
npm run api:build                               → OK
npm --workspace apps/api test                   → 112 suites / 1073 PASS / 12 skipped / 0 FAIL
  guardian.alert.readiness.spec.ts              → 7 PASS
  guardian.alert.readiness.pg.integration-spec  → 9 PASS
```

## 5. Despliegue UAT

```
backup:    /root/guardian-telemetry-20261028/backup-p4/guardian_uat_before_alert_readiness.sql.gz (63 KB)
spec prev: backup-p4/workers-before.json
imagen:    guardian-uat-scripts:97b63f71-alert4   (build --target builder)
servicio:  guardian-uat_workers  → update-order start-first, update-failure-action rollback
estado:    1/1 Running, restarts=0, "Workers Guardian iniciados (intervalo 60000 ms)"
flags:     GUARDIAN_AI_PROVIDER=mock · GUARDIAN_ALERTS_ENABLED=false · GUARDIAN_DIAGNOSIS_ENABLED=true
BD UAT:    2 alertas / 2 intentos (sin cambios) · 24 incidentes · 24 diagnósticos
```

`guardian-uat_api` **no** se actualizó: el cambio de readiness solo afecta a
`processDue`, que ejecutan los workers. La protección `P2002` de `planForIncident`
queda en el código y llegará con el próximo despliegue de la API.

## 6. Límites de "exactamente una vez"

- **Lado Guardian**: la alerta inicial es única por incidente (índice único) y el
  envío es *at-least-once*: si el worker muere entre el claim y la respuesta del
  proveedor, el TTL del lock permite un reintento. `providerMessageId` evita
  reenvíos posteriores, pero un mensaje ya aceptado por el proveedor puede
  haberse entregado.
- **Lado proveedor**: WhatsApp Cloud API no ofrece idempotencia por clave propia;
  el `dedupeKey` es nuestro, no del proveedor. Por eso el sistema puede garantizar
  "como máximo un envío por intento del worker", no "exactamente uno" ante una
  caída justo después de la aceptación.
- **IA**: el presupuesto, el claim con compare-and-swap y `GUARDIAN_DIAGNOSIS_MAX_ATTEMPTS`
  impiden duplicar llamadas; la espera de la alerta no provoca diagnósticos extra.

## 7. Configuración nueva

| Variable | Defecto | Rango | Efecto |
| --- | --- | --- | --- |
| `GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS` | `90` | 0–900 | Espera máxima del diagnóstico para SEV2/SEV3. `0` = sin espera. SEV1 nunca espera |
