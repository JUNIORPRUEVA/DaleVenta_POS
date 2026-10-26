# Despliegue backend — candidato `700553bc` (turnos de caja)

Documento de preparación **sin ejecución**. No se despliega nada hasta autorización expresa.

- Fecha: 2026-10-26
- Candidato: rama `agent/antonio-turnos-fix`, commit **`700553bc0c8b442853e762eccaa833a0b3bbe416`**, árbol `603a07e4d6c9c984efe6df74d23ae67007adb023`
- Base: `53aa9bb1` — la misma revisión que declara la imagen desplegada
- Imagen a sustituir: `fullpos/daleventapos-backend:offline-144`
  - `Id=sha256:e2884dae0fb60634f4a467551facef9749b0202a97c8236677359447d881205b`
  - label `org.opencontainers.image.revision=53aa9bb1143168ee56697da20ff1612860e1bcfc`, `version=1.0.6-144`
- Migraciones nuevas: **ninguna** (32 carpetas, idénticas a la base)
- Variables de entorno nuevas obligatorias: **ninguna** (`CASH_SHIFT_MAX_SPAN_HOURS` y `CASH_SHIFT_CLOCK_SKEW_MINUTES` son opcionales: 24 h / 5 min por defecto, techos 72 h / 30 min)

## 0. Historial del candidato

| Commit | Estado | Contenido |
| --- | --- | --- |
| `9d531e65` | superseded | fix de turnos (229 líneas de arnés) — tenía el defecto F-3 |
| `f95b8d75` | superseded | corrige F-3 (telemetría fuera de la transacción) |
| `700553bc` | **candidato final** | cierra el riesgo R1: agregado diario atómico con el cierre |

### Defectos encontrados durante la preparación (todos corregidos)

- **F-3 (crítico)**: capturar el `P2034` de `telemetry_outbox` dentro de la transacción no lo neutraliza: PostgreSQL deja la transacción abortada y el `COMMIT` actúa como `ROLLBACK`. Se observó la API devolviendo `201` + evento `cash.session.opened` **sin fila del turno**. Corregido escribiendo el evento fuera de la transacción del negocio.
- **F-4 (riesgo R1)**: la caja diaria se actualizaba en un paso posterior al commit; una caída del proceso entre ambos dejaba el agregado desactualizado para siempre. Corregido en `700553bc` (transaccional).
- Metodológico: la primera corrida de 137 comprobaciones pasó y la intermitencia solo apareció al **repetir** el arnés de concurrencia. El arnés se repite siempre.

## 1. Comparación con la imagen desplegada

La imagen `offline-144` declara `revision=53aa9bb1…`, exactamente la base del candidato, así que el delta es solo el trabajo de esta rama:

```
13 archivos de apps/api + installer/setup.iss   (+1769 / -80)
  cash/cash-operation-window.ts       (nuevo)  ventana operativa del turno
  cash/cash.service.ts                         gateState, cierre admin, caja diaria, bloqueo
  cash/cash.controller.ts                      2 endpoints ADMIN
  cash/dto/cash.dto.ts                         occurredAt, AdminClose DTO
  sales/sales.service.ts                       ventana en ventas nuevas/offline/legacy
  sales/sales.controller.ts                    ParseUUIDPipe
  usage-telemetry/usage-telemetry.service.ts   enqueue fuera de la transacción
  (+ 5 archivos de test)
```

- No se elimina ningún endpoint, DTO, servicio, guard ni módulo.
- `package.json`, `Dockerfile`, `tsconfig` y dependencias sin cambios.
- Configuración de producción verificada (solo lectura): `FINANCIAL_LEGACY_COMPAT=true`, `CASH_CLOSE_LEGACY_COMPAT=false`, `RUN_MIGRATIONS=false`, `PRODUCTS_SOURCE=LOCAL`, `REDIS_ENABLED=false`. Compatible con el candidato; **no hay que cambiar ninguna variable**.
- Observación no bloqueante: `GIT_SHA` del servicio está desactualizado respecto a la imagen real.

## 2. Contratos HTTP y clientes antiguos (130 / 132)

Fuente: código de `69dd871b` (1.0.6+130) y `5278477e` (1.0.6+132).

