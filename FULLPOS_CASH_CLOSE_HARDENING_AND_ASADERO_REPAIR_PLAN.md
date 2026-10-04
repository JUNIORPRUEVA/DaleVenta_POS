# Plan de reparación READ-ONLY — cierre contaminado (Asadero Pacheco)

> **NO EJECUTAR.** Este documento es un plan. Requiere autorización explícita del owner
> y una ventana controlada. Ninguna sentencia de este documento se ha ejecutado.
> Generado tras blindar el flujo de cierre (`CASH-CLOSE-HARDENING`).

## 0. Contexto verificado (HECHO)

- Sesión afectada: `0e65c159` (prefijo del `cash_sessions.id`).
- Sesión que originó el monto: `d6a8181c` (turno anterior; su `closingAmount` real era `33735.60`).
- Datos contaminados en `0e65c159`: `closingAmount = 33735.60`, `difference = 30003.80`.
- `expectedAmount = 3731.80` de la sesión afectada es correcto (8 tickets).
- `cashbox_daily.currentAmount` del `businessDate` del turno también quedó contaminado
  (`currentAmount` se fija al `closingAmount` al cerrar la caja del día).

## 1. Qué columnas están contaminadas

| Tabla | Columna | Valor actual (incorrecto) | Comentario |
| --- | --- | --- | --- |
| `cash_sessions` | `"closingAmount"` | `33735.60` | monto del turno anterior |
| `cash_sessions` | `"difference"` | `30003.80` | `closingAmount - expectedAmount` |
| `cash_sessions` | `"expectedAmount"` | `3731.80` | **correcto**, no tocar |
| `cashbox_daily` | `"currentAmount"` | `33735.60` | se iguala al cierre al cerrar la caja |

**No contaminadas** (verificar en pre-check): ventas (`sales`), movimientos
(`cash_movements`), abonos (`sale_credit_payments`), NCF/fiscal. El replay sólo
ejecutó el cierre, no creó ventas ni movimientos.

## 2. Decisión que requiere al owner (no se puede deducir de la data)

El efectivo **realmente contado** en el turno `0e65c159` **no es reconstruible**: el
valor guardado pertenece a otra sesión. Opciones (elegir una, no aplicar en silencio):

- **(A) Dejar el conteo como desconocido:** `"closingAmount" = NULL`, `"difference" = NULL`.
  Semánticamente correcto (nunca se contó de verdad), pero los reportes deben tolerar NULL.
- **(B) Asumir cuadre:** `"closingAmount" = "expectedAmount"` (3731.80), `"difference" = 0`.
  Sólo válido si el negocio confirma que no hubo sobrante/faltante.
- **(C) Monto real provisto por el negocio:** usar el conteo físico real de ese turno
  (si existe en papel/ticket) → `"closingAmount" = <real>`, `"difference" = <real> - 3731.80`.

`cashbox_daily."currentAmount"` debe quedar con el **mismo criterio** que (A/B/C).

## 3. Relaciones/reportes que dependen de estas columnas

- Reportes de cierres: `cash.service.ts` `closedSessions()`, `sessionDetail()`, historial de
  caja (`cash_management_screens.dart`), impresión de reimpresión (`printHistoryTicket`).
- Corte/cierre diario: `features/contabilidad/cierres_diarios_screen.dart` y
  `features/cash/data/daily_cash_close_ticket_printer.dart` (usan `closingAmount`/`difference`).
- `cashbox_daily."currentAmount"` alimenta el estado de la caja del día.
- `usage_telemetry` (evento `CASH_SESSION_CLOSED`) guarda `entityId`, no montos; revisar
  si algún tablero externo agregó el `difference`.

Snapshots adicionales: **verificar** si existe `audit_log`/`usage_telemetry` con el payload
del cierre (pre-check incluido). No se asume su existencia.

## 4. SELECT pre-check (sólo lectura)

```sql
-- 4.1 Localizar las dos sesiones (sufijo conocido).
SELECT id, company_id, openedByUserId, cashboxDailyId, "userName",
       "businessDate", status, "openedAt", "closedAt",
       "initialAmount", "expectedAmount", "closingAmount", "difference", note
FROM cash_sessions
WHERE id::text LIKE '0e65c159%' OR id::text LIKE 'd6a8181c%';

-- 4.2 Confirmar que la sesión afectada tiene 8 tickets y expected 3731.80.
SELECT s.id, count(sa.id) AS tickets, sum(sa."totalSold") AS totalVendido
FROM cash_sessions s
LEFT JOIN sales sa ON sa."cashSessionId" = s.id
WHERE s.id::text LIKE '0e65c159%'
GROUP BY s.id;

-- 4.3 Movimientos de la sesión (deberían ser pocos/ninguno "raro").
SELECT * FROM cash_movements
WHERE "sessionId" IN (SELECT id FROM cash_sessions WHERE id::text LIKE '0e65c159%');

-- 4.4 Caja diaria afectada.
SELECT * FROM cashbox_daily
WHERE id IN (SELECT "cashboxDailyId" FROM cash_sessions WHERE id::text LIKE '0e65c159%');

-- 4.5 ¿Hay más sesiones del mismo cliente con el mismo patrón?
--     closingAmount == closing de la sesión anterior y difference <> 0.
SELECT id, "businessDate", "expectedAmount", "closingAmount", "difference", "closedAt"
FROM cash_sessions
WHERE company_id = (SELECT company_id FROM cash_sessions WHERE id::text LIKE '0e65c159%')
ORDER BY "closedAt" DESC NULLS LAST
LIMIT 50;
```