| Uso | 130 | 132 | Candidato |
| --- | --- | --- | --- |
| `GET /cash/state` campos leídos | `businessDate`, `canOperate`, `activeSession.*`, `cashboxToday` | igual | los mismos + `staleBusinessDate`, `requiresClosure`, `requiresReview` (adicionales; los clientes ignoran lo desconocido) |
| Venta con `originCashSessionId` | no lo envía (ruta legacy) | sí | ambos caminos validados, con control de ventana |
| `saleOccurredAt` | se envía | se envía | base del control (nunca `now()` del servidor) |
| Cierre `POST /cash/sessions/close` | identificado | identificado | contrato sin cambios |
| `GET /cash/sales`, `/cash/movements` | campos actuales | campos actuales | sin cambios |

Cambios de comportamiento visibles para clientes antiguos (todos intencionados, verificados en el arnés C1–C7):

1. Venta en turno vencido → `409 CASH_SESSION_STALE` con mensaje legible (antes se imputaba al cierre de otro día).
2. Abrir turno con uno de otro día → `409 CASH_CLOSE_PREVIOUS_REQUIRED` con `sessionId` y `businessDate`.
3. Petición financiera parcial (`operationId` sin `sessionId`) → `409 INVALID_PARTIAL_FINANCIAL_REQUEST` (ninguna build 130/132 envía ese payload).
4. UUID malformado en rutas `:id` → `400` (antes `500`).

## 3. Esquema y migraciones

- Candidato: 32 carpetas de migración, **cero nuevas**.
- Producción (solo lectura): `_prisma_migrations` con **174 filas, 0 sin terminar**; las tres migraciones históricamente ausentes de `production-main` ya están aplicadas — `20261013180000_wholesale_price_lists`, `20261014113000_inventory_movement_operation_id`, `20261014153000_offline_operation_payload_hash`.
- Artefactos verificados en producción (4/4): `inventory_movements.operation_id`, `inventory_movements.operation_payload_hash`, `Product.create_payload_hash`, `companies.wholesale_price_lists_enabled`.
- **Despliegue sin migración**. `RUN_MIGRATIONS=false` se mantiene.

## 4. Riesgo R2 — siete negocios con turnos vencidos

Auditoría **solo SELECT** en producción (2026-10-26). Las dos últimas filas son turnos del día y no requieren acción.

| Empresa | Usuario | Abierto | Días | Fondo | Ventas | En ventana | Fuera de ventana | Efectivo fuera de ventana | Mov. netos | Caja diaria actual |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| yahaPublicidad | Yahaira rodriguez | 2026-08-11 00:15 | 76 | 0 | 1 | 1 | 0 | 0 | 0 | 0.00 |
| Solimac | Prueva123 | 2026-09-15 16:46 | 41 | 0 | 13 | 6 | **7** | **13 380** | −500 | 0.00 |
| Puerta y Ventana. Aquino | Nandy Aquino | 2026-09-20 02:54 | 36 | 100 | 13 | 1 | **12** | **66 446** | −4 000 | 100.00 |
| jc distribuidores | JOEL CASTILLO | 2026-09-24 14:13 | 32 | 500 | 1 | 1 | 0 | 0 | 0 | 500.00 |
| pureva7 | pureva7 | 2026-10-08 12:42 | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 |
| FULLTECH, SRL | Yunior Lopez | 2026-10-08 21:12 | 17 | 0 | 10 | 1 | **9** | **61 150** | 0 | 0.00 |
| Siarah Beer & Café | Juan Núñez | 2026-10-22 14:33 | 4 | 100 | 187 | 38 | **149** | **27 720** | 0 | 100.00 |
| SIJO TELA | Sammy Guerrero | 2026-10-26 13:05 | 0 | 8 000 | 2 | 2 | 0 | 0 | 0 | 8 000.00 |
| Antonio Celulares | Antonio Lauture | 2026-10-26 13:08 | 0 | 620 | 4 | 4 | 0 | 0 | 0 | 620.00 |

Lectura de la evidencia:

- **4 negocios con ventas fuera de la ventana del turno** (Solimac, Puerta y Ventana, FULLTECH, Siarah Beer): son exactamente las ventas que el defecto imputaba al cierre de un día anterior. Su `Sale.saleDate` conserva la fecha real de la operación, así que los reportes de ventas por fecha **no** están distorsionados; lo distorsionado es la atribución de caja (turno y caja diaria).
- **3 negocios sin operaciones fuera de ventana** (yahaPublicidad, jc distribuidores, pureva7): conciliación trivial, sin movimiento de efectivo pendiente salvo el fondo.
- Las cajas diarias de yahaPublicidad, Solimac y FULLTECH están a **0.00** con ventas registradas: inconsistencia heredada del código anterior. El nuevo cierre de ese turno recalcula el agregado y la corrige (auto-sanación idempotente, verificada en el arnés R1–R3).
- En los nueve casos `otros_abiertos_misma_caja = 1` (solo el propio turno), así que el cierre de cada uno no afecta a otros empleados.

### 4.1 Procedimiento de regularización (individual, sin cierres automáticos)

Reglas: **nunca** se cierra en bloque ni se inventa un importe. El `expectedAmount` lo calcula el servidor; el `closingAmount` lo aporta el negocio con su conteo físico.

1. **Antes de tocar nada**: informar al negocio y pedir (a) conteo de efectivo físico actual en caja y (b) confirmación de depósitos realizados. Nada se ejecuta sin esa confirmación.
2. **Un negocio a la vez**, empezando por el de menor riesgo financiero: `pureva7` (0) → `yahaPublicidad` → `jc distribuidores` → `FULLTECH` → `Solimac` → `Puerta y Ventana Aquino` → `Siarah Beer & Café` (el más activo, se hace en ventana de 2 minutos).
3. Un ADMIN del negocio (o soporte con su autorización expresa) consulta `GET /cash/sessions/stale` y confirma la identidad del turno.
4. `POST /cash/sessions/:id/admin-close` con `{ reason, closingAmount: <conteo físico declarado>, note }`. El servidor registra `expectedAmount`, `difference` y nota `[CIERRE ADMINISTRATIVO] …`. **La diferencia se guarda, no se maquilla.**
5. Verificar que la caja diaria de esa fecha quedó igual a la suma de sus cierres (se recalcula dentro del mismo cierre).
6. El usuario abre el turno del día y sigue vendiendo. Los demás empleados del negocio **no se ven afectados** en ningún momento (turnos independientes por usuario); solo ese usuario espera al cierre.
7. Si el negocio pide revisar la atribución histórica, se entrega el detalle de ventas fuera de ventana (mismo SQL de auditoría) como nota de conciliación. **No se reescribe historia** ni se reasignan ventas sin autorización explícita.

## 5. Seguridad de cierre, telemetría y caja diaria

- **Cierre del turno**: `updateMany` condicionado por identidad (`id + companyId + openedByUserId + status=OPEN + closedAt=null`). Solo una petición transiciona; el resto recibe `409`. Idempotente ante reintentos y replays.
- **Caja diaria (R1 cerrado)**: el cierre y el recálculo del agregado van en la **misma transacción**, con `SELECT … FOR UPDATE` sobre `cashbox_daily` tomado al inicio y en el mismo orden en todos los cierres (sin ciclos). El importe se deriva de `SUM(closingAmount)` de los turnos CLOSED de la caja; el estado pasa a CLOSED solo cuando no queda ningún turno abierto. Idempotente y auto-sanador.
- **Telemetría**: se escribe fuera de la transacción del negocio; nunca puede revertir ni abortar una operación de caja.
- **Reinicios**: no hay estado en memoria ni locks de proceso; el bloqueo es de fila y se libera al terminar la transacción. Un reinicio a mitad del cierre deja rollback limpio (verificado con `SIGKILL` real).
- **Reintentos**: `retryOnWriteConflict` reintenta solo `P2034`, hasta 5 veces, con backoff exponencial y jitter; la transacción es idempotente.

## 6. Procedimiento de despliegue controlado (solo con autorización)

1. **Respaldo**: `pg_dump` completo de `daleventa` a almacenamiento externo + verificación con `pg_restore --list`. Sin respaldo válido no se continúa.
2. **Artefacto**: construir desde `700553bc` (árbol `603a07e4…`) y publicar con etiqueta inmutable `fullpos/daleventapos-backend:cash-turnos-700553bc`; registrar el `sha256` del manifiesto de la imagen. Referencia de integridad del `dist` compilado: 227 archivos, manifiesto con `sha256 12DA1E01D4A9C000D82494C4B9FC32409248A6F450249AA2C2616448180334BF`. El daemon de Docker no está disponible en esta máquina: la imagen se construye en el host de build/CI.
3. **Preflight**: `npx prisma migrate status` contra producción (solo lectura) → "Database schema is up to date".
4. **Despliegue**: actualizar el servicio `daleventapos_backend` a la nueva etiqueta con `--update-order start-first` y `--update-parallelism 1`, sin cambiar variables de entorno.
5. **Health checks (0–5 min)**: health endpoint 200; login de cuenta interna; `GET /cash/state` 200; log sin `P2034`, sin `ExceptionsHandler` y sin avalancha de `telemetry.enqueue.skipped`.
6. **Verificación funcional (10 min)**: apertura, venta en efectivo, movimiento de caja, cierre; y apertura con turno vencido de prueba (debe responder `CASH_CLOSE_PREVIOUS_REQUIRED`).
7. **Regularización R2**: aplicar §4.1 negocio por negocio.
8. **Observación 60–120 min** con los criterios de §7.