## 5. Backup / checkpoint recomendado

```sql
-- 5.1 Snapshot de las dos filas afectadas (rollback localizado).
CREATE TABLE _bak_cash_sessions_0e65c159 AS
SELECT * FROM cash_sessions WHERE id::text LIKE '0e65c159%' OR id::text LIKE 'd6a8181c%';

CREATE TABLE _bak_cashbox_0e65c159 AS
SELECT * FROM cashbox_daily
WHERE id IN (SELECT "cashboxDailyId" FROM cash_sessions WHERE id::text LIKE '0e65c159%');

-- 5.2 (Recomendado por el owner/DB owner) pg_dump de las tablas:
--   pg_dump -t cash_sessions -t cashbox_daily <db> > cierre_before_fix.sql
```

## 6. UPDATE propuesto (NO EJECUTAR — depende de la decisión §2)

```sql
BEGIN;

-- Opción (A) conteo desconocido:
UPDATE cash_sessions
SET "closingAmount" = NULL,
    "difference"    = NULL
WHERE id::text LIKE '0e65c159%';

-- Opción (B) asumir cuadre:
-- UPDATE cash_sessions
-- SET "closingAmount" = "expectedAmount",
--     "difference"    = 0
-- WHERE id::text LIKE '0e65c159%';

-- Caja diaria: mismo criterio que la opción elegida.
UPDATE cashbox_daily
SET "currentAmount" = (SELECT "closingAmount" FROM cash_sessions WHERE id::text LIKE '0e65c159%')
WHERE id IN (SELECT "cashboxDailyId" FROM cash_sessions WHERE id::text LIKE '0e65c159%');

COMMIT;
```

## 7. SELECT post-check

```sql
SELECT id, "expectedAmount", "closingAmount", "difference"
FROM cash_sessions WHERE id::text LIKE '0e65c159%';

SELECT id, "currentAmount", status
FROM cashbox_daily
WHERE id IN (SELECT "cashboxDailyId" FROM cash_sessions WHERE id::text LIKE '0e65c159%');

-- Las ventas históricas NO deben cambiar:
SELECT count(*) FROM sales WHERE "cashSessionId" IN
  (SELECT id FROM cash_sessions WHERE id::text LIKE '0e65c159%');
```

## 8. Rollback SQL

```sql
BEGIN;
UPDATE cash_sessions target
SET "closingAmount" = bak."closingAmount",
    "expectedAmount" = bak."expectedAmount",
    "difference"    = bak."difference"
FROM _bak_cash_sessions_0e65c159 bak
WHERE target.id = bak.id;

UPDATE cashbox_daily target
SET "currentAmount" = bak."currentAmount"
FROM _bak_cashbox_0e65c159 bak
WHERE target.id = bak.id;
COMMIT;

-- Limpieza posterior (cuando se confirme la corrección):
-- DROP TABLE _bak_cash_sessions_0e65c159;
-- DROP TABLE _bak_cashbox_0e65c159;
```

## 9. Riesgos de la reparación

- Si (B) es incorrecto y hubo un sobrante/faltante real, se oculta una discrepancia de caja.
- Corregir `closingAmount` **no** repara ventas (están intactas) ni NCF.
- Verificar el `company_id` correcto antes de cualquier UPDATE (aislamiento multiempresa).
- Ejecutar sólo con autorización explícita y backup (§5) validado.

---

# Anexo — Orden de despliegue y transición (FASE 6)

**Restricción verificada (HECHO):** el `ValidationPipe` del API usa
`whitelist: true` + `forbidNonWhitelisted: true`. Por tanto, un backend ANTIGUO
rechaza con **400** los campos nuevos (`sessionId`, `clientSessionId`).

**Consecuencia (orden obligatorio):**

1. **Desplegar primero el BACKEND** (acepta `sessionId`/`clientSessionId`).
2. **Desplegar después la APP** (envía `sessionId` siempre + `clientSessionId` al abrir).

| Combinación | Open | Close | Resultado |
| --- | --- | --- | --- |
| Backend viejo + App nueva | 400 (`clientSessionId`) | 400 (`sessionId`) | ❌ ROMPE — no desplegar así |
| Backend nuevo + App vieja | OK (ignora el campo ausente) | 409 `CASH_CLOSE_SESSION_ID_REQUIRED` | ⚠️ la app vieja no puede cerrar hasta actualizar |
| Backend nuevo + App nueva | OK | OK | ✅ objetivo |

**Ventana de transición (opcional, decisión del owner):** mientras los clientes
antiguos se actualizan, se puede activar temporalmente
`CASH_CLOSE_LEGACY_MODE=current_open`. Eso restaura el comportamiento antiguo y
**reabre el riesgo de replay** para las apps viejas → usarlo sólo el tiempo mínimo
necesario y con actualización forzada de las apps. Con el valor por defecto
(`reject`) la integridad está garantizada pero las apps viejas deben actualizarse
para poder cerrar turnos.

**Cola offline ya existente en los dispositivos:** los items `cash.close` /
`cash.movement` creados por versiones antiguas NO llevan `sessionId`; la nueva app
los descarta como `obsolete` (no se ejecutan). Nunca cierran un turno posterior.