Rollback: `docker service rollback daleventapos_backend` (vuelve a `offline-144`). Sin migraciones que deshacer: el esquema es común.

SQL de verificación de posdespliegue (solo lectura):

```sql
-- turnos abiertos de días anteriores (debe bajar a 0 tras la regularización)
SELECT company_id, count(*) FROM cash_sessions
WHERE status = 'OPEN' AND "businessDate" < to_char(now() AT TIME ZONE 'America/Santo_Domingo','YYYY-MM-DD')
GROUP BY company_id;

-- cajas diarias cuyo importe no coincide con la suma de sus cierres (últimos 7 días)
SELECT b.id, b."businessDate", b."currentAmount", coalesce(sum(s."closingAmount"),0) AS suma
FROM cashbox_daily b
LEFT JOIN cash_sessions s ON s."cashboxDailyId" = b.id AND s.status = 'CLOSED'
WHERE b."businessDate" >= current_date - 7
GROUP BY b.id, b."businessDate", b."currentAmount"
HAVING abs(coalesce(b."currentAmount",0) - coalesce(sum(s."closingAmount"),0)) > 0.01;
```

## 7. Señales de rollback inmediato

- Cualquier `5xx` nuevo en `/cash/*` o `/sales` (baseline de la auditoría: 0).
- `CASH_SESSION_STALE` en turnos del **mismo día** (falso positivo de la ventana).
- `P2034` no recuperado tras los reintentos, o p95 de apertura/cierre por encima de 2 s.
- Cierres duplicados, turnos abiertos nuevos por reintentos, o diferencia distinta de 0 en la segunda query de verificación.
- Caída de login o de realtime en más de un cliente.
- Cualquier indicio de acceso cruzado entre empresas.

## 8. Compatibilidad con operaciones offline pendientes

- La ventana operativa usa `occurredAt` del dispositivo, nunca la hora de recepción: una venta hecha dentro de la vida del turno se acepta aunque se sincronice días después, y se imputa a **su** turno (verificado: F1/F2 de la fase 4 — aceptada a las 48 h en su turno de origen).
- Una operación que ya no cabe en su turno (turno cerrado) se rechaza con `ORIGIN_SESSION_CLOSED`, no se re-imputa a un turno nuevo (F4/F5 de la fase 4 y D6–D7 de preproducción).
- Reenviar una operación vieja a un turno de hoy → `CASH_OPERATION_BEFORE_SHIFT`, sin crear filas.
- Los replays son idempotentes por `clientRequestId` (I1–I4 de fase 5).
- Riesgo declarado: una operación rechazada por turno cerrado queda en la cola del cliente hasta que el usuario la resuelva; el código de error y el mensaje son legibles por las builds 130/132.

## 9. Verificación de que las pruebas corresponden al commit final

Ejecutado **después** del commit `700553bc`, con el backend recompilado desde ese commit y la base recreada antes de cada suite:

```
run-uat.mjs                → Total 64 · OK 64 · FALLOS 0
run-preprod-checks.mjs     → Total 27 · OK 27 · FALLOS 0
run-phase5-multitenant.mjs → Total 31 · OK 31 · FALLOS 0
run-phase4-offline48.mjs   → Total 15 · OK 15 · FALLOS 0
run-phase6-daily-consistency.mjs → Total 26 · OK 26 · FALLOS 0
───────────────────────────────────────────────────────────
comprobaciones totales = 163 · fallos = 0
```

`run-phase6` incluye: 3 cierres concurrentes con agregado exacto, 3 replays sin doble contabilización, **3 muertes del proceso con `SIGKILL` a mitad del cierre** (turno queda OPEN, agregado intacto, reintento posterior converge), **muerte inmediatamente después del commit** (agregado exacto), auto-sanación de un agregado corrupto y verificación de que los cierres históricos no cambian.

Otras validaciones sobre el mismo árbol: `npm run api:build` exit 0; `npm --workspace apps/api test` → 797 passed, 8 skipped, 0 failed (78 suites). Sin cambios en Dart respecto al árbol ya validado (1394 tests Flutter + `flutter analyze` sin errores).
